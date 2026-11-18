import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'hls_prefetch.dart';
import 'playback_buffer_guard.dart';

/// Platform-independent short video widget. video_player uses ExoPlayer on
/// Android, AVPlayer on iOS, and the browser video element on Web.
class WatchShortVideoItem extends StatefulWidget {
  final dynamic videoInfo;
  final bool autoPlay;
  final bool resolvePlayableUrl;
  final bool lockedPreviewMode;
  final VoidCallback? onLockedWatchNowTap;
  final VoidCallback? onWatchAdToUnlock;

  /// 【自动降档】当前集持续卡顿（带宽撑不住当前码率）时由 item 回调，
  /// 页面负责把全局清晰度降一档（1080P→720P→480P）。
  final VoidCallback? onAutoQualityDown;

  /// 【自动升档】当前集连续 20s 几乎零缓冲（带宽有余量）时由 item 回调，
  /// 仅在用户选了 AUTO 档时由页面生效（480P→720P→1080P）。
  final VoidCallback? onAutoQualityUp;
  final Widget Function(BuildContext, dynamic)? overlayBuilder;
  final Widget Function(BuildContext, dynamic)? topOverlayBuilder;
  final bool showDebugInfo;
  final VoidCallback? onCompleted;
  final String quality;

  const WatchShortVideoItem({
    super.key,
    required this.videoInfo,
    this.autoPlay = false,
    this.resolvePlayableUrl = true,
    this.lockedPreviewMode = false,
    this.onLockedWatchNowTap,
    this.onWatchAdToUnlock,
    this.onAutoQualityDown,
    this.onAutoQualityUp,
    this.overlayBuilder,
    this.topOverlayBuilder,
    this.showDebugInfo = false,
    this.onCompleted,
    this.quality = '480P',
  });

  @override
  WatchShortVideoItemState createState() => WatchShortVideoItemState();
}

class WatchShortVideoItemState extends State<WatchShortVideoItem> {
  /// 预热（静音试播）的最长耗时。
  ///
  /// 原来 20s：为了攒 20 秒缓冲，一支 4.4Mbps 的流要下 ~11MB；
  /// 现在 6s：只要拿到「能立刻起播」的量就收工，剩下的边播边下。
  static const Duration _prefetchWarmupMaxDuration = Duration(seconds: 6);

  /// 预热目标缓冲量。
  ///
  /// 【为什么从 20s 降到 3.5s】抖音式切集只需要"第一帧能立刻出、声音不断"，
  /// 3.5 秒缓冲（≈2MB）已足够覆盖 initialize→play 的握手耗时。
  /// 预取 20 秒会把带宽吃得精光，导致"再下一集"完全没机会预热 ——
  /// 用户连续快滑时第 3 集起必然冷启动。宁可少预取、快完成。
  static const Duration _prefetchWarmupTarget = Duration(
    milliseconds: 3500,
  );

  /// 当前集剩余不足该时长时，允许提前预热下一集。
  static const Duration _prefetchNearEndWindow = Duration(seconds: 12);
  VideoPlayerController? _controller;
  Future<void>? _initializationFuture;
  int _generation = 0;

  /// 【清晰度热切换】同集内切 480P/720P/1080P 时重建播放器会丢进度，
  /// 先记下旧位置，新控制器起播后 seek 回来。
  Duration? _resumePosition;

  /// 【自动降档】滑动窗口内缓冲占比超阈值时，通知页面把清晰度降一档。
  ///
  /// 【为什么必须有】1080p 那一路均值 7.5Mbps，跨境带宽波动大（实测
  /// 高峰期只有 ~1Mbps），固定码率 HLS 播放器不会自己降档，表现就是
  /// 播 2 秒卡 8 秒死循环。抖音式体验 = 流畅优先，所以带宽撑不住时
  /// 自动降档（1080P→720P→480P），用户想回高清手动再选。
  static const Duration _stallWindow = Duration(seconds: 30);
  static const double _stallDowngradeRatio = 0.4;
  DateTime? _stallWindowStart;
  Duration _stallAccumulated = Duration.zero;
  DateTime? _lastAutoDowngradeAt;
  bool _loading = false;
  bool _completed = false;
  bool _playbackRequested = false;

  /// 用户手动点了暂停。
  ///
  /// 【为什么必须单独记】播放页的父级每次 rebuild（点赞/收藏状态变化、
  /// 解锁弹窗、清晰度弹窗关闭后的 setState…）都会走到 didUpdateWidget 里
  /// 「autoPlay 仍为 true 但没在播 → resume()」这条兜底，把用户刚按下的
  /// 暂停立刻撤销，表现就是「点了暂停没反应，还在播」。
  bool _userPaused = false;
  bool _isBuffering = false;

  /// 高清档「起播前预充缓冲」进行中。
  ///
  /// 这段时间里位置本来就该停着（预载完会主动 pause 攒数据），
  /// 卡死自愈与"playing 变 false 就恢复"的判定必须让路，否则会在
  /// 预充过程中把播放器重建掉，等于白攒。
  bool _priming = false;
  bool _recoveryInProgress = false;
  bool? _lastReportedPlaying;
  DateTime? _bufferingStartedAt;
  String? _error;
  bool _showControls = true;
  bool _showCenterPlayPause = false;
  Timer? _controlsTimer;
  Timer? _prefetchRetryTimer;
  void Function()? _backoffListener;
  DateTime _lastUiRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 切集延迟埋点：从「要求播放」到 `isPlaying == true` 的耗时。
  ///
  /// 这是唯一能客观衡量"丝滑"的指标：改前改后各滑 10 集对比数值，
  /// 比"感觉快了一点"可靠得多。
  DateTime? _playRequestedAt;
  bool _playLatencyReported = false;

  /// 本集是否已经通过 [HlsPrefetcher] 把首分片灌进浏览器缓存。
  bool _webPrefetchWarmed = false;

  /// 是否已有一轮预取正在等待带宽窗口。
  ///
  /// 【必须有】同一集会被反复要求预热：切页 postFrame 一次、+200ms/+700ms
  /// 各补一次、拖拽回调再按 400ms 节流来几次。没有这个闸门时会有多路
  /// `waitForPrefetchSlot` 同时在跑，彼此把 gate 顶成 false，触发 backoff
  /// 的 release，刚下好的分片被丢掉又重下 —— 这就是"怎么都预不热"。
  bool _prefetchInFlight = false;

  /// 要求播放时播放器是否已经准备好（已预热过的实例）。
  bool _controllerWasPrepared = false;

  /// 【卡死自愈】position 连续 [_stallTimeout] 不前进即判定为卡住。
  ///
  /// 实测两条成因：预热收尾 `seekTo(0)` 会 flush 整条缓冲，用户滑入时
  /// 只剩不到 1s 数据（起播一秒后停住）；CDN 节点拒绝连接时 ExoPlayer
  /// 直接进入 error 态。原来的恢复逻辑要求 `!isBuffering`，卡在缓冲中
  /// 时一次都不会触发，必须按"位置不再前进"来判定。
  static const Duration _stallTimeout = Duration(milliseconds: 2500);
  static const Duration _recoverCooldown = Duration(seconds: 2);
  Duration _lastObservedPosition = Duration.zero;
  DateTime _positionIdleSince = DateTime.now();
  DateTime _lastRecoveryAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _stallAttempts = 0;
  int _errorRestarts = 0;

  /// 该集是否已被调度策略主动释放（Android 释放 center-1 等）。
  ///
  /// 【必须有】releasePrefetched 只释放当下一刻的 controller，但
  /// `_schedulePrefetchRetry` 排的定时器仍可能在几秒后把这一集**重新
  /// 预热**——日志实测每次切集都会多出 1~2 个后台 init（master 下载
  /// ~1s + 首分片），纯粹抢当前集的带宽。置位后禁止一切后台预热，
  /// 直到用户真正要求播放（_markPlaybackRequested）时复位。
  bool _backgroundPrefetchSuppressed = false;

  String get _url {
    final info = widget.videoInfo;
    final urls = switch (widget.quality) {
      '1080P' => [info.videoUrlTwo, info.videoUrlOne, info.videoUrl],
      '720P' => [info.videoUrlOne, info.videoUrl, info.videoUrlTwo],
      _ => [info.videoUrl, info.videoUrlOne, info.videoUrlTwo],
    };
    return urls
        .map((e) => (e ?? '').toString().trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => '');
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay && !widget.lockedPreviewMode) _initialize();
  }

  @override
  void didUpdateWidget(covariant WatchShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 【清晰度热切换】必须比较 quality：videoUrlOne/videoUrlTwo 为空时
    // 切档不改 URL，之前只改了角标文字、流根本没换。
    final changed =
        _url != _urlFor(oldWidget) ||
        widget.videoInfo.id != oldWidget.videoInfo.id ||
        widget.lockedPreviewMode != oldWidget.lockedPreviewMode ||
        widget.quality != oldWidget.quality;
    if (changed) {
      _hideControls();
      _webPrefetchWarmed = false;
      // 换集/换清晰度：用户对上一集的暂停意图不能带到新内容上。
      _userPaused = false;
      _playRequestedAt = null;
      _playLatencyReported = false;
      // 同一集内切清晰度：记住当前进度，新控制器起播后 seek 回来。
      _resumePosition = widget.videoInfo.id == oldWidget.videoInfo.id
          ? _controller?.value.position
          : null;
      // 清晰度/集数变了：卡顿统计重新开始积累。
      _stallWindowStart = null;
      _stallAccumulated = Duration.zero;
      if (widget.autoPlay && !widget.lockedPreviewMode) {
        _initialize();
      } else {
        unawaited(_release());
      }
    } else if (widget.autoPlay != oldWidget.autoPlay) {
      if (widget.autoPlay && !widget.lockedPreviewMode) {
        resume();
      } else {
        pause();
      }
    } else if (widget.autoPlay && !widget.lockedPreviewMode) {
      // 用户手动暂停过就不要再拉起：父级任何一次 rebuild 都会走到这里，
      // 不拦的话「单击暂停」等于没按。
      if (_userPaused) return;
      final controller = _controller;
      if (controller == null || !controller.value.isPlaying) resume();
    }
  }

  String _urlFor(WatchShortVideoItem item) {
    final info = item.videoInfo;
    final urls = switch (item.quality) {
      '1080P' => [info.videoUrlTwo, info.videoUrlOne, info.videoUrl],
      '720P' => [info.videoUrlOne, info.videoUrl, info.videoUrlTwo],
      _ => [info.videoUrl, info.videoUrlOne, info.videoUrlTwo],
    };
    return urls
        .map((e) => (e ?? '').toString().trim())
        .firstWhere((e) => e.isNotEmpty, orElse: () => '');
  }

  Future<void> releasePrefetched() async {
    if ((widget.autoPlay && !widget.lockedPreviewMode) || _loading) return;
    ++_generation;
    _prefetchRetryTimer?.cancel();
    _backgroundPrefetchSuppressed = true;
    await _release();
  }

  /// 调度器把这一集重新纳入预热范围（变成 center+1）时调用。
  ///
  /// 【为什么必须有】`releasePrefetched` 会置 `_backgroundPrefetchSuppressed`，
  /// 防止被释放的集被定时器立刻重新预热抢带宽。但这个标记原来只在
  /// `_markPlaybackRequested`（用户真的要播）时才复位 —— 于是每一集
  /// 当 center+2 时被 release、当 center+1 时预热被这行 `return` 吞掉、
  /// 当 center 时只能冷启动。日志实测：`[PrefetchDbg] around center=N`
  /// 出现几十次，而 `prefetch ready` 一次都没有，`initialize done`
  /// 稳定 1.4~1.8s。角色变了，抑制就该失效。
  void allowBackgroundPrefetch() {
    _backgroundPrefetchSuppressed = false;
  }

  Future<void> _playController(VideoPlayerController controller) async {
    if (!mounted ||
        !identical(controller, _controller) ||
        !_playbackRequested ||
        widget.lockedPreviewMode) {
      return;
    }
    // 该组件已成为正在播放的集，不再需要「让出带宽」的监听。
    _removeBackoffListener();
    _markPlaybackRequested();
    await controller.setVolume(1);
    if (!mounted ||
        !identical(controller, _controller) ||
        !_playbackRequested ||
        widget.lockedPreviewMode) {
      return;
    }
    await controller.play();
  }

  /// 记录「用户要看这一集」的时刻。
  ///
  /// 必须打在**滑到这一集的那一瞬间**，而不是 `play()` 之前：否则新开一集
  /// 最耗时的 `initialize()`（跨境校验 playlist + 下载首分片）会被漏掉。
  /// 另外不能用 `isPlaying` 判定"已经开始" —— web 上调用 `play()` 就会
  /// 立刻把 `isPlaying` 置 true（乐观更新），量出来全是 0ms。
  void _markPlaybackRequested() {
    if (_playRequestedAt != null || _playLatencyReported) return;
    _controllerWasPrepared = _controller?.value.isInitialized ?? false;
    _playRequestedAt = DateTime.now();
    // 用户真正要看这一集了：解除「策略释放后禁止后台预热」的限制。
    _backgroundPrefetchSuppressed = false;
  }

  Future<void> prefetchPlayableUrl({bool playIfReady = false}) async {
    if (playIfReady && !widget.lockedPreviewMode) {
      _playbackRequested = true;
      _userPaused = false;
      _markPlaybackRequested();
    }
    if (_controller != null && _controller!.value.isInitialized) {
      if (playIfReady) await _playController(_controller!);
      return;
    }
    if (_initializationFuture != null) {
      await _initializationFuture;
      final controller = _controller;
      if (playIfReady && controller != null) {
        await _playController(controller);
      }
      return;
    }
    if (_url.isEmpty) return;

    // 用户路径（playIfReady）永远不挡；只有后台预热去重。
    if (!playIfReady) {
      if (_backgroundPrefetchSuppressed) return;
      if (_prefetchInFlight) return;
      _prefetchInFlight = true;
    }
    try {
      // 【Web 专用预热】见 hls_prefetch.dart：
      // 离屏 `<video>` + setVolume(0) 在 Chrome 上会被自动播放策略拒绝，
      // 于是原来的预热在 web 上等于没做。改成直接把首分片灌进浏览器
      // HTTP 缓存（CDN 上 `.ts` 是 max-age=2592000 + CORS *），
      // 用户滑过来时 `<video>` 直接命中本地缓存起播。
      if (kIsWeb && !playIfReady) {
        final url = _url;
        final hasSlot = await PlaybackBufferGuard.waitForPrefetchSlot(
          isCancelled: () =>
              !mounted ||
              widget.autoPlay ||
              _playbackRequested ||
              widget.lockedPreviewMode,
        );
        if (!mounted || widget.autoPlay || _playbackRequested) {
          return;
        }
        if (!hasSlot) {
          debugPrint(
            '[WatchShortVideoItem] web prefetch skipped state=${PlaybackBufferGuard.debugState}',
          );
          _schedulePrefetchRetry();
          return;
        }
        final warmed = await HlsPrefetcher.warmUp(
          url,
          quality: widget.quality,
        );
        if (!mounted) return;
        // 【等待 warmUp 期间用户已经滑到这一集】字节已经在浏览器缓存里了，
        // 直接按播放路径补齐，别把预热白丢（实测白丢一次 = 5.8s 冷启动，
        // 占 SwitchLatency 样本里最差的一档）。
        if (widget.autoPlay || _playbackRequested) {
          debugPrint(
            '[PrefetchDbg] promote warmUp to playback warmed=$warmed '
            'url=${url.split('/').last}',
          );
          if (_controller != null) {
            await _playController(_controller!);
          } else if (_initializationFuture == null) {
            await _initialize(playAfterInitialize: true, warmup: false);
          }
          return;
        }
        // 【web 不再建离屏 `<video>` 预热】与推荐页（ShortVideoItem）对齐。
        //
        // 原来这里并行做两件事：Dio `warmUp` 下首分片 + 建离屏 `<video>`
        // 静音 play()。但 `<video>` 的预热在浏览器上注定无效：
        //   1. 收尾的 `pause()` 会让 `<video>` **停止缓冲**
        //      （原生 ExoPlayer 暂停后仍继续下，这是最大差异）；
        //   2. `seekTo(0)` 会 flush 整条 MediaSource 缓冲；
        //   3. Chrome 自动播放策略还可能直接拒绝 play()。
        // 结果等于把刚下好的 403KB 白扔，还多占一条连接和一份解码。
        //
        // 只保留 Dio 灌 HTTP 缓存：用户滑过来时 `<video>` 建起来直接命中
        // 本地缓存，这才是 web 上唯一有效的预热路径。
        if (warmed) {
          _webPrefetchWarmed = true;
          debugPrint('[WatchShortVideoItem] web prefetch ready url=$url');
        } else {
          // 预热没成功：交给重试，别让这一集彻底没有预热机会。
          _schedulePrefetchRetry();
        }
        await _initialize(playAfterInitialize: false, warmup: false);
        return;
      }

      await _initialize(playAfterInitialize: playIfReady, warmup: !playIfReady);
    } finally {
      if (!playIfReady) _prefetchInFlight = false;
    }
  }

  Future<void> _initialize({
    bool playAfterInitialize = true,
    bool warmup = false,
  }) async {
    if (playAfterInitialize && !widget.lockedPreviewMode) {
      _markPlaybackRequested();
    }
    final pending = _initializationFuture;
    if (pending != null) {
      if (playAfterInitialize && !widget.lockedPreviewMode) {
        _playbackRequested = true;
      }
      // 等待期间若被 pause() 作废（generation 变化），等待结束后不能再
      // 把（可能是旧地址的）控制器播出来。
      final genAtWait = _generation;
      await pending;
      final controller = _controller;
      if (playAfterInitialize &&
          controller != null &&
          _generation == genAtWait) {
        await _playController(controller);
        return;
      }
      // 【自愈】等待中的 init 可能被 generation 变化（backoff 释放等）
      // 打断并 dispose，结束后 `_controller` 仍是 null。这时如果用户
      // 已经要求播放，绝不能就此返回——实测表现为黑屏干等 11s+
      // 直到下一轮 `_prefetchAround` 补救。重开一次播放初始化。
      if (playAfterInitialize &&
          !widget.lockedPreviewMode &&
          _generation == genAtWait &&
          _controller == null &&
          _initializationFuture == null) {
        debugPrint(
          '[PrefetchDbg] pending init yielded no controller, retrying play init',
        );
        await _initialize(playAfterInitialize: true, warmup: false);
      }
      return;
    }
    final future = _createController(
      playAfterInitialize: playAfterInitialize,
      warmup: warmup,
    );
    _initializationFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    }
  }

  Future<void> _createController({
    required bool playAfterInitialize,
    required bool warmup,
  }) async {
    final generation = ++_generation;
    final url = _url;
    if (url.isEmpty) {
      if (mounted) {
        debugPrint(
          '[WatchShortVideoItem] init failed: video url unavailable '
          'videoId=${widget.videoInfo.videoId} serialNum=${widget.videoInfo.serialNum}',
        );
        setState(() {
          _loading = false;
          _error = 'Video URL unavailable';
        });
      }
      return;
    }
    // 【按清晰度定档】后端给的是多码率 master playlist。原样丢给 `<video>`
    // 时浏览器 ABR 会挑 720p/1080p：首分片 1.70MB / 2.13MB，
    // 实测要 9.8s / 12.6s；而 480p 那一路首分片只有 403KB / 0.78s。
    // UI 上写的 "480P" 之前完全没生效，就是因为这里没做选择。
    // 命中缓存（预热或上一轮已解析）时是同步返回，不额外增加起播耗时。
    final stopwatch = Stopwatch()..start();
    debugPrint(
      '[WatchShortVideoItem] init start url=${url.split('/').last} '
      'quality=${widget.quality}',
    );
    final playable =
        HlsPrefetcher.cachedRendition(url, quality: widget.quality) ??
        await HlsPrefetcher.resolveRendition(url, quality: widget.quality);
    if (!mounted || generation != _generation) return;
    debugPrint(
      '[WatchShortVideoItem] rendition=${playable.split('/').last} '
      'cost=${stopwatch.elapsedMilliseconds}ms',
    );

    final next = VideoPlayerController.networkUrl(Uri.parse(playable));
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _completed = false;
      });
    }
    try {
      await next.initialize();
      // 新实例起来了，自愈计数与卡死观察窗口全部归零。
      _errorRestarts = 0;
      _stallAttempts = 0;
      _lastObservedPosition = Duration.zero;
      _positionIdleSince = DateTime.now();
      debugPrint(
        '[WatchShortVideoItem] initialize done '
        'cost=${stopwatch.elapsedMilliseconds}ms',
      );
      if (!mounted || generation != _generation) {
        await next.dispose();
        return;
      }
      final previous = _controller;
      previous?.removeListener(_onTick);
      _controller = next;
      next.addListener(_onTick);
      await previous?.dispose();
      await next.setLooping(false);
      if (playAfterInitialize && !widget.lockedPreviewMode) {
        // init 途中（或 initialize 之后的收尾 await 间隙）被 pause()/
        // release() 作废过：按取消处理，绝不"迟到起播"——否则画面是
        // 新一集、声音是滑走的旧一集。
        if (generation != _generation) {
          debugPrint(
            '[WatchShortVideoItem] stale play init aborted '
            'url=${url.split('/').last}',
          );
          await next.dispose();
          return;
        }
        _playbackRequested = true;
        // 【高清档起播前先攒缓冲】用户明确选择"保留 720P/1080P，加长缓冲"。
        final primed = await _primeBufferBeforePlay(next, generation);
        if (!primed) {
          // 预充期间被切集/暂停作废：不再起播，剩余收尾交给 pause/_release。
          debugPrint(
            '[WatchShortVideoItem] prime aborted url=${url.split('/').last}',
          );
          return;
        }
        await _playController(next);
        // 清晰度热切换：起播成功后把切档前的进度 seek 回来。
        final resume = _resumePosition;
        if (resume != null && resume > Duration.zero) {
          _resumePosition = null;
          await next.seekTo(resume);
        }
      } else if (warmup) {
        // 当前正在观看的这一集（autoPlay）绝不能被预取策略拦住：
        // 切集瞬间如果先等待「让出带宽」，会出现黑屏且一直不播。
        final isActiveItem = _playbackRequested || widget.autoPlay;

        if (!isActiveItem) {
          await next.setVolume(0);
          final hasSlot = await PlaybackBufferGuard.waitForPrefetchSlot(
            isCancelled: () =>
                !mounted ||
                generation != _generation ||
                _playbackRequested ||
                widget.autoPlay ||
                widget.lockedPreviewMode,
          );
          if (!mounted || generation != _generation) {
            debugPrint(
              '[PrefetchDbg] warmup init aborted after slot wait '
              'mounted=$mounted genOk=${generation == _generation}',
            );
            await next.dispose();
            return;
          }

          // 等待期间用户切到了这一集：直接起播，不能再按预取处理。
          if (_playbackRequested || widget.autoPlay) {
            debugPrint(
              '[WatchShortVideoItem] prefetch promoted to playback buffered=${_bufferedAhead(next).inSeconds}s',
            );
            await _playController(next);
            if (mounted && generation == _generation) {
              setState(() => _loading = false);
            }
            return;
          }

          if (!hasSlot) {
            debugPrint(
              '[WatchShortVideoItem] prefetch skipped state=${PlaybackBufferGuard.debugState}',
            );
            await _release();
            _schedulePrefetchRetry();
            return;
          }

          // 【原生预热绝不调用 play()】volume=0 也拦不住：video_player 的
          // ExoPlayer 开了 handleAudioFocus，预热实例一 play() 就抢走音频
          // 焦点，把正在播的当前集顶成暂停（表现：起播几秒后自己顿一下，
          // 500ms 后恢复——实测日志 recovering stalled buffered=18s）。
          // ExoPlayer 在 playWhenReady=false 时照样继续下载缓冲（实测
          // 暂停的预热实例能缓冲到 ~50s），所以原生只轮询缓冲量即可。
          // web 的 <video> 暂停时不缓冲，仍需 play() 推着走。
          if (kIsWeb) await next.play();
          final warmupDeadline = DateTime.now().add(_prefetchWarmupMaxDuration);
          while (mounted &&
              generation == _generation &&
              !_playbackRequested &&
              !widget.autoPlay &&
              DateTime.now().isBefore(warmupDeadline) &&
              _bufferedAhead(next) < _prefetchWarmupTarget) {
            if (PlaybackBufferGuard.prefetchShouldYield) {
              // 正在播放的集真的吃紧了，才放弃预取把带宽让回去。
              // 用 prefetchAllowed 会因 startAhead(3s) 门槛白丢已下的分片。
              debugPrint(
                '[WatchShortVideoItem] prefetch abandoned state=${PlaybackBufferGuard.debugState}',
              );
              await _release();
              _schedulePrefetchRetry();
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 200));
          }
          if (!mounted || generation != _generation) {
            await next.dispose();
            return;
          }
          final ahead = _bufferedAhead(next);
          debugPrint(
            '[WatchShortVideoItem] prefetch '
            '${ahead.inMilliseconds >= 800 ? 'ready' : 'ready(thin)'} '
            'buffered=${ahead.inSeconds}s target=${_prefetchWarmupTarget.inSeconds}s',
          );
        }

        if (_playbackRequested || widget.autoPlay) {
          await _playController(next);
        } else {
          // 【预热收尾是静默 pause+seekTo(0)】它不打 pause requested 日志，
          // 却是"起播 1 秒后画面顿一下"的头号嫌疑：若用户恰在此间隙滑入，
          // 正在看的控制器会被 seek 回 0。必须留日志定位。
          debugPrint(
            '[WatchShortVideoItem] warmup tail pause+seek url=${url.split('/').last}',
          );
          await next.pause();
          if (next.value.position > Duration.zero) {
            // 【seek 会 flush 整条缓冲】ExoPlayer 与 HTMLMediaElement 在
            // seek 后都会丢弃已下载数据重新请求。原实现 seek 完立刻返回，
            // 用户滑入时拿到的是"已 initialize 但缓冲 0ms"的实例 ——
            // 实测表现就是起播一秒后画面停住不动。
            await next.seekTo(Duration.zero);
            await _awaitRebuffered(
              next,
              generation,
              const Duration(milliseconds: 1200),
            );
          }
          await next.setVolume(1);
          if (_playbackRequested || widget.autoPlay) {
            await _playController(next);
          } else {
            // ExoPlayer 暂停后仍会继续下载到约 50 秒缓冲，
            // 所以必须保留「让出带宽即释放」的监听。
            _installBackoffListener();
          }
        }
      }
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    } catch (e, stack) {
      debugPrint(
        '[WatchShortVideoItem] init/play failed url=${url.split('/').last} '
        'playAfterInitialize=$playAfterInitialize error=$e',
      );
      debugPrint('$stack');
      await next.dispose();
      if (mounted && generation == _generation) {
        if (_playbackRequested || widget.autoPlay) {
          setState(() {
            _loading = false;
            _error = e.toString();
          });
        } else {
          // 【预热失败 ≠ 播放失败】warmup 的 play() 在 Chrome 上可能被
          // 自动播放策略拒绝（volume=0 不等于 muted）。离屏页面绝不能
          // 直接把错误文案挂上（用户滑过来会看到报错，且 _url 不变时
          // didUpdateWidget 不会重新 init）。降级为排队重试：届时若
          // 用户已滑到这一集，会走播放路径正常起播。
          _schedulePrefetchRetry();
        }
      }
    }
  }

  Duration _bufferedAhead(VideoPlayerController controller) {
    final value = controller.value;
    final currentPosition = value.position;
    var bufferedUntil = currentPosition;
    for (final range in value.buffered) {
      if (range.start <= currentPosition && range.end > bufferedUntil) {
        bufferedUntil = range.end;
      }
    }
    return bufferedUntil - currentPosition;
  }

  /// seek 之后等缓冲重新填回来。
  ///
  /// ExoPlayer 暂停时仍会继续预加载（LoadControl 的 bufferForPlaybackMs
  /// 与 playWhenReady 无关），所以这里能等到数据；web 的 `<video>` 暂停时
  /// 不会主动拉流，超时返回即可，不能把预取收尾卡死。
  Future<void> _awaitRebuffered(
    VideoPlayerController controller,
    int generation,
    Duration target,
  ) async {
    final deadline = DateTime.now().add(const Duration(milliseconds: 1500));
    while (mounted &&
        generation == _generation &&
        DateTime.now().isBefore(deadline)) {
      if (_bufferedAhead(controller) >= target) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  /// 720P/1080P 起播前先攒一段缓冲。
  ///
  /// 【为什么需要】实测当前 CDN 单连接吞吐只有 ~2 Mbps（同一网络下 480P
  /// 能跑到 6 Mbps，说明不是用户 WiFi 的问题），而 720P 码率 3.47 Mbps、
  /// 1080P 码率 7.54 Mbps：边播边下必被播放追上，表现就是"播 2 秒停 8 秒"。
  /// 这里在真正起播前先静音预载 + 暂停等缓冲，把第一次停顿往后推。
  ///
  /// 只在原生端生效：web 的 `<video>` 一旦 pause 就停止缓冲，等下去只是白等。
  /// 任何异常/超时都放行 —— "多缓冲"绝不能变成"打不开"。
  Future<bool> _primeBufferBeforePlay(
    VideoPlayerController controller,
    int generation,
  ) async {
    final target = switch (widget.quality) {
      '1080P' => const Duration(seconds: 6),
      '720P' => const Duration(seconds: 4),
      _ => Duration.zero,
    };
    if (target == Duration.zero ||
        kIsWeb ||
        widget.lockedPreviewMode ||
        _bufferedAhead(controller) >= target) {
      return true;
    }

    _priming = true;
    try {
      // 静音起播一小段把下载管线拉起来，再立刻暂停：ExoPlayer 在
      // playWhenReady=false 时仍会继续填缓冲（实测能到 30s+），
      // 而"从头就暂停"只会停在 bufferForPlaybackMs（约 2.5s）不再增长。
      await controller.setVolume(0);
      await controller.play();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await controller.pause();

      final deadline = DateTime.now().add(
        widget.quality == '1080P'
            ? const Duration(seconds: 12)
            : const Duration(seconds: 9),
      );
      while (mounted &&
          generation == _generation &&
          _playbackRequested &&
          DateTime.now().isBefore(deadline) &&
          _bufferedAhead(controller) < target) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      debugPrint(
        '[WatchShortVideoItem] prime quality=${widget.quality} '
        'buffered=${_bufferedAhead(controller).inMilliseconds}ms '
        'target=${target.inMilliseconds}ms',
      );
    } catch (e) {
      debugPrint('[WatchShortVideoItem] prime failed: $e');
    } finally {
      _priming = false;
      // 预充期间位置本来就停着：卡死观察窗口必须从现在重新计时，
      // 否则起播那一瞬间就会被判定成"位置 2.5s 不动"再自愈一次。
      try {
        _lastObservedPosition = controller.value.position;
      } catch (_) {
        _lastObservedPosition = Duration.zero;
      }
      _positionIdleSince = DateTime.now();
      _stallAttempts = 0;
    }

    if (!mounted || generation != _generation || !_playbackRequested) {
      return false;
    }
    return true;
  }

  /// 检测"卡住不动"，必要时自愈。
  ///
  /// 只在用户真正在看这一集时生效：离屏预热实例的 position 本来就该停着。
  void _watchForStall(VideoPlayerController controller, VideoPlayerValue value) {
    // 高清档预充缓冲期间位置停止是预期行为，不是卡死。
    if (_priming) return;
    // 用户主动暂停时位置当然不动，不是卡死。
    if (_userPaused) return;
    if (!_playbackRequested || widget.lockedPreviewMode || !value.isInitialized) {
      return;
    }
    if (value.hasError) {
      unawaited(
        _recoverPlayback(reason: 'player error: ${value.errorDescription}'),
      );
      return;
    }
    if (value.position != _lastObservedPosition) {
      _lastObservedPosition = value.position;
      _positionIdleSince = DateTime.now();
      _stallAttempts = 0;
      return;
    }
    // 播完停在末帧是正常状态，不算卡住。
    if (value.duration > Duration.zero && value.position >= value.duration) {
      return;
    }
    if (value.isPlaying && !value.isBuffering) return;
    if (DateTime.now().difference(_positionIdleSince) > _stallTimeout) {
      unawaited(_recoverPlayback(reason: 'position stalled'));
    }
  }

  void _onTick() {
    final controller = _controller;
    final value = controller?.value;
    if (controller == null || value == null) return;

    // 【切集延迟埋点】position 真正开始前进才算"播起来了"。
    final requestedAt = _playRequestedAt;
    if (requestedAt != null &&
        !_playLatencyReported &&
        value.isInitialized &&
        value.position > Duration.zero) {
      _playLatencyReported = true;
      _playRequestedAt = null;
      debugPrint(
        '[SwitchLatency] firstProgress=${DateTime.now().difference(requestedAt).inMilliseconds}ms '
        'prefetched=$_webPrefetchWarmed prepared=$_controllerWasPrepared url=$_url',
      );
    }

    // 正在播放的集上报缓冲健康度，供预取决策使用。
    if (_playbackRequested &&
        !widget.lockedPreviewMode &&
        value.isInitialized) {
      final nearEnd =
          value.duration > Duration.zero &&
          value.duration - value.position <= _prefetchNearEndWindow;
      PlaybackBufferGuard.reportActive(
        owner: this,
        buffering: value.isBuffering,
        bufferedAhead: _bufferedAhead(controller),
        nearEnd: nearEnd,
        // 清晰度决定预取阈值：1080p 码率 6 倍于 480p，带宽余量完全不同。
        quality: widget.quality,
        // 位置还在 0 附近 = 这一集刚起播，此时缓冲是正常现象，
        // 不能记成卡顿（一记就会触发冷却，把下一集的预取拦掉）。
        atStart: value.position < const Duration(milliseconds: 500),
      );
    }

    final bufferingChanged = value.isBuffering != _isBuffering;
    if (bufferingChanged) {
      _isBuffering = value.isBuffering;
      if (_isBuffering) {
        _bufferingStartedAt = DateTime.now();
        debugPrint('[WatchShortVideoItem] buffering started url=$_url');
      } else if (_bufferingStartedAt != null) {
        final duration = DateTime.now().difference(_bufferingStartedAt!);
        debugPrint(
          '[WatchShortVideoItem] buffering ended after ${duration.inMilliseconds}ms position=${value.position.inSeconds}s',
        );
        _bufferingStartedAt = null;
      }
    }
    _evaluateAutoDowngrade(value);
    // 【先判播完再判卡顿】自然播完的那一帧 isPlaying 也会翻 false，若先走
    // 卡顿判定，会在 EOS 处触发一次无意义的恢复播放。
    if (value.duration > Duration.zero &&
        value.position >= value.duration &&
        !_completed) {
      _completed = true;
      widget.onCompleted?.call();
    } else if (value.position < value.duration) {
      _completed = false;
    }

    final wasPlaying = _lastReportedPlaying;
    _lastReportedPlaying = value.isPlaying;
    if (wasPlaying == true &&
        !_priming &&
        !_userPaused &&
        !value.isPlaying &&
        !value.isBuffering &&
        _playbackRequested &&
        !_completed &&
        !widget.lockedPreviewMode) {
      unawaited(_recoverPlayback(reason: 'playing state changed to false'));
    }
    _watchForStall(controller, value);

    // 只有展示相关状态变化时才重建；进度条仅在控件可见时刷新。
    //
    // 【重建节流】原来只要控件可见就每个 tick（~60fps）setState 重建整个
    // Stack —— 而这一层里包含 VideoPlayer（web 上是 HtmlElementView，
    // Android 上是 Texture）。每帧重建平台视图是切集头几秒发涩的主因
    //（控件默认可见 2~3 秒）。改成 250ms（4fps）刷新进度，重建量降一个
    // 数量级，进度条肉眼看不出差别。
    final visualChanged =
        bufferingChanged ||
        wasPlaying != value.isPlaying ||
        _loading ||
        _error != null;
    final now = DateTime.now();
    final progressDue =
        _showControls &&
        now.difference(_lastUiRefreshAt) >= const Duration(milliseconds: 250);
    if (mounted && (visualChanged || progressDue)) {
      _lastUiRefreshAt = now;
      setState(() {});
    }
  }

  /// 【自动降档】缓冲占比过高（带宽撑不住当前码率）时通知页面降一档。
  ///
  /// 触发条件（同时满足）：
  /// - 正在自动播放的这一集（用户真的在看，离屏预热不触发）；
  /// - 已过起播阶段（position > 2s，起播缓冲不算卡顿）；
  /// - 30s 滑动窗口内缓冲时间占比 >= 40%，且窗口已积累 >= 10s；
  /// - 当前档位高于 480P（480P 已是兜底档）；
  /// - 距上次降档 >= 90s：给降档后的新码率留观察期，避免连续抖动。
  ///
  /// 降档动作由页面完成（全局 `_currentQuality` 降一档），item 随
  /// didUpdateWidget 重建播放器并保留播放进度（见 [_resumePosition]）。
  void _evaluateAutoDowngrade(VideoPlayerValue value) {
    if (!widget.autoPlay ||
        widget.lockedPreviewMode ||
        !_playbackRequested ||
        !value.isInitialized ||
        value.position < const Duration(seconds: 2)) {
      return;
    }
    final now = DateTime.now();
    final start = _stallWindowStart;
    if (start == null || now.difference(start) > _stallWindow) {
      _stallWindowStart = now;
      _stallAccumulated = Duration.zero;
    }
    // 累计当前这轮 buffering（每 tick 只累计增量，记完把起点挪到 now）。
    if (value.isBuffering && _bufferingStartedAt != null) {
      _stallAccumulated += now.difference(_bufferingStartedAt!);
      _bufferingStartedAt = now;
    }
    final windowElapsed = now.difference(_stallWindowStart!);
    if (windowElapsed < const Duration(seconds: 10)) return;
    final ratio =
        _stallAccumulated.inMilliseconds / windowElapsed.inMilliseconds;

    // 【自动升档】窗口 >= 20s 且几乎零缓冲 → 当前码率下带宽有余量，
    // 通知页面尝试升一档。只在 AUTO 模式下由页面生效；手动选档时忽略
    // （用户明确要的档不动）。命中即重置窗口，避免连续上报。
    if (windowElapsed >= const Duration(seconds: 20) && ratio < 0.05) {
      _stallWindowStart = now;
      _stallAccumulated = Duration.zero;
      widget.onAutoQualityUp?.call();
      return;
    }

    // 【自动降档】兜底档 480P 无处可降，不再上报。
    if (widget.quality == '480P') return;
    final last = _lastAutoDowngradeAt;
    if (last != null && now.difference(last) < const Duration(seconds: 90)) {
      return;
    }
    if (ratio < _stallDowngradeRatio) return;
    _lastAutoDowngradeAt = now;
    _stallWindowStart = now;
    _stallAccumulated = Duration.zero;
    debugPrint(
      '[WatchShortVideoItem] auto quality downgrade requested '
      'quality=${widget.quality} bufferingRatio=${(ratio * 100).toStringAsFixed(0)}%',
    );
    widget.onAutoQualityDown?.call();
  }

  void _installBackoffListener() {
    if (_backoffListener != null) return;
    void listener() {
      if (!mounted) return;
      if (_playbackRequested || widget.lockedPreviewMode) return;
      debugPrint(
        '[WatchShortVideoItem] releasing prefetch to free bandwidth state=${PlaybackBufferGuard.debugState}',
      );
      unawaited(_release());
      _schedulePrefetchRetry();
    }

    _backoffListener = listener;
    PlaybackBufferGuard.addBackoffListener(listener);
  }

  /// 当前集恢复健康后，重新尝试预取，避免一次让出带宽后整集都不再预热。
  void _schedulePrefetchRetry() {
    if (!mounted || _playbackRequested || widget.lockedPreviewMode) return;
    _prefetchRetryTimer?.cancel();
    _prefetchRetryTimer = Timer(PlaybackBufferGuard.stallCooldown, () {
      if (!mounted || widget.autoPlay || widget.lockedPreviewMode) return;
      if (_controller != null) return;
      unawaited(prefetchPlayableUrl());
    });
  }

  void _removeBackoffListener() {
    final listener = _backoffListener;
    if (listener == null) return;
    _backoffListener = null;
    PlaybackBufferGuard.removeBackoffListener(listener);
  }

  Future<void> _recoverPlayback({required String reason}) async {
    if (_recoveryInProgress || !mounted) return;
    if (!_playbackRequested || widget.lockedPreviewMode) return;
    final now = DateTime.now();
    if (now.difference(_lastRecoveryAt) < _recoverCooldown) return;
    _recoveryInProgress = true;
    _lastRecoveryAt = now;
    _positionIdleSince = now;
    try {
      final controller = _controller;
      if (controller == null) {
        // controller 已经不在了：直接重建，别让这一集一直黑着。
        await _restartPlayback();
        return;
      }
      final value = controller.value;
      debugPrint(
        '[WatchShortVideoItem] recovering stalled playback reason=$reason '
        'attempt=${_stallAttempts + 1} url=$_url '
        'position=${value.position.inSeconds}s '
        'buffered=${_bufferedAhead(controller).inSeconds}s '
        'playing=${value.isPlaying} buffering=${value.isBuffering} '
        'error=${value.errorDescription}',
      );
      // 解码/网络错误只能重建控制器：play() 在 error 态下没有任何效果。
      if (value.hasError || _stallAttempts >= 1) {
        _stallAttempts = 0;
        await _restartPlayback();
        return;
      }
      _stallAttempts++;
      // 回退 100ms 再 seek：seek 到与当前完全相同的位置在部分实现里会被
      // 优化掉，必须保证真的触发一次新的数据请求。
      final position = value.position;
      final target = position > const Duration(milliseconds: 200)
          ? position - const Duration(milliseconds: 100)
          : Duration.zero;
      await controller.seekTo(target);
      if (!mounted ||
          !identical(controller, _controller) ||
          !_playbackRequested) {
        return;
      }
      await _playController(controller);
    } catch (e) {
      debugPrint('[WatchShortVideoItem] recover failed: $e');
    } finally {
      _recoveryInProgress = false;
    }
  }

  /// 重建控制器：错误态、以及"seek 也救不回来"的卡死都走这里。
  Future<void> _restartPlayback() async {
    if (!mounted || !_playbackRequested || widget.lockedPreviewMode) return;
    if (_errorRestarts >= 3) {
      debugPrint(
        '[WatchShortVideoItem] giving up after $_errorRestarts rebuilds url=$_url',
      );
      if (mounted) {
        setState(() => _error ??= 'playback failed');
      }
      return;
    }
    _errorRestarts++;
    // 被调度策略置位的「禁止后台预热」必须清掉，否则 _createController
    // 会把自己当成离屏预取而拒绝起播。
    _backgroundPrefetchSuppressed = false;
    _stallAttempts = 0;
    debugPrint(
      '[WatchShortVideoItem] rebuilding controller attempt=$_errorRestarts '
      'url=${_url.split('/').last}',
    );
    await _release();
    // 重建属于故障恢复，不该再打一条 SwitchLatency 污染切集数据。
    _playLatencyReported = true;
    if (!mounted || !_playbackRequested) return;
    await _initialize(playAfterInitialize: true, warmup: false);
  }

  void pause({String reason = 'unspecified', bool byUser = false}) {
    _playbackRequested = false;
    _userPaused = byUser;
    PlaybackBufferGuard.clearActive(this);
    final controller = _controller;
    if (controller != null) {
      debugPrint(
        '[WatchShortVideoItem] pause requested reason=$reason position=${controller.value.position.inSeconds}s',
      );
      // 【先静音再暂停】`pause()` 是异步的，快速连滑时可能在它真正落地前
      // 又被 `_playController` 拉起（或平台层迟了一拍），实测就会出现
      // "画面已经是第 3 集且还没加载出来，声音还是第 1 集"。
      // 音量压 0 是同步生效的最后一道闸；真起播时 `_playController`
      // 会重新 setVolume(1)，不影响正常体验。
      unawaited(controller.setVolume(0));
      unawaited(controller.pause());
    } else if (_initializationFuture != null) {
      // 【快速连滑串音的根因】init 还在飞、controller 还没建出来时被
      // pause()，原来等于没按。init 落地后 _createController 会重新置
      // _playbackRequested=true 强行起播——已经滑走的旧集在几秒后
      // "迟到出声"（画面已是新一集，声音还是旧的）。作废这一代 init，
      // 让它在自己的检查点上 dispose，绝不迟到起播。
      ++_generation;
      debugPrint(
        '[WatchShortVideoItem] pause during init, invalidated generation '
        'reason=$reason',
      );
    }
  }

  void resume() {
    if (widget.lockedPreviewMode) return;
    _playbackRequested = true;
    _userPaused = false;
    _markPlaybackRequested();
    if (_controller == null) {
      unawaited(_initialize());
    } else {
      unawaited(_playController(_controller!));
    }
  }

  Future<void> activateForPlayback() async {
    if (widget.lockedPreviewMode) return;
    _playbackRequested = true;
    _userPaused = false;
    _markPlaybackRequested();
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      await _playController(controller);
      return;
    }
    if (_initializationFuture == null) {
      await _initialize();
    }
  }

  void _togglePlayPause() {
    if (_controller == null || widget.lockedPreviewMode) return;
    if (_controller!.value.isPlaying) {
      pause(reason: 'user tap', byUser: true);
    } else {
      resume();
    }
    _showPlaybackControl();
  }

  void _showPlaybackControl() {
    if (!mounted) return;
    _controlsTimer?.cancel();
    setState(() {
      _showControls = true;
      _showCenterPlayPause = true;
    });
    _controlsTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      final paused = _controller?.value.isPlaying != true;
      setState(() {
        _showControls = false;
        // 暂停时保留中央播放按钮：否则用户点完暂停后连"已暂停"的唯一提示
        // 都会消失，看起来像是卡住了。
        _showCenterPlayPause = paused;
      });
    });
  }

  void _hideControls() {
    _controlsTimer?.cancel();
    _showControls = false;
    _showCenterPlayPause = false;
  }

  void _seek(double value) {
    final controller = _controller;
    if (controller == null) return;
    final duration = controller.value.duration;
    if (duration <= Duration.zero) return;
    unawaited(controller.seekTo(duration * value));
  }

  Future<void> _release() async {
    ++_generation;
    _removeBackoffListener();
    PlaybackBufferGuard.clearActive(this);
    // 【埋点计时器必须随释放重置】否则：这一集上次被打断的 init 留下的
    // `_playRequestedAt` 会被下一次 activate 复用，SwitchLatency 量出来的
    // 是"上上次"的起点（实测污染出 19.4s 的假样本）。
    _playRequestedAt = null;
    _playLatencyReported = false;
    _controllerWasPrepared = false;
    _resumePosition = null;
    final old = _controller;
    _controller = null;
    old?.removeListener(_onTick);
    await old?.dispose();
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _prefetchRetryTimer?.cancel();
    ++_generation;
    _removeBackoffListener();
    PlaybackBufferGuard.clearActive(this);
    final old = _controller;
    old?.removeListener(_onTick);
    unawaited(old?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _controller;
    // 【封面占位】接口返回的 videoPicture 在视频起播前垫底显示：
    // 滑动预热、初始化加载、切清晰度重建期间都看得到封面，不再是纯黑屏。
    // 条件是「还没渲染出画面」——起播后由视频层自然盖住，不需要手动隐藏。
    final coverUrl = (widget.videoInfo.coverUrl ?? '').trim();
    final showCover =
        coverUrl.isNotEmpty &&
        (player == null || !player.value.isInitialized || _loading);
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (showCover)
          Positioned.fill(
            child: Image.network(
              coverUrl,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        if (player != null && player.value.isInitialized)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: player.value.size.width,
              height: player.value.size.height,
              child: VideoPlayer(player),
            ),
          ),
        if (!_loading && player != null && player.value.isInitialized)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlayPause,
            ),
          ),
        // 只有「用户正在看的这一集」才转圈。离屏预热的页面如果也挂
        // CircularProgressIndicator，会同时有 2~3 个全屏进度圈在每帧重绘，
        // 白白抢渲染时间（web 上尤其明显），滑过去之前看到的还是一直在转。
        if ((_loading || _isBuffering) &&
            (_playbackRequested || widget.autoPlay))
          const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            ),
          ),
        if (_error != null)
          Center(
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        if (widget.overlayBuilder != null)
          widget.overlayBuilder!(context, widget.videoInfo),
        if (widget.topOverlayBuilder != null)
          widget.topOverlayBuilder!(context, widget.videoInfo),
        if (!widget.lockedPreviewMode && _showCenterPlayPause)
          Center(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.36),
                  shape: BoxShape.circle,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(
                    player?.value.isPlaying == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
            ),
          ),
        if (!widget.lockedPreviewMode &&
            _showControls &&
            player != null &&
            player.value.isInitialized)
          _buildPlaybackControls(player),
        if (widget.lockedPreviewMode) _buildLockedWatchNowAction(),
      ],
    );
  }

  Widget _buildPlaybackControls(VideoPlayerController player) {
    final duration = player.value.duration;
    final position = player.value.position;
    final progress = duration > Duration.zero
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final buffered = duration > Duration.zero
        ? (player.value.buffered.isEmpty
                      ? Duration.zero
                      : player.value.buffered.last.end)
                  .inMilliseconds /
              duration.inMilliseconds
        : 0.0;

    return Positioned(
      left: 12,
      right: 12,
      bottom: 16,
      child: IgnorePointer(
        ignoring: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                icon: Icon(
                  player.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
                onPressed: _togglePlayPause,
              ),
              const SizedBox(width: 4),
              Text(
                _formatDuration(position),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    secondaryActiveTrackColor: Colors.white38,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white24,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: progress.toDouble(),
                    secondaryTrackValue: buffered.clamp(0.0, 1.0).toDouble(),
                    min: 0,
                    max: 1,
                    onChanged: _seek,
                  ),
                ),
              ),
              Text(
                _formatDuration(duration),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLockedWatchNowAction() {
    final hasWatchNow = widget.onLockedWatchNowTap != null;
    final hasWatchAd = widget.onWatchAdToUnlock != null;
    if (!hasWatchNow && !hasWatchAd) return const SizedBox.shrink();

    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 【防溢出】PageView 的离屏预加载页会被以 ~1x1 约束做一次测量
          // 布局，任何固定尺寸内容（500x300 大图等）都会溢出报错。
          // 约束太小说明本实例不可见，直接跳过渲染；真实可见页面是
          // 全屏约束，不受影响。
          if (constraints.maxWidth < 50 || constraints.maxHeight < 50) {
            return const SizedBox.shrink();
          }
          return SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasWatchAd)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onWatchAdToUnlock,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 500,
                          maxHeight: 300,
                        ),
                        child: Image.asset(
                          'assets/images/unlock.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  if (hasWatchNow && hasWatchAd) const SizedBox(height: 16),
                  if (hasWatchNow) _buildPurchaseVipButton(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPurchaseVipButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onLockedWatchNowTap,
      child: const Text(
        'Purchase VIP',
        style: TextStyle(
          color: Color(0xFFFFE389),
          fontSize: 18,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFFFFE389),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }
}

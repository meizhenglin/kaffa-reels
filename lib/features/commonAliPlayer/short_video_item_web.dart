// Cross-platform short video item backed by Flutter video_player.
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../recommend/models/video_info.dart';
import 'hls_prefetch.dart';
import 'playback_buffer_guard.dart';

class ShortVideoItem extends StatefulWidget {
  final VideoInfo videoInfo;
  final bool autoPlay;
  final bool resolvePlayableUrl;
  final Widget Function(BuildContext context, VideoInfo videoInfo)?
  overlayBuilder;
  final Widget Function(BuildContext context, VideoInfo videoInfo)?
  topOverlayBuilder;
  final String? debugInfo;
  final VoidCallback? onCompleted;

  const ShortVideoItem({
    super.key,
    required this.videoInfo,
    this.autoPlay = false,
    this.resolvePlayableUrl = true,
    this.overlayBuilder,
    this.topOverlayBuilder,
    this.debugInfo,
    this.onCompleted,
  });

  @override
  State<ShortVideoItem> createState() => ShortVideoItemState();
}

class ShortVideoItemState extends State<ShortVideoItem> {
  /// 静音试播要攒到的缓冲量。
  ///
  /// 3.5 秒 ≈ 2MB，足够覆盖"切页 → play()"的握手耗时；再往上多攒一秒，
  /// 都是从当前正在播的那一集嘴里抢来的带宽，得不偿失。
  static const Duration _warmupTarget = Duration(milliseconds: 3500);
  static const Duration _warmupMax = Duration(seconds: 6);

  VideoPlayerController? _controller;
  bool _isLoading = false;
  String? _lastError;
  int _setupGeneration = 0;
  bool _didNotifyCompletion = false;
  Timer? _prefetchRetryTimer;
  void Function()? _backoffListener;

  /// 用户是否已经滑到这一条。预取/预热过程中一旦置位，就要立刻按
  /// 「正常播放」处理，而不是继续按低优先级预取。
  bool _playbackRequested = false;

  /// 是否已有一次预取正在等待带宽窗口（用于去重拖拽期间的重复触发）。
  bool _prefetchInFlight = false;

  /// 切集延迟埋点：从「要求播放」到 `isPlaying == true` 的耗时。
  DateTime? _playRequestedAt;
  bool _playLatencyReported = false;

  /// 【卡死自愈】position 连续 [_stallTimeout] 不前进即判定为卡住。
  ///
  /// 实测"起播一秒后卡住不动"有两个来源：预热收尾 seekTo(0) 清空缓冲后
  /// 只剩不到 1s 数据；CDN 节点拒绝连接导致 ExoPlayer 进入 error 态。
  /// 两者都不会自动恢复，必须在 tick 里主动兜底。
  static const Duration _stallTimeout = Duration(milliseconds: 2500);
  static const Duration _recoverCooldown = Duration(seconds: 2);
  Duration _lastObservedPosition = Duration.zero;
  DateTime _positionIdleSince = DateTime.now();
  DateTime _lastRecoveryAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _stallAttempts = 0;
  int _errorRestarts = 0;
  bool _recoveryInProgress = false;

  /// 本集首分片是否已进入浏览器缓存（web）。
  bool _webPrefetchWarmed = false;

  /// 要求播放时播放器是否已经准备好（预热出来的实例）。
  bool _controllerWasPrepared = false;

  /// 用户手动点了暂停。
  ///
  /// 【为什么单独记一个标记】推荐流里 `widget.autoPlay` 对当前页恒为 true，
  /// 而 [_watchForStall] 的判定条件是「autoPlay 或 _playbackRequested」——
  /// 只按播放器状态判断的话，用户暂停 2.5 秒后会被卡死自愈逻辑当成
  /// "卡住了"重新拉起来，表现就是"点了暂停过两秒自己又播了"。
  bool _userPaused = false;

  /// 单击后短暂显示的播放/暂停图标。
  bool _showPlayPauseHint = false;
  Timer? _playPauseHintTimer;

  @override
  void initState() {
    super.initState();
    if (widget.autoPlay) {
      _setup(widget.videoInfo.videoUrl, true);
    }
  }

  @override
  void didUpdateWidget(covariant ShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoInfo.videoUrl != oldWidget.videoInfo.videoUrl) {
      _webPrefetchWarmed = false;
      _playRequestedAt = null;
      _playLatencyReported = false;
      // 换片了：用户对上一集的暂停意图不能带到新的一集。
      _userPaused = false;
      if (widget.autoPlay) {
        _setup(widget.videoInfo.videoUrl, true);
      } else {
        unawaited(_disposeController());
      }
    } else if (widget.autoPlay != oldWidget.autoPlay) {
      if (widget.autoPlay) {
        // 已经预热好了就直接播，别把预热出来的 controller 丢掉重建 ——
        // 那等于把预加载成果一次性作废，又回到冷启动。
        _userPaused = false;
        _playbackRequested = true;
        _markPlaybackRequested();
        final controller = _controller;
        if (controller != null && controller.value.isInitialized) {
          _removeBackoffListener();
          controller.setVolume(1);
          controller.play();
        } else {
          _setup(widget.videoInfo.videoUrl, true);
        }
      } else {
        _playbackRequested = false;
        unawaited(_disposeController());
      }
    }
  }

  Future<void> releasePrefetched() async {
    if (widget.autoPlay || _playbackRequested || _isLoading) return;
    _setupGeneration++;
    await _disposeController();
  }

  /// 记录「用户要看这一条」的时刻（同 WatchShortVideoItem 的埋点口径）。
  ///
  /// 不能用 `isPlaying` 判定"已经开始"：web 上调 `play()` 就会立刻把
  /// `isPlaying` 置 true，量出来全是 0ms。真正有意义的是 position 开始前进。
  void _markPlaybackRequested() {
    if (_playRequestedAt != null || _playLatencyReported) return;
    _controllerWasPrepared = _controller?.value.isInitialized ?? false;
    _playRequestedAt = DateTime.now();
  }

  Future<void> prefetchPlayableUrl({bool playIfReady = false}) async {
    if (playIfReady) {
      _userPaused = false;
      _playbackRequested = true;
      _markPlaybackRequested();
    }
    if (_controller != null || _isLoading) {
      // 正在预热（_isLoading=false 但 controller 已在播）时，warmup 循环
      // 会看到 _playbackRequested 自动转正；这里只需补一次音量恢复。
      if (playIfReady && _controller?.value.isInitialized == true) {
        await _controller!.setVolume(1);
        await _controller!.play();
      }
      return;
    }
    // 拖拽过程中会被反复触发（每次滚动回调都可能调），
    // 已经有预取在等带宽窗口就直接返回，避免堆一堆等待者。
    if (_prefetchInFlight) return;
    _prefetchInFlight = true;
    try {
      if (!playIfReady) {
        // 单码率 HLS 下，预取会和正在播放的视频抢带宽：
        // 只有当前视频缓冲充足时才允许预取。
        final allowed = await PlaybackBufferGuard.waitForPrefetchSlot(
          isCancelled: () => !mounted || widget.autoPlay || _playbackRequested,
        );
        if (!allowed && !_playbackRequested) {
          debugPrint(
            '[ShortVideoItem] prefetch skipped state=${PlaybackBufferGuard.debugState}',
          );
          return;
        }
        if (!mounted) return;
      }
    } finally {
      _prefetchInFlight = false;
    }
    // 【Web 专用预热】离屏 `<video>` 的静音试播会被 Chrome 自动播放策略
    // 拒绝（video_player_web 只设 volume=0，不设 muted），所以 web 上改成
    // 直接把首分片灌进浏览器 HTTP 缓存，滑过来时 `<video>` 命中本地缓存。
    if (kIsWeb && !playIfReady && !_playbackRequested) {
      final warmed = await HlsPrefetcher.warmUp(widget.videoInfo.videoUrl);
      if (warmed && mounted && !_playbackRequested && !widget.autoPlay) {
        _webPrefetchWarmed = true;
        debugPrint('[ShortVideoItem] web prefetch ready');
        // 字节进缓存后，再把「创建 <video> + 校验 m3u8 + 拿 metadata」
        // 也提前做掉（只 initialize，不 play —— play 才会被自动播放策略拒绝）。
        await _setup(widget.videoInfo.videoUrl, false, warmup: false);
        return;
      }
    }

    // 等待期间用户已经滑到这一条：按播放路径起播，别让预取白白作废。
    await _setup(
      widget.videoInfo.videoUrl,
      playIfReady || _playbackRequested,
    );
    if (!_playbackRequested && _controller != null) {
      _installBackoffListener();
    }
  }

  Duration _bufferedAhead(VideoPlayerController controller) {
    final value = controller.value;
    final position = value.position;
    var bufferedUntil = position;
    for (final range in value.buffered) {
      if (range.start <= position && range.end > bufferedUntil) {
        bufferedUntil = range.end;
      }
    }
    return bufferedUntil - position;
  }

  void _installBackoffListener() {
    if (_backoffListener != null) return;
    void listener() {
      if (!mounted || widget.autoPlay || _playbackRequested) return;
      debugPrint(
        '[ShortVideoItem] releasing prefetch to free bandwidth state=${PlaybackBufferGuard.debugState}',
      );
      _setupGeneration++;
      unawaited(_disposeController());
      _schedulePrefetchRetry();
    }

    _backoffListener = listener;
    PlaybackBufferGuard.addBackoffListener(listener);
  }

  /// 正在播放的视频恢复健康后，再尝试预取下一条。
  void _schedulePrefetchRetry() {
    if (!mounted || widget.autoPlay || _playbackRequested) return;
    _prefetchRetryTimer?.cancel();
    _prefetchRetryTimer = Timer(PlaybackBufferGuard.stallCooldown, () {
      if (!mounted || widget.autoPlay || _playbackRequested) return;
      if (_controller != null || _isLoading) return;
      unawaited(prefetchPlayableUrl());
    });
  }

  void _removeBackoffListener() {
    final listener = _backoffListener;
    if (listener == null) return;
    _backoffListener = null;
    PlaybackBufferGuard.removeBackoffListener(listener);
  }

  Future<void> _setup(String url, bool autoPlay, {bool warmup = true}) async {
    final generation = ++_setupGeneration;
    if (autoPlay || widget.autoPlay || _playbackRequested) {
      _markPlaybackRequested();
    }
    final normalizedUrl = url.trim();
    if (normalizedUrl.isEmpty) {
      await _disposeController();
      if (mounted && generation == _setupGeneration) {
        setState(() => _isLoading = false);
      }
      return;
    }

    final next = VideoPlayerController.networkUrl(Uri.parse(normalizedUrl));
    if (mounted && generation == _setupGeneration) {
      setState(() {
        _isLoading = true;
        _lastError = null;
        _didNotifyCompletion = false;
      });
    }

    try {
      await next.initialize();
      if (!mounted || generation != _setupGeneration) {
        await next.dispose();
        return;
      }

      final old = _controller;
      _controller = next;
      // 新实例起来了，自愈计数与卡死观察窗口全部归零。
      _errorRestarts = 0;
      _stallAttempts = 0;
      _lastObservedPosition = Duration.zero;
      _positionIdleSince = DateTime.now();
      _controller!.addListener(_onPlayerTick);
      await old?.dispose();

      // _playbackRequested 也属于"现在就该播"：用户可能在 initialize()
      // 还没返回时就滑到了这一条，此时若还按预取走预热流程，
      // 会停在"已加载但没播"的冻结帧上。
      if ((autoPlay || widget.autoPlay || _playbackRequested) &&
          generation == _setupGeneration) {
        _removeBackoffListener();
        _playRequestedAt ??= DateTime.now();
        _playLatencyReported = false;
        await _controller!.setVolume(1);
        await _controller!.play();
      } else if (generation == _setupGeneration) {
        // 【预取必须真播一下】video_player 的 initialize() 在 web 上只等到
        // metadata，浏览器不会替你去抓首段；Android 的 ExoPlayer 也只在
        // 真正 play 时才把缓冲往前推。所以这里静音试播到 ~3.5s 缓冲，
        // 再暂停归零 —— 用户滑过来时是"点播放"，而不是"从头加载"。
        //
        // [warmup] 为 false 时不试播，只保留已 initialize 的实例：web 上
        // 静音 play() 会被自动播放策略拒绝（video_player_web 只设 volume=0，
        // 不设 muted），试播纯属浪费；而"提前 initialize"这段本身就有价值。
        if (warmup) {
          await _warmup(_controller!, generation);
        }
        if (mounted &&
            generation == _setupGeneration &&
            !_playbackRequested) {
          _installBackoffListener();
        }
      }
      if (mounted && generation == _setupGeneration) {
        setState(() => _isLoading = false);
        if (_controller == null && !_playbackRequested && !widget.autoPlay) {
          // 预热因"没换到数据"被释放后要排队重试，否则这一集永远停在
          // 没有实例的状态，用户滑过来只能走冷启动。
          _schedulePrefetchRetry();
        }
      }
    } catch (e) {
      await next.dispose();
      if (!mounted || generation != _setupGeneration) return;
      _lastError = e.toString();
      setState(() => _isLoading = false);
    }
  }

  /// 静音试播，把下一集的起始缓冲提前拉下来。
  ///
  /// 结束状态刻意是「暂停 + position=0 + 音量 1」：
  /// - 停在 0 是为了用户切过来时从第一秒开始播，而不是从预热位置续播；
  /// - 音量恢复 1 是为了无论走哪条后续路径（activate 或 didUpdateWidget）
  ///   都不会出现"视频在播但没声音"。
  ///
  /// 如果用户中途滑到了这一条（[_playbackRequested] 置位），
  /// 就保留播放状态、只把音量拉回来，等于零延迟起播。
  Future<void> _warmup(VideoPlayerController controller, int generation) async {
    try {
      await controller.setVolume(0);
      // 【原生绝不能 play()】video_player 的 ExoPlayer 开了 handleAudioFocus，
      // 预热实例一旦 play() 就抢走音频焦点，把正在播的那一集顶成暂停。
      // 实测症状：正在看的集 position 停在 77ms~2.6s 不动，而 buffered
      // 高达 12~48s —— 数据早就够了，只是播放被掐停。
      // ExoPlayer 在 playWhenReady=false 时照样会预加载（LoadControl 的
      // bufferForPlaybackMs 与播放状态无关），所以原生只轮询缓冲量即可；
      // web 的 <video> 暂停时不拉流，仍需 play() 推着走。
      if (kIsWeb) {
        await controller.play();
      }
      final deadline = DateTime.now().add(_warmupMax);
      var lastBuffered = Duration.zero;
      var stagnantTicks = 0;
      var abandoned = false;
      while (mounted &&
          generation == _setupGeneration &&
          !_playbackRequested &&
          !widget.autoPlay &&
          DateTime.now().isBefore(deadline) &&
          _bufferedAhead(controller) < _warmupTarget) {
        if (PlaybackBufferGuard.prefetchShouldYield) {
          abandoned = true;
          debugPrint(
            '[ShortVideoItem] warmup abandoned buffered=${_bufferedAhead(controller).inMilliseconds}ms '
            'state=${PlaybackBufferGuard.debugState}',
          );
          break;
        }
        final buffered = _bufferedAhead(controller);
        if (buffered > lastBuffered) {
          lastBuffered = buffered;
          stagnantTicks = 0;
        } else if (++stagnantTicks >= 8) {
          // 原生暂停态最多预加载到 bufferForPlaybackMs（约 2.5s）就不再增长，
          // 干等只会白占预取槽，让后面几集完全没机会预热。
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (!mounted || generation != _setupGeneration) return;
      if (_playbackRequested || widget.autoPlay) {
        await controller.setVolume(1);
        return;
      }
      final buffered = _bufferedAhead(controller);
      if (abandoned && buffered < const Duration(milliseconds: 800)) {
        // 【保留而不是丢弃】冷启动最贵的一步（解析 m3u8 + 建解码器）已经
        // 做完了，扔掉等于把白送的 500ms 起播时间还回去——实测丢弃后
        // prepared=false 的样本全是 1.0~2.6s 冷启动。
        // ExoPlayer 在暂停态仍会继续预加载，用户滑过来时通常已攒到 1~2s，
        // 剩下的靠正常流式补上；真卡住还有 _watchForStall 兜底。
        debugPrint(
          '[ShortVideoItem] warmup shallow kept buffered=${buffered.inMilliseconds}ms',
        );
      }
      await controller.pause();
      final position = controller.value.position;
      if (position > Duration.zero) {
        // 【seek 会 flush 整条缓冲】ExoPlayer 与 HTMLMediaElement 在 seek
        // 之后都会丢弃已下载数据重新请求。原实现 seek 完立刻返回，用户
        // 滑入时拿到的是"已 initialize 但缓冲 0ms"的实例 —— 实测表现就是
        // 起播一秒后画面停住不动（日志 warmup ready buffered=0ms）。
        await controller.seekTo(Duration.zero);
        await _awaitRebuffered(
          controller,
          generation,
          const Duration(milliseconds: 1200),
        );
      }
      await controller.setVolume(1);
      final aheadMs = _bufferedAhead(controller).inMilliseconds;
      // 【区分 ready 与 ready(thin)】原来超时退出也打印 ready，
      // 于是日志里出现 `warmup ready buffered=0ms`——看着像预热成功，
      // 实际一个字节都没下下来。分开打，排查时不会被误导。
      debugPrint(
        '[ShortVideoItem] warmup ${aheadMs >= 800 ? 'ready' : 'ready(thin)'} '
        'buffered=${aheadMs}ms target=${_warmupTarget.inMilliseconds}ms',
      );
    } catch (e) {
      // 预热失败不影响正常播放：用户滑过来时会重新走 _setup。
      debugPrint('[ShortVideoItem] warmup failed: $e');
    }
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
        generation == _setupGeneration &&
        DateTime.now().isBefore(deadline)) {
      if (_bufferedAhead(controller) >= target) return;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
  }

  /// 检测"卡住不动"，必要时自愈。
  ///
  /// 只在用户真正在看这一条时生效：离屏预热实例的 position 本来就该停着。
  void _watchForStall(VideoPlayerController controller, VideoPlayerValue value) {
    // 用户主动暂停时位置当然不动，这不是卡死。
    if (_userPaused) return;
    if (!(_playbackRequested || widget.autoPlay) || !value.isInitialized) {
      return;
    }
    if (value.hasError) {
      _recoverFromStall(controller, reason: 'error: ${value.errorDescription}');
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
      _recoverFromStall(controller, reason: 'position stalled');
    }
  }

  void _recoverFromStall(
    VideoPlayerController controller, {
    required String reason,
  }) {
    if (_recoveryInProgress || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastRecoveryAt) < _recoverCooldown) return;
    _lastRecoveryAt = now;
    _positionIdleSince = now;
    final value = controller.value;
    debugPrint(
      '[ShortVideoItem] stall recovery attempt=${_stallAttempts + 1} '
      'reason=$reason position=${value.position.inMilliseconds}ms '
      'buffered=${_bufferedAhead(controller).inMilliseconds}ms',
    );
    if (value.hasError || _stallAttempts >= 1) {
      _stallAttempts = 0;
      unawaited(_restartPlayback());
      return;
    }
    _stallAttempts++;
    // 回退 100ms 再 seek：seek 到与当前完全相同的位置在部分实现里会被
    // 优化掉，必须保证真的触发一次新的数据请求。
    final position = value.position;
    final target = position > const Duration(milliseconds: 200)
        ? position - const Duration(milliseconds: 100)
        : Duration.zero;
    unawaited(() async {
      await controller.seekTo(target);
      if (mounted && identical(controller, _controller)) {
        await controller.play();
      }
    }());
  }

  Future<void> _restartPlayback() async {
    if (_recoveryInProgress || !mounted) return;
    if (!(_playbackRequested || widget.autoPlay)) return;
    if (_errorRestarts >= 3) {
      if (mounted) {
        setState(() => _lastError ??= 'playback failed');
      }
      return;
    }
    _recoveryInProgress = true;
    try {
      _errorRestarts++;
      debugPrint(
        '[ShortVideoItem] rebuilding controller attempt=$_errorRestarts',
      );
      await _disposeController();
      if (!mounted || !(_playbackRequested || widget.autoPlay)) return;
      await _setup(widget.videoInfo.videoUrl, true);
    } finally {
      _recoveryInProgress = false;
    }
  }

  void _onPlayerTick() {
    final c = _controller;
    if (c == null) return;
    final value = c.value;

    // 【切集延迟埋点】第一次真正播起来时打一条，用来量化"丝滑"。
    final requestedAt = _playRequestedAt;
    if (requestedAt != null &&
        !_playLatencyReported &&
        value.isInitialized &&
        value.position > Duration.zero) {
      _playLatencyReported = true;
      _playRequestedAt = null;
      debugPrint(
        '[SwitchLatency] firstProgress=${DateTime.now().difference(requestedAt).inMilliseconds}ms '
        'prefetched=$_webPrefetchWarmed prepared=$_controllerWasPrepared',
      );
    }
    // 【必须用 _playbackRequested 兜底】推荐页翻页走的是
    // controller 监听 + 命令式 prefetchPlayableUrl(playIfReady: true)，
    // **不会 setState**，所以 widget.autoPlay 自始至终都是 false。
    // 只用 widget.autoPlay 判断的话，_activeOwner 永远是 null，
    // 而 PlaybackBufferGuard.prefetchAllowed 的第一条就是
    // 「没有 active owner 就不预取」—— 于是预取从开屏起就一直是死的。
    if ((_playbackRequested || widget.autoPlay) && value.isInitialized) {
      PlaybackBufferGuard.reportActive(
        owner: this,
        buffering: value.isBuffering,
        bufferedAhead: _bufferedAhead(c),
        // 位置还在 0 附近 = 刚起播。此时 ahead 必然是 0、也可能短暂
        // buffering，都不该当成"带宽吃紧"去封锁下一集的预取。
        atStart: value.position < const Duration(milliseconds: 500),
      );
    }
    if (value.position >= value.duration && value.duration > Duration.zero) {
      if (_didNotifyCompletion) return;
      _didNotifyCompletion = true;
      widget.onCompleted?.call();
    } else if (value.isPlaying) {
      _didNotifyCompletion = false;
    }
    _watchForStall(c, value);
  }

  Future<void> _disposeController() async {
    _removeBackoffListener();
    PlaybackBufferGuard.clearActive(this);
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    controller.removeListener(_onPlayerTick);
    await controller.dispose();
  }

  void pause() {
    // 【外部暂停必须标记 _userPaused】切 tab / 被全屏覆盖时父级走的是
    // 这里（不是 _togglePlayPause）。若不标记，_watchForStall 会把
    // 「暂停 + 缓冲中 position 不动」误判成卡死，position 停滞超过
    // _stallTimeout 后触发 _recoverFromStall → seek + play()，
    // 结果就是：用户已经切到别的 tab，视频缓冲一好就在后台自动开播。
    // 切回本 tab 时 resume() 会清掉该标记，不影响恢复播放。
    _userPaused = true;
    _playbackRequested = false;
    PlaybackBufferGuard.clearActive(this);
    unawaited(_controller?.pause());
  }

  /// 单击视频区域：暂停 / 继续播放。
  void _togglePlayPause() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      _userPaused = true;
      pause();
    } else {
      _userPaused = false;
      resume();
    }
    _showPlayPauseFeedback();
  }

  /// 在画面中央短暂显示一下当前的播放/暂停图标。
  ///
  /// 暂停后没有任何反馈的话，用户会以为是卡住了（尤其是 720P 缓冲慢时）。
  void _showPlayPauseFeedback() {
    if (!mounted) return;
    _playPauseHintTimer?.cancel();
    setState(() => _showPlayPauseHint = true);
    _playPauseHintTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() => _showPlayPauseHint = false);
    });
  }

  /// 彻底释放播放器（包括当前正在播放的这一条）。
  ///
  /// 进入全屏播放页时必须调用：仅仅 [pause] 时 ExoPlayer 仍会继续下载到
  /// 约 50 秒缓冲，等于同一部剧被两个播放器各下载一遍。
  void releasePlayback() {
    _playbackRequested = false;
    _prefetchRetryTimer?.cancel();
    _setupGeneration++;
    unawaited(_disposeController());
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void resume() {
    _userPaused = false;
    _playbackRequested = true;
    if (_controller == null) {
      _setup(widget.videoInfo.videoUrl, true);
      return;
    }
    // 预取时为了不嘈杂把音量压到 0，恢复播放必须拉回 1。
    _markPlaybackRequested();
    _controller!.setVolume(1);
    _controller!.play();
  }

  @override
  void dispose() {
    _prefetchRetryTimer?.cancel();
    _playPauseHintTimer?.cancel();
    _setupGeneration++;
    unawaited(_disposeController());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black),
        if (_isLoading || controller == null || !controller.value.isInitialized)
          // 只有"用户已经在看的这一条"才转圈。预取中的离屏页面如果也挂
          // CircularProgressIndicator，会同时有 2~3 个进度圈在持续驱动帧，
          // 白白抢占渲染时间（web 上尤其明显）。
          (_playbackRequested || widget.autoPlay)
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : const SizedBox.shrink()
        else
          Positioned.fill(
            child: FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        // 【单击暂停/播放】铺在视频之上、业务浮层之下：
        // 右侧点赞/收藏/Watch 按钮在后面的 overlayBuilder 里，命中优先级更高，
        // 点按钮不会误触发暂停。
        if (!_isLoading && controller != null && controller.value.isInitialized)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlayPause,
            ),
          ),
        if (widget.overlayBuilder != null)
          widget.overlayBuilder!(context, widget.videoInfo),
        if (widget.topOverlayBuilder != null)
          widget.topOverlayBuilder!(context, widget.videoInfo),
        if (_showPlayPauseHint)
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
                    controller?.value.isPlaying == true
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 38,
                  ),
                ),
              ),
            ),
          ),
        if (_lastError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _lastError!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

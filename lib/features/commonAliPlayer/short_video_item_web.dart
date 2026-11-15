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

  /// 本集首分片是否已进入浏览器缓存（web）。
  bool _webPrefetchWarmed = false;

  /// 要求播放时播放器是否已经准备好（预热出来的实例）。
  bool _controllerWasPrepared = false;

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
      if (widget.autoPlay) {
        _setup(widget.videoInfo.videoUrl, true);
      } else {
        unawaited(_disposeController());
      }
    } else if (widget.autoPlay != oldWidget.autoPlay) {
      if (widget.autoPlay) {
        // 已经预热好了就直接播，别把预热出来的 controller 丢掉重建 ——
        // 那等于把预加载成果一次性作废，又回到冷启动。
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
      await controller.play();
      final deadline = DateTime.now().add(_warmupMax);
      while (mounted &&
          generation == _setupGeneration &&
          !_playbackRequested &&
          !widget.autoPlay &&
          DateTime.now().isBefore(deadline) &&
          _bufferedAhead(controller) < _warmupTarget) {
        if (!PlaybackBufferGuard.prefetchAllowed) {
          debugPrint(
            '[ShortVideoItem] warmup abandoned buffered=${_bufferedAhead(controller).inMilliseconds}ms '
            'state=${PlaybackBufferGuard.debugState}',
          );
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      if (!mounted || generation != _setupGeneration) return;
      if (_playbackRequested || widget.autoPlay) {
        await controller.setVolume(1);
        return;
      }
      await controller.pause();
      await controller.seekTo(Duration.zero);
      await controller.setVolume(1);
      debugPrint(
        '[ShortVideoItem] warmup ready buffered=${_bufferedAhead(controller).inMilliseconds}ms '
        'target=${_warmupTarget.inMilliseconds}ms',
      );
    } catch (e) {
      // 预热失败不影响正常播放：用户滑过来时会重新走 _setup。
      debugPrint('[ShortVideoItem] warmup failed: $e');
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
      );
    }
    if (value.position >= value.duration && value.duration > Duration.zero) {
      if (_didNotifyCompletion) return;
      _didNotifyCompletion = true;
      widget.onCompleted?.call();
    } else if (value.isPlaying) {
      _didNotifyCompletion = false;
    }
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
    _playbackRequested = false;
    PlaybackBufferGuard.clearActive(this);
    unawaited(_controller?.pause());
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
        if (widget.overlayBuilder != null)
          widget.overlayBuilder!(context, widget.videoInfo),
        if (widget.topOverlayBuilder != null)
          widget.topOverlayBuilder!(context, widget.videoInfo),
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

// Cross-platform short video item backed by Flutter video_player.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../recommend/models/video_info.dart';
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
  VideoPlayerController? _controller;
  bool _isLoading = false;
  String? _lastError;
  int _setupGeneration = 0;
  bool _didNotifyCompletion = false;
  Timer? _prefetchRetryTimer;
  void Function()? _backoffListener;

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
      if (widget.autoPlay) {
        _setup(widget.videoInfo.videoUrl, true);
      } else {
        unawaited(_disposeController());
      }
    } else if (widget.autoPlay != oldWidget.autoPlay) {
      if (widget.autoPlay) {
        _setup(widget.videoInfo.videoUrl, true);
      } else {
        unawaited(_disposeController());
      }
    }
  }

  Future<void> releasePrefetched() async {
    if (widget.autoPlay || _isLoading) return;
    _setupGeneration++;
    await _disposeController();
  }

  Future<void> prefetchPlayableUrl({bool playIfReady = false}) async {
    if (_controller != null || _isLoading) {
      if (playIfReady && _controller?.value.isInitialized == true) {
        await _controller!.play();
      }
      return;
    }
    if (!playIfReady) {
      // 单码率 HLS 下，预取会和正在播放的视频抢带宽：
      // 只有当前视频缓冲充足时才允许预取。
      final allowed = await PlaybackBufferGuard.waitForPrefetchSlot(
        isCancelled: () => !mounted || widget.autoPlay,
      );
      if (!allowed) {
        debugPrint(
          '[ShortVideoItem] prefetch skipped state=${PlaybackBufferGuard.debugState}',
        );
        return;
      }
    }
    await _setup(widget.videoInfo.videoUrl, playIfReady);
    if (!playIfReady && _controller != null) {
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
      if (!mounted || widget.autoPlay) return;
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
    if (!mounted || widget.autoPlay) return;
    _prefetchRetryTimer?.cancel();
    _prefetchRetryTimer = Timer(PlaybackBufferGuard.stallCooldown, () {
      if (!mounted || widget.autoPlay) return;
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

  Future<void> _setup(String url, bool autoPlay) async {
    final generation = ++_setupGeneration;
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

      if ((autoPlay || widget.autoPlay) && generation == _setupGeneration) {
        _removeBackoffListener();
        await _controller!.play();
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

  void _onPlayerTick() {
    final c = _controller;
    if (c == null) return;
    final value = c.value;
    if (widget.autoPlay && value.isInitialized) {
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
    PlaybackBufferGuard.clearActive(this);
    unawaited(_controller?.pause());
  }

  /// 彻底释放播放器（包括当前正在播放的这一条）。
  ///
  /// 进入全屏播放页时必须调用：仅仅 [pause] 时 ExoPlayer 仍会继续下载到
  /// 约 50 秒缓冲，等于同一部剧被两个播放器各下载一遍。
  void releasePlayback() {
    _prefetchRetryTimer?.cancel();
    _setupGeneration++;
    unawaited(_disposeController());
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void resume() {
    if (_controller == null) {
      _setup(widget.videoInfo.videoUrl, true);
      return;
    }
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
          const Center(child: CircularProgressIndicator(color: Colors.white))
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

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
  static const Duration _prefetchWarmupMaxDuration = Duration(seconds: 20);
  static const Duration _prefetchWarmupTarget = Duration(seconds: 20);

  /// 当前集剩余不足该时长时，允许提前预热下一集。
  static const Duration _prefetchNearEndWindow = Duration(seconds: 20);
  VideoPlayerController? _controller;
  Future<void>? _initializationFuture;
  int _generation = 0;
  bool _loading = false;
  bool _completed = false;
  bool _playbackRequested = false;
  bool _isBuffering = false;
  bool _recoveryInProgress = false;
  bool? _lastReportedPlaying;
  DateTime? _bufferingStartedAt;
  String? _error;
  bool _showControls = true;
  bool _showCenterPlayPause = false;
  Timer? _controlsTimer;
  Timer? _prefetchRetryTimer;
  void Function()? _backoffListener;

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
    final changed =
        _url != _urlFor(oldWidget) ||
        widget.videoInfo.id != oldWidget.videoInfo.id ||
        widget.lockedPreviewMode != oldWidget.lockedPreviewMode;
    if (changed) {
      _hideControls();
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
    await _release();
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
    await controller.setVolume(1);
    if (!mounted ||
        !identical(controller, _controller) ||
        !_playbackRequested ||
        widget.lockedPreviewMode) {
      return;
    }
    await controller.play();
  }

  Future<void> prefetchPlayableUrl({bool playIfReady = false}) async {
    if (playIfReady && !widget.lockedPreviewMode) {
      _playbackRequested = true;
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
    await _initialize(playAfterInitialize: playIfReady, warmup: !playIfReady);
  }

  Future<void> _initialize({
    bool playAfterInitialize = true,
    bool warmup = false,
  }) async {
    final pending = _initializationFuture;
    if (pending != null) {
      if (playAfterInitialize && !widget.lockedPreviewMode) {
        _playbackRequested = true;
      }
      await pending;
      final controller = _controller;
      if (playAfterInitialize && controller != null) {
        await _playController(controller);
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
        setState(() {
          _loading = false;
          _error = 'Video URL unavailable';
        });
      }
      return;
    }
    final next = VideoPlayerController.networkUrl(Uri.parse(url));
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        _completed = false;
      });
    }
    try {
      await next.initialize();
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
        _playbackRequested = true;
        await _playController(next);
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

          await next.play();
          final warmupDeadline = DateTime.now().add(_prefetchWarmupMaxDuration);
          while (mounted &&
              generation == _generation &&
              !_playbackRequested &&
              !widget.autoPlay &&
              DateTime.now().isBefore(warmupDeadline) &&
              _bufferedAhead(next) < _prefetchWarmupTarget) {
            if (!PlaybackBufferGuard.prefetchAllowed) {
              // 正在播放的集开始吃紧，放弃预取把带宽让回去。
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
          debugPrint(
            '[WatchShortVideoItem] prefetch ready buffered=${_bufferedAhead(next).inSeconds}s target=${_prefetchWarmupTarget.inSeconds}s',
          );
        }

        if (_playbackRequested || widget.autoPlay) {
          await _playController(next);
        } else {
          await next.pause();
          await next.seekTo(Duration.zero);
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
    } catch (e) {
      await next.dispose();
      if (mounted && generation == _generation) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
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

  void _onTick() {
    final controller = _controller;
    final value = controller?.value;
    if (controller == null || value == null) return;

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
    final wasPlaying = _lastReportedPlaying;
    _lastReportedPlaying = value.isPlaying;
    if (wasPlaying == true &&
        !value.isPlaying &&
        !value.isBuffering &&
        _playbackRequested &&
        !_completed &&
        !widget.lockedPreviewMode) {
      unawaited(_recoverPlayback(reason: 'playing state changed to false'));
    }
    if (value.duration > Duration.zero &&
        value.position >= value.duration &&
        !_completed) {
      _completed = true;
      widget.onCompleted?.call();
    } else if (value.position < value.duration) {
      _completed = false;
    }

    // 只有展示相关状态变化时才重建；进度条仅在控件可见时需要每帧刷新。
    final visualChanged =
        bufferingChanged ||
        wasPlaying != value.isPlaying ||
        _loading ||
        _error != null;
    if (mounted && (visualChanged || _showControls || _showCenterPlayPause)) {
      setState(() {});
    }
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
    if (_recoveryInProgress) return;
    _recoveryInProgress = true;
    try {
      final controller = _controller;
      if (controller == null || !mounted || !_playbackRequested) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted ||
          !identical(controller, _controller) ||
          !_playbackRequested) {
        return;
      }
      final value = controller.value;
      if (!value.isPlaying &&
          !value.isBuffering &&
          !widget.lockedPreviewMode &&
          value.position < value.duration) {
        debugPrint(
          '[WatchShortVideoItem] recovering stalled playback reason=$reason position=${value.position.inSeconds}s buffered=${_bufferedAhead(controller).inSeconds}s',
        );
        await _playController(controller);
      }
    } finally {
      _recoveryInProgress = false;
    }
  }

  void pause({String reason = 'unspecified'}) {
    _playbackRequested = false;
    PlaybackBufferGuard.clearActive(this);
    final controller = _controller;
    if (controller != null) {
      debugPrint(
        '[WatchShortVideoItem] pause requested reason=$reason position=${controller.value.position.inSeconds}s',
      );
      unawaited(controller.pause());
    }
  }

  void resume() {
    if (widget.lockedPreviewMode) return;
    _playbackRequested = true;
    if (_controller == null) {
      unawaited(_initialize());
    } else {
      unawaited(_playController(_controller!));
    }
  }

  Future<void> activateForPlayback() async {
    if (widget.lockedPreviewMode) return;
    _playbackRequested = true;
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
      pause();
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
      setState(() {
        _showControls = false;
        _showCenterPlayPause = false;
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
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
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
        if (_loading || _isBuffering)
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
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasWatchAd)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onWatchAdToUnlock,
                  child: Image.asset(
                    'assets/images/unlock.png',
                    width: 500,
                    height: 300,
                    fit: BoxFit.contain,
                  ),
                ),
              if (hasWatchNow && hasWatchAd) const SizedBox(height: 16),
              if (hasWatchNow) _buildPurchaseVipButton(),
            ],
          ),
        ),
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

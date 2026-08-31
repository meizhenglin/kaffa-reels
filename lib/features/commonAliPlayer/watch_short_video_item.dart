import 'dart:async';

import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
import 'package:aliplayer_widget/slot/slot_elements.dart';
import 'package:flutter/material.dart';

import '../recommend/models/video_info.dart';

class WatchShortVideoItem extends StatefulWidget {
  final VideoInfo videoInfo;
  final bool autoPlay;
  final bool resolvePlayableUrl;
  final bool lockedPreviewMode;
  final VoidCallback? onLockedWatchNowTap;
  // 看广告解锁按钮的回调（激励广告就绪时显示）
  final VoidCallback? onWatchAdToUnlock;
  final Widget Function(BuildContext context, VideoInfo videoInfo)?
  overlayBuilder;
  final Widget Function(BuildContext context, VideoInfo videoInfo)?
  topOverlayBuilder;
  final bool showDebugInfo;
  final VoidCallback? onCompleted;
  final String quality; // '480P', '720P', '1080P'

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
  State<WatchShortVideoItem> createState() => WatchShortVideoItemState();
}

class WatchShortVideoItemState extends State<WatchShortVideoItem> {
  static const String _tag = 'WatchShortVideoItem';
  static const int _completedStateCode = FlutterAvpdef.completion;

  bool get _isPlaybackBlocked => widget.lockedPreviewMode;

  AliPlayerWidgetController? _controller;
  int? _lastPrepareCostMs;
  int? _lastFirstFrameCostMs;
  StutterInfo? _lastStutterInfo;
  String _currentUrl = '';
  bool _hasResolvedPlayableUrl = false;
  bool _isForegroundActive = false;
  bool _isLoading = false;
  bool _hasPlayer = false;
  bool _isFetchingPlayableUrl = false;
  bool _isPlaying = false;
  bool _showControls = true;
  Timer? _controlsHideTimer;
  bool _showCenterPlayPause = false;
  bool _didNotifyCompletion = false;
  Timer? _centerPlayPauseTimer;
  bool _isLongPressSpeeding = false;
  bool _showLongPressSpeedHint = false;

  AliPlayerWidgetController? get controller => _controller;

  String _getUrlForQuality(String quality) {
    switch (quality) {
      case '1080P':
        // 1080P -> videoUrlTwo (vipEpisodesUrl1440)
        return widget.videoInfo.videoUrlTwo ?? widget.videoInfo.videoUrl;
      case '720P':
        // 720P -> videoUrlOne (vipEpisodesUrl1080)
        return widget.videoInfo.videoUrlOne ?? widget.videoInfo.videoUrl;
      case '480P':
      default:
        return widget.videoInfo.videoUrl;
    }
  }

  @override
  void initState() {
    super.initState();
    _currentUrl = _getUrlForQuality(widget.quality);
    _hasResolvedPlayableUrl =
        !widget.resolvePlayableUrl || _currentUrl.isNotEmpty;
    _isForegroundActive = widget.autoPlay;
    _isLoading = widget.autoPlay && _currentUrl.isNotEmpty;

    debugPrint(
      '[$_tag][initState] id=${widget.videoInfo.id} autoPlay=${widget.autoPlay} resolve=${widget.resolvePlayableUrl} quality=${widget.quality} url=$_currentUrl',
    );

    if (_currentUrl.isNotEmpty && widget.autoPlay && !_isPlaybackBlocked) {
      _configurePlayer(_currentUrl, autoPlay: true);
    }

    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showCenterPlayPauseOverlay();
      });
    }

    if (widget.resolvePlayableUrl &&
        _currentUrl.isEmpty &&
        !_isPlaybackBlocked) {
      scheduleMicrotask(
        () => prefetchPlayableUrl(playIfReady: widget.autoPlay),
      );
    }
  }

  void _configurePlayer(String url, {required bool autoPlay}) {
    final bool isFirstInit = _controller == null;
    if (isFirstInit) {
      _controller = AliPlayerWidgetController(context);
      _controller!.playStateNotifier.addListener(_handlePlayStateChanged);
    }
    // Always register strategies (they get replaced if already registered)
    final stateMounted = mounted;
    _controller!.strategyManager
      ..register(
        FirstFrameStrategy(
          onPrepared: (cost) {
            _lastPrepareCostMs = cost.inMilliseconds;
            debugPrint(
              '[$_tag][strategy][prepared] id=${widget.videoInfo.id} costMs=$_lastPrepareCostMs url=$url mounted=$stateMounted',
            );
            setState(() {
              _isLoading = false;
            });
          },
          onFirstFrame: (cost) {
            _lastFirstFrameCostMs = cost.inMilliseconds;
            debugPrint(
              '[$_tag][strategy][firstFrame] id=${widget.videoInfo.id} costMs=$_lastFirstFrameCostMs url=$url mounted=$stateMounted',
            );
            setState(() {
              _isLoading = false;
            });
          },
        ),
      )
      ..register(
        StutterDetectStrategy(
          onStutterDetected: (info) {
            _lastStutterInfo = info;
            debugPrint(
              '[$_tag][strategy][stutter] id=${widget.videoInfo.id} count=${info.stutterCount} totalMs=${info.totalStutterDuration.inMilliseconds} rate=${info.stutterRate.toStringAsFixed(4)} url=$url',
            );
          },
        ),
      );
    _hasPlayer = true;
    _isLoading = autoPlay && url.isNotEmpty;

    final videoSource = VideoSourceFactory.createUrlSource(url);
    final data = AliPlayerWidgetData(
      sceneType: SceneType.listPlayer,
      videoSource: videoSource,
      androidViewType: AndroidViewType.textureView,
      coverUrl: widget.videoInfo.coverUrl ?? '',
      autoPlay: autoPlay,
      onPlayerConfig: (_) async {
        await _controller?.setScaleMode(ScaleMode.SCALE_ASPECT_FILL);
      },
    );
    _controller!.configure(data);
  }

  void _handlePlayStateChanged() {
    final playState = _controller?.playStateNotifier.value;
    debugPrint('[$_tag][playState] state=$playState loading=$_isLoading');
    if (playState == _completedStateCode) {
      if (_didNotifyCompletion) return;
      _didNotifyCompletion = true;
      widget.onCompleted?.call();
      return;
    }
    // Close loading when video starts playing (any non-completed state)
    if (_isLoading) {
      setState(() {
        _isLoading = false;
      });
    }
    _didNotifyCompletion = false;
  }

  @override
  void didUpdateWidget(covariant WatchShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    debugPrint(
      '[$_tag][didUpdateWidget] quality: ${oldWidget.quality} -> ${widget.quality} _hasPlayer=$_hasPlayer',
    );

    // Handle quality change - reload video with new URL
    if (widget.quality != oldWidget.quality) {
      final newUrl = _getUrlForQuality(widget.quality);
      debugPrint(
        '[$_tag][qualityChange] from=${oldWidget.quality} to=${widget.quality} newUrl=$newUrl currentUrl=$_currentUrl',
      );
      _currentUrl = newUrl;
      _isLoading = true;
      debugPrint(
        '[$_tag][qualityChange] _hasPlayer=$_hasPlayer _isPlaybackBlocked=$_isPlaybackBlocked',
      );
      if (_hasPlayer && !_isPlaybackBlocked) {
        debugPrint('[$_tag][qualityChange] calling _configurePlayer');
        _configurePlayer(_currentUrl, autoPlay: _isPlaying);
      }
      if (mounted) setState(() {});
    }

    if (widget.lockedPreviewMode != oldWidget.lockedPreviewMode) {
      if (widget.lockedPreviewMode) {
        pause();
        if (mounted) {
          setState(() {
            _showCenterPlayPause = false;
          });
        }
      } else if (widget.autoPlay) {
        resume();
      }
    }

    if (widget.autoPlay != oldWidget.autoPlay) {
      if (widget.autoPlay && !widget.lockedPreviewMode) {
        resume();
      } else {
        pause();
      }
    }

    if (widget.videoInfo.videoUrl != oldWidget.videoInfo.videoUrl &&
        widget.videoInfo.videoUrl.isNotEmpty &&
        widget.videoInfo.videoUrl != _currentUrl) {
      _currentUrl = widget.videoInfo.videoUrl;
      _hasResolvedPlayableUrl = true;
      if (widget.autoPlay && !_isPlaybackBlocked) {
        _configurePlayer(_currentUrl, autoPlay: true);
      } else {
        if (_controller != null) {
          _controller!.pause();
        }
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
      if (mounted) {
        setState(() {});
      }
    }

    if (widget.resolvePlayableUrl &&
        widget.autoPlay &&
        !_isPlaybackBlocked &&
        !_hasResolvedPlayableUrl &&
        _currentUrl.isEmpty) {
      scheduleMicrotask(() => prefetchPlayableUrl(playIfReady: true));
    }
  }

  Future<void> refreshUrl() async {
    await prefetchPlayableUrl(playIfReady: mounted && widget.autoPlay);
  }

  Future<void> prefetchPlayableUrl({bool playIfReady = false}) async {
    if (!mounted || _isFetchingPlayableUrl) return;
    if (_isPlaybackBlocked) {
      _controller?.pause();
      _isForegroundActive = false;
      _isPlaying = false;
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    if (!widget.resolvePlayableUrl) {
      _hasResolvedPlayableUrl = true;
      if (_currentUrl.isNotEmpty) {
        if (_controller == null) {
          _configurePlayer(
            _currentUrl,
            autoPlay: playIfReady || (widget.autoPlay && _isForegroundActive),
          );
          if (mounted) {
            setState(() {});
          }
        } else if (playIfReady || (widget.autoPlay && _isForegroundActive)) {
          _controller!.play();
        } else {
          _controller!.pause();
        }
      } else if (playIfReady && _isForegroundActive) {
        resume();
      }
      return;
    }

    if (_hasResolvedPlayableUrl && _currentUrl.isNotEmpty) {
      if (_controller == null) {
        _configurePlayer(
          _currentUrl,
          autoPlay: playIfReady || (widget.autoPlay && _isForegroundActive),
        );
        if (mounted) {
          setState(() {});
        }
      } else if (playIfReady && _isForegroundActive) {
        resume();
      }
      return;
    }

    _hasResolvedPlayableUrl = true;
  }

  void _disposeController() {
    if (_controller != null) {
      _controller!.playStateNotifier.removeListener(_handlePlayStateChanged);
      _controller!.pause();
      _controller!.stop();
      _controller!.destroy();
      _controller = null;
    }
    _hasPlayer = false;
    _isPlaying = false;
  }

  void _restartControlsHideTimer() {
    _controlsHideTimer?.cancel();
  }

  void _showCenterPlayPauseOverlay() {
    _centerPlayPauseTimer?.cancel();
    if (mounted) {
      setState(() {
        _showCenterPlayPause = true;
      });
    }
    _centerPlayPauseTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _showCenterPlayPause = false;
      });
    });
  }

  void _handleScreenTap() {
    if (widget.lockedPreviewMode) {
      return;
    }
    _togglePlaybackFromCenter();
  }

  void _togglePlaybackFromCenter() {
    if (_isPlaying) {
      pause();
    } else {
      resume();
    }
    _showCenterPlayPauseOverlay();
    _restartControlsHideTimer();
  }

  void _handleLongPressStart() {
    _centerPlayPauseTimer?.cancel();
    _controlsHideTimer?.cancel();
    if (mounted) {
      setState(() {
        _showLongPressSpeedHint = true;
        _showCenterPlayPause = false;
      });
    }
    if (!_isLongPressSpeeding) {
      _isLongPressSpeeding = true;
      final controller = _controller;
      if (controller != null) {
        controller.setSpeed(speed: 2.0);
      }
    }
  }

  void _handleLongPressEnd() {
    if (mounted) {
      setState(() {
        _showLongPressSpeedHint = false;
      });
    }
    if (_isLongPressSpeeding) {
      _isLongPressSpeeding = false;
      final controller = _controller;
      if (controller != null) {
        controller.setSpeed(speed: 1.0);
      }
    }
    if (_showControls) {
      _restartControlsHideTimer();
    }
  }

  void pause() {
    _isForegroundActive = false;
    _isPlaying = false;
    _controller?.pause();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void resume() {
    if (_isPlaybackBlocked) {
      pause();
      return;
    }

    _isForegroundActive = true;
    _isPlaying = true;
    if (_currentUrl.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
      scheduleMicrotask(() => prefetchPlayableUrl(playIfReady: true));
      return;
    }

    if (_controller == null) {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
      }
      _configurePlayer(_currentUrl, autoPlay: true);
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
    _controller?.play();
  }

  Widget _buildAnimatedWatchControls() {
    return IgnorePointer(
      ignoring: !_showControls,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        opacity: _showControls ? 1 : 0,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_controller != null)
              Positioned(
                left: 12,
                right: 12,
                bottom: 16,
                child: _WatchShortVideoProgressBar(controller: _controller!),
              ),
            if (widget.topOverlayBuilder != null)
              widget.topOverlayBuilder!(context, widget.videoInfo),
            if (widget.overlayBuilder != null)
              widget.overlayBuilder!(context, widget.videoInfo),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedCenterPlayPauseButton() {
    return IgnorePointer(
      ignoring: !_showCenterPlayPause || _isLongPressSpeeding,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        opacity: _showCenterPlayPause && !_isLongPressSpeeding ? 1 : 0,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: _showCenterPlayPause && !_isLongPressSpeeding ? 1 : 0.9,
          child: Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlaybackFromCenter,
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.36),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 38,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLongPressSpeedHint() {
    return IgnorePointer(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        opacity: _showLongPressSpeedHint ? 1 : 0,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          scale: _showLongPressSpeedHint ? 1 : 0.94,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              ),
              child: const Text(
                '2x',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String getPlaybackDebugInfo() {
    final stutterCount = _lastStutterInfo?.stutterCount ?? 0;
    final stutterTotalMs =
        _lastStutterInfo?.totalStutterDuration.inMilliseconds ?? 0;
    final hasUrl = _currentUrl.isNotEmpty;
    final hasController = _controller != null;
    return 'watch debug\n'
        'videoId=${widget.videoInfo.videoId} episodesId=${widget.videoInfo.id} ep=${widget.videoInfo.serialNum}\n'
        'initialUrl=${widget.videoInfo.videoUrl.isEmpty ? 'empty' : 'present'} autoPlay=${widget.autoPlay} canPlay=${widget.videoInfo.isCanPlay}\n'
        'stateMounted=$mounted loading=$_isLoading resolved=$_hasResolvedPlayableUrl\n'
        'hasUrl=$hasUrl hasController=$hasController foreground=$_isForegroundActive\n'
        'prepareMs=${_lastPrepareCostMs ?? -1} firstFrameMs=${_lastFirstFrameCostMs ?? -1}\n'
        'stutterCount=$stutterCount stutterMs=$stutterTotalMs';
  }

  @override
  void dispose() {
    debugPrint('[$_tag][dispose] id=${widget.videoInfo.id}');
    _controlsHideTimer?.cancel();
    _centerPlayPauseTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  Widget _buildLockedPreviewCover() {
    final coverUrl = widget.videoInfo.coverUrl?.trim() ?? '';
    if (coverUrl.isEmpty) {
      return Container(color: Colors.black);
    }

    return Positioned.fill(
      child: Image.network(
        coverUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            Container(color: Colors.black),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLockedWatchNowAction() {
    if (!widget.lockedPreviewMode) {
      return const SizedBox.shrink();
    }

    final hasWatchNow = widget.onLockedWatchNowTap != null;
    final hasWatchAd = widget.onWatchAdToUnlock != null;

    if (!hasWatchNow && !hasWatchAd) {
      return const SizedBox.shrink();
    }

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

  /// 会员购买入口。
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.lockedPreviewMode)
            _buildLockedPreviewCover()
          else if (_controller != null)
            Positioned.fill(
              child: AliPlayerWidget(
                _controller!,
                slotBuilders: {
                  SlotType.playState: (_) => ValueListenableBuilder<bool>(
                    valueListenable: _controller!.isLoadingStateNotifier,
                    builder: (context, isLoadingState, __) {
                      if (!isLoadingState) return const SizedBox.shrink();
                      return const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        ),
                      );
                    },
                  ),
                },
                hiddenSlotElements: {
                  SlotType.topBar: {
                    TopBarElements.back,
                    TopBarElements.title,
                    TopBarElements.download,
                    TopBarElements.snapshot,
                    TopBarElements.pip,
                    TopBarElements.settings,
                  },
                  SlotType.bottomBar: {
                    BottomBarElements.progress,
                    BottomBarElements.fullscreen,
                    BottomBarElements.speed,
                    BottomBarElements.quality,
                    BottomBarElements.subtitle,
                    BottomBarElements.refresh,
                  },
                  SlotType.playControl: {
                    PlayControlElements.doubleTap,
                    PlayControlElements.longPress,
                    PlayControlElements.leftVerticalDrag,
                    PlayControlElements.rightVerticalDrag,
                    PlayControlElements.horizontalDrag,
                  },
                  SlotType.overlays: const <String>{},
                },
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _handleScreenTap,
              onLongPressStart: (_) => _handleLongPressStart(),
              onLongPressEnd: (_) => _handleLongPressEnd(),
              onLongPressCancel: _handleLongPressEnd,
            ),
          ),
          if (_isLoading)
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
          if (widget.lockedPreviewMode)
            Positioned.fill(
              child: IgnorePointer(
                ignoring: true,
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.28)),
              ),
            ),
          _buildAnimatedWatchControls(),
          _buildAnimatedCenterPlayPauseButton(),
          _buildLockedWatchNowAction(),
          _buildLongPressSpeedHint(),
          if (widget.showDebugInfo)
            Positioned(
              left: 12,
              right: 12,
              top: 96,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                  ),
                  child: DefaultTextStyle(
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.35,
                      fontFamily: 'monospace',
                    ),
                    child: Text(getPlaybackDebugInfo()),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WatchShortVideoProgressBar extends StatefulWidget {
  final AliPlayerWidgetController controller;

  const _WatchShortVideoProgressBar({required this.controller});

  @override
  State<_WatchShortVideoProgressBar> createState() =>
      _WatchShortVideoProgressBarState();
}

class _WatchShortVideoProgressBarState
    extends State<_WatchShortVideoProgressBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Duration>(
      valueListenable: widget.controller.totalDurationNotifier,
      builder: (context, totalDuration, _) {
        return ValueListenableBuilder<Duration>(
          valueListenable: widget.controller.currentPositionNotifier,
          builder: (context, currentPosition, __) {
            return ValueListenableBuilder<Duration>(
              valueListenable: widget.controller.bufferedPositionNotifier,
              builder: (context, bufferedPosition, ___) {
                final totalMs = totalDuration.inMilliseconds;
                final currentMs = currentPosition.inMilliseconds.clamp(
                  0,
                  totalMs > 0 ? totalMs : 0,
                );
                final bufferedMs = bufferedPosition.inMilliseconds.clamp(
                  0,
                  totalMs > 0 ? totalMs : 0,
                );
                final progressValue = totalMs > 0 ? currentMs / totalMs : 0.0;
                final bufferValue = totalMs > 0 ? bufferedMs / totalMs : 0.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                            secondaryActiveTrackColor: Colors.white38,
                            inactiveTrackColor: Colors.white24,
                            activeTrackColor: Colors.white,
                            thumbColor: Colors.white,
                            overlayColor: Colors.white24,
                          ),
                          child: Slider(
                            value: _dragValue ?? progressValue,
                            secondaryTrackValue: bufferValue,
                            min: 0,
                            max: 1,
                            onChanged: totalMs > 0
                                ? (value) {
                                    setState(() {
                                      _dragValue = value;
                                    });
                                  }
                                : null,
                            onChangeEnd: totalMs > 0
                                ? (value) {
                                    final seekMs = (value * totalMs).round();
                                    widget.controller.seek(
                                      Duration(milliseconds: seekMs),
                                    );
                                    setState(() {
                                      _dragValue = null;
                                    });
                                  }
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${_formatDuration(Duration(milliseconds: currentMs))} / ${_formatDuration(totalDuration)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 单个播放项组件

import 'dart:async';

import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
import 'package:aliplayer_widget/slot/slot_elements.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../recommend/models/video_info.dart';
import '../recommend/providers/recommend_provider.dart';

/// 单个播放项组件
class ShortVideoItem extends StatefulWidget {
  final VideoInfo videoInfo;
  final bool autoPlay;
  final bool resolvePlayableUrl;
  final Widget Function(BuildContext context, VideoInfo videoInfo)? overlayBuilder;
  final Widget Function(BuildContext context, VideoInfo videoInfo)? topOverlayBuilder;
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
  static const String _tag = 'ShortVideoItem';
  static const int _completedStateCode = FlutterAvpdef.completion;

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
  bool _showCenterPlayPause = false;
  bool _didNotifyCompletion = false;
  Timer? _centerPlayPauseTimer;

  AliPlayerWidgetController? get controller => _controller;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoInfo.videoUrl;
    _hasResolvedPlayableUrl = !widget.resolvePlayableUrl || _currentUrl.isNotEmpty;
    _isForegroundActive = widget.autoPlay;
    _isLoading = widget.autoPlay && _currentUrl.isNotEmpty;

    debugPrint(
      '[$_tag][initState] id=${widget.videoInfo.id} autoPlay=${widget.autoPlay} resolve=${widget.resolvePlayableUrl}',
    );

    if (_currentUrl.isNotEmpty && widget.autoPlay) {
      _configurePlayer(_currentUrl, autoPlay: true);
    }

    if (widget.resolvePlayableUrl && _currentUrl.isEmpty) {
      scheduleMicrotask(() => prefetchPlayableUrl(playIfReady: widget.autoPlay));
    }
  }

  void _configurePlayer(String url, {required bool autoPlay}) {
    final hadController = _controller != null;
    if (!hadController) {
      _controller = AliPlayerWidgetController(context);
      _controller!.playStateNotifier.addListener(_handlePlayStateChanged);
      _controller!.strategyManager
        ..register(FirstFrameStrategy(
          onPrepared: (cost) {
            _lastPrepareCostMs = cost.inMilliseconds;
            debugPrint(
              '[$_tag][strategy][prepared] id=${widget.videoInfo.id} costMs=$_lastPrepareCostMs url=$url',
            );
          },
          onFirstFrame: (cost) {
            _lastFirstFrameCostMs = cost.inMilliseconds;
            debugPrint(
              '[$_tag][strategy][firstFrame] id=${widget.videoInfo.id} costMs=$_lastFirstFrameCostMs url=$url',
            );
            if (!mounted || !_hasPlayer) return;
            setState(() {
              _isLoading = false;
            });
          },
        ))
        ..register(StutterDetectStrategy(
          onStutterDetected: (info) {
            _lastStutterInfo = info;
            debugPrint(
              '[$_tag][strategy][stutter] id=${widget.videoInfo.id} count=${info.stutterCount} totalMs=${info.totalStutterDuration.inMilliseconds} rate=${info.stutterRate.toStringAsFixed(4)} url=$url',
            );
          },
        ));
    }
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
    if (playState == _completedStateCode) {
      if (_didNotifyCompletion) return;
      _didNotifyCompletion = true;
      widget.onCompleted?.call();
      return;
    }
    _didNotifyCompletion = false;
  }

  @override
  void didUpdateWidget(covariant ShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.autoPlay != oldWidget.autoPlay) {
      if (widget.autoPlay) {
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
      if (widget.autoPlay) {
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

    if (!widget.resolvePlayableUrl) {
      _hasResolvedPlayableUrl = true;
      if (playIfReady && _isForegroundActive) {
        resume();
      }
      return;
    }

    if (_hasResolvedPlayableUrl && _currentUrl.isNotEmpty) {
      if (playIfReady && _isForegroundActive) {
        resume();
      }
      return;
    }

    if (widget.videoInfo.videoId <= 0 || widget.videoInfo.id <= 0) {
      _hasResolvedPlayableUrl = true;
      return;
    }

    _isFetchingPlayableUrl = true;
    try {
      final container = ProviderScope.containerOf(context);
      final repo = container.read(recommendRepositoryProvider);
      final result = await repo.fetchEpisodeUrl(
        videoId: widget.videoInfo.videoId,
        episodesId: widget.videoInfo.id,
      );

      if (!mounted) return;

      if (result != null && result.videoUrl.isNotEmpty) {
        _currentUrl = result.videoUrl;
        _hasResolvedPlayableUrl = true;
        if (playIfReady || (widget.autoPlay && _isForegroundActive)) {
          _configurePlayer(_currentUrl, autoPlay: true);
        } else if (_controller != null) {
          _controller!.pause();
        }
        setState(() {
          _isLoading = false;
        });
      }
    } catch (_) {
    } finally {
      _isFetchingPlayableUrl = false;
    }
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
    _togglePlaybackFromCenter();
  }

  Widget _buildAnimatedCenterPlayPauseButton() {
    return IgnorePointer(
      ignoring: !_showCenterPlayPause,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        opacity: _showCenterPlayPause ? 1 : 0,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          scale: _showCenterPlayPause ? 1 : 0.9,
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

  void _togglePlaybackFromCenter() {
    if (_isPlaying) {
      pause();
    } else {
      resume();
    }
    _showCenterPlayPauseOverlay();
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
    _isForegroundActive = true;
    _isPlaying = true;
    if (_currentUrl.isEmpty) {
      scheduleMicrotask(() => prefetchPlayableUrl(playIfReady: true));
      return;
    }

    if (_controller == null) {
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

  String getPlaybackDebugInfo() {
    final stutterCount = _lastStutterInfo?.stutterCount ?? 0;
    final stutterTotalMs =
        _lastStutterInfo?.totalStutterDuration.inMilliseconds ?? 0;
    return 'loading=$_isLoading resolved=$_hasResolvedPlayableUrl prepareMs=${_lastPrepareCostMs ?? -1} firstFrameMs=${_lastFirstFrameCostMs ?? -1} stutterCount=$stutterCount stutterMs=$stutterTotalMs';
  }

  @override
  void dispose() {
    debugPrint('[$_tag][dispose] id=${widget.videoInfo.id}');
    _centerPlayPauseTimer?.cancel();
    _disposeController();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_controller != null)
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
          if (_controller != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: _ShortVideoProgressBar(controller: _controller!),
            ),
          if (widget.topOverlayBuilder != null)
            widget.topOverlayBuilder!(context, widget.videoInfo),
          if (widget.overlayBuilder != null)
            widget.overlayBuilder!(context, widget.videoInfo),
          _buildAnimatedCenterPlayPauseButton(),
        ],
      ),
    );
  }
}

class _ShortVideoProgressBar extends StatefulWidget {
  final AliPlayerWidgetController controller;

  const _ShortVideoProgressBar({required this.controller});

  @override
  State<_ShortVideoProgressBar> createState() => _ShortVideoProgressBarState();
}

class _ShortVideoProgressBarState extends State<_ShortVideoProgressBar> {
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
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

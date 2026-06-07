// Brief: Single video item widget for immersive short video list playback.
//
// Mirrors the official aliplayer_widget example ShortVideoItem.
// Uses AliPlayerWidget with SceneType.listPlayer for seamless list playback
// and preloading via AliPlayerPreload.

import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
import 'package:aliplayer_widget/slot/slot_elements.dart';
import 'package:flutter/material.dart';

import '../models/video_info.dart';

/// Single video item widget for the immersive short video list.
///
/// Uses AliPlayerWidget (SceneType.listPlayer) for video playback.
/// Preloading is handled separately by AliPlayerPreload.
///
/// Mirrors Java: each AUIVideoItemView in the AUIVideoEpisodeController's list.
class ShortVideoItem extends StatefulWidget {
  /// Video data source
  final VideoInfo videoInfo;

  /// Whether to auto-play when mounted
  /// Only the current page should have autoPlay=true
  final bool autoPlay;

  const ShortVideoItem({
    super.key,
    required this.videoInfo,
    this.autoPlay = false,
  });

  @override
  State<ShortVideoItem> createState() => ShortVideoItemState();
}

class ShortVideoItemState extends State<ShortVideoItem> {
  static const String _tag = 'ShortVideoItem';

  late final AliPlayerWidgetController _controller;

  AliPlayerWidgetController get controller => _controller;

  @override
  void initState() {
    super.initState();
    debugPrint('[$_tag][initState] id=${widget.videoInfo.id} autoPlay=${widget.autoPlay}');

    _controller = AliPlayerWidgetController(context);

    final videoSource = VideoSourceFactory.createUrlSource(widget.videoInfo.videoUrl);
    final data = AliPlayerWidgetData(
      sceneType: SceneType.listPlayer,
      videoSource: videoSource,
      coverUrl: widget.videoInfo.coverUrl ?? '',
      autoPlay: widget.autoPlay,
      onPlayerConfig: (_) {},
    );
    _controller.configure(data);
  }

  @override
  void dispose() {
    debugPrint('[$_tag][dispose] id=${widget.videoInfo.id}');
    _controller.destroy();
    super.dispose();
  }

  /// Pause video playback
  /// Mirrors Java: aliListPlayer.pause()
  void pause() {
    debugPrint('[$_tag][pause] id=${widget.videoInfo.id}');
    _controller.pause();
  }

  /// Resume video playback
  /// Mirrors Java: aliListPlayer.start()
  void resume() {
    debugPrint('[$_tag][resume] id=${widget.videoInfo.id}');
    _controller.play();
  }

  /// Stop video playback and release resources
  /// Mirrors Java: aliListPlayer.stop()
  void stop() {
    debugPrint('[$_tag][stop] id=${widget.videoInfo.id}');
    _controller.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AliPlayerWidget(
            _controller,
            slotBuilders: {
              SlotType.overlays: (context) => _buildRightSideActionsOverlay(context),
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
            },
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: _ShortVideoProgressBar(controller: _controller),
          ),
        ],
      ),
    );
  }

  /// Build right-side action buttons overlay
  /// Mirrors Java: right side action buttons in AUIVideoItemView
  Widget _buildRightSideActionsOverlay(BuildContext context) {
    return PositionedDirectional(
      end: 12,
      bottom: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildActionButton(
            icon: Icons.favorite_border,
            label: 'Like',
            onTap: () {
              // TODO: implement like functionality
            },
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.comment_outlined,
            label: 'Comment',
            onTap: () {
              // TODO: implement comment functionality
            },
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.share_outlined,
            label: 'Share',
            onTap: () {
              // TODO: implement share functionality
            },
          ),
        ],
      ),
    );
  }

  /// Build a single action button
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
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

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
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

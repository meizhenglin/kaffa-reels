// Brief: Single video item widget for immersive short video list playback.
//
// Mirrors the official aliplayer_widget example ShortVideoItem.
// Uses AliPlayerWidget with SceneType.listPlayer for seamless list playback
// and preloading via AliPlayerPreload.

import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
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

  /// Player widget controller
  /// AliPlayerWidget internally uses AliListPlayer when SceneType.listPlayer is set
  late final AliPlayerWidgetController _controller;

  @override
  void initState() {
    super.initState();
    debugPrint('[$_tag][initState] id=${widget.videoInfo.id} autoPlay=${widget.autoPlay}');

    // Initialize player controller
    _controller = AliPlayerWidgetController(context);

    // Configure with list player scene
    // Mirrors Java: AliListPlayer with list episode management
    final videoSource = VideoSourceFactory.createUrlSource(widget.videoInfo.videoUrl);
    final data = AliPlayerWidgetData(
      sceneType: SceneType.listPlayer,
      videoSource: videoSource,
      coverUrl: widget.videoInfo.coverUrl ?? '',
      autoPlay: widget.autoPlay,
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
      child: AliPlayerWidget(
        _controller,
        slotBuilders: {
          // Right-side action buttons overlay
          // Mirrors Java: right action bar (like, comment, share)
          SlotType.overlays: (context) => _buildRightSideActionsOverlay(context),
        },
      ),
    );
  }

  /// Build right-side action buttons overlay
  /// Mirrors Java: right side action buttons in AUIVideoItemView
  Widget _buildRightSideActionsOverlay(BuildContext context) {
    return Positioned(
      right: 12,
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

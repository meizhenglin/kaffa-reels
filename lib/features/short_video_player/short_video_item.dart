// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 单个播放项组件

import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
import 'package:flutter/material.dart';
import 'package:short_video_player/video_info.dart';

/// 单个播放项组件
class ShortVideoItem extends StatefulWidget {
  final VideoInfo videoInfo;
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
  static const String _tag = "ShortVideoItem";
  late AliPlayerWidgetController _controller;

  @override
  void initState() {
    super.initState();
    debugPrint("[$_tag][lifecycle][initState]: ${widget.videoInfo.id}");

    _controller = AliPlayerWidgetController(context);

    final videoSource = VideoSourceFactory.createUrlSource(
      widget.videoInfo.videoUrl,
    );
    final data = AliPlayerWidgetData(
      sceneType: SceneType.listPlayer,
      videoSource: videoSource,
      coverUrl: widget.videoInfo.coverUrl,
      autoPlay: widget.autoPlay,
    );
    _controller.configure(data);
  }

  @override
  void dispose() {
    debugPrint("[$_tag][lifecycle][dispose]: ${widget.videoInfo.id}");
    _controller.destroy();
    super.dispose();
  }

  void pause() {
    debugPrint("[$_tag][paused]: ${widget.videoInfo.id}");
    _controller.pause();
  }

  void resume() {
    debugPrint("[$_tag][resumed]: ${widget.videoInfo.id}");
    _controller.play();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        AliPlayerWidget(
          _controller,
          slotBuilders: {
            SlotType.overlays: (context) => _buildRightSideActionsOverlay(context),
          },
          hiddenSlotElements: {
            SlotType.topBar: {'back', 'snapshot', 'settings'},
          },
        ),
      ],
    );
  }

  // Widget _buildTopBar(BuildContext context) {
  //   return Positioned(
  //     top: 0,
  //     left: 0,
  //     right: 0,
  //     child: Container(
  //       padding: EdgeInsets.only(
  //         top: MediaQuery.paddingOf(context).top + 8,
  //         left: 8,
  //         right: 8,
  //         bottom: 12,
  //       ),
  //       decoration: const BoxDecoration(
  //         gradient: LinearGradient(
  //           begin: Alignment.topCenter,
  //           end: Alignment.bottomCenter,
  //           colors: [Colors.black54, Colors.transparent],
  //         ),
  //       ),
  //       child: Row(
  //         children: [
  //           Expanded(
  //             child: Text(
  //               'EP.${widget.videoInfo.id}',
  //               style: const TextStyle(
  //                 color: Colors.white,
  //                 fontSize: 16,
  //                 fontWeight: FontWeight.w600,
  //               ),
  //               maxLines: 1,
  //               overflow: TextOverflow.ellipsis,
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _buildRightSideActionsOverlay(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildActionButton(
            icon: Icons.favorite_border,
            label: '点赞',
            onTap: () {},
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.comment_outlined,
            label: '评论',
            onTap: () {},
          ),
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.share_outlined,
            label: '分享',
            onTap: () {},
          ),
        ],
      ),
    );
  }

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
              color: Colors.black.withOpacity(0.3),
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

// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 单个播放项组件

import 'dart:async';
import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/video_info.dart';
import '../providers/recommend_provider.dart';

/// 单个播放项组件
/// 可选 overlayBuilder 用于在播放器上叠加详情页专属 UI
class ShortVideoItem extends StatefulWidget {
  const ShortVideoItem({
    super.key,
    required this.videoInfo,
    this.autoPlay = false,
    /// 叠加层 builder，传入后替换默认右侧操作按钮
    this.overlayBuilder,
  });

  final VideoInfo videoInfo;
  final bool autoPlay;
  final Widget Function(BuildContext context, VideoInfo videoInfo)? overlayBuilder;

  @override
  State<ShortVideoItem> createState() => ShortVideoItemState();
}

class ShortVideoItemState extends State<ShortVideoItem> {
  static const String _tag = "ShortVideoItem";

  late AliPlayerWidgetController _controller;

  /// 当前正在使用的视频 URL
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoInfo.videoUrl;
    debugPrint(
        "[$_tag][initState] id=${widget.videoInfo.id} autoPlay=${widget.autoPlay}");

    _controller = AliPlayerWidgetController(context);

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
  void didUpdateWidget(ShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 视频 URL 变化（来自 getEpisodeInfo 更新）
    if (widget.videoInfo.videoUrl != oldWidget.videoInfo.videoUrl &&
        widget.videoInfo.videoUrl != _currentUrl) {
      _applyNewUrl(widget.videoInfo.videoUrl);
    }
  }

  /// 从父组件调用：滑动后获取实时播放地址并更新播放器
  Future<void> refreshUrl() async {
    if (!mounted) return;
    debugPrint(
        "[$_tag][refreshUrl] id=${widget.videoInfo.id} fetching real URL...");

    try {
      final container = ProviderScope.containerOf(context);
      final repo = container.read(recommendRepositoryProvider);
      final result = await repo.fetchEpisodeUrl(
        videoId: widget.videoInfo.videoId,
        episodesId: widget.videoInfo.id,
      );

      if (!mounted) return;

      if (result != null && result.videoUrl.isNotEmpty) {
        debugPrint(
            "[$_tag][refreshUrl] got URL: ${result.videoUrl} isCanPlay=${result.isCanPlay}");
        if (result.videoUrl != _currentUrl) {
          _applyNewUrl(result.videoUrl);
        }
      } else {
        debugPrint(
            "[$_tag][refreshUrl] no result or empty URL, keep current: $_currentUrl");
      }
    } catch (e) {
      debugPrint("[$_tag][refreshUrl] error: $e");
    }
  }

  void _applyNewUrl(String newUrl) {
    if (newUrl.isEmpty || newUrl == _currentUrl) return;
    debugPrint(
        "[$_tag][applyNewUrl] ${widget.videoInfo.id}: $_currentUrl → $newUrl");

    _controller.stop();
    _controller.destroy();
    _currentUrl = newUrl;

    _controller = AliPlayerWidgetController(context);

    final videoSource = VideoSourceFactory.createUrlSource(newUrl);
    final data = AliPlayerWidgetData(
      sceneType: SceneType.listPlayer,
      videoSource: videoSource,
      coverUrl: widget.videoInfo.coverUrl ?? '',
      autoPlay: widget.autoPlay,
    );
    _controller.configure(data);
  }

  /// 切换到指定集：直接替换当前播放器内容并播放（不重建 widget）
  void switchTo(VideoInfo newInfo) {
    if (!mounted) return;
    debugPrint("[$_tag][switchTo] ${widget.videoInfo.id} → ${newInfo.id} url=${newInfo.videoUrl}");

    _controller.stop();
    _controller.destroy();
    _currentUrl = newInfo.videoUrl;

    _controller = AliPlayerWidgetController(context);

    if (newInfo.videoUrl.isEmpty) return;
    final videoSource = VideoSourceFactory.createUrlSource(newInfo.videoUrl);
    final data = AliPlayerWidgetData(
      sceneType: SceneType.listPlayer,
      videoSource: videoSource,
      coverUrl: newInfo.coverUrl ?? '',
      autoPlay: true,
    );
    _controller.configure(data);
  }

  @override
  void dispose() {
    debugPrint("[$_tag][dispose] id=${widget.videoInfo.id}");
    _controller.stop();
    _controller.destroy();
    super.dispose();
  }

  void pause() {
    debugPrint("[$_tag][pause] id=${widget.videoInfo.id}");
    _controller.pause();
  }

  void resume() {
    debugPrint("[$_tag][resume] id=${widget.videoInfo.id}");
    _controller.play();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: widget.overlayBuilder != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                AliPlayerWidget(
                  _controller,
                  slotBuilders: {
                    SlotType.overlays: (context) => const SizedBox.shrink(),
                  },
                  hiddenSlotElements: {
                    SlotType.topBar: {'back', 'snapshot', 'settings'},
                  },
                ),
                widget.overlayBuilder!(context, widget.videoInfo),
              ],
            )
          : _buildPlayWidget(),
    );
  }

  Widget _buildPlayWidget() {
    return AliPlayerWidget(
      _controller,
      slotBuilders: {
        SlotType.overlays: (context) => _buildRightSideActionsOverlay(context),
      },
      hiddenSlotElements: {
        SlotType.topBar: {'back', 'snapshot', 'settings'},
      },
    );
  }

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
          const SizedBox(height: 16),
          _buildActionButton(
            icon: Icons.play_circle_outline,
            label: 'Watch',
            onTap: () => _navigateToPlayer(context),
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

  void _navigateToPlayer(BuildContext context) {
    _controller.pause();
    final info = widget.videoInfo;
    context.push(
      '/detail',
      extra: {
        'url': info.videoUrl,
        'videoUrlOne': info.videoUrlOne,
        'videoUrlTwo': info.videoUrlTwo,
        'title': info.title,
        'dramaId': info.videoId.toString(),
        'currentIndex': info.serialNum > 0 ? info.serialNum - 1 : 0,
        'isVipOnly': false,
      },
    );
  }
}

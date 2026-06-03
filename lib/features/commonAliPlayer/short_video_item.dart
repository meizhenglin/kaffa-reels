// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 单个播放项组件

import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
import 'package:flutter/material.dart';
import '../recommend/models/video_info.dart';

/// 单个播放项组件
class ShortVideoItem extends StatefulWidget {
  /// 视频数据源
  final VideoInfo videoInfo;

  /// 是否自动播放
  final bool autoPlay;

  /// 叠加层 builder，传入后替换默认右侧操作按钮
  final Widget Function(BuildContext context, VideoInfo videoInfo)? overlayBuilder;

  const ShortVideoItem({
    super.key,
    required this.videoInfo,
    this.autoPlay = false,
    this.overlayBuilder,
  });

  @override
  State<ShortVideoItem> createState() => ShortVideoItemState();
}

class ShortVideoItemState extends State<ShortVideoItem> {
  static const String _tag = "ShortVideoItem";

  late AliPlayerWidgetController _controller;

  /// 当前是否处于 loading 状态（用于自定义 loading 遮罩）
  bool _isLoading = false;

  /// loading 状态监听器引用，用于移除
  VoidCallback? _loadingListener;

  /// 当前正在使用的视频 URL
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();

    _currentUrl = widget.videoInfo.videoUrl;
    debugPrint(
        "[$_tag][initState] id=${widget.videoInfo.id} autoPlay=${widget.autoPlay}");

    _controller = AliPlayerWidgetController(context);

    if (_currentUrl.isEmpty) {
      debugPrint("[$_tag] url empty, skip configure");
      return;
    }

    final data = AliPlayerWidgetData(
      sceneType: SceneType.listPlayer,
      videoSource: VideoSourceFactory.createUrlSource(_currentUrl),
      coverUrl: widget.videoInfo.coverUrl ?? '',
      autoPlay: widget.autoPlay,
      onPlayerConfig: (player) async {
        _loadingListener = () {
          if (mounted) {
            setState(() {
              _isLoading = _controller.isLoadingStateNotifier.value;
            });
          }
        };
        _controller.isLoadingStateNotifier.addListener(_loadingListener!);
        debugPrint("[$_tag] onPlayerConfig: listening to isLoadingState");
      },
    );
    _controller.configure(data);
    debugPrint("[$_tag] configured with url=$_currentUrl");
  }

  /// 切换到指定集：直接替换当前播放器内容并播放（不重建 widget）
  void switchTo(VideoInfo newInfo) {
    if (!mounted) return;
    debugPrint(
        "[$_tag][switchTo] ${widget.videoInfo.id} → ${newInfo.id} url=${newInfo.videoUrl}");

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
    debugPrint("[$_tag][lifecycle][dispose]: ${widget.videoInfo.id}");
    if (_loadingListener != null) {
      _controller.isLoadingStateNotifier.removeListener(_loadingListener!);
    }
    _controller.stop();
    _controller.destroy();
    super.dispose();
  }

  /// 暂停播放
  void pause() {
    debugPrint("[$_tag][paused]: ${widget.videoInfo.id}");
    _controller.pause();
  }

  /// 恢复播放
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
            SlotType.topBar: (context) => _buildTopBar(context),
            SlotType.overlays: widget.overlayBuilder != null
                ? (context) => const SizedBox.shrink()
                : (context) => _buildRightSideActionsOverlay(context),
          },
          hiddenSlotElements: {
            SlotType.topBar: {'back', 'snapshot', 'settings'},
          },
        ),
        if (widget.overlayBuilder != null)
          widget.overlayBuilder!(context, widget.videoInfo),
        if (_isLoading)
          Positioned.fill(
            child: Container(
              color: Colors.black38,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 8,
          right: 8,
          bottom: 12,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.videoInfo.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
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
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

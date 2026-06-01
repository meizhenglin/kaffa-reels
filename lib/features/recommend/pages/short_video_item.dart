// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 单个播放项组件

import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

class ShortVideoItemState extends State<ShortVideoItem>
    with WidgetsBindingObserver {
  static const String _tag = "ShortVideoItem";

  AliPlayerWidgetController? _controller;

  VoidCallback? _preparedListener;

  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.videoInfo.videoUrl;
    debugPrint(
        "[$_tag][initState] id=${widget.videoInfo.id} autoPlay=${widget.autoPlay}");

    _controller = AliPlayerWidgetController(context);

    final videoSource = VideoSourceFactory.createUrlSource(_currentUrl);
    final data = AliPlayerWidgetData(
      sceneType: SceneType.listPlayer,
      videoSource: videoSource,
      coverUrl: widget.videoInfo.coverUrl ?? '',
      autoPlay: widget.autoPlay,
    );
    _controller!.configure(data).then((_) {
      debugPrint("[$_tag][configure done] id=${widget.videoInfo.id}");
      if (widget.autoPlay) {
        _schedulePlay();
      }
    });

    if (widget.autoPlay) {
      _subscribePrepared();
    }

    WidgetsBinding.instance.addObserver(this);
  }

  void _subscribePrepared() {
    if (_controller == null) return;
    if (_controller!.isPreparedNotifier.value) {
      _schedulePlay();
      return;
    }

    _preparedListener = () {
      if (!mounted || _controller == null) return;
      if (_controller!.isPreparedNotifier.value) {
        _controller!.isPreparedNotifier.removeListener(_preparedListener!);
        _preparedListener = null;
        debugPrint("[$_tag] isPrepared 变为 true，触发播放");
        _schedulePlay();
      }
    };
    _controller?.isPreparedNotifier.addListener(_preparedListener!);
  }

  void _cancelPreparedListener() {
    if (_preparedListener != null && _controller != null) {
      _controller!.isPreparedNotifier.removeListener(_preparedListener!);
      _preparedListener = null;
    }
  }

  void _schedulePlay() {
    if (!mounted) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      debugPrint("[$_tag][play postFrame] id=${widget.videoInfo.id}");
      _controller?.play();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    debugPrint(
        "[$_tag][AppLifecycleState] state=$state autoPlay=${widget.autoPlay}");
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (widget.autoPlay && _controller != null) {
          _controller!.pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (widget.autoPlay && _controller != null) {
          _controller!.play();
        }
        break;
    }
  }

  @override
  void didUpdateWidget(ShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.autoPlay && !oldWidget.autoPlay) {
      debugPrint("[$_tag] autoPlay: false→true id=${widget.videoInfo.id}");
      _subscribePrepared();
      _schedulePlay();
    }

    if (!widget.autoPlay && oldWidget.autoPlay) {
      debugPrint("[$_tag] autoPlay: true→false id=${widget.videoInfo.id}");
      _cancelPreparedListener();
      _controller?.pause();
    }

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

    _cancelPreparedListener();
    _controller?.stop();
    _currentUrl = newUrl;

    final videoSource = VideoSourceFactory.createUrlSource(newUrl);
    final data = AliPlayerWidgetData(
      sceneType: SceneType.listPlayer,
      videoSource: videoSource,
      coverUrl: widget.videoInfo.coverUrl ?? '',
      autoPlay: widget.autoPlay,
    );
    _controller?.configure(data).then((_) {
      if (mounted && widget.autoPlay) {
        _schedulePlay();
        _subscribePrepared();
      }
    });
  }

  @override
  void dispose() {
    debugPrint("[$_tag][dispose] id=${widget.videoInfo.id}");
    WidgetsBinding.instance.removeObserver(this);
    _cancelPreparedListener();
    _controller?.stop();
    _controller?.destroy();
    super.dispose();
  }

  void pause() {
    debugPrint("[$_tag][pause] id=${widget.videoInfo.id}");
    _controller?.pause();
  }

  void resume() {
    debugPrint("[$_tag][resume] id=${widget.videoInfo.id}");
    _controller?.play();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null) {
      return Container(color: Colors.black);
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: widget.overlayBuilder != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                AliPlayerWidget(
                  _controller!,
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
      _controller!,
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

  void _navigateToPlayer(BuildContext context) async {
    _controller?.pause();

    final info = widget.videoInfo;
    await context.push('/detail', extra: {
      'url': _currentUrl,
      'videoId': info.videoId.toString(),
      'videoUrlOne': info.videoUrlOne,
      'videoUrlTwo': info.videoUrlTwo,
      'title': info.title,
      'dramaId': info.videoId.toString(),
      'currentIndex': info.serialNum > 0 ? info.serialNum - 1 : 0,
      'isVipOnly': false,
      'autoPlay': true,
    });

    if (widget.autoPlay) {
      debugPrint("[$_tag] 从详情页返回，触发恢复播放");
      _subscribePrepared();
    }
  }
}

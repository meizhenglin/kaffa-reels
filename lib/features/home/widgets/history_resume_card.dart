import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/last_watched_provider.dart';

/// 首页底部 Tab 栏上方悬浮的"继续观看"卡片
/// - 固定在距离底部导航栏上方 20pt
/// - 可向左/右动画收缩，收缩后仅显示剧集封面图
/// - 点击进入播放器从上次观看位置继续播放
class HistoryResumeCard extends ConsumerStatefulWidget {
  const HistoryResumeCard({super.key});

  @override
  ConsumerState<HistoryResumeCard> createState() => _HistoryResumeCardState();
}

class _HistoryResumeCardState extends ConsumerState<HistoryResumeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _widthAnimation;
  late Animation<double> _iconRotationAnimation;

  bool _isCollapsed = false;

  static const _cardHeight = 52.0;
  static const _borderRadius = 8.0;
  static const _expandedContentWidth = 200.0; // 内容区宽度（不含封面）
  static const _thumbnailSize = 52.0; // 封面图尺寸 = 卡片高度

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    );
    _widthAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    _iconRotationAnimation = Tween<double>(
      begin: 0,
      end: 0.5,
    ).animate(_widthAnimation);

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _isCollapsed = true);
      } else if (status == AnimationStatus.dismissed) {
        setState(() => _isCollapsed = false);
      }
    });

    Future.microtask(() {
      ref.read(lastWatchedProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleCollapse() {
    if (_controller.isCompleted) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
  }

  void _onTap() {
    final info = ref.read(lastWatchedProvider).info;
    if (info == null) return;

    context.push(
      '/short-video',
      extra: {'videoId': info.videoId},
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lastWatchedProvider);

    if (state.info == null) return const SizedBox.shrink();

    return Positioned(
      left: 12,
      right: 12,
      bottom: 20,
      child: AnimatedBuilder(
        animation: _widthAnimation,
        builder: (context, _) {
          return GestureDetector(
            onTap: _onTap,
            child: Container(
              height: _cardHeight,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF202A46), Color(0xFF392E40)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(_borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _buildThumbnail(state.info!.coverUrl),
                  SizeTransition(
                    axisAlignment: -1,
                    sizeFactor: _widthAnimation,
                    child: SizedBox(
                      width: _expandedContentWidth,
                      child: _buildContent(state.info),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _toggleCollapse,
                    child: SizedBox(
                      width: 32,
                      height: _cardHeight,
                      child: Center(
                        child: RotationTransition(
                          turns: _iconRotationAnimation,
                          child: const Icon(
                            Icons.chevron_right,
                            color: Colors.white60,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildThumbnail(String? coverUrl) {
    return SizedBox(
      width: _thumbnailSize,
      height: _cardHeight,
      child: coverUrl != null && coverUrl.isNotEmpty
          ? Image.network(
              coverUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildThumbnailPlaceholder(),
            )
          : _buildThumbnailPlaceholder(),
    );
  }

  Widget _buildThumbnailPlaceholder() {
    return Container(
      color: const Color(0xFF2A2A40),
      child: const Center(
        child: Icon(Icons.movie_outlined, color: Colors.white54, size: 20),
      ),
    );
  }

  Widget _buildContent(LastWatchedInfo? info) {
    if (info == null) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white54,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            info.videoName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            info.episodeLabel,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(
                Icons.play_circle_outline,
                color: Color(0xFF8F4EFF),
                size: 12,
              ),
              const SizedBox(width: 3),
              const Text(
                'Resume',
                style: TextStyle(
                  color: Color(0xFF8F4EFF),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}

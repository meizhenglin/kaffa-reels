import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../components/preload_network_image.dart';
import '../providers/last_watched_provider.dart';

/// 首页底部 Tab 栏上方悬浮的"继续观看"卡片
///
/// LTR（中文/英文）：
///   右滑卡片 → 卡片右滑+淡出，封面图从右侧淡入
///   左滑封面图 → 封面图左滑+淡出，卡片从右滑入
///   关闭按钮在封面图左侧
///
/// RTL（阿拉伯文）：
///   左滑卡片 → 卡片左滑+淡出，封面图从左侧淡入
///   右滑封面图 → 封面图右滑+淡出，卡片从左滑入
///   关闭按钮在封面图右侧
class HistoryResumeCard extends ConsumerStatefulWidget {
  const HistoryResumeCard({super.key});

  @override
  ConsumerState<HistoryResumeCard> createState() => _HistoryResumeCardState();
}

class _HistoryResumeCardState extends ConsumerState<HistoryResumeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  static const _cardHeight = 52.0;
  static const _borderRadius = 8.0;
  static const _thumbnailSize = 52.0;
  static const _coverWidth = 65.0;
  static const _coverHeight = 92.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    );

    Future.microtask(() {
      ref.read(lastWatchedProvider.notifier).load();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

    final isRtl = Directionality.of(context) == TextDirection.rtl;

    // 卡片展开方向：LTR 右滑展开，RTL 左滑展开
    // 封面图始终出现在卡片原位（卡片的右边缘 / 左边缘）
    final slideDir = isRtl ? -1.0 : 1.0;
    final slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(slideDir * 1.5, 0.0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    final cardOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(_controller);
    final coverOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    // 封面图滑入方向和卡片滑出方向相反，但都从屏幕外开始
    final coverSlideAnimation = Tween<Offset>(
      begin: Offset(slideDir * 2.0, 0.0), // 从屏幕外滑入
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // 滑动手势方向判断
    void handleDragEnd(DragEndDetails details) {
      final velocity = details.primaryVelocity ?? 0;
      if (isRtl) {
        if (velocity < -150) {
          _controller.forward();
        } else if (velocity > 150) {
          _controller.reverse();
        }
      } else {
        if (velocity > 150) {
          _controller.forward();
        } else if (velocity < -150) {
          _controller.reverse();
        }
      }
    }

    return Positioned(
      left: 12,
      right: 12,
      bottom: 20,
      child: SizedBox(
        height: 20 + _coverHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: isRtl ? 0 : null,
              right: isRtl ? null : 0,
              bottom: 20,
              child: FadeTransition(
                opacity: coverOpacity,
                child: SlideTransition(
                  position: coverSlideAnimation,
                  child: _buildCoverCard(state.info, isRtl),
                ),
              ),
            ),
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: slideAnimation,
                child: FadeTransition(
                  opacity: cardOpacity,
                  child: GestureDetector(
                    onTap: _onTap,
                    onHorizontalDragEnd: handleDragEnd,
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
                        textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                        children: [
                          _buildThumbnail(state.info!.coverUrl),
                          Expanded(
                            child: _buildContent(state.info),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverCard(LastWatchedInfo? info, bool isRtl) {
    return SizedBox(
      width: _coverWidth,
      height: _coverHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: _coverWidth,
            height: _coverHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(_borderRadius),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.6),
                width: 2,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_borderRadius - 2),
              child: info != null && info.coverUrl.isNotEmpty
                  ? PreloadNetworkImage(
                      imageUrl: info.coverUrl,
                      preloadAsset: 'assets/images/small_preload_bg.png',
                      borderRadius: BorderRadius.circular(_borderRadius - 2),
                      fit: BoxFit.cover,
                    )
                  : _buildThumbnailPlaceholder(),
            ),
          ),
          Positioned(
            top: -4,
            left: isRtl ? null : -4,
            right: isRtl ? -4 : null,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                ref.read(lastWatchedProvider.notifier).clear();
              },
              child: Image.asset(
                'assets/images/cover_close_icon.png',
                width: 16,
                height: 16,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.close, size: 16, color: Colors.white),
              ),
            ),
          ),
          Center(
            child: Image.asset(
              'assets/images/cover_play_icon.png',
              width: 20,
              height: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(String? coverUrl) {
    return SizedBox(
      width: _thumbnailSize,
      height: _cardHeight,
      child: coverUrl != null && coverUrl.isNotEmpty
          ? PreloadNetworkImage(
              imageUrl: coverUrl,
              preloadAsset: 'assets/images/small_preload_bg.png',
              fit: BoxFit.cover,
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
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            info.videoName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
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
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 2),
          const Row(
            children: [
              Icon(
                Icons.play_circle_outline,
                color: Color(0xFF8F4EFF),
                size: 11,
              ),
              SizedBox(width: 3),
              Text(
                'Resume',
                style: TextStyle(
                  color: Color(0xFF8F4EFF),
                  fontSize: 10,
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

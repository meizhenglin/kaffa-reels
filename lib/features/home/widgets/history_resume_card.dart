import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qahwa_tv/l10n/app_localizations.dart';

import '../../../components/preload_network_image.dart';
import '../providers/last_watched_provider.dart';

/// 首页底部 Tab 栏上方悬浮的"继续观看"卡片
///
/// LTR（中文/英文）：
///   右滑卡片 → 卡片右滑+淡出，封面图在右侧显示
///   左滑封面图 → 封面图左滑+淡出，卡片重新显示
///   关闭按钮在封面图左上角
///
/// RTL（阿拉伯文）：
///   左滑卡片 → 卡片左滑+淡出，封面图在左侧显示
///   右滑封面图 → 封面图右滑+淡出，卡片重新显示
///   关闭按钮在封面图右上角
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
  static const _thumbnailWidth = 32.0;
  static const _thumbnailHeight = 45.0;
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

  Future<void> _onTap() async {
    final info = ref.read(lastWatchedProvider).info;
    if (info == null) return;

    await context.push(
      '/short-video',
      extra: {
        'videoId': info.videoId,
        'initialIndex': info.watchedEpNum > 0 ? info.watchedEpNum - 1 : 0,
        'seedVideo': {
          'id': info.episodesId,
          'videoId': int.tryParse(info.videoId) ?? 0,
          'serialNum': info.watchedEpNum,
          'title': info.videoName,
          'coverUrl': info.coverUrl,
          'totalEpisodes': info.totalEpisodes,
        },
      },
    );
    if (!mounted) return;
    await ref.read(lastWatchedProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lastWatchedProvider);
    final info = state.info;

    if (info == null || !info.hasDisplayableContent) {
      return const SizedBox.shrink();
    }

    final locale = Localizations.localeOf(context);
    final isRtl = locale.languageCode.toLowerCase() == 'ar';
    final continueWatchingText =
        AppLocalizations.of(context).continueWatching;

    // 交互规则：LTR 右滑展开/左滑收起；RTL 左滑展开/右滑收起
    final slideDir = isRtl ? -1.0 : 1.0;
    final cardSideAlignment = isRtl ? Alignment.centerLeft : Alignment.centerRight;
    final slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(slideDir * 1.5, 0.0),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    final cardOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(_controller);
    final coverOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);
    // 封面图滑入方向和卡片滑出方向相反，但都从屏幕外开始
    final coverSlideAnimation = Tween<Offset>(
      begin: Offset(slideDir, 0.0),
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

    return PositionedDirectional(
      start: 12,
      end: 12,
      bottom: 20,
      child: SizedBox(
        height: 20 + _coverHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Align(
                alignment: cardSideAlignment,
                child: GestureDetector(
                  onHorizontalDragEnd: handleDragEnd,
                  child: Directionality(
                    textDirection:
                        isRtl ? TextDirection.rtl : TextDirection.ltr,
                    child: FadeTransition(
                      opacity: coverOpacity,
                      child: SlideTransition(
                        position: coverSlideAnimation,
                        child: _buildCoverCard(info, isRtl),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            PositionedDirectional(
              bottom: 20,
              start: 0,
              end: 0,
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
                        gradient: LinearGradient(
                          colors: const [Color(0xFF202A46), Color(0xFF392E40)],
                          begin: isRtl
                              ? AlignmentDirectional.centerEnd
                              : AlignmentDirectional.centerStart,
                          end: isRtl
                              ? AlignmentDirectional.centerStart
                              : AlignmentDirectional.centerEnd,
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
                      child: Builder(
                        builder: (context) {
                          final thumbnail = Padding(
                            padding: EdgeInsets.only(
                              left: isRtl ? 0 : 4,
                              right: isRtl ? 4 : 0,
                            ),
                            child: _buildThumbnail(info.coverUrl),
                          );

                          final content = Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(
                                left: isRtl ? 8 : 11,
                                right: isRtl ? 11 : 8,
                              ),
                              child: _buildContent(
                                info,
                                continueWatchingText,
                                isRtl ? TextDirection.rtl : TextDirection.ltr,
                              ),
                            ),
                          );

                          final playButton = Padding(
                            padding: EdgeInsets.only(
                              left: isRtl ? 15 : 0,
                              right: isRtl ? 0 : 15,
                            ),
                            child: Image.asset(
                              'assets/images/card_play_icon.png',
                              width: 25,
                              height: 25,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.play_circle_fill,
                                color: Colors.white,
                                size: 25,
                              ),
                            ),
                          );

                          return Row(
                            textDirection:
                                isRtl ? TextDirection.rtl : TextDirection.ltr,
                            children: [
                              thumbnail,
                              content,
                              const SizedBox(width: 12),
                              playButton,
                            ],
                          );
                        },
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        width: _thumbnailWidth,
        height: _thumbnailHeight,
        child: coverUrl != null && coverUrl.isNotEmpty
            ? PreloadNetworkImage(
                imageUrl: coverUrl,
                preloadAsset: 'assets/images/small_preload_bg.png',
                fit: BoxFit.cover,
              )
            : _buildThumbnailPlaceholder(),
      ),
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

  Widget _buildContent(
    LastWatchedInfo? info,
    String continueWatchingText,
    TextDirection textDirection,
  ) {
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

    final isRtl = textDirection == TextDirection.rtl;

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment:
            isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            info.videoName,
            textDirection: textDirection,
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            '$continueWatchingText EP.${info.watchedEpNum}',
            textDirection: textDirection,
            textAlign: isRtl ? TextAlign.right : TextAlign.left,
            style: const TextStyle(
              color: Color(0xFFAEAEAE),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

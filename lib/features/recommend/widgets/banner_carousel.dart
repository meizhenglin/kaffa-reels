import 'dart:ui';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../components/preload_network_image.dart';
import '../../auth/providers/auth_provider.dart';
import '../../home/models/home_card_layout.dart';
import '../../home/providers/last_watched_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../models/banner.dart';
import '../utils/drama_navigation.dart';

/// ============================================================================
/// Banner 轮播图组件
///
/// 【功能说明】
/// 在页面顶部展示推荐/广告内容的轮播图：
/// - 自动轮播（可配置间隔）
/// - 点击跳转到对应短剧
/// - 底部指示器显示当前位置（在图片内部）
/// - 图片上叠加渐变遮罩和标题文字
/// - 播放按钮可跳转到播放器
/// ============================================================================
class BannerCarousel extends ConsumerStatefulWidget {
  const BannerCarousel({
    super.key,
    required this.banners,
    required this.onBannerTap,
    this.height = 180,
    this.autoPlayInterval = const Duration(seconds: 5),
    this.onSearchTap,
  });

  final List<BannerItem> banners;
  final void Function(BannerItem banner) onBannerTap;
  final double height;
  final Duration autoPlayInterval;
  final VoidCallback? onSearchTap;

  @override
  ConsumerState<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends ConsumerState<BannerCarousel> {
  int _currentIndex = 0;

  /// 跳转到播放器，只需传 videoId，播放器自己请求数据
  Future<void> _onPlayTap(BannerItem banner) async {
    final videoId = banner.videoId ?? banner.dramaId;
    if (videoId.isEmpty) return;
    await context.push('/short-video', extra: {'videoId': videoId});
    if (!mounted) return;
    await ref.read(lastWatchedProvider.notifier).load();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final hasRealBanners =
        widget.banners.isNotEmpty && widget.banners.first.id != '__preload__';
    final isLoading = widget.banners.isNotEmpty &&
        widget.banners.length == 1 &&
        widget.banners.first.id == '__preload__';

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          CarouselSlider.builder(
            itemCount: widget.banners.length,
            itemBuilder: (context, index, realIndex) {
              final banner = widget.banners[index];
              return Stack(
                fit: StackFit.expand,
                children: [
                  _BannerImageLayer(
                    imageUrl: banner.imageUrl,
                    isLoading: isLoading,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.65),
                        ],
                      ),
                    ),
                  ),
                  // 底部蒙层
                  PositionedDirectional(
                    bottom: 0,
                    start: 0,
                    end: 0,
                    height: HomeCardLayout.bannerScaled(context, 300),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, const Color(0xFF1F2025)],
                        ),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    start: HomeCardLayout.bannerScaled(context, 38),
                    end: HomeCardLayout.bannerScaled(context, 38),
                    bottom: HomeCardLayout.bannerScaled(context, 49),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BannerTextOverlay(
                          title: banner.videoName ?? banner.title,
                          tags: banner.tags,
                          showExclusiveBadge: index == 0,
                        ),
                        SizedBox(height: HomeCardLayout.bannerScaled(context, 15)),
                        Center(
                          child: _PlayButton(onTap: () => _onPlayTap(banner)),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
            options: CarouselOptions(
              height: widget.height,
              viewportFraction: 1,
              autoPlay: widget.banners.length > 1,
              autoPlayInterval: widget.autoPlayInterval,
              autoPlayAnimationDuration: const Duration(milliseconds: 400),
              autoPlayCurve: Curves.easeInOut,
              onPageChanged: (index, reason) {
                setState(() => _currentIndex = index);
              },
            ),
          ),

          // 顶部渐变遮罩（IgnorePointer，不拦截触摸）
          PositionedDirectional(
            top: 0,
            start: 0,
            end: 0,
            height: topPadding + HomeCardLayout.bannerScaled(context, 60),
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [const Color(0xFF101010), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),

          // 左侧 logo
          PositionedDirectional(
            top: topPadding + HomeCardLayout.bannerScaled(context, 16),
            start: HomeCardLayout.bannerScaled(context, 16),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                // 点击 logo 也跳转到播放器

                _onPlayTap(widget.banners[_currentIndex]);
              },
              child: Image.asset(
                'assets/images/logo.png', // 这里才是真正显示图片的地方
                width: HomeCardLayout.bannerScaled(context, 74),
                height: HomeCardLayout.bannerScaled(context, 32),
              ),
            ),
          ),

          // 右侧按钮组
          PositionedDirectional(
            top: topPadding + HomeCardLayout.bannerScaled(context, 16),
            end: HomeCardLayout.bannerScaled(context, 12),
            child: Row(
              textDirection: Directionality.of(context),
              children: [
                _ActionButton(
                  onTap: () => widget.onSearchTap?.call(),
                  isVip: false,
                  child: Image.asset(
                    'assets/images/search_icon.png',
                    width: HomeCardLayout.bannerScaled(context, 32),
                    height: HomeCardLayout.bannerScaled(context, 32),
                  ),
                ),
                SizedBox(width: HomeCardLayout.bannerScaled(context, 8)),
                _ActionButton(
                  onTap: () {
                    final authState = ref.read(authProvider);
                    final isTourist = authState.user == null || authState.user!.isTourist;
                    if (isTourist) {
                      openMembershipPage(context, ref, showLoginPrompt: false);
                      return;
                    }
                    openMembershipPage(context, ref);
                  },
                  isVip: true,
                  child: Image.asset(
                    'assets/images/vip_icon.png',
                    width: HomeCardLayout.bannerScaled(context, 32),
                    height: HomeCardLayout.bannerScaled(context, 32),
                  ),
                ),
              ],
            ),
          ),

          // 指示器（loading 时隐藏）
          PositionedDirectional(
            start: 0,
            end: 0,
            bottom: HomeCardLayout.bannerScaled(context, 11),
            child: isLoading
                ? const SizedBox.shrink()
                : _buildIndicator(hasRealBanners),
          ),
        ],
      ),
    );
  }

  /// 构建指示器
  Widget _buildIndicator(bool hasRealBanners) {
    final count = hasRealBanners ? widget.banners.length : 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isActive = index == _currentIndex;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: EdgeInsets.symmetric(
            horizontal: HomeCardLayout.bannerScaled(context, 4),
          ),
          width: HomeCardLayout.bannerScaled(context, 7),
          height: HomeCardLayout.bannerScaled(context, 7),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFFFFFFF) : const Color(0xFF777777),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

class _BannerTextOverlay extends StatelessWidget {
  const _BannerTextOverlay({
    required this.title,
    required this.tags,
    required this.showExclusiveBadge,
  });

  final String? title;
  final String? tags;
  final bool showExclusiveBadge;

  @override
  Widget build(BuildContext context) {
    final normalizedTitle = title?.trim();
    final tagItems = (tags ?? '')
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();

    if ((normalizedTitle == null || normalizedTitle.isEmpty) && tagItems.isEmpty && !showExclusiveBadge) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showExclusiveBadge) ...[
          Image.asset(
            'assets/images/exclusive.png',
            width: HomeCardLayout.bannerScaled(context, 103),
            height: HomeCardLayout.bannerScaled(context, 24),
          ),
          SizedBox(height: HomeCardLayout.bannerScaled(context, 15)),
        ],
        if (normalizedTitle != null && normalizedTitle.isNotEmpty)
          Text(
            normalizedTitle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: HomeCardLayout.bannerScaled(context, 25),
              fontWeight: FontWeight.w800,
            ),
          ),
        if (tagItems.isNotEmpty) ...[
          SizedBox(height: HomeCardLayout.bannerScaled(context, 5)),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < tagItems.length; i++) ...[
                if (i > 0) const _BannerTagSeparator(),
                Text(
                  tagItems[i],
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: HomeCardLayout.bannerScaled(context, 13),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _BannerTagSeparator extends StatelessWidget {
  const _BannerTagSeparator();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: HomeCardLayout.bannerScaled(context, 8),
      ),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: SizedBox(
          width: HomeCardLayout.bannerScaled(context, 3),
          height: HomeCardLayout.bannerScaled(context, 3),
        ),
      ),
    );
  }
}

/// 播放按钮组件
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: HomeCardLayout.bannerScaled(context, 164),
        height: HomeCardLayout.bannerScaled(context, 45),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(
            HomeCardLayout.bannerScaled(context, 30),
          ),
          border: Border.all(
            color: const Color(0xFF9843FF),
            width: HomeCardLayout.bannerScaled(context, 3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          children: [
            // const Icon(
            //   Icons.play_arrow_rounded,
            //   color: Color(0xFF8F4EFF),
            //   size: 28,
            // ),
            Image(
              image: const AssetImage('assets/images/action_icon.png'),
              width: HomeCardLayout.bannerScaled(context, 22),
              height: HomeCardLayout.bannerScaled(context, 22),
            ),
            SizedBox(width: HomeCardLayout.bannerScaled(context, 9)),
            Text(
              'Watch Now',
              style: TextStyle(
                color: const Color(0xFF8F4EFF),
                fontSize: HomeCardLayout.bannerScaled(context, 16),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 操作按钮组件
class _BannerImageLayer extends StatelessWidget {
  const _BannerImageLayer({
    required this.imageUrl,
    required this.isLoading,
  });

  final String imageUrl;
  final bool isLoading;

  /// 是否是本地资源（占位图）
  bool get _isLocalAsset => imageUrl.startsWith('assets/') || imageUrl.isEmpty;

  @override
  Widget build(BuildContext context) {
    if (isLoading || _isLocalAsset) {
      return _buildPreloadBackground();
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: Stack(
        key: ValueKey(imageUrl),
        fit: StackFit.expand,
        children: [
          _BlurredBannerBackground(imageUrl: imageUrl),
          ColoredBox(color: Colors.black.withValues(alpha: 0.18)),
          Center(
            child: PreloadNetworkImage(
              imageUrl: imageUrl,
              preloadAsset: 'assets/images/banner_preload_bg.png',
              width: double.infinity,
              height: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreloadBackground() {
    return ColoredBox(
      color: const Color(0xFF1F2025),
      child: Center(
        child: Image.asset(
          'assets/images/banner_preload_bg.png',
          fit: BoxFit.contain,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
        ),
      ),
    );
  }
}

class _BlurredBannerBackground extends StatelessWidget {
  const _BlurredBannerBackground({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.network(
          imageUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: Color(0xFF1F2025),
          ),
        ),
        ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: HomeCardLayout.bannerScaled(context, 18),
              sigmaY: HomeCardLayout.bannerScaled(context, 18),
            ),
            child: Container(
              color: Colors.black.withValues(alpha: 0.18),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.child,
    required this.onTap,
    required this.isVip,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool isVip;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.translucent,
      child: SizedBox(
        width: HomeCardLayout.bannerScaled(context, 32),
        height: HomeCardLayout.bannerScaled(context, 32),
        child: child,
      ),
    );
  }
}

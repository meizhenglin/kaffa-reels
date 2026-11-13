import 'dart:async';

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../components/preload_network_image.dart';
import '../../auth/providers/auth_provider.dart';
import '../../home/models/home_card_layout.dart';
import '../../home/providers/last_watched_provider.dart';
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

  /// 自己控制轮播，不用 carousel_slider 的 autoPlay。
  ///
  /// 【为什么必须自己管】carousel_slider 5.1.2 的自动轮播 timer 里是这么写的
  /// （carousel_slider.dart:129-140）：
  ///
  ///     Timer.periodic(..., (_) {
  ///       if (!mounted) { clearTimer(); return; }
  ///       final route = ModalRoute.of(context);   // ← 问题在这
  ///       ...
  ///     });
  ///
  /// `mounted` 对「已 deactivate 但还没 unmount」的元素仍然为 true，
  /// 而 deactivate 之后调用 `ModalRoute.of(context)` 会触发框架断言
  /// （framework.dart:5049 "Looking up a deactivated widget's ancestor is
  /// unsafe"），紧接着把元素树搞成不一致状态，连锁抛出
  /// framework.dart:6417 / 6268 的断言 —— 也就是线上那块红屏。
  /// 触发场景：切 tab / MediaQuery 尺寸变化（DevTools 设备工具栏）时
  /// banner 被移出树，而 timer 恰好在这时 tick。
  ///
  /// 现在：包自带 autoPlay 关闭，由 [_autoPlayTimer] 驱动，
  /// 并在 deactivate() 里第一时间取消 —— 元素一离开树就没有 timer 了。
  final CarouselSliderController _carouselController = CarouselSliderController();
  Timer? _autoPlayTimer;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  @override
  void didUpdateWidget(covariant BannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banners.length != widget.banners.length ||
        oldWidget.autoPlayInterval != widget.autoPlayInterval) {
      if (_currentIndex >= widget.banners.length) {
        _currentIndex = 0;
      }
      _startAutoPlay();
    }
  }

  @override
  void deactivate() {
    // 关键：元素一旦离开树就先停表，避免在 deactivate 状态下操作控制器。
    _stopAutoPlay();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _startAutoPlay();
  }

  @override
  void dispose() {
    _stopAutoPlay();
    super.dispose();
  }

  void _startAutoPlay() {
    _stopAutoPlay();
    if (widget.banners.length <= 1) return;
    _autoPlayTimer = Timer.periodic(widget.autoPlayInterval, (_) => _goNext());
  }

  void _stopAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
  }

  Future<void> _goNext() async {
    if (!mounted) return;
    if (!_carouselController.ready) return;
    try {
      await _carouselController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } catch (_) {
      // 动画途中元素被移除（切 tab / 路由变化）时忽略；
      // 下一次 activate 会重新启动定时器。
    }
  }

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
            carouselController: _carouselController,
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
              // 必须 false：包内的自动轮播会在 deactivate 后调用
              // ModalRoute.of(context)，引发红屏断言。改由 _autoPlayTimer 驱动。
              autoPlay: false,
              autoPlayInterval: widget.autoPlayInterval,
              autoPlayAnimationDuration: const Duration(milliseconds: 400),
              autoPlayCurve: Curves.easeInOut,
              onPageChanged: (index, reason) {
                if (!mounted) return;
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
                if (widget.banners.isEmpty) return;
                final index = _currentIndex < widget.banners.length
                    ? _currentIndex
                    : widget.banners.length - 1;
                _onPlayTap(widget.banners[index]);
              },
              child: Image.asset(
                'assets/images/logo_new.png', // 这里才是真正显示图片的地方
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

    return Stack(
      fit: StackFit.expand,
      children: [
        // 背景层：使用 ColorFiltered + 低透明度彩色实现模糊感，
        // 不再单独下载一次原图做 blur，避免重复加载。
        _BlurredBannerBackground(imageUrl: imageUrl),
        // 主图层
        PreloadNetworkImage(
          imageUrl: imageUrl,
          preloadAsset: 'assets/images/banner_preload_bg.png',
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.cover,
        ),
      ],
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

/// 背景模糊层：使用 ColorFiltered 模拟暖色调模糊感，
/// 避免通过 Image.network 重复下载原图。
class _BlurredBannerBackground extends StatelessWidget {
  const _BlurredBannerBackground({required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(
        const Color(0xFF1A1A2E).withValues(alpha: 0.45),
        BlendMode.darken,
      ),
      child: Image.network(
        imageUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        // 仅在网络不佳时显示占位色
        errorBuilder: (_, __, ___) => const ColoredBox(
          color: Color(0xFF1F2025),
        ),
      ),
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

import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/banner.dart';

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
  void _onPlayTap(BannerItem banner) {
    final videoId = banner.videoId ?? banner.dramaId;
    if (videoId == null || videoId.isEmpty) return;
    context.push('/short-video', extra: {'videoId': videoId});
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
                  // 图片内容：loading 时静态预加载图，真实数据时带淡入动画
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: isLoading
                        ? Image.asset(
                            'assets/images/banner_preload_bg.png',
                            key: const ValueKey('preload'),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                          )
                        :                           Image.network(
                            key: ValueKey(banner.id),
                            banner.imageUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            loadingBuilder: (_, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              // 真实图片加载中：叠在预加载图上面，淡入效果
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.asset(
                                    'assets/images/banner_preload_bg.png',
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    height: double.infinity,
                                  ),
                                  AnimatedOpacity(
                                    opacity: 1.0,
                                    duration: const Duration(milliseconds: 300),
                                    child: child,
                                  ),
                                ],
                              );
                            },
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.grey.shade300,
                              child: const Icon(Icons.image_not_supported),
                            ),
                          ),
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
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: 300,
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
                  // 播放按钮
                  Positioned(
                    bottom: 49,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: _PlayButton(onTap: () => _onPlayTap(banner)),
                    ),
                  ),
                  // 标题
                  if (banner.title != null)
                    PositionedDirectional(
                      bottom: 121,
                      start: 0,
                      end: 0, // 同时设置 start 和 end 为 0 实现横向拉伸居中
                      child: Center(
                        child: Text(
                          banner.title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + 60,
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
          Positioned(
            top: topPadding + 16,
            left: 16,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                // 点击 logo 也跳转到播放器

                _onPlayTap(widget.banners[_currentIndex]);
              },
              child: Image.asset(
                'assets/images/logo.png', // 这里才是真正显示图片的地方
                width: 74,
                height: 32,
              ),
            ),
          ),

          // 右侧按钮组
          Positioned(
            top: topPadding + 16,
            right: 12,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              child: Row(
                children: [ 
                  _ActionButton(
                    // icon: Icons.search_rounded,
                    onTap: () => widget.onSearchTap?.call(),
                    isVip: false,
                    // child:Image(image:  AssetImage('assets/images/search.png'),width: 24,height: 24,),
                    child:Image.asset('assets/images/search_icon.png',width: 32,height: 32,)

                  ),
                  const SizedBox(width: 8),
                  _ActionButton(
                    onTap: () => context.push('/membership'),
                    isVip: true,
                    child: Image.asset('assets/images/vip_icon.png', width: 32, height: 32),

                  ),
                ],
              ),
            ),
          ),

          // 指示器（loading 时隐藏）
          Positioned(
            left: 0,
            right: 0,
            bottom: 11,
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
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFFFFFFFF) : const Color(0xFF777777),
            shape: BoxShape.circle,
          ),
        );
      }),
    );
  }
}

/// 播放按钮组件
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 164,
        height: 45,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xFF9843FF), width: 3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // const Icon(
            //   Icons.play_arrow_rounded,
            //   color: Color(0xFF8F4EFF),
            //   size: 28,
            // ),
            const Image(
              image: AssetImage('assets/images/action_icon.png'),
              width: 22,
              height: 22,
            ),
            const SizedBox(width: 9),
            Text(
              'Watch Now',
              style: TextStyle(
                color: const Color(0xFF8F4EFF),
                fontSize: 16,
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
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    // required this.icon,
    required this.child,

    required this.onTap,
    required this.isVip,
  });

  // final IconData icon;
  final Widget child;
  final VoidCallback onTap;
  final bool isVip;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // child: Container(
      //   // padding: const EdgeInsets.all(10),
      //   decoration: BoxDecoration(
      //     color: isVip
      //         ? Colors.amber.withValues(alpha: 0.9)
      //         : Colors.black.withValues(alpha: 0.3),
      //     borderRadius: BorderRadius.circular(12),
      //   ),
      //   // child: Icon(icon, color: isVip ? Colors.black : Colors.white, size: 24),
      //   child: child,
      // ),
        child: child,

    );
  }
}

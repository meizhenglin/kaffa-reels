import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../home/pages/main_page.dart' show currentTabIndexProvider;
import '../models/game_carousel_item.dart';

/// 游戏轮播图组件 - 无限轮播
class GameCarousel extends ConsumerStatefulWidget {
  const GameCarousel({super.key, required this.items, this.onItemTap});

  final List<GameCarouselItem> items;
  final void Function(GameCarouselItem item)? onItemTap;

  /// 轮播图原始尺寸比例 945*321
  static const double imageAspectRatio = 945 / 321;

  @override
  ConsumerState<GameCarousel> createState() => _GameCarouselState();
}

class _GameCarouselState extends ConsumerState<GameCarousel> {
  late PageController _pageController;
  int _currentIndex = 0;
  Timer? _autoPlayTimer;

  // 初始位置设为中间的大数字，实现伪无限滚动
  static const int _initialPage = 10000;

  /// 游戏 tab 在底部导航中的索引（对应 NavigationConfig.branchPaths[3]）。
  static const int _gamesTabIndex = 3;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialPage);
    _startAutoPlay();

    // 【离屏停表】MainPage 用 StatefulShellRoute.indexedStack，切到其它 tab
    // 时本 State 仍然 mounted、不会触发 deactivate —— 原来的定时器会在
    // 用户看不到的地方每 3 秒播一次 400ms 动画 + setState，纯浪费 CPU/GPU。
    // 现在监听全局 tab 索引：不在游戏 tab 就停表，切回来再恢复。
    ref.listenManual<int>(currentTabIndexProvider, (previous, next) {
      if (next == _gamesTabIndex) {
        _startAutoPlay();
      } else {
        _autoPlayTimer?.cancel();
        _autoPlayTimer = null;
      }
    });
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    if (widget.items.isEmpty) return;
    if (ref.read(currentTabIndexProvider) != _gamesTabIndex) return;
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void didUpdateWidget(covariant GameCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 数据从空到有（异步加载完成）时恢复轮播。
    if (oldWidget.items.isEmpty != widget.items.isEmpty) {
      _startAutoPlay();
    }
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  GameCarouselItem _getItem(int index) {
    return widget.items[index % widget.items.length];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return AspectRatio(
        aspectRatio: GameCarousel.imageAspectRatio,
        child: _buildPlaceholder(),
      );
    }

    return AspectRatio(
      aspectRatio: GameCarousel.imageAspectRatio,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) {
              final item = _getItem(index);
              return AnimatedScale(
                scale: _currentIndex == index ? 1.0 : 0.95,
                duration: const Duration(milliseconds: 200),
                child: _CarouselItem(
                  item: item,
                  onTap: () => widget.onItemTap?.call(item),
                ),
              );
            },
          ),
          PositionedDirectional(
            bottom: 8,
            start: 0,
            end: 0,
            child: _buildIndicator(),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2025),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: Icon(Icons.videogame_asset, size: 48, color: Colors.white38),
      ),
    );
  }

  Widget _buildIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.items.length, (index) {
        final isActive = index == _currentIndex % widget.items.length;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: isActive ? 16 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.white38,
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

class _CarouselItem extends StatelessWidget {
  const _CarouselItem({required this.item, this.onTap});

  final GameCarouselItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildImage(),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.7),
                    ],
                  ),
                ),
              ),
              if (item.title != null && item.title!.isNotEmpty)
                PositionedDirectional(
                  bottom: 12,
                  start: 12,
                  end: 12,
                  child: Text(
                    item.title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (item.imageUrl != null && item.imageUrl!.isNotEmpty) {
      return Image.network(
        item.imageUrl!,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Center(
        child: Icon(Icons.videogame_asset, size: 64, color: Colors.white38),
      ),
    );
  }
}

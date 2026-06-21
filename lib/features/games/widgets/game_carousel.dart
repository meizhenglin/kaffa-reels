import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game_carousel_item.dart';

/// 游戏轮播图组件
class GameCarousel extends ConsumerStatefulWidget {
  const GameCarousel({
    super.key,
    required this.items,
    this.height = 160,
    this.autoPlayInterval = const Duration(seconds: 5),
    this.onItemTap,
  });

  final List<GameCarouselItem> items;
  final double height;
  final Duration autoPlayInterval;
  final void Function(GameCarouselItem item)? onItemTap;

  @override
  ConsumerState<GameCarousel> createState() => _GameCarouselState();
}

class _GameCarouselState extends ConsumerState<GameCarousel> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return SizedBox(
        height: widget.height,
        child: _buildPlaceholder(),
      );
    }

    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          // 轮播图
          CarouselSlider.builder(
            itemCount: widget.items.length,
            itemBuilder: (context, index, realIndex) {
              final item = widget.items[index];
              return _CarouselItem(
                item: item,
                onTap: () => widget.onItemTap?.call(item),
              );
            },
            options: CarouselOptions(
              height: widget.height,
              viewportFraction: 0.9,
              enlargeCenterPage: true,
              enlargeFactor: 0.15,
              autoPlay: widget.items.length > 1,
              autoPlayInterval: widget.autoPlayInterval,
              autoPlayAnimationDuration: const Duration(milliseconds: 400),
              autoPlayCurve: Curves.easeInOut,
              onPageChanged: (index, reason) {
                setState(() => _currentIndex = index);
              },
            ),
          ),
          
          // 指示器
          if (widget.items.length > 1)
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
        child: Icon(
          Icons.videogame_asset,
          size: 48,
          color: Colors.white38,
        ),
      ),
    );
  }

  Widget _buildIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.items.length, (index) {
        final isActive = index == _currentIndex;
        
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
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
  const _CarouselItem({
    required this.item,
    this.onTap,
  });

  final GameCarouselItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
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
              // 背景图
              _buildImage(),
              
              // 渐变遮罩
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
              
              // 标题（如果有）
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
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          return _buildPlaceholder();
        },
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Center(
        child: Icon(
          Icons.videogame_asset,
          size: 64,
          color: Colors.white38,
        ),
      ),
    );
  }
}

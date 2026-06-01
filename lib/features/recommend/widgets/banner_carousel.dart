import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_service.dart';
import '../models/banner.dart';
import '../models/drama.dart';
import '../../recommend/models/video_info.dart';
import '../../player/presentation/player_controller.dart';

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

  /// 跳转到播放器
  Future<void> _onPlayTap(BannerItem banner) async {
    try {
      final videoId = banner.videoId ?? banner.dramaId;

      // 1. 请求剧集目录，获取总集数和集数列表
      final dirResp = await apiServiceProvider.getEpisodesDirectoryByVideoId(videoId: videoId);
      debugPrint('[Banner play] dirResp.isSuccess=${dirResp.isSuccess} data=${dirResp.data}');
      if (!dirResp.isSuccess || dirResp.data == null) return;

      final dirData = dirResp.data as Map<String, dynamic>;
      final videoEpisodes = dirData['videoEpisodes'] as int? ?? 1;

      // 2. 用 videoEpisodes 作为 pageSize 请求所有剧集视频地址
      final playResp = await apiServiceProvider.getVideoListByVideoId(
        videoId: videoId,
        episodesNum: 1,
        pageSize: videoEpisodes,
      );
      debugPrint('[Banner play] playResp.isSuccess=${playResp.isSuccess} data=${playResp.data}');
      if (!playResp.isSuccess) return;

      // 3. 构建 episodesId → 视频地址映射
      final Map<String, Map> playById = {};
      if (playResp.data is List) {
        for (final item in playResp.data as List) {
          if (item is Map) {
            final id = (item['episodesId'] ?? '').toString();
            if (id.isNotEmpty) playById[id] = item;
          }
        }
      }

      // 4. 构造 Drama 对象
      final drama = Drama(
        id: videoId,
        title: dirData['videoName'] as String? ?? banner.bannerEpisodesName ?? '',
        coverUrl: dirData['videoPicture'] as String? ?? banner.imageUrl,
        views: 0,
        rating: 0.0,
        description: '',
        episodeCount: videoEpisodes,
        isVipOnly: dirData['isVip'] == 1,
        videoUrl: null,
        badge: null,
        aspectRatio: 0.72,
      );

      // 4. 构造 EpisodeData 列表
      final episodes = <EpisodeData>[];

      // directory 返回的是 voList[].directoryList[]（嵌套结构），需要展开
      final List<Map> dirItems = [];
      final voList = dirData['voList'] as List? ?? [];
      for (final group in voList) {
        if (group is! Map) continue;
        final directoryList = group['directoryList'] as List? ?? [];
        for (final m in directoryList) {
          if (m is Map) dirItems.add(m);
        }
      }

      for (final m in dirItems) {
        final epId = (m['episodesId'] ?? '').toString();
        final playItem = playById[epId];
        final epNum = m['episodesNum'] as int? ?? 0;
        final url = playItem != null ? (playItem['episodesUrl'] as String? ?? '') : '';
        episodes.add(EpisodeData(
          id: epId,
          title: '${drama.title} EP.$epNum',
          videoUrl: url,
          coverUrl: playItem != null ? (playItem['videoPicture'] as String? ?? drama.coverUrl) : drama.coverUrl,
          isUnlocked: playItem != null ? (playItem['isCanPlay'] as int? ?? 1) == 1 : true,
        ));
      }

      // 6. 跳转阿里云沉浸式播放器
      if (mounted) {
        // 过滤掉没有视频地址的集（避免播放器崩溃）
        final validEpisodes = episodes.where((ep) => ep.videoUrl.isNotEmpty).toList();
        final videoInfos = validEpisodes.asMap().entries.map((e) {
          final ep = e.value;
          return VideoInfo(
            id: e.key + 1,
            videoId: int.tryParse(drama.id) ?? 0,
            videoUrl: ep.videoUrl,
            coverUrl: ep.coverUrl,
            title: ep.title,
            serialNum: e.key + 1,
            isCanPlay: ep.isUnlocked ? 1 : 0,
          );
        }).toList();

        debugPrint('[Banner play] validEpisodes=${validEpisodes.length}, '
            'first url=${validEpisodes.firstOrNull?.videoUrl ?? "null"}');
        // 序列化 VideoInfo 列表通过 extra 传递
        final extraList = videoInfos.map((vi) => vi.toJson()).toList();
        context.push('/short-video', extra: {'episodes': extraList});
      }
    } catch (e) {
      debugPrint('[Banner play] error=$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.banners.isEmpty) {
      return SizedBox(height: widget.height);
    }

    final topPadding = MediaQuery.of(context).padding.top;

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
                  Image.network(
                    banner.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.image_not_supported),
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
                    // icon: Icons.workspace_premium_rounded,

                    onTap: () {},
                    isVip: true,
                    // child:Image(image:  AssetImage('assets/images/search.png'),width: 24,height: 24,),
                    child:Image.asset('assets/images/vip_icon.png',width: 32,height: 32,)

                  ),
                ],
              ),
            ),
          ),

          // 指示器
          Positioned(left: 0, right: 0, bottom: 11, child: _buildIndicator()),
        ],
      ),
    );
  }

  /// 构建指示器
  Widget _buildIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.banners.length, (index) {
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

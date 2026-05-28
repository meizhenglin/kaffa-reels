import 'dart:math';

import '../../../core/constants/app_constants.dart';
import '../models/banner.dart';
import '../models/drama.dart';
import '../models/drama_badge.dart';
import '../models/video_info.dart';

class RecommendMockData {
  RecommendMockData._();

  static final _random = Random();

  static const _covers = [
    'https://fastly.picsum.photos/seed/drama1/400/600',
    'https://fastly.picsum.photos/seed/drama2/400/720',
    'https://fastly.picsum.photos/seed/drama3/400/540',
    'https://fastly.picsum.photos/seed/drama4/400/680',
    'https://fastly.picsum.photos/seed/drama5/400/620',
    'https://fastly.picsum.photos/seed/drama6/400/700',
    'https://fastly.picsum.photos/seed/drama7/400/560',
    'https://fastly.picsum.photos/seed/drama8/400/640',
    'https://fastly.picsum.photos/seed/drama9/400/580',
    'https://fastly.picsum.photos/seed/drama10/400/660',
    'https://fastly.picsum.photos/seed/drama11/400/610',
    'https://fastly.picsum.photos/seed/drama12/400/590',
  ];

  static const _titlesEn = [
    'Desert Love',
    'Cairo Nights',
    'Golden Sands',
    'Royal Secret',
    'Moon over Medina',
    'Heart of Arabia',
    'Silent Promise',
    'Storm & Rose',
    'Hidden Crown',
    'Last Emir',
    'Scarlet Veil',
    'Whispered Oath',
  ];

  static const _titlesAr = [
    'حب الصحراء',
    'ليالي القاهرة',
    'الرمال الذهبية',
    'سر ملكي',
    'قمر فوق المدينة',
    'قلب الجزيرة',
    'وعد صامت',
    'العاصفة والورد',
    'التاج المخفي',
    'الأمير الأخير',
    'الحجاب القرمزي',
    'القسم المهمس',
  ];

  static const List<String> _videoUrls = [
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
    'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8',
  ];

  static List<BannerItem> banners() => [
        BannerItem(
          id: 'b1',
          imageUrl: 'https://fastly.picsum.photos/seed/banner1/800/400',
          dramaId: 'd1',
          title: _titlesEn[0],
        ),
        BannerItem(
          id: 'b2',
          imageUrl: 'https://fastly.picsum.photos/seed/banner2/800/400',
          dramaId: 'd2',
          title: _titlesEn[1],
        ),
        BannerItem(
          id: 'b3',
          imageUrl: 'https://fastly.picsum.photos/seed/banner3/800/400',
          dramaId: 'd3',
          title: _titlesEn[2],
        ),
        BannerItem(
          id: 'b4',
          imageUrl: 'https://fastly.picsum.photos/seed/banner4/800/400',
          dramaId: 'd4',
          title: _titlesEn[3],
        ),
      ];

  static Drama dramaById(String id) {
    final index = int.tryParse(id.replaceAll('d', '')) ?? 1;
    return _buildDrama(index - 1);
  }

  static List<Drama> hotDramas() =>
      List.generate(8, (i) => _buildDrama(i, forceBadge: DramaBadge.hot));

  static List<Drama> allRecommended() =>
      List.generate(20, (i) => _buildDrama(i));

  static List<Drama> recommendedPage(int page, {int pageSize = 6}) {
    final start = (page - 1) * pageSize;
    return List.generate(pageSize, (i) {
      final idx = start + i;
      return _buildDrama(idx % _covers.length);
    });
  }

  /// 生成模拟视频列表（用于 ShortVideoPage 降级）
  static List<VideoInfo> videos() {
    return List.generate(_videoUrls.length, (i) {
      return VideoInfo(
        id: i + 1,
        videoId: i + 1,
        videoUrl: _videoUrls[i % _videoUrls.length],
        serialNum: i + 1,
        longTime: 100,
        collectNum: _random.nextInt(10),
        likeNum: _random.nextInt(20),
        shareNum: _random.nextInt(5),
        isCollect: 0,
        isLike: 0,
        totalEpisodes: 20,
        title: '${_titlesEn[i % _titlesEn.length]} / ${_titlesAr[i % _titlesAr.length]}',
      );
    });
  }

  static Drama _buildDrama(int index, {DramaBadge? forceBadge}) {
    final badges = [DramaBadge.hot, DramaBadge.update, DramaBadge.exclusive];
    final badge = forceBadge ?? badges[index % badges.length];
    final aspectRatios = [0.68, 0.75, 0.62, 0.8, 0.7, 0.65];

    return Drama(
      id: 'd${index + 1}',
      title: '${_titlesEn[index % _titlesEn.length]} / ${_titlesAr[index % _titlesAr.length]}',
      coverUrl: _covers[index % _covers.length],
      views: 12000 + index * 8340,
      rating: 4.0 + (index % 10) / 10,
      description: 'A captivating short drama series set in the Arab world.',
      episodeCount: 12 + index % 20,
      isVipOnly: index % 4 == 0,
      videoUrl: _videoUrls[index % _videoUrls.length],
      badge: badge,
      aspectRatio: aspectRatios[index % aspectRatios.length],
    );
  }
}

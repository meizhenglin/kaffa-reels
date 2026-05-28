import 'dart:math';

import '../models/banner.dart';
import '../models/drama.dart';
import '../models/drama_badge.dart';

/// ============================================================================
/// 全面的阿拉伯短剧模拟数据生成器
///
/// 【功能】为应用提供完整的模拟数据，包括：
/// - 短剧列表（带阿拉伯语/英语标题）
/// - Banner 轮播数据
/// - 分类数据
/// - 搜索建议
/// - 分页支持
/// ============================================================================

class ComprehensiveMockData {
  ComprehensiveMockData._();

  static final Random _random = Random(42);

  // ==================== 封面图片 ====================
  static const List<String> _covers = [
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
    'https://fastly.picsum.photos/seed/drama13/400/630',
    'https://fastly.picsum.photos/seed/drama14/400/570',
    'https://fastly.picsum.photos/seed/drama15/400/650',
    'https://fastly.picsum.photos/seed/drama16/400/600',
  ];

  // ==================== Banner 图片 ====================
  static const List<String> _bannerImages = [
    'https://fastly.picsum.photos/seed/banner1/800/400',
    'https://fastly.picsum.photos/seed/banner2/800/400',
    'https://fastly.picsum.photos/seed/banner3/800/400',
    'https://fastly.picsum.photos/seed/banner4/800/400',
    'https://fastly.picsum.photos/seed/banner5/800/400',
  ];

  // ==================== 阿拉伯短剧数据（30个）====================
  static const List<Map<String, String>> _arabicDramas = [
    // Romance / رومانسي
    {
      'titleEn': 'Desert Rose',
      'titleAr': 'وردة الصحراء',
      'descEn': 'A love story between a desert princess and a commoner.',
      'descAr': 'قصة حب بين أميرة الصحراء وشاب عادي.',
      'category': 'romance',
    },
    {
      'titleEn': 'Forbidden Love',
      'titleAr': 'حب ممنوع',
      'descEn': 'Two souls destined to be apart but bound by love.',
      'descAr': 'روحان destined للابتعاد لكنهما مرتبطان بالحب.',
      'category': 'romance',
    },
    {
      'titleEn': 'Nights in Cairo',
      'titleAr': 'ليالي القاهرة',
      'descEn': 'A modern love story set in the heart of Cairo.',
      'descAr': 'قصة حب عصرية في قلب القاهرة.',
      'category': 'romance',
    },
    {
      'titleEn': 'Love in Exile',
      'titleAr': 'حب في المنفى',
      'descEn': 'A refugee finds unexpected love in a foreign land.',
      'descAr': 'لاجئ يجد حباً غير متوقع في أرض غريبة.',
      'category': 'romance',
    },
    {
      'titleEn': 'The Wait',
      'titleAr': 'الانتظار',
      'descEn': 'A woman waits for her lover to return from war.',
      'descAr': 'امرأة تنتظر عودة حبيبها من الحرب.',
      'category': 'romance',
    },
    // Action / أكشن
    {
      'titleEn': 'The Shadow',
      'titleAr': 'الظل',
      'descEn': 'A spy uncovers a conspiracy that could change everything.',
      'descAr': 'جاسوس يكتشف مؤامرة قد تغير كل شيء.',
      'category': 'action',
    },
    {
      'titleEn': 'Desert Storm',
      'titleAr': 'عاصفة الصحراء',
      'descEn': 'Action-packed adventures in the Arabian desert.',
      'descAr': 'مغامرات مليئة بالحماس في الصحراء العربية.',
      'category': 'action',
    },
    {
      'titleEn': 'The Protector',
      'titleAr': 'الحامي',
      'descEn': 'A bodyguard must protect his charge at all costs.',
      'descAr': 'حارس شخصي يجب أن يحمي موكله بأي ثمن.',
      'category': 'action',
    },
    {
      'titleEn': 'Vengeance',
      'titleAr': 'الانتقام',
      'descEn': 'A man seeks revenge for his family.',
      'descAr': 'رجل يبحث عن الانتقام لعائلته.',
      'category': 'action',
    },
    {
      'titleEn': 'Undercover',
      'titleAr': 'مخبأ',
      'descEn': 'An undercover agent lives a double life.',
      'descAr': 'عميل سري يعيش حياة مزدوجة.',
      'category': 'action',
    },
    // Comedy / كوميديا
    {
      'titleEn': 'The Mix-Up',
      'titleAr': 'الخلط',
      'descEn': 'A hilarious case of mistaken identity.',
      'descAr': 'حالة مضحكة من الخلط في الهوية.',
      'category': 'comedy',
    },
    {
      'titleEn': 'Neighbors',
      'titleAr': 'الجيران',
      'descEn': 'Chaos ensues when new neighbors move in.',
      'descAr': 'يبدأ الفوضى عندما ينتقل جيران جدد.',
      'category': 'comedy',
    },
    {
      'titleEn': 'Office Life',
      'titleAr': 'حياة المكتب',
      'descEn': 'The hilarious daily struggles of office workers.',
      'descAr': 'المعاناة اليومية المضحكة لعمال المكتب.',
      'category': 'comedy',
    },
    {
      'titleEn': 'Wedding Disaster',
      'titleAr': 'كارثة حفل زفاف',
      'descEn': 'Nothing goes right at this wedding.',
      'descAr': 'لا تسير الأمور بشكل صحيح في هذا حفل الزفاف.',
      'category': 'comedy',
    },
    {
      'titleEn': 'The Driver',
      'titleAr': 'السائق',
      'descEn': 'A taxi driver encounters eccentric passengers.',
      'descAr': 'سائق تكسي يلتقي براكب eccentric.',
      'category': 'comedy',
    },
    // Thriller / إثارة
    {
      'titleEn': 'The Secret',
      'titleAr': 'السر',
      'descEn': 'A family secret threatens to destroy everything.',
      'descAr': 'سر عائلي يهدد بتدمير كل شيء.',
      'category': 'thriller',
    },
    {
      'titleEn': 'Dark Night',
      'titleAr': 'ليلة مظلمة',
      'descEn': 'A murder mystery in an old mansion.',
      'descAr': 'لغز جريمة قتل في قصر قديم.',
      'category': 'thriller',
    },
    {
      'titleEn': 'The Witness',
      'titleAr': 'الشاهد',
      'descEn': 'A witness must hide from dangerous criminals.',
      'descAr': 'شاهد يجب أن يختبئ من مجرمين خطرين.',
      'category': 'thriller',
    },
    {
      'titleEn': 'Missing',
      'titleAr': 'مفقود',
      'descEn': 'A mother searches for her missing child.',
      'descAr': 'أم تبحث عن طفلها المفقود.',
      'category': 'thriller',
    },
    {
      'titleEn': 'The Confession',
      'titleAr': 'الاعتراف',
      'descEn': 'A detective unravels a web of lies.',
      'descAr': 'محقق يفكك شبكة من الأكاذيب.',
      'category': 'thriller',
    },
    // Sci-Fi / خيال علمي
    {
      'titleEn': 'Year 2050',
      'titleAr': 'عام 2050',
      'descEn': 'A glimpse into a future Arab civilization.',
      'descAr': 'نظرة على حضارة عربية مستقبلية.',
      'category': 'sci-fi',
    },
    {
      'titleEn': 'The Clone',
      'titleAr': 'النسخة',
      'descEn': 'A man discovers he has a clone.',
      'descAr': 'رجل يكتشف أن لديه نسخة منه.',
      'category': 'sci-fi',
    },
    {
      'titleEn': 'Virtual Love',
      'titleAr': 'حب افتراضي',
      'descEn': 'Can love exist in a virtual world?',
      'descAr': 'هل يمكن أن يوجد الحب في عالم افتراضي؟',
      'category': 'sci-fi',
    },
    // Costume / تاريخي
    {
      'titleEn': 'The Emir',
      'titleAr': 'الأمير',
      'descEn': 'The rise and fall of a young emir.',
      'descAr': 'صعود وسقوط أمير شاب.',
      'category': 'costume',
    },
    {
      'titleEn': 'Palace Intrigue',
      'titleAr': 'مكائد القصر',
      'descEn': 'Political drama in a royal palace.',
      'descAr': 'دراما سياسية في قصر ملكي.',
      'category': 'costume',
    },
    {
      'titleEn': 'The Merchant',
      'titleAr': 'التاجر',
      'descEn': 'A merchant navigates trade routes and politics.',
      'descAr': 'تاجر يتنقل بين طرق التجارة والسياسة.',
      'category': 'costume',
    },
    {
      'titleEn': 'Sword of Honor',
      'titleAr': 'سيف الشرف',
      'descEn': 'A warrior fights for honor and glory.',
      'descAr': 'محارب يقاتل من أجل الشرف والمجد.',
      'category': 'costume',
    },
    // Urban / عصري
    {
      'titleEn': 'Downtown Dubai',
      'titleAr': 'وسط دبي',
      'descEn': 'Life in the fast lane of Dubai.',
      'descAr': 'الحياة في المسار السريع في دبي.',
      'category': 'urban',
    },
    {
      'titleEn': 'The CEO',
      'titleAr': 'الرئيس التنفيذي',
      'descEn': 'A young woman takes over her family business.',
      'descAr': 'شاب takes over her family business.',
      'category': 'urban',
    },
    {
      'titleEn': 'Young and Ambitious',
      'titleAr': 'شاب طموح',
      'descEn': 'A graduate navigates the corporate world.',
      'descAr': 'خريج يتنقل في عالم الشركات.',
      'category': 'urban',
    },
  ];

  // ==================== 测试视频 URL ====================
  // 注意：AliPlayerWidget + listPlayer 内部会同时预加载多个视频，
  // 必须保证这些 URL 都是有效的真实视频地址，否则预加载会 404 导致播放失败。
  // 推荐页分页时每个视频 i % _testVideoUrls.length 会复用这些 URL。
  //
  // TODO: 替换为你后端 API 返回的真实视频 m3u8 地址。
  // 如果后端视频失效，请联系后端确认哪些 videoUrl 仍然有效。
  static const List<String> _testVideoUrls = [
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ];

  // ==================== 生成 Banner ====================
  static List<BannerItem> banners() {
    return List.generate(5, (i) {
      final drama = _buildDrama(i);
      return BannerItem(
        id: 'banner_$i',
        imageUrl: _bannerImages[i % _bannerImages.length],
        dramaId: drama.id,
        title: drama.title.split(' / ').first,
      );
    });
  }

  // ==================== 生成热门短剧 ====================
  static List<Drama> hotDramas() {
    return List.generate(10, (i) {
      final drama = _buildDrama(i);
      return Drama(
        id: 'hot_$i',
        title: drama.title,
        coverUrl: drama.coverUrl,
        views: 50000 + _random.nextInt(100000),
        rating: 4.0 + _random.nextDouble() * 1.5,
        description: drama.description,
        episodeCount: 10 + _random.nextInt(30),
        isVipOnly: i % 4 == 0,
        videoUrl: _testVideoUrls[i % _testVideoUrls.length],
        badge: DramaBadge.hot,
        aspectRatio: 0.72 + _random.nextDouble() * 0.15,
      );
    });
  }

  // ==================== 生成最新更新 ====================
  static List<Drama> newUpdates() {
    return List.generate(8, (i) {
      final drama = _buildDrama(i + 10);
      return Drama(
        id: 'new_$i',
        title: drama.title,
        coverUrl: drama.coverUrl,
        views: 10000 + _random.nextInt(50000),
        rating: 3.5 + _random.nextDouble() * 1.5,
        description: drama.description,
        episodeCount: 5 + _random.nextInt(20),
        isVipOnly: i % 5 == 0,
        videoUrl: _testVideoUrls[i % _testVideoUrls.length],
        badge: DramaBadge.update,
        aspectRatio: 0.72 + _random.nextDouble() * 0.15,
      );
    });
  }

  // ==================== 生成 VIP 专区 ====================
  static List<Drama> vipDramas() {
    return List.generate(6, (i) {
      final drama = _buildDrama(i + 20);
      return Drama(
        id: 'vip_$i',
        title: drama.title,
        coverUrl: drama.coverUrl,
        views: 80000 + _random.nextInt(150000),
        rating: 4.5 + _random.nextDouble() * 1.0,
        description: drama.description,
        episodeCount: 15 + _random.nextInt(25),
        isVipOnly: true,
        videoUrl: _testVideoUrls[i % _testVideoUrls.length],
        badge: DramaBadge.exclusive,
        aspectRatio: 0.72 + _random.nextDouble() * 0.15,
      );
    });
  }

  // ==================== 分页获取推荐 ====================
  static List<Drama> recommendedPage(int page, {int pageSize = 12}) {
    final start = (page - 1) * pageSize;
    return List.generate(pageSize, (i) {
      final index = (start + i) % _arabicDramas.length;
      final drama = _buildDrama(index);
      return Drama(
        id: 'rec_${page}_$i',
        title: drama.title,
        coverUrl: drama.coverUrl,
        views: drama.views + (page * 1000) + (i * 500),
        rating: drama.rating,
        description: drama.description,
        episodeCount: drama.episodeCount,
        isVipOnly: (start + i) % 6 == 0,
        videoUrl: _testVideoUrls[i % _testVideoUrls.length],
        badge: _getBadgeForIndex(start + i),
        aspectRatio: 0.65 + (i % 3) * 0.1,
      );
    });
  }

  // ==================== 根据分类获取 ====================
  static List<Drama> dramasByCategory(String categoryId, {int page = 1, int pageSize = 12}) {
    final filteredDramas = _arabicDramas
        .where((d) => categoryId == 'all' || d['category'] == categoryId)
        .toList();

    return List.generate(pageSize, (i) {
      final dramaIndex = (page - 1) * pageSize + i;
      final sourceDrama = filteredDramas[dramaIndex % filteredDramas.length];
      return _buildDramaFromData(sourceDrama, index: dramaIndex);
    });
  }

  // ==================== 搜索 ====================
  static List<Drama> search(String query, {int page = 1, int pageSize = 12}) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return [];

    final filtered = _arabicDramas.where((d) {
      final titleEn = d['titleEn']!.toLowerCase();
      final titleAr = d['titleAr']!.toLowerCase();
      final descEn = d['descEn']!.toLowerCase();
      final descAr = d['descAr']!.toLowerCase();
      return titleEn.contains(q) ||
          titleAr.contains(q) ||
          descEn.contains(q) ||
          descAr.contains(q);
    }).toList();

    if (filtered.isEmpty) {
      // 如果没有匹配，返回一些随机结果
      return List.generate(pageSize, (i) {
        final index = (page - 1) * pageSize + i;
        return _buildDrama(index);
      });
    }

    return List.generate(pageSize, (i) {
      final dramaIndex = (page - 1) * pageSize + i;
      final sourceDrama = filtered[dramaIndex % filtered.length];
      return _buildDramaFromData(sourceDrama, index: dramaIndex);
    });
  }

  // ==================== 获取单个短剧 ====================
  static Drama dramaById(String id) {
    // 解析 ID 格式
    int index = 0;

    if (id.startsWith('hot_')) {
      index = int.tryParse(id.replaceFirst('hot_', '')) ?? 0;
      return hotDramas()[index % 10];
    } else if (id.startsWith('new_')) {
      index = int.tryParse(id.replaceFirst('new_', '')) ?? 0;
      return newUpdates()[index % 8];
    } else if (id.startsWith('vip_')) {
      index = int.tryParse(id.replaceFirst('vip_', '')) ?? 0;
      return vipDramas()[index % 6];
    } else if (id.startsWith('banner_')) {
      index = int.tryParse(id.replaceFirst('banner_', '')) ?? 0;
      return _buildDrama(index % _arabicDramas.length);
    } else if (id.startsWith('rec_')) {
      // rec_page_index
      final parts = id.split('_');
      if (parts.length >= 3) {
        index = int.tryParse(parts.last) ?? 0;
      }
      return _buildDrama(index % _arabicDramas.length);
    } else {
      // 尝试解析数字 ID
      final numId = int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), ''));
      if (numId != null) {
        index = numId;
      }
    }

    return _buildDrama(index % _arabicDramas.length);
  }

  // ==================== 内部方法 ====================

  static Drama _buildDrama(int index) {
    final data = _arabicDramas[index % _arabicDramas.length];
    return _buildDramaFromData(data, index: index);
  }

  static Drama _buildDramaFromData(Map<String, String> data, {required int index}) {
    final badges = [DramaBadge.hot, DramaBadge.update, DramaBadge.exclusive];
    final aspectRatios = [0.68, 0.72, 0.75, 0.80, 0.65];

    return Drama(
      id: 'drama_$index',
      title: '${data['titleEn']} / ${data['titleAr']}',
      coverUrl: _covers[index % _covers.length],
      views: 10000 + _random.nextInt(200000),
      rating: 3.5 + _random.nextDouble() * 2.0,
      description: '${data['descEn']} / ${data['descAr']}',
      episodeCount: 8 + _random.nextInt(30),
      isVipOnly: index % 5 == 0,
      videoUrl: _testVideoUrls[index % _testVideoUrls.length],
      badge: badges[index % badges.length],
      aspectRatio: aspectRatios[index % aspectRatios.length],
    );
  }

  static DramaBadge _getBadgeForIndex(int index) {
    if (index % 10 == 0) return DramaBadge.hot;
    if (index % 5 == 0) return DramaBadge.update;
    return DramaBadge.exclusive;
  }

  // ==================== 统计信息 ====================
  static int get totalDramas => _arabicDramas.length * 3; // 模拟更多数据

  static Map<String, int> get categoryStats => {
        'all': _arabicDramas.length,
        'romance': _arabicDramas.where((d) => d['category'] == 'romance').length,
        'action': _arabicDramas.where((d) => d['category'] == 'action').length,
        'comedy': _arabicDramas.where((d) => d['category'] == 'comedy').length,
        'thriller': _arabicDramas.where((d) => d['category'] == 'thriller').length,
        'sci-fi': _arabicDramas.where((d) => d['category'] == 'sci-fi').length,
        'costume': _arabicDramas.where((d) => d['category'] == 'costume').length,
        'urban': _arabicDramas.where((d) => d['category'] == 'urban').length,
      };
}

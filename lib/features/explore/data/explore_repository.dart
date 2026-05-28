import '../../recommend/data/comprehensive_mock_data.dart';
import '../../recommend/models/drama.dart';
import '../models/category.dart';

class ExploreRepository {
  Future<List<Category>> fetchCategories() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return _categories;
  }

  Future<({List<Drama> dramas, bool hasMore})> fetchDramasByCategory({
    required String categoryId,
    required int page,
    int pageSize = 12,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final dramas = ComprehensiveMockData.dramasByCategory(
      categoryId,
      page: page,
      pageSize: pageSize,
    );
    return (dramas: dramas, hasMore: page < 10);
  }

  Future<({List<Drama> dramas, bool hasMore})> searchDramas({
    required String query,
    required int page,
    int pageSize = 12,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final dramas = ComprehensiveMockData.search(query, page: page, pageSize: pageSize);
    return (dramas: dramas, hasMore: page < 5 && dramas.isNotEmpty);
  }

  /// 获取热门搜索关键词
  Future<List<String>> fetchHotKeywords({bool isArabic = false}) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return isArabic ? _hotKeywordsAr : _hotKeywordsEn;
  }

  static const List<String> _hotKeywordsAr = [
    'حب',
    'صحراء',
    'القاهرة',
    'غموض',
    'كوميديا',
    'قصر',
    'أمير',
    'انتقام',
  ];

  static const List<String> _hotKeywordsEn = [
    'Love',
    'Desert',
    'Cairo',
    'Mystery',
    'Comedy',
    'Palace',
    'Emir',
    'Revenge',
  ];

  static final List<Category> _categories = [
    const Category(id: 'all', name: 'All', nameEn: 'All', nameAr: 'الكل'),
    const Category(id: 'romance', name: 'Romance', nameEn: 'Romance', nameAr: 'رومانسي'),
    const Category(id: 'action', name: 'Action', nameEn: 'Action', nameAr: 'أكشن'),
    const Category(id: 'comedy', name: 'Comedy', nameEn: 'Comedy', nameAr: 'كوميديا'),
    const Category(id: 'thriller', name: 'Thriller', nameEn: 'Thriller', nameAr: 'إثارة'),
    const Category(id: 'sci-fi', name: 'Sci-Fi', nameEn: 'Sci-Fi', nameAr: 'خيال علمي'),
    const Category(id: 'costume', name: 'Costume', nameEn: 'Costume', nameAr: 'تاريخي'),
    const Category(id: 'urban', name: 'Urban', nameEn: 'Urban', nameAr: 'عصري'),
  ];
}

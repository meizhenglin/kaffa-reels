import '../../recommend/data/comprehensive_mock_data.dart';
import '../../recommend/models/drama.dart';
import '../models/category.dart';

class ExploreMockData {
  ExploreMockData._();

  static const String allCategoryId = 'all';

  static List<Category> categories() => const [
        Category(id: 'all', name: 'All', nameEn: 'All', nameAr: 'الكل'),
        Category(id: 'romance', name: 'Romance', nameEn: 'Romance', nameAr: 'رومانسي'),
        Category(id: 'action', name: 'Action', nameEn: 'Action', nameAr: 'أكشن'),
        Category(id: 'comedy', name: 'Comedy', nameEn: 'Comedy', nameAr: 'كوميديا'),
        Category(id: 'thriller', name: 'Thriller', nameEn: 'Thriller', nameAr: 'إثارة'),
        Category(id: 'sci-fi', name: 'Sci-Fi', nameEn: 'Sci-Fi', nameAr: 'خيال علمي'),
        Category(id: 'costume', name: 'Costume', nameEn: 'Costume', nameAr: 'تاريخي'),
        Category(id: 'urban', name: 'Urban', nameEn: 'Urban', nameAr: 'عصري'),
      ];

  static const List<String> hotKeywords = [
    'Love',
    'حب',
    'Desert',
    'صحراء',
    'Cairo',
    'القاهرة',
    'Mystery',
    'غموض',
    'Comedy',
    'كوميديا',
    'Palace',
    'قصر',
    'Emir',
    'أمير',
  ];

  static List<Drama> dramasByCategory(String categoryId, int page, {int pageSize = 12}) {
    return ComprehensiveMockData.dramasByCategory(
      categoryId,
      page: page,
      pageSize: pageSize,
    );
  }

  static List<Drama> search(String query, {int page = 1, int pageSize = 12}) {
    return ComprehensiveMockData.search(query, page: page, pageSize: pageSize);
  }

  static bool matchesCategory(Drama drama, String categoryId) {
    if (categoryId == allCategoryId) return true;
    // 基于阿拉伯语标题匹配
    final text = drama.title.toLowerCase();
    switch (categoryId) {
      case 'romance':
        return text.contains('love') || text.contains('حب') || text.contains('romance');
      case 'action':
        return text.contains('action') || text.contains('أكشن') || text.contains('shadow') || text.contains('revenge');
      case 'comedy':
        return text.contains('comedy') || text.contains('كوميديا') || text.contains('mix');
      case 'thriller':
        return text.contains('secret') || text.contains('إثارة') || text.contains('night');
      case 'sci-fi':
        return text.contains('future') || text.contains('2050') || text.contains('خيال علمي');
      case 'costume':
        return text.contains('emir') || text.contains('أمير') || text.contains('palace') || text.contains('king');
      case 'urban':
        return text.contains('dubai') || text.contains('ceo') || text.contains('عصري');
      default:
        return true;
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../recommend/models/drama.dart';
import '../models/category.dart';

enum ExploreStatus { initial, loading, success, error }

class ExploreState {
  const ExploreState({
    this.status = ExploreStatus.initial,
    this.categories = const [],
    this.selectedCategoryId = 'all',
    this.dramas = const [],
    this.page = 1,
    this.hasMore = true,
    this.isRefreshing = false,
    this.isLoadingMore = false,
    this.errorMessage,
  });

  final ExploreStatus status;
  final List<Category> categories;
  final String selectedCategoryId;
  final List<Drama> dramas;
  final int page;
  final bool hasMore;
  final bool isRefreshing;
  final bool isLoadingMore;
  final String? errorMessage;

  bool get isLoading => status == ExploreStatus.loading;
  bool get hasError => status == ExploreStatus.error;
  bool get hasData => status == ExploreStatus.success;

  ExploreState copyWith({
    ExploreStatus? status,
    List<Category>? categories,
    String? selectedCategoryId,
    List<Drama>? dramas,
    int? page,
    bool? hasMore,
    bool? isRefreshing,
    bool? isLoadingMore,
    String? errorMessage,
    bool clearError = false,
  }) {
    return ExploreState(
      status: status ?? this.status,
      categories: categories ?? this.categories,
      selectedCategoryId: selectedCategoryId ?? this.selectedCategoryId,
      dramas: dramas ?? this.dramas,
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final exploreProvider =
    StateNotifierProvider<ExploreNotifier, ExploreState>((ref) {
  return ExploreNotifier();
});

class ExploreNotifier extends StateNotifier<ExploreState> {
  ExploreNotifier() : super(const ExploreState()) {
    _init();
  }

  Future<void> _init() async {
    state = state.copyWith(status: ExploreStatus.loading, clearError: true);
    try {
      final resp = await apiServiceProvider.getVideoLabelList();
      List<Category> categories = _defaultCategories;
      if (resp.isSuccess && resp.data != null) {
        final list = resp.data as List;
        categories = list.map((json) => _categoryFromJson(json as Map<String, dynamic>)).toList();
        if (categories.isEmpty) categories = _defaultCategories;
      }
      state = state.copyWith(categories: categories);
      await _loadDramas(page: 1, append: false);
    } catch (e) {
      state = state.copyWith(
        status: ExploreStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> selectCategory(String categoryId) async {
    if (state.selectedCategoryId == categoryId) return;
    state = state.copyWith(
      selectedCategoryId: categoryId,
      status: ExploreStatus.loading,
      clearError: true,
    );
    await _loadDramas(page: 1, append: false);
  }

  Future<void> refresh() async {
    if (state.isRefreshing) return;
    state = state.copyWith(isRefreshing: true, clearError: true);
    await _loadDramas(page: 1, append: false);
    state = state.copyWith(isRefreshing: false);
  }

  Future<void> loadMore() async {
    if (state.isLoadingMore || !state.hasMore || !state.hasData) return;
    state = state.copyWith(isLoadingMore: true);
    await _loadDramas(page: state.page + 1, append: true);
    state = state.copyWith(isLoadingMore: false);
  }

  Future<void> _loadDramas({required int page, required bool append}) async {
    try {
      final resp = await apiServiceProvider.getVideoHotPicks(
        videoHotListType: state.selectedCategoryId == 'all' ? 1 : 2,
      );
      List<Drama> dramas = [];
      if (resp.isSuccess && resp.data != null) {
        final list = resp.data as List;
        dramas = list.map((json) => Drama.fromJson(json as Map<String, dynamic>)).toList();
      }
      state = state.copyWith(
        status: ExploreStatus.success,
        dramas: append ? [...state.dramas, ...dramas] : dramas,
        page: page,
        hasMore: dramas.length >= 12,
      );
    } catch (e) {
      state = state.copyWith(
        status: ExploreStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  static List<Category> _defaultCategories = [
    const Category(id: 'all', name: 'All', nameEn: 'All', nameAr: 'الكل'),
    const Category(id: 'romance', name: 'Romance', nameEn: 'Romance', nameAr: 'رومانسي'),
    const Category(id: 'action', name: 'Action', nameEn: 'Action', nameAr: 'أكشن'),
    const Category(id: 'comedy', name: 'Comedy', nameEn: 'Comedy', nameAr: 'كوميديا'),
    const Category(id: 'thriller', name: 'Thriller', nameEn: 'Thriller', nameAr: 'إثارة'),
    const Category(id: 'sci-fi', name: 'Sci-Fi', nameEn: 'Sci-Fi', nameAr: 'خيال علمي'),
    const Category(id: 'costume', name: 'Costume', nameEn: 'Costume', nameAr: 'تاريخي'),
    const Category(id: 'urban', name: 'Urban', nameEn: 'Urban', nameAr: 'عصري'),
  ];

  static Category _categoryFromJson(Map<String, dynamic> json) {
    // 兼容不同的字段命名
    return Category(
      id: (json['id'] ?? json['labelId'] ?? json['categoryId'] ?? '').toString(),
      name: (json['name'] ?? json['labelName'] ?? json['categoryName'] ?? '').toString(),
      nameEn: (json['nameEn'] ?? json['name'] ?? '').toString(),
      nameAr: (json['nameAr'] ?? '').toString(),
    );
  }
}

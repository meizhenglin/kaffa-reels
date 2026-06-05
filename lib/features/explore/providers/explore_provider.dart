import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../recommend/models/drama.dart';
import '../models/category.dart';

const int _explorePageSize = 12;

enum ExploreStatus { initial, loading, success, error }

class ExploreState {
  const ExploreState({
    this.status = ExploreStatus.initial,
    this.categories = const [],
    this.selectedCategoryId = '-1',
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
        categories = list
            .map((json) => Category.fromJson(json as Map<String, dynamic>))
            .toList();
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
      final videoLabelId = int.tryParse(state.selectedCategoryId) ?? -1;
      final resp = await apiServiceProvider.getVideoListByLabel(
        videoLabelId: videoLabelId,
        pageNum: page,
        pageSize: _explorePageSize,
      );
      List<Drama> dramas = [];
      var hasMore = false;
      if (resp.isSuccess && resp.data != null) {
        final rawData = resp.data;
        final records = rawData is List
            ? rawData
            : ((rawData as Map<String, dynamic>)['records'] as List? ??
                (rawData['list'] as List? ?? const []));
        dramas = records
            .map((json) => Drama.fromJson(json as Map<String, dynamic>))
            .toList();

        if (rawData is Map<String, dynamic>) {
          final current = (rawData['current'] as num?)?.toInt() ?? page;
          final pages = (rawData['pages'] as num?)?.toInt() ?? current;
          hasMore = current < pages;
        } else {
          hasMore = dramas.length >= _explorePageSize;
        }
      }
      state = state.copyWith(
        status: ExploreStatus.success,
        dramas: append ? [...state.dramas, ...dramas] : dramas,
        page: page,
        hasMore: hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        status: ExploreStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  static List<Category> _defaultCategories = [
    const Category(id: '-1', name: 'All', nameEn: 'All', nameAr: 'الكل'),
  ];

}

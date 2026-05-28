import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recommend/models/drama.dart';
import '../data/explore_mock_data.dart';
import '../data/explore_repository.dart';
import '../models/category.dart';

enum ExploreStatus { initial, loading, success, error }

class ExploreState {
  const ExploreState({
    this.status = ExploreStatus.initial,
    this.categories = const [],
    this.selectedCategoryId = ExploreMockData.allCategoryId,
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

final exploreRepositoryProvider = Provider<ExploreRepository>((ref) {
  return ExploreRepository();
});

final exploreProvider =
    StateNotifierProvider<ExploreNotifier, ExploreState>((ref) {
  return ExploreNotifier(ref.read(exploreRepositoryProvider));
});

class ExploreNotifier extends StateNotifier<ExploreState> {
  ExploreNotifier(this._repository) : super(const ExploreState()) {
    _init();
  }

  final ExploreRepository _repository;

  Future<void> _init() async {
    state = state.copyWith(status: ExploreStatus.loading, clearError: true);
    try {
      final categories = await _repository.fetchCategories();
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
      final result = await _repository.fetchDramasByCategory(
        categoryId: state.selectedCategoryId,
        page: page,
      );
      state = state.copyWith(
        status: ExploreStatus.success,
        dramas: append ? [...state.dramas, ...result.dramas] : result.dramas,
        page: page,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        status: ExploreStatus.error,
        errorMessage: e.toString(),
      );
    }
  }
}

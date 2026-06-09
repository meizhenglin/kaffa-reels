import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart' show apiServiceProviderRef;
import '../../recommend/models/drama.dart';

const int favoritesPageSize = 21;

enum FavoritesStatus {
  initial,
  loading,
  success,
  error,
}

class FavoritesState {
  const FavoritesState({
    this.status = FavoritesStatus.initial,
    this.items = const [],
    this.isLoadingMore = false,
    this.isRefreshing = false,
    this.hasMore = true,
    this.page = 1,
    this.errorMessage,
  });

  final FavoritesStatus status;
  final List<Drama> items;
  final bool isLoadingMore;
  final bool isRefreshing;
  final bool hasMore;
  final int page;
  final String? errorMessage;

  bool get isLoading => status == FavoritesStatus.loading;
  bool get isEmpty => items.isEmpty;

  FavoritesState copyWith({
    FavoritesStatus? status,
    List<Drama>? items,
    bool? isLoadingMore,
    bool? isRefreshing,
    bool? hasMore,
    int? page,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return FavoritesState(
      status: status ?? this.status,
      items: items ?? this.items,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

final favoritesProvider =
    StateNotifierProvider<FavoritesNotifier, FavoritesState>((ref) {
  return FavoritesNotifier(ref);
});

class FavoritesNotifier extends StateNotifier<FavoritesState> {
  FavoritesNotifier(this._ref) : super(const FavoritesState());

  final Ref _ref;

  Future<void> loadInitial() async {
    if (state.isLoading) return;

    state = state.copyWith(
      status: FavoritesStatus.loading,
      items: const [],
      page: 1,
      hasMore: true,
      isLoadingMore: false,
      isRefreshing: false,
      clearErrorMessage: true,
    );

    await _fetchPage(page: 1, replace: true);
  }

  Future<void> refresh() async {
    if (state.isLoading || state.isRefreshing) return;

    state = state.copyWith(
      isRefreshing: true,
      page: 1,
      hasMore: true,
      clearErrorMessage: true,
    );

    await _fetchPage(page: 1, replace: true);
  }

  Future<void> loadMore() async {
    if (state.isLoading || state.isRefreshing || state.isLoadingMore || !state.hasMore) {
      return;
    }

    state = state.copyWith(isLoadingMore: true, clearErrorMessage: true);
    await _fetchPage(page: state.page + 1, replace: false);
  }

  Future<void> _fetchPage({required int page, required bool replace}) async {
    final response = await _ref.read(apiServiceProviderRef).getUserVideoChasing(
          page: page,
          pageSize: favoritesPageSize,
        );

    if (!response.isSuccess) {
      state = state.copyWith(
        status: FavoritesStatus.error,
        isLoadingMore: false,
        isRefreshing: false,
        errorMessage: response.error ?? 'Failed to load favorites',
      );
      return;
    }

    final records = _extractList(response.data);
    final dramas = records
        .whereType<Map>()
        .map((item) => Drama.fromJson(Map<String, dynamic>.from(item)))
        .where((drama) => drama.id.isNotEmpty && drama.id != '0')
        .toList();

    state = state.copyWith(
      status: FavoritesStatus.success,
      items: replace ? dramas : [...state.items, ...dramas],
      page: page,
      hasMore: dramas.length >= favoritesPageSize,
      isLoadingMore: false,
      isRefreshing: false,
      clearErrorMessage: true,
    );
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return const [];

    final map = Map<String, dynamic>.from(data);
    final candidates = [
      map['list'],
      map['dataList'],
      map['records'],
      map['rows'],
      map['items'],
    ];

    for (final candidate in candidates) {
      if (candidate is List) {
        return candidate;
      }
    }

    return const [];
  }
}

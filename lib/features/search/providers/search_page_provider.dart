import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recommend/models/drama.dart';
import '../../explore/data/explore_repository.dart';

class SearchPageState {
  const SearchPageState({
    this.query = '',
    this.debouncedQuery = '',
    this.searchResults = const [],
    this.isLoadingResults = false,
    this.errorMessage,
    this.page = 1,
    this.hasMore = false,
  });

  final String query;
  final String debouncedQuery;
  final List<Drama> searchResults;
  final bool isLoadingResults;
  final String? errorMessage;
  final int page;
  final bool hasMore;

  bool get hasActiveSearch => debouncedQuery.trim().isNotEmpty;

  SearchPageState copyWith({
    String? query,
    String? debouncedQuery,
    List<Drama>? searchResults,
    bool? isLoadingResults,
    String? errorMessage,
    int? page,
    bool? hasMore,
    bool clearError = false,
  }) {
    return SearchPageState(
      query: query ?? this.query,
      debouncedQuery: debouncedQuery ?? this.debouncedQuery,
      searchResults: searchResults ?? this.searchResults,
      isLoadingResults: isLoadingResults ?? this.isLoadingResults,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

final searchPageProvider =
    StateNotifierProvider<SearchPageNotifier, SearchPageState>((ref) {
  return SearchPageNotifier();
});

class SearchPageNotifier extends StateNotifier<SearchPageState> {
  SearchPageNotifier() : _repository = ExploreRepository(), super(const SearchPageState());

  final ExploreRepository _repository;
  Timer? _debounceTimer;

  void setQuery(String value) {
    state = state.copyWith(query: value, clearError: true);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _onDebounced(value);
    });
  }

  Future<void> _onDebounced(String value) async {
    final trimmed = value.trim();
    state = state.copyWith(debouncedQuery: trimmed);

    if (trimmed.isEmpty) {
      state = state.copyWith(searchResults: [], isLoadingResults: false, page: 1, hasMore: false);
      return;
    }

    await _performSearch(trimmed, page: 1, append: false);
  }

  Future<void> submitSearch([String? keyword]) async {
    final q = (keyword ?? state.query).trim();
    if (q.isEmpty) return;

    _debounceTimer?.cancel();
    state = state.copyWith(query: q, debouncedQuery: q);
    await _performSearch(q, page: 1, append: false);
  }

  Future<void> _performSearch(String query, {required int page, required bool append}) async {
    state = state.copyWith(isLoadingResults: true, clearError: true);
    try {
      final result = await _repository.searchDramas(query: query, page: page);
      state = state.copyWith(
        searchResults: append ? [...state.searchResults, ...result.dramas] : result.dramas,
        isLoadingResults: false,
        page: page,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(isLoadingResults: false, errorMessage: e.toString());
    }
  }

  Future<void> loadMoreSearch() async {
    if (!state.hasActiveSearch || state.isLoadingResults || !state.hasMore) return;
    await _performSearch(state.debouncedQuery, page: state.page + 1, append: true);
  }

  void clearSearch() {
    _debounceTimer?.cancel();
    state = const SearchPageState();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

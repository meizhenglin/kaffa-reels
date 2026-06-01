import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../recommend/models/drama.dart';

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

/// 排行列表数据，直接调后端 API
final rankingDramasProvider = FutureProvider<List<Drama>>((ref) async {
  final resp = await apiServiceProvider.getRankingList();
  if (!resp.isSuccess || resp.data == null) return [];
  final list = resp.data as List;
  return list.map((json) => Drama.fromJson(json as Map<String, dynamic>)).toList();
});

class SearchPageNotifier extends StateNotifier<SearchPageState> {
  SearchPageNotifier() : super(const SearchPageState());

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
      final resp = await apiServiceProvider.getSearchList(keyword: query);
      final List<Drama> results = [];
      if (resp.isSuccess && resp.data != null) {
        final list = resp.data as List;
        for (final json in list) {
          results.add(Drama.fromJson(json as Map<String, dynamic>));
        }
      }
      state = state.copyWith(
        searchResults: append ? [...state.searchResults, ...results] : results,
        isLoadingResults: false,
        page: page,
        hasMore: results.length >= 12,
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

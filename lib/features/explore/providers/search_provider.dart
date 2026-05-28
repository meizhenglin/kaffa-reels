import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recommend/models/drama.dart';
import '../data/explore_mock_data.dart';
import '../data/explore_repository.dart';
import '../data/search_history_storage.dart';
import '../models/search_suggestion.dart';
import 'explore_provider.dart';

class SearchState {
  const SearchState({
    this.query = '',
    this.debouncedQuery = '',
    this.suggestions = const [],
    this.searchResults = const [],
    this.isSearching = false,
    this.isLoadingResults = false,
    this.showSuggestions = false,
    this.errorMessage,
    this.page = 1,
    this.hasMore = false,
  });

  final String query;
  final String debouncedQuery;
  final List<SearchSuggestion> suggestions;
  final List<Drama> searchResults;
  final bool isSearching;
  final bool isLoadingResults;
  final bool showSuggestions;
  final String? errorMessage;
  final int page;
  final bool hasMore;

  bool get hasActiveSearch => debouncedQuery.trim().isNotEmpty;

  SearchState copyWith({
    String? query,
    String? debouncedQuery,
    List<SearchSuggestion>? suggestions,
    List<Drama>? searchResults,
    bool? isSearching,
    bool? isLoadingResults,
    bool? showSuggestions,
    String? errorMessage,
    int? page,
    bool? hasMore,
    bool clearError = false,
  }) {
    return SearchState(
      query: query ?? this.query,
      debouncedQuery: debouncedQuery ?? this.debouncedQuery,
      suggestions: suggestions ?? this.suggestions,
      searchResults: searchResults ?? this.searchResults,
      isSearching: isSearching ?? this.isSearching,
      isLoadingResults: isLoadingResults ?? this.isLoadingResults,
      showSuggestions: showSuggestions ?? this.showSuggestions,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      page: page ?? this.page,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(
    ref.read(exploreRepositoryProvider),
    ref.read(searchHistoryStorageProvider),
  );
});

class SearchNotifier extends StateNotifier<SearchState> {
  SearchNotifier(this._repository, this._historyStorage)
      : super(const SearchState()) {
    _loadSuggestions();
  }

  final ExploreRepository _repository;
  final SearchHistoryStorage _historyStorage;
  Timer? _debounceTimer;

  void _loadSuggestions() {
    final recent = _historyStorage
        .load()
        .map((k) => SearchSuggestion(keyword: k, type: SearchSuggestionType.recent))
        .toList();
    final hot = ExploreMockData.hotKeywords
        .map((k) => SearchSuggestion(keyword: k, type: SearchSuggestionType.hot))
        .toList();

    state = state.copyWith(
      suggestions: [...recent, ...hot],
    );
  }

  void setQuery(String value) {
    state = state.copyWith(
      query: value,
      showSuggestions: true,
      clearError: true,
    );
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _onDebounced(value);
    });
  }

  Future<void> _onDebounced(String value) async {
    final trimmed = value.trim();
    state = state.copyWith(debouncedQuery: trimmed);

    if (trimmed.isEmpty) {
      state = state.copyWith(
        searchResults: [],
        isLoadingResults: false,
        page: 1,
        hasMore: false,
      );
      _loadSuggestions();
      return;
    }

    await _performSearch(trimmed, page: 1, append: false);
  }

  Future<void> submitSearch([String? keyword]) async {
    final q = (keyword ?? state.query).trim();
    if (q.isEmpty) return;

    state = state.copyWith(
      query: q,
      debouncedQuery: q,
      showSuggestions: false,
    );
    await _historyStorage.add(q);
    _loadSuggestions();
    await _performSearch(q, page: 1, append: false);
  }

  Future<void> _performSearch(
    String query, {
    required int page,
    required bool append,
  }) async {
    state = state.copyWith(isLoadingResults: true, clearError: true);
    try {
      final result = await _repository.searchDramas(query: query, page: page);
      state = state.copyWith(
        searchResults:
            append ? [...state.searchResults, ...result.dramas] : result.dramas,
        isLoadingResults: false,
        page: page,
        hasMore: result.hasMore,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingResults: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> loadMoreSearch() async {
    if (!state.hasActiveSearch || state.isLoadingResults || !state.hasMore) {
      return;
    }
    await _performSearch(
      state.debouncedQuery,
      page: state.page + 1,
      append: true,
    );
  }

  void setShowSuggestions(bool show) {
    state = state.copyWith(showSuggestions: show);
    if (show) _loadSuggestions();
  }

  Future<void> removeHistoryItem(String keyword) async {
    await _historyStorage.remove(keyword);
    _loadSuggestions();
  }

  Future<void> clearHistory() async {
    await _historyStorage.clear();
    _loadSuggestions();
  }

  void clearSearch() {
    _debounceTimer?.cancel();
    state = const SearchState();
    _loadSuggestions();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

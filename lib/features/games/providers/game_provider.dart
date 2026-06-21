import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart' show apiServiceProviderRef;
import '../models/game_carousel_item.dart';
import '../models/game_list_item.dart';
import '../services/game_service.dart';

class GameState {
  final List<GameCarouselItem> carouselItems;
  final List<GameListItem> recommendedGames;
  final bool isLoadingCarousel;
  final bool isLoadingList;
  final bool hasMore;
  final int currentPage;
  final String? errorMessage;

  const GameState({
    this.carouselItems = const [],
    this.recommendedGames = const [],
    this.isLoadingCarousel = false,
    this.isLoadingList = false,
    this.hasMore = true,
    this.currentPage = 1,
    this.errorMessage,
  });

  GameState copyWith({
    List<GameCarouselItem>? carouselItems,
    List<GameListItem>? recommendedGames,
    bool? isLoadingCarousel,
    bool? isLoadingList,
    bool? hasMore,
    int? currentPage,
    String? errorMessage,
  }) {
    return GameState(
      carouselItems: carouselItems ?? this.carouselItems,
      recommendedGames: recommendedGames ?? this.recommendedGames,
      isLoadingCarousel: isLoadingCarousel ?? this.isLoadingCarousel,
      isLoadingList: isLoadingList ?? this.isLoadingList,
      hasMore: hasMore ?? this.hasMore,
      currentPage: currentPage ?? this.currentPage,
      errorMessage: errorMessage,
    );
  }
}

class GameNotifier extends StateNotifier<GameState> {
  GameNotifier(this._ref) : super(const GameState()) {
    initialize();
  }

  final Ref _ref;
  static const int _pageSize = 20;

  Future<void> initialize() async {
    await Future.wait([
      fetchCarouselList(),
      fetchRecommendedGames(refresh: true),
    ]);
  }

  Future<void> fetchCarouselList() async {
    state = state.copyWith(isLoadingCarousel: true, errorMessage: null);

    final apiService = _ref.read(apiServiceProviderRef);
    final response = await apiService.getGameBanner();

    if (response.isSuccess && response.data is List) {
      final items = (response.data as List)
          .map((json) => GameCarouselItem.fromJson(json as Map<String, dynamic>))
          .toList();
      items.sort((a, b) => (a.sortOrder ?? 0).compareTo(b.sortOrder ?? 0));

      state = state.copyWith(
        carouselItems: items,
        isLoadingCarousel: false,
      );
    } else {
      state = state.copyWith(
        isLoadingCarousel: false,
        errorMessage: response.error ?? 'Failed to load game banner',
      );
    }
  }

  Future<void> fetchRecommendedGames({bool refresh = false, int? categoryId, int? gameType, String? moduleType}) async {
    if (!refresh && (state.isLoadingList || !state.hasMore)) return;

    final nextPage = refresh ? 1 : state.currentPage;
    state = state.copyWith(
      isLoadingList: true,
      errorMessage: null,
      currentPage: nextPage,
    );

    final apiService = _ref.read(apiServiceProviderRef);
    final response = await apiService.getGameList(
      categoryId: categoryId,
      gameType: gameType,
      moduleType: moduleType,
      page: nextPage,
      pageSize: _pageSize,
    );

    if (response.isSuccess && response.data is List) {
      final newItems = (response.data as List)
          .map((json) => GameListItem.fromJson(json as Map<String, dynamic>))
          .toList();

      final hasMore = newItems.length >= _pageSize;
      final games = refresh ? newItems : [...state.recommendedGames, ...newItems];

      state = state.copyWith(
        recommendedGames: games,
        isLoadingList: false,
        hasMore: hasMore,
        currentPage: nextPage + 1,
      );
    } else {
      state = state.copyWith(
        isLoadingList: false,
        errorMessage: response.error ?? 'Failed to load games',
      );
    }
  }

  Future<void> loadMore() async {
    await fetchRecommendedGames();
  }

  Future<void> refresh() async {
    await initialize();
  }

  Future<void> openGame(BuildContext context, GameListItem game) async {
    final gameTypeValue = game.gameType == GameType.app ? 'app' : 'h5';
    await GameService.openGame(
      context,
      gameTypeValue,
      game.h5Url,
      game.downloadUrl,
      game.name,
    );
  }
}

final gameProvider = StateNotifierProvider<GameNotifier, GameState>((ref) {
  return GameNotifier(ref);
});

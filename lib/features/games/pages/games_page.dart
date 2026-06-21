import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router/router_config.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../../l10n/app_localizations.dart';
import '../models/game_list_item.dart';
import '../providers/game_provider.dart';
import '../widgets/game_carousel.dart';

class GamesPage extends ConsumerStatefulWidget {
  const GamesPage({super.key});

  @override
  ConsumerState<GamesPage> createState() => _GamesPageState();
}

class _GamesPageState extends ConsumerState<GamesPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gameState = ref.watch(gameProvider);
    final carouselItems = gameState.carouselItems;
    final recommendedGames = gameState.recommendedGames;
    final isLoadingCarousel = gameState.isLoadingCarousel;
    final hasMore = gameState.hasMore;
    final errorMessage = gameState.errorMessage;

    return GradientScaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(gameProvider.notifier).refresh(),
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.only(top: 50, bottom: 24),
            itemCount: _buildItemCount(
              isLoadingCarousel: isLoadingCarousel,
              recommendedGames: recommendedGames,
              hasMore: hasMore,
              errorMessage: errorMessage,
            ),
            itemBuilder: (context, index) {
              return switch (index) {
                0 when isLoadingCarousel =>
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                0 when errorMessage != null && recommendedGames.isEmpty =>
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        errorMessage,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                0 when carouselItems.isEmpty ||
                      carouselItems.isNotEmpty =>
                  GameCarousel(
                    items: carouselItems,
                    height: 160,
                    onItemTap: (item) {
                      if (item.id.isEmpty) return;
                      final router = ref.read(routerProvider);
                      router.push(
                        '/games/detail/${item.id}',
                        extra: {
                          'id': item.id,
                          'gameName': item.title,
                        },
                      );
                    },
                  ),
                _ when errorMessage != null && recommendedGames.isEmpty =>
                  const SizedBox.shrink(),
                _ when index - 1 < recommendedGames.length =>
                  _GameListTile(
                    game: recommendedGames[index - 1],
                    onTap: () {
                      final router = ref.read(routerProvider);
                      final game = recommendedGames[index - 1];
                      router.push(
                        '/games/detail/${game.id}',
                        extra: {
                          'id': game.id,
                          'gameName': game.name,
                        },
                      );
                    },
                  ),
                _ when hasMore =>
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                _ => const SizedBox.shrink(),
              };
            },
          ),
        ),
      ),
    );
  }

  int _buildItemCount({
    required bool isLoadingCarousel,
    required List<GameListItem> recommendedGames,
    required bool hasMore,
    required String? errorMessage,
  }) {
    final baseCount = 1;
    final listCount = recommendedGames.length;
    final loadMoreCount = hasMore ? 1 : 0;
    final errorVisible = errorMessage != null && recommendedGames.isEmpty;

    if (isLoadingCarousel) return baseCount;
    if (errorVisible) return baseCount;
    return baseCount + listCount + loadMoreCount;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    final maxScroll = position.maxScrollExtent;
    final currentScroll = position.pixels;

    if (maxScroll - currentScroll < 200) {
      final gameState = ref.read(gameProvider);
      if (!gameState.isLoadingList && gameState.hasMore) {
        ref.read(gameProvider.notifier).loadMore();
      }
    }
  }
}

class _GameListTile extends StatelessWidget {
  const _GameListTile({
    required this.game,
    required this.onTap,
  });

  final GameListItem game;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                game.icon,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 48,
                  height: 48,
                  color: const Color(0xFF2A2A2A),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.videogame_asset,
                    color: Colors.white54,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    game.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white70,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    game.gameTypeDesc,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.white60,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _GameActionButton(
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

class _GameActionButton extends StatelessWidget {
  const _GameActionButton({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: const Text('Go play'),
    );
  }
}

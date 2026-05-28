import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/models/drama_list_type.dart';
import '../../recommend/providers/recommend_provider.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../../recommend/widgets/drama_card.dart';

/// 短剧列表页面
///
/// 支持展示热门短剧列表和全部推荐列表，通过 [DramaListType] 区分
class DramaListPage extends ConsumerWidget {
  const DramaListPage({
    super.key,
    required this.type,
  });

  final DramaListType type;

  String _title(AppLocalizations l10n) {
    switch (type) {
      case DramaListType.hot:
        return l10n.topRecommend;
      case DramaListType.recommended:
        return l10n.allRecommended;
    }
  }

  List<Drama> _dramas(RecommendState state) {
    switch (type) {
      case DramaListType.hot:
        return state.hotDramas;
      case DramaListType.recommended:
        return state.recommendedDramas;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final recommendState = ref.watch(recommendProvider);
    final dramas = _dramas(recommendState);
    final isLoading = recommendState.isLoading && dramas.isEmpty;

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context, l10n),
            Expanded(
              child: _buildBody(context, ref, dramas, isLoading),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Image.asset(
              'assets/images/back.png',
              width: 24,
              height: 24,
            ),
          ),
          Expanded(
            child: Text(
              _title(l10n),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    List<Drama> dramas,
    bool isLoading,
  ) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (dramas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.movie_outlined,
              size: 64,
              color: Colors.white38,
            ),
            const SizedBox(height: 16),
            Text(
              'No dramas available',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.white60,
                  ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(recommendProvider.notifier).refresh(),
      child: GridView.builder(
        padding: const EdgeInsets.all(15),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 15,
          crossAxisSpacing: 15,
          childAspectRatio: 165 / 224,
        ),
        itemCount: dramas.length,
        itemBuilder: (context, index) {
          final drama = dramas[index];
          return DramaCard(
            drama: drama,
            onTap: () => openDramaPlayerWithVipCheck(
              context: context,
              drama: drama,
              authState: ref.watch(authProvider),
              memberState: ref.watch(memberStateProvider),
            ),
          );
        },
      ),
    );
  }
}

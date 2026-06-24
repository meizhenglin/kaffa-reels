import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/app_empty_state.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/recommend/utils/drama_navigation.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/models/home_card_layout.dart';
import '../models/recharge_product.dart';
import '../providers/coin_record_provider.dart';
import '../providers/membership_provider.dart';

/// K-Coin recharge products page
/// Shows list of K-Coin packages from /api/rechargeGoodsConfig/list, select and buy via Google Pay
class CoinRechargePage extends ConsumerStatefulWidget {
  const CoinRechargePage({super.key});

  @override
  ConsumerState<CoinRechargePage> createState() => _CoinRechargePageState();
}

class _CoinRechargePageState extends ConsumerState<CoinRechargePage> {
  int? _selectedIndex;
  bool _isPurchasing = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(rechargeProductsProvider.notifier).load();
    });
  }

  Future<void> _handlePurchase(RechargeProduct product) async {
    final l10n = AppLocalizations.of(context);
    
    // 游客不能充值K币
    final authState = ref.read(authProvider);
    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      await openMembershipPage(context, ref);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.subscriptionConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name),
            const SizedBox(height: 8),
            Text(
              '${product.totalAmount} K-Coin',
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFFD700),
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              '\$${product.price}',
              style: Theme.of(ctx).textTheme.bodyLarge,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.pay),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isPurchasing = true);

    try {
      final handler = ref.read(rechargePurchaseHandlerProvider);
      final success = await handler.purchase(product);

      if (!success && mounted) {
        final reason = handler.lastError ?? l10n.purchaseFailedPleaseRetry;
        AppSnackBar.show(context, message: reason);
      } else if (success && mounted) {
        AppSnackBar.show(context, message: l10n.purchaseSuccessful);
        // 刷新余额
        await ref.read(coinBalanceInfoProvider.notifier).load();
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(rechargeProductsProvider);
    final l10n = AppLocalizations.of(context);

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  RtlBackButton(
                    onPressed: () => context.pop(),
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.kCoinRecharge,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),

            // Body
            Expanded(
              child: _buildBody(context, state, l10n),
            ),

            // Bottom Pay button
            if (state.products.isNotEmpty && _selectedIndex != null)
              _buildBottomPayButton(
                context,
                state.products[_selectedIndex!],
                l10n,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    RechargeProductsState state,
    AppLocalizations l10n,
  ) {
    if (state.isLoading && state.products.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      );
    }

    if (state.errorMessage != null && state.products.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 64),
            const SizedBox(height: 16),
            Text(
              state.errorMessage!,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.read(rechargeProductsProvider.notifier).load(),
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    if (state.products.isEmpty) {
      return AppEmptyState(
        message: l10n.noDataAvailableAtTheMoment,
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(rechargeProductsProvider.notifier).load(),
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1A1A1A),
      child: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: HomeCardLayout.scaled(context, 12),
          crossAxisSpacing: HomeCardLayout.scaled(context, 12),
          childAspectRatio: 0.85,
        ),
        itemCount: state.products.length,
        itemBuilder: (context, index) {
          final product = state.products[index];
          return _ProductCard(
            product: product,
            isSelected: _selectedIndex == index,
            onTap: () => setState(() => _selectedIndex = index),
          );
        },
      ),
    );
  }

  Widget _buildBottomPayButton(
    BuildContext context,
    RechargeProduct product,
    AppLocalizations l10n,
  ) {
    return ColoredBox(
      color: const Color(0xFF121212),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.of(context).padding.bottom + 10,
          ),
          child: SizedBox(
            width: double.infinity,
            height: 42,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFEE7A3), Color(0xFFDE962B)],
                ),
                borderRadius: BorderRadius.circular(21),
              ),
              child: FilledButton(
                onPressed: _isPurchasing
                    ? null
                    : () => _handlePurchase(product),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: const Color(0xFF753900),
                  disabledForegroundColor: const Color(0xFF753900).withAlpha(153),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(21),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: _isPurchasing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF753900),
                        ),
                      )
                    : Text(
                        l10n.payPrice(product.price),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF753900),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  const _ProductCard({
    required this.product,
    required this.isSelected,
    required this.onTap,
  });

  final RechargeProduct product;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFD700)
                : const Color(0xFFFFD700).withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coin icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.monetization_on,
                color: Color(0xFF1A1A1A),
                size: 24,
              ),
            ),
            const SizedBox(height: 8),

            // Amount (show total if bonus)
            Text(
              product.totalAmount > product.coinAmount
                  ? '${product.totalAmount} K'
                  : '${product.coinAmount} K',
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),

            // Bonus tag
            if (product.bonusAmount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B6B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '+${product.bonusAmount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              const SizedBox(height: 17),

            const SizedBox(height: 2),

            // Price
            if (product.price.isNotEmpty)
              Text(
                '\$${product.price}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),

            const Spacer(),

            // Selected indicator
            if (isSelected)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.selected,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  l10n.select,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

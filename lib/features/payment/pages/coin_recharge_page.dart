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
import '../models/payment_channel.dart';
import '../../home/models/home_card_layout.dart';
import '../models/recharge_product.dart';
import '../providers/coin_record_provider.dart' as coin_record;
import '../providers/recharge_provider.dart';
import '../services/unified_payment_handler.dart';
import '../services/payment_service.dart';
import '../widgets/payment_channel_selector.dart';

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
      await openMembershipPage(context, ref, showLoginPrompt: false);
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
            Text(product.displayAmount ?? product.name),
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
      // Google 渠道包（Android）与 iOS：跳过渠道选择，直接走商店内购
      // （iOS 上 rechargePurchaseHandler 最终路由 /notice/apple）。
      if (shouldUseStoreDirectly()) {
        final handler = ref.read(rechargePurchaseHandlerProvider);
        final success = await handler.purchase(product);
        if (!success && mounted) {
          final raw = handler.lastError;
          var reason = raw == null
              ? l10n.purchaseFailedPleaseRetry
              : _localizePlayFailure(raw, l10n);
          // 把商店原始 debugMessage 带出来，方便测试排障。
          // 【iOS 也要带】之前只带 Play 的 debugMessage，iOS 上排障信息丢失。
          final storeDebug = <String?>[
            PaymentService.instance.lastIosDebugMessage,
            PaymentService.instance.lastPlayDebugMessage,
          ].whereType<String>().toList();
          if (storeDebug.isNotEmpty) {
            reason = '$reason\n(${storeDebug.join(' | ')})';
          }
          AppSnackBar.show(context, message: reason);
        } else if (success && mounted) {
          AppSnackBar.show(context, message: l10n.purchaseSuccessful);
          await ref.read(coin_record.coinBalanceInfoProvider.notifier).load();
        }
        return;
      }

      // Platform flavor: let user select payment channel (HaiPay sub-methods).
      final unifiedHandler = ref.read(unifiedPaymentHandlerProvider);
      final haiPayMethods = await unifiedHandler.fetchHaiPayMethods(
        price: product.price,
        productName: product.name,
      );

      final channel = await PaymentChannelSelector.show(
        context: context,
        price: product.price,
        productName: product.name,
        haiPayMethods: haiPayMethods,
      );

      if (channel == null) return;

      if (channel.isGooglePlay) {
        final handler = ref.read(rechargePurchaseHandlerProvider);
        final success = await handler.purchase(product);
        if (!success && mounted) {
          final raw = handler.lastError;
          var reason = raw == null
              ? l10n.purchaseFailedPleaseRetry
              : _localizePlayFailure(raw, l10n);
          // 同会员页：把 Play 原始 debugMessage 带出来，方便测试排障。
          final playDebug = PaymentService.instance.lastPlayDebugMessage;
          if (playDebug != null && playDebug.isNotEmpty) {
            reason = '$reason\n(Play: $playDebug)';
          }
          AppSnackBar.show(context, message: reason);
        } else if (success && mounted) {
          AppSnackBar.show(context, message: l10n.purchaseSuccessful);
          await ref.read(coin_record.coinBalanceInfoProvider.notifier).load();
        }
      } else {
        // HaiPay completion is handled silently. The gateway may update the
        // balance shortly after its status endpoint confirms payment, so retry
        // the user-center lookup after returning from the WebView.
        final balanceNotifier = ref.read(
          coin_record.coinBalanceInfoProvider.notifier,
        );
        final completed = await unifiedHandler.purchaseRecharge(
          product: product,
          price: product.price,
          context: context,
          channel: channel,
          onPaymentComplete: (paid) {
            if (paid) {
              balanceNotifier.load();
            }
          },
        );
        if (completed) {
          await _refreshHaiPayBalance(balanceNotifier);
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isPurchasing = false);
      }
    }
  }

  Future<void> _refreshHaiPayBalance(
    coin_record.CoinBalanceNotifier balanceNotifier,
  ) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      await balanceNotifier.load();
    }
  }

  /// 把 Play 侧的稳定失败原因码翻译成给用户看的文案。
  ///
  /// 拿不到已知码时原样返回（多半是后端返回的业务错误文案）。
  ///
  /// 关键点：`play-no-eligible-offer`（商品在商店里存在，但当前账号 / 国家
  /// 买不了）和 `play-item-not-found`（商品真的不存在）是两种完全不同的故障，
  /// 提示必须分开，否则用户会去查错的方向。
  String _localizePlayFailure(String code, AppLocalizations l10n) {
    switch (code) {
      case 'play-service-unavailable':
      case 'play-service-disconnected':
        return l10n.membershipPlayServiceUnavailable;
      case 'play-store-unavailable':
      case 'play-feature-not-supported':
        return l10n.membershipPlayStoreUnavailable;
      case 'play-network-error':
      case 'play-timeout':
        return l10n.membershipPlayNetworkError;
      case 'play-no-eligible-offer':
        return l10n.membershipPlayNoEligibleOffer;
      case 'play-item-not-found':
      case 'play-item-unavailable':
      case 'play-developer-error':
      case 'play-not-subscription':
        return l10n.membershipPlayItemNotAvailable;
      // iOS StoreKit 侧的失败码（iOS 商品查不到 / 商店不可用）。
      case 'ios-store-unavailable':
        return l10n.membershipIosStoreUnavailable;
      case 'ios-network-error':
        return l10n.membershipIosNetworkError;
      case 'ios-store-error':
        return l10n.membershipIosStoreError;
      case 'ios-item-not-found':
        return l10n.membershipIosItemNotAvailable;
      default:
        return code;
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
            Expanded(child: _buildBody(context, state, l10n)),

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
              onPressed: () =>
                  ref.read(rechargeProductsProvider.notifier).load(),
              child: Text(l10n.retry),
            ),
          ],
        ),
      );
    }

    if (state.products.isEmpty) {
      return AppEmptyState(message: l10n.noDataAvailableAtTheMoment);
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
                  disabledForegroundColor: const Color(
                    0xFF753900,
                  ).withAlpha(153),
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
              product.displayAmount ?? product.name,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),

            if (product.bonusAmount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.card_giftcard,
                      color: Color(0xFFFF6B6B),
                      size: 13,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '+${product.bonusAmount} K-Coin',
                      style: const TextStyle(
                        color: Color(0xFFFF8A8A),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 15),

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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../app/providers/app_providers.dart';
import '../../../components/rtl_back_button.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/config/build_flavor.dart';
import '../models/payment_channel.dart';
import '../providers/recharge_provider.dart';
import '../services/unified_payment_handler.dart';
import '../widgets/payment_channel_selector.dart';

/// Recharge coins page (K币充值)
class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(rechargeProductsProvider.notifier).load();
    });
  }

  void _handleBack() {
    Navigator.of(context).pop();
  }

  Future<void> _handlePurchase(RechargeProduct product) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.confirmPurchase),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.price,
              style: Theme.of(
                ctx,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(product.displayAmount ?? product.name),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.purchase),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Google flavor: skip HaiPay entirely — go straight to Google Play.
    if (BuildFlavor.isGoogle) {
      final handler = ref.read(rechargePurchaseHandlerProvider);
      await handler.purchase(product);
      return;
    }

    // Step 1: Let user select payment channel (Google Play or HaiPay sub-methods)
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

    bool success = false;

    if (channel.isGooglePlay) {
      // Google Play flow (original logic)
      final handler = ref.read(rechargePurchaseHandlerProvider);
      success = await handler.purchase(product);
    } else {
      // HaiPay H5 flow
      success = await unifiedHandler.purchaseRecharge(
        product: product,
        price: product.price,
        context: context,
        channel: channel,
      );
    }

    if (success) {
      if (mounted) {
        AppSnackBar.show(context, message: l10n.purchaseStarted);
      }
    } else {
      if (mounted) {
        AppSnackBar.show(context, message: l10n.failedToStartPurchase);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(rechargeProductsProvider);
    final coinState = ref.watch(coinBalanceProvider);

    return GradientScaffold(
      bottomBackgroundColor: const Color(0xFF121212),
      body: Stack(
        children: [
          Container(
            color: const Color(0xFF121212),
            child: CustomScrollView(
              slivers: [
                // Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 40),
                        Row(
                          children: [
                            const Icon(
                              Icons.monetization_on,
                              color: Colors.amber,
                              size: 48,
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l10n.myCoins,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '${coinState.balance}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        Text(
                          l10n.rechargeCoinsTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.choosePackage,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),

                // Loading
                if (state.isLoading)
                  const SliverFillRemaining(
                    child: Center(child: CircularProgressIndicator()),
                  )
                // Products
                else if (state.products.isNotEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.85,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final product = state.products[index];
                        final isSelected = _selectedIndex == index;

                        return _buildProductCard(product, isSelected, index);
                      }, childCount: state.products.length),
                    ),
                  )
                else
                  SliverFillRemaining(
                    child: Center(
                      child: Text(
                        l10n.noRechargePackages,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),

          // Back button
          PositionedDirectional(
            top: MediaQuery.of(context).padding.top + 8,
            start: 8,
            child: RtlBackButton(onPressed: _handleBack, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(
    RechargeProduct product,
    bool isSelected,
    int index,
  ) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
        });
        _handlePurchase(product);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.amber.withOpacity(0.2)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.amber : Colors.white.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.monetization_on,
              color: isSelected ? Colors.amber : Colors.white70,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              product.displayAmount ?? product.name,
              style: TextStyle(
                color: isSelected ? Colors.amber : Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (product.bonusAmount > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.card_giftcard,
                    color: Colors.orangeAccent,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '+${product.bonusAmount} K-Coin',
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.amber
                    : Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                product.price,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white,
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

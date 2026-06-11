import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../providers/membership_provider.dart';

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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Purchase'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(product.name),
            const SizedBox(height: 8),
            Text(
              product.price,
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text('${product.totalAmount} coins'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Purchase'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Start purchase
    final handler = ref.read(rechargePurchaseHandlerProvider);
    final success = await handler.purchase(product);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase started, please wait...')),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start purchase')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                            const Icon(Icons.monetization_on, color: Colors.amber, size: 48),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'My Coins',
                                  style: TextStyle(color: Colors.white70, fontSize: 14),
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
                        const Text(
                          'Recharge Coins',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Choose a package to recharge',
                          style: TextStyle(color: Colors.white70),
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
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.85,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final product = state.products[index];
                          final isSelected = _selectedIndex == index;

                          return _buildProductCard(product, isSelected, index);
                        },
                        childCount: state.products.length,
                      ),
                    ),
                  )
                else
                  const SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'No recharge packages available',
                        style: TextStyle(color: Colors.white70),
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
            child: RtlBackButton(
              onPressed: _handleBack,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(RechargeProduct product, bool isSelected, int index) {
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
          color: isSelected ? Colors.amber.withOpacity(0.2) : Colors.white.withOpacity(0.1),
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
              '${product.totalAmount}',
              style: TextStyle(
                color: isSelected ? Colors.amber : Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Text(
              'Coins',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.amber : Colors.white.withOpacity(0.2),
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

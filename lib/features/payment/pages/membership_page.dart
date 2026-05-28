import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../models/subscription_product.dart';
import '../providers/membership_provider.dart';
import '../services/payment_service.dart';

/// ============================================================================
/// 会员订阅页面
///
/// 【功能】
/// - 展示 VIP 会员权益
/// - 显示订阅套餐选择
/// - 处理应用内购买
/// - 恢复购买
///
/// 【订阅套餐】
/// - 周卡、月卡、季卡、年卡
/// - 支持应用内购买（iOS/Android）
///
/// 【如何修改】
/// - 修改套餐信息：修改 subscription_product.dart
/// - 修改购买逻辑：修改 membership_provider.dart
/// ============================================================================
class MembershipPage extends ConsumerStatefulWidget {
  const MembershipPage({super.key});

  @override
  ConsumerState<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends ConsumerState<MembershipPage> {
  List<ProductDetails> _products = [];
  bool _isLoadingProducts = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  /// 加载产品列表
  Future<void> _loadProducts() async {
    final notifier = ref.read(memberStateProvider.notifier);
    final products = await notifier.getProducts();
    setState(() {
      _products = products;
      _isLoadingProducts = false;
    });
  }

  /// 处理购买
  Future<void> _handlePurchase(SubscriptionProduct product) async {
    ProductDetails? details;
    final platform = PaymentService.instance.currentPlatform;
    final productId = product.getProductId(platform);

    try {
      details = _products.firstWhere((p) => p.id == productId);
    } catch (_) {
      try {
        details = _products.firstWhere((p) => p.id.contains(product.id));
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Product not available')),
          );
        }
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${product.type.displayNameCn} ${product.type.displayName}'),
            const SizedBox(height: 8),
            Text(
              product.price,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your subscription will automatically renew unless canceled before the end of the billing period.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Subscribe'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final notifier = ref.read(memberStateProvider.notifier);
    final success = await notifier.purchase(details);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Purchase initiated. Please complete payment.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  /// 恢复购买
  Future<void> _handleRestore() async {
    final notifier = ref.read(memberStateProvider.notifier);
    final success = await notifier.restorePurchases();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'Purchases restored successfully!' : 'No purchases to restore',
          ),
        ),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final memberState = ref.watch(memberStateProvider);
    final theme = Theme.of(context);

    return GradientScaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => context.pop(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Membership',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverFillRemaining(
              child: memberState.isVip && !memberState.isExpired
                  ? _buildActiveSubscription(memberState)
                  : _buildSubscriptionPlans(),
            ),
          ],
        ),
      ),
    );
  }

  /// 已订阅视图
  Widget _buildActiveSubscription(MemberState memberState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber[700]!, Colors.orange[600]!],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(Icons.workspace_premium, size: 64, color: Colors.white),
                const SizedBox(height: 12),
                const Text(
                  'You are VIP',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Expires: ${_formatDate(memberState.expireDate)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                if (memberState.daysRemaining != null)
                  Text(
                    '${memberState.daysRemaining} days remaining',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Your VIP Benefits',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...MemberBenefits.vipTierCn.map(
                    (benefit) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check, size: 16, color: Colors.green),
                          const SizedBox(width: 8),
                          Expanded(child: Text(benefit)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.settings),
            label: const Text('Manage Subscription'),
          ),
        ],
      ),
    );
  }

  /// 订阅套餐视图
  Widget _buildSubscriptionPlans() {
    final theme = Theme.of(context);
    final memberState = ref.watch(memberStateProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.secondaryContainer,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              children: [
                Icon(Icons.workspace_premium, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Unlock Premium',
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Enjoy all dramas without ads',
                  style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Member Benefits',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    _buildBenefitRow('Ad-free viewing', true, MemberBenefits.vipTierCn[0]),
                    _buildBenefitRow('HD/4K quality', true, MemberBenefits.vipTierCn[1]),
                    _buildBenefitRow('Full library access', true, MemberBenefits.vipTierCn[2]),
                    _buildBenefitRow('Exclusive content', true, MemberBenefits.vipTierCn[3]),
                    _buildBenefitRow('Early access', true, MemberBenefits.vipTierCn[4]),
                    const Divider(height: 24),
                    _buildBenefitRow('With ads', false, 'Standard quality, limited content'),
                    _buildBenefitRow('No downloads', false, 'Limited library'),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoadingProducts)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: SubscriptionProducts.products.map((product) {
                  return _SubscriptionCard(
                    product: product,
                    onSubscribe: () => _handlePurchase(product),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: memberState.isRestoring ? null : _handleRestore,
              child: memberState.isRestoring
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Restore Purchases'),
            ),
          ),
          if (memberState.errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                memberState.errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _openUrl('https://example.com/privacy'),
                  child: const Text('Privacy Policy'),
                ),
                const Text('|'),
                TextButton(
                  onPressed: () => _openUrl('https://example.com/terms'),
                  child: const Text('Terms of Service'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBenefitRow(String title, bool isVip, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            isVip ? Icons.check_circle : Icons.cancel,
            color: isVip ? Colors.green : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: isVip ? null : Colors.grey,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: isVip ? null : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// 订阅卡片组件
class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({required this.product, required this.onSubscribe});

  final SubscriptionProduct product;
  final VoidCallback onSubscribe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSubscribe,
        child: Column(
          children: [
            if (product.isPopular || product.isBestValue)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: product.isBestValue ? Colors.amber[700] : theme.colorScheme.primary,
                child: Text(
                  product.isBestValue ? 'BEST VALUE' : 'POPULAR',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.type.displayNameCn,
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(product.type.displayName, style: theme.textTheme.bodySmall),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                product.price,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            product.originalPrice,
                            style: theme.textTheme.bodySmall?.copyWith(
                              decoration: TextDecoration.lineThrough,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onSubscribe,
                      child: const Text('Subscribe Now'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../../recommend/providers/recommend_provider.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/models/subscription_product.dart';
import '../../payment/providers/membership_provider.dart';
import '../../payment/services/payment_service.dart';

class MembershipPage extends ConsumerStatefulWidget {
  const MembershipPage({super.key});

  @override
  ConsumerState<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends ConsumerState<MembershipPage> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(recommendProvider.notifier).loadInitial();
    });
  }

  Future<void> _handlePurchase(SubscriptionProduct product) async {
    final l10n = AppLocalizations.of(context);
    final platform = PaymentService.instance.currentPlatform;
    final productId = product.getProductId(platform);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Subscription'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${product.type.displayNameCn} ${product.type.displayName}'),
            const SizedBox(height: 8),
            Text(
              product.price,
              style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFFD700),
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.membership_subscribe,
              style: Theme.of(ctx).textTheme.bodySmall,
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
            child: Text(l10n.subscribe),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final memberNotifier = ref.read(memberStateProvider.notifier);
    final products = await memberNotifier.getProducts();

    ProductDetails? details;
    try {
      details = products.firstWhere((p) => p.id == productId);
    } catch (_) {
      try {
        details = products.firstWhere((p) => p.id.contains(product.id));
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Product not available')),
          );
        }
        return;
      }
    }

    final success = await memberNotifier.purchase(details);
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase initiated. Please complete payment.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recommendState = ref.watch(recommendProvider);
    final memberState = ref.watch(memberStateProvider);

    if (memberState.isVip && !memberState.isExpired) {
      return _buildActiveView(l10n, memberState);
    }

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // 1. 顶部图片 379
                    _buildTopImage(),

                    // 2. VIP 选项区 231
                    _buildVipOptions(l10n),

                    // 3. 剧卡片横向滚动 137
                    _buildDramaSection(recommendState),

                    // 4. 五列文字介绍
                    _buildBenefitsSection(l10n),
                  ],
                ),
              ),
            ),

            // 5. 底部支付按钮 42 + 安全区
            _buildBottomPayButton(l10n, memberState),
          ],
        ),
      ),
    );
  }

  /// 1. 顶部图片
  Widget _buildTopImage() {
    return SizedBox(
      height: 379,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/vip_banner.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF5D4391), Color(0xFF1F2025)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          // 返回按钮
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => context.pop(),
            ),
          ),
        ],
      ),
    );
  }

  /// 2. VIP 选项区：高 231，三个选项上下排列
  Widget _buildVipOptions(AppLocalizations l10n) {
    return Container(
      height: 231,
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          // 三个选项
          Expanded(
            child: Column(
              children: List.generate(SubscriptionProducts.products.length, (i) {
                final product = SubscriptionProducts.products[i];
                final isSelected = _selectedIndex == i;
                return _VipOptionItem(
                  product: product,
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedIndex = i),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// 3. 剧卡片横向滚动区：高 137
  Widget _buildDramaSection(RecommendState recommendState) {
    final dramas = recommendState.vipZone.isNotEmpty
        ? recommendState.vipZone
        : (recommendState.topRecommend.isNotEmpty
            ? recommendState.topRecommend
            : _mockDramas.cast<dynamic>());

    return Container(
      height: 137,
      color: const Color(0xFF121212),
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Popular Dramas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'View All >',
                    style: TextStyle(
                      color: Colors.white.withAlpha(128),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: dramas.length,
              itemBuilder: (context, index) {
                final drama = dramas[index];
                return _DramaCard(
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
          ),
        ],
      ),
    );
  }

  /// 4. 五列文字介绍
  Widget _buildBenefitsSection(AppLocalizations l10n) {
    final items = [
      (Icons.block, 'Ad-free', 'No interruptions while watching'),
      (Icons.hd, 'HD Quality', 'Crystal clear video stream'),
      (Icons.download, 'Downloads', 'Watch offline anywhere'),
      (Icons.bolt, 'Early Access', 'New releases first'),
      (Icons.star, 'VIP Content', 'Exclusive member videos'),
    ];

    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          return Expanded(
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700).withAlpha(25),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.$1, size: 20, color: const Color(0xFFFFD700)),
                ),
                const SizedBox(height: 8),
                Text(
                  item.$2,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.$3,
                  style: TextStyle(
                    color: Colors.white.withAlpha(128),
                    fontSize: 9,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// 5. 底部支付按钮
  Widget _buildBottomPayButton(AppLocalizations l10n, MemberState memberState) {
    final product = _selectedIndex < SubscriptionProducts.products.length
        ? SubscriptionProducts.products[_selectedIndex]
        : null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        MediaQuery.of(context).padding.bottom + 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        border: Border(
          top: BorderSide(color: Colors.white.withAlpha(13)),
        ),
      ),
      child: SizedBox(
        height: 42,
        child: FilledButton(
          onPressed: product == null ? null : () => _handlePurchase(product),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: const Color(0xFF1F2025),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(21),
            ),
            padding: EdgeInsets.zero,
          ),
          child: Text(
            product != null
                ? 'Subscribe Now  ${product.price}'
                : 'Subscribe Now',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }

  /// 已订阅视图
  Widget _buildActiveView(AppLocalizations l10n, MemberState memberState) {
    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    _buildTopImage(),
                    _buildVipOptions(l10n),
                    _buildBenefitsSection(l10n),
                    const SizedBox(height: 16),
                    _buildActiveInfo(memberState, l10n),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            _buildBottomPayButton(l10n, memberState),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveInfo(MemberState memberState, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.workspace_premium, size: 48, color: Colors.white),
          const SizedBox(height: 8),
          Text(
            'You are a VIP Member!',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Expires: ${_formatDate(memberState.expireDate)}  •  ${memberState.daysRemaining ?? 0} days left',
            style: TextStyle(
              color: Colors.white.withAlpha(204),
              fontSize: 13,
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

  List<_MockDrama> get _mockDramas {
    return [
      _MockDrama('drama_0', 'Desert Rose', 'https://picsum.photos/seed/d1/200/280'),
      _MockDrama('drama_1', 'The Shadow', 'https://picsum.photos/seed/d2/200/280'),
      _MockDrama('drama_2', 'Sand Storm', 'https://picsum.photos/seed/d3/200/280'),
      _MockDrama('drama_3', 'Oasis', 'https://picsum.photos/seed/d4/200/280'),
      _MockDrama('drama_4', 'Falcon', 'https://picsum.photos/seed/d5/200/280'),
    ];
  }
}

/// 单个 VIP 选项行
class _VipOptionItem extends StatelessWidget {
  const _VipOptionItem({
    required this.product,
    required this.isSelected,
    required this.onTap,
  });

  final SubscriptionProduct product;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBestValue = product.isBestValue;
    final isPopular = product.isPopular;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFFFD700).withAlpha(25)
              : const Color(0xFF2A2A30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFFD700)
                : Colors.white.withAlpha(13),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // 单选框
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFFFFD700) : Colors.white38,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFFD700),
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            // 标题
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        product.type.displayNameCn,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        product.type.displayName,
                        style: TextStyle(
                          color: Colors.white.withAlpha(128),
                          fontSize: 12,
                        ),
                      ),
                      if (isBestValue || isPopular) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: isBestValue
                                ? const Color(0xFFFFD700)
                                : const Color(0xFF5D4391),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isBestValue ? 'BEST' : 'HOT',
                            style: TextStyle(
                              color: isBestValue ? const Color(0xFF1F2025) : Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    product.benefits.take(2).join(' • '),
                    style: TextStyle(
                      color: Colors.white.withAlpha(102),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 价格
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  product.price,
                  style: const TextStyle(
                    color: Color(0xFFFFD700),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (product.originalPrice != product.price)
                  Text(
                    product.originalPrice,
                    style: TextStyle(
                      color: Colors.white.withAlpha(77),
                      fontSize: 10,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 剧卡片
class _DramaCard extends StatelessWidget {
  const _DramaCard({required this.drama, required this.onTap});

  final dynamic drama;
  final VoidCallback onTap;

  String get _coverUrl => drama.coverUrl ?? '';
  String get _title {
    final t = drama.title ?? '';
    return t.contains(' / ') ? t.split(' / ').first : t;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 106,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(12),
                      image: _coverUrl.isNotEmpty
                          ? DecorationImage(
                              image: NetworkImage(_coverUrl),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: _coverUrl.isEmpty
                        ? Center(
                            child: Icon(
                              Icons.movie_outlined,
                              color: Colors.white.withAlpha(77),
                              size: 28,
                            ),
                          )
                        : null,
                  ),
                  if (drama.isVipOnly == true)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Image.asset(
                        'assets/images/home_vip_icon.png',
                        width: 36,
                        height: 15,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _MockDrama {
  final String id;
  final String title;
  final String coverUrl;
  const _MockDrama(this.id, this.title, this.coverUrl);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../../../core/utils/localized_badge_assets.dart';
import '../../../components/preload_network_image.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../../recommend/providers/recommend_provider.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/models/subscription_product.dart';
import '../../payment/providers/membership_provider.dart';
import '../../payment/services/payment_service.dart';
import '../../../components/rtl_back_button.dart';

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
      ref.read(membershipDramaProvider.notifier).load();
      ref.read(membershipProductsProvider.notifier).loadVipProducts();
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
    final membershipProducts = ref.read(membershipProductsProvider).products;
    final products = await memberNotifier.getProducts(
      membershipProducts.isNotEmpty
          ? membershipProducts
          : SubscriptionProducts.fallbackProducts,
    );

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
    final recommendState = ref.watch(membershipDramaProvider);
    final memberState = ref.watch(memberStateProvider);
    final membershipProductsState = ref.watch(membershipProductsProvider);
    final products = membershipProductsState.products.isNotEmpty
        ? membershipProductsState.products
        : SubscriptionProducts.fallbackProducts;

    if (_selectedIndex >= products.length && products.isNotEmpty) {
      _selectedIndex = 0;
    }

    if (memberState.isVip && !memberState.isExpired) {
      return _buildActiveView(l10n, memberState, products);
    }

    return GradientScaffold(
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // 1. 顶部图片 379
                  _buildTopImage(),

                  // 2. VIP 选项区 231
                  _buildVipOptions(l10n, products),

                  // 3. 剧卡片横向滚动 137
                  _buildDramaSection(recommendState),

                  // 4. 五列文字介绍
                  _buildBenefitsSection(l10n),
                ],
              ),
            ),
          ),

          // 5. 底部支付按钮 42 + 安全区
          _buildBottomPayButton(l10n, memberState, products),
        ],
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
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
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
          PositionedDirectional(
            top: MediaQuery.of(context).padding.top + 8,
            start: 8,
            child: RtlBackButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  Navigator.of(context).maybePop();
                }
              },
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// 2. VIP 选项区：高 231，三个选项上下排列
  Widget _buildVipOptions(AppLocalizations l10n, List<SubscriptionProduct> products) {
    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        children: List.generate(products.length, (i) {
          final product = products[i];
          final isSelected = _selectedIndex == i;
          return _VipOptionItem(
            product: product,
            title: _localizedProductTitle(l10n, product),
            isSelected: isSelected,
            onTap: () => setState(() => _selectedIndex = i),
          );
        }),
      ),
    );
  }

  String _localizedProductTitle(
    AppLocalizations l10n,
    SubscriptionProduct product,
  ) {
    if (product.displayName != null && product.displayName!.trim().isNotEmpty) {
      return product.displayName!.trim();
    }

    final name = product.id.toLowerCase();
    if (name.contains('year')) {
      return l10n.membership_yearly;
    }
    if (name.contains('quarter')) {
      return l10n.membership_quarterly;
    }
    if (name.contains('month')) {
      return l10n.membership_monthly;
    }

    switch (product.type) {
      case SubscriptionPeriod.monthly:
        return l10n.membership_monthly;
      case SubscriptionPeriod.quarterly:
        return l10n.membership_quarterly;
      case SubscriptionPeriod.yearly:
        return l10n.membership_yearly;
    }
  }

  /// 3. 剧卡片横向滚动区：高 137
  Widget _buildDramaSection(MembershipDramaState recommendState) {
    final dramas = recommendState.vipZone.isNotEmpty
        ? recommendState.vipZone
        : recommendState.topRecommend;
    final displayDramas = dramas.take(3).toList();
    final showSkeletonCards = displayDramas.isEmpty;

    return Container(
      height: 137,
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: List.generate(3, (index) {
          final drama = index < displayDramas.length ? displayDramas[index] : null;
          return Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: index == 2 ? 0 : 12),
              child: drama != null
                  ? _DramaCard(
                      drama: drama,
                      onTap: () => openDramaPlayerWithVipCheck(
                        context: context,
                        drama: drama,
                        authState: ref.watch(authProvider),
                        memberState: ref.watch(memberStateProvider),
                      ),
                    )
                  : _DramaCardPlaceholder(showImage: showSkeletonCards),
            ),
          );
        }),
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
  Widget _buildBottomPayButton(
    AppLocalizations l10n,
    MemberState memberState,
    List<SubscriptionProduct> products,
  ) {
    final product = _selectedIndex < products.length ? products[_selectedIndex] : null;
    final amount = product?.price.replaceFirst(RegExp(r'^[^0-9]+'), '') ?? '';
    final buttonLabel = amount.isNotEmpty ? 'Pay \$$amount' : 'Pay';

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        16,
        10,
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
            onPressed: product == null ? null : () => _handlePurchase(product),
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
            child: Text(
              buttonLabel,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF753900),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 已订阅视图
  Widget _buildActiveView(
    AppLocalizations l10n,
    MemberState memberState,
    List<SubscriptionProduct> products,
  ) {
    return GradientScaffold(
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildTopImage(),
                  _buildVipOptions(l10n, products),
                  _buildBenefitsSection(l10n),
                  const SizedBox(height: 16),
                  _buildActiveInfo(memberState, l10n),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          _buildBottomPayButton(l10n, memberState, products),
        ],
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
}

/// 单个 VIP 选项行
class _VipOptionItem extends StatelessWidget {
  const _VipOptionItem({
    required this.product,
    required this.title,
    required this.isSelected,
    required this.onTap,
  });

  final SubscriptionProduct product;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;

  static const _priceGradient = LinearGradient(
    begin: Alignment.centerRight,
    end: Alignment.centerLeft,
    colors: [Color(0xFFEABD81), Color(0xFFF5D1A2)],
  );

  @override
  Widget build(BuildContext context) {
    final price = product.price;
    final symbol = price.isNotEmpty ? price.substring(0, 1) : '';
    final amount = price.length > 1 ? price.substring(1) : price;
    final originalPrice = product.originalPrice;
    final hasOriginalPrice =
        originalPrice.isNotEmpty && originalPrice != price;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/vip_item_bg.png'),
            fit: BoxFit.fill,
          ),
        ),
        child: Row(
          children: [
            Image.asset(
              isSelected
                  ? 'assets/images/vip_selected.png'
                  : 'assets/images/vip_notselected.png',
              width: 20,
              height: 20,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 15),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasOriginalPrice)
                  Text(
                    originalPrice,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withAlpha(160),
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.white.withAlpha(160),
                    ),
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => _priceGradient.createShader(
                        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                      ),
                      blendMode: BlendMode.srcIn,
                      child: Text(
                        symbol,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    ShaderMask(
                      shaderCallback: (bounds) => _priceGradient.createShader(
                        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                      ),
                      blendMode: BlendMode.srcIn,
                      child: Text(
                        amount,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
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
class _DramaCardPlaceholder extends StatelessWidget {
  const _DramaCardPlaceholder({this.showImage = true});

  final bool showImage;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Container(
        color: const Color(0xFF1A1A1A),
        child: showImage
            ? Image.asset(
                'assets/images/small_preload_bg.png',
                fit: BoxFit.cover,
              )
            : const SizedBox.expand(),
      ),
    );
  }
}

class _DramaCard extends StatelessWidget {
  const _DramaCard({required this.drama, required this.onTap});

  final dynamic drama;
  final VoidCallback onTap;

  String get _coverUrl => drama.coverUrl ?? '';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.none,
          children: [
            PreloadNetworkImage(
              imageUrl: _coverUrl,
              preloadAsset: 'assets/images/small_preload_bg.png',
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(10),
            ),
            if (drama.videoAccessType == 1)
              PositionedDirectional(
                top: 0,
                start: 0,
                child: Image.asset(
                  localizedHomeVipBadgeAsset(context),
                  width: 42,
                  height: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
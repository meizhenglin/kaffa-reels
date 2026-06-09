import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/utils/localized_badge_assets.dart';
import '../../../components/preload_network_image.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../../recommend/providers/recommend_provider.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/models/subscription_product.dart';
import '../../payment/providers/membership_provider.dart';
import '../../../components/rtl_back_button.dart';

class MembershipPage extends ConsumerStatefulWidget {
  const MembershipPage({super.key});

  @override
  ConsumerState<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends ConsumerState<MembershipPage> {
  static const double _bottomButtonHeight = 42;
  static const double _bottomButtonTopSpacing = 0;
  static const double _bottomButtonBottomSpacing = 10;
  static const Color _membershipBottomColor = Color(0xFF121212);
  int _selectedIndex = 0;
  bool _isBootstrappingProducts = true;

  @override
  void initState() {
    super.initState();
    ref.listenManual<MemberState>(memberStateProvider, (previous, next) {
      final message = next.errorMessage;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.errorMessage &&
          mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });
    Future.microtask(() async {
      ref.read(membershipDramaProvider.notifier).load();
      await ref.read(membershipProductsProvider.notifier).loadVipProducts();
      if (mounted) {
        setState(() {
          _isBootstrappingProducts = false;
        });
      }
    });
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    context.go('/profile');
  }

  Future<void> _handlePurchase(SubscriptionProduct product) async {
    final l10n = AppLocalizations.of(context);
    final authState = ref.read(authProvider);

    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.membershipLoginBeforeSubscribe)),
        );
      }
      context.push('/auth/login?redirect=/membership');
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

    if (kIsWeb) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.membershipWebPurchaseUnsupported)),
        );
      }
      return;
    }

    final memberNotifier = ref.read(memberStateProvider.notifier);
    final success = await memberNotifier.purchase(
      selectedProduct: product,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.membershipPurchaseOpened),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recommendState = ref.watch(membershipDramaProvider);
    final memberState = ref.watch(memberStateProvider);
    final membershipProductsState = ref.watch(membershipProductsProvider);
    final hasProducts = membershipProductsState.products.isNotEmpty;
    final products = hasProducts
        ? membershipProductsState.products
        : const <SubscriptionProduct>[];
    final isInitialProductsLoading = _isBootstrappingProducts ||
        (membershipProductsState.isLoading && !membershipProductsState.hasLoaded);

    if (_selectedIndex >= products.length && products.isNotEmpty) {
      _selectedIndex = 0;
    }

    if (memberState.isVip && !memberState.isExpired) {
      return _buildActiveView(l10n, memberState, products);
    }

    return GradientScaffold(
      bottomBackgroundColor: _membershipBottomColor,
      bottomNavigationBar:
          isInitialProductsLoading ? null : _buildBottomPayButton(l10n, memberState, products),
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: _membershipBottomColor),
          ),
          SingleChildScrollView(
            child: Column(
              children: [
                _buildTopImage(),
                if (isInitialProductsLoading)
                  _buildInitialProductsLoadingState(context)
                else ...[
                  _buildVipOptions(l10n, products, membershipProductsState.isLoading),
                  _buildDramaSection(recommendState),
                  _buildBenefitsSection(l10n),
                  _buildBottomSpacer(context),
                ],
              ],
            ),
          ),
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

  /// 1. 顶部图片
  Widget _buildTopImage() {
    return Stack(
      children: [
        Image.asset(
          'assets/images/vip_banner.png',
          width: double.infinity,
          errorBuilder: (_, __, ___) => Container(
            height: 379,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF5D4391), Color(0xFF1F2025)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVipOptions(
    AppLocalizations l10n,
    List<SubscriptionProduct> products,
    bool isLoading,
  ) {
    if (isLoading && products.isEmpty) {
      return const SizedBox.shrink();
    }

    if (products.isEmpty) {
      return Container(
        width: double.infinity,
        color: const Color(0xFF121212),
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 0),
        child: const Text(
          'No membership plans available right now.',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w400,
            color: Colors.white70,
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 0),
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
  Widget _buildInitialProductsLoadingState(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;
    final loadingHeight = (viewportHeight - 379 - topPadding).clamp(260.0, double.infinity);

    return SizedBox(
      width: double.infinity,
      height: loadingHeight,
      child: const ColoredBox(
        color: Color(0xFF121212),
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildDramaSection(MembershipDramaState recommendState) {
    final dramas = recommendState.vipZone.isNotEmpty
        ? recommendState.vipZone
        : recommendState.topRecommend;
    final displayDramas = dramas.take(3).toList();
    final showSkeletonCards = displayDramas.isEmpty;

    return Container(
      height: 137,
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(horizontal: 15),
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

  /// 4. Member Benefits 介绍
  Widget _buildBenefitsSection(AppLocalizations l10n) {
    final benefits = [
      l10n.membership_benefits_unlockEpisodes,
      l10n.membership_benefits_watchHd,
      l10n.membership_benefits_singleDevice,
    ];

    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.fromLTRB(15, 16, 15, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.membership_benefits_title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InkWell(
                    onTap: () => context.push('/profile/report'),
                    borderRadius: BorderRadius.circular(16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1),
                          ),
                          child: const Center(
                            child: Text(
                              '?',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.membership_benefits_complaint,
                          style: const TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...List.generate(benefits.length, (index) {
            return Padding(
              padding: EdgeInsets.only(bottom: index == benefits.length - 1 ? 0 : 8),
              child: Text(
                '${index + 1}、${benefits[index]}',
                style: const TextStyle(
                  fontWeight: FontWeight.w400,
                  fontSize: 13,
                  color: Colors.white,
                ),
              ),
            );
          }),
          const SizedBox(height: 10),
          Text(
            l10n.membership_benefits_tipsLabel,
            style: const TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '1、${l10n.membership_benefits_tipContent}',
            style: const TextStyle(
              fontWeight: FontWeight.w400,
              fontSize: 13,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSpacer(BuildContext context) {
    final height = _bottomButtonHeight + _bottomButtonTopSpacing;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: const ColoredBox(color: _membershipBottomColor),
    );
  }

  /// 5. 底部支付按钮
  Widget _buildBottomPayButton(
    AppLocalizations l10n,
    MemberState memberState,
    List<SubscriptionProduct> products,
  ) {
    final product = _selectedIndex < products.length ? products[_selectedIndex] : null;
    final buttonLabel = product != null ? 'Pay ${product.price.trim()}' : 'Pay';

    return ColoredBox(
      color: const Color(0xFF121212),
      child: SafeArea(
        top: false,
        left: false,
        right: false,
        bottom: false,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            16,
            _bottomButtonTopSpacing,
            16,
            MediaQuery.of(context).padding.bottom + _bottomButtonBottomSpacing,
          ),
          child: SizedBox(
            width: double.infinity,
            height: _bottomButtonHeight,
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
      bottomBackgroundColor: _membershipBottomColor,
      bottomNavigationBar: _buildBottomPayButton(l10n, memberState, products),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                _buildTopImage(),
                _buildVipOptions(l10n, products, false),
                _buildActiveInfo(memberState, l10n),
                _buildBenefitsSection(l10n),
                _buildBottomSpacer(context),
              ],
            ),
          ),
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

  Widget _buildActiveInfo(MemberState memberState, AppLocalizations l10n) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
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

  ({String symbol, String amount}) _parsePriceParts(String price) {
    final cleaned = price.replaceAll(RegExp(r'[\u0000-\u001F\u007F\u200E\u200F\u202A-\u202E]'), '');
    final trimmed = cleaned.trim();
    if (trimmed.isEmpty) {
      return (symbol: '', amount: '');
    }

    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
    final match = RegExp(r'([^\d.,]*)([\d][\d.,]*)([^\d.,]*)').firstMatch(compact);
    if (match == null) {
      return (symbol: '', amount: trimmed);
    }

    final leadingSymbol = match.group(1) ?? '';
    final amount = match.group(2) ?? trimmed;
    final trailingSymbol = match.group(3) ?? '';
    final symbol = leadingSymbol.isNotEmpty ? leadingSymbol : trailingSymbol;

    return (symbol: symbol, amount: amount);
  }

  @override
  Widget build(BuildContext context) {
    final priceParts = _parsePriceParts(product.price);
    final amount = priceParts.amount;
    final originalPrice = product.originalPrice;
    final originalPriceParts = _parsePriceParts(originalPrice);
    final hasOriginalPrice =
        originalPrice.isNotEmpty && originalPrice != product.price;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 60,
        margin: const EdgeInsets.only(bottom: 15),
        padding: const EdgeInsets.symmetric(horizontal: 15),
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
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (hasOriginalPrice) ...[
                  Text(
                    originalPriceParts.amount,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 7),
                ],
                ShaderMask(
                  shaderCallback: (bounds) => _priceGradient.createShader(
                    Rect.fromLTWH(0, 0, bounds.width, bounds.height),
                  ),
                  blendMode: BlendMode.srcIn,
                  child: const Text(
                    r'$',
                    style: TextStyle(
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
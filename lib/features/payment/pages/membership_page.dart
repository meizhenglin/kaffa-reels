import 'package:flutter/foundation.dart';
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
  const MembershipPage({super.key, this.backTarget});

  final String? backTarget;

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
  bool _isCheckingPendingPayments = true;

  @override
  void initState() {
    super.initState();
    ref.listenManual<MemberState>(memberStateProvider, (previous, next) {
      final message = next.errorMessage;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.errorMessage &&
          mounted) {
        // Map special error codes to localized messages
        String displayMessage = message;
        if (message == 'itemAlreadyOwned') {
          final l10n = AppLocalizations.of(context);
          displayMessage = l10n.membershipItemAlreadyOwned;
        }
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                displayMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black),
              ),
              backgroundColor: const Color(0xFFFFFFFF),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
      }
    });
    Future.microtask(() async {
      // 检查并重试待处理的支付回调
      await ref.read(memberStateProvider.notifier).checkAndRetryPendingPayments();
      if (mounted) {
        setState(() {
          _isCheckingPendingPayments = false;
        });
      }

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
    if (widget.backTarget != null && widget.backTarget!.isNotEmpty) {
      context.go(widget.backTarget!);
      return;
    }
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

  /// 检查产品是否已拥有
  Future<bool> _checkIfProductAlreadyOwned(SubscriptionProduct product) async {
    try {
      final paymentService = PaymentService.instance;
      final purchases = await paymentService.queryExistingPurchases();
      for (final purchase in purchases) {
        if ((purchase.status == PurchaseStatus.purchased ||
                purchase.status == PurchaseStatus.restored) &&
            purchase.productID == product.id) {
          return true;
        }
      }
    } catch (e) {
      debugPrint('Error checking existing purchases: $e');
    }
    return false;
  }

  Future<void> _handlePurchase(SubscriptionProduct product) async {
    final l10n = AppLocalizations.of(context);
    final authState = ref.read(authProvider);

    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      await openMembershipPage(context, ref);
      return;
    }

    // 显示购买确认对话框
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

    // 检查是否已拥有此订阅
    final isAlreadyOwned = await _checkIfProductAlreadyOwned(product);
    if (isAlreadyOwned && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              l10n.membershipItemAlreadyOwned,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black),
            ),
            backgroundColor: const Color(0xFFFFFFFF),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      return;
    }

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
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.membershipPurchaseOpened),
        ),
      );
    }
    // Don't pop here - wait for purchaseStream callback to handle result
  }

  @override
  Widget build(BuildContext context) {
    print('>>>>>>>>>>>>> MembershipPage.build() CALLED <<<<<<<<<<<<');
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
    
    // DEBUG - show VIP status in console
    final isVipAsync = ref.watch(isVipProvider);
    final isVipDebug = isVipAsync.valueOrNull ?? false;
    print('[MembershipPage] isLoading: ${membershipProductsState.isLoading}, hasProducts: $hasProducts, isVip: $isVipDebug');

    if (_selectedIndex >= products.length && products.isNotEmpty) {
      _selectedIndex = 0;
    }

    // Note: Don't block purchase flow for VIP users - they can still buy to upgrade/downgrade
    // Google Play handles the logic automatically

    // 检查待处理支付时的加载状态
    if (_isCheckingPendingPayments) {
      return GradientScaffold(
        bottomBackgroundColor: _membershipBottomColor,
        body: Container(
          color: _membershipBottomColor,
          child: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  'Checking payment status...',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      );
    }

    debugPrint('[MembershipPage] build called. isInitialProductsLoading: $isInitialProductsLoading, products.length: ${products.length}');

    return GradientScaffold(
      bottomBackgroundColor: _membershipBottomColor,
      bottomNavigationBar:
          isInitialProductsLoading ? null : _buildBottomPayButton(l10n, memberState, products),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              const Positioned.fill(
                child: ColoredBox(color: _membershipBottomColor),
              ),
              Positioned.fill(
                child: Column(
                  children: [
                    _buildTopImage(),
                    Expanded(
                      child: isInitialProductsLoading
                          ? _buildInitialProductsLoadingState(context)
                          : SingleChildScrollView(
                              child: Column(
                                children: [
                                  _buildVipOptions(l10n, products, membershipProductsState.isLoading),
                                  _buildDramaSection(recommendState),
                                  _buildBenefitsSection(l10n),
                                  // TODO: 下版本开启 K 币充值功能
                                  // _buildRechargeSection(context),
                                  _buildBottomSpacer(context),
                                ],
                              ),
                            ),
                    ),
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
          );
        },
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

  String _localizedProductTitleById(AppLocalizations l10n, String productId) {
    final name = productId.toLowerCase();
    if (name.contains('year')) {
      return l10n.membership_yearly;
    }
    if (name.contains('quarter')) {
      return l10n.membership_quarterly;
    }
    if (name.contains('month')) {
      return l10n.membership_monthly;
    }
    return productId;
  }

  /// 通过产品ID或goodsCode查找订阅产品
  SubscriptionProduct? _findProductById(String productIdOrCode) {
    final membershipProductsState = ref.read(membershipProductsProvider);
    final products = membershipProductsState.products;

    // 先尝试精确匹配 id（productId）
    for (final product in products) {
      if (product.googlePlayId == productIdOrCode ||
          product.appStoreId == productIdOrCode ||
          product.id == productIdOrCode) {
        return product;
      }
    }

    // 再尝试匹配 goodsCode
    for (final product in products) {
      final productId = PaymentService.instance.getProductIdForType(product.id);
      if (productId == productIdOrCode) {
        return product;
      }
    }

    return null;
  }

  /// 3. 剧卡片横向滚动区：高 137
  Widget _buildInitialProductsLoadingState(BuildContext context) {
    final viewportHeight = MediaQuery.of(context).size.height;
    final topPadding = MediaQuery.of(context).padding.top;

    return SizedBox(
      width: double.infinity,
      height: viewportHeight - topPadding,
      child: const ColoredBox(
        color: Color(0xFF121212),
        child: Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildDramaSection(MembershipDramaState recommendState) {
    // DEBUG: 打印所有相关信息
    print('==========================================');
    print('[_buildDramaSection CALLED]');
    print('status: ${recommendState.status}');
    print('vipZone.length: ${recommendState.vipZone.length}');
    print('topRecommend.length: ${recommendState.topRecommend.length}');
    if (recommendState.vipZone.isNotEmpty) {
      print('FIRST VIP: ${recommendState.vipZone.first.title}');
      print('FIRST VIP cover: ${recommendState.vipZone.first.coverUrl}');
    }
    print('==========================================');
    
    final dramas = recommendState.vipZone.isNotEmpty
        ? recommendState.vipZone
        : recommendState.topRecommend;
    final displayDramas = dramas.take(3).toList();
    final showSkeletonCards = displayDramas.isEmpty;
    print('[_buildDramaSection] displayDramas.length: ${displayDramas.length}, showSkeletonCards: $showSkeletonCards');

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

  /// 5. K币充值入口
  Widget _buildRechargeSection(BuildContext context) {
    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.fromLTRB(15, 16, 15, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recharge Coins',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: () => context.push('/recharge'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.monetization_on, color: Colors.amber, size: 32),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Get Coins',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Watch premium content',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.amber, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 6. 底部支付按钮
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
    List<SubscriptionProduct> products, {
    bool isInitialProductsLoading = false,
  }) {
    final recommendState = ref.watch(membershipDramaProvider);
    return GradientScaffold(
      bottomBackgroundColor: _membershipBottomColor,
      bottomNavigationBar: isInitialProductsLoading ? null : _buildBottomPayButton(l10n, memberState, products),
      body: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                _buildTopImage(),
                Expanded(
                  child: isInitialProductsLoading
                      ? _buildInitialProductsLoadingState(context)
                      : SingleChildScrollView(
                          child: Column(
                            children: [
                              _buildVipOptions(l10n, products, false),
                              _buildDramaSection(recommendState),
                              _buildBenefitsSection(l10n),
                              _buildBottomSpacer(context),
                            ],
                          ),
                        ),
                ),
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

  // Widget _buildActiveInfo(MemberState memberState, AppLocalizations l10n) {
  //   return Container(
  //     margin: const EdgeInsets.symmetric(horizontal: 15),
  //     padding: const EdgeInsets.all(16),
  //     decoration: BoxDecoration(
  //       gradient: const LinearGradient(
  //         colors: [Color(0xFFFFD700), Color(0xFFFF8C00)],
  //       ),
  //       borderRadius: BorderRadius.circular(16),
  //     ),
  //     child: Column(
  //       children: [
  //         const Icon(Icons.workspace_premium, size: 48, color: Colors.white),
  //         const SizedBox(height: 4),
  //         Text(
  //           'Expires: ${_formatDate(memberState.expireDate)}  •  ${memberState.daysRemaining ?? 0} days left',
  //           style: TextStyle(
  //             color: Colors.white.withAlpha(204),
  //             fontSize: 13,
  //           ),
  //         ),
  //       ],
  //     ),
  //   );
  // }

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
    debugPrint('[_DramaCard] coverUrl: $_coverUrl, drama.title: ${drama.title}');
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          debugPrint('[_DramaCard] constraints: ${constraints.maxWidth}x${constraints.maxHeight}');
          return Stack(
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
          );
        },
      ),
    );
  }
}
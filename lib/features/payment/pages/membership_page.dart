import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_snack_bar.dart';
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
  bool _hasActiveSubscription = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual<MemberState>(memberStateProvider, (previous, next) {
      final message = next.errorMessage;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.errorMessage &&
          mounted) {
        String displayMessage = message;
        if (message == 'itemAlreadyOwned') {
          final l10n = AppLocalizations.of(context);
          displayMessage = l10n.membershipItemAlreadyOwned;
        }
        AppSnackBar.show(context, message: displayMessage);
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

      // 从服务器获取VIP状态
      final authState = ref.read(authProvider);
      final isVip = authState.user?.isVip ?? false;
      final vipExpireDate = authState.user?.vipExpireDate;
      final hasActive = isVip && (vipExpireDate == null || vipExpireDate.isAfter(DateTime.now()));

      // 调试打印
      debugPrint('[MembershipPage] ===== VIP 状态调试 =====');
      debugPrint('[MembershipPage] userId: ${authState.user?.id}');
      debugPrint('[MembershipPage] isVip: $isVip');
      debugPrint('[MembershipPage] vipExpireDate: $vipExpireDate');
      debugPrint('[MembershipPage] hasActiveSubscription: $hasActive');
      debugPrint('[MembershipPage] 当前时间: ${DateTime.now()}');
      debugPrint('[MembershipPage] =========================');

      if (mounted) {
        setState(() {
          _isBootstrappingProducts = false;
          _hasActiveSubscription = hasActive;
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

  Future<void> _handlePurchase(SubscriptionProduct product) async {
    final l10n = AppLocalizations.of(context);
    final authState = ref.read(authProvider);

    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      await openMembershipPage(context, ref);
      return;
    }

    // 从服务器获取VIP状态（包含过期时间检查）
    final isVip = authState.user?.isVip ?? false;
    final vipExpireDate = authState.user?.vipExpireDate;
    final hasActiveSubscription = isVip && 
        (vipExpireDate == null || vipExpireDate.isAfter(DateTime.now()));

    // 调试打印
    debugPrint('[MembershipPage] ===== 点击购买按钮 =====');
    debugPrint('[MembershipPage] userId: ${authState.user?.id}');
    debugPrint('[MembershipPage] isVip: $isVip');
    debugPrint('[MembershipPage] vipExpireDate: $vipExpireDate');
    debugPrint('[MembershipPage] hasActiveSubscription: $hasActiveSubscription');
    debugPrint('[MembershipPage] 当前时间: ${DateTime.now()}');
    debugPrint('[MembershipPage] =========================');

    if (hasActiveSubscription) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
      }
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

    if (confirmed != true) {
      // 用户取消，清理可能残留的待处理订单状态
      ref.read(memberStateProvider.notifier).clearPendingOrder();
      return;
    }

    // 显示加载状态
    _isPurchasing = true;
    if (mounted) setState(() {});

    // 订阅商品允许通过 Google Play 自动升级/降级，不在本地拦截重复购买

    if (kIsWeb) {
      _isPurchasing = false;
      if (mounted) {
        setState(() {});
        AppSnackBar.show(context, message: l10n.membershipWebPurchaseUnsupported);
      }
      return;
    }

    final memberNotifier = ref.read(memberStateProvider.notifier);
    final success = await memberNotifier.purchase(
      selectedProduct: product,
    );

    _isPurchasing = false;
    if (mounted) setState(() {});

    if (success && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final activatedLabel = switch (product.type) {
        SubscriptionPeriod.monthly => l10n.membershipSubscriptionActivatedMonthly,
        SubscriptionPeriod.quarterly =>
          l10n.membershipSubscriptionActivatedQuarterly,
        SubscriptionPeriod.yearly => l10n.membershipSubscriptionActivatedYearly,
      };
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            activatedLabel,
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
    } else if (!success && mounted) {
      // 显示真实的错误信息，而不是误导性的 "Google Play opened" 提示
      final memberState = ref.read(memberStateProvider);
      final errorMsg = memberState.errorMessage;
      if (errorMsg != null && errorMsg.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.membershipPurchaseOpened),
          ),
        );
      }
    }
  }

  bool _isPurchasing = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recommendState = ref.watch(membershipDramaProvider);
    final memberState = ref.watch(memberStateProvider);
    final membershipProductsState = ref.watch(membershipProductsProvider);
    final isVip = ref.watch(isVipProvider);
    final hasProducts = membershipProductsState.products.isNotEmpty;
    final products = hasProducts
        ? membershipProductsState.products
        : const <SubscriptionProduct>[];
    final isInitialProductsLoading = _isBootstrappingProducts ||
        (membershipProductsState.isLoading && !membershipProductsState.hasLoaded);

    if (_selectedIndex >= products.length && products.isNotEmpty) {
      _selectedIndex = 0;
    }

    // 检查待处理支付时的加载状态 - 这个需要全屏 loading
    if (_isCheckingPendingPayments) {
      return GradientScaffold(
        bottomBackgroundColor: _membershipBottomColor,
        body: Container(
          color: _membershipBottomColor,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Colors.white),
                SizedBox(height: 16),
                Text(
                  l10n.checkingPaymentStatus,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 如果是 VIP 用户，显示会员专属视图
    if (isVip) {
      return _buildActiveView(
        l10n,
        memberState,
        products,
        isInitialProductsLoading: isInitialProductsLoading,
      );
    }

    // 非 VIP 用户 - 普通购买视图
    return GradientScaffold(
      bottomBackgroundColor: _membershipBottomColor,
      bottomNavigationBar:
          isInitialProductsLoading ? null : _buildBottomPayButton(l10n, memberState, products),
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: _membershipBottomColor),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildTopImage(),
                  // 商品列表区域 - 独立处理 loading 状态
                  if (isInitialProductsLoading)
                    _buildProductsLoadingState(context)
                  else
                    _buildVipOptions(l10n, products, false, hasActiveSubscription: _hasActiveSubscription),
                  _buildDramaSection(recommendState),
                  _buildBenefitsSection(l10n, products),
                  // TODO: 下版本开启 K 币充值功能
                  // _buildRechargeSection(context),
                  _buildBottomSpacer(context),
                ],
              ),
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

  /// 商品列表加载状态
  Widget _buildProductsLoadingState(BuildContext context) {
    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: CircularProgressIndicator(color: Colors.white),
        ),
      ),
    );
  }

  /// 1. 顶部图片
  Widget _buildTopImage() {
    return SizedBox(
      width: double.infinity,
      child: Image.asset(
        'assets/images/vip_banner.png',
        width: double.infinity,
        fit: BoxFit.fitWidth,
        errorBuilder: (_, __, ___) => Container(
          height: 380,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF5D4391), Color(0xFF1F2025)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVipOptions(
    AppLocalizations l10n,
    List<SubscriptionProduct> products,
    bool isLoading, {
    bool hasActiveSubscription = false,
  }) {
    if (isLoading && products.isEmpty) {
      return const SizedBox.shrink();
    }

    if (products.isEmpty) {
      return Container(
        width: double.infinity,
        color: const Color(0xFF121212),
        padding: const EdgeInsets.fromLTRB(15, 16, 15, 0),
        child: Text(
          l10n.noMembershipPlans,
          style: const TextStyle(
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
            isSubscribed: hasActiveSubscription,
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

  Widget _buildDramaSection(MembershipDramaState recommendState) {
    final dramas = recommendState.vipZone.isNotEmpty
        ? recommendState.vipZone
        : recommendState.topRecommend;
    final displayDramas = dramas.take(3).toList();

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
                  : _DramaCardPlaceholder(),
            ),
          );
        }),
      ),
    );
  }

  /// 4. Member Benefits 介绍
  Widget _buildBenefitsSection(AppLocalizations l10n, List<SubscriptionProduct> products) {
    final benefits = [
      l10n.membership_benefits_unlockEpisodes,
      l10n.membership_benefits_watchHd,
      l10n.membership_benefits_singleDevice,
    ];
    final planNotes = _planNoteEntries(l10n).toList();
    final items = [
      ...benefits,
      ...planNotes,
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
          ...List.generate(items.length, (index) {
            return Padding(
              padding: EdgeInsets.only(bottom: index == items.length - 1 ? 0 : 8),
              child: Text(
                '${index + 1}、${items[index]}',
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
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.membership_benefits_tipContent,
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

  Iterable<String> _planNoteEntries(AppLocalizations l10n) sync* {
    yield l10n.membership_benefits_planNoteMonthly;
    yield l10n.membership_benefits_planNoteQuarterly;
    yield l10n.membership_benefits_planNoteYearly;
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
  Widget _buildRechargeSection(BuildContext context, AppLocalizations l10n) {
    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.fromLTRB(15, 16, 15, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.rechargeCoinsTitle,
            style: const TextStyle(
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.getCoins,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.watchPremiumContent,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
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
    final isDisabled = _hasActiveSubscription || product == null;
    final buttonLabel = _hasActiveSubscription
        ? l10n.alreadySubscribed
        : (product != null ? '${l10n.pay} ${product.price.trim()}' : l10n.pay);

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
                onPressed: isDisabled ? null : () => _handlePurchase(product),
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
          const Positioned.fill(
            child: ColoredBox(color: _membershipBottomColor),
          ),
          Positioned.fill(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildTopImage(),
                  if (isInitialProductsLoading)
                    _buildProductsLoadingState(context)
                  else
                    _buildVipOptions(l10n, products, false, hasActiveSubscription: _hasActiveSubscription),
                  _buildDramaSection(recommendState),
                  _buildBenefitsSection(l10n, products),
                  _buildBottomSpacer(context),
                ],
              ),
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
    this.isSubscribed = false,
  });

  final SubscriptionProduct product;
  final String title;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isSubscribed;

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
      onTap: isSubscribed ? null : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 60,
          margin: const EdgeInsets.only(bottom: 15),
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/images/vip_item_bg.png'),
              fit: BoxFit.fill,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: [
                Image.asset(
                  isSubscribed
                      ? 'assets/images/vip_selected.png'
                      : (isSelected
                          ? 'assets/images/vip_selected.png'
                          : 'assets/images/vip_notselected.png'),
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
        builder: (context, constraints) {
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
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../core/utils/localized_badge_assets.dart';
import '../../../components/preload_network_image.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/config/build_flavor.dart';
import '../../recommend/providers/recommend_provider.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/models/subscription_product.dart';
import '../../payment/providers/membership_provider.dart';
import '../../payment/services/payment_service.dart';
import '../../payment/models/payment_channel.dart';
import '../../payment/services/unified_payment_handler.dart';
import '../../payment/widgets/payment_channel_selector.dart';
import '../../payment/widgets/payment_loading_overlay.dart';
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
  bool _hasActiveSubscription = false;

  /// 最近一次已经展示过的错误文案。
  /// memberStateProvider 的 listener 和购买回调都会弹 SnackBar，
  /// 用它去重，避免同一个错误弹两次。
  String? _lastShownError;

  @override
  void initState() {
    super.initState();
    ref.listenManual<MemberState>(memberStateProvider, (previous, next) {
      final message = next.errorMessage;
      if (message != null &&
          message.isNotEmpty &&
          message != previous?.errorMessage &&
          mounted) {
        final l10n = AppLocalizations.of(context);
        String displayMessage = message;
        if (message == 'itemAlreadyOwned') {
          displayMessage = l10n.membershipItemAlreadyOwned;
        } else {
          displayMessage = _localizePlayFailure(message, l10n) ?? message;
        }
        // 把 Play 给出的原始 debugMessage 带到提示上（测试排障用）：
        // 本地化文案只说「结算不可用」，Play 的 debugMessage 才是
        // 真正原因（账号无资格 / 应用未发布 / 地区不支持等）。
        final playDebug = PaymentService.instance.lastPlayDebugMessage;
        if (playDebug != null && playDebug.isNotEmpty) {
          displayMessage = '$displayMessage\n(Play: $playDebug)';
        }
        final iosDebug = PaymentService.instance.lastIosDebugMessage;
        if (iosDebug != null && iosDebug.isNotEmpty) {
          displayMessage = '$displayMessage\n(App Store: $iosDebug)';
        }
        _lastShownError = displayMessage;
        AppSnackBar.show(context, message: displayMessage);
      }
    });

    // 并行加载商品列表和检查待处理支付（不阻塞UI渲染）
    Future.microtask(() async {
      // 立即开始加载商品列表
      ref.read(membershipProductsProvider.notifier).loadVipProducts();
      ref.read(membershipDramaProvider.notifier).load();

      // 立即允许显示商品列表（loading状态由provider控制）
      if (mounted) {
        setState(() {
          _isBootstrappingProducts = false;
        });
      }

      // 在后台检查待处理支付
      await ref
          .read(memberStateProvider.notifier)
          .checkAndRetryPendingPayments();
    });

    // 检查VIP状态
    //
    // 【必须响应式，不能只在进页面时读一次】
    // 之前这里是一个 100ms 后的一次性 setState：购买成功后
    // purchase() 内部会 refreshUserInfo（authProvider 更新），
    // 但 _hasActiveSubscription 没有任何代码跟着更新，
    // 导致底部按钮 / 套餐卡片停留在旧状态，要退出重进才刷新。
    // 现在监听 authProvider 的变化，会员状态一变就同步。
    void syncActiveSubscription() {
      if (!mounted) return;
      final authState = ref.read(authProvider);
      final isVip = authState.user?.isVip ?? false;
      final vipExpireDate = authState.user?.vipExpireDate;
      final hasActive =
          isVip &&
          (vipExpireDate == null || vipExpireDate.isAfter(DateTime.now()));
      if (hasActive != _hasActiveSubscription) {
        setState(() {
          _hasActiveSubscription = hasActive;
        });
      }
    }

    ref.listenManual(authProvider, (_, _) => syncActiveSubscription());
    Future.microtask(() async {
      await Future.delayed(Duration(milliseconds: 100));
      if (!mounted) return;
      syncActiveSubscription();
    });
  }

  /// 把 Play 侧的稳定失败原因码映射成多语言提示。
  ///
  /// 返回 null 表示这个字符串不是已知的 Play 失败码，调用方应原样展示。
  ///
  /// 关键点：Play **没有受理请求**（SERVICE_UNAVAILABLE / 商店缺失 / 网络不通）
  /// 和「商品没配好」是两类完全不同的故障，提示必须分开，
  /// 否则用户会去查错的方向。
  String? _localizePlayFailure(String code, AppLocalizations l10n) {
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
      case 'play-item-not-found':
      case 'play-item-unavailable':
      case 'play-developer-error':
        return l10n.membershipPlayItemNotAvailable;
      case 'play-no-eligible-offer':
        return l10n.membershipPlayNoEligibleOffer;
      case 'play-not-subscription':
        return l10n.membershipPlayNotSubscription;
      // iOS StoreKit 侧的失败码（PaymentService.lastIosFailureCode）。
      // 文案指向 App Store，不要让 iOS 用户看到「去查 Google Play」。
      case 'ios-store-unavailable':
        return l10n.membershipIosStoreUnavailable;
      case 'ios-network-error':
        return l10n.membershipIosNetworkError;
      case 'ios-store-error':
        return l10n.membershipIosStoreError;
      case 'ios-item-not-found':
        return l10n.membershipIosItemNotAvailable;
      // 支付已成功但后端回调没确认（收据校验失败 / 后端接口异常）。
      case 'store-callback-failed':
        return l10n.membershipStoreCallbackFailed;
      default:
        return null;
    }
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

    // VIP?含?
    final isVip = authState.user?.isVip ?? false;
    final vipExpireDate = authState.user?.vipExpireDate;
    final hasActiveSubscription =
        isVip &&
        (vipExpireDate == null || vipExpireDate.isAfter(DateTime.now()));

    // ?印

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

    // 示购买确认对话
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
      // 可??订
      ref.read(memberStateProvider.notifier).clearPendingOrder();
      return;
    }

    // 示载
    _isPurchasing = true;
    if (mounted) setState(() {});

    // 订??许? Google Play 级/级不复购买

    // Web + Google flavor: Google Play Billing API is not callable from
    // a browser. Refuse and surface the localized "unsupported" copy.
    // Web + platform flavor falls through to HaiPay (works in WebView /
    // external browser) below.
    if (kIsWeb && BuildFlavor.isGoogle) {
      _isPurchasing = false;
      if (mounted) {
        setState(() {});
        AppSnackBar.show(
          context,
          message: l10n.membershipWebPurchaseUnsupported,
        );
      }
      return;
    }

    // Google 渠道包（Android）与 iOS：跳过 HaiPay 选择器，直接走商店内购
    // （iOS 上是 StoreKit，回调自动路由 /notice/apple）。
    if (shouldUseStoreDirectly()) {
      final memberNotifier = ref.read(memberStateProvider.notifier);
      // 【支付统一遮罩】订阅确认后全屏拦截交互；超时只解除遮罩，
      // 购买在后台继续（内部有 120 秒超时与结果提示）。
      try {
        await PaymentLoadingOverlay.run(
          context,
          message: l10n.paymentProcessing,
          timeout: const Duration(seconds: 130),
          task: () => memberNotifier.purchase(selectedProduct: product),
        );
      } on PaymentProcessingTimeoutException {
        if (mounted) {
          AppSnackBar.show(context, message: l10n.paymentProcessingTimeout);
        }
      }
      _isPurchasing = false;
      if (mounted) setState(() {});
      return;
    }

    final handler = ref.read(unifiedPaymentHandlerProvider);
    final haiPayMethods = await handler.fetchHaiPayMethods(
      price: product.price,
      productName: product.displayName ?? product.id,
    );

    final channel = await PaymentChannelSelector.show(
      context: context,
      price: product.price,
      productName: product.displayName ?? product.id,
      haiPayMethods: haiPayMethods,
    );

    if (channel == null) {
      _isPurchasing = false;
      if (mounted) setState(() {});
      return;
    }

    bool success = false;
    String? errorMessage;

    if (channel.isGooglePlay) {
      final memberNotifier = ref.read(memberStateProvider.notifier);
      // 【支付统一遮罩】同商店直购路径。
      try {
        success = await PaymentLoadingOverlay.run(
          context,
          message: l10n.paymentProcessing,
          timeout: const Duration(seconds: 130),
          task: () => memberNotifier.purchase(selectedProduct: product),
        );
      } on PaymentProcessingTimeoutException {
        if (mounted) {
          AppSnackBar.show(context, message: l10n.paymentProcessingTimeout);
        }
      }
      if (!success) {
        final memberState = ref.read(memberStateProvider);
        errorMessage = memberState.errorMessage;
        // 错误可能是 Play 的稳定原因码，映射成多语言提示。
        if (errorMessage != null) {
          errorMessage =
              _localizePlayFailure(errorMessage, l10n) ?? errorMessage;
        }
      } else {
        // Google Play 购买成功后刷新状态
        ref.read(authProvider.notifier).refreshUserInfo();
        ref.invalidate(isVipProvider);
      }
    } else {
      success = await handler.purchaseVip(
        product: product,
        price: product.price,
        context: context,
        channel: channel,
        onPaymentComplete: (paid) {
          if (paid) {
            ref.read(authProvider.notifier).refreshUserInfo();
            ref.invalidate(isVipProvider);
          }
        },
      );
      if (!success) {
        errorMessage = handler.lastError;
      }
    }

    _isPurchasing = false;
    if (mounted) setState(() {});

    if (success && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final activatedLabel = switch (product.type) {
        SubscriptionPeriod.monthly =>
          l10n.membershipSubscriptionActivatedMonthly,
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
      if (errorMessage != null &&
          errorMessage.isNotEmpty &&
          errorMessage != _lastShownError) {
        _lastShownError = errorMessage;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
        );
      }
      // WebView 内部已有提示，关闭时不需要额外显示
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
    final isInitialProductsLoading =
        _isBootstrappingProducts ||
        (membershipProductsState.isLoading &&
            !membershipProductsState.hasLoaded);

    if (_selectedIndex >= products.length && products.isNotEmpty) {
      _selectedIndex = 0;
    }

    // VIP 已订阅用户显示
    if (isVip) {
      return _buildActiveView(
        l10n,
        memberState,
        products,
        isInitialProductsLoading: isInitialProductsLoading,
      );
    }

    // 非VIP用户 - 立即显示页面内容
    return GradientScaffold(
      bottomBackgroundColor: _membershipBottomColor,
      bottomNavigationBar: isInitialProductsLoading
          ? null
          : _buildBottomPayButton(l10n, memberState, products),
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
                  // 商品列表 - 显示loading状态
                  if (isInitialProductsLoading)
                    _buildProductsLoadingState(context)
                  else
                    _buildVipOptions(
                      l10n,
                      products,
                      false,
                      hasActiveSubscription: _hasActiveSubscription,
                    ),
                  _buildDramaSection(recommendState),
                  _buildBenefitsSection(l10n, products),
                  // TODO: ?启 K 币??
                  // _buildRechargeSection(context),
                  _buildBottomSpacer(context),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            top: MediaQuery.of(context).padding.top + 8,
            start: 8,
            child: RtlBackButton(onPressed: _handleBack, color: Colors.white),
          ),
        ],
      ),
    );
  }

  /// ??表载
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

  /// 1. 顶?
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

  /// ?产ID?goodsCode订?产
  SubscriptionProduct? _findProductById(String productIdOrCode) {
    final membershipProductsState = ref.read(membershipProductsProvider);
    final products = membershipProductsState.products;

    // ?尝精确 idproductId
    for (final product in products) {
      if (product.googlePlayId == productIdOrCode ||
          product.appStoreId == productIdOrCode ||
          product.id == productIdOrCode) {
        return product;
      }
    }

    // 尝 goodsCode
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
          final drama = index < displayDramas.length
              ? displayDramas[index]
              : null;
          return Expanded(
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: index == 2 ? 0 : 12),
              child: drama != null
                  ? _DramaCard(
                      drama: drama,
                      onTap: () => openDramaPlayerWithVipCheck(
                        context: context,
                        drama: drama,
                        authState: ref.read(authProvider),
                        memberState: ref.read(memberStateProvider),
                      ),
                    )
                  : _DramaCardPlaceholder(),
            ),
          );
        }),
      ),
    );
  }

  /// 4. Member Benefits 绍
  Widget _buildBenefitsSection(
    AppLocalizations l10n,
    List<SubscriptionProduct> products,
  ) {
    final benefits = [
      l10n.membership_benefits_unlockEpisodes,
      l10n.membership_benefits_watchHd,
      l10n.membership_benefits_singleDevice,
    ];
    final planNotes = _planNoteEntries(l10n).toList();
    final items = [...benefits, ...planNotes];

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
              padding: EdgeInsets.only(
                bottom: index == items.length - 1 ? 0 : 8,
              ),
              child: Text(
                '${index + 1}. ${items[index]}',
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

  /// 5. K币?口
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
                  const Icon(
                    Icons.monetization_on,
                    color: Colors.amber,
                    size: 32,
                  ),
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
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.amber,
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 6. ?
  Widget _buildBottomPayButton(
    AppLocalizations l10n,
    MemberState memberState,
    List<SubscriptionProduct> products,
  ) {
    final product = _selectedIndex < products.length
        ? products[_selectedIndex]
        : null;
    final isDisabled = _hasActiveSubscription || product == null;
    // 按钮价格兜底带 $：后端下发的 price 可能是裸数字（如 "15"），
    // 显示成 "Pay 15" 很奇怪；已带货币符号（StoreKit 本地化价格
    // 如 "$15.00"、或 "SAR ..."）时保持原样不重复加。
    String? priceLabel;
    if (product != null) {
      final trimmed = product.price.trim();
      priceLabel = RegExp(r'^[\d.,\s]+$').hasMatch(trimmed)
          ? '\$$trimmed'
          : trimmed;
    }
    final buttonLabel = _hasActiveSubscription
        ? l10n.alreadySubscribed
        : (product != null ? '${l10n.pay} $priceLabel' : l10n.pay);

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
                  disabledForegroundColor: const Color(
                    0xFF753900,
                  ).withAlpha(153),
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

  /// 已订?
  Widget _buildActiveView(
    AppLocalizations l10n,
    MemberState memberState,
    List<SubscriptionProduct> products, {
    bool isInitialProductsLoading = false,
  }) {
    final recommendState = ref.watch(membershipDramaProvider);
    return GradientScaffold(
      bottomBackgroundColor: _membershipBottomColor,
      bottomNavigationBar: isInitialProductsLoading
          ? null
          : _buildBottomPayButton(l10n, memberState, products),
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
                    _buildVipOptions(
                      l10n,
                      products,
                      false,
                      hasActiveSubscription: _hasActiveSubscription,
                    ),
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
            child: RtlBackButton(onPressed: _handleBack, color: Colors.white),
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
  //           'Expires: ${_formatDate(memberState.expireDate)}    ${memberState.daysRemaining ?? 0} days left',
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

/// 个 VIP ?项
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
    final cleaned = price.replaceAll(
      RegExp(r'[\u0000-\u001F\u007F\u200E\u200F\u202A-\u202E]'),
      '',
    );
    final trimmed = cleaned.trim();
    if (trimmed.isEmpty) {
      return (symbol: '', amount: '');
    }

    final compact = trimmed.replaceAll(RegExp(r'\s+'), '');
    final match = RegExp(
      r'([^\d.,]*)([\d][\d.,]*)([^\d.,]*)',
    ).firstMatch(compact);
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

/// 卡?
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

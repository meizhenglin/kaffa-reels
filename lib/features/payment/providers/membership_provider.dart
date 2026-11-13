import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/service/pay_service.dart';
import '../../../core/storage/storage_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/recharge_product.dart';
import '../models/subscription_product.dart';
import '../services/payment_service.dart';
import '../services/receipt_verification.dart';

/// Member subscription state - simplified to only track purchase token
class MemberState {
  const MemberState({
    this.purchaseToken,
    this.isLoading = false,
    this.errorMessage,
    this.pendingOrderId,
    this.pendingProductId,
    this.pendingSubscriptionType,
    this.pendingGoodsId,
  });

  final String? purchaseToken;
  final bool isLoading;
  final String? errorMessage;
  final String? pendingOrderId;
  final String? pendingProductId;
  final String? pendingSubscriptionType;

  /// 待支付订单对应的后台商品 ID（rechargeGoodsConfig 的 id）。
  ///
  /// 后端回调体里要带 `goodsId`（会员对应的是 `payConfigType=0`），
  /// 没有它后端只能靠 orderNo 反查。
  final int? pendingGoodsId;

  MemberState copyWith({
    String? purchaseToken,
    bool? isLoading,
    String? errorMessage,
    String? pendingOrderId,
    String? pendingProductId,
    String? pendingSubscriptionType,
    int? pendingGoodsId,
    bool clearPendingOrder = false,
    bool clearError = false,
    bool clearPurchaseToken = false,
  }) {
    return MemberState(
      // 【重要】clearPendingOrder 只清「待支付订单」，
      // **不能**顺带把 purchaseToken 清成 null。
      //
      // 之前 purchaseToken 复用了 clearPendingOrder 这个开关，
      // 于是任何一次 purchase() 失败 / 购买结束都会把「已购买」的标记抹掉，
      // canAccess() / _hasActiveSubscription() 立刻变成 false。
      // 要清 token 请用 clearPurchaseToken。
      purchaseToken: clearPurchaseToken
          ? null
          : (purchaseToken ?? this.purchaseToken),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingOrderId: clearPendingOrder
          ? null
          : (pendingOrderId ?? this.pendingOrderId),
      pendingProductId: clearPendingOrder
          ? null
          : (pendingProductId ?? this.pendingProductId),
      pendingSubscriptionType: clearPendingOrder
          ? null
          : (pendingSubscriptionType ?? this.pendingSubscriptionType),
      pendingGoodsId: clearPendingOrder
          ? null
          : (pendingGoodsId ?? this.pendingGoodsId),
    );
  }
}

class MembershipProductsState {
  const MembershipProductsState({
    this.products = const [],
    this.isLoading = false,
    this.errorMessage,
    this.hasLoaded = false,
  });

  final List<SubscriptionProduct> products;
  final bool isLoading;
  final String? errorMessage;
  final bool hasLoaded;

  MembershipProductsState copyWith({
    List<SubscriptionProduct>? products,
    bool? isLoading,
    String? errorMessage,
    bool? hasLoaded,
    bool clearError = false,
  }) {
    return MembershipProductsState(
      products: products ?? this.products,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      hasLoaded: hasLoaded ?? this.hasLoaded,
    );
  }
}

/// Member state provider
final memberStateProvider =
    StateNotifierProvider<MemberStateNotifier, MemberState>((ref) {
      final notifier = MemberStateNotifier(ref);
      Future.microtask(notifier.initialize);
      ref.onDispose(notifier.dispose);
      return notifier;
    });

final membershipProductsProvider =
    StateNotifierProvider<MembershipProductsNotifier, MembershipProductsState>((
      ref,
    ) {
      return MembershipProductsNotifier(
        ref.read(dioClientProvider),
        ref.read(storageServiceProvider),
      );
    });

/// Recharge products provider for K-Coin recharge (type 1)
final rechargeProductsProvider =
    StateNotifierProvider<RechargeProductsNotifier, RechargeProductsState>((
      ref,
    ) {
      final apiService = ApiService(
        dioClient: ref.read(dioClientProvider),
        storage: ref.read(storageServiceProvider),
      );
      return RechargeProductsNotifier(apiService);
    });

class RechargeProductsNotifier extends StateNotifier<RechargeProductsState> {
  RechargeProductsNotifier(this._apiService)
    : super(const RechargeProductsState());

  final ApiService _apiService;

  Future<void> load() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await _apiService.getRechargeGoodsConfig(
        rechargeGoodsType: 1,
      );

      if (response.isSuccess) {
        final data = response.data;
        List<RechargeGoodsConfigItem> items = [];

        if (data is List) {
          items = data.map((e) => RechargeGoodsConfigItem.fromJson(e)).toList();
        } else if (data is Map && data['list'] is List) {
          items = (data['list'] as List)
              .map((e) => RechargeGoodsConfigItem.fromJson(e))
              .toList();
        }

        final products =
            items
                .where((item) => item.isEnable && item.goodsGoogleId.isNotEmpty)
                .map((item) => RechargeProduct.fromGoodsConfig(item))
                .toList()
              ..sort((a, b) => a.sort.compareTo(b.sort));

        state = state.copyWith(
          products: products,
          isLoading: false,
          hasLoaded: true,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: response.error ?? 'Failed to load recharge products',
          hasLoaded: true,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Error loading products',
        hasLoaded: true,
      );
    }
  }
}

// 一次性商品（K币充值）的购买处理在 recharge_provider.dart 里，
// 这里不再保留第二份实现 —— 之前两个文件各有一份 RechargePurchaseHandler，
// 两个页面分别 import 了不同的那份，很容易改错一边。

/// Coin balance provider
final coinBalanceProvider =
    StateNotifierProvider<CoinBalanceNotifier, CoinBalanceState>((ref) {
      return CoinBalanceNotifier(ref.read(storageServiceProvider));
    });

class CoinBalanceNotifier extends StateNotifier<CoinBalanceState> {
  CoinBalanceNotifier(this._storage) : super(const CoinBalanceState()) {
    _loadBalance();
  }

  final StorageService _storage;
  static const String _balanceKey = 'coin_balance';

  Future<void> _loadBalance() async {
    final balance = _storage.getInt(_balanceKey);
    state = state.copyWith(balance: balance);
  }

  Future<void> setBalance(int balance) async {
    await _storage.setInt(_balanceKey, balance);
    state = state.copyWith(balance: balance);
  }

  Future<void> addCoins(int amount) async {
    final newBalance = state.balance + amount;
    await setBalance(newBalance);
  }
}

class MemberStateNotifier extends StateNotifier<MemberState> {
  MemberStateNotifier(this._ref) : super(const MemberState());

  final Ref _ref;
  PayService get _payService => payServiceProvider;
  PaymentService get _paymentService => PaymentService.instance;
  ReceiptVerificationService get _receiptService =>
      ReceiptVerificationService.instance;
  StorageService get _storage => _ref.read(storageServiceProvider);

  /// Initialize the provider
  Future<void> initialize() async {
    _receiptService.initialize(baseUrl: 'https://api.your-domain.com');

    // Set user ID for purchase association
    //
    // 这个值会作为 applicationUserName 传给 Google Play，
    // Play 会把它当 obfuscatedExternalAccountId 上报，
    // 后端凭它把这笔支付对应到用户并开通会员。
    // 之前读的是 'user_id' 这个**从来没被写过**的键，恒为 null。
    final userId = await _storage.getUserIdAsync();
    _paymentService.setUserId(userId);

    await _paymentService.initialize(
      onPurchaseComplete: _handlePurchaseComplete,
      onPurchaseError: _handlePurchaseError,
    );

    // Load cached purchase token (only thing we persist locally)
    final token = _storage.getString('purchase_token');
    if (token != null && token.isNotEmpty) {
      state = state.copyWith(purchaseToken: token);
    }

    // Check and retry pending payments
    await checkAndRetryPendingPayments();
  }

  Future<void> refreshStatus() async {
    await checkAndRetryPendingPayments();
  }

  /// 清理待处理订单状态（用户取消购买时调用）
  void clearPendingOrder() {
    state = state.copyWith(clearPendingOrder: true, clearError: true);
  }

  /// 登记一笔待支付的订单。
  ///
  /// 会员订阅的 Google Play 结果是走全局的 purchaseStream 回调处理的，
  /// 那条回调需要 orderId 才知道要把这笔支付对到哪个订单上。
  /// 会员页自己的购买流程会在 purchase() 里登记；
  /// 解锁面板那条入口不在这个 provider 里，必须手动登记，
  /// 否则后端回调会因为拿不到 orderId 而失败。
  void setPendingOrder({
    required String orderId,
    required String productId,
    String? subscriptionType,
    int? goodsId,
  }) {
    state = state.copyWith(
      pendingOrderId: orderId,
      pendingProductId: productId,
      pendingSubscriptionType: subscriptionType,
      pendingGoodsId: goodsId,
      clearError: true,
    );
  }

  Future<void> _handlePurchaseComplete(PurchaseDetails purchase) async {
    // 支付成功后的主流程（建单 + 直发 /notice/google）由 [purchase] 里
    // `_paymentService.purchase` 的返回值驱动，这里只做两件事：
    //
    //   1. 把 Play 返回的购买凭据（purchaseToken 等）暂存到
    //      [_lastCompletedPurchase]，供 [purchase] 的 Step 4 组装回调参数。
    //      purchaseStream 的事件总是先于 purchase() 返回到达，
    //      所以 Step 4 执行时这里一定已经存好了。
    //   2. 兜底刷新会员状态（App 重启后恢复购买等没有进行中 purchase()
    //      调用的场景，靠这里刷新 UI）。
    debugPrint(
      '[Membership] purchase completed: ${purchase.productID} '
      '(${purchase.status.name})',
    );

    if (purchase.status == PurchaseStatus.purchased ||
        purchase.status == PurchaseStatus.restored) {
      _lastCompletedPurchase = {
        'productId': purchase.productID,
        'purchaseId': purchase.purchaseID,
        'transactionDate': purchase.transactionDate,
        // Android 上 serverVerificationData 就是 purchaseToken，
        // 后端 /notice/google 靠它去 Google 验证购买。
        'purchaseToken': purchase.verificationData.serverVerificationData,
        'verificationData': {
          'localVerificationData':
              purchase.verificationData.localVerificationData,
          'serverVerificationData':
              purchase.verificationData.serverVerificationData,
          'source': purchase.verificationData.source,
        },
      };
    }

    try {
      await _ref.read(authProvider.notifier).refreshUserInfo();
      _ref.invalidate(isVipProvider);
    } catch (e) {
      debugPrint('[Membership] refresh after purchase failed: $e');
    }
    state = state.copyWith(isLoading: false, clearPendingOrder: true);
  }

  /// 保存待处理的支付回调到本地
  Future<void> _savePendingPayment(Map<String, dynamic> paymentData) async {
    await _storage.savePendingPayment(paymentData);
  }

  /// 最近一次 Play 购买成功的凭据（productId / purchaseToken 等）。
  ///
  /// 由 [_handlePurchaseComplete] 在 purchaseStream 回调时写入，
  /// 由 [purchase] 的 Step 4 消费（组装 /notice/google 的请求参数）。
  Map<String, dynamic>? _lastCompletedPurchase;

  /// 检查并重试所有待处理的支付回调。
  ///
  /// 返回**成功补发的条数**。调用方（App 启动钩子）据此决定是否需要
  /// 刷新 K币余额：K币余额接口复用的也是 `/api/user/userPersonalCenter`，
  /// 队列为空时无条件刷新会在每次启动多打一次用户中心接口。
  /// 正在进行中的补单任务。
  ///
  /// 三个入口会触发补单：App 启动钩子（登录态恢复后）、
  /// 会员页 initState、refreshStatus。它们可能几乎同时触发，
  /// 而补单是"读队列 → 逐条补发 → 逐条出队"的非原子流程：
  /// 并发执行会让同一条待补订单被发送两次（重复建单 / 重复开通）。
  Future<int>? _pendingRetryInFlight;

  Future<int> checkAndRetryPendingPayments() {
    final inFlight = _pendingRetryInFlight;
    if (inFlight != null) return inFlight;

    final future = _doCheckAndRetryPendingPayments();
    _pendingRetryInFlight = future;
    return future.whenComplete(() {
      _pendingRetryInFlight = null;
    });
  }

  Future<int> _doCheckAndRetryPendingPayments() async {
    // 检查是否已登录
    final authState = _ref.read(authProvider);
    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      state = state.copyWith(isLoading: false);
      return 0;
    }

    state = state.copyWith(isLoading: true);

    try {
      final pendingPayments = await _storage.getPendingPayments();
      if (pendingPayments.isEmpty) {
        state = state.copyWith(isLoading: false);
        return 0;
      }

      final successfulOrderIds = <String>[];

      for (final payment in pendingPayments) {
        final orderId = payment['orderId'] as String?;
        if (orderId == null) continue;

        bool success = false;

        // 重试3次，指数退避
        for (int attempt = 1; attempt <= 3; attempt++) {
          try {
            if (payment['purchaseToken'] != null) {
              // 旧版本客户端遗留下的「客户端直发 /notice/google」待重试数据，
              // 继续按老接口补发，成功后本地清掉。
              success = await _payService.confirmGooglePurchase(params: payment);
            } else {
              // 新流程：支付成功但 userRechange 没发出去 → 补建订单。
              final goodsId = (payment['goodsId'] as num?)?.toInt();
              if (goodsId == null) break;
              final order = await _payService.createOrder(
                payConfigId: goodsId,
              );
              success = order != null;
            }
            if (success) {
              successfulOrderIds.add(orderId);
              break;
            }
          } catch (e) {
            if (attempt < 3) {
              final delay = Duration(seconds: (2 << (attempt - 1)));
              await Future.delayed(delay);
            }
          }
        }
      }

      // 移除成功的支付记录
      for (final orderId in successfulOrderIds) {
        await _storage.removePendingPayment(orderId);
      }

      // 如果有支付成功了，刷新VIP状态
      if (successfulOrderIds.isNotEmpty) {
        await _refreshVipStatus();
        // [_refreshVipStatus] 只是重读本地的 purchase_token，不会从后端拿 VIP。
        // 补单成功后必须再拉一次用户信息，否则会员到期时间/会员态还是旧值，
        // 用户会看到"订单补发成功但会员没开通"。
        try {
          await _ref.read(authProvider.notifier).refreshUserInfo();
        } catch (e) {
          debugPrint('[Membership] refresh user info after retry failed: $e');
        }
      } else {
        state = state.copyWith(isLoading: false);
      }
      return successfulOrderIds.length;
    } catch (e) {
      state = state.copyWith(isLoading: false);
      return 0;
    }
  }

  /// 刷新VIP状态 - just reload purchase token
  Future<void> _refreshVipStatus() async {
    state = state.copyWith(isLoading: true);
    try {
      final purchaseToken = _storage.getString('purchase_token');
      state = state.copyWith(purchaseToken: purchaseToken, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  void _handlePurchaseError(String error) {
    // Web + platform flavor: Google Play errors are expected and already
    // surfaced (if at all) via the membership_web_purchase_unsupported
    // copy. Don't double-broadcast through the member error channel.
    if (kIsWeb) {
      debugPrint('[MembershipProvider] suppressed on web: $error');
      state = state.copyWith(isLoading: false, clearPendingOrder: true);
      return;
    }

    // Don't show error dialog for user cancellation
    if (error == 'Purchase was canceled') {
      debugPrint('[MembershipProvider] Purchase canceled by user, ignoring');
      state = state.copyWith(
        isLoading: false,
        clearPendingOrder: true,
        errorMessage: null,
      );
      return;
    }

    state = state.copyWith(isLoading: false, errorMessage: error);
  }

  String? getPurchaseToken() {
    return _storage.getString('purchase_token');
  }

  Future<void> _clearVipStatus() async {
    state = const MemberState();

    // Only clear the purchase token
    await _storage.remove('purchase_token');
  }

  /// Clear all VIP/membership data (called on logout)
  Future<void> clearAll() async {
    await _clearVipStatus();
    state = state.copyWith(clearPendingOrder: true);
  }

  Future<bool> restorePurchases() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final success = await _paymentService.restorePurchases();
      if (!success) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to restore purchases',
        );
        return false;
      }

      await Future.delayed(const Duration(seconds: 2));
      state = state.copyWith(isLoading: false);
      return success;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to restore purchases',
      );
      return false;
    }
  }

  bool canAccess(Feature feature) {
    switch (feature) {
      case Feature.premiumContent:
      case Feature.adFree:
      case Feature.hdQuality:
      case Feature.offlineDownload:
      case Feature.earlyAccess:
        // Check if user has active subscription via Google Play
        return _hasActiveSubscription();
      case Feature.trialContent:
        return true;
    }
  }

  bool _hasActiveSubscription() {
    // Check if we have a purchase token - that means user has purchased before
    // The actual validity is verified by Google Play query
    return state.purchaseToken != null;
  }

  /// Check if user is VIP by querying Google Play
  Future<bool> checkIsVip() async {
    if (state.purchaseToken == null) return false;

    try {
      final purchases = await _paymentService.queryExistingPurchases();
      for (final purchase in purchases) {
        if (purchase.status == PurchaseStatus.purchased ||
            purchase.status == PurchaseStatus.restored) {
          return true;
        }
      }
    } catch (e) {
      // Silently handle query errors
    }
    return false;
  }

  Future<List<ProductDetails>> getProducts(
    List<SubscriptionProduct> products,
  ) async {
    final productIds = products
        .map((p) => p.getProductId(_paymentService.currentPlatform).trim())
        .where((id) => id.isNotEmpty)
        .toList();

    return _paymentService.getProducts(
      productIds: productIds,
      requireSubscriptionOnAndroid: true,
    );
  }

  Future<bool> purchase({required SubscriptionProduct selectedProduct}) async {
    // 用 clearError 而不是 errorMessage: null —— copyWith 里 null 表示「不修改」，
    // 不清空的话上一次失败的文案会一直留在 state 里，
    // 下次同样的错误再发生时 listener 会认为「文案没变」而不弹提示。
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final platformProductId = selectedProduct
          .getProductId(_paymentService.currentPlatform)
          .trim();

      // Step 1: 用户点击购买时，才和 Google Play 匹配商品。
      // 页面展示的套餐来自后端；能不能买、以商店里有没有这个商品为准。
      debugPrint(
        '[Purchase] Step 1: Querying Google Play products for "$platformProductId"',
      );
      final products = await getProducts([selectedProduct]);
      debugPrint('[Purchase] Step 1: Found ${products.length} products');
      if (products.isNotEmpty) {
        debugPrint(
          '[Purchase] Products: ${products.map((p) => '${p.id} (${p.title})').join(', ')}',
        );
      } else {
        debugPrint('[Purchase] WARNING: No products found from Google Play!');
        // 【不要在这里断言是商品 ID 的问题】
        //
        // Play 返回空列表有两种完全不同的原因：
        //   1) code=0 且 unfetched 含该 ID → Play 受理了请求但说「没这个 ID」
        //      （这时才是商品 ID / 类型 / 状态问题）
        //   2) code=2 (SERVICE_UNAVAILABLE) → Play 根本没受理请求
        //      （账号授权 / license tester / Play 商店问题，与 ID 无关）
        //
        // 真正的响应码由 PaymentService 的诊断探针打印，见
        // [PaymentService] ── Google Play 原始响应 ── 这一段。
        debugPrint('[Purchase] Play 未返回该商品，具体原因见下方「Google Play 原始响应」');
        _warnAboutProductIdMismatch(selectedProduct, platformProductId);
      }

      if (products.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          // 用 Play 返回的**真实原因**决定提示，而不是笼统地说
          // 「商品未配置」。Play 根本没受理请求时（code=2 SERVICE_UNAVAILABLE），
          // 让用户去查 Play Console 商品配置是完全指错方向的。
          errorMessage:
              _paymentService.lastPlayFailureCode ?? 'play-item-not-found',
          clearPendingOrder: true,
        );
        return false;
      }

      ProductDetails? productDetails;
      try {
        productDetails = products.firstWhere((p) => p.id == platformProductId);
      } catch (_) {
        try {
          productDetails = products.firstWhere(
            (p) => p.id.contains(selectedProduct.id),
          );
        } catch (_) {
          state = state.copyWith(
            isLoading: false,
            // 用 Play 的真实原因：`play-no-eligible-offer` 表示商品在商店里
            // 存在但当前账号/国家买不了，`play-item-not-found` 才是真的没有。
            errorMessage: _paymentService.lastPlayFailureCode ??
                'Product not available in Google Play: $platformProductId',
            clearPendingOrder: true,
          );
          return false;
        }
      }

      final goodsId = selectedProduct.goodsId;
      if (goodsId == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to create order',
          clearPendingOrder: true,
        );
        return false;
      }

      // Step 2: 匹配成功，直接拉起 Google Play 支付。
      // 【不要】在拉起支付之前调 userRechange 建订单：
      // 商品查不到时留一个永远不会被支付的「孤儿订单」，而且用户要等
      // 订单接口往返之后才知道商品买不了。订单等支付确认后再建。
      debugPrint('[Purchase] Step 2: Launching Google Play payment flow');
      state = state.copyWith(
        pendingProductId: productDetails.id,
        pendingSubscriptionType: selectedProduct.id,
        pendingGoodsId: goodsId,
      );

      final paid = await _paymentService.purchase(
        product: productDetails,
        applicationUserName: await _resolveUserId(),
      );
      debugPrint('[Purchase] Step 2: Payment flow returned paid=$paid');

      if (!paid) {
        // 之前这里只清了 isLoading，没有设置 errorMessage，
        // 结果是用户点完购买干等两分钟，屏幕上什么提示都没有。
        final detail = _paymentService.lastError;

        // 用户主动取消不是错误：不弹任何提示，状态复位，
        // 再点购买会重新走 Step 1 / Step 2（重新拉起 Play 支付台）。
        final canceled = detail != null && detail.contains('cancel');

        state = state.copyWith(
          isLoading: false,
          clearError: canceled,
          errorMessage: canceled
              ? null
              : ((detail != null && detail.isNotEmpty)
                    ? detail
                    : 'Purchase failed. Please try again.'),
          clearPendingOrder: true,
        );
        return false;
      }

      // Step 3: 支付已在 Play 侧确认 → 通知后端建单（POST /api/pay/userRechange）。
      debugPrint('[Purchase] Step 3: Payment confirmed, notifying backend');
      String? orderNo;
      try {
        final order = await _payService.createOrder(payConfigId: goodsId);
        orderNo = order?.orderId;
      } catch (e) {
        debugPrint('[Purchase] Step 3: userRechange threw: $e');
      }

      if (orderNo == null || orderNo.isEmpty) {
        // 钱已经付了，不能再当「购买失败」处理。
        // 把 goodsId 存进本地待重试队列，下次启动/进入会员页时补发 userRechange
        //（见 [checkAndRetryPendingPayments]）。
        await _savePendingPayment({
          'orderId': 'goods-$goodsId',
          'type': 'createOrder',
          'goodsId': goodsId,
        });
        debugPrint('[Purchase] Step 3: userRechange failed — queued for retry');
        state = state.copyWith(
          isLoading: false,
          errorMessage: null,
          clearPendingOrder: true,
        );
        return true;
      }

      // Step 4: 直发 /notice/google（后端 OpenAPI: pay-result-controller /
      // googleCallBack）。后端只有拿到 orderNo + purchaseToken 才能去 Google
      // 验证这笔购买、acknowledge 并开通会员——不发这个接口，后端永远不知道
      // 这笔 Play 支付对应哪个订单。
      // 参数结构与 K币链路（recharge_provider._handlePurchaseSuccess）保持一致，
      // payConfigType=0 表示会员订阅。
      final credentials = _lastCompletedPurchase;
      final purchaseToken = credentials?['purchaseToken'] as String?;
      if (credentials == null || purchaseToken == null || purchaseToken.isEmpty) {
        debugPrint(
          '[Purchase] Step 4: WARNING no purchaseToken available, skip callback',
        );
      } else {
        final callbackPayload = <String, dynamic>{
          // 后端订单字段名是 orderNo，两个都带上，兼容后端两种读法。
          'orderNo': orderNo,
          'orderId': orderNo,
          'productId': credentials['productId'],
          'purchaseId': credentials['purchaseId'],
          'transactionDate': credentials['transactionDate'],
          'status': 'purchased',
          'payConfigType': 0, // 0 = 会员订阅
          'goodsId': goodsId,
          'purchaseToken': purchaseToken,
          'verificationData': credentials['verificationData'],
        };

        // 【先存后发】发送前先把回调参数落盘（同 orderId 去重）。
        // 这样 App 在发送过程中被杀、断网、崩溃，下次启动/进会员页
        // checkAndRetryPendingPayments 都会看到这条记录并补发；
        // 发送成功后再出队。反过来（失败才存）的话，进程一死
        // 这笔已付款的订单就永远丢了。
        await _savePendingPayment(callbackPayload);

        var confirmed = false;
        for (int attempt = 1; attempt <= 3 && !confirmed; attempt++) {
          if (attempt > 1) {
            await Future<void>.delayed(Duration(seconds: 2 << (attempt - 2)));
          }
          try {
            confirmed = await _payService.confirmGooglePurchase(
              params: callbackPayload,
            );
          } catch (e) {
            debugPrint(
              '[Purchase] Step 4: /notice/google attempt $attempt failed: $e',
            );
          }
        }

        if (!confirmed) {
          debugPrint(
            '[Purchase] Step 4: /notice/google failed — kept in pending queue',
          );
        } else {
          // 后端已确认，出队。
          await _storage.removePendingPayment(orderNo);
          debugPrint('[Purchase] Step 4: /notice/google confirmed');
        }
      }

      await _ref.read(authProvider.notifier).refreshUserInfo();
      _ref.invalidate(isVipProvider);
      state = state.copyWith(isLoading: false, clearPendingOrder: true);
      return true;
    } catch (e, stack) {
      debugPrint('[Purchase] Error: $e\n$stack');
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
        clearPendingOrder: true,
      );
      return false;
    }
  }

  /// 后台下发的商品 ID 和代码里的兜底 ID 可能对不上
  /// （例如后台给的是 `com.qahwa.vip2`，兜底列表写的是 `com.qahwa.vip.2`）。
  /// 这种情况下 Play 里其实是有的，只是我们查的是另一个 ID。
  /// 查不到商品时把两边都打出来，省掉一轮来回排查。
  ///
  /// 注意：这里**只是提示 ID 存在两种写法**，不代表当前失败就是 ID 造成的。
  /// 当前失败的真正原因看 PaymentService 打印的 Play 原始响应码。
  void _warnAboutProductIdMismatch(
    SubscriptionProduct selectedProduct,
    String platformProductId,
  ) {
    final knownIds = SubscriptionProducts.fallbackProducts
        .map((p) => p.googlePlayId)
        .where((id) => id.isNotEmpty)
        .toList();
    if (knownIds.isEmpty) return;
    if (knownIds.contains(platformProductId)) return;

    debugPrint('[Purchase] ────────────────────────────────────────────');
    debugPrint('[Purchase] 商品 ID 与代码兜底列表不一致，请确认 Play 后台用的是哪个：');
    debugPrint('[Purchase]   后台下发的 ID : "$platformProductId"');
    debugPrint('[Purchase]   代码兜底 ID   : ${knownIds.join(", ")}');
    debugPrint(
      '[Purchase]   当前商品        : ${selectedProduct.id} (goodsId=${selectedProduct.goodsId})',
    );
    debugPrint('[Purchase]   两者逐字符必须完全一致（含点号 / 下划线 / 大小写）');
    debugPrint('[Purchase] ────────────────────────────────────────────');
  }

  Future<String?> _resolveUserId() async {
    // 后端真实 userId（不是 'user_id' 那个不存在的键）
    return _storage.getUserIdAsync();
  }

  @override
  void dispose() {
    _paymentService.dispose();
    super.dispose();
  }
}

class MembershipProductsNotifier
    extends StateNotifier<MembershipProductsState> {
  MembershipProductsNotifier(DioClient dioClient, StorageService storage)
    : _apiService = ApiService(dioClient: dioClient, storage: storage),
      super(const MembershipProductsState());

  final ApiService _apiService;

  Future<void> loadVipProducts() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, hasLoaded: true, clearError: true);

    try {
      final response = await _apiService.getRechargeGoodsConfig(
        rechargeGoodsType: 0,
      );
      if (!response.isSuccess) {
        state = state.copyWith(
          isLoading: false,
          products: const [],
          errorMessage: response.error,
        );
        return;
      }

      final items = _parseRechargeGoods(response.data);
      final products = SubscriptionProducts.fromRechargeGoods(items);

      // 立即更新UI显示商品（不等待Google Play查询）
      state = state.copyWith(
        isLoading: false,
        products: products,
        clearError: true,
      );

      // 只展示后台返回的套餐。
      // 【不要】在这里查 Google Play，也不要隐藏「Play 上取不到」的套餐：
      // 与商店的匹配推迟到用户点击购买时再做（见 [MemberStateNotifier.purchase]），
      // 页面第一屏永远以后端配置为准。
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        products: const [],
        errorMessage: 'Failed to load products',
      );
    }
  }

  List<RechargeGoodsConfigItem> _parseRechargeGoods(dynamic data) {
    final rawList = switch (data) {
      {'list': final list} => list,
      {'rows': final rows} => rows,
      {'data': final nested} => nested,
      List<dynamic> list => list,
      _ => const <dynamic>[],
    };

    if (rawList is! List) return const [];

    return rawList
        .whereType<Map>()
        .map(
          (item) =>
              RechargeGoodsConfigItem.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

}

/// Features that require membership
enum Feature {
  premiumContent,
  adFree,
  hdQuality,
  offlineDownload,
  earlyAccess,
  trialContent,
}

extension FeatureExt on Feature {
  String get displayName {
    switch (this) {
      case Feature.premiumContent:
        return 'Premium Content';
      case Feature.adFree:
        return 'Ad-free';
      case Feature.hdQuality:
        return 'HD Quality';
      case Feature.offlineDownload:
        return 'Offline Download';
      case Feature.earlyAccess:
        return 'Early Access';
      case Feature.trialContent:
        return 'Trial Content';
    }
  }
}

final featureAccessProvider = Provider.family<bool, Feature>((ref, feature) {
  final isVip = ref.watch(isVipProvider);
  return isVip || feature == Feature.trialContent;
});

/// Provider that checks actual VIP status from the authenticated user's info.
/// VIP status is determined by the backend user center response (isVip field + vipEndTime).
/// This provider watches authProvider, so it auto-updates when user info refreshes
/// (e.g., after a purchase triggers a backend webhook → authProvider.refreshUserInfo).
final isVipProvider = Provider<bool>((ref) {
  final auth = ref.watch(authProvider);
  final user = auth.user;
  if (user == null || user.isGuest) return false;
  return user.isVip &&
      (user.vipExpireDate == null ||
          user.vipExpireDate!.isAfter(DateTime.now()));
});

/// Provider that checks if the user has an active VIP subscription (including expired = false).
/// Convenience wrapper around isVipProvider.
final isActiveVipProvider = Provider<bool>((ref) {
  return ref.watch(isVipProvider);
});

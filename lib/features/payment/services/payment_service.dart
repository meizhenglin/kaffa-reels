import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show ProductType;
import 'package:shared_preferences/shared_preferences.dart';

import 'play_billing_probe.dart';
import 'play_billing_native_probe.dart';

/// 商品在 App 里的用途。
///
/// Google Play 的 ProductType 只区分 `inapp` / `subs`，
/// 区分不出「一次性消耗」和「一次性买断」，所以商品的用途必须由
/// 发起购买的一方登记（见 [PaymentService.purchase] 与
/// [PaymentService.purchaseConsumable]）。
///
/// - [PlayProductKind.subscription]：会员订阅，需要 acknowledge（completePurchase）
/// - [PlayProductKind.consumable]：K币这类一次性消耗，插件已在投递前自动
///   consume，**不能再** acknowledge
enum PlayProductKind { subscription, consumable }

/// Local storage helper for caching purchase state
class PaymentService {
  PaymentService._();
  static final PaymentService instance = PaymentService._();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  bool _isInitialized = false;

  StreamSubscription<List<PurchaseDetails>>? _subscription;
  Function(PurchaseDetails)? _onPurchaseComplete;
  Function(String)? _onPurchaseError;

  /// 商品 ID → 用途。购买成功后保留（订阅续订时还会用到）。
  final Map<String, PlayProductKind> _productKinds = {};

  /// 商品 ID → 该商品的购买完成回调。
  /// 一次性商品用它把「购买成功」事件送回 K币 那条链路，
  /// 避免和会员链路的全局回调互相干扰。
  final Map<String, Function(PurchaseDetails)> _productHandlers = {};

  // Cached products
  List<ProductDetails> _availableProducts = [];

  // Cached purchases for quick lookup
  List<PurchaseDetails> _cachedPurchases = [];
  DateTime? _lastPurchaseQueryTime;

  static const Duration _purchaseQueryCacheTtl = Duration(seconds: 30);

  Completer<bool>? _pendingPurchaseCompleter;
  String? _pendingPurchaseProductId;
  DateTime? _pendingPurchaseStartedAt;
  String? _lastError;

  /// 一次购买流程超过这个时长仍未收到 Play 的任何结果，
  /// 视为「上一次流程已僵死」（取消事件丢失 / 弹窗被系统杀掉），
  /// 再点购买时直接复位重来，而不是一直把用户挡在「购买中」。
  static const Duration _stalePendingPurchase = Duration(seconds: 15);

  /// 最近一次商品查询失败的 **Play 侧原因**（稳定错误码）。
  ///
  /// 由诊断探针在「商品查不到」时填入，见 [PlayBillingProbe.failureCode]。
  ///
  /// - `play-service-unavailable` / `play-store-unavailable` 等：
  ///   Play **根本没受理**请求，与商品 ID 无关，提示用户去查 Play 商店
  ///   账号 / 授权 / 商店版本。
  /// - `play-item-not-found`：Play 受理了但说没这个 ID，才查商品配置。
  /// - `play-no-eligible-offer`：商品**确实存在**（Play Console 里一直都在），
  ///   但当前账号 / 国家没有可购买的 offer（基础方案没配价 / 没激活 / 区域不符）。
  ///   这种情况下**不该**去 Play Console 建商品，见 [PlayUnfetchedStatus]。
  ///
  /// 为 null 表示没有拿到可归因的 Play 侧错误。
  String? get lastPlayFailureCode => _lastPlayFailureCode;
  String? _lastPlayFailureCode;

  /// 最近一次查询中，Play **明确表示不存在**的商品 ID。
  ///
  /// 只有在探针确认 Play 受理了请求（响应码 OK）时才会填充 —— 否则
  /// 「没取到的 ID 差集」等于全部请求过的 ID，不能当「商品不存在」用。
  ///
  /// 典型场景：后台下发了 vip1/vip2/vip3，Play Console 只建了 vip1，
  /// 这里就会是 {com.qahwa.vip2, com.qahwa.vip3}。
  Set<String> get lastMissingProductIds => _lastMissingProductIds;
  Set<String> _lastMissingProductIds = <String>{};

  /// Last error message from purchase operations
  String? get lastError => _lastError;

  /// Whether a purchase flow is currently waiting for a Play result.
  bool get hasPendingPurchase => _pendingPurchaseCompleter != null;

  /// Initialize the payment service
  Future<bool> initialize({
    Function(PurchaseDetails)? onPurchaseComplete,
    Function(String)? onPurchaseError,
  }) async {
    // Update callbacks even if already initialized
    if (onPurchaseComplete != null) {
      _onPurchaseComplete = onPurchaseComplete;
    }
    if (onPurchaseError != null) {
      _onPurchaseError = onPurchaseError;
    }

    if (_isInitialized) return true;

    // Web and non-Google targets: Google Play Billing is not callable.
    // Bail out cleanly without notifying the error channel — web users
    // still get a working HaiPay flow in the platform flavor, so this
    // is not an error condition from the user's perspective.
    if (kIsWeb) {
      _lastError = 'Google Play Billing is not supported on web.';
      _isInitialized = false;
      return false;
    }

    try {
      final isAvailable = await _inAppPurchase.isAvailable();
      if (!isAvailable) {
        _lastError = 'Google Play billing is not available on this device.';
        _onPurchaseError?.call(
          'Google Play billing is not available on this device.',
        );
        return false;
      }

      // Listen to purchase updates
      _subscription ??= _inAppPurchase.purchaseStream.listen(
        _handlePurchaseUpdate,
        onError: (error) {
          _onPurchaseError?.call('Purchase stream error: $error');
        },
      );

      _isInitialized = true;
      return true;
    } catch (e) {
      _lastError = 'Failed to initialize billing: $e';
      _onPurchaseError?.call('Failed to initialize billing: $e');
      return false;
    }
  }

  /// Get available subscription products
  Future<List<ProductDetails>> getProducts({
    required List<String> productIds,
    bool requireSubscriptionOnAndroid = false,
  }) async {
    debugPrint('[PaymentService] getProducts() called with IDs: $productIds');
    debugPrint(
      '[PaymentService] requireSubscriptionOnAndroid: $requireSubscriptionOnAndroid',
    );

    // 每次查询都重置，避免上一次的失败原因被这一次的调用误用。
    _lastPlayFailureCode = null;
    _lastMissingProductIds = <String>{};

    // Auto-initialize if needed
    if (!_isInitialized) {
      debugPrint('[PaymentService] Not initialized, initializing now...');
      final initialized = await initialize(
        onPurchaseComplete: _onPurchaseComplete,
        onPurchaseError: _onPurchaseError,
      );
      if (!initialized) {
        _lastError = 'Payment service not available';
        debugPrint('[PaymentService] Initialization failed: $_lastError');
        return [];
      }
      debugPrint('[PaymentService] Initialization succeeded');
    }

    // Sanitize product IDs: trim whitespace, remove invisible chars
    final sanitizedIds = productIds.map((id) {
      final cleaned = id.replaceAll(
        RegExp(r'[\u0000-\u001F\u007F\u200E\u200F\u202A-\u202E\s]'),
        '',
      );
      return cleaned.trim();
    }).toList();

    if (sanitizedIds.isEmpty || sanitizedIds.every((id) => id.isEmpty)) {
      _lastError = 'No valid product IDs provided';
      return [];
    }

    try {
      debugPrint(
        '[PaymentService] Calling _inAppPurchase.queryProductDetails with: $sanitizedIds',
      );

      // queryProductDetails already queries both INAPP and SUBS on Android
      final response = await _inAppPurchase.queryProductDetails(
        sanitizedIds.toSet(),
      );
      debugPrint(
        '[PaymentService] queryProductDetails response.error: ${response.error}',
      );
      debugPrint(
        '[PaymentService] queryProductDetails response.productDetails count: ${response.productDetails.length}',
      );
      if (response.productDetails.isNotEmpty) {
        debugPrint(
          '[PaymentService] Found products: ${response.productDetails.map((p) => '${p.id} (${p.title})').join(', ')}',
        );
      }

      // 【为什么必须打印 notFoundIDs】
      //
      // Google Play 的 `queryProductDetails` 在「请求成功但商品拿不到」时
      // 会返回 **error == null + productDetails 为空**。这两种完全不同的
      // 失败被混在一起，排查时只能靠猜：
      //
      //   - 商品 ID 在 Play 后台不存在 / 没配 / 没激活
      //   - 商品配了但不是订阅（是 one-time product）
      //   - App 没上传到 Play，或账号不是 license tester
      //
      // `notFoundIDs` 至少能告诉你**是哪些 ID 没找到**，配合后台一查就清楚。
      if (response.notFoundIDs.isNotEmpty) {
        debugPrint(
          '[PaymentService] notFoundIDs (Play could not fetch): ${response.notFoundIDs.join(", ")}',
        );
      }

      if (response.error != null) {
        _lastError = response.error!.message;
        debugPrint(
          '[PaymentService] queryProductDetails error: code=${response.error!.code}, message=${response.error!.message}',
        );
        _onPurchaseError?.call(response.error!.message);
        return [];
      }

      if (response.productDetails.isEmpty) {
        // 【关键】到这里只能确定「没拿到商品」，不能确定原因。
        //
        // 插件的公开 API 把 BillingResult 丢掉了
        // （flutter/flutter#194177），所以下面用探针去问 Play 拿原始响应码：
        //
        //   - code=2 (SERVICE_UNAVAILABLE) → Play 根本没受理请求，
        //     是账号授权 / license tester / Play 商店的问题，
        //     **跟商品 ID 写没写错毫无关系**。
        //   - code=0 (OK) + unfetched 里有该 ID → Play 受理了但说
        //     「这个 ID 我没有」，这才是商品 ID / 类型 / 状态的问题。
        await _logPlayDiagnosis(sanitizedIds, response.notFoundIDs);

        _lastError =
            'Products not found in Google Play: ${sanitizedIds.join(", ")}';
        debugPrint('[PaymentService] Products not found: $sanitizedIds');
        return [];
      }

      _availableProducts = response.productDetails;

      // 混合结果：有的商品查到了，有的没查到。
      //
      // 例如后台下发了 vip1/vip2/vip3，Play 只认 vip1 —— 这是**最常见**的
      // 情况（Play Console 只建了部分商品）。这时 productDetails 非空，
      // 上面那个「全空」的诊断分支根本不会走，所以这里也要跑一次探针：
      //
      //   - 探针 code=0 → Play 真的受理了请求，notFoundIDs 就是「真的没有」，
      //     可以据此把不存在的套餐对上层隐藏掉。
      //   - 探针 code=2 → Play 压根没受理，notFoundIDs 会把所有请求过的 ID
      //     都列出来，此时**不能**当「商品不存在」处理（见 play_billing_probe.dart）。
      if (response.notFoundIDs.isNotEmpty) {
        await _logPlayDiagnosis(sanitizedIds, response.notFoundIDs);
      }

      if (requireSubscriptionOnAndroid &&
          defaultTargetPlatform == TargetPlatform.android) {
        final invalidProducts = _availableProducts.where((product) {
          if (product is! GooglePlayProductDetails) {
            return true;
          }

          final productType = product.productDetails.productType;
          return productType != ProductType.subs;
        }).toList();

        if (invalidProducts.isEmpty) {
          return _availableProducts;
        }

        final subscriptionProducts = _availableProducts.where((product) {
          if (product is! GooglePlayProductDetails) {
            return false;
          }

          final productType = product.productDetails.productType;
          return productType == ProductType.subs;
        }).toList();

        if (subscriptionProducts.isNotEmpty) {
          _availableProducts = subscriptionProducts;
          return _availableProducts;
        }

        final invalidSummary = invalidProducts
            .map((product) {
              final type = product is GooglePlayProductDetails
                  ? product.productDetails.productType
                  : 'unknown';
              return '${product.id}($type)';
            })
            .join(', ');
        final message =
            'Google Play products must be subscriptions (subs), but got: $invalidSummary';
        _lastError = message;
        // Play **找到了**这个商品，只是它不是订阅类型。
        // 这跟「商品不存在」是两回事，必须给出独立的失败码，
        // 否则 UI 会误报成「商品未配置」。
        _lastPlayFailureCode = 'play-not-subscription';
        _onPurchaseError?.call(message);
        return [];
      }

      return _availableProducts;
    } catch (e) {
      _lastError = 'Failed to fetch products: $e';
      _onPurchaseError?.call('Failed to fetch products: $e');
      return [];
    }
  }

  /// 把 Play 原始的 `BillingResult` 打出来，说明这次失败**到底**是什么原因。
  ///
  /// 没有这一步的话，「商品 ID 写错」和「Play 服务不可用」在日志里长得一样，
  /// 排查就只能靠猜。参见 [PlayBillingProbe]。
  ///
  /// [notFoundIds] 是插件算出的「请求了但没取到」的 ID 差集。只有当探针确认
  /// Play **确实受理**了这次请求（响应码为 OK）时，这个差集才代表
  /// 「Play 没给这些商品详情」；**它到底是不存在还是买不了，要以原生探针
  /// 的逐商品状态码为准**，所以结论统一在两个探针都跑完之后再打印。
  Future<void> _logPlayDiagnosis(
    List<String> productIds, [
    Iterable<String> notFoundIds = const <String>[],
  ]) async {
    debugPrint('[PaymentService] ── Google Play 原始响应 ──────────────────');
    try {
      final results = await const PlayBillingProbe()
          .query(productIds.toSet())
          .timeout(const Duration(seconds: 8));
      debugPrint('[PaymentService] ${PlayBillingProbe.describe(results)}');
      _lastPlayFailureCode = PlayBillingProbe.failureCode(results);

      // 只有 Play 明确受理（两种类型都返回 OK）才认为「没给详情」可信。
      final playProcessed = results.isNotEmpty && results.every((r) => r.isOk);
      _lastMissingProductIds = playProcessed ? notFoundIds.toSet() : <String>{};
    } catch (e) {
      debugPrint('[PaymentService] Play 诊断探针执行失败: $e');
      _lastMissingProductIds = <String>{};
    }
    await _logNativeProductStatus(productIds);
    debugPrint(
      '[PaymentService] 最终失败原因码: ${_lastPlayFailureCode ?? '（Play 已受理请求，无服务端错误）'}',
    );
    debugPrint(
      '[PaymentService] Play 上确实不存在的商品: '
      '${_lastMissingProductIds.isEmpty ? '（无）' : _lastMissingProductIds.join(", ")}',
    );
    debugPrint('[PaymentService] ────────────────────────────────────────────');
  }

  /// 用**原生探针**再查一次，拿到每个商品各自的失败原因码。
  ///
  /// 插件在 `Translator.fromUnfetchedProduct` 里把
  /// `UnfetchedProduct.getStatusCode()` 丢掉了，所以纯 Dart 的探针
  /// （[PlayBillingProbe]）只知道「取不到」，不知道「**为什么**取不到」。
  /// 这里用原生通道（`BillingProbe.java`）补上，区分两种完全不同的故障：
  ///
  ///   - `PRODUCT_NOT_FOUND`：这个商品在当前 Play 应用下**真的不存在**
  ///     （建在了另一个 Play 应用下 / 类型建错 / ID 拼错）。
  ///   - `NO_ELIGIBLE_OFFER`：商品**确实存在**（Play Console 里一直都在），
  ///     但当前账号 / 国家拿不到可购买的 offer —— 修法是配基础方案的价格 /
  ///     激活 / 开放区域，**不是**去建商品。
  ///
  /// 两种情况的修复方向完全相反，所以必须分开。
  Future<void> _logNativeProductStatus(List<String> productIds) async {
    final PlayNativeProbeResult? native;
    try {
      native = await const PlayNativeBillingProbe()
          .probe(productIds)
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('[PaymentService] 原生状态码探针执行失败: $e');
      return;
    }
    if (native == null) return;

    debugPrint('[PaymentService] ── Play 逐商品状态码 ─────────────────────');
    debugPrint('[PaymentService] ${native.describe()}');
    if (!native.isOk) {
      debugPrint('[PaymentService] 原生探针未能建立结算连接，状态码不可用');
      return;
    }

    final notFound = native.notFoundIds;
    final noOffer = native.noEligibleOfferIds;

    // 原生探针拿到了 Play 的**逐商品**状态码，它比插件的「没取到的 ID 差集」
    // 权威得多：只有它明确说 PRODUCT_NOT_FOUND 的才算真的不存在。
    // （「存在但买不了」的商品不能算进去，否则会被当成「商品没配」而隐藏掉。）
    _lastMissingProductIds = notFound;
    if (notFound.isNotEmpty) {
      debugPrint(
        '[PaymentService] 判定：商品在当前 Play 应用下不存在 → ${notFound.join(", ")}',
      );
    }
    if (noOffer.isNotEmpty) {
      debugPrint(
        '[PaymentService] 判定：商品存在但当前账号/国家买不了 → ${noOffer.join(", ")}',
      );
    }

    // 失败码的优先级：只要出现「存在但买不了」，就以它为准 ——
    // 这是最容易误判成「商品没创建」的情况，必须单独提示。
    if (noOffer.isNotEmpty) {
      _lastPlayFailureCode = 'play-no-eligible-offer';
    } else if (notFound.isNotEmpty) {
      _lastPlayFailureCode = 'play-item-not-found';
    }
  }

  /// Check if user has active subscriptions
  Future<List<PurchaseDetails>> getPurchases() async {
    await restorePurchases();
    return [];
  }

  /// Initiate a subscription purchase flow (non-consumable)
  Future<bool> purchase({
    required ProductDetails product,
    String? applicationUserName,

    /// Timeout duration for purchase flow (default 120 seconds)
    Duration purchaseTimeout = const Duration(seconds: 120),
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize(
        onPurchaseComplete: _onPurchaseComplete,
        onPurchaseError: _onPurchaseError,
      );
      if (!initialized) {
        _lastError = 'Payment service not initialized';
        return false;
      }
    }

    try {
      debugPrint(
        '[PaymentService] purchase() called for ${product.id} '
        'user=${applicationUserName ?? _userId}',
      );

      // 每次新购买开始前清掉旧错误，避免失败时把上一次的文案弹给用户。
      _lastError = null;

      // 并发保护。
      //
      // 之前没有这道闸：用户连点 5 次「购买」会创建 5 个 completer，
      // 但 `_handlePurchaseUpdate` 只认「最后一个」_pendingPurchaseProductId，
      // 先前那几个 completer 永远等不到结果，只能各自跑满 120 秒超时。
      // 日志里出现多条 timeout + 「Step 3 returned false」就是这个原因。
      //
      // 但如果上一次流程已经僵死（取消/错误事件丢失，Play 那边其实早就不在
      // 对话框里了），还继续拦的话，用户点了购买却什么都不会发生，
      // 只能干等 120 秒超时。所以超过 [_stalePendingPurchase] 就直接复位重来。
      if (_pendingPurchaseCompleter != null) {
        final startedAt = _pendingPurchaseStartedAt;
        final age = startedAt == null ? null : DateTime.now().difference(startedAt);
        final isStale = age == null || age >= _stalePendingPurchase;

        if (!isStale) {
          debugPrint(
            '[PaymentService] purchase() rejected: a purchase is already in progress '
            '(pending product: $_pendingPurchaseProductId)',
          );
          _lastError = 'A purchase is already in progress. Please wait.';
          return false;
        }

        debugPrint(
          '[PaymentService] purchase() reset stale pending purchase '
          '(product: $_pendingPurchaseProductId, age: ${age?.inSeconds ?? "-"}s)',
        );
        _pendingPurchaseCompleter!.complete(false);
        _pendingPurchaseCompleter = null;
        _pendingPurchaseProductId = null;
        _pendingPurchaseStartedAt = null;
      }

      final completer = Completer<bool>();
      _pendingPurchaseCompleter = completer;
      _pendingPurchaseProductId = product.id;
      _pendingPurchaseStartedAt = DateTime.now();
      _productKinds[product.id] = PlayProductKind.subscription;

      Timer? timeoutTimer;

      Future<void> finalizePendingPurchase() async {
        timeoutTimer?.cancel();
        if (_pendingPurchaseCompleter != completer) {
          return;
        }
        if (!completer.isCompleted) {
          completer.complete(false);
        }
        _pendingPurchaseCompleter = null;
        _pendingPurchaseProductId = null;
        _pendingPurchaseStartedAt = null;
      }

      timeoutTimer = Timer(purchaseTimeout, () {
        if (!completer.isCompleted) {
          debugPrint(
            '[PaymentService] Purchase timeout after ${purchaseTimeout.inSeconds}s '
            'for ${product.id}',
          );
          _lastError =
              'Google Play did not complete the purchase in time. Please try again.';
          // 关键：超时后必须把 pending 状态清掉，
          // 否则 _pendingPurchaseCompleter 会一直非空，后续购买会被并发保护挡掉。
          finalizePendingPurchase();
        }
      });

      // 购买成功/取消时立刻停掉超时定时器，不必空等 120 秒。
      unawaited(completer.future.whenComplete(() => timeoutTimer?.cancel()));

      final purchaseParam = PurchaseParam(
        productDetails: product,
        // 【优先级】调用方传的值优先于 PaymentService 里缓存的。
        //
        // 缓存的 _userId 是 App 启动时 setUserId() 写进去的，
        // 如果那时用户还没登录就是 null；而调用方每次购买都现取，
        // 拿到的是当下真正的 userId。后端靠这个值（Play 会以
        // obfuscatedExternalAccountId 上报）把这笔支付对应到用户。
        applicationUserName: applicationUserName ?? _userId,
      );

      debugPrint('[PaymentService] Launching purchase for ${product.id}');

      // 使用 buyNonConsumable 来处理订阅商品
      try {
        final purchaseResult = await _inAppPurchase.buyNonConsumable(
          purchaseParam: purchaseParam,
        );
        debugPrint(
          '[PaymentService] buyNonConsumable returned: $purchaseResult',
        );

        // buyNonConsumable 正常返回（不抛异常）只说明 Google Play 尝试打开了
        // 实际的购买结果需要通过 purchaseStream 返回
        // 如果 3 秒内 completer 还没完成，说明 Google Play 可能没有真正打开
        await Future.delayed(const Duration(seconds: 3));
        if (!completer.isCompleted) {
          debugPrint(
            '[PaymentService] WARNING: Google Play may not have opened (no purchase result after 3s)',
          );
          // 不直接返回 false，因为 Google Play 可能只是卡住了
          // 让它继续等待，或者等待 timeout
        }

        return completer.future;
      } catch (e) {
        final message = e.toString();
        debugPrint('[PaymentService] buyNonConsumable error: $message');

        // 分析错误类型，给出更有用的错误信息
        String userMessage;
        if (message.contains('ITEM_ALREADY_OWNED')) {
          debugPrint(
            '[PaymentService] Detected ITEM_ALREADY_OWNED, clearing cache',
          );
          clearCachedPurchases();
          userMessage =
              'You already own this subscription. Please check Google Play for manage subscription.';
        } else if (message.contains('SERVICE_DISCONNECTED') ||
            message.contains('service')) {
          userMessage =
              'Google Play service is not connected. Please update Google Play Store app.';
        } else if (message.contains('NETWORK')) {
          userMessage = 'Network error. Please check your internet connection.';
        } else if (message.contains('DEVELOPER_ERROR') ||
            message.contains('product')) {
          userMessage =
              'Product configuration error. Please try again later or contact support.';
        } else if (message.contains('PERMISSION_DENIED') ||
            message.contains('permission')) {
          userMessage = 'Permission denied. Please check app permissions.';
        } else {
          userMessage = 'Purchase failed: $message';
        }

        _lastError = userMessage;
        _onPurchaseError?.call(userMessage);
        await finalizePendingPurchase();
        return false;
      }
    } catch (e) {
      final message = e.toString();
      debugPrint('[PaymentService] Purchase flow error: $message');
      clearCachedPurchases();
      _lastError = 'Purchase failed: $message';
      _onPurchaseError?.call('Purchase failed: $message');
      return false;
    }
  }

  /// User ID for purchase association
  String? _userId;

  /// Set user ID for purchase association
  void setUserId(String? userId) {
    _userId = userId;
  }

  String? _resolveUserId() => _userId;

  /// Store mapping of subscriptionType to productId
  final Map<String, String> _subscriptionTypeToProductId = {};

  /// Store a mapping from subscription type to product ID
  void registerSubscriptionProduct(String subscriptionType, String productId) {
    _subscriptionTypeToProductId[subscriptionType] = productId;
  }

  /// Get the product ID for a given subscription type
  String? getProductIdForType(String subscriptionType) {
    return _subscriptionTypeToProductId[subscriptionType];
  }

  /// Store purchase in cache
  void cachePastPurchase(PurchaseDetails purchase) {
    _cachedPurchases.removeWhere((p) => p.productID == purchase.productID);
    _cachedPurchases.add(purchase);
  }

  /// Get cached purchase for a specific product type
  PurchaseDetails? getCachedPurchase(String subscriptionType) {
    final expectedProductId = _subscriptionTypeToProductId[subscriptionType];
    if (expectedProductId != null) {
      for (final purchase in _cachedPurchases) {
        if (purchase.productID == expectedProductId &&
            (purchase.status == PurchaseStatus.purchased ||
                purchase.status == PurchaseStatus.restored)) {
          return purchase;
        }
      }
    }
    return null;
  }

  /// Initiate a consumable purchase flow (coins/recharges)
  /// Consumables need to be consumed after purchase to allow repurchase
  ///
  /// 返回 true 表示**用户真的付了款**（等到了 purchaseStream 的结果），
  /// 不是「购买弹窗已打开」。`buyConsumable` 本身在弹窗打开时就返回了，
  /// 直接用它会让 UI 在用户还没确认支付时就提示「购买成功」。
  ///
  /// [onComplete] 购买成功后回调。一次性商品的购买结果**不会**走全局的
  /// `_onPurchaseComplete`（那是会员订阅用的），必须通过这个回调拿，
  /// 否则 K币 的后端回调就永远不会发出去。
  Future<bool> purchaseConsumable({
    required ProductDetails product,
    String? applicationUserName,
    Function(PurchaseDetails)? onComplete,
    Duration purchaseTimeout = const Duration(seconds: 120),
  }) async {
    if (!_isInitialized) {
      final initialized = await initialize(
        onPurchaseComplete: _onPurchaseComplete,
        onPurchaseError: _onPurchaseError,
      );
      if (!initialized) {
        return false;
      }
    }

    // 同一时间只允许一笔购买在飞。
    if (_pendingPurchaseCompleter != null) {
      debugPrint(
        '[PaymentService] purchaseConsumable() rejected: a purchase is already in progress',
      );
      _lastError = 'A purchase is already in progress. Please wait.';
      return false;
    }

    // 登记商品用途 + 完成回调，purchase stream 那边靠这个分流。
    _productKinds[product.id] = PlayProductKind.consumable;
    if (onComplete != null) {
      _productHandlers[product.id] = onComplete;
    }

    final completer = Completer<bool>();
    _pendingPurchaseCompleter = completer;
    _pendingPurchaseProductId = product.id;

    Timer? timeoutTimer;

    Future<void> finalizePendingPurchase() async {
      timeoutTimer?.cancel();
      if (_pendingPurchaseCompleter != completer) return;
      if (!completer.isCompleted) {
        completer.complete(false);
      }
      _pendingPurchaseCompleter = null;
      _pendingPurchaseProductId = null;
    }

    timeoutTimer = Timer(purchaseTimeout, () {
      if (!completer.isCompleted) {
        debugPrint(
          '[PaymentService] Consumable purchase timeout after '
          '${purchaseTimeout.inSeconds}s for ${product.id}',
        );
        _lastError =
            'Google Play did not complete the purchase in time. Please try again.';
        _productHandlers.remove(product.id);
        finalizePendingPurchase();
      }
    });

    unawaited(completer.future.whenComplete(() => timeoutTimer?.cancel()));

    try {
      final purchaseParam = PurchaseParam(
        productDetails: product,
        // 同上：调用方现取的 userId 优先，兜底用缓存的。
        applicationUserName: applicationUserName ?? _userId,
      );

      debugPrint(
        '[PaymentService] Launching consumable purchase for ${product.id} '
        'user=${applicationUserName ?? _userId}',
      );

      // 注意：插件的 buyConsumable 默认 autoConsume = true，
      // 会在把 purchase 投递给 stream **之前**自动 consume 掉。
      // 所以 app 侧不需要（也不应该）再 consume 一次。
      final launched = await _inAppPurchase.buyConsumable(
        purchaseParam: purchaseParam,
      );

      if (!launched) {
        debugPrint(
          '[PaymentService] buyConsumable failed to launch for ${product.id}',
        );
        _productHandlers.remove(product.id);
        await finalizePendingPurchase();
        return false;
      }

      return await completer.future;
    } catch (e) {
      final message = e.toString();
      debugPrint('[PaymentService] buyConsumable error: $message');
      _productHandlers.remove(product.id);
      _lastError = 'Purchase failed: $message';
      _onPurchaseError?.call('Purchase failed: $message');
      await finalizePendingPurchase();
      return false;
    }
  }

  /// Restore previous purchases
  Future<bool> restorePurchases() async {
    if (!_isInitialized) {
      final initialized = await initialize(
        onPurchaseComplete: _onPurchaseComplete,
        onPurchaseError: _onPurchaseError,
      );
      if (!initialized) {
        return false;
      }
    }

    try {
      // Use the same applicationUserName as when purchasing
      await _inAppPurchase.restorePurchases(
        applicationUserName: _resolveUserId(),
      );
      return true;
    } catch (e) {
      _lastError = 'Restore failed: $e';
      _onPurchaseError?.call('Restore failed: $e');
      return false;
    }
  }

  /// Query existing purchases from Google Play
  Future<List<PurchaseDetails>> queryExistingPurchases({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedPurchases.isNotEmpty &&
        _lastPurchaseQueryTime != null &&
        DateTime.now().difference(_lastPurchaseQueryTime!) <
            _purchaseQueryCacheTtl) {
      debugPrint(
        '[PaymentService] Returning cached purchases from ${_lastPurchaseQueryTime!.toIso8601String()}',
      );
      return _cachedPurchases;
    }

    if (!_isInitialized) {
      await initialize(
        onPurchaseComplete: _onPurchaseComplete,
        onPurchaseError: _onPurchaseError,
      );
    }

    try {
      final androidAddition = _inAppPurchase
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();

      final response = await androidAddition.queryPastPurchases(
        applicationUserName: _resolveUserId(),
      );

      if (response.error != null) {
        return _cachedPurchases.isNotEmpty ? _cachedPurchases : [];
      }

      _cachedPurchases = response.pastPurchases;
      _lastPurchaseQueryTime = DateTime.now();

      return response.pastPurchases;
    } catch (e) {
      return _cachedPurchases.isNotEmpty ? _cachedPurchases : [];
    }
  }

  /// Handle purchase update from the stream
  Future<void> _handlePurchaseUpdate(
    List<PurchaseDetails> purchaseDetailsList,
  ) async {
    for (final purchase in purchaseDetailsList) {
      final bool isPendingProduct =
          purchase.productID == _pendingPurchaseProductId;

      switch (purchase.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          cachePastPurchase(purchase);

          // 按商品用途分流。
          //
          // 之前这里不分类型：所有 purchased 都走 completePurchase（= acknowledge）
          // 然后丢给会员的全局回调。后果是买 K币时：
          //   1. 一次性商品被 acknowledge（语义错了，插件已经自动 consume 过了）
          //   2. 事件落到会员处理器 → 没有 pendingOrderId → 抛 StateError
          //      → 用户买完币看到「Failed to process purchase」
          if (_productKinds[purchase.productID] == PlayProductKind.consumable) {
            if (isPendingProduct) {
              _pendingPurchaseCompleter?.complete(true);
              _pendingPurchaseCompleter = null;
              _pendingPurchaseProductId = null;
              _pendingPurchaseStartedAt = null;
            }
            final handler = _productHandlers.remove(purchase.productID);
            if (handler != null) {
              debugPrint(
                '[PaymentService] Consumable purchase completed: ${purchase.productID}',
              );
              handler(purchase);
            } else {
              debugPrint(
                '[PaymentService] Consumable ${purchase.productID} has no handler — ignored',
              );
            }
            break;
          }

          if (purchase.pendingCompletePurchase) {
            try {
              await _inAppPurchase.completePurchase(purchase);
            } catch (e) {
              // Silently handle acknowledge errors
            }
          }

          if (isPendingProduct) {
            _pendingPurchaseCompleter?.complete(true);
            _pendingPurchaseCompleter = null;
            _pendingPurchaseProductId = null;
            _pendingPurchaseStartedAt = null;
          }

          _onPurchaseComplete?.call(purchase);
          break;
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.canceled:
          debugPrint(
            '[PaymentService] Purchase canceled by user: ${purchase.productID}',
          );
          _productHandlers.remove(purchase.productID);
          // 【必须无条件下清理 pending】
          //
          // Play 返回 userCanceled 时**不带任何购买数据**，插件会构造一个
          // `PurchaseDetails(productID: '', status: canceled)`。
          // 如果这里还靠 `isPendingProduct`（比较 productID）来判断，
          // 取消事件永远匹配不上，_pendingPurchaseCompleter 只能等 120 秒超时
          // —— 用户取消后再点购买就会一直提示「A purchase is already in progress」。
          _pendingPurchaseCompleter?.complete(false);
          _pendingPurchaseCompleter = null;
          _pendingPurchaseProductId = null;
          _pendingPurchaseStartedAt = null;
          _lastError = 'Purchase was canceled';
          break;
        case PurchaseStatus.error:
          final errorMsg = purchase.error?.message ?? '';
          final errorCode = purchase.error?.code ?? 'unknown';
          debugPrint(
            '[PaymentService] Purchase error: code=$errorCode, message=$errorMsg',
          );
          final userFriendlyMsg = _mapPurchaseErrorToUserMessage(errorMsg);
          _lastError = userFriendlyMsg;
          _onPurchaseError?.call(userFriendlyMsg);
          _productHandlers.remove(purchase.productID);
          // 同 canceled：错误事件也可能不带 productID，pending 必须清理。
          if (isPendingProduct ||
              purchase.productID.isEmpty ||
              errorCode == 'userCanceled') {
            _pendingPurchaseCompleter?.complete(false);
            _pendingPurchaseCompleter = null;
            _pendingPurchaseProductId = null;
            _pendingPurchaseStartedAt = null;
          }
          break;
      }
    }
  }

  /// Maps Google Play error messages to user-friendly messages
  String _mapPurchaseErrorToUserMessage(String errorMsg) {
    if (errorMsg.contains('itemAlreadyOwned') ||
        errorMsg.contains('BillingResponse.itemAlreadyOwned')) {
      return 'itemAlreadyOwned'; // Special code for UI to show localized message
    }
    if (errorMsg.contains('SERVICE_UNAVAILABLE')) {
      return 'Service temporarily unavailable. Please try again later.';
    }
    if (errorMsg.contains('NETWORK_ERROR')) {
      return 'Network error. Please check your internet connection.';
    }
    if (errorMsg.contains('USER_CANCELED')) {
      return 'Purchase was canceled.';
    }
    if (errorMsg.contains('DEVELOPER_ERROR')) {
      return 'Product configuration error. Please try again later.';
    }
    if (errorMsg.contains('BILLING_UNAVAILABLE')) {
      return 'Google Play billing is unavailable. Please try again later.';
    }
    if (errorMsg.contains('ITEM_UNAVAILABLE')) {
      return 'This product is currently unavailable.';
    }
    // Default: return original message
    return 'Purchase failed. Please try again.';
  }

  /// Consume a purchase (for consumables like coins)
  /// This must be called after successful purchase to allow repurchasing
  Future<bool> consumePurchase(PurchaseDetails purchase) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final androidAddition = _inAppPurchase
          .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
      await androidAddition.consumePurchase(purchase);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Handle consumable purchase: consume then notify callback
  /// For consumables (payConfigType=1), consume after successful purchase
  Future<bool> handleConsumablePurchase(PurchaseDetails purchase) async {
    try {
      // Consume the purchase to allow future purchases
      final consumed = await consumePurchase(purchase);
      if (!consumed) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Get the current platform type
  TargetPlatform get currentPlatform {
    if (kIsWeb) return defaultTargetPlatform;
    return defaultTargetPlatform;
  }

  /// Clear cached purchases - needed when user cancels and wants to buy again
  void clearCachedPurchases() {
    _cachedPurchases.clear();
    _lastPurchaseQueryTime = null;
    debugPrint('[PaymentService] Cached purchases cleared');
  }

  /// Dispose resources
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
  }
}

/// Local storage helper for caching purchase state
class PurchaseCache {
  static const _keyIsVip = 'is_vip';
  static const _keyVipExpireDate = 'vip_expire_date';
  static const _keySubscriptionType = 'subscription_type';

  final SharedPreferences _prefs;

  PurchaseCache(this._prefs);

  bool get isVip => _prefs.getBool(_keyIsVip) ?? false;
  DateTime? get vipExpireDate {
    final str = _prefs.getString(_keyVipExpireDate);
    if (str == null) return null;
    return DateTime.tryParse(str);
  }

  String? get subscriptionType => _prefs.getString(_keySubscriptionType);

  Future<void> setVipStatus({
    required bool isVip,
    DateTime? expireDate,
    String? type,
  }) async {
    await _prefs.setBool(_keyIsVip, isVip);
    if (expireDate != null) {
      await _prefs.setString(_keyVipExpireDate, expireDate.toIso8601String());
    }
    if (type != null) {
      await _prefs.setString(_keySubscriptionType, type);
    }
  }

  Future<void> clearVipStatus() async {
    await _prefs.remove(_keyIsVip);
    await _prefs.remove(_keyVipExpireDate);
    await _prefs.remove(_keySubscriptionType);
  }
}

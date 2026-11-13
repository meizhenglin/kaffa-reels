import 'package:flutter/foundation.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart';

/// Google Play 的 `BillingResult.responseCode` → Play 官方文档里的数值。
///
/// 插件内部的 pigeon 枚举序号和 Play 的数值**不是一回事**，
/// 所以排查时必须用这里的表换算，否则会把 `SERVICE_UNAVAILABLE(2)`
/// 误读成别的错误。
const Map<BillingResponse, int> _playResponseCodes = <BillingResponse, int>{
  BillingResponse.serviceTimeout: -3,
  BillingResponse.featureNotSupported: -2,
  BillingResponse.serviceDisconnected: -1,
  BillingResponse.ok: 0,
  BillingResponse.userCanceled: 1,
  BillingResponse.serviceUnavailable: 2,
  BillingResponse.billingUnavailable: 3,
  BillingResponse.itemUnavailable: 4,
  BillingResponse.developerError: 5,
  BillingResponse.error: 6,
  BillingResponse.itemAlreadyOwned: 7,
  BillingResponse.itemNotOwned: 8,
  BillingResponse.networkError: 9,
};

/// 一次 `queryProductDetails` 的原始结果。
///
/// 插件公开的 `ProductDetailsResponse` 把 `BillingResult` 丢掉了
/// （见 flutter/flutter#194177），导致「商品不存在」和
/// 「Play 服务不可用」在 App 侧长得一模一样。这里把原始结果拿回来。
class PlayBillingQueryResult {
  const PlayBillingQueryResult({
    required this.productType,
    required this.responseCode,
    required this.debugMessage,
    required this.unfetchedIds,
    required this.foundIds,
  });

  /// 查询的商品类型（一次性商品 / 订阅）。
  final ProductType productType;

  /// Play 返回的响应码。
  final BillingResponse responseCode;

  /// Play 返回的原始调试信息（英文，仅供排查）。
  final String? debugMessage;

  /// Play 明确表示「取不到」的商品 ID。
  ///
  /// 响应码是 [BillingResponse.ok] 且这个列表非空，才说明
  /// **Play 收到了请求、但它不认这个商品 ID**。
  final List<String> unfetchedIds;

  /// 成功取到详情的商品 ID。
  final List<String> foundIds;

  /// Play 官方的数值响应码，方便和 logcat / Play Console 对照。
  int get playCode => _playResponseCodes[responseCode] ?? -999;

  /// Play 是否正常受理了这次请求。
  bool get isOk => responseCode == BillingResponse.ok;

  /// Play 受理了请求，但明确说「这些 ID 我没有」。
  bool get hasUnfetched => unfetchedIds.isNotEmpty;

  @override
  String toString() {
    return 'PlayBillingQueryResult(type=${productType.name}, '
        'code=$playCode(${responseCode.name}), '
        'found=$foundIds, unfetched=$unfetchedIds, '
        'debugMessage=$debugMessage)';
  }
}

/// 直接向 Play 询问原始 `BillingResult` 的探针。
///
/// 走的是插件自己的 `BillingClient` 连接（不新建连接、不重复计费），
/// 所以对线上流程零影响，只在需要诊断时调用。
class PlayBillingProbe {
  const PlayBillingProbe();

  /// 查询 [productIds]，分别按「一次性商品」和「订阅」各查一次。
  ///
  /// 返回空列表表示当前不是 Android 平台（无法查询）。
  Future<List<PlayBillingQueryResult>> query(Set<String> productIds) async {
    if (productIds.isEmpty) {
      return const <PlayBillingQueryResult>[];
    }

    final InAppPurchasePlatform platform;
    try {
      platform = InAppPurchasePlatform.instance;
    } catch (e) {
      // 平台实现还没注册（_instance 是 late，访问前必须有人调过 registerPlatform）。
      debugPrint('[PlayBillingProbe] platform instance not registered: $e');
      return const <PlayBillingQueryResult>[];
    }
    if (platform is! InAppPurchaseAndroidPlatform) {
      return const <PlayBillingQueryResult>[];
    }

    // 复用插件内部的连接管理器，避免再开一条 BillingClient 连接。
    // ignore: invalid_use_of_visible_for_testing_member
    final manager = platform.billingClientManager;

    final results = <PlayBillingQueryResult>[];
    for (final type in ProductType.values) {
      final ProductDetailsResponseWrapper wrapper;
      try {
        wrapper = await manager.runWithClient(
          (client) => client.queryProductDetails(
            productList: productIds
                .map(
                  (String id) =>
                      ProductWrapper(productId: id, productType: type),
                )
                .toList(),
          ),
        );
      } catch (e) {
        debugPrint('[PlayBillingProbe] query($type) threw: $e');
        continue;
      }

      results.add(
        PlayBillingQueryResult(
          productType: type,
          responseCode: wrapper.billingResult.responseCode,
          debugMessage: wrapper.billingResult.debugMessage,
          unfetchedIds: wrapper.unfetchedProductList
              .map((e) => e.productId)
              .toList(),
          foundIds: wrapper.productDetailsList.map((e) => e.productId).toList(),
        ),
      );
    }
    return results;
  }

  /// 把探针结果拼成一段可直接贴到 issue / 日志里的诊断文本。
  static String describe(List<PlayBillingQueryResult> results) {
    if (results.isEmpty) {
      return '  (no Play billing result — not Android, or query failed)';
    }
    final buffer = StringBuffer();
    for (final r in results) {
      buffer.writeln(
        '  · ${r.productType.name}: '
        'code=${r.playCode} (${r.responseCode.name}) '
        'found=${r.foundIds.isEmpty ? '-' : r.foundIds.join(',')} '
        'unfetched=${r.unfetchedIds.isEmpty ? '-' : r.unfetchedIds.join(',')}',
      );
      if (r.debugMessage != null && r.debugMessage!.isNotEmpty) {
        buffer.writeln('      debugMessage: ${r.debugMessage}');
      }
      buffer.writeln('      → ${interpret(r)}');
    }
    return buffer.toString().trimRight();
  }

  /// 根据原始响应码给出「到底为什么失败」的结论。
  static String interpret(PlayBillingQueryResult r) {
    if (!r.isOk) {
      switch (r.responseCode) {
        case BillingResponse.serviceUnavailable:
          return 'Play 服务不可用。请求根本没被 Play 受理，商品 ID 是否正确无关。'
              '常见原因：设备上的 Google 账号不是该应用的 license tester、'
              'Play 商店未登录/登录了别的账号、Play 商店版本过旧、账号授权失效。';
        case BillingResponse.billingUnavailable:
          return 'Play 商店未安装或版本过旧，设备上无法进行结算。';
        case BillingResponse.itemUnavailable:
          return '商品存在但当前不可购买（区域限制 / 已下架 / 未激活）。';
        case BillingResponse.developerError:
          return '请求参数非法，通常是商品类型不对（把一次性商品当订阅查，或反之）。';
        case BillingResponse.networkError:
          return '设备到 Play 的网络不通。';
        case BillingResponse.serviceTimeout:
          return 'Play 响应超时。';
        case BillingResponse.featureNotSupported:
          return '当前设备 / Play 商店不支持该结算能力。';
        case BillingResponse.serviceDisconnected:
          return '与 Play 的结算连接断开。';
        default:
          return 'Play 返回了错误：${r.responseCode.name}。';
      }
    }

    if (r.hasUnfetched) {
      return 'Play 正常受理了请求，但没给这些商品的详情：'
          '${r.unfetchedIds.join(', ')}。'
          '注意：这**不等于**「商品不存在」——也可能是商品存在、但当前账号/国家'
          '没有可购买的 offer。要分清得看原生探针给出的逐商品状态码'
          '（NO_ELIGIBLE_OFFER / PRODUCT_NOT_FOUND）。';
    }

    return 'Play 受理了请求，但没有返回任何商品，也没有说取不到。';
  }

  /// 从探针结果里归纳出一个**稳定**的失败原因码，供 UI 决定提示文案。
  ///
  /// 返回 null 表示 Play 正常受理了请求（没有可归因的服务端错误）。
  ///
  /// 关键区分：
  ///   - `play-service-unavailable` 等码 = Play **根本没受理**这次请求。
  ///     这时商品 ID 写没写错都无关，改商品 ID 不会有任何帮助。
  ///   - `play-item-not-found` = Play 受理了请求，但明确说「没有这个 ID」。
  ///     这才是商品 ID / 类型 / 状态这类配置问题。
  static String? failureCode(List<PlayBillingQueryResult> results) {
    if (results.isEmpty) return null;

    // inapp 和 subs 两次查询一般返回同一个响应码，取第一个非 ok 的即可。
    for (final r in results) {
      switch (r.responseCode) {
        case BillingResponse.serviceUnavailable:
          return 'play-service-unavailable';
        case BillingResponse.billingUnavailable:
          return 'play-store-unavailable';
        case BillingResponse.networkError:
          return 'play-network-error';
        case BillingResponse.serviceTimeout:
          return 'play-timeout';
        case BillingResponse.itemUnavailable:
          return 'play-item-unavailable';
        case BillingResponse.developerError:
          return 'play-developer-error';
        case BillingResponse.featureNotSupported:
          return 'play-feature-not-supported';
        case BillingResponse.serviceDisconnected:
          return 'play-service-disconnected';
        default:
          continue;
      }
    }

    // Play 受理了请求，但明确说「没这个商品 ID」。
    if (results.any((r) => r.hasUnfetched)) {
      return 'play-item-not-found';
    }
    return null;
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Play 对「这个商品取不到」给出的原因码。
///
/// 对应 billing 8.0.0 的 `com.android.billingclient.api.UnfetchedProduct.StatusCode`。
/// 插件在 `Translator.fromUnfetchedProduct` 里把 statusCode 丢掉了，
/// 所以这里通过原生探针（见 `BillingProbe.java`）把它拿回来。
class PlayUnfetchedStatus {
  const PlayUnfetchedStatus._();

  /// Play 没有给出明确原因。
  static const int unknown = 0;

  /// 商品 ID 格式非法（Play 侧对 ID 命名有要求）。
  static const int invalidProductIdFormat = 2;

  /// **这个商品在当前 Play 应用下根本不存在。**
  ///
  /// 典型原因：商品建在了另一个 Play 应用下（例如 `com.video.storydrama.platform`
  /// 和 `com.video.storydrama` 是两个独立的 Play 应用）、商品类型建错
  /// （订阅建成了 one-time product）、ID 拼错、商品已被删除。
  static const int productNotFound = 3;

  /// **商品存在，但当前账号 / 国家没有可购买的 offer。**
  ///
  /// 典型原因：订阅的基础方案没配价或没激活、该方案在新国家未开放、
  /// Play 账号所在国家与商品开放区域不匹配、账号未加入测试人员。
  /// 这种情况下「商品其实一直在商店里」，所以**不能**按「商品没创建」处理。
  static const int noEligibleOffer = 4;

  /// 把数字状态码翻译成可读名称。
  static String name(int statusCode) {
    switch (statusCode) {
      case unknown:
        return 'UNKNOWN';
      case invalidProductIdFormat:
        return 'INVALID_PRODUCT_ID_FORMAT';
      case productNotFound:
        return 'PRODUCT_NOT_FOUND';
      case noEligibleOffer:
        return 'NO_ELIGIBLE_OFFER';
      default:
        return 'CODE_$statusCode';
    }
  }

  /// 该状态码是否代表「商品确实不存在」。
  static bool isNotFound(int statusCode) => statusCode == productNotFound;

  /// 该状态码是否代表「商品存在但买不了」。
  static bool isNoEligibleOffer(int statusCode) =>
      statusCode == noEligibleOffer;
}

/// 原生探针里「某个商品被 Play 拒绝」的原始信息。
class PlayUnfetchedProduct {
  const PlayUnfetchedProduct({
    required this.productId,
    required this.productType,
    required this.statusCode,
  });

  final String productId;

  /// Play 认定的商品类型：`subs` 或 `inapp`。
  final String? productType;

  /// Play 给出的原因码，见 [PlayUnfetchedStatus]。
  final int statusCode;

  String get statusName => PlayUnfetchedStatus.name(statusCode);

  bool get isNotFound => PlayUnfetchedStatus.isNotFound(statusCode);

  bool get isNoEligibleOffer => PlayUnfetchedStatus.isNoEligibleOffer(statusCode);

  @override
  String toString() => '$productId($statusName)';
}

/// 原生探针的一次商品类型查询结果。
class PlayNativeQueryResult {
  const PlayNativeQueryResult({
    required this.type,
    required this.responseCode,
    required this.debugMessage,
    required this.foundIds,
    required this.unfetched,
  });

  /// `subs` 或 `inapp`。
  final String type;

  /// Play 的原始响应码（0 = OK）。
  final int responseCode;

  /// Play 返回的英文调试信息。
  final String? debugMessage;

  /// 成功取到详情的商品 ID。
  final List<String> foundIds;

  /// 被 Play 拒绝的商品（含原因码）。
  final List<PlayUnfetchedProduct> unfetched;

  bool get isOk => responseCode == 0;

  @override
  String toString() =>
      '$type: code=$responseCode found=$foundIds unfetched=$unfetched';
}

/// 原生探针的完整结果。
class PlayNativeProbeResult {
  const PlayNativeProbeResult({
    required this.setupCode,
    required this.setupDebugMessage,
    required this.countryCode,
    required this.queries,
  });

  /// 建立结算连接时的响应码（0 = OK）。
  final int setupCode;

  /// 建立连接失败时的调试信息。
  final String? setupDebugMessage;

  /// Play 结算国家（ISO 两位国家码），判断「区域不匹配」的关键线索。
  final String? countryCode;

  /// 按商品类型分组的查询结果。
  final List<PlayNativeQueryResult> queries;

  bool get isOk => setupCode == 0;

  /// 所有查询里成功取到详情的商品 ID。
  Set<String> get foundIds => {
    for (final q in queries) ...q.foundIds,
  };

  /// 按商品 ID 归并「被 Play 拒绝」的记录（同一个 ID 可能被查了两次）。
  Map<String, List<PlayUnfetchedProduct>> get _unfetchedById {
    final map = <String, List<PlayUnfetchedProduct>>{};
    for (final q in queries) {
      for (final p in q.unfetched) {
        map.putIfAbsent(p.productId, () => <PlayUnfetchedProduct>[]).add(p);
      }
    }
    return map;
  }

  /// **商品在当前 Play 应用下确实不存在**的 ID。
  ///
  /// 判定条件（三者同时成立）：
  ///   1. 任何一次查询里都没取到它（否则说明它只是被用错类型查了）；
  ///   2. 每一次查询都明确返回 `PRODUCT_NOT_FOUND`；
  ///   3. 没有一次返回 `NO_ELIGIBLE_OFFER`。
  ///
  /// 为什么要跨类型合并：Play 对「用 inapp 类型去查一个订阅商品」同样返回
  /// `PRODUCT_NOT_FOUND`。只认单次查询的话，一个**完全正常**的订阅商品
  /// 会被误判成「不存在」。
  Set<String> get notFoundIds {
    final found = foundIds;
    final result = <String>{};
    for (final entry in _unfetchedById.entries) {
      if (found.contains(entry.key)) continue;
      if (entry.value.every((p) => p.isNotFound)) {
        result.add(entry.key);
      }
    }
    return result;
  }

  /// **商品存在，但当前账号 / 国家没有可购买的 offer** 的 ID。
  ///
  /// 这类商品在 Play Console 里一直都在，不能按「商品没创建」处理。
  Set<String> get noEligibleOfferIds {
    final found = foundIds;
    final result = <String>{};
    for (final entry in _unfetchedById.entries) {
      if (found.contains(entry.key)) continue;
      if (entry.value.any((p) => p.isNoEligibleOffer)) {
        result.add(entry.key);
      }
    }
    return result;
  }

  /// 既不是「不存在」也不是「没 offer」的 ID（Play 给了 UNKNOWN 之类的状态）。
  Set<String> get unclassifiedIds {
    final found = foundIds;
    final notFound = notFoundIds;
    final noOffer = noEligibleOfferIds;
    return {
      for (final id in _unfetchedById.keys)
        if (!found.contains(id) &&
            !notFound.contains(id) &&
            !noOffer.contains(id))
          id,
    };
  }

  /// 拼成可直接贴进 issue / 日志的诊断文本。
  String describe() {
    final buffer = StringBuffer();
    buffer.writeln(
      'setup: code=$setupCode${setupDebugMessage == null ? '' : ' / $setupDebugMessage'}'
      '${countryCode == null ? '' : ' / 结算国家=$countryCode'}',
    );
    for (final q in queries) {
      buffer.writeln(
        '· ${q.type}: code=${q.responseCode} '
        'found=${q.foundIds.isEmpty ? '-' : q.foundIds.join(',')} '
        'unfetched=${q.unfetched.isEmpty ? '-' : q.unfetched.join(',')}',
      );
    }
    if (notFoundIds.isNotEmpty) {
      buffer.writeln('→ 商品在当前 Play 应用下不存在: ${notFoundIds.join(', ')}');
    }
    if (noEligibleOfferIds.isNotEmpty) {
      buffer.writeln(
        '→ 商品存在但当前账号/国家没有可购买的 offer: ${noEligibleOfferIds.join(', ')}',
      );
    }
    if (unclassifiedIds.isNotEmpty) {
      buffer.writeln('→ 原因不明: ${unclassifiedIds.join(', ')}');
    }
    return buffer.toString().trimRight();
  }
}

/// 通过原生 MethodChannel 向 Play 直接查询商品，并带回每个商品的原因码。
///
/// 与 `PlayBillingProbe`（纯 Dart，复用插件的连接）的区别：
/// 这里**新开一条**结算连接，直接读 `UnfetchedProduct.getStatusCode()`，
/// 因此能区分「商品不存在」和「商品存在但买不了」。
///
/// 只用于诊断，不发起购买、不影响正常结算流程。
class PlayNativeBillingProbe {
  const PlayNativeBillingProbe();

  static const MethodChannel _channel = MethodChannel(
    'com.video.storydrama/billing_probe',
  );

  /// 查询 [productIds]。非 Android 平台或原生未注册时返回 null。
  Future<PlayNativeProbeResult?> probe(List<String> productIds) async {
    if (productIds.isEmpty) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'probe',
        <String, dynamic>{'productIds': productIds},
      );
      if (raw == null) return null;
      return _parse(raw);
    } on MissingPluginException {
      debugPrint('[PlayNativeBillingProbe] 原生通道未注册（非 Android 构建）');
      return null;
    } catch (e) {
      debugPrint('[PlayNativeBillingProbe] 探针执行失败: $e');
      return null;
    }
  }

  PlayNativeProbeResult _parse(Map<String, dynamic> raw) {
    return parseResult(raw);
  }

  /// 编译期开关：`--dart-define=PLAY_PROBE_IDS=id1,id2,id3`。
  ///
  /// 打开后 App 启动就会向 Play 查询这些商品，并把**每个商品的状态码**
  /// 打到 logcat。用于在真机上快速确认「商品到底存不存在」。
  static const String probeIdsDefine = String.fromEnvironment(
    'PLAY_PROBE_IDS',
  );

  /// 启动时跑一次诊断探针（仅在通过 [probeIdsDefine] 传了商品 ID 时才动作）。
  static Future<void> runStartupProbe() async {
    final ids = probeIdsDefine
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;

    debugPrint('[PlayProbe] 启动诊断探针: $ids');
    final result = await const PlayNativeBillingProbe().probe(ids);
    if (result == null) {
      debugPrint('[PlayProbe] 原生探针不可用（非 Android 或通道未注册）');
      return;
    }
    debugPrint('[PlayProbe] ────────────────────────────────');
    debugPrint('[PlayProbe] ${result.describe()}');
    debugPrint('[PlayProbe] ────────────────────────────────');
  }

  /// 把原生返回的 Map 解析成 [PlayNativeProbeResult]。
  ///
  /// 公开出来是为了能直接对解析逻辑写单元测试。
  @visibleForTesting
  static PlayNativeProbeResult parseResult(Map<String, dynamic> raw) {
    final queries = <PlayNativeQueryResult>[];
    final rawQueries = raw['queries'];
    if (rawQueries is List) {
      for (final item in rawQueries) {
        if (item is! Map) continue;
        final found = <String>[];
        final rawFound = item['found'];
        if (rawFound is List) {
          for (final f in rawFound) {
            if (f is Map && f['productId'] is String) {
              found.add(f['productId'] as String);
            }
          }
        }
        final unfetched = <PlayUnfetchedProduct>[];
        final rawUnfetched = item['unfetched'];
        if (rawUnfetched is List) {
          for (final u in rawUnfetched) {
            if (u is! Map) continue;
            final id = u['productId'];
            if (id is! String) continue;
            unfetched.add(
              PlayUnfetchedProduct(
                productId: id,
                productType: u['productType'] as String?,
                statusCode: (u['statusCode'] as num?)?.toInt() ?? 0,
              ),
            );
          }
        }
        queries.add(
          PlayNativeQueryResult(
            type: item['type'] as String? ?? 'unknown',
            responseCode: (item['responseCode'] as num?)?.toInt() ?? -1,
            debugMessage: item['debugMessage'] as String?,
            foundIds: found,
            unfetched: unfetched,
          ),
        );
      }
    }
    return PlayNativeProbeResult(
      setupCode: (raw['setupCode'] as num?)?.toInt() ?? -1,
      setupDebugMessage: raw['setupDebugMessage'] as String?,
      countryCode: raw['countryCode'] as String?,
      queries: queries,
    );
  }
}

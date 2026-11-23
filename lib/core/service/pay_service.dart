import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/app_config.dart';
import '../config/runtime_os.dart';
import '../network/api_service.dart';
import '../storage/storage_service.dart';

/// ============================================================================
/// 支付服务
///
/// 【功能说明】
/// 对应小程序原版 common/pay.js + common/billing.js，统一封装所有支付相关逻辑：
/// - 支付环境判断（Android/iOS 支付开关）
/// - Google Play 内购（Android）
/// - iOS 内购（App Store）
/// - 抖音支付（小程序环境）
/// - 微信支付（小程序环境）
///
/// 【小程序原版对应】
/// - payOrder() → PayService.requestOrder() + PayService.pay()
/// - BillingService → PayService (Google Play)
/// ============================================================================
class PayService {
  PayService({
    ApiService? apiService,
    StorageService? storage,
  })  : _apiService = apiService ?? apiServiceProvider,
        _storage = storage ?? StorageService();

  final ApiService _apiService;
  final StorageService _storage;

  // ==================== 支付环境判断 ====================

  /// 获取当前设备 OS 名称
  ///
  /// 【不再读 AppConfig.platformType】那是打包前手改的常量（Android/iOS），
  /// 忘改就会让 iOS 端拿到 Android 的 payType=5，订单全记错渠道。
  /// 改为运行时判断（内购流程只在原生平台跑，web 不会走到这里）。
  String get osName => runtimeOsName;

  /// 判断当前环境是否允许支付（基于后端返回的系统配置）
  Future<bool> isPayEnabled() async {
    final config = await _storage.getSystemConfig();
    if (config == null) return true; // 无配置时默认允许

    final androidSwitch = config['androidPaySwitch'];
    final iosSwitch = config['iosPaySwitch'];

    if (osName == 'iOS' && iosSwitch == 0) {
      return false;
    }
    if (osName != 'iOS' && androidSwitch == 0) {
      return false;
    }
    return true;
  }

  /// 获取当前支付类型
  /// 3=抖音 2=微信 5=Android 6=iOS
  int get currentPayType {
    switch (osName) {
      case 'iOS':
        return AppConfig.payTypeiOS;
      default:
        return AppConfig.payTypeAndroid;
    }
  }

  // ==================== 统一下单 ====================

  /// 请求创建订单
  /// [payConfigId] 支付配置 ID
  /// [payType] 支付渠道类型
  Future<PayOrderResult?> createOrder({
    required int payConfigId,
    int? payType,
  }) async {
    final enabled = await isPayEnabled();
    if (!enabled) {
      throw PayException('暂不支持购买');
    }

    final resp = await _apiService.userRechange(
      payType: payType ?? currentPayType,
      payConfigId: payConfigId,
    );

    if (resp.isSuccess && resp.data != null) {
      return PayOrderResult.fromJson(resp.data as Map<String, dynamic>);
    }
    throw PayException(resp.error ?? '创建订单失败');
  }

  // ==================== Google Play 支付（Android） ====================

  /// Google Play 内购查询商品
  /// 【Flutter 实现】使用 in_app_purchase 包
  /// [productIds] 商品 ID 列表
  Future<List<ProductDetails>> queryGoogleProducts(List<String> productIds) async {
    // 注意：此方法需要配合 in_app_purchase 包实现
    // 详见 features/payment/ 模块
    throw UnimplementedError(
      'Google Play 支付请使用 in_app_purchase 包，'
      '参考 features/payment/ 模块',
    );
  }

  /// Google Play 购买（Flutter 原生通道）
  ///
  /// [params] Google 返回的购买回调完整信息，原样透传给服务端。
  ///
  /// 【注意】这里传的是 **Map**，不要再手动 `jsonEncode`。
  /// 后端 `/notice/google` 的 requestBody 是 `@RequestBody String`，
  /// 由后端自己解析 JSON；客户端多包一层字符串反而会让后端拿不到字段。
  /// 序列化细节见 [ApiService.googleCallBack]。
  Future<bool> confirmGooglePurchase({
    required Map<String, dynamic> params,
  }) async {
    final resp = await _apiService.googleCallBack(params: params);
    if (!resp.isSuccess) {
      debugPrint(
        '[PayService] Google 回调失败: code=${resp.code} error=${resp.error}',
      );
    }
    return resp.isSuccess;
  }

  // ==================== iOS 内购（App Store） ====================

  /// Apple 内购回调（`POST /notice/apple`）。
  ///
  /// 【为什么不发 /notice/google】之前 iOS 的购买结果被丢进 Google 回调，
  /// 后端 appleCallBack 永远收不到 —— 付了钱会员/金币不到账。
  /// 报文结构和 Google 回调一致（orderNo/productId/purchaseToken…），
  /// 额外带 platform=ios，receipt 放 App Store 收据（Base64）。
  Future<bool> confirmApplePurchase({
    required Map<String, dynamic> params,
  }) async {
    final resp = await _apiService.appleCallBack(params: params);
    if (!resp.isSuccess) {
      debugPrint(
        '[PayService] Apple 回调失败: code=${resp.code} error=${resp.error}',
      );
    }
    return resp.isSuccess;
  }

  /// 按当前平台把购买结果发到正确的回调接口：
  /// iOS → /notice/apple，其余 → /notice/google。
  ///
  /// 各购买链路（K币/解锁/会员）统一走这里，不再各自判断平台。
  Future<bool> confirmStorePurchase({
    required Map<String, dynamic> params,
  }) async {
    if (osName == 'iOS') {
      return confirmApplePurchase(params: {...params, 'platform': 'ios'});
    }
    return confirmGooglePurchase(params: {...params, 'platform': 'android'});
  }

  /// iOS 内购确认
  /// [params] 包含 transactionId 和 productId
  Future<bool> confirmIOSPurchase({
    required String transactionId,
    required String productId,
  }) async {
    final callbackPayload = {
      'transactionId': transactionId,
      'productId': productId,
      'platform': 'ios',
    };
    return confirmApplePurchase(params: callbackPayload);
  }

  // ==================== 播放器广告（Flutter 等价实现） ====================

  /// 检查是否可以播放（广告解锁逻辑）
  /// 对应小程序 playerManager.js 的 onCheckIsCanPlay 逻辑
  /// [episodeId] 当前集 ID
  /// [videoId] 视频 ID
  Future<bool> checkEpisodeUnlock({
    required String episodeId,
    required String videoId,
  }) async {
    // 此处应调用后端接口判断当前集是否已解锁
    // 实际业务中可调用 getEpisodeInfo 获取集信息
    final resp = await _apiService.getEpisodeInfo(
      videoId: videoId,
      episodesId: episodeId,
    );
    if (resp.isSuccess && resp.data != null) {
      final data = resp.data as Map<String, dynamic>;
      return data['isFree'] == true || data['isUnlock'] == true;
    }
    return false;
  }

  /// 购买解锁单集
  Future<bool> purchaseEpisode({
    required String videoId,
    required String episodesId,
    required int episodesNum,
    required int goodsId,
  }) async {
    final resp = await _apiService.getUserPayEpisodes(
      videoId: videoId,
      episodesId: episodesId,
      episodesNum: episodesNum,
      goodsId: goodsId,
    );
    return resp.isSuccess;
  }
}

/// 支付订单结果
class PayOrderResult {
  /// 抖音/微信订单参数
  final Map<String, dynamic>? orderData;
  /// 字节跳动授权信息
  final String? byteAuthorization;
  /// 微信签名参数
  final String? signData;
  final String? paySig;
  final String? signature;
  final String? mode;
  /// 订单 ID
  final String? orderId;

  const PayOrderResult({
    this.orderData,
    this.byteAuthorization,
    this.signData,
    this.paySig,
    this.signature,
    this.mode,
    this.orderId,
  });

  factory PayOrderResult.fromJson(Map<String, dynamic> json) {
    String? asString(dynamic value) {
      if (value == null) return null;
      return value.toString();
    }

    final nestedOrderData = json['data'] as Map<String, dynamic>?;

    return PayOrderResult(
      orderData: nestedOrderData,
      byteAuthorization: asString(json['byteAuthorization'] ?? nestedOrderData?['byteAuthorization']),
      signData: asString(json['signData'] ?? nestedOrderData?['signData']),
      paySig: asString(json['paySig'] ?? nestedOrderData?['paySig']),
      signature: asString(json['signature'] ?? nestedOrderData?['signature']),
      mode: asString(json['mode'] ?? nestedOrderData?['mode']),
      orderId: asString(
        json['orderId'] ??
            json['orderNo'] ??
            nestedOrderData?['orderId'] ??
            nestedOrderData?['orderNo'],
      ),
    );
  }
}

/// 支付异常
class PayException implements Exception {
  final String message;
  const PayException(this.message);

  @override
  String toString() => message;
}

/// PayService 全局单例 Provider
final payServiceProvider = PayService();

import 'dart:convert';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../config/app_config.dart';
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
  /// Flutter 无法直接判断真实系统，通过 platformType 读取 AppConfig
  String get osName => AppConfig.platformType;

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
  /// [params] Google 返回的购买回调完整信息，序列化后透传给服务端
  Future<bool> confirmGooglePurchase({
    required Map<String, dynamic> params,
  }) async {
    final resp = await _apiService.googleCallBack(
      params: jsonEncode(params),
    );
    return resp.isSuccess;
  }

  // ==================== iOS 内购（App Store） ====================

  /// iOS 内购（Flutter 原生通道）
  /// 【Flutter 实现】使用 in_app_purchase 包
  /// 此方法由 features/payment/ 模块调用，完成购买后通知后端
  Future<bool> confirmIOSPurchase({
    required String transactionId,
    required String productId,
  }) async {
    // 注意：此方法需要配合 in_app_purchase 包实现
    throw UnimplementedError(
      'App Store 支付请使用 in_app_purchase 包，'
      '参考 features/payment/ 模块',
    );
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
    required int goodsId,
  }) async {
    final resp = await _apiService.getUserPayEpisodes(
      videoId: videoId,
      episodesId: episodesId,
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

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../constants/api_error_code.dart';
import '../constants/app_constants.dart';
import '../model/api_endpoints.dart';
import '../storage/storage_service.dart';
import '../../app/providers/app_providers.dart';
import 'dio_client.dart';

/// ============================================================================
/// API 服务层
///
/// 【功能说明】
/// 对应小程序原版 models/ 目录下所有 Model 类，统一封装所有后端 API 调用。
/// - 所有请求自动携带 X-Client、token、client_params 头
/// - 统一处理 code=23（Token 过期）等错误
///
/// 【小程序 Model 对照】
/// - LoginModel       → 登录类 API
/// - TheaterModel      → 剧场 Tab API
/// - RecommendedModel  → 推荐 Tab API
/// - UserCenterModel   → 个人中心 API
/// - UpdataModel       → App 检查更新 API
/// ============================================================================
class ApiService {
  ApiService({DioClient? dioClient, StorageService? storage})
      : _dioClient = dioClient ?? DioClient(),
        _storage = storage ?? StorageService();

  final DioClient _dioClient;
  final StorageService _storage;

  Dio get _dio => _dioClient.dio;

  String _buildXClientHeader() {
    final savedLang = _storage.getString(AppConstants.deviceLangKey);
    final locale = PlatformDispatcher.instance.locale;
    final lang = _normalizeLang(savedLang, fallbackLocale: locale);
    final xClient = AppConfig.currentXClient;
    final version = AppConfig.appVersion;
    final osName = AppConfig.platformType;
    return '$xClient;version=$version;osName=$osName;x-lang=$lang';
  }

  String _normalizeLang(String? value, {Locale? fallbackLocale}) {
    final normalized = value?.trim();
    if (normalized == 'ar-SA') {
      return 'ar-SA';
    }
    if (normalized == 'en-US') {
      return 'en-US';
    }
    if (normalized == 'ar') {
      return 'ar-SA';
    }
    if (normalized == 'en') {
      return 'en-US';
    }
    return formatDeviceLang(fallbackLocale ?? const Locale('en'));
  }

  // ==================== 统一请求方法 ====================

  /// 统一请求方法
  /// [url]       接口路径
  /// [data]      请求参数
  /// [method]    HTTP 方法，默认 POST
  /// [isForm]    是否使用 form-urlencoded 格式
  Future<ApiResponse> request(
    String url, {
    Map<String, dynamic>? data,
    String method = 'POST',
    bool isForm = false,
  }) async {
    try {
      final token = await _storage.getToken();
      final clientParams = _storage.getString('client_params_linekong') ?? '';

      final headers = <String, dynamic>{
        'Content-Type': isForm
            ? 'application/x-www-form-urlencoded'
            : 'application/json',
        'X-Client': _buildXClientHeader(),
        if (token != null && token.isNotEmpty) 'token': token,
        if (clientParams.isNotEmpty) ...{
          'client_params': clientParams,
          'clientparams': clientParams,
        },
      };

      debugPrint('[ApiService] REQUEST[$method] => $url body=$data');

      final Response response;
      if (isForm) {
        response = await _dio.request(
          url,
          data: FormData.fromMap(data ?? {}),
          options: Options(method: method, headers: headers),
        );
      } else {
        response = await _dio.request(
          url,
          data: data,
          options: Options(method: method, headers: headers),
        );
      }

      final body = response.data;
      debugPrint('[ApiService] RESPONSE[$url] => $body');

      if (response.statusCode == 200) {
        final code = body['code'] as int?;
        final msg = body['msg'] as String?;

        if (code == ApiErrorCode.success || code == ApiErrorCode.ok) {
          return ApiResponse.success(body['data']);
        } else if (code == ApiErrorCode.tokenExpired) {
          return ApiResponse.expired(msg ?? 'Token expired');
        } else {
          return ApiResponse.error(msg ?? 'Request failed', code: code);
        }
      } else {
        return ApiResponse.error('HTTP ${response.statusCode}',
            code: response.statusCode);
      }
    } on DioException catch (e) {
      debugPrint('[ApiService] DioException => ${e.message}');
      if (e.response?.statusCode == 200) {
        final body = e.response?.data;
        final code = body?['code'] as int?;
        if (code == ApiErrorCode.tokenExpired) {
          return ApiResponse.expired(body?['msg'] ?? 'Token expired');
        }
      }
      return ApiResponse.error(e.message ?? 'Network error');
    } catch (e) {
      debugPrint('[ApiService] Exception => $e');
      return ApiResponse.error(e.toString());
    }
  }

  // ==================== LoginModel 登录类 ====================

  /// 邮箱登录
  Future<ApiResponse> login({
    required String email,
    required String passportPassword,
  }) {
    return request(
      ApiEndpoints.login,
      data: {
        'passportType': 1,
        'email': email,
        'passportPassword': passportPassword,
      },
    );
  }

  /// 游客登录
  /// 游客登录（对应 /api/user/userAuthorization）
  /// [passportName] 使用持久化的设备 UUID
  Future<ApiResponse> guestLogin({
    required String deviceId,
  }) {
    debugPrint('[ApiService] guestLogin called, deviceId=$deviceId');
    return request(
      ApiEndpoints.guestLogin,
      data: {
        'passportType': 0,     // 0=游客，1=邮箱，5=Google，6=Apple
        'passportName': deviceId,
      },
    );
  }

  /// Google 登录（idToken 模式）
  Future<ApiResponse> googleIdToken({required String idToken}) {
    return request(
      ApiEndpoints.googleIdToken,
      data: {
        'passportType': PassportType.google,
        'idToken': idToken,
      },
    );
  }

  /// Google 登录（accessToken 模式）
  Future<ApiResponse> googleLogin({required String accessToken}) {
    return request(
      ApiEndpoints.googleLogin,
      data: {
        'passportType': PassportType.google,
        'accessToken': accessToken,
      },
    );
  }

  /// Apple 登录
  Future<ApiResponse> appleLogin({
    required String identityToken,
    required String authorizationCode,
    String? fullName,
  }) {
    return request(
      ApiEndpoints.appleLogin,
      data: {
        'passportType': PassportType.apple,
        'idToken': identityToken,
        'authorizationCode': authorizationCode,
        if (fullName != null && fullName.isNotEmpty) 'fullName': fullName,
      },
    );
  }

  /// 微信登录
  Future<ApiResponse> wechatLogin({required String code}) {
    return request(
      ApiEndpoints.weixinLogin,
      data: {
        'passportType': PassportType.wechat,
        'code': code,
      },
    );
  }

  /// 抖音登录
  Future<ApiResponse> douyinLogin({required String code}) {
    return request(
      ApiEndpoints.douyinLogin,
      data: {
        'passportType': PassportType.douyin,
        'code': code,
      },
    );
  }

  /// 获取远端配置
  Future<ApiResponse> getSystemConfig() {
    return request(ApiEndpoints.getSystemConfig, method: 'GET');
  }

  // ==================== Flutter 特有 ====================

  /// 发送邮箱验证码
  /// type: 0 - 登录，1 - 注册
  Future<ApiResponse> sendEmailCode({required String email, int type = 0}) {
    return request(
      ApiEndpoints.sendEmailCode,
      data: {'email': email, 'type': type},
      isForm: true,
    );
  }

  /// 校验邮箱验证码
  Future<ApiResponse> checkEmailCode({
    required String email,
    required String code,
  }) {
    return request(
      ApiEndpoints.checkEmailCode,
      data: {'email': email, 'code': code},
      isForm: true,
    );
  }

  /// 注册账号
  Future<ApiResponse> register({
    required String email,
    required String passportPassword,
  }) {
    return request(
      ApiEndpoints.register,
      data: {
        'email': email,
        'passportPassword': passportPassword,
      },
      isForm: false,
    );
  }

  /// 修改昵称
  Future<ApiResponse> updateNickname({required String nickname}) {
    return request(
      ApiEndpoints.updateNickname,
      data: {'nickname': nickname},
    );
  }

  /// 用户设置（统一接口：修改昵称/头像/语言）
  /// setId: 1=昵称  2=头像  3=语言
  Future<ApiResponse> updateUserSettings({
    required int setId,
    String? setValue,
    String? nickName,
    String? avatarUrl,
    String? language,
  }) async {
    final response = await request(
      ApiEndpoints.userSettings,
      data: {
        'setId': setId,
        if (setValue != null) 'setValue': setValue,
        if (nickName != null) 'nickName': nickName,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (language != null) 'language': language,
      },
    );

    if (response.isSuccess && setId == 3) {
      final data = response.data;
      final returnedLanguage = data is Map<String, dynamic>
          ? data['language'] as String?
          : data is Map
              ? data['language']?.toString()
              : null;
      if (returnedLanguage != null && returnedLanguage.trim().isNotEmpty) {
        final normalizedLanguage = _normalizeLang(returnedLanguage);
        await _storage.setString(AppConstants.deviceLangKey, normalizedLanguage);
        await _storage.setString(AppConstants.localeKey, normalizedLanguage.startsWith('ar') ? 'ar' : 'en');
      }
    }

    return response;
  }

  /// 获取头像列表
  Future<ApiResponse> getAvatarList() {
    return request('${ApiEndpoints.avatarList}?id=11', method: 'GET');
  }

  // ==================== TheaterModel 剧场 Tab ====================

  /// 剧场 Banner 列表
  Future<ApiResponse> getTheaterBanner({int bannerPosition = 0}) {
    return request(
      ApiEndpoints.theaterBanner,
      data: {'bannerPosition': bannerPosition},
    );
  }

  /// 剧场 排行榜列表
  Future<ApiResponse> getRankingList({int? type}) {
    return request(
      ApiEndpoints.rankingList,
      data: type != null ? {'type': type} : null,
    );
  }

  /// 精选好剧/独家推荐/猜您喜欢/推荐剧集
  /// [videoHotListType] 1=热门搜索 2=精选好剧 3=独家推荐 4=猜您喜欢
  Future<ApiResponse> getVideoHotPicks({required int videoHotListType}) {
    return request(
      ApiEndpoints.videoHotPicks,
      data: {'videoHotListType': videoHotListType},
    );
  }

  /// 获取用户最近观看
  Future<ApiResponse> getLastUserViewHistoryOne() {
    return request(ApiEndpoints.lastUserViewHistoryOne, method: 'POST');
  }

  /// 根据视频 ID 获取用户观看的集数
  Future<ApiResponse> getUserViewHistoryByVideoId({required String videoId}) {
    return request(
      ApiEndpoints.userViewHistoryByVideoId,
      data: {'videoId': videoId},
    );
  }

  /// 获取搜索历史记录
  Future<ApiResponse> getSearchHistory() {
    return request(ApiEndpoints.searchHistory, method: 'GET');
  }

  /// 删除搜索历史记录
  Future<ApiResponse> deleteSearchHistory() {
    return request(ApiEndpoints.deleteSearchHistory, method: 'POST');
  }

  /// 推荐搜索词列表
  Future<ApiResponse> getRecommondSearchList() {
    return request(ApiEndpoints.recommondSearchList, method: 'GET');
  }

  /// 搜索结果
  Future<ApiResponse> getSearchList({required String searchName}) {
    return request(
      ApiEndpoints.searchVideo,
      data: {'searchName': searchName},
    );
  }

  /// 全部剧集 - 标签列表
  Future<ApiResponse> getVideoLabelList() {
    return request(ApiEndpoints.videoLabelList, method: 'POST');
  }

  /// 全部剧集 - 根据标签搜索剧集列表
  Future<ApiResponse> getVideoListByLabel({
    required int videoLabelId,
    int pageNum = 1,
    int pageSize = 12,
  }) {
    return request(
      ApiEndpoints.videoListByLabel,
      data: {
        'videoLabelId': videoLabelId,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
  }

  // ==================== RecommendedModel 推荐 Tab ====================

  /// 获取推荐的剧集列表
  Future<ApiResponse> getRecommendedEpisodes() {
    return request(ApiEndpoints.recommendIndex, method: 'GET');
  }

  /// 根据视频 ID 获取剧集列表（正片/花絮等）
  ///
  /// [episodesNum] 当前集号（从 getEpisodeInfo 的 videoEpisodes 获取，用于定位当前集）
  /// [pageSize] 每页集数，默认取 videoEpisodes（总集数），即一次性拉全量
  Future<ApiResponse> getVideoListByVideoId({
    required String videoId,
    int episodesNum = 1,
    int? pageSize,
  }) {
    return request(
      ApiEndpoints.playVideo,
      data: {
        'videoId': videoId,
        'episodesNum': episodesNum,
        if (pageSize != null) 'pageSize': pageSize,
      },
    );
  }

  /// 根据视频 ID 获取剧集目录（集数列表）
  Future<ApiResponse> getEpisodesDirectoryByVideoId({required String videoId}) {
    return request(
      ApiEndpoints.episodesDirectory,
      data: {'videoId': videoId},
    );
  }

  /// 视频点赞/取消点赞
  /// [type] 1=喜欢 2=取消
  Future<ApiResponse> setVideoLike({
    required String videoId,
    required int type,
  }) {
    return request(
      ApiEndpoints.videoLike,
      data: {'videoId': videoId, 'type': type},
    );
  }

  /// 视频追剧/取消追剧
  /// [type] 1=追 2=取消
  Future<ApiResponse> setVideoCollect({
    required String videoId,
    required int type,
  }) {
    return request(
      ApiEndpoints.videoCollect,
      data: {'videoId': videoId, 'type': type},
    );
  }

  /// 视频内获取商品列表（快充）
  Future<ApiResponse> getQuickRechargeList({required String videoId}) {
    return request(
      ApiEndpoints.quickRechargeList,
      data: {'videoId': videoId},
    );
  }

  /// 用户购买剧集（解锁）
  Future<ApiResponse> getUserPayEpisodes({
    required String videoId,
    required String episodesId,
    required int goodsId,
  }) {
    return request(
      ApiEndpoints.userPayEpisodes,
      data: {
        'videoId': videoId,
        'episodesId': episodesId,
        'goodsId': goodsId,
      },
    );
  }

  /// 添加观看历史
  Future<ApiResponse> setUserViewAddHistory({
    required String videoId,
    String? episodesId,
  }) {
    return request(
      ApiEndpoints.userViewAddHistory,
      data: {
        'videoId': videoId,
        if (episodesId != null) 'episodesId': episodesId,
      },
    );
  }

  /// 根据视频 ID 和剧集 ID 获取当前集信息
  Future<ApiResponse> getEpisodeInfo({
    required String videoId,
    required String episodesId,
  }) {
    return request(
      ApiEndpoints.episodesDirectory,
      data: {'videoId': videoId},
    );
  }

  // ==================== UserCenterModel 个人中心 ====================

  /// 获取个人中心信息
  Future<ApiResponse> getUserCenter() {
    return request(ApiEndpoints.userPersonalCenter, method: 'POST');
  }

  /// 用户追剧列表
  Future<ApiResponse> getUserVideoChasing({int page = 1, int pageSize = 20}) {
    return request(
      ApiEndpoints.userVideoChasing,
      data: {'page': page, 'pageSize': pageSize},
    );
  }

  /// 用户点赞列表
  Future<ApiResponse> getUserVideoLike({int page = 1, int pageSize = 20}) {
    return request(
      ApiEndpoints.userVideoLike,
      data: {'page': page, 'pageSize': pageSize},
    );
  }

  /// 用户观看历史列表
  Future<ApiResponse> getUserViewHistoryList({int page = 1, int pageSize = 20}) {
    return request(
      ApiEndpoints.userViewHistoryList,
      data: {'page': page, 'pageSize': pageSize},
    );
  }

  /// 充值记录列表
  Future<ApiResponse> getRechargeRecordList({int page = 1, int pageSize = 20}) {
    return request(
      ApiEndpoints.rechargeRecordList,
      data: {'page': page, 'pageSize': pageSize},
    );
  }

  /// 消费记录列表
  Future<ApiResponse> getConsumeRecordList({int page = 1, int pageSize = 20}) {
    return request(
      ApiEndpoints.consumeRecordList,
      data: {'page': page, 'pageSize': pageSize},
    );
  }

  /// 赠送记录列表
  Future<ApiResponse> getGiveRecordList({int page = 1, int pageSize = 20}) {
    return request(
      ApiEndpoints.giveRecordList,
      data: {'page': page, 'pageSize': pageSize},
    );
  }

  /// 商品列表
  /// [rechargeGoodsType] 0=VIP 1=K币
  Future<ApiResponse> getRechargeGoodsConfig({int rechargeGoodsType = 0}) {
    return request(
      ApiEndpoints.rechargeGoodsConfig,
      data: {'rechargeGoodsType': rechargeGoodsType},
    );
  }

  /// VIP 页精品推荐
  Future<ApiResponse> getVipHotPicks({int videoHotListType = 2}) {
    return request(
      ApiEndpoints.videoHotPicksList,
      data: {'videoHotListType': videoHotListType},
    );
  }

  /// 开通/充值会员
  /// [payType] 3=抖音 2=微信 5=Android 6=iOS
  Future<ApiResponse> userRechange({
    required int payType,
    int? goodsId,
  }) {
    return request(
      ApiEndpoints.userRechange,
      data: {
        'payType': payType,
        if (goodsId != null) 'goodsId': goodsId,
      },
    );
  }

  /// 查询是否有券
  Future<ApiResponse> queryCoupon() {
    return request(ApiEndpoints.queryCoupon, method: 'GET');
  }

  /// 注销用户
  Future<ApiResponse> cancelAccount() {
    return request(ApiEndpoints.cancelAccount, method: 'POST');
  }

  /// Google 支付回调通知
  Future<ApiResponse> googleCallBack({
    required String purchaseToken,
    required String productId,
    required String orderId,
  }) {
    return request(
      ApiEndpoints.googleCallBack,
      data: {
        'purchaseToken': purchaseToken,
        'productId': productId,
        'orderId': orderId,
      },
    );
  }

  /// 获取签到配置
  Future<ApiResponse> getSignConfig() {
    return request(ApiEndpoints.signConfig, method: 'GET');
  }

  /// 获取用户签到信息
  Future<ApiResponse> getUserSignInfo() {
    return request(ApiEndpoints.userSignInfo, method: 'GET');
  }

  /// 用户签到
  Future<ApiResponse> setUserSign() {
    return request(ApiEndpoints.userSign, method: 'POST');
  }

  // ==================== UpdataModel App 更新 ====================

  /// 检查 App 更新
  /// [deviceType] 0=Android 1=iOS
  /// [resourceVersion] 当前资源版本号
  /// [platformId] 平台 ID，默认 002
  Future<UpdateInfo?> checkUpdate({
    required int deviceType,
    required String resourceVersion,
    String platformId = '002',
  }) async {
    try {
      final token = await _storage.getToken();
      final response = await _dio.post(
        ApiEndpoints.queryVersionInfo,
        data: {
          'deviceType': deviceType,
          'version': resourceVersion,
          'platformId': platformId,
        },
        options: Options(
          headers: {
            'X-Client': _buildXClientHeader(),
            if (token != null && token.isNotEmpty) 'token': token,
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      if (data['code'] == 200 || data['code'] == 0) {
        final appInfo = data['data']?['appVersionInfo'];
        if (appInfo != null) {
          return UpdateInfo.fromJson(appInfo as Map<String, dynamic>);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[ApiService] checkUpdate error: $e');
      return null;
    }
  }

  // ==================== 通用搜索 ====================

  /// 搜索视频
  Future<ApiResponse> searchVideo({
    required String searchName,
    int page = 1,
    int pageSize = 20,
  }) {
    return request(
      ApiEndpoints.searchVideo,
      data: {'searchName': searchName, 'page': page, 'pageSize': pageSize},
    );
  }
}

// ==================== 数据模型 ====================

/// API 响应包装类
class ApiResponse {
  ApiResponse._();

  factory ApiResponse.success(dynamic data) {
    return ApiResponse._().._data = data;
  }

  factory ApiResponse.error(String message, {int? code}) {
    return ApiResponse._()
      .._error = message
      .._code = code;
  }

  factory ApiResponse.expired(String message) {
    return ApiResponse._()
      .._error = message
      .._expired = true;
  }

  dynamic _data;
  String? _error;
  int? _code;
  bool _expired = false;

  bool get isSuccess => _error == null && !_expired;
  bool get isExpired => _expired;
  dynamic get data => _data;
  String? get error => _error;
  int? get code => _code;
}

/// App 更新信息
class UpdateInfo {
  final String version;
  final String resourceVersion;
  final String? downUrl;
  final String? resourceUrl;
  final String? changeLog;
  final bool forceUpdate;

  const UpdateInfo({
    required this.version,
    required this.resourceVersion,
    this.downUrl,
    this.resourceUrl,
    this.changeLog,
    this.forceUpdate = false,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      version: json['version'] as String? ?? '',
      resourceVersion: json['resourceVersion'] as String? ?? '',
      downUrl: json['downUrl'] as String?,
      resourceUrl: json['resourceUrl'] as String?,
      changeLog: json['changeLog'] as String?,
      forceUpdate: json['forceUpdate'] == true || json['forceUpdate'] == 1,
    );
  }
}

/// ApiService 全局单例 Provider
final apiServiceProvider = ApiService();

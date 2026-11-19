import 'dart:convert';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../constants/api_error_code.dart';
import '../constants/app_constants.dart';
import '../model/api_endpoints.dart';
import '../storage/storage_service.dart';
import 'dio_client.dart';
import 'x_client_header.dart';

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

  /// 构造 `X-Client` 请求头。
  ///
  /// 统一走 [XClientHeader] —— 这里原来自己拼了一份，和 `dio_client.dart`
  /// 那份内容不一样（少了 `channel` / `build`）。而 dio_client 的拦截器
  /// 是最后写 `X-Client` 的那个，所以真正发出去的一直是少了两个字段的
  /// 那份。现在两边同源。
  Future<String> _buildXClientHeader() async {
    final savedLang = _storage.getString(AppConstants.deviceLangKey);
    final locale = PlatformDispatcher.instance.locale;
    return XClientHeader.build(savedLang: savedLang, fallbackLocale: locale);
  }

  /// 语言归一化 —— 委托给 [XClientHeader]，避免两处各写一份规则。
  String _normalizeLang(String? value, {Locale? fallbackLocale}) =>
      XClientHeader.normalizeLang(value, fallbackLocale: fallbackLocale);

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
        'X-Client': await _buildXClientHeader(),
        if (token != null && token.isNotEmpty) 'token': token,
        if (clientParams.isNotEmpty) ...{
          'client_params': clientParams,
          'clientparams': clientParams,
        },
      };

      // 请求和响应只记录排查所需的状态，不输出 code 或 token。
      debugPrint('[ApiService] REQUEST[$method] => $url');

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
      debugPrint('[ApiService] RESPONSE[$url] status=${response.statusCode}');

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
        return ApiResponse.error(
          'HTTP ${response.statusCode}',
          code: response.statusCode,
        );
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
      // 把 HTTP 状态码带回去：调用方（如启动时的登录态恢复）需要靠 401
      // 区分「token 已失效」和「网络/服务端临时故障」，否则会被误判成断网，
      // 进而在失效场景下错误地沿用本地缓存的登录态。
      return ApiResponse.error(
        e.message ?? 'Network error',
        code: e.response?.statusCode,
      );
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
  Future<ApiResponse> guestLogin({required String deviceId}) {
    debugPrint('[ApiService] guestLogin called, deviceId=$deviceId');
    return request(
      ApiEndpoints.guestLogin,
      data: {
        'passportType': 0, // 0=游客，1=邮箱，5=Google，6=Apple
        'passportName': deviceId,
      },
    );
  }

  /// Google 登录（统一 userAuthorization 接口）
  Future<ApiResponse> googleLogin({
    required String passportName,
    required String idToken,
    String? accessToken,
    String? email,
    String? displayName,
    String? avatar,
  }) {
    return request(
      ApiEndpoints.googleLogin,
      data: {
        'passportType': PassportType.google,
        'passportName': passportName,
        'idToken': idToken,
        if (accessToken != null && accessToken.isNotEmpty)
          'accessToken': accessToken,
        if (email != null && email.isNotEmpty) 'email': email,
        if (displayName != null && displayName.isNotEmpty)
          'nickName': displayName,
        if (avatar != null && avatar.isNotEmpty) 'userAvatar': avatar,
      },
    );
  }

  /// Facebook 登录（统一 userAuthorization 接口）
  Future<ApiResponse> facebookLogin({
    required String passportName,
    required String accessToken,
    String? email,
    String? displayName,
    String? avatar,
  }) {
    return request(
      ApiEndpoints.googleLogin,
      data: {
        'passportType': PassportType.facebook,
        'passportName': passportName,
        'accessToken': accessToken,
        if (email != null && email.isNotEmpty) 'email': email,
        if (displayName != null && displayName.isNotEmpty)
          'nickName': displayName,
        if (avatar != null && avatar.isNotEmpty) 'userAvatar': avatar,
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
      data: {'passportType': PassportType.wechat, 'code': code},
    );
  }

  /// TikTok 登录
  ///
  /// 后端使用统一的 userAuthorization 接口，passportType=7 走 TikTok 业务分支
  /// （⚠️ 7 这个值待后端最终确认，4 已被 Facebook 占用）。
  /// 后端内部用 client_secret 把 code 换成 TikTok access_token，返回 app token。
  ///
  /// [code] TikTok authorize 返回的 auth code
  /// [redirectUri] 本次请求 code 时实际用的 redirect URI
  ///   —— TikTok 换 token 时要求它与请求 code 时**完全一致**，
  ///      后端拿不到就无从校验，所以必须原样透传。
  /// [invitedCode] 邀请码（可选，后端支持）
  /// [codeVerifier] 启用 PKCE 时必传。
  ///   —— 后端用 code 换 access_token 时要带上它，且必须与生成
  ///      `code_challenge` 时用的字符串逐字节一致，否则 TikTok 返回
  ///      `invalid_grant`。未启用 PKCE 时为 null，后端按非 PKCE 流程处理。
  Future<ApiResponse> tiktokLogin({
    required String code,
    String? redirectUri,
    String? codeVerifier,
    String? invitedCode,
  }) {
    return request(
      ApiEndpoints.tiktokLogin,
      data: {
        'passportType': PassportType.tiktok,
        // 【passportName 必须每用户唯一】
        // 之前这里硬编码成 'TikTok_access_token'，等于所有 TikTok 用户共用
        // 同一个 passportName。后端 `passport_name` 很可能有唯一索引
        // （Google 登录之所以把 idToken 包成 JSON 再塞进 passportName，
        // 就是为了满足这一点），常量值会让第二个用户直接撞约束。
        //
        // TikTok 不返回 openId，授权阶段能拿到的唯一标识就是 auth code，
        // 所以这里传 code。后端换完 token 后自行从 user info 读 openId。
        'passportName': code,
        'code': code,
        if (redirectUri != null && redirectUri.isNotEmpty)
          'redirectUri': redirectUri,
        if (codeVerifier != null && codeVerifier.isNotEmpty)
          'codeVerifier': codeVerifier,
        if (invitedCode != null && invitedCode.isNotEmpty)
          'invitedCode': invitedCode,
      },
    );
  }

  /// 抖音登录
  Future<ApiResponse> douyinLogin({required String code}) {
    return request(
      ApiEndpoints.douyinLogin,
      data: {'passportType': PassportType.douyin, 'code': code},
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
      data: {'email': email, 'passportPassword': passportPassword},
      isForm: false,
    );
  }

  /// 修改昵称
  Future<ApiResponse> updateNickname({required String nickname}) {
    return request(ApiEndpoints.updateNickname, data: {'nickname': nickname});
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
        await _storage.setString(
          AppConstants.deviceLangKey,
          normalizedLanguage,
        );
        await _storage.setString(
          AppConstants.localeKey,
          normalizedLanguage.startsWith('ar') ? 'ar' : 'en',
        );
      }
    }

    return response;
  }

  /// 获取头像列表
  Future<ApiResponse> getAvatarList() {
    return request(
      ApiEndpoints.systemConfigSelect,
      data: {'id': 11},
      method: 'POST',
    );
  }

  /// 获取系统配置内容
  Future<ApiResponse> getSystemConfigContent({required int id}) {
    return request(
      ApiEndpoints.systemConfigSelect,
      data: {'id': id},
      method: 'POST',
    );
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
    return request(ApiEndpoints.searchVideo, data: {'searchName': searchName});
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
    return request(ApiEndpoints.episodesDirectory, data: {'videoId': videoId});
  }

  /// 视频点赞/取消点赞
  /// [type] 1=喜欢 2=取消
  Future<ApiResponse> setVideoLike({
    required String videoId,
    String? episodesId,
    required int type,
  }) {
    return request(
      ApiEndpoints.videoLike,
      data: {
        'videoId': videoId,
        if (episodesId != null && episodesId.isNotEmpty)
          'episodesId': episodesId,
        'type': type,
      },
    );
  }

  /// 视频追剧/取消追剧
  /// [type] 1=追 2=取消
  Future<ApiResponse> setVideoCollect({
    required String videoId,
    String? episodesId,
    required int type,
  }) {
    return request(
      ApiEndpoints.videoCollect,
      data: {
        'videoId': videoId,
        if (episodesId != null && episodesId.isNotEmpty)
          'episodesId': episodesId,
        'type': type,
      },
    );
  }

  /// 视频内获取商品列表（快充）
  Future<ApiResponse> getQuickRechargeList({required String videoId}) {
    return request(ApiEndpoints.quickRechargeList, data: {'videoId': videoId});
  }

  /// 用户购买剧集（解锁）
  Future<ApiResponse> getUserPayEpisodes({
    required String videoId,
    required String episodesId,
    required int episodesNum,
    int? goodsId,
  }) {
    return request(
      ApiEndpoints.userPayEpisodes,
      data: {
        'videoId': videoId,
        'episodesId': episodesId,
        'episodesNum': episodesNum,
        if (goodsId != null && goodsId > 0) 'goodsId': goodsId,
      },
    );
  }

  /// 用户通过 AdMob 激励广告解锁剧集
  Future<ApiResponse> admobUnlockEpisodes({
    required String videoId,
    required int episodesNum,
    required String adUnitId,
  }) {
    return request(
      ApiEndpoints.admobUnlockEpisodes,
      data: {
        'videoId': videoId,
        'episodesNum': episodesNum,
        'adUnitId': adUnitId,
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
    return request(ApiEndpoints.episodesDirectory, data: {'videoId': videoId});
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
  Future<ApiResponse> getUserViewHistoryList({
    int page = 1,
    int pageSize = 20,
  }) {
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

  /// 开通/充值会员/购买整剧
  /// [payType] 3=抖音 2=微信 5=Android 6=iOS
  ///
  /// 【videoId 必须是数字】后端 PayRequestBO.videoId 定义为 int32，
  /// 传字符串会被严格反序列化成 null（订单里 videoId 落库为空，
  /// 整剧解锁就丢了剧信息）。这里统一转成 int 再发。
  Future<ApiResponse> userRechange({
    required int payType,
    int? payConfigId,
    String? videoId,
  }) {
    final body = <String, dynamic>{
      'payType': payType,
      if (payConfigId != null) 'payConfigId': payConfigId,
      if (videoId != null) 'videoId': int.tryParse(videoId) ?? videoId,
    };
    debugPrint('[userRechange] 精确请求体: $body');
    return request(
      ApiEndpoints.userRechange,
      data: body,
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

  /// Google 支付回调通知（`POST /notice/google`）。
  ///
  /// 【请求体格式】
  /// 后端这个接口的 requestBody 在 OpenAPI 里声明为 `type: string`，
  /// 对应 Spring 的 `@RequestBody String params` —— Spring 会把**整个原始
  /// body 文本**交给后端，后端自己再 `JSON.parseObject`。
  ///
  /// 也就是说这里发出去的 JSON 文本本身就要是「购买信息」，
  /// **不能**再套一层 `{"params": "..."}`，否则后端解析出来的对象里只有
  /// 一个 `params` 字段，订单号 / 商品 ID 全是 null。
  ///
  /// 为了兼容后端可能写成「先取 params 字段再 parse 一次」，
  /// 这里同时带上**平铺字段**和一份**同内容的 params 字符串**，
  /// 两种解析方式都能拿到数据（多余的字段后端会忽略）。
  ///
  /// [params] 是购买信息的 Map（orderNo / productId / purchaseToken …）。
  Future<ApiResponse> googleCallBack({required Map<String, dynamic> params}) {
    return request(
      ApiEndpoints.googleCallBack,
      data: <String, dynamic>{...params, 'params': jsonEncode(params)},
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
  Future<ApiResponse> setUserSign({int? signGoodsId}) {
    return request(
      ApiEndpoints.userSign,
      data: {if (signGoodsId != null) 'signGoodsId': signGoodsId},
      method: 'POST',
    );
  }

  /// 游戏轮播图
  Future<ApiResponse> getGameBanner({int position = 0}) {
    return request(
      ApiEndpoints.gameBanner,
      data: {'position': position},
      method: 'GET',
    );
  }

  /// 游戏列表
  Future<ApiResponse> getGameList({
    int? categoryId,
    int? gameType,
    String? moduleType,
    int page = 1,
    int pageSize = 20,
  }) {
    return request(
      ApiEndpoints.gameList,
      data: {
        if (categoryId != null) 'categoryId': categoryId,
        if (gameType != null) 'gameType': gameType,
        if (moduleType != null) 'moduleType': moduleType,
        'page': page,
        'pageSize': pageSize,
      },
      method: 'GET',
    );
  }

  /// 游戏详情
  Future<ApiResponse> getGameDetail({required String id}) {
    return request(
      ApiEndpoints.gameDetail.replaceFirst('{id}', id),
      method: 'GET',
    );
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
            'X-Client': await _buildXClientHeader(),
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

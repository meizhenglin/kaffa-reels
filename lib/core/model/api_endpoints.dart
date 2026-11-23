/// ============================================================================
/// API 接口地址汇总
///
/// 【功能说明】
/// 对应小程序原版 models/api.js，集中管理所有后端接口路径。
/// 所有 API 调用统一引用此处，避免路径散落各处。
///
/// 【如何添加新接口】
/// 1. 在对应分类下添加常量
/// 2. ApiService 中添加对应方法
/// ============================================================================
class ApiEndpoints {
  ApiEndpoints._();

  // ==================== 登录相关 ====================
  static const String login = '/api/user/userAuthorization';
  static const String douyinLogin = '/api/user/userAuthorization';
  static const String weixinLogin = '/api/user/userAuthorization';
  static const String guestLogin = '/api/user/userAuthorization';
  static const String googleLogin = '/api/user/userAuthorization';
  static const String googleIdToken = '/api/user/googleIdToken';
  static const String appleLogin = '/api/user/userAuthorization';

  /// TikTok 登录（与 googleLogin 共用同一接口，仅 passportType 不同）
  static const String tiktokLogin = '/api/user/userAuthorization';
  static const String getSystemConfig = '/api/config/getConfigInfo';

  // ==================== 剧场 Tab ====================
  static const String theaterBanner = '/api/banner/list';
  static const String rankingList = '/api/videoCharts/list';
  static const String videoHotPicks = '/api/videoHotPicks/list';
  static const String lastUserViewHistoryOne =
      '/api/video/lastUserViewHistoryOne';
  static const String userViewHistoryByVideoId = '/api/video/userViewHistory';

  // 搜索
  static const String searchHistory = '/api/videoHotPicks/selectSearch';
  static const String deleteSearchHistory = '/api/videoHotPicks/deleteSearch';
  static const String recommondSearchList =
      '/api/videoHotPicks/recommondSearchList';
  static const String searchVideo = '/api/videoHotPicks/searchVideo';

  // 全部剧集
  static const String videoLabelList = '/api/videoLabel/list';
  static const String videoListByLabel = '/api/videoLabel/videoList';

  // ==================== 推荐 Tab ====================
  static const String recommendIndex = '/api/episodes/recommendIndex';
  static const String playVideo = '/api/episodes/playVideo';
  static const String videoLike = '/api/userVideoLike/like';
  static const String videoCollect = '/api/userVideoChasing/chasing';
  static const String episodesDirectory = '/api/episodes/directory';
  static const String quickRechargeList =
      '/api/rechargeGoodsConfig/quickRechargeList';
  static const String userPayEpisodes = '/api/userPayEpisodes/userPayEpisodes';
  static const String admobUnlockEpisodes =
      '/api/userPayEpisodes/admobUnlockEpisodes';
  static const String userViewAddHistory = '/api/video/userViewAddHistory';
  // static const String episodeInfo = '/api/episodes/getEpisodeInfo';
  static const String directory = '/api/episodes/directory';

  // ==================== 个人中心 ====================
  static const String userPersonalCenter = '/api/user/userPersonalCenter';
  static const String userVideoChasing = '/api/userVideoChasing/list';
  static const String userVideoLike = '/api/userVideoLike/list';
  static const String userViewHistoryList = '/api/video/userViewHistoryList';
  static const String rechargeRecordList = '/api/userAmount/rechargeRecordList';
  static const String consumeRecordList = '/api/userAmount/consumeRecordList';
  static const String giveRecordList = '/api/userAmount/giveRecordList';
  static const String rechargeGoodsConfig = '/api/rechargeGoodsConfig/list';
  static const String videoHotPicksList = '/api/videoHotPicks/list';
  static const String userRechange = '/api/pay/userRechange';
  static const String queryCoupon = '/api/coupon/query';
  static const String cancelAccount = '/api/user/cancelAccount';
  static const String payRechange = '/api/pay/userRechange';

  /// Google 支付结果回调。
  ///
  /// ⚠️ 这里**不是** `/api/pay/callback/google`。
  ///
  /// 后端 OpenAPI（https://tvapi.qahwatv.com/v3/api-docs）里，
  /// 支付结果回调都挂在 `pay-result-controller` 下，operationId 就是
  /// `googleCallBack`，路径是 `/notice/google`：
  ///
  /// ```
  /// /notice/google  (POST, requestBody: application/json, type: string)
  /// ```
  ///
  /// 之前这里写的是 `/api/pay/callback/google`，实测该路径**不存在**：
  ///
  /// ```
  /// POST /api/pay/callback/google  ->  HTTP 404 {"error":"Not Found"}
  /// ```
  ///
  /// 也就是说客户端把购买结果发到了一个 404 地址，后端从来收不到，
  /// 「付了钱会员不到账」就是这么来的。
  static const String googleCallBack = '/notice/google';

  /// Apple 内购结果回调。
  ///
  /// 后端 OpenAPI（pay-result-controller / appleCallBack）：
  /// ```
  /// /notice/apple  (POST, requestBody: application/json, type: string)
  /// ```
  /// iOS 端 App Store 内购的支付结果发这里（和 /notice/google 同构），
  /// 不然「付了钱会员/金币不到账」。
  static const String appleCallBack = '/notice/apple';

  // 签到
  static const String signConfig = '/api/userSign/getSignConfig';
  static const String userSignInfo = '/api/userSign/getSignInfo';
  static const String userSign = '/api/userSign/sign';

  // ==================== 游戏模块 ====================
  static const String gameBanner = '/api/game/banner';
  static const String gameList = '/api/game/list';
  static const String gameDetail = '/api/game/detail/{id}';

  // ==================== App 更新 ====================
  static const String queryVersionInfo =
      '/farmerApi/commons/v1/appVersion/queryVersionInfo';

  // ==================== 设备登录（Flutter 特有） ====================
  /// Flutter 匿名设备登录
  static const String flutterGuestLogin = '/login/getUuid';

  /// 发送邮箱验证码
  static const String sendEmailCode = '/api/user/sendCode';

  /// 校验邮箱验证码
  static const String checkEmailCode = '/api/user/verifyCode';

  /// 注册账号
  static const String register = '/api/user/mailRegister';

  /// 修改昵称
  static const String updateNickname = '/api/user/updateNickname';

  /// 用户设置（修改昵称/头像/语言）
  static const String userSettings = '/api/user/settings';

  /// 系统配置查询（头像列表/协议内容等）
  static const String systemConfigSelect = '/api/systemConfig/selectConfigNew';
}

/// PassportType 登录类型标识
/// 对应小程序中 data.passportType 字段
class PassportType {
  PassportType._();

  /// 游客登录
  static const int guest = 0;

  /// 微信登录
  static const int wechat = 2;

  /// 抖音登录
  static const int douyin = 3;

  /// Facebook 登录
  static const int facebook = 4;

  /// Google 登录
  static const int google = 5;

  /// Apple 登录
  static const int apple = 6;

  /// TikTok 登录
  ///
  /// ⚠️⚠️⚠️ 【待后端确认】⚠️⚠️⚠️
  ///
  /// 原本这里写的是 `4`，但 `4` 已经被 [facebook] 占用了（见上面）。
  /// 两个登录方式用同一个 passportType，后端 `/api/user/userAuthorization`
  /// 根本没法区分 → TikTok 登录会走错分支（或被当成 Facebook）。
  ///
  /// 现在改成 `7`（顺延在 apple=6 之后）。**上线前必须让后端确认**：
  /// - 如果后端确实约定 TikTok 用别的值，改这里的数字即可
  /// - 如果后端已经按 4 实现了 TikTok 分支，那要改的是后端
  ///
  /// 【passportName】传 auth code（每次登录都不同，满足唯一性）
  ///
  /// 早期注释写的是「后端期望值：TikTok access_token」，但 app 只有 code，
  /// 拿不到 access_token（那是后端用 client_secret 换的）。曾一度硬编码成
  /// 常量 `'TikTok_access_token'`，会让所有用户共用同一个 passportName，
  /// 第二个用户就会撞唯一索引。现已改为直接传 code。
  ///
  /// 【invitedCode】后端支持邀请码字段（可选）
  static const int tiktok = 7;
}

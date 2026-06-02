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
  static const String getSystemConfig = '/api/config/getConfigInfo';

  // ==================== 剧场 Tab ====================
  static const String theaterBanner = '/api/banner/list';
  static const String rankingList = '/api/VideoCharts/list';
  static const String videoHotPicks = '/api/videoHotPicks/list';
  static const String lastUserViewHistoryOne = '/api/video/lastUserViewHistoryOne';
  static const String userViewHistoryByVideoId = '/api/video/userViewHistory';

  // 搜索
  static const String searchHistory = '/api/videoHotPicks/selectSearch';
  static const String deleteSearchHistory = '/api/videoHotPicks/deleteSearch';
  static const String recommondSearchList = '/api/videoHotPicks/recommondSearchList';
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
  static const String quickRechargeList = '/api/rechargeGoodsConfig/quickRechargeList';
  static const String userPayEpisodes = '/api/userPayEpisodes/userPayEpisodes';
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
  static const String googleCallBack = '/api/pay/callback/google';

  // 签到
  static const String signConfig = '/api/userSign/getSignConfig';
  static const String userSignInfo = '/api/userSign/getSignInfo';
  static const String userSign = '/api/userSign/sign';

  // ==================== App 更新 ====================
  static const String queryVersionInfo = '/farmerApi/commons/v1/appVersion/queryVersionInfo';

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
  /// 头像列表（系统配置 id=11）
  static const String avatarList = '/api/systemConfig/selectConfig';
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
  /// Google 登录
  static const int google = 5;
  /// Apple 登录
  static const int apple = 6;
}

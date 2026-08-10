import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/commonAliPlayer/short_video_page.dart';
import '../../features/recommend/models/video_info.dart';
import '../../features/auth/pages/forgot_password_page.dart';
import '../../features/auth/pages/login_email_page.dart';
import '../../features/auth/pages/login_page.dart';
import '../../features/auth/pages/register_email_page.dart';
import '../../features/auth/pages/user_agreement_page.dart';
import '../../features/auth/pages/photo_setting_page.dart';
import '../../features/auth/pages/privacy_policy_page.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/explore/pages/explore_tab.dart';
import '../../features/home/pages/home_tab.dart';
import '../../features/home/pages/main_page.dart';
import '../../features/home/models/navigation_item.dart';
import '../../features/payment/pages/membership_page.dart';
import '../../features/payment/pages/recharge_page.dart';
import '../../features/payment/pages/coin_records_list_page.dart';
import '../../features/payment/pages/coin_recharge_page.dart';
import '../../features/payment/pages/recharge_records_page.dart';
import '../../features/payment/pages/consume_records_page.dart';
import '../../features/payment/pages/give_records_page.dart';
import '../../features/payment/pages/sign_page.dart';
import '../../features/profile/pages/profile_tab.dart';
import '../../features/profile/pages/chat_page.dart';
import '../../features/profile/pages/settings_page.dart';
import '../../features/profile/pages/change_name_page.dart';
import '../../features/profile/pages/personal_info_page.dart';
import '../../features/profile/pages/history_page.dart';
import '../../features/profile/pages/favorites_page.dart';
import '../../features/profile/pages/report_page.dart';
import '../../features/games/pages/games_tab.dart';
import '../../features/games/pages/game_detail_page.dart';
import '../../features/recommend/models/drama_list_type.dart';
import '../../features/recommend/pages/recommend_tab.dart';
import '../../features/home/pages/drama_list_page.dart';
import '../../features/search/pages/search_page.dart';

/// ============================================================================
/// 路由配置文件
///
/// 【功能说明】
/// 定义应用中所有的页面路由规则，使用 GoRouter 实现：
/// - 首页、发现、推荐、游戏、我的（底部导航栏 Tab）
/// - 播放器页面
/// - 认证相关页面（登录、注册、忘记密码）
/// - 会员页面
///
/// 【路由结构】
/// /splash              - 启动页（初始页面）
/// /                    - 首页 Tab
/// /explore             - 发现 Tab
/// /recommend           - 推荐 Tab（视频推荐）
/// /recommend/hot       - 热门短剧列表页
/// /recommend/all       - 全部推荐列表页
/// /games               - 游戏 Tab
/// /profile             - 我的 Tab
/// /player              - 视频播放器页面
/// /auth/login          - 登录页
/// /auth/register       - 注册页
/// /auth/forgot-password - 忘记密码页
/// /membership          - 会员订阅页
///
/// 【路由守卫】
/// - 已登录用户访问认证页面会自动重定向到首页
/// - 未登录用户访问需要认证的页面会跳转到登录页
///
/// 【如何修改】
/// - 添加新页面：1) 创建页面文件 2) 在这里添加 GoRoute
/// - 修改路由路径：修改 path 参数
/// - 添加路由参数：在 path 中使用 :paramName 格式
/// ============================================================================

// ==================== 导航键定义 ====================
/// 根导航器键（用于全屏页面，如播放器、登录等）
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// 首页 Tab 导航器键
final shellNavigatorHomeKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellHome');

/// 推荐 Tab 导航器键
final shellNavigatorRecommendKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellRecommend');

/// 发现 Tab 导航器键
final shellNavigatorExploreKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellExplore');

/// 游戏 Tab 导航器键
final shellNavigatorGamesKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellGames');

/// 我的 Tab 导航器键
final shellNavigatorProfileKey =
    GlobalKey<NavigatorState>(debugLabel: 'shellProfile');

/// ============================================================================
/// 路由刷新通知器
///
/// 【功能】
/// 监听认证状态变化，当用户登录/登出时自动触发路由重定向检查
///
/// 【工作原理】
/// 实现了 ChangeNotifier，当 authProvider 状态变化时会通知 GoRouter
/// GoRouter 会重新执行 redirect 逻辑来决定是否需要重定向
/// ============================================================================
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(this._ref) {
    // 监听 authProvider，当认证状态变化时通知监听器。
    // 延后到微任务里通知，避免在 widget tree 正在构建时同步触发 GoRouter 刷新。
    _ref.listen(authProvider, (_, __) {
      Future.microtask(() {
        if (hasListeners) {
          notifyListeners();
        }
      });
    });
  }

  final Ref _ref;
}

// Web: 移除 URL hash，使用 path 模式
void _configureRouterUrlStrategy() {
}

// ==================== 路由 Provider ====================
/// 路由配置 Provider
///
/// 【功能】创建并提供 GoRouter 实例
///
/// 【参数说明】
/// - initialLocation：初始路由为启动页
/// - refreshListenable：监听认证状态变化
/// - redirect：路由守卫逻辑
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier(ref);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    // 初始页面直接跳转到首页
    initialLocation: '/',
    // 监听状态变化，自动刷新路由
    refreshListenable: refreshNotifier,

    /// 路由守卫：每次路由变化时都会执行
    redirect: (context, state) {
      // 目前不执行任何重定向。已登录用户访问 auth 页是正常行为。
      return null;
    },

    /// 路由列表
    routes: [
      // ==================== 底部导航 Tab 路由 ====================
      /// StatefulShellRoute 实现带底部导航栏的页面结构
      /// 【功能】支持 5 个 Tab，每个 Tab 都有自己的 Navigator
      /// 【效果】Tab 切换时子页面不会销毁，可以保持状态
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          // MainPage 负责渲染底部导航栏和当前 Tab 页面
          return MainPage(navigationShell: navigationShell);
        },
        branches: [
          // ----- 首页 Tab -----
          StatefulShellBranch(
            navigatorKey: shellNavigatorHomeKey,
            routes: [
              GoRoute(
                path: '/',
                name: 'home',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: HomeTab(),
                ),
              ),
            ],
          ),

          // ----- 发现 Tab -----
          StatefulShellBranch(
            navigatorKey: shellNavigatorExploreKey,
            routes: [
              GoRoute(
                path: '/explore',
                name: 'explore',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ExploreTab(),
                ),
              ),
            ],
          ),

          // ----- 推荐 Tab -----
          StatefulShellBranch(
            navigatorKey: shellNavigatorRecommendKey,
            routes: [
              GoRoute(
                path: '/recommend',
                name: 'recommend',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: const RecommendTab(),
                ),
                // 推荐子页面：热门/全部列表
                routes: [
                  /// 热门短剧列表页
                  /// 【路径】/recommend/hot
                  /// 【传入参数】DramaListType.topRecommend
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'hot',
                    name: 'recommend-hot',
                    builder: (context, state) => const DramaListPage(
                      type: DramaListType.topRecommend,
                    ),
                  ),

                  /// New For This Month 列表页
                  /// 【路径】/recommend/new
                  /// 【传入参数】DramaListType.newForThisMonth
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'new',
                    name: 'recommend-new',
                    builder: (context, state) => const DramaListPage(
                      type: DramaListType.newForThisMonth,
                    ),
                  ),

                  /// VIP Zone 列表页
                  /// 【路径】/recommend/vip
                  /// 【传入参数】DramaListType.vipZone
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'vip',
                    name: 'recommend-vip',
                    builder: (context, state) => const DramaListPage(
                      type: DramaListType.vipZone,
                    ),
                  ),

                  /// 全部推荐列表页
                  /// 【路径】/recommend/all
                  /// 【传入参数】DramaListType.recommended
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'all',
                    name: 'recommend-all',
                    builder: (context, state) => const DramaListPage(
                      type: DramaListType.recommended,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ----- 游戏 Tab -----
          StatefulShellBranch(
            navigatorKey: shellNavigatorGamesKey,
            routes: [
              GoRoute(
                path: '/games',
                name: 'games',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: GamesTab(),
                ),
                routes: [
                  /// 游戏详情页
                  /// 【路径】/games/detail/:gameId
                  /// 【参数】
                  /// - gameId: 游戏ID（路径参数）
                  /// - extra: 可选，{'gameName': 游戏名称}
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'detail/:id',
                    name: 'game-detail',
                    builder: (context, state) {
                      final id = state.pathParameters['id'] ?? '';
                      final extra = state.extra as Map<String, dynamic>?;
                      final gameName = extra?['gameName'] as String?;
                      return GameDetailPage(
                        id: id,
                        gameName: gameName,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          // ----- 我的 Tab -----
          StatefulShellBranch(
            navigatorKey: shellNavigatorProfileKey,
            routes: [
              GoRoute(
                path: '/profile',
                name: 'profile',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ProfileTab(),
                ),
                routes: [
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'notifications',
                    name: 'profile-notifications',
                    builder: (context, state) => const ChatPage(),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'settings',
                    name: 'profile-settings',
                    builder: (context, state) => const SettingsPage(),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'favorites',
                    name: 'profile-favorites',
                    builder: (context, state) => const FavoritesPage(),
                  ),
                  GoRoute(
                    parentNavigatorKey: rootNavigatorKey,
                    path: 'report',
                    name: 'profile-report',
                    builder: (context, state) => const ReportPage(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),

      // ==================== 全屏页面路由 ====================

      /// Photo Setting 页面（root 路由，pop 返回正确）
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/auth/photo-setting',
        name: 'photo-setting',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is RegistrationFlowContext) {
            return PhotoSettingPage(
              fromRegister: extra.fromRegister,
              registrationContext: extra,
            );
          }
          return PhotoSettingPage(
            fromRegister: extra as bool? ?? false,
          );
        },
      ),

      /// 改名页面（root 路由，pop 返回正确）
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/change-name',
        name: 'change-name',
        builder: (context, state) {
          final extra = state.extra;
          if (extra is RegistrationFlowContext) {
            return ChangeNamePage(
              fromRegister: extra.fromRegister,
              registrationContext: extra,
            );
          }
          return ChangeNamePage(
            fromRegister: extra as bool? ?? false,
          );
        },
      ),

      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/personal-info',
        name: 'personal-info',
        builder: (context, state) => const PersonalInfoPage(),
      ),

      /// 搜索页面
      /// 【路径】/search
      /// 【参数】
      /// - q：初始搜索词（可选）
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/search',
        name: 'search',
        builder: (context, state) {
          final initialQuery = state.uri.queryParameters['q'];
          return SearchPage(initialQuery: initialQuery);
        },
      ),

      /// 阿里云沉浸式播放器
      /// 【路径】/short-video
      /// 【参数】
      /// - videoId（extra）：视频 ID，播放器自己请求 directory + playVideo
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/short-video',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          // 支持 query 参数 videoId 和 initialIndex
          final videoId = extra?['videoId'] as String? ??
              state.uri.queryParameters['videoId'] ?? '';
          final initialIndex = extra?['initialIndex'] as int? ??
              int.tryParse(state.uri.queryParameters['initialIndex'] ?? '') ?? 0;
          final seedVideoJson = extra?['seedVideo'] as Map<String, dynamic>?;
          final seedVideo = seedVideoJson == null
              ? null
              : VideoInfo.fromJson(seedVideoJson);

          debugPrint('[router] /short-video videoId=$videoId initialIndex=$initialIndex uri=${state.uri}');
          return ShortVideoPage(
            videoId: videoId,
            initialIndex: initialIndex,
            seedVideo: seedVideo,
          );
        },
      ),

      /// 登录页面
      /// 【路径】/auth/login
      /// 【参数】
      /// - redirect：登录成功后重定向的路径（可选）
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/auth/login',
        name: 'login',
        builder: (context, state) {
          final redirect = state.uri.queryParameters['redirect'];
          final backTarget = state.uri.queryParameters['back'] ?? '/';
          return LoginPage(redirect: redirect, backTarget: backTarget);
        },
        routes: [
          /// 邮箱登录页面
          /// 【路径】/auth/login/email
          GoRoute(
            parentNavigatorKey: rootNavigatorKey,
            path: 'email',
            name: 'loginEmail',
            builder: (context, state) {
              final redirect = state.uri.queryParameters['redirect'] ?? (state.extra as String?);
              return LoginEmailPage(redirect: redirect);
            },
          ),
        ],
      ),

      /// 注册页面
      /// 【路径】/auth/register
      /// 【使用场景】统一注册入口
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/auth/register',
        name: 'register',
        builder: (context, state) {
          final backTarget = state.uri.queryParameters['back'] ?? '/auth/login';
          return RegisterEmailPage(backTarget: backTarget);
        },
      ),

      /// 邮箱注册页面
      /// 【路径】/auth/register/email
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/auth/register/email',
        name: 'registerEmail',
        builder: (context, state) {
          final backTarget = state.uri.queryParameters['back'] ?? '/auth/login/email';
          return RegisterEmailPage(backTarget: backTarget);
        },
      ),

      /// 用户协议页面
      /// 【路径】/auth/user-agreement
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/auth/user-agreement',
        name: 'user-agreement',
        builder: (context, state) => const UserAgreementPage(),
      ),

      /// 隐私政策页面
      /// 【路径】/auth/privacy-policy
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/auth/privacy-policy',
        name: 'privacy-policy',
        builder: (context, state) => const PrivacyPolicyPage(),
      ),

      /// 忘记密码页面
      /// 【路径】/auth/forgot-password
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/auth/forgot-password',
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordPage(),
      ),

      /// 会员订阅页面
      /// 【路径】/membership
      /// 【功能】显示 VIP 会员订阅计划和权益
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/membership',
        name: 'membership',
        builder: (context, state) {
          final backTarget = state.uri.queryParameters['back'];
          return MembershipPage(backTarget: backTarget);
        },
      ),

      /// K币充值页面
      /// 【路径】/recharge
      /// 【功能】显示充值套餐列表
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/recharge',
        name: 'recharge',
        builder: (context, state) => const RechargePage(),
      ),

      /// 观看历史页面
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/history',
        name: 'history',
        builder: (context, state) => const HistoryPage(),
      ),

      /// K币记录列表页面
      /// 【路径】/coin-records
      /// 【功能】显示充值/消费/赠送三个选项
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/coin-records',
        name: 'coin-records',
        builder: (context, state) => const CoinRecordsListPage(),
      ),

      /// K币充值商品列表页面
      /// 【路径】/coin-recharge
      /// 【功能】显示K币充值套餐
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/coin-recharge',
        name: 'coin-recharge',
        builder: (context, state) => const CoinRechargePage(),
      ),

      /// K币充值记录页面
      /// 【路径】/coin-records/recharge
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/coin-records/recharge',
        name: 'coin-records-recharge',
        builder: (context, state) => const RechargeRecordsPage(),
      ),

      /// K币消费记录页面
      /// 【路径】/coin-records/consume
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/coin-records/consume',
        name: 'coin-records-consume',
        builder: (context, state) => const ConsumeRecordsPage(),
      ),

      /// K币赠送记录页面
      /// 【路径】/coin-records/give
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/coin-records/give',
        name: 'coin-records-give',
        builder: (context, state) => const GiveRecordsPage(),
      ),

      /// 签到页面
      /// 【路径】/sign
      /// 【功能】显示签到配置和用户签到信息
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/sign',
        name: 'sign',
        builder: (context, state) => const SignPage(),
      ),
    ],

    /// 路由错误处理
    /// 【功能】当路由不存在时显示错误页面
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text(state.error?.toString() ?? 'Page not found'),
      ),
    ),
  );
});
///
/// 【功能】提供便捷的方法跳转到指定 Tab
///
/// 【使用示例】
/// context.go('/games'); // 跳转到游戏 Tab
/// ============================================================================
extension GoRouterTabExtension on GoRouter {
  /// 跳转到指定 Tab
  /// [path] 目标 Tab 的路径（如 '/games'）
  void goToTab(String path) {
    final index = NavigationConfig.indexForPath(path);
    go(NavigationConfig.branchPaths[index]);
  }
}

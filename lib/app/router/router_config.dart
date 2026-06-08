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
import '../../features/profile/pages/profile_tab.dart';
import '../../features/profile/pages/settings_page.dart';
import '../../features/profile/pages/change_name_page.dart';
import '../../features/profile/pages/personal_info_page.dart';
import '../../features/profile/pages/history_page.dart';
import '../../features/profile/pages/favorites_page.dart';
import '../../features/profile/pages/about_page.dart';
import '../../features/recommend/models/drama_list_type.dart';
import '../../features/recommend/pages/recommend_tab.dart';
import '../../features/home/pages/drama_list_page.dart';
import '../../features/search/pages/search_page.dart';
import '../../features/splash/pages/splash_page.dart';

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

/// 需要登录才能访问的认证相关路由
/// 【作用】当用户已登录时，访问这些路由会自动重定向到首页
/// 【修改提示】如果添加新的认证页面，需要在这里添加路径
const _authRoutes = ['/auth/login', '/auth/register', '/auth/forgot-password'];

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
    // 监听 authProvider，当认证状态变化时通知监听器
    _ref.listen(authProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;
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
    // 初始页面为启动页
    initialLocation: '/splash',
    // 监听状态变化，自动刷新路由
    refreshListenable: refreshNotifier,

    /// 路由守卫：每次路由变化时都会执行
    ///
    /// 【原则】Storage 有 token → status=authenticated → 视为已登录
    /// 只要 status=authenticated，访问 /auth/* 页面就重定向到首页
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      final location = state.matchedLocation;
      final isAuthRoute = _authRoutes.any(location.startsWith);
      final isFullyLoggedIn = auth.status == AuthStatus.authenticated &&
          auth.user != null &&
          !auth.user!.isTourist;

      // 只有真正已登录的非游客用户，访问登录/注册页时才重定向到首页
      if (isAuthRoute && isFullyLoggedIn) {
        return '/';
      }

      return null;
    },

    /// 路由列表
    routes: [
      // ==================== 启动页 ====================
      /// 启动页路由
      /// 【路径】/splash
      /// 【功能】显示启动动画，初始化应用，然后跳转到首页
      GoRoute(
        path: '/splash',
        name: 'splash',
        pageBuilder: (context, state) => const MaterialPage(
          child: SplashPage(),
        ),
      ),

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
                    path: 'about',
                    name: 'profile-about',
                    builder: (context, state) => const AboutPage(),
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
        builder: (context, state) => PhotoSettingPage(
          fromRegister: state.extra as bool? ?? false,
        ),
      ),

      /// 改名页面（root 路由，pop 返回正确）
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/change-name',
        name: 'change-name',
        builder: (context, state) => ChangeNamePage(
          fromRegister: state.extra as bool? ?? false,
        ),
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
          final videoId = extra?['videoId'] as String? ?? '';
          final initialIndex = extra?['initialIndex'] as int? ?? 0;
          final seedVideoJson = extra?['seedVideo'] as Map<String, dynamic>?;
          final seedVideo = seedVideoJson == null
              ? null
              : VideoInfo.fromJson(seedVideoJson);

          debugPrint('[router] /short-video videoId=$videoId initialIndex=$initialIndex');
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
          return LoginPage(redirect: redirect);
        },
        routes: [
          /// 邮箱登录页面
          /// 【路径】/auth/login/email
          GoRoute(
            parentNavigatorKey: rootNavigatorKey,
            path: 'email',
            name: 'loginEmail',
            builder: (context, state) {
              final redirect = state.extra as String?;
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
        builder: (context, state) => const RegisterEmailPage(),
      ),

      /// 邮箱注册页面
      /// 【路径】/auth/register/email
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/auth/register/email',
        name: 'registerEmail',
        builder: (context, state) => const RegisterEmailPage(),
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
        builder: (context, state) => const MembershipPage(),
      ),

      /// 观看历史页面
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/history',
        name: 'history',
        builder: (context, state) => const HistoryPage(),
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

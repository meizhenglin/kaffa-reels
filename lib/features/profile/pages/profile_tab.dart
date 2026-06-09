import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/preload_network_image.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/providers/auth_provider.dart' show apiServiceProviderRef;
import '../../home/pages/main_page.dart' show currentTabIndexProvider;
import '../../auth/providers/auth_provider.dart'
    show AuthState, AuthStatus, authProvider, authServiceProvider;
import 'chat_page.dart';

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> with WidgetsBindingObserver {
  ProviderSubscription<AuthState>? _authStateSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    ref.listenManual<int>(currentTabIndexProvider, (previous, next) {
      if (next == 4) {
        Future.microtask(_loadUserInfo);
      }
    });

    // 监听认证状态从游客切到正式登录的瞬间，立即刷新 Profile 资料。
    // 否则页面如果没有发生路由重建，只靠 didChangeDependencies 不一定能及时拉到邮箱用户信息。
    _authStateSubscription = ref.listenManual<AuthState>(
      authProvider,
      (previous, next) {
        final previousUser = previous?.user;
        final nextUser = next.user;
        final switchedFromGuestToLoggedIn =
            previousUser != null &&
            previousUser.isTourist &&
            nextUser != null &&
            !nextUser.isTourist;
        final switchedFromNoUserToLoggedIn =
            previousUser == null &&
            nextUser != null &&
            !nextUser.isTourist;

        if (switchedFromGuestToLoggedIn || switchedFromNoUserToLoggedIn) {
          Future.microtask(_loadUserInfo);
        }
      },
    );
  }

  @override
  void dispose() {
    _authStateSubscription?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 每次依赖变化时（如从其他 tab 切换回来）重新加载用户信息
    Future.microtask(_loadUserInfo);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 从后台切回前台时也刷新
      Future.microtask(_loadUserInfo);
    }
  }

  Future<void> _loadUserInfo() async {
    final authState = ref.read(authProvider);
    final currentUser = authState.user;
    debugPrint(
      '[ProfileTab._loadUserInfo] '
      'status=${authState.status} '
      'isTourist=${currentUser?.isTourist} '
      'user=${currentUser?.toJson()}',
    );
    if (authState.status == AuthStatus.unauthenticated || currentUser == null) {
      debugPrint('[ProfileTab._loadUserInfo] skip refresh for missing user/unauthenticated');
      return;
    }

    try {
      final resp = await ref.read(apiServiceProviderRef).getUserCenter();
      if (resp.isSuccess && resp.data != null && mounted) {
        final userData = resp.data as Map<String, dynamic>;
        debugPrint('[ProfileTab._loadUserInfo] getUserCenter success: $userData');
        ref.read(authProvider.notifier).updateUserFromData(userData);
        return;
      }
      debugPrint('[ProfileTab._loadUserInfo] getUserCenter failed: success=${resp.isSuccess} data=${resp.data}');
    } catch (e) {
      debugPrint('[ProfileTab._loadUserInfo] getUserCenter error: $e');
    }

    // 网络失败时降级读取 Storage 缓存（仅正式登录用户）
    if (mounted) {
      final authService = ref.read(authServiceProvider);
      final userData = await authService.getUserData();
      debugPrint('[ProfileTab._loadUserInfo] fallback storage userData=$userData');
      if (userData != null && mounted) {
        ref.read(authProvider.notifier).updateUserFromData(userData);
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ChatPage(),
                        ),
                      );
                    },
                    icon: Image.asset(
                      'assets/images/notification.png',
                      width: 24,
                      height: 24,
                      color: Colors.white70,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      context.push('/profile/settings');
                    },
                    icon: Image.asset(
                      'assets/images/setting.png',
                      width: 26,
                      height: 26,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Column(
                  children: [
                    _buildUserSection(context),
                    const SizedBox(height: 27),
                    _buildVipBanner(context),
                    const SizedBox(height: 25),
                    _buildFunctionIcons(context),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserSection(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    final user = auth.user;
    debugPrint(
      '[ProfileTab.buildUserSection] '
      'status=${auth.status} '
      'isTourist=${user?.isTourist} '
      'user=${user?.toJson()}',
    );

    final avatarUrl = user?.photoURL ?? user?.avatar;
    final isLoggedIn = user != null && !user.isTourist;
    final shouldShowLoginButton = user == null || user.isTourist;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      textDirection: Directionality.of(context),
      children: [
        // 头像区域
        GestureDetector(
          onTap: () => _pickAvatar(context),
          child: Container(
            width: 73,
            height: 73,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(50),
              border: Border.all(color: const Color(0xFFFFFFFF), width: 1),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(50),
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? PreloadNetworkImage(
                      imageUrl: avatarUrl,
                      preloadAsset: 'assets/images/small_preload_bg.png',
                      width: 73,
                      height: 73,
                      fit: BoxFit.cover,
                    )
                  : _buildAvatarPlaceholder(),
            ),
          ),
        ),
        const SizedBox(width: 13),
        // 昵称 + ID / 登录提示
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.userNickname ?? 'Guest',
                style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (isLoggedIn)
                Container(
                  height: 18,
                  padding: const EdgeInsetsDirectional.only(end: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x26FFFFFF),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/id_bg.png', width: 20, height: 18),
                      const SizedBox(width: 4),
                      Text(user.id,
                          style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13, color: Color(0xFFFFFFFF))),
                    ],
                  ),
                )
              else
                Text(
                  l10n.loginSubtitle,
                  style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 13),
                ),
            ],
          ),
        ),
        // 最右侧：游客显示登录按钮，邮箱账号显示右箭头
        if (!shouldShowLoginButton)
          GestureDetector(
            onTap: () => _goToPersonalInfo(context),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..scale(Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0, 1.0),
              child: Image.asset('assets/images/to.png', width: 20, height: 20),
            ),
          )
        else
          GestureDetector(
            onTap: () => context.push('/auth/login?redirect=/profile'),
            child: Container(
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                l10n.login_button,
                style: const TextStyle(color: Color(0xFF8F4EFF), fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _pickAvatar(BuildContext context) async {
    final auth = ref.read(authProvider);
    if (auth.user == null || auth.user!.isTourist) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).profileLoginFirst),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    context.push('/auth/photo-setting');
  }

  Future<void> _goToPersonalInfo(BuildContext context) async {
    final auth = ref.read(authProvider);
    if (auth.user == null || auth.user!.isTourist) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).profileLoginFirst),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    context.push('/personal-info');
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      width: 73,
      height: 73,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        border: Border.all(
          color: const Color(0xFFFFFFFF),
          width: 1,
        ),
        color: Colors.grey[800],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.person, size: 40, color: Colors.white54),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _buildVipBanner(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.user;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: const DecorationImage(
          image: AssetImage('assets/images/vip_bg.png'),
          // fit: BoxFit.cover,
        ),
      ),
      child: Row(
        children: [
          // Container(
          //   width: 48,
          //   height: 48,
          //   decoration: BoxDecoration(
          //     color: Colors.white.withValues(alpha: 0.15),
          //     shape: BoxShape.circle,
          //   ),
          //   child: const Icon(
          //     Icons.workspace_premium,
          //     color: Color(0xFFFFB800),
          //     size: 28,
          //   ),
          // ),
          const SizedBox(width: 56),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context).vipMember,
                  style: const TextStyle(
                    color: Color(0xFF3A1D00),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user != null && !user.isTourist
                      ? 'Validity Period：${_formatDate(user.membershipExpiryDate)}'
                      : AppLocalizations.of(context).vipSubtitle,
                  style: const TextStyle(color: Color(0xFF3A1D00), fontSize: 12),
                ),
              ],
            ),
          ),
          if (user == null || user.isTourist)
            GestureDetector(
              onTap: () {
                final messenger = ScaffoldMessenger.of(context);
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      AppLocalizations.of(context).loginSubtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black),
                    ),
                    backgroundColor: const Color(0xFFFFFFFF),
                    duration: const Duration(seconds: 2),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(31),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/activate_bg.png'),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context).activate,
                  style: const TextStyle(
                    color: Color(0xFFFFEDC6),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else
            GestureDetector(
              onTap: () => context.push('/membership'),
              child: Container(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(31),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/activate_bg.png'),
                  ),
                ),
                child: const Text(
                  'Renewal',
                  style: TextStyle(
                    color: Color(0xFFFFEDC6),
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openComplaintAndReport() {
    context.push('/profile/report');
  }

  Widget _buildFunctionIcons(BuildContext context) {
    return Row(
      textDirection: Directionality.of(context),
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildIconButton(
          context,
          imagePath: 'assets/images/history.png',
          label: 'Watching History',
          onTap: () => context.push('/history'),
        ),
        _buildIconButton(
          context,
          imagePath: 'assets/images/favourites.png',
          label: 'Favourites',
          onTap: () => context.push('/profile/favorites'),
        ),
        _buildIconButton(
          context,
          imagePath: 'assets/images/report.png',
          label: 'Complaint and Report',
          onTap: _openComplaintAndReport,
        ),
      ],
    );
  }

  Widget _buildIconButton(
    BuildContext context, {
    required String imagePath,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Image.asset(imagePath, width: 44, height: 44),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

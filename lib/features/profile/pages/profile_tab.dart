import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_snack_bar.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/preload_network_image.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/providers/auth_provider.dart' show apiServiceProviderRef;
import '../../home/pages/main_page.dart' show currentTabIndexProvider;
import '../../auth/providers/auth_provider.dart'
    show AuthState, AuthStatus, authProvider;
import '../../recommend/utils/drama_navigation.dart';
import '../../payment/widgets/sign_and_coin_module.dart';
import '../../payment/providers/membership_provider.dart' show isVipProvider;
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

    // 监听 VIP 状态变化，变化时刷新用户信息
    ref.listenManual<bool>(isVipProvider, (previous, next) {
      if (previous != next) {
        debugPrint('[ProfileTab] VIP status changed: $previous -> $next, refreshing user info');
        Future.microtask(_loadUserInfo);
      }
    });
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

    final isTourist = currentUser.isTourist;

    debugPrint(
      '[ProfileTab._loadUserInfo] requesting user center '
      'status=${authState.status} '
      'isTourist=$isTourist '
      'id=${currentUser.id}',
    );

    try {
      final resp = await ref.read(apiServiceProviderRef).getUserCenter();
      if (resp.isSuccess && resp.data != null && mounted) {
        final userData = resp.data as Map<String, dynamic>;
        debugPrint('[ProfileTab._loadUserInfo] getUserCenter success: $userData');
        ref.read(authProvider.notifier).updateUserFromData(userData);
        return;
      }
      debugPrint(
        '[ProfileTab._loadUserInfo] getUserCenter failed: '
        'success=${resp.isSuccess} data=${resp.data} isTourist=$isTourist',
      );
    } catch (e) {
      debugPrint('[ProfileTab._loadUserInfo] getUserCenter error: $e isTourist=$isTourist');
    }
  }
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                      context.push('/profile/notifications');
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
                    const SignAndCoinModule(),
                    const SizedBox(height: 25),
                    _buildFunctionIcons(context, l10n),
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
                user?.userNickname ?? l10n.login,
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
            onTap: () => context.push('/auth/login?redirect=/profile&back=/profile'),
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
      AppSnackBar.show(context, message: AppLocalizations.of(context).profileLoginFirst);
      return;
    }
    context.push('/auth/photo-setting');
  }

  Future<void> _goToPersonalInfo(BuildContext context) async {
    final auth = ref.read(authProvider);
    if (auth.user == null || auth.user!.isTourist) {
      AppSnackBar.show(context, message: AppLocalizations.of(context).profileLoginFirst);
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
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    final user = auth.user;
    final isLoggedIn = user != null && !user.isTourist;
    final isVip = user != null && user.membershipExpiryDate != null && !user.isTourist && DateTime.now().isBefore(user.membershipExpiryDate!);

    // Web 端：文字居中，按钮在最右边
    if (kIsWeb) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          image: const DecorationImage(
            image: AssetImage('assets/images/vip_bg.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.vipMember,
                      style: const TextStyle(
                        color: Color(0xFF3A1D00),
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isVip
                          ? l10n.validityPeriod(_formatDate(ref.read(authProvider).user?.membershipExpiryDate))
                          : l10n.vipSubtitle,
                      style: const TextStyle(color: Color(0xFF3A1D00), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            if (!isLoggedIn)
              _buildLoginButton(l10n)
            else
              _buildActivateButton(context, l10n, isVip),
          ],
        ),
      );
    }

    // 手机端：contain + 固定高度保证皇冠位置一致
    return Container(
      width: double.infinity,
      height: 100,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: const DecorationImage(
          image: AssetImage('assets/images/vip_bg.png'),
          fit: BoxFit.contain,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 56),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.vipMember,
                  style: const TextStyle(
                    color: Color(0xFF3A1D00),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isVip
                      ? l10n.validityPeriod(_formatDate(ref.read(authProvider).user?.membershipExpiryDate))
                      : l10n.vipSubtitle,
                  style: const TextStyle(color: Color(0xFF3A1D00), fontSize: 12),
                ),
              ],
            ),
          ),
          if (!isLoggedIn)
            _buildLoginButton(l10n)
          else
            _buildActivateButton(context, l10n, isVip),
        ],
      ),
    );
  }

  Widget _buildLoginButton(AppLocalizations l10n) {
    return GestureDetector(
      onTap: () {
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.loginSubtitle,
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
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(31),
          image: const DecorationImage(
            image: AssetImage('assets/images/activate_bg.png'),
          ),
        ),
        child: Text(
          l10n.activate,
          style: const TextStyle(
            color: Color(0xFFFFEDC6),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildActivateButton(BuildContext context, AppLocalizations l10n, bool isVip) {
    return GestureDetector(
      onTap: () => openMembershipPage(context, ref),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsetsDirectional.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(31),
          image: const DecorationImage(
            image: AssetImage('assets/images/activate_bg.png'),
          ),
        ),
        child: Text(
          isVip ? l10n.renewal : l10n.activate,
          style: const TextStyle(
            color: Color(0xFFFFEDC6),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _openComplaintAndReport() {
    context.push('/profile/report');
  }

  Widget _buildFunctionIcons(BuildContext context, AppLocalizations l10n) {
    return Column(
      children: [
        Row(
          textDirection: Directionality.of(context),
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildIconButton(
              context,
              imagePath: 'assets/images/history.png',
              label: l10n.watchHistory,
              onTap: () => context.push('/history'),
            ),
            _buildIconButton(
              context,
              imagePath: 'assets/images/favourites.png',
              label: l10n.favourites,
              onTap: () => context.push('/profile/favorites'),
            ),
            _buildIconButton(
              context,
              imagePath: 'assets/images/recharge_icon.png',
              label: l10n.rechargeRecords,
              onTap: () => context.push('/coin-records/recharge'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          textDirection: Directionality.of(context),
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildIconButton(
              context,
              imagePath: 'assets/images/usege_icon.png',
              label: l10n.usageRecords,
              onTap: () => context.push('/coin-records/consume'),
            ),
            _buildIconButton(
              context,
              imagePath: 'assets/images/gift_icon.png',
              label: l10n.giftRecords,
              onTap: () => context.push('/coin-records/give'),
            ),
            _buildIconButton(
              context,
              imagePath: 'assets/images/report.png',
              label: l10n.complaintAndReport,
              onTap: _openComplaintAndReport,
            ),
          ],
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
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          height: 70,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(imagePath, width: 44, height: 44),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

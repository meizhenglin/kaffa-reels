import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart' show authProvider, AuthStatus, authServiceProvider;
import 'chat_page.dart';
import 'settings_page.dart';

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});

  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
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
    if (authState.status == AuthStatus.unauthenticated) return;

    try {
      final resp = await apiServiceProvider.getUserCenter();
      if (resp.isSuccess && resp.data != null && mounted) {
        final userData = resp.data as Map<String, dynamic>;
        ref.read(authProvider.notifier).updateUserFromData(userData);
        return;
      }
    } catch (_) {}

    // 网络失败时降级读取 Storage 缓存
    if (mounted) {
      final authService = ref.read(authServiceProvider);
      final userData = await authService.getUserData();
      if (userData != null && mounted) {
        ref.read(authProvider.notifier).updateUserFromData(userData);
      }
    }
  }
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
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
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SettingsPage(),
                        ),
                      );
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
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

    final avatarUrl = user?.photoURL ?? user?.avatar;
    final isLoggedIn = user != null && !user.isTourist;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
                  ? Image.network(avatarUrl, width: 73, height: 73, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildAvatarPlaceholder())
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
              GestureDetector(
                onTap: () => _goToChangeName(context),
                child: Text(
                  user?.userNickname ?? 'Guest',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 8),
              if (isLoggedIn)
                Container(
                  height: 18,
                  padding: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x26FFFFFF),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/id_bg.png', width: 20, height: 18),
                      const SizedBox(width: 4),
                      Text(user?.id ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 13, color: Color(0xFFFFFFFF))),
                    ],
                  ),
                )
              else
                Text(
                  l10n?.loginSubtitle ?? 'Login to unlock more features',
                  style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 13),
                ),
            ],
          ),
        ),
        // 最右侧：登录按钮 或 箭头
        if (isLoggedIn)
          Image.asset('assets/images/to.png', width: 20, height: 20)
        else
          GestureDetector(
            onTap: () => context.push('/auth/login?redirect=/profile'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFFFF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                l10n?.login_button ?? 'Log in',
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
        const SnackBar(
          content: Text('Please log in first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    context.push('/auth/photo-setting');
  }

  Future<void> _goToChangeName(BuildContext context) async {
    final auth = ref.read(authProvider);
    if (auth.user == null || auth.user!.isTourist) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    context.push('/change-name');
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
                  AppLocalizations.of(context)?.vipMember ?? 'VIP Member',
                  style: const TextStyle(
                    color: Color(0xFF3A1D00),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user == null || !user.isTourist
                      ? 'Validity Period：${_formatDate(user?.membershipExpiryDate)}'
                      : (AppLocalizations.of(context)?.vipSubtitle ??
                          'Unlock all series with one tap'),
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
                      AppLocalizations.of(context)?.loginSubtitle ?? 'Login to unlock more features',
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
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(31),
                  image: const DecorationImage(
                    image: AssetImage('assets/images/activate_bg.png'),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context)?.activate ?? 'Activate',
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
              onTap: () => context.go('/membership'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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

  Widget _buildFunctionIcons(BuildContext context) {
    return Row(
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
          onTap: () => context.push('/favorites'),
        ),
        _buildIconButton(
          context,
          imagePath: 'assets/images/report.png',
          label: 'Complaint and Report',
          onTap: () {},
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

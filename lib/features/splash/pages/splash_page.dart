import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../home/models/home_card_layout.dart';
import '../../auth/providers/auth_provider.dart';

/// ============================================================================
/// 启动页
///
/// 【功能】
/// - 显示启动动画（Logo 淡入+缩放）
/// - 初始化存储服务
/// - 加载主题设置
/// - 加载语言设置
/// - 初始化游客身份
/// - 动画完成后跳转到首页
///
/// 【如何修改】
/// - 修改启动图：替换 assets/images/splash.png
/// - 修改动画时长：AnimationController 的 duration
/// - 修改等待时间：Duration(milliseconds: 2000)
/// ============================================================================
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;   // 淡入动画
  late Animation<double> _scaleAnimation;  // 缩放动画
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    // 动画控制器（时长 1.5 秒）
    _controller = AnimationController(duration: const Duration(milliseconds: 1500), vsync: this);

    // 淡入动画：0 -> 1（0% - 60% 的动画进度）
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));

    // 缩放动画：0.8 -> 1.0
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOut)));

    _controller.forward();

    ref.listenManual<AuthState>(authProvider, (previous, next) {
      if (_isAuthReady(next)) {
        _navigateToHomeWhenReady();
      }
    });

    _initializeAndNavigate();
  }

  /// 初始化并导航
  /// 注意：storage.init() / themeModeProvider.load() / localeProvider.load()
  /// 已在 main.dart 中完成，此处只负责等待认证初始化完成后再进入首页。
  Future<void> _initializeAndNavigate() async {
    debugPrint('[Splash] _initializeAndNavigate start');

    final auth = ref.read(authProvider);
    if (_isAuthReady(auth)) {
      await _navigateToHomeWhenReady();
      return;
    }

    debugPrint('[Splash] waiting for auth initialization to finish before navigating');
  }

  bool _isAuthReady(AuthState auth) {
    return auth.status != AuthStatus.authenticating && auth.user != null;
  }

  Future<void> _navigateToHomeWhenReady() async {
    if (_navigated) return;
    _navigated = true;
    await _controller.forward().orCancel;
    if (mounted) {
      debugPrint('[Splash] auth ready, navigating to home');
      context.go('/');
    }
  }

  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final splashWidth = HomeCardLayout.splashWidth(context);
    final splashHeight = HomeCardLayout.splashHeight(context);
    final screenHeight = HomeCardLayout.screenHeight(context);

    return Scaffold(
      body: ColoredBox(
        color: Colors.black,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: Center(
              child: SizedBox(
                width: splashWidth,
                height: splashHeight > screenHeight ? screenHeight : splashHeight,
                child: Image.asset(
                  'assets/images/splash.png',
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

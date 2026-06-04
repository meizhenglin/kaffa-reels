import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../app/providers/app_providers.dart';
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
    _initializeAndNavigate();
  }

  /// 初始化并导航
  /// 注意：storage.init() / themeModeProvider.load() / localeProvider.load()
  /// 已在 main.dart 中完成，此处不再重复调用
  Future<void> _initializeAndNavigate() async {
    debugPrint('[Splash] _initializeAndNavigate start');
    // Guest 登录已在 main() 中同步完成，token 已就绪，此处无需再处理
    // 动画完成后直接跳转
    await _controller.forward();
    if (mounted) context.go('/');
  }

  /// 超时包装器：防止异步操作永久阻塞
  Future<void> _withTimeout(Future<void> future, Duration timeout) async {
    try {
      await future.timeout(timeout, onTimeout: () { debugPrint('[Splash] _withTimeout onTimeout!'); });
    } catch (e) {
      debugPrint('[Splash] _withTimeout catch: $e');
    }
  }

  @override void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FadeTransition(opacity: _fadeAnimation,
        child: ScaleTransition(scale: _scaleAnimation,
          child: SizedBox.expand(child: Image.asset('assets/images/splash.png', fit: BoxFit.cover)))),
    );
  }
}

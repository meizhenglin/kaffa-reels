import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qahwa_tv/l10n/app_localizations.dart';

import '_aliplayer_log_stub.dart'
    if (dart.library.io) '_aliplayer_log_native.dart'
    as aliplayer_impl;

import 'app/providers/app_providers.dart';
import 'app/router/router_config.dart';
import 'app/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/firebase/firebase_service.dart';
import 'core/providers/auth_provider.dart';

Future<void> _withTimeout(Future<void> future, Duration timeout) async {
  try {
    await future.timeout(timeout, onTimeout: () {});
  } catch (_) {}
}


void main() async {
  debugPrint('[MAIN] === main() started ===');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[MAIN] WidgetsFlutterBinding ready');

  // 关闭阿里云播放器日志（仅非 Web 平台）
  await aliplayer_impl.AliPlayerLog.init();

  // Firebase 初始化
  await _withTimeout(
    FirebaseService.initialize(),
    const Duration(seconds: 15),
  );

  runApp(
    ProviderScope(
      child: const QahwaTVApp(),
    ),
  );
}

class QahwaTVApp extends ConsumerStatefulWidget {
  const QahwaTVApp({super.key});

  @override
  ConsumerState<QahwaTVApp> createState() => _QahwaTVAppState();
}

class _QahwaTVAppState extends ConsumerState<QahwaTVApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      ref.read(themeModeProvider.notifier).load();
      ref.read(localeProvider.notifier).load();
      // 初始化 AuthService（加载缓存的 Token 和 UUID）
      await ref.read(authServiceProvider).init().timeout(const Duration(seconds: 5), onTimeout: () {});

      // 注册 Token 过期回调：先尝试刷新，刷新失败则登出
      ref.read(dioClientProvider).setOnTokenExpired(() async {
        final newToken = await ref.read(authServiceProvider).refreshToken();
        if (newToken != null) return newToken;
        // 刷新失败，强制登出
        await ref.read(authServiceProvider).logout();
        if (mounted) {
          context.go('/auth/login');
        }
        return null;
      });

      // 启动时匿名登录（仅在没有 Token 时才登录，不覆盖已有登录态）
      // 注意：AuthNotifier._init() 已在后台处理，这里不需要重复调用。
      // guestLoginProvider 的状态由 AuthNotifier 内部管理。
      // ref.read(guestLoginProvider.notifier).login();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}

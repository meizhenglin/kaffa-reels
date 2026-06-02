import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_aliplayer/flutter_aliplayer.dart';
import 'package:go_router/go_router.dart';
import 'package:arab_drama_app/l10n/app_localizations.dart';

import 'app/providers/app_providers.dart';
import 'app/router/router_config.dart';
import 'app/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/firebase/firebase_service.dart';
import 'core/providers/auth_provider.dart';
import 'core/storage/storage_service.dart';

Future<void> _withTimeout(Future<void> future, Duration timeout) async {
  try {
    await future.timeout(timeout, onTimeout: () {});
  } catch (_) {}
}


void main() async {
  debugPrint('[MAIN] === main() started ===');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[MAIN] WidgetsFlutterBinding ready');

  // 关闭阿里云播放器日志（只保留 API 请求日志）
  FlutterAliplayer.enableConsoleLog(false);
  FlutterAliplayer.setLogLevel(LogLevel.AF_LOG_LEVEL_NONE);

  // Firebase 初始化
  await _withTimeout(
    FirebaseService.initialize(),
    const Duration(seconds: 15),
  );

  runApp(
    ProviderScope(
      child: const ArabDramaApp(),
    ),
  );
}

class ArabDramaApp extends ConsumerStatefulWidget {
  const ArabDramaApp({super.key});

  @override
  ConsumerState<ArabDramaApp> createState() => _ArabDramaAppState();
}

class _ArabDramaAppState extends ConsumerState<ArabDramaApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      ref.read(themeModeProvider.notifier).load();
      ref.read(localeProvider.notifier).load();
      // 初始化 AuthService（加载缓存的 Token 和 UUID）
      await ref.read(authServiceProvider).init().timeout(const Duration(seconds: 5), onTimeout: () {});

      // 注册 Token 过期回调：清除 Token + 跳转到登录页
      ref.read(dioClientProvider).setOnTokenExpired(() {
        ref.read(authServiceProvider).logout();
        if (mounted) {
          context.go('/auth/login');
        }
      });

      // 启动时匿名登录，后续所有需要 Token 的请求直接使用
      ref.read(guestLoginProvider.notifier).login();
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

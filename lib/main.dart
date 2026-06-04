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

/// 启动时统一完成 Guest 登录，确保 UI 渲染时 token 已就绪
Future<void> _ensureGuestLogin(ProviderContainer container) async {
  final storage = container.read(storageServiceProvider);

  // 检查 token 是否已存在
  final cachedToken = await storage.getToken();
  final authToken = await storage.getAuthTokenAsync();
  if ((cachedToken != null && cachedToken.isNotEmpty) ||
      (authToken != null && authToken.isNotEmpty)) {
    debugPrint('[MAIN] token already exists, skip guest login');
    return;
  }

  debugPrint('[MAIN] no token found, performing guest login...');
  final authService = container.read(authServiceProvider);
  final result = await authService.login();
  debugPrint('[MAIN] guest login done: ${result?.token != null}');
}

Future<void> main() async {
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

  // 在 ProviderScope 创建之前，先同步完成 Guest 登录
  // 这样所有后续网络请求都有 token 可用，不会出现"空 token 先于登录"的问题
  final _tempContainer = ProviderContainer();
  await _ensureGuestLogin(_tempContainer);
  _tempContainer.dispose();

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
    // 主题/语言加载，以及注册 DioClient 的 Guest 登录回调
    // 注意：Guest 登录本身已在 main() 中同步完成，这里只做收尾工作
    Future.microtask(() {
      ref.read(themeModeProvider.notifier).load();
      ref.read(localeProvider.notifier).load();

      // 注册 Guest 登录回调：用于 code=23 时自动 guest 登录重试
      //（启动阶段 token 为空的场景已在 main() 中提前处理）
      ref.read(dioClientProvider).setOnGuestLogin(() async {
        final result = await ref.read(authServiceProvider).login();
        return result?.token;
      });
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

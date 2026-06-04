import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qahwa_tv/l10n/app_localizations.dart';

import '_aliplayer_log_stub.dart'
    if (dart.library.io) '_aliplayer_log_native.dart'
    as aliplayer_impl;

import 'app/providers/app_providers.dart';
import 'app/router/router_config.dart';
import 'app/theme/app_theme.dart';
import 'core/constants/app_constants.dart';
import 'core/firebase/firebase_service.dart';
import 'features/auth/providers/auth_provider.dart';
import 'core/storage/storage_service.dart';

Future<void> _withTimeout(Future<void> future, Duration timeout) async {
  try {
    await future.timeout(timeout, onTimeout: () {});
  } catch (_) {}
}

Future<void> main() async {
  debugPrint('[MAIN] === main() started ===');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[MAIN] WidgetsFlutterBinding ready');

  final storage = StorageService();
  await storage.init();
  debugPrint('[MAIN] StorageService initialized');

  // 关闭阿里云播放器日志（仅非 Web 平台）
  await aliplayer_impl.AliPlayerLog.init();

  // Firebase 初始化
  await _withTimeout(
    FirebaseService.initialize(),
    const Duration(seconds: 15),
  );

  // 这里只做基础设施初始化，不在 main() 提前执行游客登录。
  // 当前用户身份（自动登录 / 正式登录恢复 / 游客初始化）统一由 AuthNotifier._init() 决定，
  // 避免启动阶段出现两套认证入口，导致 token 与 UI 状态来源不一致。
  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
      ],
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
    // 启动时主动拉起认证初始化，避免依赖页面首次读取 authProvider 才触发。
    // 这样刷新 Web / 冷启动 App 后，会尽早执行正式登录恢复或游客初始化。
    Future.microtask(() {
      ref.read(authProvider);
      ref.read(themeModeProvider.notifier).load();
      ref.read(localeProvider.notifier).load();
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

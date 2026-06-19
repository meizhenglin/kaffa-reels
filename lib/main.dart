import 'dart:async';

import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qahwa_tv/l10n/app_localizations.dart';

import '_aliplayer_log_stub.dart'
    if (dart.library.io) '_aliplayer_log_native.dart'
    as aliplayer_impl;
import 'core/platform/platform_info_stub.dart'
    if (dart.library.io) 'core/platform/platform_info_io.dart';

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

Future<void> _initializeAliPlayerWidgetGlobalSettings() async {
  if (kIsWeb) {
    debugPrint('[MAIN] Skip AliPlayerWidget global settings on Web');
    return;
  }

  try {
    await AliPlayerWidgetGlobalSetting.setupConfig();

    String? cachePath;
    String? filesPath;

    if (isAndroidPlatform) {
      final externalCacheDirs = await getExternalCacheDirectories();
      cachePath = externalCacheDirs?.isNotEmpty == true
          ? externalCacheDirs!.first.path
          : null;

      final externalStorageDir = await getExternalStorageDirectory();
      filesPath = externalStorageDir?.path;

      if (cachePath == null || filesPath == null) {
        final internalCache = await getApplicationCacheDirectory();
        final internalDocs = await getApplicationDocumentsDirectory();
        cachePath ??= internalCache.path;
        filesPath ??= internalDocs.path;
      }
    } else {
      final cacheDir = await getApplicationCacheDirectory();
      final docsDir = await getApplicationDocumentsDirectory();
      cachePath = cacheDir.path;
      filesPath = docsDir.path;
    }

    AliPlayerWidgetGlobalSetting.setStoragePaths(
      cachePath: cachePath,
      filesPath: filesPath,
    );

    debugPrint('[MAIN] AliPlayerWidget global settings initialized');
  } catch (e) {
    debugPrint('[MAIN] AliPlayerWidget global settings init failed: $e');
  }
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
  await _initializeAliPlayerWidgetGlobalSettings();

  // Web：不在这里 await Firebase 初始化，避免被远端脚本超时阻塞首屏。
  // Firebase 会在首帧渲染后后台初始化。
  // 非 Web 平台：本地初始化，不需要网络，直接 await。
  if (!kIsWeb) {
    await _withTimeout(
      FirebaseService.initialize(),
      const Duration(seconds: 15),
    );
  }

  runApp(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
      ],
      child: const QahwaTVApp(),
    ),
  );

  if (kIsWeb) {
    _initFirebaseInBackground();
  }
}

void _initFirebaseInBackground() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[MAIN] Web: scheduling background Firebase init');
    FirebaseService.initialize().then((_) {
      debugPrint('[MAIN] Web: Firebase initialized in background');
    }).catchError((e) {
      debugPrint('[MAIN] Web: Firebase background init failed: $e');
    });
  });
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
    // 延迟初始化认证和设置，后台处理，不阻塞首屏渲染
    Future.microtask(() async {
      await Future.delayed(const Duration(milliseconds: 100));
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

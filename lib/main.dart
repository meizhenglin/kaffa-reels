import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobcommonlib/mobcommonlib.dart';
import 'package:qahwa_tv/l10n/app_localizations.dart';

import 'app/router/url_strategy_stub.dart'
    if (dart.library.html) 'app/router/url_strategy_web.dart'
    as url_strategy;
import 'features/commonAliPlayer/video_pointer_guard_stub.dart'
    if (dart.library.html) 'features/commonAliPlayer/video_pointer_guard_web.dart'
    as video_pointer_guard;

import 'app/providers/app_providers.dart';
import 'app/router/router_config.dart' show routerProvider;
import 'app/theme/app_theme.dart';
import 'core/ads/ad_mediator.dart';
import 'core/config/build_flavor.dart';
import 'core/config/build_info.dart';
import 'core/utils/app_restart.dart';
import 'core/widgets/mouse_drag_scroll.dart';
import 'core/firebase/firebase_service.dart';
import 'features/auth/providers/auth_provider.dart';
import 'features/payment/providers/coin_record_provider.dart' as coin_record;
import 'features/payment/providers/membership_provider.dart'
    show memberStateProvider;
import 'features/payment/services/play_billing_native_probe.dart';
import 'core/storage/storage_service.dart';
import 'services/share_service.dart';

Future<void> _withTimeout(Future<void> future, Duration timeout) async {
  try {
    await future.timeout(timeout, onTimeout: () {});
  } catch (_) {}
}

/// iOS 软重启的重建种子：值变化时以新 Key 重建 ProviderScope 子树。
/// （iOS 不允许 App 自行退出后自动拉起，exit(0) 表现为闪退，
/// 所以 iOS 的「重启」用软重启实现，见 AppRestart.registerSoftRestart）
final _appRebuildSeed = ValueNotifier<int>(0);

Future<void> main() async {
  debugPrint('[MAIN] === main() started ===');
  debugPrint('[MAIN] BuildFlavor.current = ${BuildFlavor.current}');
  // 打印完整构建标识：线上捞日志时能直接看出用户装的是哪个渠道、哪个版本。
  // 形如 `1.0.6+15.p`（platform）/ `1.0.6+15.g`（google）/ `1.0.6+15.w`（web）
  debugPrint(
    '[MAIN] BuildInfo.fullVersion = ${BuildInfo.fullVersion} '
    '(display ${BuildInfo.displayVersion})',
  );
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[MAIN] WidgetsFlutterBinding ready');

  // Web: 配置 URL 策略，移除 hash
  url_strategy.configureRouterUrlStrategy();

  // Web: 让 `<video>` 放弃接收指针事件（pointer-events: none）。
  // 否则视频这块 DOM 会独占点击，铺在上面的 GestureDetector 收不到 tap，
  // 表现就是「单击暂停/播放没反应」。非 web 平台是空实现。
  video_pointer_guard.allowVideoTapThrough();

  final storage = StorageService();
  await storage.init();
  debugPrint('[MAIN] StorageService initialized');

  if (!kIsWeb) {
    // 【启动优化】原来的顺序：
    //   Firebase(上限 15s) → AdManager → AdMediator 串行 await，
    //   全部堆在 runApp 之前，白屏时间 = 三者耗时之和。
    // 现在的顺序：
    //   1) AdMediator.initialize() 内部本来就会调 AdManager.initialize()
    //      （见 ad_mediator.dart:35-45），main 里那次单独的 AdManager 初始化
    //      是重复劳动，删掉；
    //   2) 广告 SDK 移到后台初始化：第一支广告要等用户跳转路由后才会展示，
    //      晚几百毫秒初始化没有业务影响，不值得挡首帧；
    //   3) Firebase 仍然 await —— firebase_auth 恢复会话依赖它，
    //      且它通常几百毫秒就完成（15s 只是断网兜底上限）。
    // 效果：白屏时间从「Firebase + AdMob + Meta」之和变成只剩 Firebase。
    final firebaseReady = _withTimeout(
      FirebaseService.initialize(),
      const Duration(seconds: 15),
    );
    Mobcommonlib.submitPolicyGrantResult(true, null);
    ShareService.init();

    unawaited(
      AdMediator.instance.initialize().then(
        (_) => debugPrint('[MAIN] Ads initialized in background'),
        onError: (Object e) => debugPrint('[MAIN] Ads init failed: $e'),
      ),
    );

    await firebaseReady;
  }

  // iOS 软重启：以新 Key 重建 ProviderScope 子树（provider 状态全部归零，
  // 路由回初始页），Firebase / 广告 SDK 等进程级单例保持已初始化状态。
  AppRestart.registerSoftRestart(() async {
    debugPrint('[MAIN] iOS soft restart: rebuilding app subtree');
    _appRebuildSeed.value++;
  });

  runApp(
    ValueListenableBuilder<int>(
      valueListenable: _appRebuildSeed,
      builder: (_, seed, __) => ProviderScope(
        key: ValueKey('app-$seed'),
        overrides: [storageServiceProvider.overrideWithValue(storage)],
        child: const QahwaTVApp(),
      ),
    ),
  );

  // 诊断开关：`--dart-define=PLAY_PROBE_IDS=com.qahwa.vip1,com.qahwa.vip2`
  // 打开后启动就会把每个商品的 Play 状态码打到 logcat。
  if (!kIsWeb) {
    unawaited(PlayNativeBillingProbe.runStartupProbe());
  }

  if (kIsWeb) {
    _initFirebaseInBackground();
  }
}

void _initFirebaseInBackground() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[MAIN] Web: scheduling background Firebase init');
    FirebaseService.initialize()
        .then((_) {
          debugPrint('[MAIN] Web: Firebase initialized in background');
        })
        .catchError((e) {
          debugPrint('[MAIN] Web: Firebase background init failed: `$e`');
        });
  });
}

class QahwaTVApp extends ConsumerStatefulWidget {
  const QahwaTVApp({super.key});

  @override
  ConsumerState<QahwaTVApp> createState() => _QahwaTVAppState();
}

class _QahwaTVAppState extends ConsumerState<QahwaTVApp> {
  /// 本次进程内是否已经跑过「启动补单」。
  ///
  /// auth 状态在启动过程中会变化多次（未登录 → 恢复会话 → 已登录），
  /// 用这个标记保证补单只跑一次，不随 auth 每次变化重跑。
  bool _startupPaymentRetryDone = false;

  @override
  void initState() {
    super.initState();
    ref.read(authProvider);
    Future.microtask(() {
      ref.read(themeModeProvider.notifier).load();
      ref.read(localeProvider.notifier).load();
    });
    // 【启动补单】补单必须等登录态恢复完成才能跑
    //（checkAndRetryPendingPayments 里未登录会直接 return），
    // 所以这里监听 authProvider：一旦变成「已登录的非游客」就执行。
    // K币和会员共用同一个本地待补队列，一次补单两条链路都覆盖。
    ref.listenManual(authProvider, (_, _) => _retryPendingPaymentsWhenReady());
    _retryPendingPaymentsWhenReady();
  }

  /// 登录态就绪后补发未完成的支付回调（会员开通 / K币到账）。
  void _retryPendingPaymentsWhenReady() {
    if (_startupPaymentRetryDone) return;
    final authState = ref.read(authProvider);
    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      // 会话还没恢复完，等 auth 下一次变化再试。
      return;
    }
    _startupPaymentRetryDone = true;

    Future.microtask(() async {
      int retried = 0;
      try {
        retried = await ref
            .read(memberStateProvider.notifier)
            .checkAndRetryPendingPayments();
      } catch (e) {
        debugPrint('[MAIN] startup pending-payment retry failed: $e');
      }
      // 只有在**真的补发过**订单时才刷新 K币余额：
      // K币余额接口复用的也是 /api/user/userPersonalCenter，
      // 无条件刷新会让每次启动都多打一次用户中心接口。
      if (retried == 0) return;
      try {
        await ref.read(coin_record.coinBalanceInfoProvider.notifier).load();
      } catch (e) {
        debugPrint('[MAIN] startup coin balance refresh failed: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    final app = MaterialApp.router(
      // Web 端这个值会写进浏览器标签页标题。必须和 `web/index.html` 的
      // `<title>` 一致，否则页面加载时标题会「先显示 index.html 的、
      // Flutter 起来后再跳一次」。品牌名由 BuildFlavor.brandName 决定，
      // google 渠道是 Qahwa TV，其余是 Kaffa Reels。
      title: BuildFlavor.brandName,
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
      // Web/桌面默认把鼠标排除在拖拽设备之外，导致所有列表只能用滚轮。
      // 统一在这里开启，全站页面都能像手机一样按住拖动。
      scrollBehavior: const MouseDragScrollBehavior(),
      builder: (context, child) => child ?? const SizedBox.shrink(),
    );

    if (kIsWeb) {
      return _WebFrame(child: app);
    }
    return app;
  }
}

// ============================================================================
// Web: max-width 1024px centered
// ============================================================================

class _WebFrame extends StatelessWidget {
  const _WebFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1024),
        child: child,
      ),
    );
  }
}

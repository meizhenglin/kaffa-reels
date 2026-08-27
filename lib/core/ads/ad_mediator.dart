import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'ad_manager.dart';
import 'meta_ad_manager.dart';
import 'ad_config.dart';

/// 广告平台枚举
enum AdPlatform {
  admob,
  meta,
}

/// 统一的广告中介器
/// 同时管理 AdMob 和 Meta 广告，提供统一的接口
/// 支持两种模式：
/// 1. 主备模式：优先 AdMob，失败后尝试 Meta
/// 2. 并行模式：同时请求两个平台，哪个先好展示哪个
class AdMediator {
  AdMediator._();

  static final AdMediator instance = AdMediator._();

  final AdManager _admobManager = AdManager.instance;
  final MetaAdManager _metaManager = MetaAdManager.instance;

  /// 广告加载模式
  /// primary - 主备模式（默认），优先 AdMob
  /// parallel - 并行模式，两个平台同时请求
  AdLoadMode _loadMode = AdLoadMode.primary;

  /// 设置广告加载模式
  void setLoadMode(AdLoadMode mode) {
    _loadMode = mode;
  }

  /// 初始化所有广告 SDK
  Future<void> initialize() async {
    debugPrint('[AdMediator] Initializing all ad platforms...');

    // 初始化 AdMob
    await _admobManager.initialize();

    // 初始化 Meta
    await _metaManager.initialize();

    debugPrint('[AdMediator] All ad platforms initialized');
  }

  /// 预加载激励广告
  /// 根据当前模式预加载广告
  Future<void> preloadRewardedAd() async {
    if (!AdConfig.isAdEnabled) return;

    switch (_loadMode) {
      case AdLoadMode.primary:
        // 主备模式：优先预加载 AdMob
        _admobManager.preloadRewardedAd();
        _metaManager.preloadRewardedAd(); // 同时预加载 Meta 作为备用
        break;
      case AdLoadMode.parallel:
        // 并行模式：同时预加载两个平台
        _admobManager.preloadRewardedAd();
        _metaManager.preloadRewardedAd();
        break;
    }
  }

  /// 激励广告是否已准备好（任意平台）
  bool isRewardedAdReady() {
    if (!AdConfig.isAdEnabled) return false;

    switch (_loadMode) {
      case AdLoadMode.primary:
        // 禁用 AdMob 时只检查 Meta
        if (AdConfig.isAdmobEnabled && _admobManager.isRewardedAdReady()) return true;
        if (_metaManager.isRewardedAdReady()) return true;
        return false;
      case AdLoadMode.parallel:
        // 并行模式：两个都可以
        return (AdConfig.isAdmobEnabled && _admobManager.isRewardedAdReady()) ||
            _metaManager.isRewardedAdReady();
    }
  }

  /// 获取已就绪的广告平台
  /// 当两个平台都就绪时，随机选择（50% Google / 50% Meta）
  AdPlatform? getReadyPlatform() {
    if (!AdConfig.isAdEnabled) return null;

    final bool admobReady = AdConfig.isAdmobEnabled && _admobManager.isRewardedAdReady();
    final bool metaReady = _metaManager.isRewardedAdReady();

    // 两个都就绪时，随机选择（50% 概率）
    if (admobReady && metaReady) {
      final selected = Random().nextBool() ? AdPlatform.admob : AdPlatform.meta;
      debugPrint('[AdMediator] Both platforms ready, randomly selected: $selected');
      return selected;
    }

    // 只有一个就绪时返回就绪的那个
    if (admobReady) return AdPlatform.admob;
    if (metaReady) return AdPlatform.meta;
    return null;
  }

  /// 展示激励广告（统一接口）
  /// 自动选择已就绪的广告平台进行展示
  /// [onRewardEarned] 用户完整观看广告、获得奖励时回调
  /// [onNotReady] 所有广告平台都未就绪时回调
  /// [onDismissed] 广告关闭时回调
  /// [preferredPlatform] 优先使用的广告平台（可选）
  Future<bool> showRewardedAd({
    required void Function() onRewardEarned,
    void Function()? onNotReady,
    void Function()? onDismissed,
    AdPlatform? preferredPlatform,
  }) async {
    if (!AdConfig.isAdEnabled) {
      onNotReady?.call();
      return false;
    }

    debugPrint('[AdMediator] showRewardedAd called, mode=$_loadMode, preferredPlatform=$preferredPlatform');

    // 确定使用哪个平台的广告
    AdPlatform? platformToUse = preferredPlatform;

    if (platformToUse == null) {
      platformToUse = getReadyPlatform();
    }

    // 如果指定平台没准备好，尝试另一个
    if (platformToUse == AdPlatform.admob && !_admobManager.isRewardedAdReady()) {
      if (_metaManager.isRewardedAdReady()) {
        platformToUse = AdPlatform.meta;
      } else {
        platformToUse = null;
      }
    } else if (platformToUse == AdPlatform.meta && !_metaManager.isRewardedAdReady()) {
      if (_admobManager.isRewardedAdReady()) {
        platformToUse = AdPlatform.admob;
      } else {
        platformToUse = null;
      }
    }

    if (platformToUse == null) {
      debugPrint('[AdMediator] No ad platform ready');
      onNotReady?.call();
      return false;
    }

    debugPrint('[AdMediator] Using platform: $platformToUse');

    switch (platformToUse) {
      case AdPlatform.admob:
        return _showAdmobRewardedAd(
          onRewardEarned: onRewardEarned,
          onDismissed: onDismissed,
        );
      case AdPlatform.meta:
        return _showMetaRewardedAd(
          onRewardEarned: onRewardEarned,
          onDismissed: onDismissed,
        );
    }
  }

  /// 展示 AdMob 激励广告
  Future<bool> _showAdmobRewardedAd({
    required void Function() onRewardEarned,
    void Function()? onDismissed,
  }) async {
    return await _admobManager.showRewardedAd(
      onRewardEarned: onRewardEarned,
      onNotReady: null, // AdMob 不会调用这个，因为我们已经检查过
    );
  }

  /// 展示 Meta 激励广告
  Future<bool> _showMetaRewardedAd({
    required void Function() onRewardEarned,
    void Function()? onDismissed,
  }) async {
    return await _metaManager.showRewardedAd(
      onRewardEarned: onRewardEarned,
      onNotReady: null, // Meta 不会调用这个，因为我们已经检查过
      onDismissed: onDismissed,
    );
  }

  /// 预加载插屏广告
  Future<void> preloadInterstitialAd() async {
    if (!AdConfig.isAdEnabled) return;

    switch (_loadMode) {
      case AdLoadMode.primary:
        // 禁用 AdMob 时只预加载 Meta
        if (AdConfig.isAdmobEnabled) {
          _admobManager.preloadInterstitialAd();
        }
        _metaManager.preloadInterstitialAd();
        break;
      case AdLoadMode.parallel:
        if (AdConfig.isAdmobEnabled) {
          _admobManager.preloadInterstitialAd();
        }
        _metaManager.preloadInterstitialAd();
        break;
    }
  }

  /// 插屏广告是否已准备好（任意平台）
  bool isInterstitialAdReady() {
    if (!AdConfig.isAdEnabled) return false;

    switch (_loadMode) {
      case AdLoadMode.primary:
        // 禁用 AdMob 时只检查 Meta
        if (AdConfig.isAdmobEnabled && _admobManager.isInterstitialAdReady()) return true;
        if (_metaManager.isInterstitialAdReady()) return true;
        return false;
      case AdLoadMode.parallel:
        return (AdConfig.isAdmobEnabled && _admobManager.isInterstitialAdReady()) ||
            _metaManager.isInterstitialAdReady();
    }
  }

  /// 获取已就绪的插屏广告平台
  AdPlatform? getReadyInterstitialPlatform() {
    if (!AdConfig.isAdEnabled) return null;

    final bool admobReady = AdConfig.isAdmobEnabled && _admobManager.isInterstitialAdReady();
    final bool metaReady = _metaManager.isInterstitialAdReady();

    // 两个都就绪时，随机选择（50% 概率）
    if (admobReady && metaReady) {
      final selected = Random().nextBool() ? AdPlatform.admob : AdPlatform.meta;
      debugPrint('[AdMediator] Both interstitial platforms ready, randomly selected: $selected');
      return selected;
    }

    if (admobReady) return AdPlatform.admob;
    if (metaReady) return AdPlatform.meta;
    return null;
  }

  /// 展示插屏广告（统一接口，支持 AdMob 和 Meta）
  Future<bool> showInterstitialAd({VoidCallback? onDismissed}) async {
    if (!AdConfig.isAdEnabled) return false;

    debugPrint('[AdMediator] showInterstitialAd called, mode=$_loadMode');

    AdPlatform? platformToUse = getReadyInterstitialPlatform();

    // 如果指定平台没准备好或被禁用，尝试另一个
    if (platformToUse == AdPlatform.admob && (!AdConfig.isAdmobEnabled || !_admobManager.isInterstitialAdReady())) {
      if (_metaManager.isInterstitialAdReady()) {
        platformToUse = AdPlatform.meta;
      } else {
        platformToUse = null;
      }
    } else if (platformToUse == AdPlatform.meta && !_metaManager.isInterstitialAdReady()) {
      if (AdConfig.isAdmobEnabled && _admobManager.isInterstitialAdReady()) {
        platformToUse = AdPlatform.admob;
      } else {
        platformToUse = null;
      }
    }

    if (platformToUse == null) {
      debugPrint('[AdMediator] No interstitial ad platform ready');
      return false;
    }

    debugPrint('[AdMediator] Using interstitial platform: $platformToUse');

    switch (platformToUse) {
      case AdPlatform.admob:
        return _admobManager.showInterstitialAd(onDismissed: onDismissed);
      case AdPlatform.meta:
        return _metaManager.showInterstitialAd(onDismissed: onDismissed);
    }
  }

  /// 销毁所有广告资源
  void dispose() {
    _admobManager.dispose();
    _metaManager.dispose();
  }
}

/// 广告加载模式
enum AdLoadMode {
  /// 主备模式：优先 AdMob，失败后尝试 Meta
  primary,

  /// 并行模式：同时请求两个平台
  parallel,
}

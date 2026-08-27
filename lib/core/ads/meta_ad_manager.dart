import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'ad_config.dart';

/// Meta Audience Network 广告管理器
/// 通过 MethodChannel 与原生 Android 代码通信
class MetaAdManager {
  MetaAdManager._();

  static final MetaAdManager instance = MetaAdManager._();

  static const _channel = MethodChannel('com.video.storydrama/meta_ads');

  bool _isInitialized = false;
  bool _isRewardedAdLoading = false;
  bool _isRewardedAdReady = false;

  /// 插屏广告状态
  bool _isInterstitialAdLoading = false;
  bool _isInterstitialAdReady = false;

  /// 上次加载失败时间（用于冷却）
  DateTime? _lastLoadFailedTime;

  /// 加载冷却时间（毫秒）- 正式环境至少45秒
  static const int _loadCooldownMs = 45000;

  /// 回调存储
  void Function()? _rewardEarnedCallback;
  void Function()? _dismissedCallback;
  void Function()? _interstitialDismissedCallback;

  /// Meta 广告是否启用（Placement ID 不是占位符时启用）
  bool get _isMetaAdEnabled => AdConfig.metaRewardedAdPlacementId != 'YOUR_META_REWARDED_AD_PLACEMENT_ID';

  /// 激励广告 Placement ID（从 AdConfig 获取）
  String get rewardedAdPlacementId => AdConfig.metaRewardedAdPlacementId;

  /// 插屏广告 Placement ID
  String get interstitialAdPlacementId => AdConfig.metaInterstitialAdPlacementId;

  /// 初始化 Meta SDK
  Future<void> initialize() async {
    if (_isInitialized) return;

    debugPrint('[MetaAdManager] Initializing...');

    if (!_isMetaAdEnabled) {
      debugPrint('[MetaAdManager] Meta ad is disabled');
      return;
    }

    // 设置 MethodChannel 回调处理
    _setupMethodChannelHandler();

    try {
      final result = await _channel.invokeMethod<bool>('initialize');
      _isInitialized = result ?? false;
      debugPrint('[MetaAdManager] Meta SDK initialized: $_isInitialized');
    } catch (e) {
      debugPrint('[MetaAdManager] Meta SDK init FAILED: $e');
    }
  }

  /// 设置 MethodChannel 回调处理
  void _setupMethodChannelHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onAdLoaded':
          final success = call.arguments as bool? ?? false;
          setRewardedAdReady(success);
          break;
        case 'onInterstitialAdLoaded':
          final success = call.arguments as bool? ?? false;
          setInterstitialAdReady(success);
          break;
        case 'onAdFailed':
          final error = call.arguments as String? ?? 'Unknown error';
          debugPrint('[MetaAdManager] Meta ad failed: $error');
          setRewardedAdReady(false);
          _lastLoadFailedTime = DateTime.now();
          break;
        case 'onInterstitialAdFailed':
          final error = call.arguments as String? ?? 'Unknown error';
          debugPrint('[MetaAdManager] Meta interstitial ad failed: $error');
          setInterstitialAdReady(false);
          _lastLoadFailedTime = DateTime.now();
          break;
        case 'onAdRewarded':
          debugPrint('[MetaAdManager] User earned reward from Meta ad');
          _rewardEarnedCallback?.call();
          break;
        case 'onAdClosed':
          debugPrint('[MetaAdManager] Meta ad closed');
          setRewardedAdReady(false);
          _dismissedCallback?.call();
          break;
        case 'onInterstitialAdClosed':
          debugPrint('[MetaAdManager] Meta interstitial ad closed');
          setInterstitialAdReady(false);
          _interstitialDismissedCallback?.call();
          break;
      }
    });
  }

  /// 预加载激励广告
  Future<void> preloadRewardedAd() async {
    if (!AdConfig.isAdEnabled) return;

    debugPrint('[MetaAdManager] preloadRewardedAd called, isLoading=$_isRewardedAdLoading, isReady=$_isRewardedAdReady');

    if (_isRewardedAdLoading || _isRewardedAdReady) {
      return;
    }

    await loadRewardedAd();
  }

  /// 预加载插屏广告
  Future<void> preloadInterstitialAd() async {
    if (!AdConfig.isAdEnabled) return;

    debugPrint('[MetaAdManager] preloadInterstitialAd called, isLoading=$_isInterstitialAdLoading, isReady=$_isInterstitialAdReady');

    if (_isInterstitialAdLoading || _isInterstitialAdReady) {
      return;
    }

    await loadInterstitialAd();
  }

  /// 加载插屏广告
  Future<void> loadInterstitialAd() async {
    if (!AdConfig.isAdEnabled) return;
    if (_isInterstitialAdLoading) return;

    // 检查冷却时间
    if (_lastLoadFailedTime != null) {
      final elapsed = DateTime.now().difference(_lastLoadFailedTime!).inMilliseconds;
      if (elapsed < _loadCooldownMs) {
        debugPrint('[MetaAdManager] Interstitial still in cooldown, skip loading');
        return;
      }
    }

    _isInterstitialAdLoading = true;
    debugPrint('[MetaAdManager] Loading Meta interstitial ad with placement: $interstitialAdPlacementId');

    try {
      await _channel.invokeMethod('loadInterstitialAd', {
        'placementId': interstitialAdPlacementId,
      });
      debugPrint('[MetaAdManager] Meta interstitial ad loading started');
    } catch (e) {
      debugPrint('[MetaAdManager] Failed to load Meta interstitial ad: $e');
      _isInterstitialAdLoading = false;
    }
  }

  /// 插屏广告是否已准备好
  bool isInterstitialAdReady() {
    if (!AdConfig.isAdEnabled) return false;
    return _isInterstitialAdReady;
  }

  /// 展示插屏广告
  Future<bool> showInterstitialAd({void Function()? onDismissed}) async {
    debugPrint('[MetaAdManager] showInterstitialAd called, isReady=$_isInterstitialAdReady');

    _interstitialDismissedCallback = onDismissed;

    if (!AdConfig.isAdEnabled) {
      debugPrint('[MetaAdManager] Meta ad is disabled');
      return false;
    }

    if (!_isInterstitialAdReady) {
      debugPrint('[MetaAdManager] Meta interstitial ad not ready');
      return false;
    }

    try {
      debugPrint('[MetaAdManager] Showing Meta interstitial ad...');
      await _channel.invokeMethod('showInterstitialAd');
      return true;
    } catch (e) {
      debugPrint('[MetaAdManager] Error showing Meta interstitial ad: $e');
      return false;
    }
  }

  /// 更新插屏广告就绪状态
  void setInterstitialAdReady(bool ready) {
    _isInterstitialAdReady = ready;
    _isInterstitialAdLoading = false;
    debugPrint('[MetaAdManager] Meta interstitial ad ready: $ready');
  }

  /// 加载激励广告
  Future<void> loadRewardedAd() async {
    if (!AdConfig.isAdEnabled) return;
    if (_isRewardedAdLoading) return;

    // 检查冷却时间
    if (_lastLoadFailedTime != null) {
      final elapsed = DateTime.now().difference(_lastLoadFailedTime!).inMilliseconds;
      if (elapsed < _loadCooldownMs) {
        debugPrint('[MetaAdManager] Still in cooldown (${(_loadCooldownMs - elapsed) / 1000}s remaining), skip loading');
        return;
      }
    }

    _isRewardedAdLoading = true;
    debugPrint('[MetaAdManager] Loading Meta rewarded ad...');

    try {
      await _channel.invokeMethod('loadRewardedAd', {
        'placementId': rewardedAdPlacementId,
      });
      debugPrint('[MetaAdManager] Meta rewarded ad loading started');
    } catch (e) {
      debugPrint('[MetaAdManager] Failed to load Meta rewarded ad: $e');
      _isRewardedAdLoading = false;
    }
  }

  /// 激励广告是否已准备好
  bool isRewardedAdReady() {
    if (!AdConfig.isAdEnabled) return false;
    return _isRewardedAdReady;
  }

  /// 更新广告就绪状态（由 MethodChannel 调用）
  void setRewardedAdReady(bool ready) {
    _isRewardedAdReady = ready;
    _isRewardedAdLoading = false;
    debugPrint('[MetaAdManager] Meta rewarded ad ready: $ready');
  }

  /// 更新广告加载状态
  void setRewardedAdLoading(bool loading) {
    _isRewardedAdLoading = loading;
  }

  /// 展示激励广告
  Future<bool> showRewardedAd({
    required void Function() onRewardEarned,
    void Function()? onNotReady,
    void Function()? onDismissed,
  }) async {
    debugPrint('[MetaAdManager] showRewardedAd called, isReady=$_isRewardedAdReady');

    // 存储回调
    _rewardEarnedCallback = onRewardEarned;
    _dismissedCallback = onDismissed;

    if (!AdConfig.isAdEnabled) {
      debugPrint('[MetaAdManager] Meta ad is disabled');
      onNotReady?.call();
      return false;
    }

    if (!_isRewardedAdReady) {
      debugPrint('[MetaAdManager] Meta rewarded ad not ready');
      onNotReady?.call();
      return false;
    }

    try {
      debugPrint('[MetaAdManager] Showing Meta rewarded ad...');
      await _channel.invokeMethod('showRewardedAd');
      return true;
    } catch (e) {
      debugPrint('[MetaAdManager] Error showing Meta rewarded ad: $e');
      return false;
    }
  }

  /// 销毁广告资源
  void dispose() {
    try {
      _channel.invokeMethod('destroyRewardedAd');
      _channel.invokeMethod('destroyInterstitialAd');
    } catch (e) {
      debugPrint('[MetaAdManager] Error destroying ad: $e');
    }
    _isRewardedAdReady = false;
    _isRewardedAdLoading = false;
    _isInterstitialAdReady = false;
    _isInterstitialAdLoading = false;
    _rewardEarnedCallback = null;
    _dismissedCallback = null;
    _interstitialDismissedCallback = null;
  }
}

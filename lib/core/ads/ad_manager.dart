import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../app/router/router_config.dart';
import 'ad_config.dart';

/// AdMob 广告管理器
/// 管理插屏广告的加载、展示和生命周期
class AdManager {
  AdManager._();

  static final AdManager instance = AdManager._();

  InterstitialAd? _interstitialAd;
  bool _isAdLoading = false;
  DateTime? _lastAdShownTime;

  /// 是否使用模拟广告（用于开发调试）
  static bool get _useDebugMockAd => kDebugMode && false; // 关闭调试模拟，使用真实广告

  /// 初始化广告 SDK
  Future<void> initialize() async {
    debugPrint('[AdManager] Initializing...');
    if (!AdConfig.isAdEnabled) {
      debugPrint('[AdManager] Ad is disabled');
      return;
    }

    if (_useDebugMockAd) {
      debugPrint('[AdManager] Debug mock mode enabled');
      return;
    }

    try {
      final result = await MobileAds.instance.initialize();
      debugPrint('[AdManager] AdMob SDK initialized: $result');
    } catch (e) {
      debugPrint('[AdManager] AdMob init FAILED: $e');
    }

    // 预加载广告
    _loadInterstitialAd();
  }

  /// 预加载插屏广告
  void _loadInterstitialAd() {
    debugPrint('[AdManager] _loadInterstitialAd called, isLoading=$_isAdLoading, ad=${_interstitialAd != null}, mockAd=$_useDebugMockAd');
    
    if (_isAdLoading || _interstitialAd != null || _useDebugMockAd) {
      return;
    }

    _isAdLoading = true;
    debugPrint('[AdManager] Loading interstitial ad with unit ID: ${AdConfig.interstitialAdUnitId}');

    InterstitialAd.load(
      adUnitId: AdConfig.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitialAd = ad;
          _isAdLoading = false;
          debugPrint('[AdManager] Interstitial ad LOADED successfully');
          _setupAdListeners();
        },
        onAdFailedToLoad: (error) {
          _isAdLoading = false;
          debugPrint('[AdManager] Interstitial ad FAILED to load: $error');
          // 延迟重试
          Future.delayed(const Duration(seconds: 5), _loadInterstitialAd);
        },
      ),
    );
  }

  /// 设置广告监听器
  void _setupAdListeners() {
    _interstitialAd?.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('[AdManager] Interstitial ad dismissed');
        _interstitialAd = null;
        // 广告关闭后执行回调
        _onAdDismissed?.call();
        _onAdDismissed = null;
        // 广告关闭后预加载下一个
        _loadInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[AdManager] Failed to show interstitial ad: $error');
        _interstitialAd = null;
        _loadInterstitialAd();
      },
    );
  }

  /// 检查是否可以展示广告
  bool _canShowAd() {
    if (!AdConfig.isAdEnabled) {
      return false;
    }

    // 调试模式：始终可以显示
    if (_useDebugMockAd) {
      return true;
    }

    if (_interstitialAd == null) {
      debugPrint('[AdManager] Ad not ready, try to load...');
      _loadInterstitialAd();
      return false;
    }

    // 检查间隔
    if (_lastAdShownTime != null) {
      final elapsed = DateTime.now().difference(_lastAdShownTime!).inSeconds;
      if (elapsed < AdConfig.minIntervalSeconds) {
        debugPrint('[AdManager] Too soon to show ad (${AdConfig.minIntervalSeconds}s interval)');
        return false;
      }
    }

    return true;
  }

  /// 广告关闭回调
  VoidCallback? _onAdDismissed;

  /// 展示插屏广告
  /// 返回是否成功展示
  Future<bool> showInterstitialAd({VoidCallback? onDismissed}) async {
    debugPrint('[AdManager] showInterstitialAd called, ad=$_interstitialAd, loading=$_isAdLoading');
    _onAdDismissed = onDismissed;
    
    if (!_canShowAd()) {
      debugPrint('[AdManager] Cannot show ad - _canShowAd returned false');
      return false;
    }

    // 调试模式：显示模拟广告
    if (_useDebugMockAd) {
      return _showDebugMockAd();
    }

    try {
      _lastAdShownTime = DateTime.now();
      debugPrint('[AdManager] Showing real interstitial ad...');
      await _interstitialAd!.show();
      debugPrint('[AdManager] Real interstitial ad shown successfully');
      return true;
    } catch (e) {
      debugPrint('[AdManager] Error showing interstitial ad: $e');
      _interstitialAd = null;
      _loadInterstitialAd();
      return false;
    }
  }

  /// 调试模式：显示模拟广告对话框
  Future<bool> _showDebugMockAd() async {
    _lastAdShownTime = DateTime.now();
    debugPrint('[AdManager] [DEBUG MOCK] Showing simulated interstitial ad');

    // 显示一个模拟广告对话框
    await showDialog(
      context: rootNavigatorKey.currentContext!,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('[DEBUG] Simulated Ad'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ad_units, size: 64, color: Colors.amber),
            SizedBox(height: 16),
            Text('This is a debug mock ad.\nAdMob will show real ads in production.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close (Simulated Ad)'),
          ),
        ],
      ),
    );

    debugPrint('[AdManager] [DEBUG MOCK] Simulated ad closed');
    return true;
  }

  /// 在视频播放特定节点展示广告（如每看完一集）
  /// [episodeIndex] 当前剧集索引
  /// [totalEpisodes] 总剧集数
  Future<bool> showAdAfterEpisode({
    required int episodeIndex,
    required int totalEpisodes,
  }) async {
    // 可配置：每N集展示一次广告
    const adInterval = 2; // 每2集展示一次
    if ((episodeIndex + 1) % adInterval == 0 && episodeIndex < totalEpisodes - 1) {
      return showInterstitialAd();
    }
    return false;
  }

  /// 释放广告资源
  void dispose() {
    _interstitialAd?.dispose();
    _interstitialAd = null;
  }
}

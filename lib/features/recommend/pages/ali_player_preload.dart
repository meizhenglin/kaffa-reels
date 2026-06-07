// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/28
// Brief: AliPlayer Preload

import 'package:flutter/material.dart';
import 'package:flutter_aliplayer/flutter_aliplayer_medialoader.dart';

import '../../commonAliPlayer/short_video_preload_tuning.dart';
import '../models/video_info.dart';

import 'ali_sliding_window.dart';

/// A class that manages cover preloading logic using the sliding window concept.
///
/// 使用滑动窗口概念管理封面预加载逻辑的类。
class AliPlayerPreload {
  /// The tag for logging purposes.
  static const String _logTag = 'AliPlayerPreload';

  /// Cover preloader instance.
  late final AliSlidingWindow<String>? _coverPreloader;
  late final AliSlidingWindow<String> _videoPreloader;

  /// Build context.
  final BuildContext _context;

  /// Whether to enable cover URL strategy.
  final bool _isCoverUrlStrategyEnabled;
  final FlutterAliPlayerMediaLoader _mediaLoader = FlutterAliPlayerMediaLoader();

  /// Constructor for AliPlayerPreload.
  AliPlayerPreload({
    required BuildContext context,
    required bool enableCoverUrlStrategy,
  })  : _context = context,
        _isCoverUrlStrategyEnabled = enableCoverUrlStrategy {
    _log('[init]');
    _initializeSlidingWindows();
    _initMediaLoader();
  }

  /// Initialize sliding windows after the instance is created.
  void _initializeSlidingWindows() {
    _videoPreloader = AliSlidingWindow.withCustomItems(
      ShortVideoPreloadTuning.mediaPreloadWindowOffsets,
      _preloadMedia,
      _cancelPreloadMedia,
      isValid: _isValidUrl,
      extra: 'VIDEO',
    );

    _coverPreloader = _isCoverUrlStrategyEnabled
        ? AliSlidingWindow.withWindowSize(
            ShortVideoPreloadTuning.recommendCoverPreloadLeftWindowSize,
            ShortVideoPreloadTuning.recommendCoverPreloadRightWindowSize,
            _preloadImage,
            null,
            isValid: _isValidUrl,
            extra: 'COVER',
          )
        : null;
  }

  /// Release resources and clean up.
  void destroy() {
    _log('[api][destroy]');
    _videoPreloader.release();
    _coverPreloader?.release();
    _releaseMediaLoader();
  }

  void _initMediaLoader() {
    _mediaLoader.setOnLoadStatusListener(
      (String url) => _log('[cbk][video][completion], $url'),
      (String url) => _log('[cbk][video][cancel], $url'),
      (String url, int code, String msg) {
        _log('[cbk][video][error], $url, $code, $msg', isError: true);
      },
      (String url, String code, String msg) {
        _log('[cbk][video][errorV2], $url, $code, $msg', isError: true);
      },
    );
  }

  void _releaseMediaLoader() {
    _mediaLoader.setOnLoadStatusListener(null, null, null, null);
  }

  /// Set video items (replace existing items).
  void setItems(List<VideoInfo> items) {
    _log('[api][set], ${items.length}');
    _updateItems(items, overwrite: true);
  }

  /// Add video items (append to existing items).
  void addItems(List<VideoInfo> items) {
    _log('[api][add], ${items.length}');
    _updateItems(items, overwrite: false);
  }

  /// Move to a specific position in the item list.
  void moveTo(int position) {
    _log('[api][moveTo], $position');
    _videoPreloader.moveTo(position);
    _coverPreloader?.moveTo(position);
  }

  /// Update cover items.
  void _updateItems(
    List<VideoInfo> items, {
    required bool overwrite,
  }) {
    if (items.isEmpty) return;

    final videoUrls = <String>{};
    final coverUrls = <String>{};
    for (final item in items) {
      if (_isValidUrl(item.videoUrl)) videoUrls.add(item.videoUrl);
      if (_isValidUrl(item.coverUrl)) coverUrls.add(item.coverUrl!);
    }

    if (overwrite) {
      _videoPreloader.setItems(videoUrls.toList());
      _coverPreloader?.setItems(coverUrls.toList());
    } else {
      _videoPreloader.addItems(videoUrls.toList());
      _coverPreloader?.addItems(coverUrls.toList());
    }
  }

  /// Validate if a URL is valid.
  static bool _isValidUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.isAbsolute;
  }

  /// Preload image using precacheImage.
  void _preloadMedia(String url) {
    Future.microtask(() {
      try {
        _log('[preload][video][load], $url');
        _mediaLoader.load(url, ShortVideoPreloadTuning.mediaPreloadBufferDurationMs);
      } catch (e) {
        _log('[preload][video][load][error], $e', isError: true);
      }
    });
  }

  void _cancelPreloadMedia(String url) {
    Future.microtask(() {
      try {
        _log('[preload][video][cancel], $url');
        _mediaLoader.cancel(url);
      } catch (e) {
        _log('[preload][video][cancel][error], $e', isError: true);
      }
    });
  }

  /// Preload image using precacheImage.
  void _preloadImage(String url) {
    Future.microtask(() async {
      _log('[preload][image], $url');
      await precacheImage(NetworkImage(url), _context, onError: (_, __) {
        _log('[cbk][image][error], $url', isError: true);
      });
    });
  }

  /// Log information with a consistent format.
  static void _log(String message, {bool isError = false}) {
    debugPrint('[$_logTag][${isError ? 'E' : 'I'}] $message');
  }
}

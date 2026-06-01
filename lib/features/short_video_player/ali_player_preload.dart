// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/28
// Brief: AliPlayer Preload

import 'package:flutter/material.dart';
import 'package:flutter_aliplayer/flutter_aliplayer_medialoader.dart';
import 'package:short_video_player/video_info.dart';

import 'ali_sliding_window.dart';

/// 使用滑动窗口概念管理视频和封面预加载逻辑的类。
class AliPlayerPreload {
  static const String _logTag = 'AliPlayerPreload';
  static const int _preloadBufferDuration = 3 * 1000;
  static const List<int> _mediaPreloadWindows = [-1, 1, 2];
  static const int _coverPreloadLeftWindowSize = 3;
  static const int _coverPreloadRightWindowSize = 10;

  late final AliSlidingWindow<String> _videoPreloader;
  late final AliSlidingWindow<String>? _coverPreloader;
  final BuildContext _context;
  final bool _isCoverUrlStrategyEnabled;
  final FlutterAliPlayerMediaLoader _mediaLoader = FlutterAliPlayerMediaLoader();

  AliPlayerPreload({
    required BuildContext context,
    required bool enableCoverUrlStrategy,
  })  : _context = context,
        _isCoverUrlStrategyEnabled = enableCoverUrlStrategy {
    _log("[init]");
    _initializeSlidingWindows();
    _initMediaLoader();
  }

  void _initializeSlidingWindows() {
    _videoPreloader = AliSlidingWindow.withCustomItems(
      _mediaPreloadWindows,
      _preloadMedia,
      _cancelPreloadMedia,
      isValid: _isValidUrl,
      extra: 'VIDEO',
    );

    _coverPreloader = _isCoverUrlStrategyEnabled
        ? AliSlidingWindow.withWindowSize(
            _coverPreloadLeftWindowSize,
            _coverPreloadRightWindowSize,
            _preloadImage,
            null,
            isValid: _isValidUrl,
            extra: 'COVER',
          )
        : null;
  }

  Future<void> _initMediaLoader() async {
    _mediaLoader.setOnLoadStatusListener(
      (String url) => _log("[cbk][video][completion], $url", isError: false),
      (String url) => _log("[cbk][video][cancel], $url", isError: false),
      (String url, int code, String msg) {},
      (String url, String code, String msg) =>
          _log("[cbk][video][errorV2], $url, $code, $msg", isError: true),
    );
  }

  void destroy() {
    _log("[api][destroy]");
    _videoPreloader.release();
    _coverPreloader?.release();
    _releaseMediaLoader();
  }

  void _releaseMediaLoader() {
    _mediaLoader.setOnLoadStatusListener(null, null, null, null);
  }

  void setItems(List<VideoInfo> items) {
    _log("[api][set], ${items.length}");
    _updateItems(items, overwrite: true);
  }

  void addItems(List<VideoInfo> items) {
    _log("[api][add], ${items.length}");
    _updateItems(items, overwrite: false);
  }

  void moveTo(int position) {
    _log("[api][moveTo], $position");
    _videoPreloader.moveTo(position);
    _coverPreloader?.moveTo(position);
  }

  void _updateItems(List<VideoInfo> items, {required bool overwrite}) {
    if (items.isEmpty) return;

    final videoUrls = <String>{};
    final coverUrls = <String>{};

    for (final item in items) {
      if (_isValidUrl(item.videoUrl)) videoUrls.add(item.videoUrl);
      if (_isValidUrl(item.coverUrl)) coverUrls.add(item.coverUrl);
    }

    if (overwrite) {
      _videoPreloader.setItems(videoUrls.toList());
      _coverPreloader?.setItems(coverUrls.toList());
    } else {
      _videoPreloader.addItems(videoUrls.toList());
      _coverPreloader?.addItems(coverUrls.toList());
    }
  }

  static bool _isValidUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.isAbsolute;
  }

  void _preloadMedia(String url) {
    Future.microtask(() async {
      try {
        _log("[preload][video][load], $url");
        _mediaLoader.load(url, _preloadBufferDuration);
      } catch (e) {
        _log("[preload][video][load][error], $e", isError: true);
      }
    });
  }

  void _cancelPreloadMedia(String url) {
    Future.microtask(() async {
      try {
        _log("[preload][video][cancel], $url");
        _mediaLoader.cancel(url);
      } catch (e) {
        _log("[preload][video][cancel][error], $e", isError: true);
      }
    });
  }

  void _preloadImage(String url) {
    Future.microtask(() async {
      _log("[preload][image], $url");
      await precacheImage(NetworkImage(url), _context, onError: (_, __) {
        _log("[cbk][image][error], $url", isError: true);
      });
    });
  }

  static void _log(String message, {bool isError = false}) {
    debugPrint("[$_logTag][${isError ? 'E' : 'I'}] $message");
  }
}

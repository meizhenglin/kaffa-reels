// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/28
// Brief: AliPlayer Preload

import 'package:flutter/material.dart';
import 'package:flutter_aliplayer/flutter_aliplayer_medialoader.dart';

import '../recommend/models/video_info.dart';

import 'ali_sliding_window.dart';
import 'short_video_preload_tuning.dart';

enum AliPreloadDebugStatus {
  neverStarted,
  loading,
  completed,
  canceled,
  error,
}

class AliPreloadDebugEntry {
  const AliPreloadDebugEntry({
    required this.normalizedUrlKey,
    required this.originalUrl,
    required this.status,
    required this.requestCount,
    required this.lastRequestedBufferDurationMs,
    required this.lastTier,
    required this.lastUpdatedAt,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  final String normalizedUrlKey;
  final String originalUrl;
  final AliPreloadDebugStatus status;
  final int requestCount;
  final int lastRequestedBufferDurationMs;
  final String lastTier;
  final DateTime lastUpdatedAt;
  final int? lastErrorCode;
  final String? lastErrorMessage;

  AliPreloadDebugEntry copyWith({
    String? normalizedUrlKey,
    String? originalUrl,
    AliPreloadDebugStatus? status,
    int? requestCount,
    int? lastRequestedBufferDurationMs,
    String? lastTier,
    DateTime? lastUpdatedAt,
    int? lastErrorCode,
    String? lastErrorMessage,
  }) {
    return AliPreloadDebugEntry(
      normalizedUrlKey: normalizedUrlKey ?? this.normalizedUrlKey,
      originalUrl: originalUrl ?? this.originalUrl,
      status: status ?? this.status,
      requestCount: requestCount ?? this.requestCount,
      lastRequestedBufferDurationMs:
          lastRequestedBufferDurationMs ?? this.lastRequestedBufferDurationMs,
      lastTier: lastTier ?? this.lastTier,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastErrorCode: lastErrorCode ?? this.lastErrorCode,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
    );
  }

  String toDebugLabel() {
    final errorPart = lastErrorCode != null ||
            (lastErrorMessage != null && lastErrorMessage!.isNotEmpty)
        ? ' error=${lastErrorCode ?? '-'}:${lastErrorMessage ?? '-'}'
        : '';
    return 'status=${status.name} tier=$lastTier requests=$requestCount bufferMs=$lastRequestedBufferDurationMs$errorPart';
  }
}

/// A class that manages cover preloading logic using the sliding window concept.
class AliPlayerPreload {
  static const String _logTag = 'AliPlayerPreload';

  late final AliSlidingWindow<String>? _coverPreloader;
  final bool _enableVideoPreload;
  late final AliSlidingWindow<String>? _videoPreloader;
  AliSlidingWindow<String>? _nearVideoPreloader;
  AliSlidingWindow<String>? _farVideoPreloader;

  final BuildContext _context;
  final bool _isCoverUrlStrategyEnabled;
  final bool _usePrioritizedVideoPreload;
  final FlutterAliPlayerMediaLoader _mediaLoader = FlutterAliPlayerMediaLoader();
  final Map<String, AliPreloadDebugEntry> _debugEntriesByUrlKey = {};

  AliPlayerPreload({
    required BuildContext context,
    required bool enableCoverUrlStrategy,
    bool usePrioritizedVideoPreload = false,
    bool enableVideoPreload = true,
  })  : _context = context,
        _isCoverUrlStrategyEnabled = enableCoverUrlStrategy,
        _usePrioritizedVideoPreload = usePrioritizedVideoPreload,
        _enableVideoPreload = enableVideoPreload {
    _log('[init]');
    _initializeSlidingWindows();
    _initMediaLoader();
  }

  void _initializeSlidingWindows() {
    _videoPreloader = _enableVideoPreload
        ? AliSlidingWindow.withCustomItems(
            ShortVideoPreloadTuning.mediaPreloadWindowOffsets,
            _preloadMedia,
            _cancelPreloadMedia,
            isValid: _isValidUrl,
            extra: 'VIDEO',
          )
        : null;

    _nearVideoPreloader = _enableVideoPreload && _usePrioritizedVideoPreload
        ? AliSlidingWindow.withCustomItems(
            ShortVideoPreloadTuning.watchMediaPreloadNearOffsets,
            (url) => _preloadMedia(
              url,
              bufferDurationMs: ShortVideoPreloadTuning.watchMediaPreloadNearBufferDurationMs,
              tier: 'near',
            ),
            _cancelPreloadMedia,
            isValid: _isValidUrl,
            extra: 'VIDEO_NEAR',
          )
        : null;
    _farVideoPreloader = _enableVideoPreload && _usePrioritizedVideoPreload
        ? AliSlidingWindow.withCustomItems(
            ShortVideoPreloadTuning.watchMediaPreloadFarOffsets,
            (url) => _preloadMedia(
              url,
              bufferDurationMs: ShortVideoPreloadTuning.watchMediaPreloadFarBufferDurationMs,
              tier: 'far',
            ),
            _cancelPreloadMedia,
            isValid: _isValidUrl,
            extra: 'VIDEO_FAR',
          )
        : null;

    _coverPreloader = _isCoverUrlStrategyEnabled
        ? AliSlidingWindow.withWindowSize(
            ShortVideoPreloadTuning.commonCoverPreloadLeftWindowSize,
            ShortVideoPreloadTuning.commonCoverPreloadRightWindowSize,
            _preloadImage,
            null,
            isValid: _isValidUrl,
            extra: 'COVER',
          )
        : null;
  }

  void destroy() {
    _log('[api][destroy]');
    _videoPreloader?.release();
    _nearVideoPreloader?.release();
    _farVideoPreloader?.release();
    _coverPreloader?.release();
    _releaseMediaLoader();
  }

  void _initMediaLoader() {
    _mediaLoader.setOnLoadStatusListener(
      (String url) => _handleLoadCompletion(url),
      (String url) => _handleLoadCancel(url),
      (String url, int code, String msg) {
        _handleLoadError(url, code, msg);
      },
      (String url, String code, String msg) {
        _handleLoadError(url, null, '$code:$msg');
      },
    );
  }

  void _releaseMediaLoader() {
    _mediaLoader.setOnLoadStatusListener(null, null, null, null);
  }

  void setItems(List<VideoInfo> items) {
    _log('[api][set], ${items.length}');
    _updateItems(items, overwrite: true);
  }

  void addItems(List<VideoInfo> items) {
    _log('[api][add], ${items.length}');
    _updateItems(items, overwrite: false);
  }

  void moveTo(int position) {
    _log('[api][moveTo], $position');
    if (_usePrioritizedVideoPreload) {
      _nearVideoPreloader?.moveTo(position, preserveExecutedItems: true);
      _farVideoPreloader?.moveTo(position, preserveExecutedItems: true);
    } else {
      _videoPreloader?.moveTo(position, preserveExecutedItems: true);
    }
    _coverPreloader?.moveTo(position);
  }

  void _updateItems(
    List<VideoInfo> items, {
    required bool overwrite,
  }) {
    if (items.isEmpty) return;

    final videoUrls = items.map((item) => item.videoUrl).toList(growable: false);
    final coverUrls = items.map((item) => item.coverUrl ?? '').toList(growable: false);

    if (overwrite) {
      if (_usePrioritizedVideoPreload) {
        _nearVideoPreloader?.setItems(videoUrls);
        _farVideoPreloader?.setItems(videoUrls);
      } else {
        _videoPreloader?.setItems(videoUrls);
      }
      _coverPreloader?.setItems(coverUrls);
    } else {
      if (_usePrioritizedVideoPreload) {
        _nearVideoPreloader?.addItems(videoUrls);
        _farVideoPreloader?.addItems(videoUrls);
      } else {
        _videoPreloader?.addItems(videoUrls);
      }
      _coverPreloader?.addItems(coverUrls);
    }
  }

  static bool _isValidUrl(String? url) {
    if (url == null || url.isEmpty) return false;
    final uri = Uri.tryParse(url);
    return uri != null && uri.isAbsolute;
  }

  void _preloadMedia(
    String url, {
    int? bufferDurationMs,
    String tier = 'default',
  }) {
    Future.microtask(() {
      try {
        final durationMs =
            bufferDurationMs ?? ShortVideoPreloadTuning.mediaPreloadBufferDurationMs;
        _recordPreloadRequest(
          url,
          bufferDurationMs: durationMs,
          tier: tier,
        );
        _log(
          '[preload][video][load], key=${_normalizeUrlKey(url)} tier=$tier durationMs=$durationMs, $url',
        );
        _mediaLoader.load(url, durationMs);
      } catch (e) {
        _log('[preload][video][load][error], $e', isError: true);
      }
    });
  }

  void _cancelPreloadMedia(String url) {
    Future.microtask(() {
      try {
        _log('[preload][video][cancel], key=${_normalizeUrlKey(url)}, $url');
        _mediaLoader.cancel(url);
      } catch (e) {
        _log('[preload][video][cancel][error], $e', isError: true);
      }
    });
  }

  AliPreloadDebugEntry? getDebugEntry(String? url) {
    if (url == null || url.isEmpty) return null;
    return _debugEntriesByUrlKey[_normalizeUrlKey(url)];
  }

  Map<String, AliPreloadDebugEntry> getDebugEntriesSnapshot() =>
      Map.unmodifiable(_debugEntriesByUrlKey);

  void _recordPreloadRequest(
    String url, {
    required int bufferDurationMs,
    required String tier,
  }) {
    final key = _normalizeUrlKey(url);
    final now = DateTime.now();
    final existing = _debugEntriesByUrlKey[key];
    _debugEntriesByUrlKey[key] = (existing ??
            AliPreloadDebugEntry(
              normalizedUrlKey: key,
              originalUrl: url,
              status: AliPreloadDebugStatus.neverStarted,
              requestCount: 0,
              lastRequestedBufferDurationMs: 0,
              lastTier: 'unknown',
              lastUpdatedAt: now,
            ))
        .copyWith(
          originalUrl: url,
          status: AliPreloadDebugStatus.loading,
          requestCount: (existing?.requestCount ?? 0) + 1,
          lastRequestedBufferDurationMs: bufferDurationMs,
          lastTier: tier,
          lastUpdatedAt: now,
          lastErrorCode: null,
          lastErrorMessage: null,
        );
  }

  void _handleLoadCompletion(String url) {
    _updateDebugStatus(url, AliPreloadDebugStatus.completed);
    _log('[cbk][video][completion], key=${_normalizeUrlKey(url)}, $url');
  }

  void _handleLoadCancel(String url) {
    _updateDebugStatus(url, AliPreloadDebugStatus.canceled);
    _log('[cbk][video][cancel], key=${_normalizeUrlKey(url)}, $url');
  }

  void _handleLoadError(String url, int? code, String msg) {
    _updateDebugStatus(
      url,
      AliPreloadDebugStatus.error,
      errorCode: code,
      errorMessage: msg,
    );
    _log(
      '[cbk][video][error], key=${_normalizeUrlKey(url)}, $url, ${code ?? '-'}, $msg',
      isError: true,
    );
  }

  void _updateDebugStatus(
    String url,
    AliPreloadDebugStatus status, {
    int? errorCode,
    String? errorMessage,
  }) {
    final key = _normalizeUrlKey(url);
    final now = DateTime.now();
    final existing = _debugEntriesByUrlKey[key];
    _debugEntriesByUrlKey[key] = (existing ??
            AliPreloadDebugEntry(
              normalizedUrlKey: key,
              originalUrl: url,
              status: status,
              requestCount: 0,
              lastRequestedBufferDurationMs: 0,
              lastTier: 'unknown',
              lastUpdatedAt: now,
            ))
        .copyWith(
          originalUrl: url,
          status: status,
          lastUpdatedAt: now,
          lastErrorCode: errorCode,
          lastErrorMessage: errorMessage,
        );
  }

  String _normalizeUrlKey(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final queryKeys = uri.queryParametersAll.keys.toList()..sort();
    final normalizedQuery = <String>[];
    for (final key in queryKeys) {
      final values = [...?uri.queryParametersAll[key]]..sort();
      for (final value in values) {
        normalizedQuery.add('$key=$value');
      }
    }
    return '${uri.scheme}://${uri.host}${uri.path}?${normalizedQuery.join('&')}';
  }

  void _preloadImage(String url) {
    Future.microtask(() async {
      _log('[preload][image], $url');
      await precacheImage(NetworkImage(url), _context, onError: (_, __) {
        _log('[cbk][image][error], $url', isError: true);
      });
    });
  }

  static void _log(String message, {bool isError = false}) {
    debugPrint('[$_logTag][${isError ? 'E' : 'I'}] $message');
  }
}

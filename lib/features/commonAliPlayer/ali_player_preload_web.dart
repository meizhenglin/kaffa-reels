// Web stub for AliPlayerPreload.
// AliPlayer relies on native Android/iOS plugins that are not available in the
// browser. For the Web build we expose a no-op implementation that keeps the
// public API surface compatible with the mobile `AliPlayerPreload` so that
// upstream callers (recommendPage.dart, etc.) can be written once.
import 'package:flutter/widgets.dart';

import '../recommend/models/video_info.dart';

class AliPlayerPreload {
  AliPlayerPreload({
    required BuildContext context,
    required bool enableCoverUrlStrategy,
    bool usePrioritizedVideoPreload = false,
    bool enableVideoPreload = true,
  });

  void destroy() {}

  void setItems(List<VideoInfo> items) {}

  void addItems(List<VideoInfo> items) {}

  void moveTo(int position) {}
}

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
}
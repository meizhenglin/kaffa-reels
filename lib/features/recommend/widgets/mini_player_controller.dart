import 'dart:async';
import 'package:flutter/widgets.dart' show WidgetsBinding;

import 'package:flutter_aliplayer/flutter_aliplayer.dart';
import 'package:flutter_aliplayer/flutter_aliplayer_factory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';

/// Mini player state for the Recommend tab.
class MiniPlayerState {
  const MiniPlayerState({
    this.videoUrl = '',
    this.title = '',
    this.coverUrl,
    this.dramaId,
    this.episodes = const [],
    this.isPlaying = false,
    this.isLoading = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.hasError = false,
  });

  final String videoUrl;
  final String title;
  final String? coverUrl;
  final String? dramaId;
  final List<MiniEpisode> episodes;
  final bool isPlaying;
  final bool isLoading;
  final int positionMs;
  final int durationMs;
  final bool hasError;

  double get progress => durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  MiniPlayerState copyWith({
    String? videoUrl,
    String? title,
    String? coverUrl,
    String? dramaId,
    List<MiniEpisode>? episodes,
    bool? isPlaying,
    bool? isLoading,
    int? positionMs,
    int? durationMs,
    bool? hasError,
  }) {
    return MiniPlayerState(
      videoUrl: videoUrl ?? this.videoUrl,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      dramaId: dramaId ?? this.dramaId,
      episodes: episodes ?? this.episodes,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      hasError: hasError ?? this.hasError,
    );
  }
}

class MiniEpisode {
  const MiniEpisode({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.coverUrl,
    this.isUnlocked = true,
  });
  final String id;
  final String title;
  final String videoUrl;
  final String? coverUrl;
  final bool isUnlocked;
}

/// Controller for the mini player on the Recommend tab.
class MiniPlayerController extends StateNotifier<MiniPlayerState> {
  MiniPlayerController() : super(const MiniPlayerState()) {
    _player = FlutterAliPlayerFactory.createAliPlayer();
    _setupListeners();
  }

  final Logger _logger = Logger();
  FlutterAliplayer? _player;
  Timer? _positionTimer;
  int? _viewId;

  /// 热重启检测：static 在热重启后保留旧值，实例 buildId 每次 build 时递增
  /// 两者对比可判断热重启是否发生
  static int staticBuildId = 0;
  int buildId = 0;

  /// 热重启重置中，此时 setViewId 不要自动加载视频
  bool _resettingForHotRestart = false;

  void setViewId(int viewId) {
    _viewId = viewId;
    if (state.videoUrl.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _player?.setPlayerView(viewId);
        if (!_resettingForHotRestart) {
          _loadVideo(state.videoUrl);
        }
        _resettingForHotRestart = false;
      });
    }
  }

  @override
  void _setupListeners() {
    final player = _player;
    if (player == null) return;

    player.setOnPrepared((_) async {
      if (mounted) {
        final duration = await player.getDuration();
        state = state.copyWith(isLoading: false, durationMs: duration);
        _startPositionTimer();
      }
    });

    player.setOnRenderingStart((_) {
      if (mounted) state = state.copyWith(isLoading: false);
    });

    player.setOnLoadingStatusListener(
      loadingBegin: (_) {
        if (mounted) state = state.copyWith(isLoading: true);
      },
      loadingProgress: (percent, _, __) {
        if (mounted) state = state.copyWith(isLoading: true);
      },
      loadingEnd: (_) {
        if (mounted) state = state.copyWith(isLoading: false);
      },
    );

    player.setOnInfo((infoCode, extraValue, _, __) {
      if (!mounted) return;
      if (infoCode == InfoCode.CURRENTPOSITION && extraValue != null) {
        state = state.copyWith(positionMs: extraValue);
      }
    });

    player.setOnStateChanged((newState, _) {
      if (!mounted) return;
      switch (newState) {
        case FlutterAvpdef.started:
          state = state.copyWith(isPlaying: true, isLoading: false);
          break;
        case FlutterAvpdef.paused:
          state = state.copyWith(isPlaying: false);
          break;
        case FlutterAvpdef.stopped:
          state = state.copyWith(isPlaying: false);
          break;
        default:
          break;
      }
    });

    player.setOnError((code, extra, msg, _) {
      _logger.e('MiniPlayer error: $code $extra $msg');
      if (mounted) state = state.copyWith(hasError: true, isLoading: false);
    });

    player.setOnCompletion((_) {
      if (mounted) {
        state = state.copyWith(isPlaying: false, positionMs: state.durationMs);
      }
    });
  }

  void _loadVideo(String url) {
    final player = _player;
    if (player == null || url.isEmpty) return;
    state = state.copyWith(
      isLoading: true,
      hasError: false,
      positionMs: 0,
      durationMs: 0,
    );
    player.setAutoPlay(true);
    player.setUrl(url);
  }

  void playDrama({
    required String videoUrl,
    required String title,
    String? coverUrl,
    String? dramaId,
    List<MiniEpisode> episodes = const [],
  }) {
    _logger.d('[MiniPlayer] playDrama url=$videoUrl title=$title _viewId=$_viewId');
    state = state.copyWith(
      videoUrl: videoUrl,
      title: title,
      coverUrl: coverUrl,
      dramaId: dramaId,
      episodes: episodes,
      isLoading: true,
      hasError: false,
      positionMs: 0,
      durationMs: 0,
    );
    if (_viewId != null) {
      _logger.d('[MiniPlayer] _viewId is set, loading video');
      _player?.setPlayerView(_viewId!);
      _loadVideo(videoUrl);
    } else {
      _logger.w('[MiniPlayer] _viewId is null! AliPlayerView.onCreated not called yet');
    }
  }

  /// 热重启后 AliPlayerView 重建时调用此方法
  /// 停止旧播放器实例，释放 SurfaceTexture，避免 "already connected to another API" 错误
  void resetAfterHotRestart() {
    _resettingForHotRestart = true;
    _player?.stop();
    _player?.release();
    _player = FlutterAliPlayerFactory.createAliPlayer();
    _setupListeners();
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void togglePlay() {
    final player = _player;
    if (player == null) return;
    try {
      if (state.isPlaying) {
        player.pause();
        state = state.copyWith(isPlaying: false);
      } else {
        player.play();
        state = state.copyWith(isPlaying: true);
      }
    } catch (_) {
      // Ignore on unsupported platforms
    }
  }

  void seekTo(double progress) {
    final player = _player;
    if (player == null || state.durationMs <= 0) return;
    final position = (state.durationMs * progress.clamp(0.0, 1.0)).round();
    try {
      player.seekTo(position, FlutterAvpdef.ACCURATE);
    } catch (_) {
      // Ignore on unsupported platforms
    }
    state = state.copyWith(positionMs: position);
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      final player = _player;
      if (player == null || !mounted) return;
      try {
        final pos = await player.getCurrentPosition();
        if (mounted && pos is int) {
          state = state.copyWith(positionMs: pos);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _player?.stop();
    _player?.release();
    _player = null;
    super.dispose();
  }
}

/// Provider for the mini player.
final miniPlayerProvider =
    StateNotifierProvider<MiniPlayerController, MiniPlayerState>((ref) {
  final controller = MiniPlayerController();
  ref.onDispose(() => controller.dispose());
  return controller;
});

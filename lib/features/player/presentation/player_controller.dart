import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_aliplayer/flutter_aliplayer.dart';
import 'package:flutter_aliplayer/flutter_aliplayer_factory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../domain/player_state.dart';

import '../domain/player_state.dart';

class PlayerArgs {
  const PlayerArgs({
    required this.videoUrl,
    required this.title,
    this.dramaId,
    this.allEpisodes = const [],
    this.currentIndex = 0,
    this.coverUrl,
    this.isUnlocked = true,
    this.videoUrlOne,
    this.videoUrlTwo,
  });

  final String videoUrl;
  final String title;
  final String? dramaId;
  final List<EpisodeData> allEpisodes;
  final int currentIndex;
  final String? coverUrl;
  final bool isUnlocked;
  final String? videoUrlOne;
  final String? videoUrlTwo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerArgs &&
          videoUrl == other.videoUrl &&
          dramaId == other.dramaId &&
          currentIndex == other.currentIndex;

  @override
  int get hashCode => Object.hash(videoUrl, dramaId, currentIndex);
}

class EpisodeData {
  const EpisodeData({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.coverUrl,
    this.isUnlocked = true,
    this.isVipOnly = false,
  });

  final String id;
  final String title;
  final String videoUrl;
  final String? coverUrl;
  final bool isUnlocked;
  /// Whether the parent drama requires VIP to unlock locked episodes.
  /// Free episodes (isUnlocked=true) are always watchable even by guests.
  final bool isVipOnly;
}

class PlayerController extends StateNotifier<PlayerState> {
  PlayerController(this._args)
      : super(PlayerState(
          title: _buildTitle(_args.title, _args.currentIndex),
          videoUrl: _args.videoUrl,
          currentQuality: VideoQuality.sd,
        )) {
    _init();
  }

  static String _buildTitle(String dramaTitle, int index) {
    if (dramaTitle.contains('EP.')) return dramaTitle;
    return '$dramaTitle EP.${index + 1}';
  }

  final PlayerArgs _args;
  final Logger _logger = Logger();
  FlutterAliplayer? _player;
  Timer? _hideControlsTimer;
  Timer? _positionTimer;
  bool _isDisposed = false;

  static const List<double> supportedSpeeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  List<EpisodeData> get allEpisodes => _args.allEpisodes;
  int get currentIndex => _args.currentIndex;
  bool get hasNextEpisode => currentIndex < allEpisodes.length - 1;
  bool get hasPreviousEpisode => currentIndex > 0;
  bool isUnlockedAt(int index) => index < allEpisodes.length && allEpisodes[index].isUnlocked;

  String? get videoUrlOne => _args.videoUrlOne;
  String? get videoUrlTwo => _args.videoUrlTwo;

  String _urlForQuality(VideoQuality quality) {
    switch (quality) {
      case VideoQuality.sd:
        return _args.videoUrl;
      case VideoQuality.hd:
        return _args.videoUrlOne ?? _args.videoUrl;
      case VideoQuality.fhd:
        return _args.videoUrlTwo ?? _args.videoUrlOne ?? _args.videoUrl;
    }
  }

  Future<void> switchQuality(VideoQuality quality) async {
    final url = _urlForQuality(quality);
    if (url == state.videoUrl) return;
    await loadVideo(url);
    state = state.copyWith(currentQuality: quality);
  }

  Future<void> _init() async {
    try {
      if (Platform.isIOS) {
        await FlutterAliPlayerFactory.initLicenseServiceForIOS();
      }
      await _initBrightness();
      _createPlayer();
    } catch (e, st) {
      _logger.e('Player init failed', error: e, stackTrace: st);
      state = state.copyWith(
        status: PlayerStatus.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _initBrightness() async {
    try {
      final brightness = await ScreenBrightness().application;
      state = state.copyWith(brightness: brightness.clamp(0.0, 1.0));
    } catch (_) {
      // Web/desktop may not support system brightness
    }
  }

  void _createPlayer() {
    _logger.d('Creating player for ${_args.videoUrl}');
    _player = FlutterAliPlayerFactory.createAliPlayer();
    final player = _player!;

    player.setOnPrepared((_) async {
      if (_isDisposed) return;
      _logger.d('onPrepared fired for ${state.videoUrl}');
      final duration = await player.getDuration();
      state = state.copyWith(
        status: PlayerStatus.prepared,
        durationMs: duration,
      );
      await player.play();
    });

    player.setOnRenderingStart((_) {
      if (_isDisposed) return;
      state = state.copyWith(status: PlayerStatus.playing);
      _startPositionTimer();
    });

    player.setOnStateChanged((newState, _) {
      if (_isDisposed) return;
      _handleNativeState(newState);
    });

    player.setOnLoadingStatusListener(
      loadingBegin: (_) {
        if (_isDisposed) return;
        state = state.copyWith(status: PlayerStatus.buffering);
      },
      loadingProgress: (percent, _, _playerId) {
        if (_isDisposed) return;
        final buffered = (state.durationMs * percent / 100).round();
        state = state.copyWith(
          status: PlayerStatus.buffering,
          bufferedMs: buffered,
        );
      },
      loadingEnd: (_) {
        if (_isDisposed) return;
        if (state.isPlaying) {
          state = state.copyWith(status: PlayerStatus.playing);
        }
      },
    );

    player.setOnInfo((infoCode, extraValue, _, _playerId) {
      if (_isDisposed) return;
      if (infoCode == InfoCode.CURRENTPOSITION && extraValue != null) {
        state = state.copyWith(
          positionMs: extraValue,
          status: state.status == PlayerStatus.buffering
              ? PlayerStatus.playing
              : state.status,
        );
      } else if (infoCode == InfoCode.BUFFEREDPOSITION && extraValue != null) {
        state = state.copyWith(bufferedMs: extraValue);
      }
    });

    player.setOnCompletion((_) {
      if (_isDisposed) return;
      state = state.copyWith(
        status: PlayerStatus.completed,
        positionMs: state.durationMs,
      );
      _stopPositionTimer();
    });

    player.setOnError((code, extra, msg, _) {
      if (_isDisposed) return;
      _logger.e('Player error: $code $extra $msg');
      state = state.copyWith(
        status: PlayerStatus.error,
        errorMessage: msg ?? 'Playback error ($code)',
      );
    });

    player.setOnSeekComplete((_) {
      if (_isDisposed) return;
      state = state.copyWith(isSeeking: false);
    });

    player.setAutoPlay(true);
  }

  void _handleNativeState(int newState) {
    switch (newState) {
      case FlutterAvpdef.started:
        state = state.copyWith(status: PlayerStatus.playing);
        _startPositionTimer();
      case FlutterAvpdef.paused:
        state = state.copyWith(status: PlayerStatus.paused);
        _stopPositionTimer();
      case FlutterAvpdef.stopped:
        state = state.copyWith(status: PlayerStatus.idle);
        _stopPositionTimer();
      case FlutterAvpdef.completion:
        state = state.copyWith(status: PlayerStatus.completed);
        _stopPositionTimer();
      case FlutterAvpdef.error:
        state = state.copyWith(
          status: PlayerStatus.error,
          errorMessage: state.errorMessage ?? 'Playback error',
        );
        _stopPositionTimer();
    }
  }

  Future<void> onViewCreated(int viewId) async {
    final player = _player;
    if (player == null) return;

    _logger.d('onViewCreated called, viewId=$viewId, url=${_args.videoUrl}');
    await player.setPlayerView(viewId);
    await loadVideo(_args.videoUrl);
  }

  void _preloadAdjacentEpisodes() {
    if (currentIndex < allEpisodes.length - 1) {
      final nextEpisode = allEpisodes[currentIndex + 1];
      _preloadVideo(nextEpisode.videoUrl);
    }
    if (currentIndex > 0) {
      final prevEpisode = allEpisodes[currentIndex - 1];
      _preloadVideo(prevEpisode.videoUrl);
    }
  }

  void _preloadVideo(String url) async {
    if (url.isEmpty) return;
    final preloadPlayer = FlutterAliPlayerFactory.createAliPlayer();
    preloadPlayer.setAutoPlay(false);
    preloadPlayer.setUrl(url);
    _preloadPlayers ??= [];
    _preloadPlayers!.add(preloadPlayer);
  }

  List<FlutterAliplayer>? _preloadPlayers;

  Future<void> loadVideo(String url) async {
    final player = _player;
    if (player == null) return;
    if (url.isEmpty) {
      _logger.w('loadVideo called with empty URL');
      return;
    }

    _logger.d('loadVideo: $url');

    state = state.copyWith(
      status: PlayerStatus.loading,
      videoUrl: url,
      positionMs: 0,
      durationMs: 0,
      clearError: true,
    );

    player.setAutoPlay(true);
    await player.setUrl(url);
    await player.prepare();

    // 超时检测：如果 15 秒内没有 prepared 回调，说明视频加载失败
    Future.delayed(const Duration(seconds: 15), () {
      if (_isDisposed) return;
      if (state.status == PlayerStatus.loading) {
        _logger.w('Video load timeout for: $url');
        state = state.copyWith(
          status: PlayerStatus.error,
          errorMessage: '视频加载超时，请检查网络或视频地址是否有效',
        );
      }
    });
  }

  Future<void> loadEpisode(int index) async {
    if (index < 0 || index >= allEpisodes.length) return;

    final episode = allEpisodes[index];
    state = state.copyWith(title: _buildTitle(_args.title, index));
    await loadVideo(episode.videoUrl);
    _preloadAdjacentEpisodes();
  }

  Future<void> playNextEpisode() async {
    if (hasNextEpisode) {
      await loadEpisode(currentIndex + 1);
    }
  }

  Future<void> playPreviousEpisode() async {
    if (hasPreviousEpisode) {
      await loadEpisode(currentIndex - 1);
    }
  }

  Future<void> togglePlay() async {
    final player = _player;
    if (player == null || state.isLocked) return;

    if (state.isPlaying) {
      await player.pause();
      state = state.copyWith(status: PlayerStatus.paused);
    } else {
      if (state.status == PlayerStatus.completed) {
        await player.seekTo(0, FlutterAvpdef.ACCURATE);
      }
      await player.play();
      state = state.copyWith(status: PlayerStatus.playing);
    }
    showControls();
  }

  Future<void> play() => togglePlay();

  Future<void> pause() async {
    await _player?.pause();
    state = state.copyWith(status: PlayerStatus.paused);
  }

  Future<void> seekToProgress(double progress) async {
    final player = _player;
    if (player == null || state.durationMs <= 0) return;

    final position = (state.durationMs * progress.clamp(0.0, 1.0)).round();
    state = state.copyWith(isSeeking: true, positionMs: position);
    await player.seekTo(position, FlutterAvpdef.ACCURATE);
    showControls();
  }

  Future<void> setPlaybackSpeed(double speed) async {
    final player = _player;
    if (player == null) return;

    try {
      await player.setSpeed(speed);
    } catch (_) {
      // Ignore on unsupported platforms
    }
    state = state.copyWith(playbackSpeed: speed);
    showControls();
  }

  void cyclePlaybackSpeed() {
    final currentIndex = supportedSpeeds.indexOf(state.playbackSpeed);
    final nextIndex = (currentIndex + 1) % supportedSpeeds.length;
    setPlaybackSpeed(supportedSpeeds[nextIndex]);
  }

  Future<void> setVolume(double volume) async {
    final player = _player;
    if (player == null) return;

    final clamped = volume.clamp(0.0, 1.0);
    try {
      await player.setVolume(clamped);
    } catch (_) {
      // Ignore on unsupported platforms (e.g. web/desktop)
    }
    state = state.copyWith(
      volume: clamped,
      gestureHint: '${(clamped * 100).round()}%',
    );
    _clearGestureHintLater();
  }

  Future<void> adjustVolumeByDelta(double delta) async {
    await setVolume(state.volume + delta);
  }

  Future<void> setBrightness(double brightness) async {
    final clamped = brightness.clamp(0.0, 1.0);
    try {
      await ScreenBrightness().setApplicationScreenBrightness(clamped);
    } catch (_) {
      // Ignore on unsupported platforms
    }
    state = state.copyWith(
      brightness: clamped,
      gestureHint: '${(clamped * 100).round()}%',
    );
    _clearGestureHintLater();
  }

  Future<void> adjustBrightnessByDelta(double delta) async {
    await setBrightness(state.brightness + delta);
  }

  void toggleFullscreen() {
    final isFullscreen = !state.isFullscreen;
    state = state.copyWith(isFullscreen: isFullscreen);

    if (isFullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    showControls();
  }

  void toggleLock() {
    state = state.copyWith(
      isLocked: !state.isLocked,
      showControls: !state.isLocked ? false : true,
    );
  }

  void showControls() {
    if (state.isLocked) return;
    state = state.copyWith(showControls: true);
    _resetHideControlsTimer();
  }

  void hideControls() {
    if (state.isLocked) return;
    state = state.copyWith(showControls: false);
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (!_isDisposed && state.isPlaying && !state.isLocked) {
        hideControls();
      }
    });
  }

  void _startPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      final player = _player;
      if (player == null || _isDisposed || state.isSeeking) return;
      try {
        final pos = await player.getCurrentPosition();
        if (pos is int && pos != state.positionMs) {
          state = state.copyWith(positionMs: pos);
        }
      } catch (_) {}
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void _clearGestureHintLater() {
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!_isDisposed) {
        state = state.copyWith(clearGestureHint: true);
      }
    });
  }

  Future<void> disposePlayer() async {
    if (_isDisposed) return;
    _isDisposed = true;
    _hideControlsTimer?.cancel();
    _stopPositionTimer();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    // Release preload players
    if (_preloadPlayers != null) {
      for (final p in _preloadPlayers!) {
        try {
          await p.release();
        } catch (_) {}
      }
      _preloadPlayers = null;
    }

    final player = _player;
    _player = null;
    if (player != null) {
      try {
        await player.stop();
        await player.release();
      } catch (e) {
        _logger.w('Player release error: $e');
      }
    }
  }

  @override
  void dispose() {
    disposePlayer();
    super.dispose();
  }
}

final playerControllerProvider = StateNotifierProvider.family<PlayerController, PlayerState, PlayerArgs>((ref, args) {
  final controller = PlayerController(args);
  ref.onDispose(() => controller.disposePlayer());
  return controller;
});

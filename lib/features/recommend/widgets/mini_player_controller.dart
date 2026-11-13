import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

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
  final String videoUrl, title;
  final String? coverUrl, dramaId;
  final List<MiniEpisode> episodes;
  final bool isPlaying, isLoading, hasError;
  final int positionMs, durationMs;
  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0;
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
  }) => MiniPlayerState(
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

class MiniEpisode {
  const MiniEpisode({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.coverUrl,
    this.isUnlocked = true,
  });
  final String id, title, videoUrl;
  final String? coverUrl;
  final bool isUnlocked;
}

class MiniPlayerController extends StateNotifier<MiniPlayerState> {
  MiniPlayerController() : super(const MiniPlayerState());
  VideoPlayerController? _player;
  Timer? _positionTimer;
  int _generation = 0;

  VideoPlayerController? get player => _player;
  void playDrama({
    required String videoUrl,
    required String title,
    String? coverUrl,
    String? dramaId,
    List<MiniEpisode> episodes = const [],
  }) {
    state = state.copyWith(
      videoUrl: videoUrl,
      title: title,
      coverUrl: coverUrl,
      dramaId: dramaId,
      episodes: episodes,
      isLoading: true,
      hasError: false,
      isPlaying: false,
      positionMs: 0,
      durationMs: 0,
    );
    unawaited(_load(videoUrl));
  }

  Future<void> _load(String url) async {
    final generation = ++_generation;
    final next = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await next.initialize();
      if (!mounted || generation != _generation) {
        await next.dispose();
        return;
      }
      final previous = _player;
      _player = next;
      await previous?.dispose();
      await next.play();
      state = state.copyWith(
        isLoading: false,
        isPlaying: true,
        durationMs: next.value.duration.inMilliseconds,
        hasError: false,
      );
      _positionTimer?.cancel();
      _positionTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        if (!mounted || _player == null) return;
        final v = _player!.value;
        state = state.copyWith(
          positionMs: v.position.inMilliseconds,
          isPlaying: v.isPlaying,
          isLoading: v.isBuffering,
        );
      });
    } catch (_) {
      await next.dispose();
      if (mounted && generation == _generation)
        state = state.copyWith(
          isLoading: false,
          hasError: true,
          isPlaying: false,
        );
    }
  }

  void togglePlay() {
    final p = _player;
    if (p == null) return;
    if (p.value.isPlaying) {
      unawaited(p.pause());
      state = state.copyWith(isPlaying: false);
    } else {
      unawaited(p.play());
      state = state.copyWith(isPlaying: true);
    }
  }

  void seekTo(double progress) {
    final p = _player;
    if (p == null || state.durationMs <= 0) return;
    final ms = (state.durationMs * progress.clamp(0.0, 1.0)).round();
    unawaited(p.seekTo(Duration(milliseconds: ms)));
    state = state.copyWith(positionMs: ms);
  }

  @override
  void dispose() {
    _generation++;
    _positionTimer?.cancel();
    unawaited(_player?.dispose());
    _player = null;
    super.dispose();
  }
}

final miniPlayerProvider =
    StateNotifierProvider<MiniPlayerController, MiniPlayerState>(
      (ref) => MiniPlayerController(),
    );

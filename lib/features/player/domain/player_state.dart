import 'package:equatable/equatable.dart';

enum VideoQuality { sd, hd, fhd }

enum PlayerStatus {
  idle,
  loading,
  prepared,
  playing,
  paused,
  buffering,
  completed,
  error,
}

class PlayerState extends Equatable {
  const PlayerState({
    this.status = PlayerStatus.idle,
    this.isFullscreen = false,
    this.showControls = true,
    this.isLocked = false,
    this.positionMs = 0,
    this.durationMs = 0,
    this.bufferedMs = 0,
    this.volume = 1.0,
    this.brightness = 0.5,
    this.playbackSpeed = 1.0,
    this.errorMessage,
    this.title = '',
    this.videoUrl = '',
    this.isSeeking = false,
    this.gestureHint,
    this.currentQuality = VideoQuality.sd,
  });

  final PlayerStatus status;
  final bool isFullscreen;
  final bool showControls;
  final bool isLocked;
  final int positionMs;
  final int durationMs;
  final int bufferedMs;
  final double volume;
  final double brightness;
  final double playbackSpeed;
  final String? errorMessage;
  final String title;
  final String videoUrl;
  final bool isSeeking;
  final String? gestureHint;
  final VideoQuality currentQuality;

  bool get isPlaying => status == PlayerStatus.playing;
  bool get isBuffering =>
      status == PlayerStatus.buffering || status == PlayerStatus.loading;
  bool get hasError => status == PlayerStatus.error;

  double get progress =>
      durationMs > 0 ? (positionMs / durationMs).clamp(0.0, 1.0) : 0.0;

  double get bufferedProgress =>
      durationMs > 0 ? (bufferedMs / durationMs).clamp(0.0, 1.0) : 0.0;

  PlayerState copyWith({
    PlayerStatus? status,
    bool? isFullscreen,
    bool? showControls,
    bool? isLocked,
    int? positionMs,
    int? durationMs,
    int? bufferedMs,
    double? volume,
    double? brightness,
    double? playbackSpeed,
    String? errorMessage,
    String? title,
    String? videoUrl,
    bool? isSeeking,
    String? gestureHint,
    VideoQuality? currentQuality,
    bool clearGestureHint = false,
    bool clearError = false,
  }) {
    return PlayerState(
      status: status ?? this.status,
      isFullscreen: isFullscreen ?? this.isFullscreen,
      showControls: showControls ?? this.showControls,
      isLocked: isLocked ?? this.isLocked,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
      bufferedMs: bufferedMs ?? this.bufferedMs,
      volume: volume ?? this.volume,
      brightness: brightness ?? this.brightness,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      title: title ?? this.title,
      videoUrl: videoUrl ?? this.videoUrl,
      isSeeking: isSeeking ?? this.isSeeking,
      gestureHint: clearGestureHint ? null : (gestureHint ?? this.gestureHint),
      currentQuality: currentQuality ?? this.currentQuality,
    );
  }

  @override
  List<Object?> get props => [
        status,
        isFullscreen,
        showControls,
        isLocked,
        positionMs,
        durationMs,
        bufferedMs,
        volume,
        brightness,
        playbackSpeed,
        errorMessage,
        title,
        videoUrl,
        isSeeking,
        gestureHint,
        currentQuality,
      ];
}

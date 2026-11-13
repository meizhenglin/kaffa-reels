import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'player_native.dart' if (dart.library.html) 'player_web.dart';

/// Common video player component.
enum VideoQuality { sd, hd, fhd }

class CommonEpisode {
  const CommonEpisode({
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

/// Shared player entry point. Existing callers can continue passing the full
/// playback and episode metadata while playback is handled by video_player.
class CommonVideoPlayer extends ConsumerStatefulWidget {
  const CommonVideoPlayer({
    super.key,
    required this.videoUrl,
    required this.videoId,
    this.isFullscreen = false,
    this.onBackPressed,
    this.initialProgress,
    this.autoPlay = true,
    this.allEpisodes = const [],
    this.currentIndex = 0,
    this.videoUrlOne,
    this.videoUrlTwo,
    this.title,
    this.coverUrl,
    this.isVipOnly = false,
    this.isCanPlay = 1,
    this.isVip = 0,
    this.onEpisodeChanged,
  });

  final String videoUrl;
  final String videoId;
  final bool isFullscreen;
  final VoidCallback? onBackPressed;
  final Duration? initialProgress;
  final bool autoPlay;
  final List<CommonEpisode> allEpisodes;
  final int currentIndex;
  final String? videoUrlOne;
  final String? videoUrlTwo;
  final String? title;
  final String? coverUrl;
  final bool isVipOnly;
  final int isCanPlay;
  final int isVip;
  final void Function(int index)? onEpisodeChanged;

  @override
  ConsumerState<CommonVideoPlayer> createState() => _CommonVideoPlayerState();
}

class _CommonVideoPlayerState extends ConsumerState<CommonVideoPlayer> {
  @override
  Widget build(BuildContext context) => WebFullscreenPlayer(
    videoUrl: widget.videoUrl,
    coverUrl: widget.coverUrl,
    autoPlay: widget.autoPlay,
    title: widget.title ?? '',
    isCanPlay: widget.isCanPlay,
    isVip: widget.isVip,
    allEpisodes: widget.allEpisodes,
    currentIndex: widget.currentIndex,
    onEpisodeChanged: widget.onEpisodeChanged,
    onBackPressed: widget.onBackPressed,
  );
}

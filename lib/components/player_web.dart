// Web-specific fullscreen player using native video_player
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'common_video_player.dart' show CommonEpisode;

// Web-only fullscreen player using native video_player
class _WebFullscreenPlayer extends StatefulWidget {
  final String videoUrl;
  final String? coverUrl;
  final bool autoPlay;
  final String title;
  final int isCanPlay;
  final int isVip;
  final List<CommonEpisode> allEpisodes;
  final int currentIndex;
  final void Function(int index)? onEpisodeChanged;
  final VoidCallback? onBackPressed;

  const WebFullscreenPlayer({
    super.key,
    required this.videoUrl,
    this.coverUrl,
    this.autoPlay = true,
    this.title = '',
    this.isCanPlay = 1,
    this.isVip = 0,
    this.allEpisodes = const [],
    this.currentIndex = 0,
    this.onEpisodeChanged,
    this.onBackPressed,
  });

  @override
  State<WebFullscreenPlayer> createState() => WebFullscreenPlayerState();
}

class _WebFullscreenPlayerState extends State<_WebFullscreenPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _isPlaying = false;
  bool _showControls = true;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  int _currentIndex = 0;

  bool get _isLocked => widget.isCanPlay == 0 || widget.isVip == 1;

  String get _currentVideoUrl {
    if (widget.allEpisodes.isNotEmpty && _currentIndex < widget.allEpisodes.length) {
      return widget.allEpisodes[_currentIndex].videoUrl;
    }
    return widget.videoUrl;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
    _initController();
  }

  @override
  void didUpdateWidget(WebFullscreenPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newUrl = _currentVideoUrl;
    final oldUrl = oldWidget.allEpisodes.isNotEmpty && 
        oldWidget.currentIndex < oldWidget.allEpisodes.length
        ? oldWidget.allEpisodes[oldWidget.currentIndex].videoUrl
        : oldWidget.videoUrl;
    
    if (newUrl != oldUrl) {
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
      _hasError = false;
      _isPlaying = false;
      _initController();
    }
    
    if (widget.currentIndex != oldWidget.currentIndex) {
      _currentIndex = widget.currentIndex;
    }
  }

  Future<void> _initController() async {
    final url = _currentVideoUrl;
    if (url.isEmpty) return;

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;

    try {
      await controller.initialize();
      if (!mounted) return;

      controller.addListener(_onControllerUpdate);

      if (widget.autoPlay && !_isLocked) {
        await controller.play();
        setState(() => _isPlaying = true);
      }

      setState(() {
        _isInitialized = true;
        _duration = controller.value.duration;
        _position = Duration.zero;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
      });
    }
  }

  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;
    final playing = _controller!.value.isPlaying;
    final pos = _controller!.value.position;
    final dur = _controller!.value.duration;
    if (playing != _isPlaying || pos != _position || dur != _duration) {
      setState(() {
        _isPlaying = playing;
        _position = pos;
        _duration = dur;
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_controller == null || _isLocked) return;
    if (_isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
    setState(() => _showControls = false);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showControls = true);
    });
  }

  void _onSliderChanged(double value) {
    if (_controller == null) return;
    final ms = (value * _duration.inMilliseconds).round();
    _controller!.seekTo(Duration(milliseconds: ms));
  }

  void _previousEpisode() {
    if (_currentIndex > 0) {
      widget.onEpisodeChanged?.call(_currentIndex - 1);
    }
  }

  void _nextEpisode() {
    if (_currentIndex < widget.allEpisodes.length - 1) {
      widget.onEpisodeChanged?.call(_currentIndex + 1);
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    if (_currentVideoUrl.isEmpty) {
      return Container(color: Colors.black, child: const Center(child: Text('No video URL', style: TextStyle(color: Colors.white))));
    }

    if (_hasError) {
      return Container(color: Colors.black, child: const Center(child: Text('Failed to load video', style: TextStyle(color: Colors.white))));
    }

    if (!_isInitialized || _controller == null) {
      return Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (widget.coverUrl != null)
              Image.network(widget.coverUrl!, fit: BoxFit.cover),
            const Center(child: CircularProgressIndicator(color: Colors.white)),
          ],
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Video
          if (!_isLocked)
            Center(
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            ),

          // Gesture layer
          Positioned.fill(
            child: GestureDetector(
              onTap: _togglePlay,
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.transparent),
            ),
          ),

          // Cover when paused
          if (!_isPlaying && !_isLocked && widget.coverUrl != null)
            Positioned.fill(
              child: Image.network(widget.coverUrl!, fit: BoxFit.contain),
            ),

          // Locked overlay
          if (_isLocked)
            Container(
              color: Colors.black87,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock, color: Colors.white, size: 64),
                    SizedBox(height: 16),
                    Text('VIP Content', style: TextStyle(color: Colors.white, fontSize: 18)),
                  ],
                ),
              ),
            ),

          // Controls
          if (!_isLocked && _showControls) ...[
            // Top bar
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 8,
                  right: 8,
                  bottom: 12,
                ),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: widget.onBackPressed ?? () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.allEpisodes.isNotEmpty && _currentIndex < widget.allEpisodes.length
                            ? widget.allEpisodes[_currentIndex].title
                            : widget.title,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom bar with progress
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.skip_previous, color: Colors.white),
                      onPressed: _currentIndex > 0 ? _previousEpisode : null,
                    ),
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 32),
                      onPressed: _togglePlay,
                    ),
                    IconButton(
                      icon: const Icon(Icons.skip_next, color: Colors.white),
                      onPressed: _currentIndex < widget.allEpisodes.length - 1 ? _nextEpisode : null,
                    ),
                    const SizedBox(width: 8),
                    Text(_formatDuration(_position), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.white,
                          inactiveTrackColor: Colors.white38,
                          thumbColor: Colors.white,
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                        ),
                        child: Slider(
                          value: _duration.inMilliseconds > 0
                              ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
                              : 0.0,
                          onChanged: _onSliderChanged,
                        ),
                      ),
                    ),
                    Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ],

          // Center play button when paused
          if (!_isPlaying && !_isLocked && !_showControls)
            Center(
              child: IconButton(
                iconSize: 64,
                color: Colors.white,
                onPressed: _togglePlay,
                icon: const Icon(Icons.play_circle_fill),
              ),
            ),
        ],
      ),
    );
  }
}

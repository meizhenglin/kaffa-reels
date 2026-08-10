// Web stub for ShortVideoItem.
// On mobile, this widget is backed by AliPlayerWidgetController (native).
// On Web we fall back to the `video_player` package (HTML5 video element).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../recommend/models/video_info.dart';

class ShortVideoItem extends StatefulWidget {
  final VideoInfo videoInfo;
  final bool autoPlay;
  final bool resolvePlayableUrl;
  final Widget Function(BuildContext context, VideoInfo videoInfo)? overlayBuilder;
  final Widget Function(BuildContext context, VideoInfo videoInfo)? topOverlayBuilder;
  final String? debugInfo;
  final VoidCallback? onCompleted;

  const ShortVideoItem({
    super.key,
    required this.videoInfo,
    this.autoPlay = false,
    this.resolvePlayableUrl = true,
    this.overlayBuilder,
    this.topOverlayBuilder,
    this.debugInfo,
    this.onCompleted,
  });

  @override
  State<ShortVideoItem> createState() => ShortVideoItemState();
}

class ShortVideoItemState extends State<ShortVideoItem> {
  VideoPlayerController? _controller;
  bool _isLoading = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _setup(widget.videoInfo.videoUrl, widget.autoPlay);
  }

  @override
  void didUpdateWidget(covariant ShortVideoItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoInfo.videoUrl != oldWidget.videoInfo.videoUrl &&
        widget.videoInfo.videoUrl.isNotEmpty) {
      _setup(widget.videoInfo.videoUrl, widget.autoPlay);
    } else if (widget.autoPlay != oldWidget.autoPlay) {
      widget.autoPlay ? resume() : pause();
    }
  }

  Future<void> prefetchPlayableUrl({bool playIfReady = false}) async {}

  Future<void> _setup(String url, bool autoPlay) async {
    if (url.isEmpty) return;
    final old = _controller;
    final next = VideoPlayerController.networkUrl(Uri.parse(url));
    setState(() => _isLoading = true);
    try {
      await next.initialize();
      if (!mounted) {
        await next.dispose();
        return;
      }
      await old?.dispose();
      _controller = next;
      if (autoPlay) {
        await _controller!.play();
      }
      _controller!.addListener(_onPlayerTick);
      setState(() => _isLoading = false);
    } catch (e) {
      _lastError = e.toString();
      await next.dispose();
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _onPlayerTick() {
    final c = _controller;
    if (c == null) return;
    final value = c.value;
    if (value.position >= value.duration && value.duration > Duration.zero) {
      widget.onCompleted?.call();
    }
  }

  void pause() {
    _controller?.pause();
  }

  void resume() {
    _controller?.play();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onPlayerTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: Colors.black),
        if (_isLoading || controller == null || !controller.value.isInitialized)
          const Center(
            child: CircularProgressIndicator(color: Colors.white),
          )
        else
          Center(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio == 0
                  ? 9 / 16
                  : controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          ),
        if (widget.overlayBuilder != null)
          widget.overlayBuilder!(context, widget.videoInfo),
        if (widget.topOverlayBuilder != null)
          widget.topOverlayBuilder!(context, widget.videoInfo),
        if (_lastError != null)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _lastError!,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
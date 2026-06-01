import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter_aliplayer/flutter_aliplayer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/player_state.dart';
import 'episode_sheet.dart';
import 'player_controller.dart';

/// ============================================================================
/// 视频播放器核心组件
///
/// 【功能说明】
/// 阿里云播放器封装，提供完整的视频播放体验：
/// - 视频播放控制（播放/暂停/停止）
/// - 手势控制（亮度、音量、进度）
/// - 控制栏显示/隐藏
/// - 锁定屏幕功能
/// - 选集面板按钮
///
/// 【使用场景】
/// - PlayerPage（播放器页面）的核心播放器
///
/// 【手势说明】
/// - 单击：显示/隐藏控制栏
/// - 双击：播放/暂停
/// - 左侧上下滑：调节亮度
/// - 右侧上下滑：调节音量
///
/// 【组成部分】
/// - AliPlayerWidget: 阿里云播放器视图（仅 isActive 时渲染）
/// - _LoadingOverlay: 加载中遮罩
/// - _ErrorOverlay: 错误提示遮罩
/// - _GestureHintOverlay: 手势提示遮罩（亮度/音量）
/// - _ControlsOverlay: 控制栏遮罩
///   - _TopBar: 顶部栏（返回、标题、锁定）
///   - _BottomBar: 底部栏（进度条、播放控制、倍速、全屏）
///
/// 【如何修改】
/// - 修改控制栏样式：修改 _ControlsOverlay 及其子组件
/// - 修改手势行为：修改 GestureDetector 的回调
/// - 修改加载/错误提示：修改 _LoadingOverlay 和 _ErrorOverlay
/// ============================================================================
class PlayerWidget extends ConsumerStatefulWidget {
  const PlayerWidget({
    super.key,
    required this.args,
    required this.isActive,
    this.onEpisodeTap,
  });

  final PlayerArgs args;
  final bool isActive;
  final VoidCallback? onEpisodeTap;

  @override
  ConsumerState<PlayerWidget> createState() => _PlayerWidgetState();
}

class _PlayerWidgetState extends ConsumerState<PlayerWidget> {
  late final AliPlayerWidgetController _aliController;
  double _dragStartY = 0;
  double _dragStartValue = 0;
  bool _isLeftDrag = false;
  bool _isRightDrag = false;

  @override
  void initState() {
    super.initState();
    _aliController = AliPlayerWidgetController(context);
    final videoSource = VideoSourceFactory.createUrlSource(widget.args.videoUrl);
    final data = AliPlayerWidgetData(
      videoSource: videoSource,
      coverUrl: widget.args.coverUrl ?? '',
      videoTitle: widget.args.title,
    );
    _aliController.configure(data);
  }

  @override
  void dispose() {
    _aliController.destroy();
    super.dispose();
  }

  void _handleTap() {
    final controller = ref.read(playerControllerProvider(widget.args).notifier);
    final state = ref.read(playerControllerProvider(widget.args));
    if (state.isLocked) {
      controller.showControls();
    } else if (state.showControls) {
      controller.hideControls();
    } else {
      controller.showControls();
    }
  }

  void _handleDoubleTap() {
    final controller = ref.read(playerControllerProvider(widget.args).notifier);
    final state = ref.read(playerControllerProvider(widget.args));
    if (!state.isLocked) controller.togglePlay();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playerControllerProvider(widget.args));
    final controller = ref.read(playerControllerProvider(widget.args).notifier);
    final size = MediaQuery.sizeOf(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        // 播放器视图（AliPlayerWidget — aliplayer_widget 高级封装）
        if (widget.isActive)
          Positioned.fill(
            child: Container(color: Colors.black, child: AliPlayerWidget(_aliController)),
          )
        else
          Container(color: Colors.black),

        // 封面兜底
        if (!widget.isActive || !state.isPlaying)
          Positioned.fill(
            child: widget.args.coverUrl != null
                ? Image.network(widget.args.coverUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: Colors.grey[900]))
                : Container(color: Colors.grey[900]),
          ),

        // 手势层（AliPlayerWidget 内已封装手势，额外叠加亮度和音量控制）
        Positioned.fill(
          child: GestureDetector(
            onTap: _handleTap,
            onDoubleTap: _handleDoubleTap,
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (details) {
              if (state.isLocked) return;
              final dx = details.localPosition.dx;
              _dragStartY = details.localPosition.dy;
              if (dx < size.width * 0.35) {
                _isLeftDrag = true;
                _isRightDrag = false;
                _dragStartValue = state.brightness;
              } else if (dx > size.width * 0.65) {
                _isRightDrag = true;
                _isLeftDrag = false;
                _dragStartValue = state.volume;
              } else {
                _isLeftDrag = false;
                _isRightDrag = false;
              }
            },
            onVerticalDragUpdate: (details) {
              if (state.isLocked) return;
              final delta = _dragStartY - details.localPosition.dy;
              if (_isLeftDrag) {
                controller.setBrightness(_dragStartValue + delta / size.height);
              } else if (_isRightDrag) {
                controller.setVolume(_dragStartValue + delta / size.height);
              }
            },
            onVerticalDragEnd: (_) {
              _isLeftDrag = false;
              _isRightDrag = false;
            },
          ),
        ),

        // 加载中
        if (state.isBuffering) const _LoadingOverlay(),

        // 错误提示
        if (state.hasError)
          _ErrorOverlay(
            message: state.errorMessage ?? 'Playback error',
            onRetry: () => controller.loadVideo(state.videoUrl),
          ),

        // 手势提示（亮度/音量）
        if (state.gestureHint != null)
          _GestureHintOverlay(hint: state.gestureHint!),

        // 控制栏
        AnimatedOpacity(
          opacity: state.showControls || state.isLocked ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(
            ignoring: !state.showControls && !state.isLocked,
            child: _ControlsOverlay(
              state: state,
              controller: controller,
              onEpisodeTap: widget.onEpisodeTap,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: Colors.white));
  }
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black54,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _GestureHintOverlay extends StatelessWidget {
  const _GestureHintOverlay({required this.hint});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
        child: Text(hint, style: const TextStyle(color: Colors.white, fontSize: 18)),
      ),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({
    required this.state,
    required this.controller,
    this.onEpisodeTap,
  });

  final PlayerState state;
  final PlayerController controller;
  final VoidCallback? onEpisodeTap;

  String _formatDuration(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _TopBar(
            title: state.title,
            isLocked: state.isLocked,
            onBack: () => Navigator.of(context).maybePop(),
            onLockToggle: controller.toggleLock,
          ),
        ),
        if (!state.isLocked && !state.isPlaying && !state.isBuffering)
          Center(
            child: IconButton(
              iconSize: 64,
              color: Colors.white,
              onPressed: controller.togglePlay,
              icon: const Icon(Icons.play_circle_fill),
            ),
          ),
        // 右侧操作按钮（点赞、收藏、分享+选集）- 抖音风格纵向排列
        if (!state.isLocked)
          Positioned(
            right: 12,
            bottom: 215,
            child: _DouyinActionColumn(
              onEpisodeTap: onEpisodeTap,
              episodeCount: controller.allEpisodes.length,
              currentIndex: controller.currentIndex + 1,
            ),
          ),
        if (!state.isLocked)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              state: state,
              controller: controller,
              formatDuration: _formatDuration,
            ),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.isLocked,
    required this.onBack,
    required this.onLockToggle,
  });

  final String title;
  final bool isLocked;
  final VoidCallback onBack;
  final VoidCallback onLockToggle;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Container(
      padding: EdgeInsets.only(top: padding.top + 8, left: 8, right: 8, bottom: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: onBack),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(icon: Icon(isLocked ? Icons.lock : Icons.lock_open, color: Colors.white), onPressed: onLockToggle),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.state,
    required this.controller,
    required this.formatDuration,
  });

  final PlayerState state;
  final PlayerController controller;
  final String Function(int ms) formatDuration;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return Container(
      padding: EdgeInsets.only(left: 12, right: 12, bottom: padding.bottom + 12, top: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 264,
            child: _BufferedSlider(
              value: state.progress,
              bufferedValue: state.bufferedProgress,
              onChangeStart: (_) => controller.showControls(),
              onChanged: (v) => controller.seekToProgress(v),
              onChangeEnd: (_) => controller.showControls(),
            ),
          ),
          const SizedBox(width: 8),
          Text(formatDuration(state.positionMs), style: const TextStyle(color: Colors.white, fontSize: 12)),
          const Text(' / ', style: TextStyle(color: Colors.white54)),
          Text(formatDuration(state.durationMs), style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      ),
    );
  }
}

// _EpisodeNavBar removed (no longer used)

/// 抖音风格右侧操作按钮列（点赞、收藏、分享+选集）
class _DouyinActionColumn extends StatelessWidget {
  const _DouyinActionColumn({
    required this.onEpisodeTap,
    required this.episodeCount,
    required this.currentIndex,
  });

  final VoidCallback? onEpisodeTap;
  final int episodeCount;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DouyinActionBtn(icon: Icons.favorite, label: '999+', onTap: () {}),
        const SizedBox(height: 20),
        _DouyinActionBtn(icon: Icons.star, label: '999+', onTap: () {}),
        const SizedBox(height: 20),
        _DouyinActionBtn(icon: Icons.share, label: '999+', onTap: () {}),
        const SizedBox(height: 20),
        _DouyinEpisodeBtn(
          currentIndex: currentIndex,
          total: episodeCount,
          onTap: onEpisodeTap ?? () {},
        ),
      ],
    );
  }
}

class _DouyinActionBtn extends StatelessWidget {
  const _DouyinActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              shadows: [Shadow(blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

/// 选集按钮：图标在上，Episode 文字在下
class _DouyinEpisodeBtn extends StatelessWidget {
  const _DouyinEpisodeBtn({
    required this.currentIndex,
    required this.total,
    required this.onTap,
  });

  final int currentIndex;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: Colors.black38,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.list, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            'Episode',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              shadows: [Shadow(blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom slider that paints a buffered (grey) region behind the playhead.
class _BufferedSlider extends StatelessWidget {
  const _BufferedSlider({
    required this.value,
    required this.bufferedValue,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double value;
  final double bufferedValue;
  final ValueChanged<double> onChangeStart;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        trackShape: _BufferedTrackShape(bufferedValue: bufferedValue),
      ),
      child: Slider(
        value: value,
        onChangeStart: onChangeStart,
        onChanged: onChanged,
        onChangeEnd: onChangeEnd,
        activeColor: Colors.white,
        inactiveColor: Colors.transparent,
      ),
    );
  }
}

class _BufferedTrackShape extends SliderTrackShape {
  const _BufferedTrackShape({required this.bufferedValue});

  final double bufferedValue;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    return Rect.fromLTWH(offset.dx, trackTop, parentBox.size.width, trackHeight);
  }

  @override
  void paint(
    Painting context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
  }) {
    final canvas = context.canvas;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final bufferedFraction = bufferedValue.clamp(0.0, 1.0);
    final bufferedRight = trackRect.left + trackRect.width * bufferedFraction;
    final playedRight = thumbCenter.dx;

    final inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.white38
      ..style = PaintingStyle.fill;

    final activePaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? Colors.white
      ..style = PaintingStyle.fill;

    final rRadius = trackRect.height / 2;

    // Buffered region (full track)
    final bufferedRect = RRect.fromRectAndRadius(trackRect, Radius.circular(rRadius));
    canvas.drawRRect(bufferedRect, inactivePaint);

    // Active/played region
    if (playedRight > trackRect.left) {
      final activeRect = Rect.fromLTRB(
        trackRect.left,
        trackRect.top,
        playedRight.clamp(trackRect.left, trackRect.right),
        trackRect.bottom,
      );
      final activeRRect = RRect.fromRectAndCorners(
        activeRect,
        topLeft: Radius.circular(rRadius),
        bottomLeft: Radius.circular(rRadius),
        topRight: playedRight >= trackRect.right ? Radius.circular(rRadius) : Radius.zero,
        bottomRight: playedRight >= trackRect.right ? Radius.circular(rRadius) : Radius.zero,
      );
      canvas.drawRRect(activeRRect, activePaint);
    }
  }
}

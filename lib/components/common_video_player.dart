import 'package:aliplayer_widget/aliplayer_widget_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_aliplayer/flutter_aliplayer.dart';
import 'package:flutter_aliplayer/flutter_aliplayer_factory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/constants/api_error_code.dart';
import '../features/payment/widgets/vip_paywall_overlay.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/payment/providers/membership_provider.dart';
import '../features/recommend/utils/drama_navigation.dart';
import '../l10n/app_localizations.dart';
import 'rtl_back_button.dart';

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

/// Common video player component.
///
/// Supports two modes:
/// - Recommend mode (`isFullscreen=false`): AliPlayerWidget with overlay actions
/// - Fullscreen mode (`isFullscreen=true`): FlutterAliplayer with full controls
class CommonVideoPlayer extends ConsumerStatefulWidget {
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
  /// 剧集级别 VIP 标识（整部剧是否 VIP-only）
  final bool isVipOnly;
  /// 当前集是否可播放（0=需解锁，1=可播放），来自 getEpisodeInfo
  final int isCanPlay;
  /// 是否 VIP 专属内容，来自 getEpisodeInfo
  final int isVip;
  /// 切换剧集时的回调，用于通知父组件
  final void Function(int index)? onEpisodeChanged;

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
    /// 默认为 1（可播放），0 表示需要解锁
    this.isCanPlay = 1,
    /// 默认为 0（非 VIP 专属），1 表示 VIP 专属
    this.isVip = 0,
    this.onEpisodeChanged,
  });

  @override
  ConsumerState<CommonVideoPlayer> createState() => _CommonVideoPlayerState();
}

class _CommonVideoPlayerState extends ConsumerState<CommonVideoPlayer> {
  VideoQuality _currentQuality = VideoQuality.sd;

  @override
  Widget build(BuildContext context) {
    if (widget.isFullscreen) {
      return _FullscreenPlayerView(
        videoUrl: widget.videoUrl,
        videoId: widget.videoId,
        title: widget.title ?? '',
        coverUrl: widget.coverUrl,
        allEpisodes: widget.allEpisodes,
        currentIndex: widget.currentIndex,
        videoUrlOne: widget.videoUrlOne,
        videoUrlTwo: widget.videoUrlTwo,
        isVipOnly: widget.isVipOnly,
        isCanPlay: widget.isCanPlay,
        isVip: widget.isVip,
        onEpisodeChanged: widget.onEpisodeChanged,
        initialProgress: widget.initialProgress,
        autoPlay: widget.autoPlay,
        onBackPressed: widget.onBackPressed,
        currentQuality: _currentQuality,
        onQualityChanged: (q) => setState(() => _currentQuality = q),
      );
    }
    return _RecommendPlayerView(
      videoUrl: widget.videoUrl,
      videoId: widget.videoId,
      coverUrl: widget.coverUrl,
      autoPlay: widget.autoPlay,
      onBackPressed: widget.onBackPressed,
    );
  }
}

// ============================================================================
// 推荐页模式 — 使用 AliPlayerWidget (SceneType.listPlayer)
// ============================================================================

class _RecommendPlayerView extends StatefulWidget {
  const _RecommendPlayerView({
    required this.videoUrl,
    required this.videoId,
    this.coverUrl,
    this.autoPlay = false,
    this.onBackPressed,
  });

  final String videoUrl;
  final String videoId;
  final String? coverUrl;
  final bool autoPlay;
  final VoidCallback? onBackPressed;

  @override
  State<_RecommendPlayerView> createState() => _RecommendPlayerViewState();
}

class _RecommendPlayerViewState extends State<_RecommendPlayerView> {
  late AliPlayerWidgetController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AliPlayerWidgetController(context);
    final videoSource = VideoSourceFactory.createUrlSource(widget.videoUrl);
    final data = AliPlayerWidgetData(
      sceneType: SceneType.listPlayer,
      videoSource: videoSource,
      autoPlay: widget.autoPlay,
    );
    _controller.configure(data);
  }

  @override
  void dispose() {
    _controller.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AliPlayerWidget(
      _controller,
      slotBuilders: {
        SlotType.topBar: (context) => _buildTopBar(context),
      },
      hiddenSlotElements: {
        SlotType.topBar: {'back', 'snapshot', 'settings'},
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return PositionedDirectional(
      top: 0,
      start: 0,
      end: 0,
      child: Container(
        padding: EdgeInsetsDirectional.only(
          top: MediaQuery.paddingOf(context).top + 8,
          start: 8,
          end: 8,
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
            if (widget.onBackPressed != null)
              RtlBackButton(
                color: Colors.white,
                onPressed: widget.onBackPressed,
              ),
            Expanded(
              child: Text(
                widget.videoId,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 全屏模式 — 使用 FlutterAliplayerFactory
// ============================================================================

class _FullscreenPlayerView extends ConsumerStatefulWidget {
  const _FullscreenPlayerView({
    required this.videoUrl,
    required this.videoId,
    required this.title,
    this.coverUrl,
    required this.allEpisodes,
    required this.currentIndex,
    this.videoUrlOne,
    this.videoUrlTwo,
    required this.isVipOnly,
    required this.isCanPlay,
    required this.isVip,
    this.initialProgress,
    required this.autoPlay,
    this.onBackPressed,
    required this.currentQuality,
    required this.onQualityChanged,
    this.onEpisodeChanged,
  });

  final String videoUrl;
  final String videoId;
  final String title;
  final String? coverUrl;
  final List<CommonEpisode> allEpisodes;
  final int currentIndex;
  final String? videoUrlOne;
  final String? videoUrlTwo;
  final bool isVipOnly;
  final int isCanPlay;
  final int isVip;
  final void Function(int index)? onEpisodeChanged;
  final Duration? initialProgress;
  final bool autoPlay;
  final VoidCallback? onBackPressed;
  final VideoQuality currentQuality;
  final void Function(VideoQuality) onQualityChanged;

  @override
  ConsumerState<_FullscreenPlayerView> createState() => _FullscreenPlayerViewState();
}

class _FullscreenPlayerViewState extends ConsumerState<_FullscreenPlayerView> {
  late FlutterAliplayer _player;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _hasError = false;
  String? _errorMessage;
  int _positionMs = 0;
  int _durationMs = 0;
  bool _showControls = true;
  /// 当前集是否被锁定（isCanPlay=0 或 404 错误）
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _player = FlutterAliPlayerFactory.createAliPlayer();
    _setupListeners();
    // 根据 API 返回的 isCanPlay 和 isVip 判断是否锁定
    _isLocked = widget.isCanPlay == 0 || widget.isVip == 1;
  }

  @override
  void didUpdateWidget(_FullscreenPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换集数时更新锁定状态，如果变为锁定则停止播放
    final wasLocked = oldWidget.isCanPlay == 0 || oldWidget.isVip == 1;
    final nowLocked = widget.isCanPlay == 0 || widget.isVip == 1;
    if (nowLocked && !wasLocked) {
      _player.stop();
    }
    _isLocked = nowLocked;
  }

  @override
  void dispose() {
    _player.stop();
    _player.release();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _setupListeners() {
    _player.setOnPrepared((_) async {
      final duration = await _player.getDuration();
      if (!mounted) return;
      setState(() {
        _durationMs = duration;
        _isBuffering = false;
      });
      if (widget.autoPlay) {
        _player.play();
      }
      if (widget.initialProgress != null &&
          widget.initialProgress!.inMilliseconds > 0) {
        _player.seekTo(
            widget.initialProgress!.inMilliseconds, FlutterAvpdef.ACCURATE);
      }
    });

    _player.setOnRenderingStart((_) {
      if (mounted) setState(() => _isPlaying = true);
    });

    _player.setOnStateChanged((newState, _) {
      if (!mounted) return;
      switch (newState) {
        case FlutterAvpdef.started:
          setState(() => _isPlaying = true);
          break;
        case FlutterAvpdef.paused:
          setState(() => _isPlaying = false);
          break;
        case FlutterAvpdef.stopped:
          setState(() => _isPlaying = false);
          break;
        default:
          break;
      }
    });

    _player.setOnLoadingStatusListener(
      loadingBegin: (_) {
        if (mounted) setState(() => _isBuffering = true);
      },
      loadingProgress: (_, __, ___) {
        if (mounted) setState(() => _isBuffering = true);
      },
      loadingEnd: (_) {
        if (mounted) setState(() => _isBuffering = false);
      },
    );

    _player.setOnInfo((code, extra, _, __) {
      if (code == InfoCode.CURRENTPOSITION &&
          extra != null &&
          mounted) {
        setState(() => _positionMs = extra);
      }
    });

    _player.setOnError((code, extra, msg, _) {
      if (mounted) {
        // 404 错误视为锁定状态
        final is404 = (msg ?? '').contains('404') ||
            (extra ?? '').contains('404') ||
            code == ApiErrorCode.videoNotFound;
        if (is404) {
          setState(() => _isLocked = true);
        } else {
          setState(() {
            _hasError = true;
            _errorMessage = msg ?? 'Playback error';
          });
        }
      }
    });
  }

  void _loadUrl(String url) {
    _player.setAutoPlay(widget.autoPlay);
    _player.setUrl(url);
    _player.prepare();
  }

  void _onViewCreated(int viewId) {
    _player.setPlayerView(viewId);
    _loadUrl(_urlForQuality(widget.currentQuality));
  }

  String _urlForQuality(VideoQuality q) {
    switch (q) {
      case VideoQuality.sd:
        return widget.videoUrl;
      case VideoQuality.hd:
        return widget.videoUrlOne ?? widget.videoUrl;
      case VideoQuality.fhd:
        return widget.videoUrlTwo ?? widget.videoUrlOne ?? widget.videoUrl;
    }
  }

  void _switchQuality(VideoQuality q) {
    if (q == widget.currentQuality) return;
    final url = _urlForQuality(q);
    _player.stop();
    _loadUrl(url);
    widget.onQualityChanged(q);
  }

  void _togglePlay() {
    if (_isLocked) {
      return;
    }
    if (_isPlaying) {
      _player.pause();
    } else {
      if (_positionMs >= _durationMs && _durationMs > 0) {
        _player.seekTo(0, FlutterAvpdef.ACCURATE);
      }
      _player.play();
    }
  }

  Future<void> _handleUnlock() async {
    final purchased = await openMembershipPage(
      context,
      ref,
      showLoginPrompt: false,
    );
    if (!mounted || !purchased) return;

    await ref.read(memberStateProvider.notifier).refreshStatus();
    if (!mounted) return;

    setState(() {
      _isLocked = false;
      _hasError = false;
      _errorMessage = null;
    });

    _loadUrl(_urlForQuality(widget.currentQuality));
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  String _formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 手势层 — 点击切换控制栏显示，双击播放/暂停
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleControls,
              onDoubleTap: _togglePlay,
              behavior: HitTestBehavior.opaque,
            ),
          ),

          // 播放器画面
          AliPlayerView(
            onCreated: (viewId) => _onViewCreated(viewId),
            x: 0,
            y: 0,
            width: MediaQuery.sizeOf(context).width,
            height: MediaQuery.sizeOf(context).height,
            aliPlayerViewType: AliPlayerViewTypeForAndroid.textureview,
          ),

          // 封面兜底
          if (!_isPlaying && !_isBuffering && widget.coverUrl != null)
            Positioned.fill(
              child: Image.network(
                widget.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: Colors.grey[900]),
              ),
            ),

          // 加载中
          if (_isBuffering)
            const Center(
                child: CircularProgressIndicator(color: Colors.white)),

          // 错误提示
          if (_hasError)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 48),
                  const SizedBox(height: 12),
                  Text(_errorMessage ?? 'Playback error',
                      style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      setState(() => _hasError = false);
                      _loadUrl(_urlForQuality(widget.currentQuality));
                    },
                    child: Text(AppLocalizations.of(context).retry),
                  ),
                ],
              ),
            ),

          // VIP 解锁弹层（isCanPlay=0 或 isVip=1 或 404 错误时显示）
          if (_isLocked)
            VipPaywallOverlay(
              title: widget.title.isNotEmpty
                  ? widget.title
                  : AppLocalizations.of(context).playerVipContent,
              onUnlock: _handleUnlock,
              canClose: false,
            ),

          // 播放按钮（暂停时显示）
          if (!_isPlaying && !_isBuffering && !_hasError)
            Center(
              child: IconButton(
                iconSize: 64,
                color: Colors.white,
                onPressed: _togglePlay,
                icon: const Icon(Icons.play_circle_fill),
              ),
            ),

          // 顶部栏
          if (_showControls) _buildTopBar(context),

          // 右侧操作列
          if (_showControls)
            _buildActionColumn(context),

          // 底部进度条
          if (_showControls) _buildBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return PositionedDirectional(
      top: 0,
      start: 0,
      end: 0,
      child: Container(
        padding: EdgeInsetsDirectional.only(
          top: MediaQuery.paddingOf(context).top + 8,
          start: 8,
          end: 8,
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
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: widget.onBackPressed ?? () => context.pop(),
            ),
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionColumn(BuildContext context) {
    return PositionedDirectional(
      end: 12,
      bottom: 120,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionBtn(icon: Icons.favorite, label: '999+', onTap: () {}),
          const SizedBox(height: 20),
          _ActionBtn(icon: Icons.star, label: '999+', onTap: () {}),
          const SizedBox(height: 20),
          _ActionBtn(icon: Icons.share, label: 'Share', onTap: () {}),
          const SizedBox(height: 20),
          _QualityBtn(
            currentQuality: widget.currentQuality,
            onQualityChanged: _switchQuality,
            videoUrlOne: widget.videoUrlOne,
            videoUrlTwo: widget.videoUrlTwo,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => _showEpisodeSheet(context),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                      color: Colors.black38, shape: BoxShape.circle),
                  child:
                      const Icon(Icons.list, color: Colors.white, size: 28),
                ),
                const SizedBox(height: 4),
                Text(AppLocalizations.of(context).episode,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        shadows: [Shadow(blurRadius: 4)])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final progress =
        _durationMs > 0 ? (_positionMs / _durationMs).clamp(0.0, 1.0) : 0.0;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: padding.bottom + 16,
          top: 24,
        ),
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
              icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white),
              onPressed: _togglePlay,
            ),
            Text(_formatDuration(_positionMs),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white38,
                  thumbColor: Colors.white,
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: progress,
                  onChanged: (v) {
                    _player.seekTo((v * _durationMs).round(),
                        FlutterAvpdef.ACCURATE);
                    setState(() => _positionMs = (v * _durationMs).round());
                  },
                ),
              ),
            ),
            Text(_formatDuration(_durationMs),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  void _showEpisodeSheet(BuildContext context) {
    final authState = ref.read(authProvider);
    final memberState = ref.read(memberStateProvider);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _CommonEpisodeSheet(
        episodes: widget.allEpisodes,
        currentIndex: widget.currentIndex,
        isVipOnly: widget.isVipOnly,
        authState: authState,
        memberState: memberState,
        onEpisodeTap: (index) {
          Navigator.pop(sheetContext);
          widget.onEpisodeChanged?.call(index);
        },
        onUnlock: () async {
          Navigator.pop(sheetContext);
          final purchased = await openMembershipPage(
            context,
            ref,
            showLoginPrompt: false,
          );
          if (!mounted || !purchased) return;

          await ref.read(memberStateProvider.notifier).refreshStatus();
          if (!mounted) return;

          final refreshedMemberState = ref.read(memberStateProvider);
          if (widget.currentIndex >= 0 && widget.currentIndex < widget.allEpisodes.length) {
            final currentEpisode = widget.allEpisodes[widget.currentIndex];
            if (currentEpisode.isUnlocked || (refreshedMemberState.isVip && !refreshedMemberState.isExpired)) {
              widget.onEpisodeChanged?.call(widget.currentIndex);
            }
          }
        },
      ),
    );
  }
}

class _CommonEpisodeSheet extends StatelessWidget {
  const _CommonEpisodeSheet({
    required this.episodes,
    required this.currentIndex,
    required this.onEpisodeTap,
    required this.isVipOnly,
    this.authState,
    this.memberState,
    this.onUnlock,
  });

  final List<CommonEpisode> episodes;
  final int currentIndex;
  final void Function(int index) onEpisodeTap;
  final bool isVipOnly;
  final AuthState? authState;
  final MemberState? memberState;
  final VoidCallback? onUnlock;

  bool _isLockedForCurrentUser(CommonEpisode episode) {
    if (episode.isUnlocked) return false;
    if (!isVipOnly) return false;

    final isGuest =
        authState == null || !authState!.isAuthenticated || authState!.user?.isGuest == true;
    if (isGuest) return true;

    final needsVip = memberState == null || !memberState!.isVip || memberState!.isExpired;
    return needsVip;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsetsDirectional.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade400,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(
                  'Episodes',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${episodes.length} Episodes',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 32),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.0,
              ),
              itemCount: episodes.length,
              itemBuilder: (context, index) {
                final episode = episodes[index];
                final isCurrent = index == currentIndex;
                final isLocked = _isLockedForCurrentUser(episode);

                return GestureDetector(
                  onTap: () {
                    if (isLocked) {
                      _showLockedDialog(context, index);
                    } else {
                      onEpisodeTap(index);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: isCurrent
                          ? Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            )
                          : null,
                    ),
                    child: Center(
                      child: isLocked
                          ? Icon(
                              Icons.lock_rounded,
                              color: Colors.grey.shade600,
                              size: 24,
                            )
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isCurrent
                                    ? Colors.white
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showLockedDialog(BuildContext context, int episodeIndex) {
    final l10n = AppLocalizations.of(context);
    final isGuest =
        authState == null || !authState!.isAuthenticated || authState!.user?.isGuest == true;

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(isGuest ? l10n.loginRequiredTitle : l10n.vipRequiredTitle),
        content: Text(
          isGuest
              ? 'Episode ${episodeIndex + 1} is locked. Please login to continue.'
              : 'Episode ${episodeIndex + 1} requires VIP membership.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onUnlock?.call();
            },
            child: Text(isGuest ? 'Login' : 'Subscribe'),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
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
                color: Colors.black38, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  shadows: [Shadow(blurRadius: 4)])),
        ],
      ),
    );
  }
}

class _QualityBtn extends StatelessWidget {
  const _QualityBtn({
    required this.currentQuality,
    required this.onQualityChanged,
    this.videoUrlOne,
    this.videoUrlTwo,
  });

  final VideoQuality currentQuality;
  final void Function(VideoQuality) onQualityChanged;
  final String? videoUrlOne;
  final String? videoUrlTwo;

  String _label(VideoQuality q) {
    switch (q) {
      case VideoQuality.sd:
        return 'SD';
      case VideoQuality.hd:
        return 'HD';
      case VideoQuality.fhd:
        return 'FHD';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
                color: Colors.black38, shape: BoxShape.circle),
            child: Text(
              _label(currentQuality),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          Text(l10n.quality,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  shadows: [Shadow(blurRadius: 4)])),
        ],
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QualitySheet(
        currentQuality: currentQuality,
        onQualityChanged: (q) {
          Navigator.pop(ctx);
          onQualityChanged(q);
        },
        hasHd: videoUrlOne != null && videoUrlOne!.isNotEmpty,
        hasFhd: videoUrlTwo != null && videoUrlTwo!.isNotEmpty,
      ),
    );
  }
}

class _QualitySheet extends StatelessWidget {
  const _QualitySheet({
    required this.currentQuality,
    required this.onQualityChanged,
    required this.hasHd,
    required this.hasFhd,
  });

  final VideoQuality currentQuality;
  final void Function(VideoQuality) onQualityChanged;
  final bool hasHd;
  final bool hasFhd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsetsDirectional.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.shade400,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text(l10n.selectQuality,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text(_label(currentQuality),
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
              ],
            ),
          ),
          _qualityTile(context, VideoQuality.sd, 'SD', l10n.qualityStandard, currentQuality,
              onQualityChanged),
          _qualityTile(context, VideoQuality.hd, 'HD', l10n.qualityHigh, currentQuality,
              onQualityChanged, enabled: hasHd),
          _qualityTile(context, VideoQuality.fhd, 'FHD', l10n.qualityFullHd, currentQuality,
              onQualityChanged, enabled: hasFhd),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  String _label(VideoQuality q) {
    switch (q) {
      case VideoQuality.sd:
        return 'SD';
      case VideoQuality.hd:
        return 'HD';
      case VideoQuality.fhd:
        return 'FHD';
    }
  }

  Widget _qualityTile(
    BuildContext context,
    VideoQuality q,
    String label,
    String desc,
    VideoQuality current,
    void Function(VideoQuality) onTap, {
    bool enabled = true,
  }) {
    final l10n = AppLocalizations.of(context);
    final selected = q == current;
    return ListTile(
      leading:
          Icon(Icons.check_circle, color: selected ? Colors.blue : Colors.transparent),
      title: Text(label,
          style: TextStyle(
              fontWeight: FontWeight.bold, color: enabled ? null : Colors.grey)),
      subtitle: Text(desc,
          style: TextStyle(
              color: enabled ? Colors.grey : Colors.grey.shade400, fontSize: 12)),
      trailing: enabled
          ? null
          : Text(l10n.unavailable,
              style: const TextStyle(color: Colors.grey, fontSize: 12)),
      onTap: enabled ? () => onTap(q) : null,
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_aliplayer/flutter_aliplayer.dart';
import 'package:flutter_aliplayer/flutter_aliplayer_factory.dart' show AliPlayerView, AliPlayerViewTypeForAndroid, FlutterAliPlayerFactory;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';

import '../domain/player_state.dart';
import 'episode_sheet.dart';
import 'player_controller.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';

/// ============================================================================
/// 全屏播放器页面
///
/// 架构：
/// - PageView.builder 负责上下滑动
/// - 每个 page 包含 AliPlayerView（仅当前页 active 时渲染）
/// - 独立的播放器实例管理 (_EpisodePlayer)
/// - VIP 剧：前3集免费，后续集数需要登录/VIP
/// ============================================================================
class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    super.key,
    required this.videoUrl,
    required this.title,
    this.dramaId,
    this.allEpisodes = const [],
    this.currentIndex = 0,
    this.coverUrl,
    this.isVipOnly = false,
    this.videoUrlOne,
    this.videoUrlTwo,
  });

  final String videoUrl;
  final String title;
  final String? dramaId;
  final List<EpisodeData> allEpisodes;
  final int currentIndex;
  final String? coverUrl;
  /// Whether the drama is VIP-only. Determines if locked episodes
  /// require login/VIP check before playback.
  final bool isVipOnly;
  final String? videoUrlOne;
  final String? videoUrlTwo;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late PageController _pageController;
  late List<EpisodeData> _episodes;
  int _currentIndex = 0;
  bool _initialized = false;
  VideoQuality _currentQuality = VideoQuality.sd;

  // 每个 episode 对应一个播放器实例
  final Map<String, _EpisodePlayer> _players = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
    _episodes = widget.allEpisodes;
    // 短视频直接跳转时没有 episodes，用传入的 URL 构造单集
    if (_episodes.isEmpty && widget.videoUrl.isNotEmpty) {
      _episodes = [
        EpisodeData(
          id: 'single_${DateTime.now().millisecondsSinceEpoch}',
          title: widget.title,
          videoUrl: widget.videoUrl,
          coverUrl: widget.coverUrl,
          isUnlocked: true,
        ),
      ];
    }
    _pageController = PageController(initialPage: _currentIndex);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    // 初始化当前集数的播放器
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_episodes.isNotEmpty) {
        _ensurePlayer(_currentIndex);
      }
    });
  }

  @override
  void dispose() {
    _disposeAllPlayers();
    _pageController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _disposeAllPlayers() {
    for (final p in _players.values) {
      p.dispose();
    }
    _players.clear();
  }

  _EpisodePlayer _getPlayer(int index) {
    final episode = _episodes[index];
    if (!_players.containsKey(episode.id)) {
      _players[episode.id] = _EpisodePlayer(
        episode: episode,
        onStateChanged: (playing, loading) {
          if (mounted) setState(() {});
        },
      );
    }
    return _players[episode.id]!;
  }

  void _ensurePlayer(int index) {
    if (index < 0 || index >= _episodes.length) return;
    final episode = _episodes[index];

    // 如果是锁定集，先检查权限
    if (!episode.isUnlocked && widget.isVipOnly) {
      _showLockedEpisodeDialog(index);
      return;
    }

    if (!_players.containsKey(episode.id)) {
      _players[episode.id] = _EpisodePlayer(
        episode: episode,
        onStateChanged: (_, __) {},
      );
    }
    // 播放
    _players[episode.id]!.play();
  }

  void _showLockedEpisodeDialog(int index) {
    final authState = ref.read(authProvider);
    final memberState = ref.read(memberStateProvider);

    final bool isGuest = !authState.isAuthenticated || authState.user?.isGuest == true;
    final bool needsVip = !memberState.isVip || memberState.isExpired;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isGuest ? 'Login Required' : 'VIP Required'),
        content: Text(
          isGuest
              ? 'Please login to continue watching Episode ${index + 1}.'
              : 'Episode ${index + 1} requires VIP membership.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (isGuest) {
                context.push('/login');
              } else {
                context.push('/membership');
              }
            },
            child: Text(isGuest ? 'Login' : 'Subscribe'),
          ),
        ],
      ),
    );
  }

  void _onPageChanged(int index) {
    if (index < 0 || index >= _episodes.length) return;

    // 暂停旧视频
    final oldEpisode = _episodes[_currentIndex];
    _players[oldEpisode.id]?.pause();

    setState(() => _currentIndex = index);

    // 播放新视频
    _ensurePlayer(index);

    // 预加载相邻集数
    if (index + 1 < _episodes.length) {
      _ensurePreload(index + 1);
    }
    if (index - 1 >= 0) {
      _ensurePreload(index - 1);
    }

    // 清理超出范围的播放器，防止资源泄漏和原生层冲突
    _prunePlayers(index);
  }

  void _prunePlayers(int activeIndex) {
    final keepIds = <String>{};
    keepIds.add(_episodes[activeIndex].id);
    if (activeIndex - 1 >= 0) keepIds.add(_episodes[activeIndex - 1].id);
    if (activeIndex + 1 < _episodes.length) keepIds.add(_episodes[activeIndex + 1].id);

    final toRemove = _players.keys.where((id) => !keepIds.contains(id)).toList();
    for (final id in toRemove) {
      _players[id]?.dispose();
      _players.remove(id);
    }
  }

  void _ensurePreload(int index) {
    if (index < 0 || index >= _episodes.length) return;
    final episode = _episodes[index];
    if (!_players.containsKey(episode.id)) {
      _players[episode.id] = _EpisodePlayer.preload(
        episode: episode,
        onStateChanged: (_, __) {},
      );
    }
  }

  String _urlForQuality(VideoQuality quality) {
    switch (quality) {
      case VideoQuality.sd:
        return widget.videoUrl;
      case VideoQuality.hd:
        return widget.videoUrlOne ?? widget.videoUrl;
      case VideoQuality.fhd:
        return widget.videoUrlTwo ?? widget.videoUrlOne ?? widget.videoUrl;
    }
  }

  void _switchQuality(VideoQuality quality) {
    if (quality == _currentQuality) return;
    final player = _getPlayer(_currentIndex);
    final url = _urlForQuality(quality);
    player.loadUrl(url);
    setState(() => _currentQuality = quality);
  }

  void _showEpisodeSheet() {
    final authState = ref.read(authProvider);
    final memberState = ref.read(memberStateProvider);
    showEpisodeSheet(
      context,
      episodes: _episodes,
      currentIndex: _currentIndex,
      isVipOnly: widget.isVipOnly,
      authState: authState,
      memberState: memberState,
      onEpisodeTap: (index) {
        Navigator.pop(context);
        if (index == _currentIndex) return;
        // 锁定集先检查权限
        final episode = _episodes[index];
        if (!episode.isUnlocked && widget.isVipOnly) {
          _showLockedEpisodeDialog(index);
          return;
        }
        _pageController.jumpToPage(index);
      },
      onUnlock: (index) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unlock Episode'),
            content: Text('Episode ${index + 1} is locked. Subscribe to watch.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/membership');
                },
                child: const Text('Subscribe'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      _initialized = true;
      // 播放初始集数
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_episodes.isNotEmpty) {
          _ensurePlayer(_currentIndex);
        }
      });
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _episodes.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, index) {
          final episode = _episodes[index];
          final player = _getPlayer(index);
          return _EpisodeCard(
            dramaTitle: widget.title,
            episode: episode,
            player: player,
            isActive: index == _currentIndex,
            onEpisodeTap: _showEpisodeSheet,
            episodes: _episodes,
            currentIndex: _currentIndex,
            currentQuality: _currentQuality,
            onQualityChanged: (quality) => _switchQuality(quality),
            videoUrlOne: widget.videoUrlOne,
            videoUrlTwo: widget.videoUrlTwo,
          );
        },
      ),
    );
  }
}

/// 单个集数卡片
class _EpisodeCard extends StatefulWidget {
  const _EpisodeCard({
    required this.dramaTitle,
    required this.episode,
    required this.player,
    required this.isActive,
    required this.onEpisodeTap,
    required this.episodes,
    required this.currentIndex,
    required this.currentQuality,
    required this.onQualityChanged,
    this.videoUrlOne,
    this.videoUrlTwo,
  });

  final String dramaTitle;
  final EpisodeData episode;
  final _EpisodePlayer player;
  final bool isActive;
  final VoidCallback onEpisodeTap;
  final List<EpisodeData> episodes;
  final int currentIndex;
  final VideoQuality currentQuality;
  final void Function(VideoQuality) onQualityChanged;
  final String? videoUrlOne;
  final String? videoUrlTwo;

  @override
  State<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends State<_EpisodeCard> {
  @override
  void dispose() {
    if (!widget.isActive) {
      widget.player.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 手势层放在最前面，确保 Flutter 先收到触摸事件再传给原生 AliPlayerView
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.player.togglePlay,
            onDoubleTap: widget.player.togglePlay,
            behavior: HitTestBehavior.opaque,
          ),
        ),

        // 阿里云播放器画面
        Container(
          width: MediaQuery.sizeOf(context).width,
          height: MediaQuery.sizeOf(context).height,
          color: Colors.black,
          child: AliPlayerView(
            onCreated: (viewId) => widget.player.attachView(viewId),
            x: 0,
            y: 0,
            width: MediaQuery.sizeOf(context).width,
            height: MediaQuery.sizeOf(context).height,
            aliPlayerViewType: AliPlayerViewTypeForAndroid.textureview,
          ),
        ),

        // 封面兜底（未播放时显示）
        if (!widget.isActive || !widget.player.isPlaying)
          Positioned.fill(
            child: Image.network(
              widget.episode.coverUrl ?? '',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: Colors.grey[900]),
            ),
          ),

        // 顶部导航栏：返回 + 剧名 + EP.X
        _TopBar(
          dramaTitle: widget.dramaTitle,
          currentIndex: widget.currentIndex,
          episodeCount: widget.episodes.length,
        ),

        // 右侧操作列
        Positioned(
          right: 12,
          bottom: 80,
          child: _ActionColumn(
            episodeCount: widget.episodes.length,
            currentIndex: widget.currentIndex,
            onEpisodeTap: widget.onEpisodeTap,
            currentQuality: widget.currentQuality,
            onQualityChanged: widget.onQualityChanged,
            videoUrlOne: widget.videoUrlOne,
            videoUrlTwo: widget.videoUrlTwo,
          ),
        ),

        // 底部进度条
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _BottomBar(
            player: widget.player,
            episode: widget.episode,
            episodeCount: widget.episodes.length,
            currentIndex: widget.currentIndex,
          ),
        ),
      ],
    );
  }
}

/// 顶部导航栏：返回按钮 + 剧名 + EP.X
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.dramaTitle,
    required this.currentIndex,
    required this.episodeCount,
  });

  final String dramaTitle;
  final int currentIndex;
  final int episodeCount;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);

    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 16,
        top: padding.top + 4,
        bottom: 8,
      ),
      decoration: BoxDecoration(
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
          // 返回按钮
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          const SizedBox(width: 4),
          // 剧名 + EP.X
          Expanded(
            child: Text(
              '$dramaTitle  (EP.${currentIndex + 1})',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 右侧操作列
class _ActionColumn extends StatelessWidget {
  const _ActionColumn({
    required this.episodeCount,
    required this.currentIndex,
    required this.onEpisodeTap,
    required this.currentQuality,
    required this.onQualityChanged,
    this.videoUrlOne,
    this.videoUrlTwo,
  });

  final int episodeCount;
  final int currentIndex;
  final VoidCallback onEpisodeTap;
  final VideoQuality currentQuality;
  final void Function(VideoQuality) onQualityChanged;
  final String? videoUrlOne;
  final String? videoUrlTwo;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionBtn(icon: Icons.favorite, label: '999+', onTap: () {}),
        const SizedBox(height: 20),
        _ActionBtn(icon: Icons.star, label: '999+', onTap: () {}),
        const SizedBox(height: 20),
        _ActionBtn(icon: Icons.share, label: 'Share', onTap: () {}),
        const SizedBox(height: 20),
        _QualityBtn(
          currentQuality: currentQuality,
          onQualityChanged: onQualityChanged,
          videoUrlOne: videoUrlOne,
          videoUrlTwo: videoUrlTwo,
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: onEpisodeTap,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                child: const Icon(Icons.list, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 4),
              const Text(
                'Episode',
                style: TextStyle(color: Colors.white, fontSize: 11, shadows: [Shadow(blurRadius: 4)]),
              ),
            ],
          ),
        ),
      ],
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showQualityPicker(context),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
            child: Text(
              _qualityLabel(currentQuality),
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Quality',
            style: TextStyle(color: Colors.white, fontSize: 11, shadows: [Shadow(blurRadius: 4)]),
          ),
        ],
      ),
    );
  }

  String _qualityLabel(VideoQuality q) {
    switch (q) {
      case VideoQuality.sd:
        return 'SD';
      case VideoQuality.hd:
        return 'HD';
      case VideoQuality.fhd:
        return 'FHD';
    }
  }

  void _showQualityPicker(BuildContext context) {
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
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Text('Select Quality', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('Current: ${_label(currentQuality)}', style: TextStyle(color: Colors.grey.shade600, fontSize: 14)),
              ],
            ),
          ),
          _qualityTile(VideoQuality.sd, 'SD', 'Standard quality', currentQuality, onQualityChanged),
          _qualityTile(VideoQuality.hd, 'HD', 'High quality', currentQuality, onQualityChanged, enabled: hasHd),
          _qualityTile(VideoQuality.fhd, 'FHD', 'Full HD', currentQuality, onQualityChanged, enabled: hasFhd),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _qualityTile(VideoQuality q, String label, String desc, VideoQuality current, void Function(VideoQuality) onTap, {bool enabled = true}) {
    final isSelected = q == current;
    return ListTile(
      leading: Icon(Icons.check_circle, color: isSelected ? Colors.blue : Colors.transparent),
      title: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: enabled ? null : Colors.grey)),
      subtitle: Text(desc, style: TextStyle(color: enabled ? Colors.grey : Colors.grey.shade400, fontSize: 12)),
      trailing: enabled ? null : const Text('Unavailable', style: TextStyle(color: Colors.grey, fontSize: 12)),
      onTap: enabled ? () => onTap(q) : null,
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
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.label, required this.onTap});

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
            decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 4)]),
          ),
        ],
      ),
    );
  }
}

/// 底部进度条
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.player,
    required this.episode,
    required this.episodeCount,
    required this.currentIndex,
  });

  final _EpisodePlayer player;
  final EpisodeData episode;
  final int episodeCount;
  final int currentIndex;

  String _formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    return '${(totalSec ~/ 60).toString().padLeft(2, '0')}:${(totalSec % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);

    return Container(
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 标题 + 集数
          Row(
            children: [
              Expanded(
                child: Text(
                  episode.title.isNotEmpty ? episode.title : 'EP.${currentIndex + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${currentIndex + 1} / $episodeCount',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 进度条
          Row(
            children: [
              Text(
                _formatDuration(player.positionMs),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white38,
                    thumbColor: Colors.white,
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                  ),
                  child: Slider(
                    value: player.positionMs > 0
                        ? player.positionMs / (player.durationMs > 0 ? player.durationMs : 1)
                        : 0,
                    onChanged: (v) => player.seekTo((v * player.durationMs).toInt()),
                  ),
                ),
              ),
              Text(
                _formatDuration(player.durationMs),
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 单个集数的播放器管理类
class _EpisodePlayer {
  _EpisodePlayer({
    required EpisodeData episode,
    required void Function(bool playing, bool loading) onStateChanged,
  })  : _episode = episode,
        _onStateChanged = onStateChanged {
    _player = FlutterAliPlayerFactory.createAliPlayer();
    _setupListeners();
  }

  // 预加载模式（不自动播放）
  _EpisodePlayer.preload({
    required EpisodeData episode,
    required void Function(bool playing, bool loading) onStateChanged,
  })  : _episode = episode,
        _onStateChanged = onStateChanged {
    _player = FlutterAliPlayerFactory.createAliPlayer();
    _player.setAutoPlay(false);
    if (episode.videoUrl.isNotEmpty) {
      _player.setUrl(episode.videoUrl);
    }
    _setupListeners();
  }

  final EpisodeData _episode;
  final void Function(bool playing, bool loading) _onStateChanged;
  late final FlutterAliplayer _player;
  final _logger = Logger();

  int _viewId = -1;
  bool _isPlaying = false;
  bool _isLoading = false;
  int _positionMs = 0;
  int _durationMs = 0;
  Timer? _positionTimer;
  bool _isAttached = false;
  bool _isDisposed = false;

  bool get isPlaying => _isPlaying;
  int get positionMs => _positionMs;
  int get durationMs => _durationMs;

  void attachView(int viewId) {
    _viewId = viewId;
    _player.setPlayerView(viewId);
    _isAttached = true;
    _logger.d('EpisodePlayer attachView: $viewId for ${_episode.id}');
    play();
  }

  void play() async {
    _logger.d('[EpisodePlayer] play() called _isAttached=$_isAttached _viewId=$_viewId url=${_episode.videoUrl}');
    if (!_isAttached || _viewId < 0) return;
    if (_episode.videoUrl.isEmpty) return;
    _isLoading = true;
    _onStateChanged(_isPlaying, _isLoading);
    _player.setAutoPlay(true);
    _player.setUrl(_episode.videoUrl);
    await _player.prepare();
    _startPositionTimer();
  }

  void pause() {
    _player.pause();
    _isPlaying = false;
    _isLoading = false;
    _onStateChanged(_isPlaying, _isLoading);
    _stopPositionTimer();
  }

  void togglePlay() {
    if (_isPlaying) {
      pause();
    } else {
      play();
    }
  }

  Future<void> loadUrl(String url) async {
    if (!_isAttached || _viewId < 0 || url.isEmpty) return;
    _isLoading = true;
    _onStateChanged(_isPlaying, _isLoading);
    _player.stop();
    await _player.setUrl(url);
    await _player.prepare();
  }

  void seekTo(int ms) {
    _player.seekTo(ms, FlutterAvpdef.ACCURATE);
  }

  void _setupListeners() {
    _player.setOnPrepared((_) async {
      _logger.d('EpisodePlayer prepared: ${_episode.id}');
      _isLoading = false;
      _durationMs = await _player.getDuration();
      _onStateChanged(_isPlaying, _isLoading);
    });

    _player.setOnRenderingStart((_) {
      _isPlaying = true;
      _isLoading = false;
      _onStateChanged(_isPlaying, _isLoading);
    });

    _player.setOnStateChanged((newState, _) {
      switch (newState) {
        case FlutterAvpdef.started:
          _isPlaying = true;
          _isLoading = false;
          break;
        case FlutterAvpdef.paused:
          _isPlaying = false;
          break;
        case FlutterAvpdef.stopped:
          _isPlaying = false;
          break;
        default:
          break;
      }
      _onStateChanged(_isPlaying, _isLoading);
    });

    _player.setOnLoadingStatusListener(
      loadingBegin: (_) {
        _isLoading = true;
        _onStateChanged(_isPlaying, _isLoading);
      },
      loadingProgress: (_, __, ___) {},
      loadingEnd: (_) {
        _isLoading = false;
        _onStateChanged(_isPlaying, _isLoading);
      },
    );

    _player.setOnInfo((code, extra, __, ___) {
      if (code == InfoCode.CURRENTPOSITION && extra != null) {
        _positionMs = extra;
      }
    });

    _player.setOnError((code, extra, msg, _) {
      _logger.e('EpisodePlayer error: $code $extra $msg');
      _isPlaying = false;
      _isLoading = false;
      _onStateChanged(_isPlaying, _isLoading);
    });
  }

  void _startPositionTimer() {
    _stopPositionTimer();
    _positionTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final pos = await _player.getCurrentPosition();
        if (_isDisposed) return;
        if (pos is int) _positionMs = pos;
      } catch (_) {}
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  void dispose() {
    _isDisposed = true;
    _stopPositionTimer();
    _player.stop();
    _player.release();
  }
}

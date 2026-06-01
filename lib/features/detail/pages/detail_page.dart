import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:preload_page_view/preload_page_view.dart';

import '../../../app/providers/app_providers.dart';
import '../../../components/common_video_player.dart';
import '../../../core/network/api_service.dart';
import '../../recommend/models/video_info.dart';
import '../../recommend/pages/ali_player_preload.dart';
import '../../recommend/pages/short_video_item.dart';
import '../../player/presentation/episode_sheet.dart';
import '../../player/presentation/player_controller.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../../payment/widgets/vip_paywall_overlay.dart';

/// 详情页 — 完全复用 ShortVideoListPage 模式，唯一区别是传入 overlayBuilder
class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({
    super.key,
    required this.videoUrl,
    required this.videoId,
    this.title,
    this.coverUrl,
    this.allEpisodes = const [],
    this.currentIndex = 0,
    this.videoUrlOne,
    this.videoUrlTwo,
    this.isVipOnly = false,
    this.initialProgress,
    this.autoPlay = false,
    this.isCanPlay = 1,
    this.isVip = 0,
  });

  final String videoUrl;
  final String videoId;
  final String? title;
  final String? coverUrl;
  final List<CommonEpisode> allEpisodes;
  final int currentIndex;
  final String? videoUrlOne;
  final String? videoUrlTwo;
  final bool isVipOnly;
  final Duration? initialProgress;
  final bool autoPlay;
  final int isCanPlay;
  final int isVip;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  late PreloadPageController _preloadPageController;
  late AliPlayerPreload _aliPlayerPreload;
  late List _itemKeys;
  int _currentIndex = 0;

  /// 所有集的播放数据
  final List<VideoInfo> _episodes = [];

  bool _isLoading = true;
  String? _errorMessage;

  late ApiService _apiService;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.currentIndex;
    _preloadPageController = PreloadPageController();
    _preloadPageController.addListener(_onPageChanged);
    _aliPlayerPreload = AliPlayerPreload(
      context: context,
      enableCoverUrlStrategy: true,
    );
    _apiService = ApiService(
      dioClient: ref.read(dioClientProvider),
      storage: ref.read(storageServiceProvider),
    );
    _fetchAll();
  }

  @override
  void dispose() {
    _aliPlayerPreload.destroy();
    _preloadPageController.removeListener(_onPageChanged);
    _preloadPageController.dispose();
    super.dispose();
  }

  /// 完全按照 ShortVideoListPage 的 _onPageChanged 逻辑
  void _onPageChanged() {
    final newIndex = _preloadPageController.page?.round() ?? 0;
    if (_currentIndex == newIndex) return;
    _currentIndex = newIndex;
    _aliPlayerPreload.moveTo(newIndex);
    _pauseAllExceptCurrent(newIndex);
  }

  /// 完全按照 ShortVideoListPage 的 _pauseAllExceptCurrent 逻辑
  void _pauseAllExceptCurrent(int currentIndex) {
    for (int i = 0; i < _itemKeys.length; i++) {
      if (i != currentIndex) {
        _itemKeys[i].currentState?.pause();
      } else {
        _itemKeys[i].currentState?.resume();
      }
    }
  }

  void _showEpisodeSheet(int currentIdx) {
    final episodes = _episodes.map((vi) {
      return EpisodeData(
        id: vi.id.toString(),
        title: vi.title,
        videoUrl: vi.videoUrl,
        coverUrl: vi.coverUrl,
        isUnlocked: vi.isCanPlay == 1,
      );
    }).toList();

    showEpisodeSheet(
      context,
      episodes: episodes,
      currentIndex: currentIdx,
      isVipOnly: false,
      authState: ref.read(authProvider),
      memberState: ref.read(memberStateProvider),
      onEpisodeTap: _animateToEpisode,
      onUnlock: (_) => context.push('/membership'),
    );
  }

  Future<void> _fetchAll() async {
    final videoIdStr = widget.videoId;

    final String episodesId = widget.allEpisodes.isNotEmpty
        ? widget.allEpisodes[_currentIndex].id.toString()
        : videoIdStr;

    try {
      final epInfoFuture = _apiService.getEpisodeInfo(
        videoId: videoIdStr,
        episodesId: episodesId,
      );
      final dirFuture = _apiService.getEpisodesDirectoryByVideoId(
        videoId: videoIdStr,
      );
      final playFuture = _apiService.getVideoListByVideoId(
        videoId: videoIdStr,
        episodesNum: 50,
        pageSize: 50,
      );

      final results = await Future.wait([epInfoFuture, dirFuture, playFuture]);
      final epInfoData = results[0];

      String currentEpId = episodesId;
      if (epInfoData.isSuccess && epInfoData.data != null) {
        final d = epInfoData.data as Map<String, dynamic>;
        currentEpId = _toString(d['episodesId']) ?? episodesId;
      }

      final eps = _parseEpisodes(results[1], results[2], videoIdStr);

      int matchedIndex = 0;
      for (int i = 0; i < eps.length; i++) {
        if (eps[i].id.toString() == currentEpId) {
          matchedIndex = i;
          break;
        }
      }

      if (!mounted) return;

      _episodes.clear();
      _episodes.addAll(eps);
      _currentIndex = matchedIndex;

      // 完全按照 ShortVideoListPage.initState 的逻辑
      _aliPlayerPreload.setItems(eps.cast<VideoInfo>());
      _aliPlayerPreload.moveTo(matchedIndex);
      _itemKeys = List.generate(
        _episodes.length,
        (_) => GlobalKey<ShortVideoItemState>(),
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      _setError(e.toString());
    }
  }

  /// 选集/上下集切换：滚动到目标集（和推荐页滑动行为完全一致）
  void _animateToEpisode(int index) {
    if (index < 0 || index >= _episodes.length) return;
    _aliPlayerPreload.moveTo(index);
    _preloadPageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _errorMessage = msg;
        _isLoading = false;
      });
    }
  }

  String? _toString(Object? v) => v?.toString();

  List<VideoInfo> _parseEpisodes(
    ApiResponse dirResp,
    ApiResponse playResp,
    String videoIdStr,
  ) {
    final Map<String, Map> playById = {};
    if (playResp.isSuccess && playResp.data != null && playResp.data is List) {
      for (final item in playResp.data as List) {
        if (item is! Map) continue;
        final id = _toString(item['episodesId']);
        if (id != null) playById[id] = item;
      }
    }

    List<dynamic> dirItems = [];
    if (dirResp.isSuccess && dirResp.data != null) {
      final d = dirResp.data as Map<String, dynamic>;
      final voList = d['voList'] as List?;
      if (voList is List) {
        for (final group in voList) {
          if (group is Map) {
            final dirList = group['directoryList'] as List?;
            if (dirList is List) dirItems.addAll(dirList);
          }
        }
      }
      if (dirItems.isEmpty) {
        final flat = d['directoryList'] as List?;
        if (flat is List) dirItems = flat;
      }
    }

    final episodes = <VideoInfo>[];

    for (final item in dirItems) {
      if (item is! Map) continue;
      final m = item;
      final epId = _toString(m['episodesId']) ?? '';
      final epNum = m['episodesNum'] as int? ?? 0;
      final playItem = playById[epId];
      final isCanPlay = playItem != null
          ? (playItem['isCanPlay'] as int? ?? 1)
          : (m['isCanPlay'] as int? ?? 1);

      episodes.add(VideoInfo(
        id: int.tryParse(epId) ?? 0,
        videoId: int.tryParse(videoIdStr) ?? 0,
        title: _toString(m['episodesName']) ?? (epNum > 0 ? 'EP.$epNum' : ''),
        videoUrl: playItem != null ? (_toString(playItem['episodesUrl']) ?? '') : '',
        coverUrl: playItem != null ? _toString(playItem['videoPicture']) : null,
        videoUrlOne: playItem != null ? _toString(playItem['vipEpisodesUrl1080']) : null,
        videoUrlTwo: playItem != null ? _toString(playItem['vipEpisodesUrl1440']) : null,
        serialNum: epNum,
        isCanPlay: isCanPlay,
      ));
    }

    if (episodes.isEmpty && playResp.data is List) {
      for (final item in playResp.data as List) {
        if (item is! Map) continue;
        final m = item;
        final epId = _toString(m['episodesId']) ?? '';
        final epNum = m['episodesNum'] as int? ?? 0;
        episodes.add(VideoInfo(
          id: int.tryParse(epId) ?? 0,
          videoId: int.tryParse(videoIdStr) ?? 0,
          title: _toString(m['episodesName']) ?? (epNum > 0 ? 'EP.$epNum' : epId),
          videoUrl: _toString(m['episodesUrl']) ?? '',
          coverUrl: _toString(m['videoPicture']),
          videoUrlOne: _toString(m['vipEpisodesUrl1080']),
          videoUrlTwo: _toString(m['vipEpisodesUrl1440']),
          serialNum: epNum,
          isCanPlay: m['isCanPlay'] as int? ?? 1,
        ));
      }
    }

    return episodes;
  }

  Widget _buildDetailOverlay(BuildContext context, VideoInfo vi, int index) {
    final isFirst = index == 0;
    final isLast = index == _episodes.length - 1;
    final isLocked = vi.isCanPlay != 1;
    final episodeTitle = vi.title;

    return Stack(
      fit: StackFit.expand,
      children: [
        _buildTopBar(episodeTitle, isFirst, isLast),
        if (isLocked)
          VipPaywallOverlay(
            title: episodeTitle.isNotEmpty ? episodeTitle : widget.title ?? '',
            onUnlock: () => context.push('/membership'),
            canClose: false,
          ),
        _buildActionColumn(index, isFirst, isLast),
      ],
    );
  }

  Widget _buildTopBar(String episodeTitle, bool isFirst, bool isLast) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 48,
          right: 16,
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
            Expanded(
              child: Text(
                episodeTitle.isNotEmpty ? episodeTitle : widget.title ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isFirst)
              const Icon(Icons.expand_less, color: Colors.white54, size: 20)
            else if (isLast)
              const Icon(Icons.expand_more, color: Colors.white54, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionColumn(int index, bool isFirst, bool isLast) {
    return Positioned(
      right: 12,
      bottom: 100,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActionBtn(
            icon: Icons.skip_previous,
            label: 'Prev',
            enabled: !isFirst,
            onTap: isFirst ? null : () => _animateToEpisode(index - 1),
          ),
          const SizedBox(height: 16),
          _ActionBtn(
            icon: Icons.skip_next,
            label: 'Next',
            enabled: !isLast,
            onTap: isLast ? null : () => _animateToEpisode(index + 1),
          ),
          const SizedBox(height: 16),
          _ActionBtn(
            icon: Icons.list,
            label: 'Episode',
            enabled: true,
            onTap: () => _showEpisodeSheet(index),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _errorMessage != null
              ? _ErrorView(
                  message: _errorMessage!,
                  onRetry: () {
                    setState(() {
                      _isLoading = true;
                      _errorMessage = null;
                    });
                    _fetchAll();
                  },
                  onBack: () => Navigator.pop(context),
                )
              : Stack(
                  children: [
                    PreloadPageView.builder(
                      controller: _preloadPageController,
                      scrollDirection: Axis.vertical,
                      preloadPagesCount: 1,
                      itemCount: _episodes.length,
                      itemBuilder: (context, index) {
                        return ShortVideoItem(
                          key: _itemKeys[index],
                          videoInfo: _episodes[index],
                          autoPlay: index == _currentIndex,
                          overlayBuilder: (ctx, vi) =>
                              _buildDetailOverlay(ctx, vi, index),
                        );
                      },
                    ),
                    Positioned(
                      top: MediaQuery.paddingOf(context).top + 8,
                      left: 8,
                      child: SafeArea(
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
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
    required this.enabled,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: enabled ? Colors.black38 : Colors.black12,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: enabled ? Colors.white : Colors.white30,
              size: 28,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white30,
              fontSize: 11,
              shadows: const [Shadow(blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.white54, size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(color: Colors.white54),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: onBack,
                child: const Text('Go Back',
                    style: TextStyle(color: Colors.white54)),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

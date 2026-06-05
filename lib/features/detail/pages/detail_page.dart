import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:preload_page_view/preload_page_view.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../../commonAliPlayer/short_video_item.dart';
import '../../player/domain/player_state.dart';
import '../../player/presentation/episode_sheet.dart';
import '../../player/presentation/player_controller.dart';
import '../../recommend/models/video_info.dart';
import '../../recommend/pages/ali_player_preload.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../../payment/widgets/vip_paywall_overlay.dart';
import '../../../components/rtl_back_button.dart';

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

    final oldIndex = _currentIndex;
    _currentIndex = newIndex;
    _aliPlayerPreload.moveTo(newIndex);

    // 暂停旧视频
    if (oldIndex < _itemKeys.length) {
      _itemKeys[oldIndex].currentState?.pause();
    }

    // 播放新视频（不需要 refreshUrl，URL 已通过 playVideo 完整加载）
    if (newIndex < _itemKeys.length) {
      _itemKeys[newIndex].currentState?.resume();
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
      isVipOnly: widget.isVipOnly,
      authState: ref.read(authProvider),
      memberState: ref.read(memberStateProvider),
      onEpisodeTap: _animateToEpisode,
      onUnlock: (_) => context.push('/membership'),
    );
  }

  Future<void> _fetchAll() async {
    final videoIdStr = widget.videoId;

    try {
      // 1. 先拿 directory（选集列表）
      final dirResp = await _apiService.getEpisodesDirectoryByVideoId(
        videoId: videoIdStr,
      );
      debugPrint("[DetailPage][fetchAll] dirResp success=${dirResp.isSuccess}");

      if (!dirResp.isSuccess || dirResp.data == null) {
        _setError('Failed to load episodes list');
        return;
      }

      // 解析出所有集 ID
      final dirData = dirResp.data as Map<String, dynamic>;
      final videoEpisodes = dirData['videoEpisodes'] as int? ?? 1;
      final voList = dirData['voList'] as List?;
      final dirItems = <Map>[];

      if (voList is List) {
        for (final group in voList) {
          if (group is Map) {
            final dirList = group['directoryList'] as List?;
            if (dirList is List) {
              for (final item in dirList) {
                if (item is Map) dirItems.add(item);
              }
            }
          }
        }
      }
      if (dirItems.isEmpty) {
        final flat = dirData['directoryList'] as List?;
        if (flat is List) {
          for (final item in flat) {
            if (item is Map) dirItems.add(item);
          }
        }
      }
      debugPrint("[DetailPage] directory episodes count=${dirItems.length}");

      if (dirItems.isEmpty) {
        _setError('No episodes found');
        return;
      }

      // 2. 尝试 playVideo（批量获取 URL）
      List<Map>? playList;
      final playResp = await _apiService.getVideoListByVideoId(
        videoId: videoIdStr,
        episodesNum: 1,
        pageSize: videoEpisodes,
      );
      debugPrint("[DetailPage][fetchAll] playResp success=${playResp.isSuccess}");

      if (playResp.isSuccess && playResp.data is List) {
        final rawList = playResp.data as List;
        for (final item in rawList) {
          if (item is Map) {
            playList ??= [];
            playList.add(item);
          }
        }
      }

      // 3. 构建 episodesId → playItem 映射（playVideo 成功时）
      final Map<String, Map> playById = {};
      if (playList != null) {
        for (final item in playList) {
          final id = _toString(item['episodesId']);
          if (id != null) playById[id] = item;
        }
        debugPrint("[DetailPage] playVideo loaded ${playById.length} URLs");
      }

      // 4. 构建 VideoInfo 列表
      final List<VideoInfo> eps = [];

      if (playById.isNotEmpty) {
        // playVideo 成功：用 playVideo 的 URL（完整数据）
        for (final m in dirItems) {
          final epId = _toString(m['episodesId']) ?? '';
          final playItem = playById[epId];
          eps.add(VideoInfo(
            id: int.tryParse(epId) ?? 0,
            videoId: int.tryParse(videoIdStr) ?? 0,
            title: _toString(m['episodesName']) ?? '',
            videoUrl: playItem != null ? (_toString(playItem['episodesUrl']) ?? '') : '',
            coverUrl: playItem != null ? _toString(playItem['videoPicture']) : null,
            videoUrlOne: playItem != null ? _toString(playItem['vipEpisodesUrl1080']) : null,
            videoUrlTwo: playItem != null ? _toString(playItem['vipEpisodesUrl1440']) : null,
            serialNum: m['episodesNum'] as int? ?? 0,
            isCanPlay: playItem != null ? (playItem['isCanPlay'] as int? ?? 1) : (m['isCanPlay'] as int? ?? 1),
          ));
        }
      } else {
        // playVideo 失败：逐集调 getEpisodeInfo 获取 URL
        debugPrint("[DetailPage] playVideo failed, falling back to getEpisodeInfo per episode");
        for (final m in dirItems) {
          final epId = _toString(m['episodesId']) ?? '';
          try {
            final epResp = await _apiService.getEpisodeInfo(
              videoId: videoIdStr,
              episodesId: epId,
            );
            if (epResp.isSuccess && epResp.data != null) {
              final d = epResp.data as Map<String, dynamic>;
              eps.add(VideoInfo(
                id: int.tryParse(epId) ?? 0,
                videoId: int.tryParse(videoIdStr) ?? 0,
                title: _toString(m['episodesName']) ?? '',
                videoUrl: _toString(d['episodesUrl']) ?? '',
                coverUrl: _toString(d['videoPicture']),
                videoUrlOne: _toString(d['vipEpisodesUrl1080']),
                videoUrlTwo: _toString(d['vipEpisodesUrl1440']),
                serialNum: m['episodesNum'] as int? ?? 0,
                isCanPlay: d['isCanPlay'] as int? ?? 1,
              ));
            } else {
              eps.add(VideoInfo(
                id: int.tryParse(epId) ?? 0,
                videoId: int.tryParse(videoIdStr) ?? 0,
                title: _toString(m['episodesName']) ?? '',
                videoUrl: '',
                serialNum: m['episodesNum'] as int? ?? 0,
                isCanPlay: m['isCanPlay'] as int? ?? 1,
              ));
            }
          } catch (_) {
            eps.add(VideoInfo(
              id: int.tryParse(epId) ?? 0,
              videoId: int.tryParse(videoIdStr) ?? 0,
              title: _toString(m['episodesName']) ?? '',
              videoUrl: '',
              serialNum: m['episodesNum'] as int? ?? 0,
              isCanPlay: m['isCanPlay'] as int? ?? 1,
            ));
          }
        }
      }

      debugPrint("[DetailPage][fetchAll] parsed episodes count=${eps.length}");
      for (final ep in eps.take(3)) {
        debugPrint("[DetailPage] ep: id=${ep.id} title=${ep.title} url=${ep.videoUrl}");
      }

      if (!mounted) return;

      _episodes.clear();
      _episodes.addAll(eps);

      int startIndex = widget.currentIndex.clamp(0, eps.isEmpty ? 0 : eps.length - 1);

      _aliPlayerPreload.setItems(eps.cast<VideoInfo>());
      _aliPlayerPreload.moveTo(startIndex);
      _itemKeys = List.generate(
        _episodes.length,
        (_) => GlobalKey<ShortVideoItemState>(),
      );

      if (!mounted) return;
      _currentIndex = startIndex;
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("[DetailPage][fetchAll] error: $e");
      _setError(e.toString());
    }
  }

  /// 选集/上下集切换：直接换当前播放器内容（和推荐页滑动行为完全一致）
  void _animateToEpisode(int index) {
    if (index < 0 || index >= _episodes.length) return;

    final oldIndex = _currentIndex;
    _currentIndex = index;

    _aliPlayerPreload.moveTo(index);

    // 暂停旧集
    if (oldIndex < _itemKeys.length) {
      _itemKeys[oldIndex].currentState?.pause();
    }

    // 切换到新集
    _itemKeys[index].currentState?.switchTo(_episodes[index]);

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
    return PositionedDirectional(
      top: 0,
      start: 0,
      end: 0,
      child: Container(
        padding: EdgeInsetsDirectional.only(
          top: MediaQuery.paddingOf(context).top + 8,
          start: 48,
          end: 16,
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
    return PositionedDirectional(
      end: 12,
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
                    PositionedDirectional(
                      top: MediaQuery.paddingOf(context).top + 8,
                      start: 8,
                      child: SafeArea(
                        child: RtlBackButton(
                          onPressed: () => Navigator.pop(context),
                          color: Colors.white,
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

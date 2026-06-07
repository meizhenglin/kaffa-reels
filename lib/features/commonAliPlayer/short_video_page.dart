// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 沉浸式列表播放页面（适配本项目 VideoInfo 模型）
//
// 【数据加载策略】 — watch 页先完整拉齐 episodes，再走与 recommend 同款的播放链路

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:preload_page_view/preload_page_view.dart';

import '../home/pages/main_page.dart';
import '../../core/network/api_service.dart';
import '../recommend/models/video_info.dart';
import 'ali_player_preload.dart';
import 'watch_short_video_item.dart';
import 'short_video_preload_tuning.dart';

const bool _showWatchPlaybackDebug = false;

typedef ShortVideoOverlayBuilder = Widget Function(
  BuildContext context,
  VideoInfo videoInfo,
  int index,
  ShortVideoListController controller,
);

typedef ShortVideoTopOverlayBuilder = Widget Function(
  BuildContext context,
  VideoInfo videoInfo,
  int index,
  ShortVideoListController controller,
);

typedef ShortVideoForegroundBuilder = Widget Function(
  BuildContext context,
  List<VideoInfo> episodes,
  int currentIndex,
  ShortVideoListController controller,
);

class ShortVideoListController {
  VoidCallback? _showEpisodePickerHandler;
  ValueChanged<int>? _jumpToEpisodeHandler;
  int Function()? _currentIndexGetter;
  List<VideoInfo> Function()? _episodesGetter;

  void _attach({
    required VoidCallback showEpisodePicker,
    required ValueChanged<int> jumpToEpisode,
    required int Function() currentIndex,
    required List<VideoInfo> Function() episodes,
  }) {
    _showEpisodePickerHandler = showEpisodePicker;
    _jumpToEpisodeHandler = jumpToEpisode;
    _currentIndexGetter = currentIndex;
    _episodesGetter = episodes;
  }

  void showEpisodePicker() => _showEpisodePickerHandler?.call();

  void jumpToEpisode(int index) => _jumpToEpisodeHandler?.call(index);

  int get currentIndex => _currentIndexGetter?.call() ?? 0;

  List<VideoInfo> get episodes => _episodesGetter?.call() ?? const [];
}

class ShortVideoPage extends StatelessWidget {
  final bool preload;
  final String videoId;
  final int initialIndex;
  final VideoInfo? seedVideo;
  final ShortVideoOverlayBuilder? overlayBuilder;
  final ShortVideoTopOverlayBuilder? topOverlayBuilder;
  final ShortVideoForegroundBuilder? foregroundBuilder;
  final Widget Function(BuildContext context, ShortVideoListController controller)?
      floatingOverlayBuilder;
  final bool showDefaultTopOverlay;
  final bool showDefaultSideOverlay;

  const ShortVideoPage({
    super.key,
    required this.videoId,
    this.preload = true,
    this.initialIndex = 0,
    this.seedVideo,
    this.overlayBuilder,
    this.topOverlayBuilder,
    this.foregroundBuilder,
    this.floatingOverlayBuilder,
    this.showDefaultTopOverlay = true,
    this.showDefaultSideOverlay = true,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ShortVideoListPage(
        preload: preload,
        videoId: videoId,
        initialIndex: initialIndex,
        seedVideo: seedVideo,
        overlayBuilder: overlayBuilder,
        topOverlayBuilder: topOverlayBuilder,
        foregroundBuilder: foregroundBuilder,
        floatingOverlayBuilder: floatingOverlayBuilder,
        showDefaultTopOverlay: showDefaultTopOverlay,
        showDefaultSideOverlay: showDefaultSideOverlay,
      ),
    );
  }
}

class ShortVideoListPage extends ConsumerStatefulWidget {
  final bool preload;
  final String videoId;
  final int initialIndex;
  final VideoInfo? seedVideo;
  final ShortVideoOverlayBuilder? overlayBuilder;
  final ShortVideoTopOverlayBuilder? topOverlayBuilder;
  final ShortVideoForegroundBuilder? foregroundBuilder;
  final Widget Function(BuildContext context, ShortVideoListController controller)?
      floatingOverlayBuilder;
  final bool showDefaultTopOverlay;
  final bool showDefaultSideOverlay;

  const ShortVideoListPage({
    super.key,
    required this.preload,
    required this.videoId,
    this.initialIndex = 0,
    this.seedVideo,
    this.overlayBuilder,
    this.topOverlayBuilder,
    this.foregroundBuilder,
    this.floatingOverlayBuilder,
    this.showDefaultTopOverlay = true,
    this.showDefaultSideOverlay = true,
  });

  @override
  ConsumerState<ShortVideoListPage> createState() => _ShortVideoListPageState();
}

class _ShortVideoListPageState extends ConsumerState<ShortVideoListPage>
    with WidgetsBindingObserver {
  static const String _tag = 'ShortVideoPage';

  String _likeLabel(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar' ? 'إعجاب' : 'Like';
  }

  String _commentLabel(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar' ? 'تعليق' : 'Comment';
  }

  late List<VideoInfo> videoInfoList;
  AliPlayerPreload? _aliPlayerPreload;
  late PageController _pageController;
  late PreloadPageController _preloadPageController;
  final ShortVideoListController _listController = ShortVideoListController();

  int _currentIndex = 0;
  final List<GlobalKey<WatchShortVideoItemState>> _itemKeys = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isCurrentTabActive = false;
  ProviderSubscription<int>? _tabIndexSubscription;

  bool get _shouldFollowHomeTabVisibility => widget.videoId.isNotEmpty;

  bool get _usePreloadMode => widget.preload;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;

    if (_usePreloadMode) {
      _preloadPageController = PreloadPageController(initialPage: _currentIndex);
      _preloadPageController.addListener(_handlePreloadPageChanged);
    } else {
      _pageController = PageController(initialPage: _currentIndex);
    }

    _listController._attach(
      showEpisodePicker: _showEpisodePicker,
      jumpToEpisode: _jumpToEpisode,
      currentIndex: () => _currentIndex,
      episodes: () => videoInfoList,
    );

    _isCurrentTabActive = _shouldFollowHomeTabVisibility
        ? ref.read(currentTabIndexProvider) == 2
        : true;

    if (_shouldFollowHomeTabVisibility) {
      _tabIndexSubscription = ref.listenManual<int>(
        currentTabIndexProvider,
        (previous, next) {
          if (!mounted) return;
          _isCurrentTabActive = next == 2;
          if (_isCurrentTabActive) {
            _resumeCurrent();
          } else {
            _pauseCurrent();
          }
        },
      );
    }

    _loadData();
  }

  @override
  void dispose() {
    _tabIndexSubscription?.close();
    WidgetsBinding.instance.removeObserver(this);
    _aliPlayerPreload?.destroy();
    if (_usePreloadMode) {
      _preloadPageController.removeListener(_handlePreloadPageChanged);
      _preloadPageController.dispose();
    } else {
      _pageController.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _pauseCurrent();
        break;
      case AppLifecycleState.resumed:
        if (_isCurrentTabActive) {
          _resumeCurrent();
        }
        break;
    }
  }

  Future<void> _fetchByVideoId() async {
    if (widget.videoId.isEmpty) return;

    debugPrint('[$_tag] fetching by videoId=${widget.videoId}');

    try {
      final dirResp = await apiServiceProvider.getEpisodesDirectoryByVideoId(
        videoId: widget.videoId,
      );
      if (!dirResp.isSuccess || dirResp.data == null) {
        _setError('无法加载剧集目录');
        return;
      }

      final dirData = dirResp.data as Map<String, dynamic>;
      final videoEpisodes = dirData['videoEpisodes'] as int? ?? 10;

      final playResp = await apiServiceProvider.getVideoListByVideoId(
        videoId: widget.videoId,
        episodesNum: 1,
        pageSize: videoEpisodes,
      );
      if (!playResp.isSuccess || playResp.data is! List) {
        _setError('无法加载视频地址');
        return;
      }

      final videos = (playResp.data as List)
          .whereType<Map>()
          .map(
            (item) => VideoInfo.fromJson(
              Map<String, dynamic>.from(item).cast<String, dynamic>(),
            ),
          )
          .where((item) => item.videoUrl.isNotEmpty)
          .toList()
        ..sort((a, b) => a.serialNum.compareTo(b.serialNum));

      if (videos.isEmpty) {
        _setError('该剧暂无可播放剧集');
        return;
      }

      videoInfoList = videos;
      final seedEpisodeId = widget.seedVideo?.id ?? 0;
      final seedSerialNum = widget.seedVideo?.serialNum ?? 0;
      final resolvedInitialIndex = seedEpisodeId > 0
          ? videoInfoList.indexWhere((item) => item.id == seedEpisodeId)
          : seedSerialNum > 0
              ? videoInfoList.indexWhere((item) => item.serialNum == seedSerialNum)
              : -1;
      _currentIndex = resolvedInitialIndex >= 0
          ? resolvedInitialIndex
          : widget.initialIndex.clamp(0, videoInfoList.length - 1);

      if (_usePreloadMode) {
        _preloadPageController.removeListener(_handlePreloadPageChanged);
        _preloadPageController.dispose();
        _preloadPageController = PreloadPageController(initialPage: _currentIndex);
        _preloadPageController.addListener(_handlePreloadPageChanged);
      } else {
        _pageController.dispose();
        _pageController = PageController(initialPage: _currentIndex);
      }

      _itemKeys
        ..clear()
        ..addAll(
          List.generate(
            videoInfoList.length,
            (_) => GlobalKey<WatchShortVideoItemState>(),
          ),
        );

      _aliPlayerPreload?.destroy();
      _aliPlayerPreload = AliPlayerPreload(
        context: context,
        enableCoverUrlStrategy: true,
        usePrioritizedVideoPreload: true,
        enableVideoPreload: true,
      );
      _aliPlayerPreload!.setItems(videoInfoList);
      _aliPlayerPreload!.moveTo(_currentIndex);

      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_usePreloadMode) {
          _preloadPageController.jumpToPage(_currentIndex);
        } else {
          _pageController.jumpToPage(_currentIndex);
        }
        _aliPlayerPreload?.moveTo(_currentIndex);
        _reportViewHistory(_currentIndex);
        _prefetchAround(_currentIndex);
        _resumeCurrent();
      });
    } catch (e) {
      debugPrint('[$_tag] fetchByVideoId error=$e');
      _setError('加载失败：$e');
    }
  }

  void _loadData() {
    _fetchByVideoId();
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _errorMessage = msg;
      });
    }
  }

  void _handlePreloadPageChanged() {
    if (!widget.preload) return;
    final newIndex = _preloadPageController.page?.round() ?? 0;
    if (_currentIndex == newIndex) return;
    _onPageChanged(newIndex);
    _reportViewHistory(newIndex);
  }

  void _onPageChanged(int newPageIndex) {
    if (_currentIndex == newPageIndex) return;

    debugPrint('[$_tag]${'-' * 30}[index][$_currentIndex->$newPageIndex]');

    setState(() {
      _currentIndex = newPageIndex;
    });
    _aliPlayerPreload?.moveTo(newPageIndex);
    _pauseAllExceptCurrent(newPageIndex);
    _prefetchAround(newPageIndex);
  }

  void _prefetchAround(int centerIndex) {
    final indices = ShortVideoPreloadTuning.pagePlayablePrefetchOffsets
        .map((offset) => centerIndex + offset)
        .toSet();
    for (final index in indices) {
      if (index < 0 || index >= _itemKeys.length) continue;
      _itemKeys[index].currentState?.prefetchPlayableUrl(
        playIfReady: index == centerIndex && _isCurrentTabActive,
      );
    }
  }

  void _pauseCurrent() {
    if (_itemKeys.isEmpty) return;
    _itemKeys[_currentIndex].currentState?.pause();
  }

  void _resumeCurrent() {
    if (_itemKeys.isEmpty) return;
    _itemKeys[_currentIndex].currentState?.resume();
  }

  void _reportViewHistory(int index) {
    if (index < 0 || index >= videoInfoList.length) return;
    final videoInfo = videoInfoList[index];
    final episodesId = videoInfo.id.toString();
    debugPrint(
      '[$_tag] setUserViewAddHistory videoId=${widget.videoId} episodesId=$episodesId',
    );
    apiServiceProvider.setUserViewAddHistory(
      videoId: widget.videoId,
      episodesId: episodesId,
    );
  }

  void _pauseAllExceptCurrent(int currentIndex) {
    for (int i = 0; i < _itemKeys.length; i++) {
      if (i != currentIndex) {
        _itemKeys[i].currentState?.pause();
      } else if (_isCurrentTabActive) {
        _itemKeys[i].currentState?.resume();
      }
    }
  }

  void _jumpToEpisode(int index) {
    if (index < 0 || index >= videoInfoList.length) return;
    if (_usePreloadMode) {
      _preloadPageController.jumpToPage(index);
    } else {
      _pageController.jumpToPage(index);
    }
    _onPageChanged(index);
    _reportViewHistory(index);
  }

  void _showEpisodePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.62,
            ),
            decoration: const BoxDecoration(
              color: Color(0xFF111111),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Row(
                    children: [
                      const Text(
                        '选集',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${videoInfoList.length} 集',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1,
                    ),
                    itemCount: videoInfoList.length,
                    itemBuilder: (context, index) {
                      final item = videoInfoList[index];
                      final selected = index == _currentIndex;
                      final locked = item.isCanPlay == 0;
                      return GestureDetector(
                        onTap: () {
                          if (locked) return;
                          Navigator.of(sheetContext).pop();
                          _jumpToEpisode(index);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? Colors.white
                                : const Color(0xFF222222),
                            borderRadius: BorderRadius.circular(12),
                            border: selected
                                ? Border.all(color: Colors.white, width: 2)
                                : null,
                          ),
                          child: Center(
                            child: locked
                                ? const Icon(
                                    Icons.lock_rounded,
                                    color: Colors.white38,
                                  )
                                : Text(
                                    '${item.serialNum > 0 ? item.serialNum : index + 1}',
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.black
                                          : Colors.white,
                                      fontWeight: FontWeight.w700,
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
          ),
        );
      },
    );
  }

  double _watchSideOverlayBottomInset(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final safeBottom = mediaQuery.padding.bottom;
    final screenHeight = mediaQuery.size.height;
    return math.max(safeBottom + screenHeight * 0.12, safeBottom + 24);
  }

  Widget _buildDefaultTopOverlay(BuildContext context, VideoInfo videoInfo) {
    final episodeLabel = videoInfo.serialNum > 0 ? ' EP${videoInfo.serialNum}' : '';
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${videoInfo.title}$episodeLabel',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultSideOverlay(BuildContext context, VideoInfo videoInfo) {
    return Positioned(
      right: 12,
      bottom: _watchSideOverlayBottomInset(context),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSideActionButton(
              icon: Icons.favorite_border,
              label: _likeLabel(context),
              onTap: () {},
            ),
            const SizedBox(height: 16),
            _buildSideActionButton(
              icon: Icons.comment_outlined,
              label: _commentLabel(context),
              onTap: () {},
            ),
            const SizedBox(height: 16),
            _buildSideActionButton(
              icon: Icons.share_outlined,
              label: MaterialLocalizations.of(context).shareButtonLabel,
              onTap: () {},
            ),
            const SizedBox(height: 16),
            _buildSideActionButton(
              icon: Icons.list_alt_rounded,
              label: '选集',
              onTap: _showEpisodePicker,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final videoItem = videoInfoList[index];
    final autoPlay = index == _currentIndex;
    return WatchShortVideoItem(
      key: _itemKeys[index],
      videoInfo: videoItem,
      autoPlay: autoPlay,
      resolvePlayableUrl: false,
      overlayBuilder: (ctx, vi) {
        final children = <Widget>[];
        if (widget.showDefaultSideOverlay) {
          children.add(_buildDefaultSideOverlay(ctx, vi));
        }
        if (widget.overlayBuilder != null) {
          children.add(widget.overlayBuilder!(ctx, vi, index, _listController));
        }
        return Stack(children: children);
      },
      topOverlayBuilder: (ctx, vi) {
        final children = <Widget>[];
        if (widget.showDefaultTopOverlay) {
          children.add(_buildDefaultTopOverlay(ctx, vi));
        }
        if (widget.topOverlayBuilder != null) {
          children.add(widget.topOverlayBuilder!(ctx, vi, index, _listController));
        }
        return Stack(children: children);
      },
      showDebugInfo: _showWatchPlaybackDebug,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    }

    final pageView = _usePreloadMode
        ? PreloadPageView.builder(
            controller: _preloadPageController,
            scrollDirection: Axis.vertical,
            itemCount: videoInfoList.length,
            itemBuilder: _buildItem,
            preloadPagesCount: 4,
          )
        : PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: videoInfoList.length,
            itemBuilder: _buildItem,
            onPageChanged: (index) {
              _onPageChanged(index);
              _reportViewHistory(index);
            },
          );

    if (widget.foregroundBuilder == null && widget.floatingOverlayBuilder == null) {
      return pageView;
    }

    return Stack(
      children: [
        pageView,
        if (widget.foregroundBuilder != null)
          widget.foregroundBuilder!(
            context,
            videoInfoList,
            _currentIndex,
            _listController,
          ),
        if (widget.floatingOverlayBuilder != null)
          widget.floatingOverlayBuilder!(context, _listController),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:preload_page_view/preload_page_view.dart';

import '../../l10n/app_localizations.dart';
import '../home/pages/main_page.dart';
import '../home/providers/last_watched_provider.dart';
import '../../core/network/api_service.dart';
import '../recommend/models/video_info.dart';
import '../recommend/providers/video_action_provider.dart';
import '../recommend/utils/drama_navigation.dart';
import '../payment/providers/membership_provider.dart';
import 'ali_player_preload.dart';
import 'watch_short_video_item.dart';

const bool _showWatchPlaybackDebug = false;

enum _EpisodeSheetTab { episodes, content }

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

  int? _pendingLockedDialogIndex;

  Future<void> _toggleLike(VideoInfo videoInfo) async {
    final videoId = videoInfo.videoId.toString();
    if (videoId.isEmpty || videoId == '0') return;

    final currentValue = ref.read(videoActionProvider).isLiked(
          videoId,
          fallback: videoInfo.isLike == 1,
        );
    final currentCount = ref.read(videoActionProvider).likeCount(
          videoId,
          fallback: videoInfo.likeNum,
        );
    await ref.read(videoActionProvider.notifier).toggleLike(
          videoId: videoId,
          episodesId: videoInfo.id.toString(),
          currentValue: currentValue,
          currentCount: currentCount,
        );
  }

  Future<void> _toggleCollect(VideoInfo videoInfo) async {
    final videoId = videoInfo.videoId.toString();
    if (videoId.isEmpty || videoId == '0') return;

    final currentValue = ref.read(videoActionProvider).isCollected(
          videoId,
          fallback: videoInfo.isCollect == 1,
        );
    final currentCount = ref.read(videoActionProvider).collectCount(
          videoId,
          fallback: videoInfo.collectNum,
        );
    await ref.read(videoActionProvider.notifier).toggleCollect(
          videoId: videoId,
          episodesId: videoInfo.id.toString(),
          currentValue: currentValue,
          currentCount: currentCount,
        );
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
  int? _pendingLockedEpisodeIndex;
  bool _showWatchNowOverlay = false;

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
    if (newIndex == _currentIndex) return;

    final previousIndex = _currentIndex;
    if (_isEpisodeLocked(newIndex)) {
      _guardLockedEpisode(newIndex, previousIndex: previousIndex);
      return;
    }

    _handlePageChanged(newIndex, previousIndex: previousIndex);
  }

  void _onPageChanged(int newPageIndex) {
    if (_currentIndex == newPageIndex) return;

    debugPrint('[$_tag]${'-' * 30}[index][$_currentIndex->$newPageIndex]');

    _pauseAtIndex(_currentIndex);
    _currentIndex = newPageIndex;
    _aliPlayerPreload?.moveTo(_currentIndex);
    _prefetchAround(_currentIndex);
    _resumeCurrent();
    if (mounted) {
      setState(() {});
    }
  }

  void _prefetchAround(int centerIndex) {
    final preload = _aliPlayerPreload;
    if (preload == null) return;
    preload.moveTo(centerIndex);
  }

  void _pauseAtIndex(int index) {
    if (index < 0 || index >= _itemKeys.length) return;
    _itemKeys[index].currentState?.pause();
  }

  void _resumeAtIndex(int index) {
    if (index < 0 || index >= _itemKeys.length) return;
    _itemKeys[index].currentState?.resume();
  }

  void _pauseNearbyItems(int centerIndex) {
    _pauseAtIndex(centerIndex - 1);
    _pauseAtIndex(centerIndex);
    _pauseAtIndex(centerIndex + 1);
  }

  void _pauseCurrent() {
    _pauseAtIndex(_currentIndex);
  }

  void _resumeCurrent() {
    _resumeAtIndex(_currentIndex);
  }

  void _reportViewHistory(int index) {
    if (index < 0 || index >= videoInfoList.length) return;

    final item = videoInfoList[index];
    final episodesId = item.id.toString();
    if (widget.videoId.isEmpty || episodesId.isEmpty || episodesId == '0') return;

    Future.microtask(() async {
      final response = await apiServiceProvider.setUserViewAddHistory(
        videoId: widget.videoId,
        episodesId: episodesId,
      );
      if (!response.isSuccess) return;
      if (!mounted) return;
      await ref.read(lastWatchedProvider.notifier).load();
    });
  }

  bool _isEpisodeLocked(int index) {
    if (index < 0 || index >= videoInfoList.length) return false;
    final memberState = ref.read(memberStateProvider);
    if (memberState.isVip && !memberState.isExpired) {
      return false;
    }
    return videoInfoList[index].isCanPlay == 0;
  }

  Future<void> _showMembershipReminderDialog({int? lockedIndex}) async {
    if (_pendingLockedDialogIndex == lockedIndex) return;
    _pendingLockedDialogIndex = lockedIndex;

    final l10n = AppLocalizations.of(context);
    final shouldConfirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            l10n.watchLockedReminderTitle,
            textAlign: TextAlign.center,
          ),
          content: Text(
            l10n.watchLockedReminderMessage,
            textAlign: TextAlign.center,
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.common_cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.common_confirm),
            ),
          ],
        );
      },
    );
    _pendingLockedDialogIndex = null;
    if (!mounted) return;
    if (shouldConfirm == true) {
      final purchased = await openMembershipPage(
        context,
        ref,
        showLoginPrompt: false,
      );
      if (!mounted) return;
      if (purchased) {
        await ref.read(memberStateProvider.notifier).refreshStatus();
        _clearPendingLockedOverlay();
        if (mounted) {
          setState(() {});
        }
        final retryIndex = lockedIndex ?? _pendingLockedEpisodeIndex;
        if (retryIndex != null) {
          await _jumpToEpisode(retryIndex);
        }
      }
      return;
    }
    setState(() {
      _pendingLockedEpisodeIndex = lockedIndex ?? _pendingLockedEpisodeIndex;
      _showWatchNowOverlay = _pendingLockedEpisodeIndex != null;
    });
  }

  Future<bool> _guardLockedEpisode(int index, {int? previousIndex}) async {
    if (!_isEpisodeLocked(index)) return true;
    final sourceIndex = previousIndex ?? _currentIndex;
    _pauseNearbyItems(sourceIndex);
    if (_currentIndex != index) {
      _currentIndex = index;
      _aliPlayerPreload?.moveTo(_currentIndex);
      _prefetchAround(_currentIndex);
    }
    _pauseNearbyItems(index);
    if (mounted) {
      setState(() {
        _pendingLockedEpisodeIndex = index;
        _showWatchNowOverlay = true;
      });
    }
    await _showMembershipReminderDialog(lockedIndex: index);
    return false;
  }

  void _clearPendingLockedOverlay() {
    if (!mounted) return;
    setState(() {
      _pendingLockedEpisodeIndex = null;
      _showWatchNowOverlay = false;
    });
  }

  Future<void> _jumpToEpisode(int index) async {
    if (index < 0 || index >= videoInfoList.length) return;
    if (index == _currentIndex) return;

    final previousIndex = _currentIndex;
    if (_isEpisodeLocked(index)) {
      if (_usePreloadMode) {
        _preloadPageController.jumpToPage(index);
      } else {
        _pageController.jumpToPage(index);
      }
      await _guardLockedEpisode(index, previousIndex: previousIndex);
      return;
    }

    _clearPendingLockedOverlay();
    if (_usePreloadMode) {
      _preloadPageController.jumpToPage(index);
    } else {
      _pageController.jumpToPage(index);
    }
    if (!mounted) return;
    _onPageChanged(index);
    _reportViewHistory(index);
  }

  Future<void> _playNextEpisode() async {
    final nextIndex = _currentIndex + 1;
    if (nextIndex >= videoInfoList.length) {
      return;
    }
    if (!mounted) return;
    await _jumpToEpisode(nextIndex);
  }

  Future<void> _handlePageChanged(int index, {int? previousIndex}) async {
    final sourceIndex = previousIndex ?? _currentIndex;
    if (index == sourceIndex) return;
    if (_isEpisodeLocked(index)) {
      await _guardLockedEpisode(index, previousIndex: sourceIndex);
      return;
    }
    _clearPendingLockedOverlay();
    _onPageChanged(index);
    _reportViewHistory(index);
  }

  void _showEpisodePicker() {
    final currentEpisode = videoInfoList[_currentIndex];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final memberState = ref.watch(memberStateProvider);
        return _WatchEpisodeBottomSheet(
          episodes: videoInfoList,
          currentIndex: _currentIndex,
          title: currentEpisode.title,
          coverUrl: currentEpisode.coverUrl,
          isVipUnlocked: memberState.isVip && !memberState.isExpired,
          onEpisodeTap: (index) async {
            Navigator.of(sheetContext).pop();
            await _jumpToEpisode(index);
          },
          onReportTap: () async {
            final router = GoRouter.of(context);
            _pauseCurrent();
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.of(sheetContext).pop();
            await Future<void>.delayed(const Duration(milliseconds: 260));
            if (!mounted) return;
            router.push('/profile/report');
          },
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

  String _formatActionCount(int count) {
    if (count > 999) return '999+';
    return count.toString();
  }

  Widget _buildDefaultTopOverlay(BuildContext context, VideoInfo videoInfo) {
    final isLockedCurrentEpisode =
        _showWatchNowOverlay && _pendingLockedEpisodeIndex == _currentIndex;
    if (isLockedCurrentEpisode) {
      return _buildTopOverlayContent(context, videoInfo);
    }

    return _buildTopOverlayContent(context, videoInfo);
  }

  Widget _buildTopOverlayContent(BuildContext context, VideoInfo videoInfo) {
    final episodeLabel = videoInfo.serialNum > 0 ? ' EP.${videoInfo.serialNum}' : '';
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
    final l10n = AppLocalizations.of(context);
    final videoId = videoInfo.videoId.toString();
    final actionState = ref.watch(videoActionProvider);

    final isLiked = actionState.isLiked(videoId, fallback: videoInfo.isLike == 1);
    final isCollected = actionState.isCollected(videoId, fallback: videoInfo.isCollect == 1);
    final likeCount = actionState.likeCount(videoId, fallback: videoInfo.likeNum);
    final collectCount = actionState.collectCount(videoId, fallback: videoInfo.collectNum);

    return Positioned(
      right: 12,
      bottom: _watchSideOverlayBottomInset(context),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSideActionButton(
              icon: isLiked ? Icons.favorite : Icons.favorite_border,
              label: _formatActionCount(likeCount),
              onTap: () => _toggleLike(videoInfo),
            ),
            const SizedBox(height: 16),
            _buildSideActionButton(
              icon: isCollected ? Icons.star_rounded : Icons.star_border_rounded,
              label: _formatActionCount(collectCount),
              onTap: () => _toggleCollect(videoInfo),
            ),
            const SizedBox(height: 16),
            _buildSideActionButton(
              icon: Icons.list_alt_rounded,
              label: l10n.episode,
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
    final lockedPreviewMode =
        _showWatchNowOverlay && index == _currentIndex && _isEpisodeLocked(index);
    return WatchShortVideoItem(
      key: _itemKeys[index],
      videoInfo: videoItem,
      autoPlay: autoPlay,
      resolvePlayableUrl: false,
      lockedPreviewMode: lockedPreviewMode,
      onLockedWatchNowTap: lockedPreviewMode
          ? () => _showMembershipReminderDialog(lockedIndex: index)
          : null,
      onCompleted: _playNextEpisode,
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
            preloadPagesCount: 2,
          )
        : PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: videoInfoList.length,
            itemBuilder: _buildItem,
            onPageChanged: _handlePageChanged,
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

class _WatchEpisodeBottomSheet extends StatefulWidget {
  const _WatchEpisodeBottomSheet({
    required this.episodes,
    required this.currentIndex,
    required this.title,
    required this.coverUrl,
    required this.isVipUnlocked,
    required this.onEpisodeTap,
    required this.onReportTap,
  });

  final List<VideoInfo> episodes;
  final int currentIndex;
  final String title;
  final String? coverUrl;
  final bool isVipUnlocked;
  final ValueChanged<int> onEpisodeTap;
  final VoidCallback onReportTap;

  @override
  State<_WatchEpisodeBottomSheet> createState() => _WatchEpisodeBottomSheetState();
}

class _WatchEpisodeBottomSheetState extends State<_WatchEpisodeBottomSheet> {
  static const Color _sheetColor = Color(0xFF202126);
  static const Color _tabColor = Color(0xFF323337);
  static const LinearGradient _activeGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF8F4EFF), Color(0xFFA237FF)],
  );

  late _EpisodeSheetTab _activeTab;
  late int _selectedSegment;

  @override
  void initState() {
    super.initState();
    _activeTab = _EpisodeSheetTab.episodes;
    _selectedSegment = widget.currentIndex ~/ 20;
  }

  List<List<int>> get _episodeSegments {
    final result = <List<int>>[];
    for (var start = 0; start < widget.episodes.length; start += 20) {
      final end = math.min(start + 20, widget.episodes.length);
      result.add(List<int>.generate(end - start, (index) => start + index));
    }
    return result;
  }

  List<int> get _currentSegmentEpisodes {
    if (_episodeSegments.isEmpty) return const [];
    return _episodeSegments[_selectedSegment.clamp(0, _episodeSegments.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final currentEpisode = widget.episodes[widget.currentIndex];
    final maxHeight = mediaQuery.size.height * 0.72;

    return SafeArea(
      top: false,
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: _sheetColor,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(15),
            topRight: Radius.circular(15),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(15, 15, 15, mediaQuery.padding.bottom + 15),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, currentEpisode),
                    const SizedBox(height: 15),
                    _buildTabs(context),
                    const SizedBox(height: 15),
                    Expanded(
                      child: _activeTab == _EpisodeSheetTab.episodes
                          ? _buildEpisodesPanel()
                          : _buildContentPanel(currentEpisode),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(
                top: 10,
                end: 0,
                child: _buildReportButton(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, VideoInfo currentEpisode) {
    final subtitle = currentEpisode.content.trim().isNotEmpty
        ? currentEpisode.content.trim()
        : 'Short drama series';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: widget.coverUrl != null && widget.coverUrl!.isNotEmpty
              ? Image.network(
                  widget.coverUrl!,
                  width: 80,
                  height: 114,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _buildCoverPlaceholder(),
                )
              : _buildCoverPlaceholder(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 114,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 72),
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: Color(0xFF999999),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  currentEpisode.serialNum > 0
                      ? '${widget.title} EP.${currentEpisode.serialNum}'
                      : '${widget.title} EP.${widget.currentIndex + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReportButton(BuildContext context) {
    final isArabic = Directionality.of(context) == TextDirection.rtl;
    return InkWell(
      onTap: widget.onReportTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.help_outline,
              size: 16,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              isArabic ? 'تقرير' : 'Report',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverPlaceholder() {
    return Container(
      width: 80,
      height: 114,
      color: const Color(0xFF323337),
      alignment: Alignment.center,
      child: const Icon(Icons.movie_creation_outlined, color: Colors.white38),
    );
  }

  Widget _buildTabs(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: _buildTabButton(
            label: l10n.episodes,
            isActive: _activeTab == _EpisodeSheetTab.episodes,
            onTap: () => setState(() => _activeTab = _EpisodeSheetTab.episodes),
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: _buildTabButton(
            label: 'Content',
            isActive: _activeTab == _EpisodeSheetTab.content,
            onTap: () => setState(() => _activeTab = _EpisodeSheetTab.content),
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton({
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        decoration: BoxDecoration(
          color: isActive ? null : _tabColor,
          gradient: isActive ? _activeGradient : null,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodesPanel() {
    final segments = _episodeSegments;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (segments.length > 1)
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: segments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (context, index) {
                final segment = segments[index];
                final startEpisode = widget.episodes[segment.first].serialNum > 0
                    ? widget.episodes[segment.first].serialNum
                    : segment.first + 1;
                final endEpisode = widget.episodes[segment.last].serialNum > 0
                    ? widget.episodes[segment.last].serialNum
                    : segment.last + 1;
                final isActive = index == _selectedSegment;
                return GestureDetector(
                  onTap: () => setState(() => _selectedSegment = index),
                  child: Text(
                    '$startEpisode-$endEpisode',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isActive ? const Color(0xFF8F4EFF) : Colors.white,
                    ),
                  ),
                );
              },
            ),
          ),
        if (segments.length > 1) const SizedBox(height: 15),
        Expanded(
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                const itemSize = 50.0;
                const minSpacing = 12.0;
                final columnCount = math.max(
                  1,
                  ((constraints.maxWidth + minSpacing) / (itemSize + minSpacing)).floor(),
                );
                final totalItemWidth = columnCount * itemSize;
                final spacing = columnCount > 1
                    ? math.max(
                        minSpacing,
                        (constraints.maxWidth - totalItemWidth) / (columnCount - 1),
                      )
                    : 0.0;

                return Wrap(
                  spacing: spacing,
                  runSpacing: 12,
                  children: _currentSegmentEpisodes.map((episodeIndex) {
                    final episode = widget.episodes[episodeIndex];
                    return SizedBox(
                      width: itemSize,
                      height: itemSize,
                      child: _buildEpisodeItem(episode, episodeIndex),
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeItem(VideoInfo episode, int index) {
    final isCurrent = index == widget.currentIndex;
    final isLocked = !widget.isVipUnlocked && episode.isCanPlay == 0;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return GestureDetector(
      onTap: () => widget.onEpisodeTap(index),
      child: Container(
        decoration: BoxDecoration(
          color: _tabColor,
          borderRadius: BorderRadius.circular(8),
          border: isCurrent
              ? Border.all(
                  width: 2,
                  color: const Color(0xFF8F4EFF),
                )
              : null,
        ),
        child: Stack(
          children: [
            Center(
              child: isCurrent
                  ? Image.asset(
                      'assets/images/playing_icon.png',
                      width: 22,
                      height: 22,
                    )
                  : Text(
                      '${episode.serialNum > 0 ? episode.serialNum : index + 1}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
            ),
            if (isLocked)
              PositionedDirectional(
                top: 1,
                start: 1,
                child: Image.asset(
                  isRtl
                      ? 'assets/images/play_lock_right_icon.png'
                      : 'assets/images/play_lock_icon.png',
                  width: 14,
                  height: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentPanel(VideoInfo currentEpisode) {
    final content = currentEpisode.content.trim();
    return SingleChildScrollView(
      child: Text(
        content,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
          color: Colors.white,
          height: 1.5,
        ),
      ),
    );
  }
}

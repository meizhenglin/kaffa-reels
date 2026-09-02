import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:preload_page_view/preload_page_view.dart';

import '../../l10n/app_localizations.dart';
import '../home/pages/main_page.dart';
import '../home/providers/last_watched_provider.dart';
import '../../core/ads/ad_mediator.dart';
import '../../core/ads/ad_config.dart';
import '../../core/network/api_service.dart';
import '../../core/storage/storage_service.dart';
import '../../core/widgets/app_snack_bar.dart';
import '../recommend/models/video_info.dart';
import '../recommend/providers/video_action_provider.dart';
import '../recommend/utils/drama_navigation.dart';
import '../auth/providers/auth_provider.dart';
import '../payment/providers/membership_provider.dart';
import '../payment/providers/coin_record_provider.dart';
import '../payment/widgets/unlock_bottom_sheet.dart';
import '../payment/models/unlock_product.dart';
import '../../app/providers/app_providers.dart';
import '../../core/widgets/share_button.dart';
import 'ali_player_preload.dart';
import 'watch_short_video_item.dart'
    if (dart.library.html) 'watch_short_video_item_web.dart';

enum VideoQuality { quality480P, quality720P, quality1080P }

const bool _showWatchPlaybackDebug = false;

enum _EpisodeSheetTab { episodes, content }

typedef ShortVideoOverlayBuilder =
    Widget Function(
      BuildContext context,
      VideoInfo videoInfo,
      int index,
      ShortVideoListController controller,
    );

typedef ShortVideoTopOverlayBuilder =
    Widget Function(
      BuildContext context,
      VideoInfo videoInfo,
      int index,
      ShortVideoListController controller,
    );

typedef ShortVideoForegroundBuilder =
    Widget Function(
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
  final Widget Function(
    BuildContext context,
    ShortVideoListController controller,
  )?
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
  final Widget Function(
    BuildContext context,
    ShortVideoListController controller,
  )?
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
  String _currentQuality = '480P';

  Future<void> _toggleLike(VideoInfo videoInfo) async {
    final videoId = videoInfo.videoId.toString();
    if (videoId.isEmpty || videoId == '0') return;

    final currentValue = ref
        .read(videoActionProvider)
        .isLiked(videoId, fallback: videoInfo.isLike == 1);
    final currentCount = ref
        .read(videoActionProvider)
        .likeCount(videoId, fallback: videoInfo.likeNum);
    await ref
        .read(videoActionProvider.notifier)
        .toggleLike(
          videoId: videoId,
          episodesId: videoInfo.id.toString(),
          currentValue: currentValue,
          currentCount: currentCount,
        );
  }

  Future<void> _toggleCollect(VideoInfo videoInfo) async {
    final videoId = videoInfo.videoId.toString();
    if (videoId.isEmpty || videoId == '0') return;

    final currentValue = ref
        .read(videoActionProvider)
        .isCollected(videoId, fallback: videoInfo.isCollect == 1);
    final currentCount = ref
        .read(videoActionProvider)
        .collectCount(videoId, fallback: videoInfo.collectNum);
    await ref
        .read(videoActionProvider.notifier)
        .toggleCollect(
          videoId: videoId,
          episodesId: videoInfo.id.toString(),
          currentValue: currentValue,
          currentCount: currentCount,
        );
  }

  Future<void> _shareVideo() async {
    final videoInfo = videoInfoList[_currentIndex];
    await showShareSheet(context, ShareContent.fromVideo(videoInfo));
  }

  late List<VideoInfo> videoInfoList;
  AliPlayerPreload? _aliPlayerPreload;
  late PageController _pageController;
  late PreloadPageController _preloadPageController;
  final ShortVideoListController _listController = ShortVideoListController();

  int _currentIndex = 0;
  List<GlobalKey<WatchShortVideoItemState>> _itemKeys = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isCurrentTabActive = false;
  bool _isDataLoaded = false;
  ProviderSubscription<int>? _tabIndexSubscription;
  int? _pendingLockedEpisodeIndex;
  bool _showWatchNowOverlay = false;
  int? _preLoginLockedIndex;
  bool _isShowingUnlockSheet = false;
  String? _pendingVideoId;

  void _setCurrentIndex(int index) {
    debugPrint('[_shortVideoPage] _setCurrentIndex: $_currentIndex -> $index');
    _currentIndex = index;
  }

  bool get _shouldFollowHomeTabVisibility => widget.videoId.isNotEmpty;

  bool get _usePreloadMode => widget.preload;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pendingVideoId = widget.videoId;
    _setupAuthListener();

    if (_usePreloadMode) {
      _preloadPageController = PreloadPageController(
        initialPage: _currentIndex,
      );
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

    // 预加载插屏广告
    AdMediator.instance.preloadInterstitialAd();

    if (_shouldFollowHomeTabVisibility) {
      _tabIndexSubscription = ref.listenManual<int>(currentTabIndexProvider, (
        previous,
        next,
      ) {
        if (!mounted) return;
        _isCurrentTabActive = next == 2;
        if (_isCurrentTabActive) {
          _resumeCurrent();
        } else {
          _pauseCurrent();
        }
      });
    }
  }

  void _setupAuthListener() {
    debugPrint(
      '[_shortVideoPage] _setupAuthListener called, videoId=${widget.videoId}',
    );

    // 监听 loginReturnProvider 来处理登录返回
    // 登录成功后刷新视频列表，确保 isCanPlay 状态是最新的
    ref.listenManual<int>(loginReturnProvider, (previous, next) {
      debugPrint(
        '[_shortVideoPage] loginReturnProvider changed: prev=$previous, next=$next',
      );
      if (next <= (previous ?? 0)) return;
      if (!mounted) return;

      // 登录返回后，刷新视频列表以更新 isCanPlay 状态
      debugPrint('[_shortVideoPage] refreshing video list after login');

      // 获取登录前要跳转的索引
      final targetIdx = ref.read(loginTargetVideoIndexProvider);
      final lockedIdx = ref.read(pendingUnlockEpisodeIndexProvider);
      debugPrint(
        '[_shortVideoPage] login returned, targetIdx=$targetIdx, lockedIdx=$lockedIdx',
      );

      // 设置刷新标记，这样 _fetchByVideoId 会使用 targetIdx
      ref.read(isRefreshingAfterLoginProvider.notifier).state = true;

      // 刷新视频列表，完成后 _checkAndShowUnlockDialog 会处理解锁弹窗
      _refreshVideoList();
    });

    // 同时监听 auth 状态用于其他用途（比如VIP状态变化）
    ref.listenManual<AuthState>(authProvider, (previous, next) {
      debugPrint(
        '[_shortVideoPage] auth changed: prev=${previous?.isAuthenticated}, next=${next.isAuthenticated}',
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

    debugPrint(
      '[$_tag] fetching by videoId=${widget.videoId}, _isDataLoaded=$_isDataLoaded',
    );
    final l10n = AppLocalizations.of(context);

    try {
      final dirResp = await apiServiceProvider.getEpisodesDirectoryByVideoId(
        videoId: widget.videoId,
      );
      if (!dirResp.isSuccess || dirResp.data == null) {
        _setError(l10n.loadCatalogFailed);
        return;
      }

      final dirData = Map<String, dynamic>.from(dirResp.data as Map);
      final videoMetadata = <String, dynamic>{
        ...dirData,
        if (dirData['videoInfo'] is Map)
          ...Map<String, dynamic>.from(dirData['videoInfo'] as Map),
      };
      final videoEpisodes =
          int.tryParse('${videoMetadata['videoEpisodes'] ?? ''}') ?? 10;
      final videoIntroduce =
          (videoMetadata['videoIntroduce'] as String?)?.trim() ?? '';

      final playResp = await apiServiceProvider.getVideoListByVideoId(
        videoId: widget.videoId,
        episodesNum: 1,
        pageSize: videoEpisodes,
      );
      if (!playResp.isSuccess || playResp.data is! List) {
        _setError(l10n.loadVideoFailed);
        return;
      }

      final videoMetadataInfo = VideoInfo.fromJson(videoMetadata);
      final videos =
          (playResp.data as List)
              .whereType<Map>()
              .map((item) {
                final episode = VideoInfo.fromJson(
                  Map<String, dynamic>.from(item).cast<String, dynamic>(),
                );
                return episode.copyWith(
                  content: episode.content.isEmpty && videoIntroduce.isNotEmpty
                      ? videoIntroduce
                      : episode.content,
                  isCollect:
                      episode.isCollect == 0 && videoMetadataInfo.isCollect == 1
                      ? 1
                      : episode.isCollect,
                  collectNum: episode.collectNum > 0
                      ? episode.collectNum
                      : videoMetadataInfo.collectNum,
                  isLike: episode.isLike == 0 && videoMetadataInfo.isLike == 1
                      ? 1
                      : episode.isLike,
                  likeNum: episode.likeNum > 0
                      ? episode.likeNum
                      : videoMetadataInfo.likeNum,
                );
              })
              .where((item) => item.videoUrl.isNotEmpty)
              .toList()
            ..sort((a, b) => a.serialNum.compareTo(b.serialNum));

      debugPrint(
        '[$_tag] fetched ${videos.length} videos, checking isCanPlay for each:',
      );
      for (int i = 0; i < videos.length && i < 15; i++) {
        debugPrint(
          '[$_tag]   episode[$i] serialNum=${videos[i].serialNum}, isCanPlay=${videos[i].isCanPlay}',
        );
      }

      if (videos.isEmpty) {
        _setError(l10n.noPlayableEpisodes);
        return;
      }

      videoInfoList = videos;

      // 检查是否是登录后刷新
      final isLoginRefresh = ref.read(isRefreshingAfterLoginProvider);
      final loginTargetIdx = ref.read(loginTargetVideoIndexProvider);

      final seedEpisodeId = widget.seedVideo?.id ?? 0;
      final savedEpisodesNum = StorageService().getLastEpisodesNum(
        widget.videoId,
      );
      final seedSerialNum = widget.seedVideo?.serialNum ?? savedEpisodesNum;
      final resolvedInitialIndex = seedEpisodeId > 0
          ? videoInfoList.indexWhere((item) => item.id == seedEpisodeId)
          : seedSerialNum > 0
          ? videoInfoList.indexWhere((item) => item.serialNum == seedSerialNum)
          : -1;

      // 如果是登录后刷新，优先使用 loginTargetIdx
      if (isLoginRefresh &&
          loginTargetIdx != null &&
          loginTargetIdx >= 0 &&
          loginTargetIdx < videoInfoList.length) {
        _currentIndex = loginTargetIdx;
        debugPrint(
          '[$_tag] login refresh: using loginTargetIdx=$loginTargetIdx for current index',
        );
      } else {
        _currentIndex = resolvedInitialIndex >= 0
            ? resolvedInitialIndex
            : widget.initialIndex.clamp(0, videoInfoList.length - 1);
      }

      if (_usePreloadMode) {
        _preloadPageController.removeListener(_handlePreloadPageChanged);
        _preloadPageController.dispose();
        _preloadPageController = PreloadPageController(
          initialPage: _currentIndex,
        );
        _preloadPageController.addListener(_handlePreloadPageChanged);
      } else {
        _pageController.dispose();
        _pageController = PageController(initialPage: _currentIndex);
      }

      // 复用已有的 _itemKeys，只在需要时扩展
      if (_itemKeys.length < videoInfoList.length) {
        final needed = videoInfoList.length - _itemKeys.length;
        _itemKeys.addAll(
          List.generate(needed, (_) => GlobalKey<WatchShortVideoItemState>()),
        );
      }

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
          // _itemKeys 已经在上面扩展，不需要在这里重新赋值
        });
      }

      debugPrint('[$_tag] fetchByVideoId completed successfully');

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

        // 如果是登录后刷新，检查是否需要显示解锁弹窗
        if (ref.read(isRefreshingAfterLoginProvider)) {
          _checkAndShowUnlockDialog();
        }
      });
    } catch (e) {
      debugPrint('[$_tag] fetchByVideoId error=$e');
      _setError(l10n.loadFailed);
    }
  }

  void _loadData() {
    if (_isDataLoaded) return;
    _isDataLoaded = true;
    _fetchByVideoId();
  }

  void _refreshVideoList() {
    debugPrint('[_refreshVideoList] called, mounted=$mounted');
    // 标记为正在加载，防止重复调用
    _isDataLoaded = true;
    _fetchByVideoId();
  }

  /// 检查登录后是否需要显示解锁弹窗
  /// 只有当目标剧集未解锁时才显示
  void _checkAndShowUnlockDialog() {
    debugPrint('[_checkAndShowUnlockDialog] called');

    // 获取登录前的目标索引
    final lockedIdx = ref.read(pendingUnlockEpisodeIndexProvider);
    if (lockedIdx == null) {
      debugPrint('[_checkAndShowUnlockDialog] no lockedIdx, skipping');
      _clearLoginState();
      return;
    }

    // 检查该剧集是否已经解锁（isCanPlay == 1 表示可播放）
    if (videoInfoList.isNotEmpty &&
        lockedIdx >= 0 &&
        lockedIdx < videoInfoList.length) {
      final isCanPlay = videoInfoList[lockedIdx].isCanPlay;
      debugPrint(
        '[_checkAndShowUnlockDialog] lockedIdx=$lockedIdx, isCanPlay=$isCanPlay',
      );

      if (isCanPlay == 1) {
        // 已经解锁，不需要显示解锁弹窗
        debugPrint(
          '[_checkAndShowUnlockDialog] episode is already unlocked, skipping unlock dialog',
        );
        _clearLoginState();
        return;
      }
    }

    // 未解锁，显示解锁弹窗
    debugPrint('[_checkAndShowUnlockDialog] showing unlock sheet');
    _isShowingUnlockSheet = true;

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _showMembershipReminderDialog(lockedIndex: lockedIdx).then((_) {
        _isShowingUnlockSheet = false;
        _clearLoginState();
      });
    });
  }

  /// 清除登录相关的状态
  void _clearLoginState() {
    ref.read(pendingUnlockEpisodeIndexProvider.notifier).state = null;
    ref.read(pendingUnlockVideoIdProvider.notifier).state = null;
    ref.read(loginTargetVideoIndexProvider.notifier).state = null;
    ref.read(isRefreshingAfterLoginProvider.notifier).state = false;
  }

  /// 滚动到指定索引的视频
  void _scrollToIndex(int index) {
    debugPrint('[_scrollToIndex] scrolling to index $index');
    if (!mounted) return;

    if (index < 0) {
      debugPrint('[_scrollToIndex] index $index is negative, skipping');
      return;
    }

    // 如果列表还未加载完成，等待一下再尝试
    if (!_isDataLoaded || videoInfoList.isEmpty) {
      debugPrint('[_scrollToIndex] list not loaded yet, deferring...');
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _scrollToIndex(index);
      });
      return;
    }

    final safeIndex = index.clamp(0, videoInfoList.length - 1);

    if (_pageController.hasClients) {
      debugPrint('[_scrollToIndex] jumping to page $safeIndex');
      _pageController.jumpToPage(safeIndex);
    } else {
      debugPrint('[_scrollToIndex] pageController not ready, deferring...');
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        _scrollToIndex(index);
      });
    }
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

    // 保存切换后的集号到本地存储
    if (newPageIndex < videoInfoList.length) {
      final newSerialNum = videoInfoList[newPageIndex].serialNum;
      if (newSerialNum > 0) {
        StorageService().saveLastEpisodesNum(widget.videoId, newSerialNum);
      }
    }

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
    if (widget.videoId.isEmpty || episodesId.isEmpty || episodesId == '0')
      return;

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
    // Use the featureAccessProvider which checks VIP status from Google Play
    final hasPremium = ref.watch(featureAccessProvider(Feature.premiumContent));
    if (hasPremium) {
      return false;
    }
    return videoInfoList[index].isCanPlay == 0;
  }

  /// 获取第一个未解锁的剧集索引（按顺序解锁检查用）
  int _getFirstUnlockedIndex() {
    for (int i = 0; i < videoInfoList.length; i++) {
      if (_isEpisodeLocked(i)) {
        return i;
      }
    }
    return -1; // 全部已解锁
  }

  Future<void> _showMembershipReminderDialog({int? lockedIndex}) async {
    debugPrint(
      '[_showMembershipReminderDialog] called with lockedIndex=$lockedIndex, currentIndex=$_currentIndex, videoInfoList.length=${videoInfoList.length}',
    );
    if (_pendingLockedDialogIndex == lockedIndex) return;
    _pendingLockedDialogIndex = lockedIndex;

    final index = lockedIndex ?? _currentIndex;

    // 先尝试自动解锁
    debugPrint('[_showMembershipReminderDialog] trying auto unlock first...');
    final autoUnlockSuccess = await _tryAutoUnlockWithBalance(index);
    debugPrint(
      '[_showMembershipReminderDialog] autoUnlockSuccess=$autoUnlockSuccess',
    );

    if (autoUnlockSuccess) {
      _pendingLockedDialogIndex = null;
      return; // 自动解锁成功，不显示半屏
    }

    // 自动解锁失败，显示解锁半屏
    await _showUnlockBottomSheet(lockedIndex: lockedIndex);

    _pendingLockedDialogIndex = null;
    if (!mounted) return;

    debugPrint(
      '[_showMembershipReminderDialog] after bottom sheet, setting state',
    );
    setState(() {
      _pendingLockedEpisodeIndex = lockedIndex ?? _pendingLockedEpisodeIndex;
      _showWatchNowOverlay = _pendingLockedEpisodeIndex != null;
      debugPrint(
        '[_showMembershipReminderDialog] _showWatchNowOverlay=$_showWatchNowOverlay, _pendingLockedEpisodeIndex=$_pendingLockedEpisodeIndex',
      );
    });
  }

  /// 显示K币解锁半屏
  Future<void> _showUnlockBottomSheet({int? lockedIndex}) async {
    final index = lockedIndex ?? _currentIndex;
    if (index < 0 || index >= videoInfoList.length) return;

    final videoInfo = videoInfoList[index];
    final videoId = videoInfo.videoId.toString();
    final episodeId = videoInfo.id.toString();
    final dramaTitle = videoInfo.title;

    // 从API获取商品列表
    List<UnlockProduct> allProducts = [];
    try {
      final apiService = ApiService(
        dioClient: ref.read(dioClientProvider),
        storage: ref.read(storageServiceProvider),
      );
      debugPrint(
        '[_showUnlockBottomSheet] Fetching products for videoId: $videoId',
      );
      final resp = await apiService.getQuickRechargeList(videoId: videoId);
      debugPrint(
        '[_showUnlockBottomSheet] Response success: ${resp.isSuccess}, data: ${resp.data}, error: ${resp.error}',
      );
      if (resp.isSuccess && resp.data != null) {
        final data = resp.data!;
        debugPrint('[_showUnlockBottomSheet] Data type: ${data.runtimeType}');
        if (data is List) {
          debugPrint('[_showUnlockBottomSheet] List length: ${data.length}');
          for (final item in data) {
            if (item is Map<String, dynamic>) {
              debugPrint(
                '[_showUnlockBottomSheet] Item: ${item['rechargeGoodsName']}',
              );
              final goodsType = item['rechargeGoodsType'] as int? ?? 0;
              UnlockProductType type = UnlockProductType.episode;
              if (goodsType == 1) {
                type = UnlockProductType.coinRecharge;
              } else if (goodsType == 2) {
                type = UnlockProductType.season; // 整剧解锁
              } else if (goodsType == 0) {
                final name = (item['rechargeGoodsName'] ?? '')
                    .toString()
                    .toLowerCase();
                if (name.contains('vip') ||
                    name.contains('monthly') ||
                    name.contains('season') ||
                    name.contains('annual')) {
                  type = UnlockProductType.vip;
                }
              }
              allProducts.add(
                UnlockProduct(
                  goodsId: item['id'] as int? ?? 0,
                  goodsName: item['rechargeGoodsName']?.toString() ?? '',
                  price:
                      (item['rechargeGoodsPrice'] as num?)?.toDouble() ?? 0.0,
                  type: type,
                  originalPrice: _parseOriginalPrice(
                    item['rechargeGoodsSubname']?.toString(),
                  ),
                  googlePlayId: item['remarks']?.toString(),
                ),
              );
            }
          }
        }
      }
      debugPrint(
        '[_showUnlockBottomSheet] allProducts length: ${allProducts.length}',
      );
    } catch (e, stack) {
      debugPrint('[_showUnlockBottomSheet] Failed to load products: $e');
      debugPrint('[_showUnlockBottomSheet] Stack trace: $stack');
    }

    // 构建解锁配置
    final config = UnlockConfig(
      videoId: videoId,
      episodeUnlockPrice: (videoInfo.unlockPrice ?? 0).toDouble(),
      allProducts: allProducts,
    );

    final result = await UnlockBottomSheet.show(
      context: context,
      videoId: videoId,
      episodeId: episodeId,
      episodesNum: videoInfo.serialNum,
      episodeIndex: index,
      dramaTitle: dramaTitle,
      coverUrl: videoInfo.coverUrl,
      config: config,
      onUnlockSuccess: (episodeIndex) {
        // 解锁成功后更新状态
        if (episodeIndex < videoInfoList.length) {
          final updatedInfo = videoInfoList[episodeIndex].copyWith(
            isCanPlay: 1,
          );
          videoInfoList[episodeIndex] = updatedInfo;
        }
      },
      onVipPurchaseSuccess: () {
        // VIP购买成功后刷新用户状态
        ref.read(authProvider.notifier).refreshUserInfo();
        ref.invalidate(isVipProvider);
      },
    );

    debugPrint(
      '[_showUnlockBottomSheet] returned from bottom sheet, result=$result, index=$index',
    );

    if (!mounted) return;

    // 处理解锁结果
    if (result == null) {
      // 用户关闭弹窗或取消，恢复 watch now 状态
      debugPrint(
        '[_showUnlockBottomSheet] result is null, restoring overlay. _pendingLockedEpisodeIndex=$_pendingLockedEpisodeIndex, currentIndex=$index',
      );
      if (mounted) {
        setState(() {
          _showWatchNowOverlay = _pendingLockedEpisodeIndex != null;
          debugPrint(
            '[_showUnlockBottomSheet] setState called: _showWatchNowOverlay=$_showWatchNowOverlay',
          );
        });
      }
      return;
    }

    if (result.isSuccess) {
      _clearPendingLockedOverlay();
      if (mounted) {
        setState(() {
          // 更新该集的可播放状态
          videoInfoList[index] = videoInfo.copyWith(isCanPlay: 1);
        });
        // 显示成功提示
        final l10n = AppLocalizations.of(context);
        AppSnackBar.show(context, message: l10n.unlockSuccess);
        // 重试播放
        final retryIndex = lockedIndex ?? _pendingLockedEpisodeIndex;
        if (retryIndex != null) {
          await _jumpToEpisode(retryIndex);
        }
      }
    } else if (result.isFailed) {
      // 失败，显示错误消息
      if (result.errorMessage != null && mounted) {
        AppSnackBar.show(context, message: result.errorMessage!);
      }
    } else if (result.isCancelled) {
      // 用户取消
      debugPrint('[_showUnlockBottomSheet] result.isCancelled');
    } else if (result.isLoginRequired) {
      // 游客需要登录，记录当前锁定的集索引和 videoId 到全局状态
      debugPrint(
        '[_showUnlockBottomSheet] result.isLoginRequired, setting _preLoginLockedIndex=$index',
      );
      _preLoginLockedIndex = index;
      ref.read(pendingUnlockEpisodeIndexProvider.notifier).state = index;
      ref.read(pendingUnlockVideoIdProvider.notifier).state = widget.videoId;
      ref.read(loginTargetVideoIndexProvider.notifier).state = index;
      debugPrint(
        '[_showUnlockBottomSheet] saved to providers: idx=$index, videoId=${widget.videoId}',
      );
      if (mounted) {
        // 使用 push 导航到登录页，ShortVideoPage 会保留在栈中
        final redirectUrl =
            '/short-video?videoId=${Uri.encodeComponent(widget.videoId)}&initialIndex=$index';
        debugPrint(
          '[_showUnlockBottomSheet] going to login with redirect: $redirectUrl',
        );
        context.push(
          '/auth/login?redirect=${Uri.encodeComponent(redirectUrl)}',
        );
      }
    } else if (result.isVip) {
      // VIP 订阅成功:关闭锁定 overlay,刷新用户信息与 VIP 状态,
      // 然后跳到当前集播放(VIP 用户通常可以直接观看)。
      debugPrint('[_showUnlockBottomSheet] result.isVip');
      _clearPendingLockedOverlay();
      if (mounted) {
        setState(() {
          videoInfoList[index] = videoInfo.copyWith(isCanPlay: 1);
        });
        await ref.read(authProvider.notifier).refreshUserInfo();
        ref.invalidate(isVipProvider);
        final retryIndex = lockedIndex ?? _pendingLockedEpisodeIndex;
        if (retryIndex != null) {
          await _jumpToEpisode(retryIndex);
        }
      }
    }
  }

  /// 解析原价（rechargeGoodsSubname 可能是 "100" 表示原价100）
  double? _parseOriginalPrice(String? subname) {
    if (subname == null || subname.isEmpty) return null;
    return double.tryParse(subname);
  }

  Future<bool> _guardLockedEpisode(int index, {int? previousIndex}) async {
    debugPrint('[_guardLockedEpisode] called with index=$index');
    if (!_isEpisodeLocked(index)) {
      debugPrint('[_guardLockedEpisode] episode not locked, returning true');
      return true;
    }
    final sourceIndex = previousIndex ?? _currentIndex;
    _pauseNearbyItems(sourceIndex);
    if (_currentIndex != index) {
      _currentIndex = index;
      _aliPlayerPreload?.moveTo(_currentIndex);
      _prefetchAround(_currentIndex);
    }
    _pauseNearbyItems(index);
    // Verify the balance and complete automatic coin unlock before rendering
    // the locked-state actions. This prevents them flashing for funded users.
    debugPrint('[_guardLockedEpisode] trying auto unlock...');
    final autoUnlockSuccess = await _tryAutoUnlockWithBalance(index);
    debugPrint('[_guardLockedEpisode] autoUnlockSuccess=$autoUnlockSuccess');
    if (autoUnlockSuccess) {
      return true;
    }

    // Only show ad and purchase actions when automatic coin unlock is unavailable.
    if (mounted) {
      setState(() {
        _pendingLockedEpisodeIndex = index;
        _showWatchNowOverlay = true;
      });
    }

    debugPrint(
      '[_guardLockedEpisode] automatic unlock unavailable, showing locked actions',
    );
    return false;
  }

  /// 尝试使用激励广告解锁剧集
  /// 用户完整看完一则激励广告，即可解锁当前 VIP 锁定剧集
  /// 这条路径对游客和登录用户都开放,无需登录。
  /// 返回 true 表示解锁成功，false 表示用户未完成观看或广告未就绪
  Future<bool> _tryUnlockWithRewardedAd(int index) async {
    debugPrint('[_tryUnlockWithRewardedAd] START - index=$index');
    if (index < 0 || index >= videoInfoList.length) {
      return false;
    }

    // 检查是否按顺序解锁：只能解锁第一个未解锁的剧集
    final firstUnlockedIndex = _getFirstUnlockedIndex();
    debugPrint(
      '[_tryUnlockWithRewardedAd] firstUnlockedIndex=$firstUnlockedIndex, requested index=$index',
    );

    if (index != firstUnlockedIndex) {
      // 不是按顺序解锁，提示用户
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        AppSnackBar.show(context, message: l10n.unlockToContinue);
      }
      return false;
    }

    // 广告未就绪时，先尝试触发加载（AdMediator 内部会自动重试）。
    // 游客场景下 token 为空也能走到这里,后端 request 会以无 token 方式发请求。
    if (!AdMediator.instance.isRewardedAdReady()) {
      debugPrint(
        '[_tryUnlockWithRewardedAd] No ad platform ready, triggering preload...',
      );
      AdMediator.instance.preloadRewardedAd();
    }

    final episode = videoInfoList[index];

    // This endpoint verifies an AdMob placement, so Meta rewards cannot unlock
    // episodes through this entry point.
    final shown = await AdMediator.instance.showRewardedAd(
      preferredPlatform: AdPlatform.admob,
      allowPlatformFallback: false,
      onRewardEarned: () async {
        debugPrint(
          '[_tryUnlockWithRewardedAd] user earned AdMob reward, unlocking episode',
        );
        try {
          final apiService = ApiService(
            dioClient: ref.read(dioClientProvider),
            storage: ref.read(storageServiceProvider),
          );
          final unlockResp = await apiService.admobUnlockEpisodes(
            videoId: widget.videoId,
            episodesNum: episode.serialNum,
            adUnitId: AdConfig.admobRewardedAdUnitId,
          );
          debugPrint(
            '[_tryUnlockWithRewardedAd] backend unlock isSuccess=${unlockResp.isSuccess}',
          );

          if (!mounted) return;
          if (unlockResp.isSuccess) {
            setState(() {
              videoInfoList[index] = episode.copyWith(isCanPlay: 1);
              _pendingLockedEpisodeIndex = null;
              _showWatchNowOverlay = false;
            });
            final l10n = AppLocalizations.of(context);
            AppSnackBar.show(context, message: l10n.unlockSuccess);
            _clearPendingLockedOverlay();
            _onPageChanged(index);
            _reportViewHistory(index);
          } else {
            // 后端未返回成功，仍然更新本地状态（前端体验优先），由后续同步逻辑兜底
            setState(() {
              videoInfoList[index] = episode.copyWith(isCanPlay: 1);
              _pendingLockedEpisodeIndex = null;
              _showWatchNowOverlay = false;
            });
          }
        } catch (e) {
          debugPrint('[_tryUnlockWithRewardedAd] backend unlock exception: $e');
          if (mounted) {
            setState(() {
              videoInfoList[index] = episode.copyWith(isCanPlay: 1);
              _pendingLockedEpisodeIndex = null;
              _showWatchNowOverlay = false;
            });
          }
        }
      },
      onNotReady: () {
        debugPrint('[_tryUnlockWithRewardedAd] No ad ready on any platform');
        // 所有广告平台都未就绪时，提示用户稍后重试
        if (mounted) {
          AppSnackBar.show(
            context,
            message: 'Ad is loading, please try again in a moment',
          );
        }
      },
    );

    return shown;
  }

  /// 尝试使用 K币余额自动解锁剧集
  /// 返回 true 表示解锁成功，false 表示余额不足
  Future<bool> _tryAutoUnlockWithBalance(int index) async {
    debugPrint('[_tryAutoUnlockWithBalance] START - index=$index');
    if (index < 0 || index >= videoInfoList.length) {
      debugPrint('[_tryAutoUnlockWithBalance] FAIL: index out of range');
      return false;
    }

    // 检查是否已登录
    final authState = ref.read(authProvider);
    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      debugPrint('[_tryAutoUnlockWithBalance] FAIL: not logged in');
      return false;
    }

    final episode = videoInfoList[index];
    final episodePrice = episode.unlockPrice ?? 0;
    debugPrint(
      '[_tryAutoUnlockWithBalance] episode id=${episode.id}, price=$episodePrice',
    );

    // 获取当前余额
    final coinNotifier = ref.read(coinBalanceInfoProvider.notifier);
    await coinNotifier.load();
    final balance = ref.read(coinBalanceInfoProvider).balance;
    debugPrint(
      '[_tryAutoUnlockWithBalance] balance=$balance, episodePrice=$episodePrice',
    );

    // 检查余额是否足够
    if (balance < episodePrice) {
      debugPrint('[_tryAutoUnlockWithBalance] FAIL: insufficient balance');
      return false;
    }

    // 余额足够，自动解锁
    debugPrint('[_tryAutoUnlockWithBalance] auto unlocking...');

    try {
      final apiService = ApiService(
        dioClient: ref.read(dioClientProvider),
        storage: ref.read(storageServiceProvider),
      );

      // 调用后端 API 解锁
      final unlockResp = await apiService.getUserPayEpisodes(
        videoId: widget.videoId,
        episodesId: episode.id.toString(),
        episodesNum: episode.serialNum,
      );

      debugPrint(
        '[_tryAutoUnlockWithBalance] unlockResp.isSuccess=${unlockResp.isSuccess}, error=${unlockResp.error}',
      );

      if (unlockResp.isSuccess) {
        // 解锁成功，扣减余额并刷新
        coinNotifier.deductCoins(episodePrice);
        await coinNotifier.load();

        // 更新本地视频状态
        setState(() {
          videoInfoList[index] = episode.copyWith(isCanPlay: 1);
          _pendingLockedEpisodeIndex = null;
          _showWatchNowOverlay = false;
        });

        // 显示成功提示
        if (mounted) {
          final l10n = AppLocalizations.of(context);
          AppSnackBar.show(
            context,
            message: '${l10n.unlockSuccess} -$episodePrice K Coin',
          );
        }
        debugPrint('[_tryAutoUnlockWithBalance] SUCCESS');
        return true;
      } else {
        debugPrint('[_tryAutoUnlockWithBalance] FAIL: unlock API failed');
        return false;
      }
    } catch (e, stack) {
      debugPrint('[_tryAutoUnlockWithBalance] FAIL: exception $e');
      debugPrint('[_tryAutoUnlockWithBalance] stack: $stack');
      return false;
    }
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
    if (nextIndex >= videoInfoList.length || !mounted) {
      return;
    }

    // Free episodes advance directly. Ads remain available only when a user
    // explicitly chooses the rewarded-ad option to unlock a locked episode.
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
        return _WatchEpisodeBottomSheet(
          episodes: videoInfoList,
          currentIndex: _currentIndex,
          title: currentEpisode.title,
          coverUrl: currentEpisode.coverUrl,
          isVipUnlocked: ref.watch(
            featureAccessProvider(Feature.premiumContent),
          ),
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
    final episodeLabel = videoInfo.serialNum > 0
        ? ' EP.${videoInfo.serialNum}'
        : '';
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
            _buildQualityButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityButton(BuildContext context) {
    return GestureDetector(
      onTap: () => _showQualityPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _currentQuality,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 2),
            Image.asset('assets/images/hd_icon.png', width: 24, height: 24),
          ],
        ),
      ),
    );
  }

  void _showQualityPicker(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasPremium = ref.watch(featureAccessProvider(Feature.hdQuality));
    final isVip = hasPremium;
    final screenWidth = MediaQuery.of(context).size.width;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          width: screenWidth,
          height: 150,
          decoration: const BoxDecoration(
            color: Color(0xFF15161A),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(15),
              topRight: Radius.circular(15),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l10n.unlockClarityLevel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                            color: Color(0xFFFFFFFF),
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.of(sheetContext).pop(),
                          child: Image.asset(
                            'assets/images/clarity_cancel_icon.png',
                            width: 12,
                            height: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 5, bottom: 20),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildQualityItem('480P', true, sheetContext),
                          const Spacer(),
                          _buildQualityItem('720P', true, sheetContext),
                          const Spacer(),
                          _buildQualityItem('1080P', isVip, sheetContext),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ).then((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  Widget _buildQualityItem(
    String label,
    bool isVipUnlocked,
    BuildContext sheetContext,
  ) {
    final is1080 = label == '1080P';
    final canTap = !is1080 || isVipUnlocked;
    return GestureDetector(
      onTap: () {
        if (is1080 && !isVipUnlocked) {
          Navigator.of(sheetContext).pop();
          _showVipPurchaseDialog();
          return;
        }
        if (canTap) {
          Navigator.of(sheetContext).pop();
          setState(() {
            _currentQuality = label;
          });
        }
      },
      child: SizedBox(
        width: 106,
        height: 40,
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: is1080 ? null : const Color(0xFF2D2E32),
            borderRadius: BorderRadius.circular(10),
            image: is1080
                ? const DecorationImage(
                    image: AssetImage('assets/images/clarity_bg.png'),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (is1080)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Image(
                    image: AssetImage('assets/images/vip_icon.png'),
                    width: 24,
                    height: 19,
                  ),
                ),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: is1080 ? const Color(0xFF3A1D00) : Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showVipPurchaseDialog() async {
    final l10n = AppLocalizations.of(context);
    final dialogContext = context;
    final shouldConfirm = await showDialog<bool>(
      context: dialogContext,
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
    if (!mounted) return;
    if (shouldConfirm != true) return;

    _pauseCurrent();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    final alreadyVip = ref.read(isVipProvider);
    if (!alreadyVip) {
      await openMembershipPage(context, ref, showLoginPrompt: false);
    }

    if (!mounted) return;
    await ref.read(memberStateProvider.notifier).refreshStatus();
    await ref.read(authProvider.notifier).refreshUserInfo();
    if (mounted) {
      setState(() {
        if (ref.read(featureAccessProvider(Feature.hdQuality))) {
          _currentQuality = '1080P';
        }
      });
    }
    if (mounted) {
      _resumeCurrent();
    }
  }

  Widget _buildDefaultSideOverlay(BuildContext context, VideoInfo videoInfo) {
    final l10n = AppLocalizations.of(context);
    final videoId = videoInfo.videoId.toString();
    final actionState = ref.watch(videoActionProvider);

    final isLiked = actionState.isLiked(
      videoId,
      fallback: videoInfo.isLike == 1,
    );
    final isCollected = actionState.isCollected(
      videoId,
      fallback: videoInfo.isCollect == 1,
    );
    final likeCount = actionState.likeCount(
      videoId,
      fallback: videoInfo.likeNum,
    );
    final collectCount = actionState.collectCount(
      videoId,
      fallback: videoInfo.collectNum,
    );

    return Positioned(
      right: 12,
      bottom: _watchSideOverlayBottomInset(context),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSideImageButton(
              activeImage: 'assets/images/like_active.png',
              inactiveImage: 'assets/images/like.png',
              label: _formatActionCount(likeCount),
              onTap: () => _toggleLike(videoInfo),
              isActive: isLiked,
            ),
            const SizedBox(height: 16),
            _buildSideImageButton(
              activeImage: 'assets/images/collection_active.png',
              inactiveImage: 'assets/images/collection.png',
              label: _formatActionCount(collectCount),
              onTap: () => _toggleCollect(videoInfo),
              isActive: isCollected,
            ),
            const SizedBox(height: 16),
            _buildSideImageButton(
              activeImage: 'assets/images/share.png',
              inactiveImage: 'assets/images/share.png',
              label: l10n.share,
              onTap: _shareVideo,
            ),
            const SizedBox(height: 16),
            _buildSideImageButton(
              activeImage: 'assets/images/series.png',
              inactiveImage: 'assets/images/series.png',
              label: l10n.episode,
              onTap: _showEpisodePicker,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSideImageButton({
    required String activeImage,
    required String inactiveImage,
    required String label,
    required VoidCallback onTap,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            isActive ? activeImage : inactiveImage,
            width: 44,
            height: 44,
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
        _showWatchNowOverlay &&
        index == _currentIndex &&
        _isEpisodeLocked(index);
    return WatchShortVideoItem(
      key: _itemKeys[index],
      videoInfo: videoItem,
      autoPlay: autoPlay,
      resolvePlayableUrl: false,
      lockedPreviewMode: lockedPreviewMode,
      onLockedWatchNowTap: lockedPreviewMode
          ? () => _showMembershipReminderDialog(lockedIndex: index)
          : null,
      onWatchAdToUnlock: lockedPreviewMode
          ? () => _tryUnlockWithRewardedAd(index)
          : null,
      onCompleted: _playNextEpisode,
      quality: _currentQuality,
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
          children.add(
            widget.topOverlayBuilder!(ctx, vi, index, _listController),
          );
        }
        return Stack(children: children);
      },
      showDebugInfo: _showWatchPlaybackDebug,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              child: Text(
                l10n.back,
                style: const TextStyle(color: Colors.white),
              ),
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

    if (widget.foregroundBuilder == null &&
        widget.floatingOverlayBuilder == null) {
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
  State<_WatchEpisodeBottomSheet> createState() =>
      _WatchEpisodeBottomSheetState();
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
    return _episodeSegments[_selectedSegment.clamp(
      0,
      _episodeSegments.length - 1,
    )];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final mediaQuery = MediaQuery.of(context);
    final safeIndex = widget.currentIndex.clamp(
      0,
      widget.episodes.isEmpty ? 0 : widget.episodes.length - 1,
    );
    final currentEpisode = widget.episodes.isNotEmpty
        ? widget.episodes[safeIndex]
        : null;
    final maxHeight = mediaQuery.size.height * 0.72;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: const BoxDecoration(
        color: _sheetColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(15),
          topRight: Radius.circular(15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(15, 15, 15, 15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (currentEpisode != null) _buildHeader(context, currentEpisode),
            const SizedBox(height: 15),
            _buildTabs(context),
            const SizedBox(height: 15),
            Expanded(
              child: _activeTab == _EpisodeSheetTab.episodes
                  ? _buildEpisodesPanel()
                  : (currentEpisode != null
                        ? _buildContentPanel(currentEpisode)
                        : const SizedBox()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, VideoInfo currentEpisode) {
    final l10n = AppLocalizations.of(context);
    final subtitle = currentEpisode.content.trim().isNotEmpty
        ? currentEpisode.content.trim()
        : l10n.shortDramaSeries;
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
            child: Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                      color: Color(0xFF999999),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    currentEpisode.serialNum > 0
                        ? '${widget.title} EP.${currentEpisode.serialNum}'
                        : '${widget.title} EP.${widget.currentIndex + 1}',
                    textAlign: TextAlign.center,
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
        ),
      ],
    );
  }

  Widget _buildReportButton(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return InkWell(
      onTap: widget.onReportTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.help_outline, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              l10n.report,
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
            label: l10n.content,
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
    final l10n = AppLocalizations.of(context);
    final segments = _episodeSegments;
    if (segments.isEmpty || widget.episodes.isEmpty) {
      return Center(
        child: Text(
          l10n.noEpisodesAvailable,
          style: const TextStyle(color: Colors.white54),
        ),
      );
    }
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
                final startEpisode =
                    widget.episodes[segment.first].serialNum > 0
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
                  ((constraints.maxWidth + minSpacing) /
                          (itemSize + minSpacing))
                      .floor(),
                );
                final totalItemWidth = columnCount * itemSize;
                final spacing = columnCount > 1
                    ? math.max(
                        minSpacing,
                        (constraints.maxWidth - totalItemWidth) /
                            (columnCount - 1),
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
              ? Border.all(width: 2, color: const Color(0xFF8F4EFF))
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

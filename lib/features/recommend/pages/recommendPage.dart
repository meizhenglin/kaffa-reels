// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 沉浸式列表播放页面
//
// 数据流向：Riverpod(VideoFeedNotifier) → Repository → AuthService → DioClient → API
// UI 只负责：展示 loading/视频列表/错误状态，不处理任何业务逻辑

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:preload_page_view/preload_page_view.dart';
import 'package:qahwa_tv/l10n/app_localizations.dart';

import '../../home/pages/main_page.dart';
import '../../commonAliPlayer/short_video_item.dart';
import '../../commonAliPlayer/short_video_preload_tuning.dart';
import '../models/video_info.dart';
import '../providers/recommend_provider.dart';
import '../providers/video_action_provider.dart';
import '../../commonAliPlayer/ali_player_preload.dart';

const bool _showRecommendPlaybackDebug = false;

/// 沉浸式列表播放页面
class ShortVideoPage extends ConsumerStatefulWidget {
  const ShortVideoPage({super.key});

  @override
  ConsumerState<ShortVideoPage> createState() => _ShortVideoPageState();
}

class _ShortVideoPageState extends ConsumerState<ShortVideoPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(videoFeedProvider.notifier).loadVideos();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoFeedProvider);

    if (state.status == VideoFeedStatus.initial ||
        state.status == VideoFeedStatus.loading) {
      return const _LoadingView();
    }

    if (state.status == VideoFeedStatus.error || state.videos.isEmpty) {
      return _ErrorView(
        message: state.errorMessage,
        onRetry: () => ref.read(videoFeedProvider.notifier).loadVideos(),
      );
    }

    return ShortVideoListPage(videos: state.videos);
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const CircularProgressIndicator(),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;

  const _ErrorView({this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.white54, size: 48),
          const SizedBox(height: 16),
          Text(
            message ?? 'Failed to load videos',
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// 沉浸式列表组件
class ShortVideoListPage extends ConsumerStatefulWidget {
  final List videos;

  const ShortVideoListPage({super.key, required this.videos});

  @override
  ConsumerState<ShortVideoListPage> createState() => _ShortVideoListPageState();
}

class _ShortVideoListPageState extends ConsumerState<ShortVideoListPage>
    with WidgetsBindingObserver {
  late PreloadPageController _preloadPageController;
  AliPlayerPreload? _aliPlayerPreload;
  late List<GlobalKey<ShortVideoItemState>> _itemKeys;
  int _currentIndex = 0;
  bool _isCurrentTabActive = false;
  bool _isCoveredByFullscreenRoute = false;
  late final ProviderSubscription<int> _tabIndexSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preloadPageController = PreloadPageController();
    _preloadPageController.addListener(_onPageChanged);
    _itemKeys = List.generate(
      widget.videos.length,
      (_) => GlobalKey<ShortVideoItemState>(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchAround(0);
    });
    _isCurrentTabActive = ref.read(currentTabIndexProvider) == 2;
    _tabIndexSubscription = ref.listenManual<int>(
      currentTabIndexProvider,
      (previous, next) {
        if (!mounted) return;
        _isCurrentTabActive = next == 2;
        if (_isCurrentTabActive && !_isCoveredByFullscreenRoute) {
          _resumeCurrent();
        } else {
          _pauseCurrent();
        }
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_aliPlayerPreload != null) return;
    _aliPlayerPreload = AliPlayerPreload(
      context: context,
      enableCoverUrlStrategy: true,
    );
    _aliPlayerPreload!.setItems(widget.videos.cast<VideoInfo>());
    _aliPlayerPreload!.moveTo(_currentIndex);
  }

  @override
  void dispose() {
    _tabIndexSubscription.close();
    WidgetsBinding.instance.removeObserver(this);
    _aliPlayerPreload?.destroy();
    _preloadPageController.dispose();
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
        if (_isCurrentTabActive && !_isCoveredByFullscreenRoute) {
          _resumeCurrent();
        }
        break;
    }
  }

  void _onPageChanged() {
    final newIndex = _preloadPageController.page?.round() ?? 0;
    if (_currentIndex == newIndex) return;
    _currentIndex = newIndex;
    _aliPlayerPreload?.moveTo(newIndex);
    _pauseAllExceptCurrent(newIndex);
    _prefetchAround(newIndex);
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

  Future<void> _openFullscreen() async {
    if (_itemKeys.isEmpty || widget.videos.isEmpty) return;
    final current = widget.videos[_currentIndex] as VideoInfo;
    final videoId = current.videoId.toString();
    if (videoId.isEmpty || videoId == '0') return;

    _isCoveredByFullscreenRoute = true;
    _pauseAllExceptCurrent(-1);

    try {
      await context.push('/short-video', extra: {
        'videoId': videoId,
        'initialIndex': _currentIndex,
        'seedVideo': current.toJson(),
      });
    } finally {
      _isCoveredByFullscreenRoute = false;
      if (mounted && _isCurrentTabActive) {
        _resumeCurrent();
      }
    }
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

  Future<void> _playNextEpisode() async {
    final nextIndex = _currentIndex + 1;
    if (nextIndex < 0 || nextIndex >= widget.videos.length) return;
    await _preloadPageController.animateToPage(
      nextIndex,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    _currentIndex = nextIndex;
    _aliPlayerPreload?.moveTo(nextIndex);
    _pauseAllExceptCurrent(nextIndex);
    _prefetchAround(nextIndex);
  }

  Widget _buildWatchButton(AppLocalizations l10n) {
    final watchLabel = _watchLabel(l10n);
    return GestureDetector(
      onTap: _openFullscreen,
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
            child: const Icon(
              Icons.play_circle_outline,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            watchLabel,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _watchLabel(AppLocalizations l10n) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar' ? 'مشاهدة' : 'Watch';
  }

  String _formatActionCount(int count) {
    if (count > 999) return '999+';
    return count.toString();
  }

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

  double _recommendSideOverlayBottomInset(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final safeBottom = mediaQuery.padding.bottom;
    final screenHeight = mediaQuery.size.height;
    return math.max(safeBottom + screenHeight * 0.12, safeBottom + 24);
  }

  Widget _buildRecommendOverlay(BuildContext context, VideoInfo videoInfo) {
    final l10n = AppLocalizations.of(context);
    final videoId = videoInfo.videoId.toString();
    final actionState = ref.watch(videoActionProvider);

    final isLiked = actionState.isLiked(videoId, fallback: videoInfo.isLike == 1);
    final isCollected = actionState.isCollected(videoId, fallback: videoInfo.isCollect == 1);
    final likeCount = actionState.likeCount(videoId, fallback: videoInfo.likeNum);
    final collectCount = actionState.collectCount(videoId, fallback: videoInfo.collectNum);

    return PositionedDirectional(
      end: 12,
      bottom: _recommendSideOverlayBottomInset(context),
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
            _buildWatchButton(l10n),
          ],
        ),
      ),
    );
  }

  String _buildDebugInfo(VideoInfo videoInfo, bool autoPlay) {
    final initialUrl = videoInfo.videoUrl;
    final initialUrlState = initialUrl.isEmpty ? 'empty' : 'present';
    return 'recommend debug\n'
        'videoId=${videoInfo.videoId} episodesId=${videoInfo.id} ep=${videoInfo.serialNum}\n'
        'initialUrl=$initialUrlState autoPlay=$autoPlay canPlay=${videoInfo.isCanPlay}';
  }

  @override
  Widget build(BuildContext context) {
    return PreloadPageView.builder(
      controller: _preloadPageController,
      scrollDirection: Axis.vertical,
      itemCount: widget.videos.length,
      itemBuilder: (context, index) {
        final video = widget.videos[index] as VideoInfo;
        final autoPlay = index == _currentIndex;
        return ShortVideoItem(
          key: _itemKeys[index],
          videoInfo: video,
          autoPlay: autoPlay,
          resolvePlayableUrl: true,
          onCompleted: _playNextEpisode,
          overlayBuilder: _buildRecommendOverlay,
          debugInfo: _showRecommendPlaybackDebug
              ? _buildDebugInfo(video, autoPlay)
              : null,
        );
      },
      preloadPagesCount: 2,
    );
  }
}

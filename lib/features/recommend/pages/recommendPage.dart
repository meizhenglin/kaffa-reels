// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 沉浸式列表播放页面
//
// 数据流向：Riverpod(VideoFeedNotifier) → Repository → AuthService → DioClient → API
// UI 只负责：展示 loading/视频列表/错误状态，不处理任何业务逻辑

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:preload_page_view/preload_page_view.dart';

import '../models/video_info.dart';
import '../providers/recommend_provider.dart';
import 'ali_player_preload.dart';
import 'short_video_item.dart';

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

    if (state.status == VideoFeedStatus.error ||
        state.videos.isEmpty) {
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
class ShortVideoListPage extends StatefulWidget {
  final List videos;

  const ShortVideoListPage({super.key, required this.videos});

  @override
  State<ShortVideoListPage> createState() => _ShortVideoListPageState();
}

class _ShortVideoListPageState extends State<ShortVideoListPage> {
  late PreloadPageController _preloadPageController;
  late AliPlayerPreload _aliPlayerPreload;
  late List _itemKeys;
  int _currentIndex = 0; 

  @override
  void initState() {
    super.initState();
    _preloadPageController = PreloadPageController();
    _preloadPageController.addListener(_onPageChanged);
    _aliPlayerPreload = AliPlayerPreload(
      context: context,
      enableCoverUrlStrategy: true,
    );
    _aliPlayerPreload.setItems(widget.videos.cast<VideoInfo>());
    _aliPlayerPreload.moveTo(0);
    _itemKeys = List.generate(
      widget.videos.length,
      (_) => GlobalKey<ShortVideoItemState>(),
    );
  }

  @override
  void dispose() {
    _aliPlayerPreload.destroy();
    _preloadPageController.dispose();
    super.dispose();
  }

  void _onPageChanged() {
    final newIndex = _preloadPageController.page?.round() ?? 0;
    if (_currentIndex == newIndex) return;
    _currentIndex = newIndex;
    _aliPlayerPreload.moveTo(newIndex);
    _pauseAllExceptCurrent(newIndex);
  }

  void _pauseAllExceptCurrent(int currentIndex) {
    for (int i = 0; i < _itemKeys.length; i++) {
      if (i != currentIndex) {
        _itemKeys[i].currentState?.pause();
      } else {
        _itemKeys[i].currentState?.resume();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PreloadPageView.builder(
      controller: _preloadPageController,
      scrollDirection: Axis.vertical,
      itemCount: widget.videos.length,
      itemBuilder: (context, index) {
        return ShortVideoItem(
          key: _itemKeys[index],
          videoInfo: widget.videos[index],
          autoPlay: index == _currentIndex,
        );
      },
      preloadPagesCount: 1,
    );
  }
}

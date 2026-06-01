// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 沉浸式列表播放页面（适配本项目 VideoInfo 模型）
//
// 仅修改导入路径和数据加载逻辑，播放器核心代码保持不变。

import 'package:flutter/material.dart';
import 'package:preload_page_view/preload_page_view.dart';

import '../recommend/models/video_info.dart';
import 'short_video_item.dart';
import 'ali_player_preload.dart';

class ShortVideoPage extends StatelessWidget {
  final bool preload;
  final List<VideoInfo>? episodes;

  const ShortVideoPage({
    super.key,
    this.preload = true,
    this.episodes,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ShortVideoListPage(
        preload: preload,
        episodes: episodes,
      ),
    );
  }
}

class ShortVideoListPage extends StatefulWidget {
  final bool preload;
  final List<VideoInfo>? episodes;

  const ShortVideoListPage({
    super.key,
    required this.preload,
    this.episodes,
  });

  @override
  State<ShortVideoListPage> createState() => _ShortVideoListPageState();
}

class _ShortVideoListPageState extends State<ShortVideoListPage> {
  static const String _tag = "ShortVideoPage";

  late List<VideoInfo> videoInfoList;
  late AliPlayerPreload _aliPlayerPreload;
  late PageController _pageController;
  late PreloadPageController _preloadPageController;

  int _currentIndex = 0;
  final List<GlobalKey<ShortVideoItemState>> _itemKeys = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    _aliPlayerPreload = AliPlayerPreload(
      context: context,
      enableCoverUrlStrategy: true,
    );

    if (widget.preload) {
      _preloadPageController = PreloadPageController();
      _preloadPageController.addListener(_onPageChanged);
    } else {
      _pageController = PageController();
      _pageController.addListener(_onPageChanged);
    }

    _loadData();
  }

  @override
  void dispose() {
    _aliPlayerPreload.destroy();
    if (widget.preload) {
      _preloadPageController.dispose();
    } else {
      _pageController.dispose();
    }
    super.dispose();
  }

  void _loadData() {
    debugPrint("[$_tag] received ${widget.episodes?.length ?? 0} episodes");

    if (widget.episodes != null && widget.episodes!.isNotEmpty) {
      videoInfoList = widget.episodes!;
    } else {
      // fallback mock
      videoInfoList = List.generate(5, (i) {
        final ep = i + 1;
        return VideoInfo(
          id: ep,
          videoId: 0,
          videoUrl: 'https://vd.lmsl.jadeedloud.com/vod/cdng customer original/course/live/Educational-720p.m3u8',
          title: 'Episode $ep',
          serialNum: ep,
          isCanPlay: 1,
        );
      });
    }

    _completeLoading();
  }

  void _completeLoading() {
    _aliPlayerPreload.setItems(videoInfoList);
    _aliPlayerPreload.moveTo(_currentIndex);

    _itemKeys.clear();
    _itemKeys.addAll(
      List.generate(
        videoInfoList.length,
        (_) => GlobalKey<ShortVideoItemState>(),
      ),
    );

    setState(() {
      _isLoading = false;
    });
  }

  void _onPageChanged() {
    final newPageIndex = widget.preload
        ? _preloadPageController.page?.round() ?? 0
        : _pageController.page?.round() ?? 0;

    if (_currentIndex == newPageIndex) return;

    debugPrint("[$_tag]${'-' * 30}[index][$_currentIndex->$newPageIndex]");

    _currentIndex = newPageIndex;
    _aliPlayerPreload.moveTo(newPageIndex);
    _pauseAllExceptCurrent(newPageIndex);
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

  Widget _buildItem(BuildContext context, int index) {
    final videoItem = videoInfoList[index];
    debugPrint("[$_tag][item][lifecycle][create][${videoItem.id}]");
    return ShortVideoItem(
      key: _itemKeys[index],
      videoInfo: videoItem,
      autoPlay: index == _currentIndex,
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

    return widget.preload
        ? PreloadPageView.builder(
            controller: _preloadPageController,
            scrollDirection: Axis.vertical,
            itemCount: videoInfoList.length,
            itemBuilder: _buildItem,
            preloadPagesCount: 1,
          )
        : PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: videoInfoList.length,
            itemBuilder: _buildItem,
          );
  }
}

// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 沉浸式列表播放页面
//
// 使用 PreloadPageView 或 PageView 来实现沉浸式视频列表播放。
// 根据 `preload` 参数决定是否启用预加载功能。
//
// - preload=true: 使用 PreloadPageView，支持预加载，滑动更流畅但内存占用高
// - preload=false: 使用 PageView，轻量但无预加载

import 'package:short_video_player/ali_player_preload.dart';
import 'package:short_video_player/demo_constants.dart';
import 'package:short_video_player/http_util.dart';
import 'package:short_video_player/sp_manager.dart';
import 'package:short_video_player/short_video_item.dart';
import 'package:short_video_player/short_video_util.dart';
import 'package:short_video_player/video_info.dart';
import 'package:flutter/material.dart';
import 'package:preload_page_view/preload_page_view.dart';

/// 沉浸式短视频播放页面
///
/// 入口 widget，直接用此 widget 即可。
///
/// Example:
/// ```dart
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => const ShortVideoPage(preload: true),
///   ),
/// );
/// ```
class ShortVideoPage extends StatelessWidget {
  /// 是否启用预加载功能
  ///
  /// - `true`（默认）: 使用 `PreloadPageView`，支持页面预加载，滑动更流畅
  /// - `false`: 使用 `PageView`，轻量级，不支持预加载
  final bool preload;

  /// 外部传入的视频列表（优先级最高）
  ///
  /// 如果传入此参数，则忽略 videoId、videoListUrl 等，直接使用此列表渲染。
  final List<VideoInfo>? videoList;

  /// 视频 id（通过后端接口获取剧集列表）
  ///
  /// 传入后会自动调用后端接口获取剧集数据。
  final int? videoId;

  /// 起始集数（配合 videoId 使用）
  final int startEpisode;

  /// 视频列表 URL（通过 URL 获取视频列表）
  ///
  /// 优先级低于 videoList，高于默认数据源。
  final String? videoListUrl;

  const ShortVideoPage({
    super.key,
    this.preload = true,
    this.videoList,
    this.videoId,
    this.startEpisode = 1,
    this.videoListUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ShortVideoListPage(
        preload: preload,
        videoList: videoList,
        videoId: videoId,
        startEpisode: startEpisode,
        videoListUrl: videoListUrl,
      ),
    );
  }
}

/// 沉浸式列表组件（Stateful）
class ShortVideoListPage extends StatefulWidget {
  final bool preload;
  final List<VideoInfo>? videoList;
  final int? videoId;
  final int startEpisode;
  final String? videoListUrl;

  const ShortVideoListPage({
    super.key,
    required this.preload,
    this.videoList,
    this.videoId,
    this.startEpisode = 1,
    this.videoListUrl,
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

  /// 加载视频数据（支持多种数据源）
  Future<void> _loadData() async {
    try {
      // 优先级: videoList > videoId > videoListUrl > 默认数据
      if (widget.videoList != null && widget.videoList!.isNotEmpty) {
        // 直接使用传入的视频列表
        setState(() {
          videoInfoList = widget.videoList!;
          _completeLoading();
        });
        return;
      }

      if (widget.videoId != null) {
        // 通过后端接口获取
        final videoList = await _loadFromApi(widget.videoId!, widget.startEpisode);
        setState(() {
          videoInfoList = videoList;
          _completeLoading();
        });
        return;
      }

      if (widget.videoListUrl != null) {
        final videoList = await ShortVideoUtil.loadVideoInfoList(widget.videoListUrl!);
        setState(() {
          videoInfoList = videoList;
          _completeLoading();
        });
        return;
      }

      // 默认逻辑：从本地存储或默认 URL 加载
      final savedLink = SPManager.instance.getString(
        DemoConstants.keyDramaInfoListUrl,
      );

      if (savedLink != null) {
        final dramaInfoList = await ShortVideoUtil.loadDramaInfoList(savedLink);
        final videoList = ShortVideoUtil.getVideoInfoListFromDramaInfo(
          dramaInfoList.firstOrNull,
        );
        setState(() {
          videoInfoList = videoList;
          _completeLoading();
        });
      } else {
        final videoList = await ShortVideoUtil.loadVideoInfoList(
          DemoConstants.defaultVideoInfoListUrl,
        );
        setState(() {
          videoInfoList = videoList;
          _completeLoading();
        });
      }
    } catch (e) {
      _handleLoadingError("Exception: $e");
    }
  }

  /// 通过后端接口获取剧集数据（先拿总数，再拿列表）
  Future<List<VideoInfo>> _loadFromApi(int videoId, int startEpisode) async {
    // 此处调用你自己的后端接口
    // Step 1: 获取剧集总数
    // final count = await HTTPUtil.instance.get('/api/video/$videoId/episodes/count');
    // Step 2: 获取剧集列表
    // final response = await HTTPUtil.instance.get('/api/video/$videoId/episodes', queryParameters: {'current': startEpisode, 'size': count});
    // return VideoInfo.fromJsonList(response['data']);

    // TODO: 替换为实际后端接口
    debugPrint('[_ShortVideoListPageState] videoId=$videoId, startEpisode=$startEpisode');
    return [];
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

    _isLoading = false;
  }

  void _handleLoadingError(String errorMessage) {
    debugPrint("[$_tag][error]: $errorMessage");
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

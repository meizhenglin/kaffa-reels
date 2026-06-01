// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: 沉浸式列表播放页面（适配本项目 VideoInfo 模型）
//
// 【数据加载策略】 — 播放器内部统一处理，调用方只需传 videoId 或 episodes
// - videoId 不为空：播放器内部请求 directory + playVideo，复用所有模块的卡片入口
// - episodes 不为空：直接使用传入数据（兼容无需 videoId 的场景）
// - 两者都为空：fallback mock 数据

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:preload_page_view/preload_page_view.dart';

import '../../core/network/api_service.dart';
import '../recommend/models/video_info.dart';
import 'short_video_item.dart';
import 'ali_player_preload.dart';

class ShortVideoPage extends StatelessWidget {
  final bool preload;
  final List<VideoInfo>? episodes;
  final String? videoId;

  const ShortVideoPage({
    super.key,
    this.preload = true,
    this.episodes,
    this.videoId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ShortVideoListPage(
        preload: preload,
        episodes: episodes,
        videoId: videoId,
      ),
    );
  }
}

class ShortVideoListPage extends ConsumerStatefulWidget {
  final bool preload;
  final List<VideoInfo>? episodes;
  final String? videoId;

  const ShortVideoListPage({
    super.key,
    required this.preload,
    this.episodes,
    this.videoId,
  });

  @override
  ConsumerState<ShortVideoListPage> createState() => _ShortVideoListPageState();
}

class _ShortVideoListPageState extends ConsumerState<ShortVideoListPage> {
  static const String _tag = "ShortVideoPage";

  late List<VideoInfo> videoInfoList;
  late AliPlayerPreload _aliPlayerPreload;
  late PageController _pageController;
  late PreloadPageController _preloadPageController;

  int _currentIndex = 0;
  final List<GlobalKey<ShortVideoItemState>> _itemKeys = [];
  bool _isLoading = true;
  String? _errorMessage;

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

  /// 优先通过 videoId 请求目录和视频地址（播放器内部统一处理）
  Future<void> _fetchByVideoId() async {
    if (widget.videoId == null || widget.videoId!.isEmpty) return;

    debugPrint("[$_tag] fetching by videoId=${widget.videoId}");

    try {
      // 1. 请求目录（获取剧集数量和基本信息）
      final dirResp = await apiServiceProvider.getEpisodesDirectoryByVideoId(
        videoId: widget.videoId!,
      );
      if (!dirResp.isSuccess || dirResp.data == null) {
        _setError('无法加载剧集目录');
        return;
      }

      final dirData = dirResp.data as Map<String, dynamic>;
      final videoEpisodes = dirData['videoEpisodes'] as int? ?? 1;
      final videoName = dirData['videoName'] as String? ?? '';
      final videoPicture = dirData['videoPicture'] as String? ?? '';

      // 展开嵌套目录结构
      final List<Map> dirItems = [];
      final voList = dirData['voList'] as List? ?? [];
      for (final group in voList) {
        if (group is Map) {
          final directoryList = group['directoryList'] as List? ?? [];
          for (final m in directoryList) {
            if (m is Map) dirItems.add(m);
          }
        }
      }

      // 2. 请求所有集的视频地址
      final playResp = await apiServiceProvider.getVideoListByVideoId(
        videoId: widget.videoId!,
        episodesNum: 1,
        pageSize: videoEpisodes,
      );
      if (!playResp.isSuccess) {
        _setError('无法加载视频地址');
        return;
      }

      // 建立 episodesId → 视频信息的映射
      final Map<String, Map> playById = {};
      if (playResp.data is List) {
        for (final item in playResp.data as List) {
          if (item is Map) {
            final id = (item['episodesId'] ?? '').toString();
            if (id.isNotEmpty) playById[id] = item;
          }
        }
      }

      // 3. 合并数据构建 VideoInfo 列表
      final validVideos = <VideoInfo>[];
      for (final m in dirItems) {
        final epId = (m['episodesId'] ?? '').toString();
        final playItem = playById[epId];
        if (playItem == null) continue;

        final epNum = m['episodesNum'] as int? ?? 0;
        final url = playItem['episodesUrl'] as String? ?? '';
        if (url.isEmpty) continue;

        validVideos.add(VideoInfo(
          id: validVideos.length + 1,
          videoId: int.tryParse(widget.videoId!) ?? 0,
          videoUrl: url,
          coverUrl: playItem['videoPicture'] as String? ?? videoPicture,
          title: '$videoName EP.$epNum',
          serialNum: epNum,
          isCanPlay: (playItem['isCanPlay'] as int? ?? 1) == 1 ? 1 : 0,
        ));
      }

      if (validVideos.isEmpty) {
        _setError('该剧暂无可播放剧集');
        return;
      }

      videoInfoList = validVideos;
      _completeLoading();
    } catch (e) {
      debugPrint("[$_tag] fetchByVideoId error=$e");
      _setError('加载失败：$e');
    }
  }

  void _loadData() {
    if (widget.videoId != null && widget.videoId!.isNotEmpty) {
      // 优先用 videoId，播放器内部请求数据，所有模块复用
      _fetchByVideoId();
    } else if (widget.episodes != null && widget.episodes!.isNotEmpty) {
      // episodes 不为空，直接使用
      videoInfoList = widget.episodes!;
      _completeLoading();
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
      _completeLoading();
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

import 'package:flutter/material.dart';
import 'package:flutter_aliplayer/flutter_aliplayer.dart';
import 'package:flutter_aliplayer/flutter_aliplayer_factory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 最简播放器页面：仅包含 AliPlayerView，用于测试真实 m3u8 流地址是否可播放
class TestPlayerPage extends ConsumerStatefulWidget {
  const TestPlayerPage({super.key});

  @override
  ConsumerState<TestPlayerPage> createState() => _TestPlayerPageState();
}

class _TestPlayerPageState extends ConsumerState<TestPlayerPage> {
  int? _viewId;
  bool _viewCreated = false;
  bool _isPlaying = false;

  // 真实测试视频地址（HLS m3u8）
  static const String _testUrl =
      'https://vod.qahwatv.com/asset/88b48c8a37fae617b9a39796c8880f35/play_video/c259324473993fe6c2c8d846267b8bee_0.m3u8';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // AliPlayerView - 无任何容器包裹
          SizedBox(
            width: MediaQuery.sizeOf(context).width,
            height: MediaQuery.sizeOf(context).height,
            child: AliPlayerView(
              onCreated: (viewId) {
                debugPrint('===== AliPlayerView onCreated: viewId=$viewId =====');
                setState(() {
                  _viewId = viewId;
                  _viewCreated = true;
                });
                _autoPlay();
              },
              x: 0,
              y: 0,
              width: MediaQuery.sizeOf(context).width,
              height: MediaQuery.sizeOf(context).height,
              aliPlayerViewType: AliPlayerViewTypeForAndroid.surfaceview,
            ),
          ),

          // 调试信息
          Positioned(
            top: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'viewCreated=$_viewCreated  viewId=$_viewId  playing=$_isPlaying',
                      style: TextStyle(
                        color: _viewCreated ? Colors.green : Colors.red,
                        fontSize: 14,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _testUrl,
                      style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _viewCreated ? _togglePlay : null,
                    icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                    label: Text(_isPlaying ? 'Pause' : 'Play'),
                  ),
                ],
              ),
            ),
          ),

          // 返回按钮
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }

  void _autoPlay() {
    if (_viewId == null) return;
    final player = FlutterAliPlayerFactory.createAliPlayer();
    player.setPlayerView(_viewId!);
    player.setAutoPlay(true);
    player.setUrl(_testUrl);
    player.setOnPrepared((_) {
      debugPrint('TestPlayer: onPrepared');
      setState(() => _isPlaying = true);
    });
    player.setOnError((code, extra, msg, _) {
      debugPrint('TestPlayer error: $code $extra $msg');
    });
  }

  void _togglePlay() {
    // 简单切换状态示意，实际播放由 autoPlay 控制
    setState(() => _isPlaying = !_isPlaying);
  }
}

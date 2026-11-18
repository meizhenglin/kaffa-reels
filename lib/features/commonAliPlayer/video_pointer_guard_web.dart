import 'dart:async';
import 'dart:html' as html;

import 'package:flutter/foundation.dart' show debugPrint;

/// 【web 上「单击暂停」失效的根因】
///
/// video_player 在 web 上把视频渲染成**真实的 `<video>` DOM 元素**
/// （HtmlElementView / platform view）。Flutter web 引擎会把它插进 DOM 的
/// `<flt-platform-view-slot style="pointer-events: auto">` 里，DOM 层级高于
/// Flutter 画布 —— 于是这块区域内的所有指针事件都被 `<video>` 吃掉，
/// 铺在视频之上的 GestureDetector（单击暂停/播放）**永远收不到 tap**。
///
/// 这和「Flutter widget 盖在 platform view 上点不动」是同一个问题，
/// 官方推荐的思路也是让 DOM 元素放弃接收指针事件（pointer-events: none）。
///
/// 本项目所有视频都由自己画控件，`<video>` 本身不需要任何鼠标交互，
/// 因此把它以及它的 platform view 包装层设成 `pointer-events: none`，
/// 事件就能穿透回 Flutter 画布，单击暂停/播放、拖动（PageView 上下滑）都恢复。
bool _installed = false;
bool _patchScheduled = false;

/// 这些标签只可能在「包裹一个视频」的链路上出现，打补丁不会误伤别的
/// platform view（例如支付页的 iframe 也是 platform view，绝不能一起禁掉）。
const Set<String> _videoWrapperTags = <String>{
  'VIDEO',
  'FLT-PLATFORM-VIEW',
  'FLT-PLATFORM-VIEW-SLOT',
};

void allowVideoTapThrough() {
  if (_installed) return;
  _installed = true;
  _patchVideos();
  // 播放器是懒创建的：`<video>` 要等 VideoPlayerController.initialize()
  // 之后才插进 DOM，而且每换一集都会新建一个，所以要持续监听新增节点。
  html.MutationObserver((_, __) => _schedulePatch()).observe(
    html.document.documentElement!,
    childList: true,
    subtree: true,
  );
  debugPrint('[VideoTapThrough] installed');
}

void _schedulePatch() {
  if (_patchScheduled) return;
  _patchScheduled = true;
  scheduleMicrotask(() {
    _patchScheduled = false;
    _patchVideos();
  });
}

void _patchVideos() {
  var patched = 0;
  for (final video in html.document.querySelectorAll('video')) {
    html.Element? element = video;
    // 只沿着 video → flt-platform-view → flt-platform-view-slot 往上走，
    // 碰到别的节点立刻停手。
    while (element != null && _videoWrapperTags.contains(element.tagName)) {
      if (element is html.HtmlElement && element.style.pointerEvents != 'none') {
        element.style.pointerEvents = 'none';
        patched++;
      }
      final parent = element.parent;
      element = parent is html.Element ? parent : null;
    }
  }
  if (patched > 0) {
    debugPrint('[VideoTapThrough] pointer-events:none on $patched node(s)');
  }
}

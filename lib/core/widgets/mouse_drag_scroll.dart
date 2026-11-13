import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 允许用鼠标拖动滚动/翻页。
///
/// 【为什么需要】
/// Flutter 默认的 [ScrollBehavior] 把 [PointerDeviceKind.mouse] 排除在
/// 「可拖拽设备」之外（只剩触摸、手写笔、触控板），所以在 Web 和桌面上，
/// 列表和 PageView 只能用滚轮，无法像手机那样按住拖动。
///
/// 这个行为在 `main.dart` 里通过 `MaterialApp.scrollBehavior` 全局启用，
/// 因此全站页面（首页、探索、剧集详情、播放页等）都支持鼠标拖拽。
///
/// 说明：文字输入框与可选中文本使用自己的手势识别器，鼠标横向拖选文字
/// 仍然可用；这里只是补上鼠标作为「滚动/翻页」的拖拽来源。
class MouseDragScrollBehavior extends MaterialScrollBehavior {
  const MouseDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

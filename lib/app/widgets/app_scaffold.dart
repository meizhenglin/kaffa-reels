import 'package:flutter/material.dart';

/// ============================================================================
/// 应用背景组件
///
/// 【功能说明】
/// 为应用提供统一的渐变背景效果：
/// - 顶部 0-182pt：从 #5D4391 渐变到 #1F2025
/// - 182pt 到底部：纯色 #1F2025
///
/// 【使用方式】
/// 用 AppScaffold 替代 Scaffold，它会自动应用渐变背景
/// ============================================================================
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.drawer,
    this.endDrawer,
    this.endDrawerEnableOpenDragGesture = true,
    this.drawerEnableOpenDragGesture = true,
    this.onDrawerChanged,
    this.onEndDrawerChanged,
    this.primary = true,
    this.resizeToAvoidBottomInset,
    this.restorationId,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final Widget? endDrawer;
  final bool endDrawerEnableOpenDragGesture;
  final bool drawerEnableOpenDragGesture;
  final void Function(bool)? onDrawerChanged;
  final void Function(bool)? onEndDrawerChanged;
  final bool primary;
  final bool? resizeToAvoidBottomInset;
  final String? restorationId;

  /// 渐变背景组件
  static Widget get gradientBackground => const _GradientBackground();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: appBar,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      drawer: drawer,
      endDrawer: endDrawer,
      endDrawerEnableOpenDragGesture: endDrawerEnableOpenDragGesture,
      drawerEnableOpenDragGesture: drawerEnableOpenDragGesture,
      onDrawerChanged: onDrawerChanged,
      onEndDrawerChanged: onEndDrawerChanged,
      primary: primary,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      restorationId: restorationId,
    );
  }
}

/// 渐变背景组件
class _GradientBackground extends StatelessWidget {
  const _GradientBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 顶部渐变区域（0-182px）
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter, // 从底部开始
              end: Alignment.topCenter,      // 到顶部结束
              colors: [
                Color(0xFF5D4391),
                Color(0xFF1F2025),
              ],
              stops: [0.0, 1.0],
            ),
          ),
        ),
        // 渐变区域固定高度 182px
        SizedBox(height: 182),
        // 底部纯色区域（182px 以下）
        PositionedDirectional(
          top: 182,
          start: 0,
          end: 0,
          bottom: 0,
          child: Container(
            color: const Color(0xFF1F2025),
          ),
        ),
      ],
    );
  }
}

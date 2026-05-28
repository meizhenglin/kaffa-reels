import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/tab_scroll_provider.dart';

/// ============================================================================
/// Tab 滚动控制器 Mixin
///
/// 【功能说明】
/// 为 Tab 页面提供滚动控制功能：
/// - 注册 ScrollController 到 Provider
/// - 支持双击回到顶部功能
///
/// 【使用方式】
/// 在 ConsumerStatefulWidget 中使用 with 关键字引入：
/// ```dart
/// class _MyPageState extends ConsumerState<MyPage> with TabScrollMixin {
///   @override
///   String get tabId => 'unique_tab_id';
///   ...
/// }
/// ```
///
/// 【如何修改】
/// - 如果不需要双击回到顶部功能，可以不继承此 Mixin
/// - tabId 必须是唯一的，用于标识不同的 Tab
/// ============================================================================
mixin TabScrollMixin<T extends ConsumerStatefulWidget> on ConsumerState<T> {
  /// 获取当前 Tab 的唯一标识符
  /// 【重要】每个使用此 Mixin 的页面必须有唯一的 tabId
  String get tabId;

  /// 滚动控制器，用于控制列表滚动
  late final ScrollController tabScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // 在第一帧绘制完成后注册 ScrollController
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(tabScrollProvider.notifier).register(tabId, tabScrollController);
      }
    });
  }

  @override
  void dispose() {
    tabScrollController.dispose();
    super.dispose();
  }
}

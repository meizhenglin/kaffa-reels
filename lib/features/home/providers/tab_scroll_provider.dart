import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 各 Tab 滚动控制器注册表，用于双击 Tab 回到顶部
class TabScrollNotifier extends StateNotifier<Map<String, ScrollController>> {
  TabScrollNotifier() : super(const {});

  void register(String tabId, ScrollController controller) {
    state = {...state, tabId: controller};
  }

  void unregister(String tabId) {
    final next = Map<String, ScrollController>.from(state)..remove(tabId);
    state = next;
  }

  Future<void> scrollToTop(String tabId) async {
    final controller = state[tabId];
    if (controller == null || !controller.hasClients) return;
    await controller.animateTo(
      0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
  }
}

final tabScrollProvider =
    StateNotifierProvider<TabScrollNotifier, Map<String, ScrollController>>(
  (ref) => TabScrollNotifier(),
);

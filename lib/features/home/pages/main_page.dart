import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../../explore/pages/explore_page.dart';
import '../models/navigation_item.dart';
import '../providers/tab_scroll_provider.dart';
import '../widgets/bottom_nav_bar.dart';
import '../widgets/history_resume_card.dart';

/// 当前活跃 tab 索引 provider（供其他页面订阅）
/// 用于在切换 tab 时通知页面暂停/恢复视频播放等
final currentTabIndexProvider = StateProvider<int>((ref) => 0);

/// 主框架页面
class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> {
  int _lastTappedIndex = -1;
  DateTime _lastTapTime = DateTime.fromMillisecondsSinceEpoch(0);
  static const _doubleTapInterval = Duration(milliseconds: 400);

  void _onTabTapped(int index, List<NavigationItem> items) {
    final now = DateTime.now();
    final isSameTab = index == widget.navigationShell.currentIndex;
    final isDoubleTap = isSameTab &&
        _lastTappedIndex == index &&
        now.difference(_lastTapTime) < _doubleTapInterval;

    _lastTappedIndex = index;
    _lastTapTime = now;

    if (isDoubleTap) {
      final tabId = NavigationConfig.idForIndex(index);
      ref.read(tabScrollProvider.notifier).scrollToTop(tabId);
      return;
    }

    if (isSameTab) {
      widget.navigationShell.goBranch(index, initialLocation: true);
    } else {
      // 切 tab 前先 unfocus 搜索框，防止输入法的 FocusNode 残留
      if (widget.navigationShell.currentIndex == 1) {
        ExplorePage.unfocusSearch(context);
      }
      widget.navigationShell.goBranch(index);
    }

    // 通知其他页面 tab 切换了
    ref.read(currentTabIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = NavigationConfig.items(l10n);
    final currentIndex = widget.navigationShell.currentIndex;

    return GradientScaffold(
      body: Stack(
        children: [
          widget.navigationShell,
          if (currentIndex == 0) const HistoryResumeCard(),
        ],
      ),
      bottomNavigationBar: AppBottomNavBar(
        items: items,
        currentIndex: currentIndex,
        onTap: (index) => _onTabTapped(index, items),
      ),
    );
  }
}

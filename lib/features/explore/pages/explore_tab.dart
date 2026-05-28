import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/mixins/tab_scroll_mixin.dart';
import 'explore_page.dart';

/// 探索 Tab
class ExploreTab extends ConsumerStatefulWidget {
  const ExploreTab({super.key});

  @override
  ConsumerState<ExploreTab> createState() => _ExploreTabState();
}

class _ExploreTabState extends ConsumerState<ExploreTab> with TabScrollMixin {
  @override
  String get tabId => 'explore';

  @override
  Widget build(BuildContext context) {
    return ExplorePage(scrollController: tabScrollController);
  }
}

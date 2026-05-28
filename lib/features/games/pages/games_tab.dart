import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../home/mixins/tab_scroll_mixin.dart';
import 'games_page.dart';

/// 游戏 Tab
class GamesTab extends ConsumerStatefulWidget {
  const GamesTab({super.key});

  @override
  ConsumerState<GamesTab> createState() => _GamesTabState();
}

class _GamesTabState extends ConsumerState<GamesTab> with TabScrollMixin {
  @override
  String get tabId => 'games';

  @override
  Widget build(BuildContext context) {
    return const GamesPage();
  }
}

import 'package:flutter/material.dart';

import 'recommendPage.dart' as recommend_feed;

/// 推荐 Tab
class RecommendTab extends StatelessWidget {
  const RecommendTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const recommend_feed.ShortVideoPage();
  }
}

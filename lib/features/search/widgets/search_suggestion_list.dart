import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/search_page_provider.dart';

/// 搜索框下方显示的推荐剧名列表
///
/// - 搜索框未聚焦时纵向滚动显示
/// - 搜索框聚焦且有输入时隐藏
class SearchSuggestionList extends ConsumerWidget {
  const SearchSuggestionList({
    super.key,
    required this.isFocused,
    required this.hasInput,
    this.onTap,
  });

  final bool isFocused;
  final bool hasInput;
  final void Function(String word)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final words = ref.watch(recommendedSearchListProvider).value ?? [];

    if (words.isEmpty || (isFocused && hasInput)) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: words.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return GestureDetector(
            onTap: () => onTap?.call(words[index]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0x1AFFFFFF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                words[index],
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

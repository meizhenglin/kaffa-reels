import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../providers/search_provider.dart';

/// ============================================================================
/// 探索页搜索框组件
///
/// 【功能说明】
/// 用于搜索短剧的输入框：
/// - 显示搜索图标和提示文字
/// - 支持输入和清除
/// - 与 searchProvider 联动
/// - 获得/失去焦点时通知父组件
///
/// 【使用场景】
/// - ExplorePage（探索页）顶部的搜索框
///
/// 【状态联动】
/// - 输入内容同步到 searchProvider.query
/// - 提交搜索时调用 searchProvider.submitSearch
/// - 获得焦点时显示 SearchSuggestionsPanel
///
/// 【组成部分】
/// - TextField: 搜索输入框
/// - prefixIcon: 搜索图标
/// - suffixIcon: 清除按钮（输入内容时显示）
///
/// 【如何修改】
/// - 修改提示文字：在 AppLocalizations 中修改 searchHint
/// - 修改圆角：修改 borderRadius
/// - 修改背景色：修改 fillColor
/// ============================================================================
class ExploreSearchBar extends ConsumerStatefulWidget {
  const ExploreSearchBar({
    super.key,
    required this.focusNode,
    required this.onSubmitted,
    this.onFocusChange,
  });

  /// 焦点控制器（由父组件传入）
  final FocusNode focusNode;
  /// 搜索提交的回调
  final void Function(String query) onSubmitted;
  /// 焦点变化的回调（可选）
  final ValueChanged<bool>? onFocusChange;

  @override
  ConsumerState<ExploreSearchBar> createState() => _ExploreSearchBarState();
}

class _ExploreSearchBarState extends ConsumerState<ExploreSearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    widget.focusNode.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    widget.onFocusChange?.call(widget.focusNode.hasFocus);
    ref.read(searchProvider.notifier).setShowSuggestions(widget.focusNode.hasFocus);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.watch(searchProvider);

    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      textInputAction: TextInputAction.search,
      textAlign: TextAlign.start,
      keyboardType: TextInputType.text,
      decoration: InputDecoration(
        hintText: l10n.searchHint,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _controller.clear();
                  ref.read(searchProvider.notifier).clearSearch();
                  widget.onSubmitted('');
                },
              )
            : null,
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      onChanged: (value) {
        setState(() {});
        ref.read(searchProvider.notifier).setQuery(value);
      },
      onSubmitted: (value) {
        ref.read(searchProvider.notifier).submitSearch(value);
        widget.onSubmitted(value);
      },
    );
  }
}

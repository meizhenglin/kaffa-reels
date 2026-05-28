import 'package:flutter/material.dart';

/// ============================================================================
/// 高亮关键词文本组件
///
/// 【功能说明】
/// 在文本中高亮显示搜索关键词：
/// - 查找文本中的关键词位置
/// - 将关键词使用特殊样式显示
/// - 支持多个关键词同时高亮
///
/// 【使用场景】
/// - 搜索结果中高亮匹配的关键词
/// - 列表中高亮显示搜索词
///
/// 【样式说明】
/// - 普通文本：使用基础样式
/// - 高亮文本：主题色 + 加粗 + 浅色背景
///
/// 【参数说明】
/// - text: 原始文本
/// - highlight: 要高亮的关键词
/// - style: 基础文本样式
/// - highlightStyle: 高亮文本样式
/// - maxLines: 最大显示行数
/// - textAlign: 文本对齐方式
///
/// 【如何修改】
/// - 修改高亮颜色：修改 highlightStyle 的 color
/// - 修改高亮背景：修改 highlightStyle 的 backgroundColor
/// - 修改高亮字体：修改 fontWeight
/// ============================================================================
class HighlightedText extends StatelessWidget {
  const HighlightedText({
    super.key,
    required this.text,
    required this.highlight,
    this.style,
    this.highlightStyle,
    this.maxLines,
    this.textAlign,
  });

  /// 原始文本
  final String text;
  /// 要高亮的关键词
  final String highlight;
  /// 基础文本样式
  final TextStyle? style;
  /// 高亮文本样式
  final TextStyle? highlightStyle;
  /// 最大显示行数
  final int? maxLines;
  /// 文本对齐方式
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = style ?? theme.textTheme.bodyMedium;
    // 高亮样式：主题色 + 加粗 + 浅色背景
    final activeStyle = highlightStyle ??
        baseStyle?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        );

    final trimmedHighlight = highlight.trim();
    // 如果关键词为空，直接显示原文
    if (trimmedHighlight.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
      );
    }

    // 构建高亮文本片段
    final spans = <TextSpan>[];
    final lowerText = text.toLowerCase();
    final lowerHighlight = trimmedHighlight.toLowerCase();
    var start = 0;

    // 查找所有匹配位置
    while (true) {
      final index = lowerText.indexOf(lowerHighlight, start);
      if (index < 0) {
        // 没有更多匹配，添加剩余文本
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
        break;
      }
      // 添加匹配前的普通文本
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: baseStyle));
      }
      // 添加高亮文本
      spans.add(TextSpan(
        text: text.substring(index, index + trimmedHighlight.length),
        style: activeStyle,
      ));
      start = index + trimmedHighlight.length;
    }

    return RichText(
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign ?? TextAlign.start,
      text: TextSpan(children: spans),
    );
  }
}

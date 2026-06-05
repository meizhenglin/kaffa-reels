import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../core/network/api_service.dart';
import '../../../l10n/app_localizations.dart';

class SystemConfigContentPage extends ConsumerStatefulWidget {
  const SystemConfigContentPage({
    super.key,
    required this.configId,
    required this.title,
  });

  final int configId;
  final String title;

  @override
  ConsumerState<SystemConfigContentPage> createState() =>
      _SystemConfigContentPageState();
}

class _SystemConfigContentPageState
    extends ConsumerState<SystemConfigContentPage> {
  late final Future<String> _contentFuture = _loadContent();

  Future<String> _loadContent() async {
    final l10n = AppLocalizations.of(context);
    final response = await apiServiceProvider.getSystemConfigContent(
      id: widget.configId,
    );

    if (!response.isSuccess) {
      throw Exception(response.error ?? l10n.failedToLoadContent);
    }

    final data = response.data;
    if (data == null) {
      return '';
    }

    if (data is String) {
      return data;
    }

    if (data is List && data.isNotEmpty) {
      final first = data.first;
      if (first is Map) {
        return _extractContentFromMap(Map<String, dynamic>.from(first));
      }
    }

    if (data is Map) {
      return _extractContentFromMap(Map<String, dynamic>.from(data));
    }

    return data.toString();
  }

  String _extractContentFromMap(Map<String, dynamic> data) {
    const candidateKeys = [
      'content',
      'configContent',
      'value',
      'configValue',
      'text',
      'desc',
      'description',
      'details',
      'remark',
      'richText',
    ];

    for (final key in candidateKeys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    for (final entry in data.entries) {
      final value = entry.value;
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return '';
  }

  bool _looksLikeHtml(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return false;

    return RegExp(r'<[^>]+>').hasMatch(trimmed) ||
        trimmed.contains('&nbsp;') ||
        trimmed.contains('&lt;') ||
        trimmed.contains('&gt;');
  }

  TextStyle get _contentTextStyle => const TextStyle(
        fontWeight: FontWeight.w400,
        fontSize: 12,
        color: Colors.white,
        height: 20 / 12,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  RtlBackButton(
                    onPressed: () => context.pop(),
                    color: Colors.white,
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const Opacity(
                    opacity: 0,
                    child: RtlBackButton(
                      onPressed: null,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<String>(
                future: _contentFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          snapshot.error.toString().replaceFirst('Exception: ', ''),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    );
                  }

                  final content = snapshot.data?.trim() ?? '';
                  if (content.isEmpty) {
                    return Center(
                      child: Text(
                        l10n.noContentAvailable,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Directionality(
                      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                      child: Align(
                        alignment:
                            isRtl ? Alignment.centerRight : Alignment.centerLeft,
                        child: _looksLikeHtml(content)
                            ? Html(
                                data: content,
                                style: {
                                  'html': Style(
                                    margin: Margins.zero,
                                    padding: HtmlPaddings.zero,
                                    color: Colors.white,
                                    fontSize: FontSize(_contentTextStyle.fontSize!),
                                    fontWeight: _contentTextStyle.fontWeight,
                                    lineHeight: LineHeight(_contentTextStyle.height!),
                                    textAlign: TextAlign.start,
                                  ),
                                  'body': Style(
                                    margin: Margins.zero,
                                    padding: HtmlPaddings.zero,
                                    color: Colors.white,
                                    fontSize: FontSize(_contentTextStyle.fontSize!),
                                    fontWeight: _contentTextStyle.fontWeight,
                                    lineHeight: LineHeight(_contentTextStyle.height!),
                                  ),
                                  'p': Style(
                                    margin: Margins.only(bottom: 12),
                                    color: Colors.white,
                                  ),
                                  'span': Style(color: Colors.white),
                                  'div': Style(color: Colors.white),
                                  'li': Style(color: Colors.white),
                                  'a': Style(
                                    color: const Color(0xFF8CC8FF),
                                    textDecoration: TextDecoration.underline,
                                  ),
                                  'strong': Style(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  'b': Style(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  'h1': Style(color: Colors.white),
                                  'h2': Style(color: Colors.white),
                                  'h3': Style(color: Colors.white),
                                  'h4': Style(color: Colors.white),
                                  'h5': Style(color: Colors.white),
                                  'h6': Style(color: Colors.white),
                                },
                              )
                            : SelectableText(
                                content,
                                textAlign: TextAlign.left,
                                style: _contentTextStyle,
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

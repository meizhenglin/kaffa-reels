import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../core/network/api_service.dart';

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
    final response = await apiServiceProvider.getSystemConfigContent(
      id: widget.configId,
    );

    if (!response.isSuccess) {
      throw Exception(response.error ?? 'Failed to load content');
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

  @override
  Widget build(BuildContext context) {
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
                    return const Center(
                      child: Text(
                        'No content available',
                        style: TextStyle(
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
                        child: SelectableText(
                          content,
                          textAlign: TextAlign.left,
                          style: const TextStyle(
                            fontWeight: FontWeight.w400,
                            fontSize: 12,
                            color: Colors.white,
                            height: 20 / 12,
                          ),
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

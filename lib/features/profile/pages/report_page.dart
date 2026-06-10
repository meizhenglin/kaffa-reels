import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';

class ReportPage extends ConsumerStatefulWidget {
  const ReportPage({super.key});

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends ConsumerState<ReportPage> {
  static const List<String> _reportTypes = [
    'Choose Type',
    'Content issue',
    'Playback problem',
    'Copyright concern',
    'Other',
  ];

  late final TextEditingController _reportController;
  late final ScrollController _scrollController;
  late final FocusNode _reportFocusNode;
  final GlobalKey _reportFieldKey = GlobalKey();
  String _selectedType = _reportTypes.first;

  @override
  void initState() {
    super.initState();
    _reportController = TextEditingController();
    _scrollController = ScrollController();
    _reportFocusNode = FocusNode()..addListener(_handleReportFocusChange);
  }

  @override
  void dispose() {
    _reportFocusNode
      ..removeListener(_handleReportFocusChange)
      ..dispose();
    _scrollController.dispose();
    _reportController.dispose();
    super.dispose();
  }

  void _handleReportFocusChange() {
    if (!_reportFocusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _reportFieldKey.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: GradientScaffold(
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    RtlBackButton(
                      color: Colors.white,
                      onPressed: () => context.pop(),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Complaint and Report',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
                    return AnimatedPadding(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      padding: EdgeInsets.only(bottom: keyboardInset),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ReportDropdown(
                                value: _selectedType,
                                items: _reportTypes,
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() => _selectedType = value);
                                },
                              ),
                              const SizedBox(height: 15),
                              const Text(
                                'Complaint and Report',
                                style: TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 10),
                              _ReportTextArea(
                                fieldKey: _reportFieldKey,
                                controller: _reportController,
                                focusNode: _reportFocusNode,
                              ),
                              const SizedBox(height: 10),
                              RichText(
                                text: const TextSpan(
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    fontSize: 14,
                                    color: Color(0xFF999999),
                                  ),
                                  children: [
                                    TextSpan(text: 'Contact Us:'),
                                    TextSpan(text: 'gahwatv register@gahwatv.com'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: _SubmitButton(
                    onPressed: () {},
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportDropdown extends StatefulWidget {
  const _ReportDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  State<_ReportDropdown> createState() => _ReportDropdownState();
}

class _ReportDropdownState extends State<_ReportDropdown> {
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _toggleMenu() {
    if (_overlayEntry != null) {
      _removeOverlay();
      return;
    }
    _showOverlay();
  }

  void _showOverlay() {
    final context = _anchorKey.currentContext;
    if (context == null) return;

    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    const horizontalPadding = 16.0;
    const spacing = 8.0;
    final topLeft = box.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
                child: const SizedBox.expand(),
              ),
            ),
            Positioned(
              left: horizontalPadding,
              right: horizontalPadding,
              top: topLeft.dy + box.size.height + spacing,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B3C45),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.items
                        .map(
                          (item) => InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              _removeOverlay();
                              widget.onChanged(item);
                            },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Text(
                                item,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w400,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        key: _anchorKey,
        onTap: _toggleMenu,
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF3B3C45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w400,
                    fontSize: 15,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(
                _overlayEntry == null
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_up_rounded,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportTextArea extends StatelessWidget {
  const _ReportTextArea({
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
  });

  final GlobalKey fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: fieldKey,
      height: 190,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        expands: true,
        maxLines: null,
        minLines: null,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(
          fontWeight: FontWeight.w400,
          fontSize: 13,
          color: Colors.white,
        ),
        decoration: InputDecoration(
          hintText: 'Complaint and ReportComplaint and Report',
          hintStyle: const TextStyle(
            fontWeight: FontWeight.w400,
            fontSize: 13,
            color: Colors.white,
          ),
          filled: true,
          fillColor: const Color(0xFF3B3C45),
          contentPadding: const EdgeInsets.all(14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0x66FFFFFF)),
          ),
        ),
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF8F4EFF),
          borderRadius: BorderRadius.circular(21),
        ),
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(21),
            ),
          ),
          child: const Text(
            'Submit Report',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

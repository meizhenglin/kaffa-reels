import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../core/network/api_service.dart';
import '../../../components/rtl_back_button.dart';
import '../../auth/providers/auth_provider.dart';

class ChangeNamePage extends ConsumerStatefulWidget {
  const ChangeNamePage({super.key, this.fromRegister = false});

  final bool fromRegister;

  @override
  ConsumerState<ChangeNamePage> createState() => _ChangeNamePageState();
}

class _ChangeNamePageState extends ConsumerState<ChangeNamePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _newNameController;
  bool _isSubmitting = false;

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _canConfirm {
    final newName = _newNameController.text.trim();
    final currentName = _nameController.text.trim();
    return !_isSubmitting && newName.isNotEmpty && newName != currentName;
  }

  @override
  void initState() {
    super.initState();
    final currentName = ref.read(authProvider).user?.userNickname ?? '';
    _nameController = TextEditingController(text: currentName);
    _newNameController = TextEditingController()..addListener(_handleNameChanged);
  }

  void _handleNameChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _newNameController.removeListener(_handleNameChanged);
    _nameController.dispose();
    _newNameController.dispose();
    super.dispose();
  }

  Future<void> _onConfirm() async {
    final newName = _newNameController.text.trim();
    if (newName.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      await ref.read(authProvider.notifier).updateNickname(newName);

      final resp = await apiServiceProvider.getUserCenter();
      if (!resp.isSuccess) {
        throw Exception(resp.error ?? 'Failed to update name');
      }

      if (resp.data != null && mounted) {
        await ref
            .read(authProvider.notifier)
            .updateUserFromData(resp.data as Map<String, dynamic>);
      }

      if (!mounted) {
        return;
      }

      context.go('/profile');
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is Exception
          ? error.toString().replaceFirst('Exception: ', '')
          : 'Failed to update name';
      _showErrorMessage(message);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    // 游客直接跳转登录；注册补全流程允许临时放行
    if ((auth.user == null || auth.user!.isTourist) && !widget.fromRegister) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/auth/login');
      });
      return const SizedBox.shrink();
    }

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                textDirection: Directionality.of(context),
                children: [
                  RtlBackButton(
                    onPressed: () async {
                      final didPop = await Navigator.of(context).maybePop();
                      if (!context.mounted) {
                        return;
                      }
                      if (!didPop) {
                        context.go('/profile');
                      }
                    },
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                  const Expanded(
                    child: Text(
                      'Change Name',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Opacity(
                    opacity: 0,
                    child: RtlBackButton(
                      onPressed: null,
                      constraints: BoxConstraints(minWidth: 24, minHeight: 24),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInlineField(
                      context,
                      title: 'Name',
                      value: _nameController.text,
                      valueColor: Colors.white54,
                    ),
                    const SizedBox(height: 16),
                    _buildEditableInlineField(context),
                  ],
                ),
              ),
            ),
            if (widget.fromRegister) ...[
              GestureDetector(
                onTap: () => context.go('/profile'),
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 15),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(color: const Color(0xFF8F4EFF), width: 1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Text(
                    'Skip',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF8F4EFF),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            GestureDetector(
              onTap: _canConfirm ? _onConfirm : null,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 15),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: _canConfirm
                      ? const LinearGradient(
                          colors: [Color(0xFF8F4EFF), Color(0xFFA237FF)],
                        )
                      : null,
                  color: _canConfirm ? null : const Color(0xFF3B3C45),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  'confirm',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _canConfirm ? Colors.white : Colors.white38,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineField(
    BuildContext context, {
    required String title,
    required String value,
    Color valueColor = Colors.white,
  }) {
    final textDirection = Directionality.of(context);
    final valueTextAlign = textDirection == TextDirection.rtl ? TextAlign.start : TextAlign.end;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF3B3C45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        textDirection: textDirection,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: valueTextAlign,
              style: TextStyle(
                color: valueColor,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditableInlineField(BuildContext context) {
    final textDirection = Directionality.of(context);
    final hintTextAlign = textDirection == TextDirection.rtl ? TextAlign.start : TextAlign.end;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF3B3C45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        textDirection: textDirection,
        children: [
          const Text(
            'New Name',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: SizedBox(
              height: 20,
              child: TextField(
                controller: _newNameController,
                textAlign: hintTextAlign,
                textAlignVertical: TextAlignVertical.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  height: 1.0,
                ),
                decoration: const InputDecoration(
                  hintText: 'Please Enter',
                  hintStyle: TextStyle(
                    color: Colors.white38,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.0,
                  ),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

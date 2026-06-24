import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../core/network/api_service.dart';
import '../../../components/rtl_back_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../home/pages/main_page.dart' show currentTabIndexProvider;
import '../../auth/models/user_model.dart';
import '../../auth/pages/photo_setting_page.dart' show RegistrationFlowContext;
import '../../auth/providers/auth_provider.dart';

class ChangeNamePage extends ConsumerStatefulWidget {
  const ChangeNamePage({
    super.key,
    this.fromRegister = false,
    this.registrationContext,
  });

  final bool fromRegister;
  final RegistrationFlowContext? registrationContext;

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

  void _goToProfileTab() {
    ref.read(currentTabIndexProvider.notifier).state = 4;
    context.go('/profile');
  }

  @override
  void dispose() {
    _newNameController.removeListener(_handleNameChanged);
    _nameController.dispose();
    _newNameController.dispose();
    super.dispose();
  }

  Future<void> _ensureRegistrationIdentity(RegistrationFlowContext registrationContext) async {
    final l10n = AppLocalizations.of(context);
    final authNotifier = ref.read(authProvider.notifier);
    final authState = ref.read(authProvider);
    final session = authState.registrationSession;
    final currentUser = authState.user;
    final expectedUserId = (session?.userId.isNotEmpty == true
            ? session!.userId
            : registrationContext.userId)
        .trim();
    final expectedEmail = (session?.email.isNotEmpty == true
            ? session!.email
            : registrationContext.email)
        .trim()
        .toLowerCase();

    if (session == null) {
      throw Exception(l10n.registrationSessionExpired);
    }

    bool matchesCurrentUser(UserModel? user) {
      if (user == null) return false;
      final userIdMatches = expectedUserId.isNotEmpty && user.id.trim() == expectedUserId;
      final emailMatches = expectedEmail.isNotEmpty && (user.email?.trim().toLowerCase() == expectedEmail);
      return userIdMatches || emailMatches;
    }

    if (matchesCurrentUser(currentUser)) {
      return;
    }

    final resp = await apiServiceProvider.getUserCenter();
    if (!resp.isSuccess || resp.data == null) {
      throw Exception(resp.error ?? l10n.failedToVerifyAccount);
    }

    await authNotifier.updateUserFromData(resp.data as Map<String, dynamic>);

    final refreshedUser = ref.read(authProvider).user;
    if (!matchesCurrentUser(refreshedUser)) {
      throw Exception(l10n.loginSessionMismatch);
    }
  }

  Future<void> _onConfirm() async {
    final l10n = AppLocalizations.of(context);
    final newName = _newNameController.text.trim();
    if (newName.isEmpty || _isSubmitting) return;

    setState(() => _isSubmitting = true);

    try {
      if (widget.fromRegister) {
        final registrationContext = widget.registrationContext;
        if (registrationContext == null) {
          throw Exception(l10n.missingRegistrationContext);
        }
        await _ensureRegistrationIdentity(registrationContext);
      }

      await ref.read(authProvider.notifier).updateNickname(newName);

      final resp = await apiServiceProvider.getUserCenter();
      if (!resp.isSuccess) {
        throw Exception(resp.error ?? l10n.failedToUpdateName);
      }

      if (resp.data != null && mounted) {
        await ref
            .read(authProvider.notifier)
            .updateUserFromData(resp.data as Map<String, dynamic>);
      }

      if (!mounted) {
        return;
      }

      if (widget.fromRegister) {
        ref.read(authProvider.notifier).clearRegistrationSession();
      }
      _goToProfileTab();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is Exception
          ? error.toString().replaceFirst('Exception: ', '')
      : l10n.failedToUpdateName;
      _showErrorMessage(message);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);

    // 游客直接跳转登录；注册补全流程允许临时放行
    if ((auth.user == null || auth.user!.isTourist) && !widget.fromRegister) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/auth/login?back=/profile');
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
                        _goToProfileTab();
                      }
                    },
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                  Expanded(
                    child: Text(
                      l10n.changeName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
                      title: l10n.nameField,
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
                onTap: _goToProfileTab,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 15),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.transparent,
                    border: Border.all(color: const Color(0xFF8F4EFF), width: 1),
                    borderRadius: BorderRadius.circular(24),
                  ),
                    child: Text(
                      l10n.skip,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
                  l10n.confirm,
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
    final l10n = AppLocalizations.of(context);
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
          Text(
            l10n.newName,
            style: const TextStyle(
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
                decoration: InputDecoration(
                  hintText: l10n.pleaseEnter,
                  hintStyle: const TextStyle(
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

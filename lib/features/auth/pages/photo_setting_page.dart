import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_service.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../home/pages/main_page.dart' show currentTabIndexProvider;
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';

class RegistrationFlowContext {
  const RegistrationFlowContext({
    required this.email,
    required this.userId,
    this.fromRegister = true,
  });

  final String email;
  final String userId;
  final bool fromRegister;
}

class PhotoSettingPage extends ConsumerStatefulWidget {
  const PhotoSettingPage({
    super.key,
    this.fromRegister = false,
    this.registrationContext,
  });

  final bool fromRegister;
  final RegistrationFlowContext? registrationContext;

  @override
  ConsumerState<PhotoSettingPage> createState() => _PhotoSettingPageState();
}

class _PhotoSettingPageState extends ConsumerState<PhotoSettingPage> {
  List<String> _avatars = [];
  String? _selectedAvatar;
  bool _isLoading = true;
  bool _isSubmitting = false;

  void _showErrorMessage(String message) {
    AppSnackBar.show(context, message: message);
  }

  @override
  void initState() {
    super.initState();
    _loadAvatars();
  }

  Future<void> _loadAvatars() async {
    setState(() => _isLoading = true);
    final resp = await apiServiceProvider.getAvatarList();
    if (!mounted) {
      return;
    }

    if (resp.isSuccess && resp.data != null) {
      final list = resp.data as List;
      setState(() {
        _avatars = list.map((e) => (e as Map<String, dynamic>)['iconUrl'] as String).toList();
        _isLoading = false;
      });
    } else {
      setState(() => _isLoading = false);
      _showErrorMessage(resp.error ?? 'Failed to load avatars');
    }
  }

  Future<void> _ensureRegistrationIdentity(RegistrationFlowContext registrationContext) async {
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
      throw Exception('Registration session expired. Please register again.');
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
      throw Exception(resp.error ?? 'Failed to verify current account');
    }

    final userData = resp.data as Map<String, dynamic>;
    await authNotifier.updateUserFromData(userData);

    final refreshedUser = ref.read(authProvider).user;
    if (!matchesCurrentUser(refreshedUser)) {
      throw Exception('Current login session does not match the newly registered account. Please log in again and retry.');
    }
  }

  void _goToProfileTab() {
    ref.read(currentTabIndexProvider.notifier).state = 4;
    context.go('/profile');
  }

  void _onSkip() {
    if (widget.fromRegister) {
      context.go('/change-name', extra: widget.registrationContext ?? true);
      return;
    }
    ref.read(authProvider.notifier).clearRegistrationSession();
    _goToProfileTab();
  }

  Future<void> _onContinue() async {
    if (_selectedAvatar == null || _isSubmitting) {
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      if (widget.fromRegister) {
        final registrationContext = widget.registrationContext;
        if (registrationContext == null) {
          throw Exception('Missing registration context');
        }
        await _ensureRegistrationIdentity(registrationContext);
      }

      await ref.read(authProvider.notifier).updateAvatar(_selectedAvatar!);

      final resp = await apiServiceProvider.getUserCenter();
      if (!resp.isSuccess) {
        throw Exception(resp.error ?? 'Failed to update avatar');
      }

      if (resp.data != null && mounted) {
        await ref.read(authProvider.notifier).updateUserFromData(resp.data as Map<String, dynamic>);
      }

      if (!mounted) {
        return;
      }

      if (widget.fromRegister) {
        context.go('/change-name', extra: widget.registrationContext ?? true);
      } else {
        _goToProfileTab();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message = error is Exception
          ? error.toString().replaceFirst('Exception: ', '')
          : 'Failed to update avatar';
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
                children: [
                  RtlBackButton(
                    onPressed: () async {
                      if (widget.fromRegister) {
                        final didPop = await Navigator.of(context).maybePop();
                        if (!context.mounted) {
                          return;
                        }
                        if (!didPop) {
                          _goToProfileTab();
                        }
                      } else {
                        _goToProfileTab();
                      }
                    },
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                  const Expanded(
                    child: Text(
                      'Photo Setting',
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
            const SizedBox(height: 24),
            // 头像列表
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Color(0xFF8F4EFF)),
                    )
                  : _avatars.isEmpty
                      ? const Center(
                          child: Text(
                            'No avatars available',
                            style: TextStyle(color: Colors.white54),
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisSpacing: 16,
                            crossAxisSpacing: 16,
                          ),
                          itemCount: _avatars.length,
                          itemBuilder: (context, index) {
                            final url = _avatars[index];
                            final isSelected = _selectedAvatar == url;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedAvatar = url),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: isSelected
                                      ? Border.all(
                                          color: const Color(0xFF8F4EFF),
                                          width: 3,
                                        )
                                      : null,
                                ),
                                child: ClipOval(
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      color: const Color(0xFF3B3C45),
                                      child: const Icon(
                                        Icons.person,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            // Skip 按钮（仅注册流程显示）
            if (widget.fromRegister) ...[
              GestureDetector(
                onTap: _onSkip,
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
            // Continue 按钮
            GestureDetector(
              onTap: _selectedAvatar != null && !_isSubmitting ? _onContinue : null,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 15),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: _selectedAvatar != null && !_isSubmitting
                      ? const LinearGradient(
                          colors: [Color(0xFF8F4EFF), Color(0xFFA237FF)],
                        )
                      : null,
                  color: _selectedAvatar == null || _isSubmitting
                      ? const Color(0xFF3B3C45)
                      : null,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  'confirm',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _selectedAvatar != null && !_isSubmitting
                        ? Colors.white
                        : Colors.white38,
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
}

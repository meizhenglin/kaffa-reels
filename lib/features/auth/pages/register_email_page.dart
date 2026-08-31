import 'dart:async';
import 'dart:math';

import 'package:email_validator/email_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../components/rtl_back_button.dart';
import '../../../core/network/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/auth_provider.dart' show AuthState;
import 'photo_setting_page.dart' show RegistrationFlowContext;
import '../../payment/providers/membership_provider.dart'
    show memberStateProvider;

class RegisterEmailPage extends ConsumerStatefulWidget {
  const RegisterEmailPage({super.key, this.backTarget = '/auth/login'});

  final String backTarget;

  @override
  ConsumerState<RegisterEmailPage> createState() => _RegisterEmailPageState();
}

class _RegisterEmailPageState extends ConsumerState<RegisterEmailPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _policyShakeKey = GlobalKey<_PolicyCheckboxState>();
  bool _agreePolicy = false;

  bool _showCodeInput = false;
  bool _showConfirm = false;
  bool _showPasswordInput = false;
  bool _isLoading = false;
  bool _isConfirmLoading = false;
  int _countdown = 0;
  Timer? _timer;
  Timer? _errorClearTimer;
  ProviderSubscription<AuthState>? _authErrorSubscription;

  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _passwordFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_clearAuthErrorOnInput);
    _codeController.addListener(_clearAuthErrorOnInput);
    _passwordController.addListener(_clearAuthErrorOnInput);
    _confirmPasswordController.addListener(_clearAuthErrorOnInput);
    _authErrorSubscription = ref.listenManual<AuthState>(
      authProvider,
      (previous, next) => _scheduleErrorAutoClear(next.errorMessage),
    );
  }

  void _scheduleErrorAutoClear(String? errorMessage) {
    _errorClearTimer?.cancel();
    final message = errorMessage?.trim();
    if (message == null || message.isEmpty) {
      return;
    }
    _errorClearTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      final authState = ref.read(authProvider);
      if (authState.errorMessage == message) {
        ref.read(authProvider.notifier).clearError();
      }
    });
  }

  void _clearAuthErrorOnInput() {
    _errorClearTimer?.cancel();
    final authState = ref.read(authProvider);
    if (authState.errorMessage != null && authState.errorMessage!.isNotEmpty) {
      ref.read(authProvider.notifier).clearError();
    }
  }

  Future<void> _confirmPassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    if (!_agreePolicy) {
      _policyShakeKey.currentState?.shake();
      return;
    }

    setState(() => _isLoading = true);

    final success = await ref
        .read(authProvider.notifier)
        .signUpWithEmail(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          username: _emailController.text.split('@').first,
        );

    if (!mounted) return;

    setState(() => _isLoading = false);

    if (success) {
      final loginSuccess = await ref
          .read(authProvider.notifier)
          .signInWithEmailForRegistration(
            _emailController.text.trim(),
            _passwordController.text,
          );
      if (!mounted) return;
      if (!loginSuccess) {
        final errorMsg = ref.read(authProvider).errorMessage;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE53935),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 36),
                ),
                const SizedBox(height: 16),
                Text(
                  errorMsg ?? 'Registration succeeded, but login failed',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && Navigator.canPop(context)) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        });
        return;
      }

      try {
        final resp = await apiServiceProvider.getUserCenter();
        if (resp.isSuccess && resp.data != null) {
          final currentUser = ref.read(authProvider).user;
          final userCenterData = resp.data as Map<String, dynamic>;
          final mergedUserData = <String, dynamic>{
            ...?currentUser?.toJson(),
            ...userCenterData,
            if (userCenterData['userId'] == null && currentUser?.id != null)
              'userId': currentUser!.id,
            if (userCenterData['email'] == null && currentUser?.email != null)
              'email': currentUser!.email,
            if (userCenterData['passportType'] == null &&
                currentUser?.passportType != null)
              'passportType': currentUser!.passportType,
            'isGuest': false,
          };
          await ref
              .read(authProvider.notifier)
              .updateUserFromData(mergedUserData);
        }
      } catch (_) {}
      if (!mounted) return;
      final authState = ref.read(authProvider);
      final registeredUser = authState.user;
      final registrationSession = authState.registrationSession;
      final registrationContext = RegistrationFlowContext(
        email: registrationSession?.email ?? _emailController.text.trim(),
        userId: registrationSession?.userId ?? registeredUser?.id ?? '',
      );
      debugPrint(
        '[RegisterEmail] registration flow ready, opening photo-setting',
      );
      ref.read(authProvider.notifier).clearGuestLoginStatus();

      // Refresh member status after registration/login
      ref.read(memberStateProvider.notifier).refreshStatus();

      GoRouter.of(
        context,
      ).go('/auth/photo-setting', extra: registrationContext);
    } else {
      final errorMsg = ref.read(authProvider).errorMessage;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFFE53935),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                errorMsg ?? 'Registration failed',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }
  }

  @override
  void dispose() {
    _authErrorSubscription?.close();
    _errorClearTimer?.cancel();
    _emailController.removeListener(_clearAuthErrorOnInput);
    _codeController.removeListener(_clearAuthErrorOnInput);
    _passwordController.removeListener(_clearAuthErrorOnInput);
    _confirmPasswordController.removeListener(_clearAuthErrorOnInput);
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    setState(() => _countdown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _sendCode() async {
    if (_isLoading) return;
    if (!_emailFormKey.currentState!.validate()) return;
    if (!_agreePolicy) {
      _policyShakeKey.currentState?.shake();
      return;
    }

    setState(() {
      _isLoading = true;
      _showCodeInput = true;
      _showConfirm = true;
    });

    final authService = ref.read(authServiceProvider);
    final result = await authService.sendEmailCode(
      email: _emailController.text.trim(),
    );

    if (!mounted) return;

    if (result.success) {
      _startCountdown();
      setState(() => _isLoading = false);
    } else {
      setState(() {
        _isLoading = false;
        _showCodeInput = false;
        _showConfirm = false;
      });
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFFE53935),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                result.message ?? 'Failed to send code',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreePolicy) {
      _policyShakeKey.currentState?.shake();
      return;
    }

    setState(() => _isConfirmLoading = true);

    final authService = ref.read(authServiceProvider);
    final result = await authService.checkEmailCode(
      email: _emailController.text.trim(),
      code: _codeController.text.trim(),
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _isConfirmLoading = false;
        _showPasswordInput = true;
      });
    } else {
      setState(() => _isConfirmLoading = false);
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: const BoxDecoration(
                  color: Color(0xFFE53935),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                result.message ?? 'Verification failed',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      );
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.of(context, rootNavigator: true).pop();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login_bg.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF1A1A2A)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: Column(
                children: [
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      RtlBackButton(
                        onPressed: () {
                          ref.read(authProvider.notifier).clearError();
                          context.go(widget.backTarget);
                        },
                        color: Colors.white,
                        constraints: const BoxConstraints(
                          minWidth: 20,
                          minHeight: 20,
                        ),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Create Account',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const Opacity(
                        opacity: 0,
                        child: RtlBackButton(
                          onPressed: null,
                          color: Colors.white,
                          constraints: BoxConstraints(
                            minWidth: 20,
                            minHeight: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 67),
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: Image.asset(
                        'assets/images/APP_LOGO_NEW_SMALL.png',
                        width: 92,
                        height: 92,
                        errorBuilder: (_, __, ___) => Container(
                          width: 92,
                          height: 92,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8F4EFF), Color(0xFFA237FF)],
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 63),
                  // Email and code section
                  if (!_showPasswordInput) ...[
                    Form(
                      key: _emailFormKey,
                      child: _EmailInput(
                        controller: _emailController,
                        enabled: !_showConfirm,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return l10n.requiredField;
                          }
                          if (!EmailValidator.validate(v.trim())) {
                            return l10n.invalidEmail;
                          }
                          return null;
                        },
                      ),
                    ),
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          if (_showCodeInput) ...[
                            const SizedBox(height: 24),
                            _CodeInput(
                              controller: _codeController,
                              enabled: !_isLoading,
                              isLoading: _isLoading,
                              countdown: _countdown,
                              onResend: _isLoading ? null : _sendCode,
                              validator: (v) {
                                if (v == null || v.isEmpty) {
                                  return l10n.requiredField;
                                }
                                return null;
                              },
                            ),
                          ],
                          Consumer(
                            builder: (_, ref, __) {
                              final msg = ref.watch(authProvider).errorMessage;
                              if (msg == null) return const SizedBox.shrink();
                              return Column(
                                children: [
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      msg,
                                      style: const TextStyle(
                                        color: Color(0xFFFF6B6B),
                                        fontSize: 13,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 24),
                          if (!_showCodeInput) ...[
                            GestureDetector(
                              onTap: _sendCode,
                              child: Container(
                                width: double.infinity,
                                height: 50,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF8F4EFF),
                                      Color(0xFFA237FF),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(30),
                                ),
                                child: const Center(
                                  child: Text(
                                    'Obtain Verification code',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (_showConfirm) ...[
                            const SizedBox(height: 16),
                            Builder(
                              builder: (context) {
                                return GestureDetector(
                                  onTap: _isConfirmLoading ? null : _confirm,
                                  child: Container(
                                    width: double.infinity,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [
                                          Color(0xFF8F4EFF),
                                          Color(0xFFA237FF),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(30),
                                    ),
                                    child: Center(
                                      child: _isConfirmLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: Image(
                                                image: AssetImage(
                                                  'assets/images/loading_icon.png',
                                                ),
                                              ),
                                            )
                                          : const Text(
                                              'Confirm',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  // Password section (same position as email/code)
                  if (_showPasswordInput) ...[
                    Form(
                      key: _passwordFormKey,
                      child: Column(
                        children: [
                          _PasswordInput(
                            controller: _passwordController,
                            hintText: 'Enter Password',
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return l10n.requiredField;
                              }
                              if (v.length < 6) {
                                return 'Minimum 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 15),
                          _PasswordInput(
                            controller: _confirmPasswordController,
                            hintText: 'Re-enter New Password',
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return l10n.requiredField;
                              }
                              if (v != _passwordController.text) {
                                return 'Passwords do not match';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          GestureDetector(
                            onTap: _isLoading ? null : _confirmPassword,
                            child: Container(
                              width: double.infinity,
                              height: 50,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF8F4EFF),
                                    Color(0xFFA237FF),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(30),
                              ),
                              child: Center(
                                child: _isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: Image(
                                          image: AssetImage(
                                            'assets/images/loading_icon.png',
                                          ),
                                        ),
                                      )
                                    : const Text(
                                        'Confirm',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  _PolicyCheckbox(
                    key: _policyShakeKey,
                    value: _agreePolicy,
                    onChanged: (v) => setState(() => _agreePolicy = v ?? false),
                  ),
                  const Spacer(),
                  const SizedBox(height: 60),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailInput extends StatelessWidget {
  const _EmailInput({
    required this.controller,
    required this.validator,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      autofillHints: const [AutofillHints.email],
      validator: validator,
      cursorColor: const Color(0xFFFFFFFF),
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Enter E-Mail',
        hintStyle: const TextStyle(
          color: Color(0xFF999999),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: Padding(
          padding: const EdgeInsetsDirectional.only(start: 20, end: 12),
          child: Image.asset(
            'assets/images/login_email_icon.png',
            width: 20,
            height: 20,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.email_outlined, size: 20),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
        filled: true,
        fillColor: const Color(0xFF3B3C45),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12),
      ),
    );
  }
}

class _CodeInput extends StatelessWidget {
  const _CodeInput({
    required this.controller,
    required this.validator,
    required this.isLoading,
    required this.countdown,
    required this.onResend,
    this.enabled = true,
  });

  final TextEditingController controller;
  final FormFieldValidator<String> validator;
  final bool isLoading;
  final int countdown;
  final VoidCallback? onResend;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      validator: validator,
      cursorColor: const Color(0xFFFFFFFF),
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Enter Verification Code',
        hintStyle: const TextStyle(
          color: Color(0xFF999999),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: const Padding(
          padding: EdgeInsetsDirectional.only(start: 20, end: 12),
          child: Icon(Icons.verified_user_outlined, size: 20),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
        suffixIcon: (countdown > 0 || isLoading)
            ? Padding(
                padding: const EdgeInsetsDirectional.only(end: 20),
                child: Row(
                  textDirection: TextDirection.ltr,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 1,
                      height: 18,
                      color: const Color(0xFF999999),
                    ),
                    const SizedBox(width: 12),
                    isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Image(
                              image: AssetImage(
                                'assets/images/loading_icon.png',
                              ),
                            ),
                          )
                        : Text(
                            '${countdown}S',
                            style: const TextStyle(
                              color: Color(0xFF999999),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ],
                ),
              )
            : Padding(
                padding: const EdgeInsetsDirectional.only(end: 20),
                child: Row(
                  textDirection: TextDirection.ltr,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 1,
                      height: 18,
                      color: const Color(0xFF999999),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: onResend == null ? null : () => onResend!(),
                      child: Text(
                        'Resend',
                        style: TextStyle(
                          color: Color(0xFF8F4EFF),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        suffixIconConstraints: const BoxConstraints(minWidth: 80),
        filled: true,
        fillColor: const Color(0xFF3B3C45),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12),
      ),
    );
  }
}

class _PasswordInput extends StatelessWidget {
  const _PasswordInput({
    required this.controller,
    required this.hintText,
    required this.validator,
  });

  final TextEditingController controller;
  final String hintText;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: true,
      validator: validator,
      cursorColor: const Color(0xFFFFFFFF),
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(
          color: Color(0xFF999999),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: const Padding(
          padding: EdgeInsetsDirectional.only(start: 20, end: 12),
          child: Icon(Icons.lock_outline, size: 20),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
        filled: true,
        fillColor: const Color(0xFF3B3C45),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30),
          borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
        ),
        errorStyle: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 12),
      ),
    );
  }
}

class _PolicyCheckbox extends StatefulWidget {
  _PolicyCheckbox({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  State<_PolicyCheckbox> createState() => _PolicyCheckboxState();
}

class _PolicyCheckboxState extends State<_PolicyCheckbox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void shake() {
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final dx = sin(_controller.value * pi * 3) * 5;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: GestureDetector(
        onTap: () => widget.onChanged(!widget.value),
        child: Row(
          textDirection: Directionality.of(context),
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 15,
              height: 15,
              child: GestureDetector(
                onTap: () => widget.onChanged(!widget.value),
                child: Image.asset(
                  widget.value
                      ? 'assets/images/selected_icon.png'
                      : 'assets/images/not_selected_icon.png',
                  width: 15,
                  height: 15,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: RichText(
                text: TextSpan(
                  text: 'I have read and agree ',
                  style: const TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(
                      text: 'User Agreement',
                      style: const TextStyle(
                        color: Color(0xFF8F4EFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => context.push('/auth/user-agreement'),
                    ),
                    const TextSpan(
                      text: ' And ',
                      style: TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: const TextStyle(
                        color: Color(0xFF8F4EFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => context.push('/auth/privacy-policy'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:email_validator/email_validator.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/providers/auth_provider.dart' show apiServiceProviderRef;
import '../../../core/utils/app_restart.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../../../components/rtl_back_button.dart';

class LoginEmailPage extends ConsumerStatefulWidget {
  const LoginEmailPage({super.key, this.redirect});

  final String? redirect;

  @override
  ConsumerState<LoginEmailPage> createState() => _LoginEmailPageState();
}

class _LoginEmailPageState extends ConsumerState<LoginEmailPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _autoLogin = false;

  @override
  void initState() {
    super.initState();
    _loadAutoLoginSettings();
  }

  Future<void> _loadAutoLoginSettings() async {
    final storage = ref.read(storageServiceProvider);
    final enabled = await storage.getAutoLogin();
    final savedEmail = await storage.getAutoLoginEmail();
    if (mounted) {
      setState(() {
        _autoLogin = enabled;
        if (savedEmail != null && savedEmail.isNotEmpty) {
          _emailController.text = savedEmail;
        }
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    debugPrint('=== _submit called ===');
    if (!_formKey.currentState!.validate()) return;

    ref.read(authProvider.notifier).clearError();
    final wasMounted = mounted;
    final router = GoRouter.of(context);

    final success = await ref.read(authProvider.notifier).signInWithEmail(
          _emailController.text.trim(),
          _passwordController.text,
        );

    if (!success) {
      debugPrint('[LoginEmail] signInWithEmail returned false');
      return;
    }

    debugPrint('[LoginEmail] signInWithEmail success, saving credentials...');

    try {
      final resp = await ref.read(apiServiceProviderRef).getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        final userData = resp.data as Map<String, dynamic>;
        ref.read(authProvider.notifier).updateUserFromData(userData);
        debugPrint('[LoginEmail] getUserCenter success: $userData');
      } else {
        debugPrint(
          '[LoginEmail] getUserCenter failed: '
          'success=${resp.isSuccess} data=${resp.data} error=${resp.error}',
        );
      }
    } catch (e) {
      debugPrint('[LoginEmail] getUserCenter error: $e');
    }

    // 保存或清除自动登录凭证
    final storage = ref.read(storageServiceProvider);
    if (_autoLogin) {
      await storage.saveAutoLogin(true);
      await storage.saveAutoLoginEmail(_emailController.text.trim());
      await storage.saveAutoLoginPassword(_passwordController.text);
      await storage.saveAutoLoginTimestamp();
    } else {
      await storage.saveAutoLogin(false);
      await storage.clearAutoLoginCredentials();
    }

    debugPrint('[LoginEmail] credentials saved, wasMounted=$wasMounted, navigating...');

    // 再次检查 mounted，因为所有 await 都结束后状态可能已改变
    if (!wasMounted) {
      debugPrint('[LoginEmail] no longer mounted after awaits, skip navigation');
      return;
    }

    // 登录成功后按平台处理；如果外部显式传了 redirect，则优先按 redirect 跳转
    final target = widget.redirect;
    if (target != null && target.isNotEmpty) {
      router.go(target);
      return;
    }

    if (kIsWeb) {
      router.go('/');
      return;
    }

    await AppRestart.restart();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
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
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                children: [
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      RtlBackButton(
                        onPressed: () {
                          final navigator = Navigator.of(context);
                          if (navigator.canPop()) {
                            navigator.pop();
                          } else {
                            context.push('/auth/login');
                          }
                        },
                        color: Colors.white,
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      ),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'Log in to Qahwa Tv',
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
                      constraints: BoxConstraints(minWidth: 20, minHeight: 20),
                    ),
                  ),
                    ],
                  ),
                  const SizedBox(height: 67),
                  Center(
                    child: Image.asset(
                      'assets/images/login_logo.png',
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
                  const SizedBox(height: 63),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _EmailInput(
                          controller: _emailController,
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
                        const SizedBox(height: 20),
                        _PasswordInput(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          onToggle: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return l10n.requiredField;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: GestureDetector(
                            onTap: () => context.push('/auth/forgot-password'),
                            child: const Text(
                              'Forget Your Password',
                              style: TextStyle(
                                color: Color(0xFFFFFFFF),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        if (auth.errorMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              auth.errorMessage!,
                              style: const TextStyle(
                                color: Color(0xFFFF6B6B),
                                fontSize: 13,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        GestureDetector(
                          onTap: auth.isLoading ? null : _submit,
                          child: Container(
                            width: double.infinity,
                            height: 48,
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
                              child: auth.isLoading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Log in',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        GestureDetector(
                          onTap: () =>
                              setState(() => _autoLogin = !_autoLogin),
                          child: Row(
                            textDirection: Directionality.of(context),
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 15,
                                height: 15,
                                child: GestureDetector(
                                  onTap: () =>
                                      setState(() => _autoLogin = !_autoLogin),
                                  child: Image.asset(
                                    _autoLogin
                                        ? 'assets/images/selected_icon.png'
                                        : 'assets/images/not_selected_icon.png',
                                    width: 15,
                                    height: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Auto log (expires after 30 days)',
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push('/auth/register'),
                    child: RichText(
                      text: const TextSpan(
                        text: 'Do not have StoryDrama account? ',
                        style: TextStyle(
                          color: Color(0xFF999999),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        children: [
                          TextSpan(
                            text: 'Sign up',
                            style: TextStyle(
                              color: Color(0xFF8F4EFF),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
  });

  final TextEditingController controller;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
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
            errorBuilder: (_, __, ___) => const Icon(
              Icons.email_outlined,
              size: 20,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
        filled: true,
        fillColor: const Color(0xFF3B3C45),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    required this.obscureText,
    required this.onToggle,
    required this.validator,
  });

  final TextEditingController controller;
  final bool obscureText;
  final VoidCallback onToggle;
  final FormFieldValidator<String> validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      autofillHints: const [AutofillHints.password],
      validator: validator,
      cursorColor: const Color(0xFFFFFFFF),
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: 'Enter Password',
        hintStyle: const TextStyle(
          color: Color(0xFF999999),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 20, right: 12),
          child: Icon(
            Icons.lock_outline,
            size: 20,
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
        suffixIcon: GestureDetector(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Image.asset(
              obscureText
                  ? 'assets/images/dontShowPsw_icon.png'
                  : 'assets/images/showPsw_icon.png',
              width: 20,
              height: 20,
            ),
          ),
        ),
        suffixIconConstraints: const BoxConstraints(minWidth: 40),
        filled: true,
        fillColor: const Color(0xFF3B3C45),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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

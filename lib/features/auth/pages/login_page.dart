import 'dart:io';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/social_sign_in_button.dart';

/// ============================================================================
/// 登录/注册页面
///
/// 【功能】
/// - 邮箱密码登录/注册（同一页面切换）
/// - Google 登录
/// - Apple 登录（仅 iOS）
/// - 游客模式
///
/// 【如何修改】
/// - 修改表单验证：修改 _validateEmail/Password/Confirm 方法
/// - 修改登录按钮逻辑：修改 _submit 方法
/// ============================================================================
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.redirect});
  final String? redirect;  // 登录后重定向路径

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isRegisterMode = false;  // 是否注册模式
  bool _obscurePassword = true;  // 密码是否隐藏
  bool _obscureConfirm = true;   // 确认密码是否隐藏
  String? _emailError;
  String? _passwordError;
  String? _confirmError;

  @override void dispose() {
    _emailController.dispose(); _passwordController.dispose(); _confirmPasswordController.dispose();
    super.dispose();
  }

  /// 邮箱验证
  void _validateEmail(String value) {
    setState(() {
      if (value.isEmpty) _emailError = AppLocalizations.of(context).requiredField;
      else if (!EmailValidator.validate(value.trim())) _emailError = AppLocalizations.of(context).invalidEmail;
      else _emailError = null;
    });
  }

  /// 密码验证
  void _validatePassword(String value) {
    setState(() {
      if (value.isEmpty) _passwordError = AppLocalizations.of(context).requiredField;
      else if (value.length < 6) _passwordError = AppLocalizations.of(context).passwordTooShort;
      else _passwordError = null;
    });
  }

  /// 确认密码验证
  void _validateConfirm(String value) {
    setState(() {
      if (value != _passwordController.text) _confirmError = AppLocalizations.of(context).passwordsDoNotMatch;
      else _confirmError = null;
    });
  }

  /// 表单是否有效
  bool get _isFormValid {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || !EmailValidator.validate(email)) return false;
    if (password.length < 6) return false;
    if (_isRegisterMode && password != _confirmPasswordController.text) return false;
    return _emailError == null && _passwordError == null && (_isRegisterMode ? _confirmError == null : true);
  }

  /// 提交表单
  Future<void> _submit() async {
    _validateEmail(_emailController.text);
    _validatePassword(_passwordController.text);
    if (_isRegisterMode) _validateConfirm(_confirmPasswordController.text);
    if (!_formKey.currentState!.validate() || !_isFormValid) return;

    ref.read(authProvider.notifier).clearError();
    final notifier = ref.read(authProvider.notifier);
    final success = _isRegisterMode
        ? await notifier.signUpWithEmail(email: _emailController.text.trim(), password: _passwordController.text, username: _emailController.text.split('@').first)
        : await notifier.signInWithEmail(_emailController.text.trim(), _passwordController.text);

    if (success && mounted) _navigateAfterAuth();
  }

  /// 认证后导航
  void _navigateAfterAuth() {
    final redirect = widget.redirect;
    if (redirect != null && redirect.isNotEmpty && redirect != '/auth/login') context.go(redirect);
    else context.go('/');
  }

  /// Google 登录
  Future<void> _signInWithGoogle() async {
    ref.read(authProvider.notifier).clearError();
    final success = await ref.read(authProvider.notifier).signInWithGoogle();
    if (success && mounted) _navigateAfterAuth();
  }

  /// Apple 登录
  Future<void> _signInWithApple() async {
    ref.read(authProvider.notifier).clearError();
    final success = await ref.read(authProvider.notifier).signInWithApple();
    if (success && mounted) _navigateAfterAuth();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);

    return GradientScaffold(
      body: SafeArea(child: Center(child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420),
          child: Form(key: _formKey, autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const SizedBox(height: 24),
              Icon(Icons.movie_filter_rounded, size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(l10n.appTitle, textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(_isRegisterMode ? l10n.createAccount : l10n.welcomeBack, textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.6))),
              const SizedBox(height: 32),

              // 邮箱输入框
              AuthTextField(controller: _emailController, label: l10n.email, keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next, prefixIcon: Icons.email_outlined, errorText: _emailError,
                autofillHints: const [AutofillHints.email], onChanged: _validateEmail,
                validator: (v) { if (v == null || v.isEmpty) return l10n.requiredField; if (!EmailValidator.validate(v.trim())) return l10n.invalidEmail; return null; }),
              const SizedBox(height: 16),

              // 密码输入框
              AuthTextField(controller: _passwordController, label: l10n.password, obscureText: _obscurePassword,
                textInputAction: _isRegisterMode ? TextInputAction.next : TextInputAction.done,
                prefixIcon: Icons.lock_outline, errorText: _passwordError,
                autofillHints: _isRegisterMode ? const [AutofillHints.newPassword] : const [AutofillHints.password],
                onChanged: _validatePassword,
                suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
                validator: (v) { if (v == null || v.isEmpty) return l10n.requiredField; if (v.length < 6) return l10n.passwordTooShort; return null; }),

              // 确认密码（仅注册模式）
              if (_isRegisterMode) ...[
                const SizedBox(height: 16),
                AuthTextField(controller: _confirmPasswordController, label: l10n.confirmPassword, obscureText: _obscureConfirm,
                  textInputAction: TextInputAction.done, prefixIcon: Icons.lock_outline, errorText: _confirmError,
                  autofillHints: const [AutofillHints.newPassword], onChanged: _validateConfirm,
                  suffixIcon: IconButton(icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm)),
                  validator: (v) { if (v != _passwordController.text) return l10n.passwordsDoNotMatch; return null; }),
              ],

              // 忘记密码链接（仅登录模式）
              if (!_isRegisterMode) Align(alignment: AlignmentDirectional.centerEnd,
                child: TextButton(onPressed: () => context.push('/auth/forgot-password'), child: Text(l10n.forgotPassword))),

              // 错误信息
              if (auth.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(auth.errorMessage!, style: TextStyle(color: theme.colorScheme.error), textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),

              // 提交按钮
              FilledButton(onPressed: auth.isLoading ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: auth.isLoading ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_isRegisterMode ? l10n.register : l10n.login)),

              const SizedBox(height: 12),
              OutlinedButton(onPressed: () { setState(() { _isRegisterMode = !_isRegisterMode; _confirmPasswordController.clear(); _confirmError = null; ref.read(authProvider.notifier).clearError(); }); },
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(_isRegisterMode ? '${l10n.login} →' : l10n.register)),

              // 社交登录分隔符
              const SizedBox(height: 16),
              Row(children: [const Expanded(child: Divider()), Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('OR', style: theme.textTheme.bodySmall)), const Expanded(child: Divider())]),
              const SizedBox(height: 16),

              // Google 登录
              SocialSignInButton(label: 'Continue with Google', isLoading: auth.isLoading,
                icon: Image.network('https://www.google.com/favicon.ico', width: 20, height: 20, errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 24)),
                onPressed: _signInWithGoogle),

              // Apple 登录（仅 iOS）
              if (Platform.isIOS) ...[
                const SizedBox(height: 12),
                SocialSignInButton(label: 'Continue with Apple', isLoading: auth.isLoading, backgroundColor: Colors.black, foregroundColor: Colors.white,
                  icon: const Icon(Icons.apple, size: 24), onPressed: _signInWithApple),
              ],

              const SizedBox(height: 16),
              TextButton(onPressed: () => context.go('/'), child: Text(l10n.continueAsGuest)),
            ])))))),
    );
  }
}

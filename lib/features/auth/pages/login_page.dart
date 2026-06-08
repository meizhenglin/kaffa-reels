import 'dart:async' as async;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../../../components/rtl_back_button.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.redirect});

  final String? redirect;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with WidgetsBindingObserver {
  bool _googleWarmUpStarted = false;
  bool _appIsInForeground = true;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted || message.trim().isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? const Color(0xFFD64545) : const Color(0xFF2E7D32),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  void _startGoogleWarmUpIfNeeded() {
    if (!mounted || _googleWarmUpStarted) return;
    _googleWarmUpStarted = true;
    async.unawaited(ref.read(authRepositoryProvider).warmUpGoogleSignIn());
  }

  void _navigateAfterLogin() {
    if (!mounted) return;

    final target = widget.redirect;
    if (target != null && target.isNotEmpty) {
      context.go(target);
      return;
    }

    context.push('/auth/photo-setting');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startGoogleWarmUpIfNeeded();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startGoogleWarmUpIfNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appIsInForeground = true;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _appIsInForeground = false;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                            context.go('/');
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
                      ),
                    ),
                  ),
                  const SizedBox(height: 63),
                  // Buttons — isolated in Builder so auth state changes don't
                  // rebuild the Sign up link below.
                  Builder(
                    builder: (context) {
                      return Column(
                        children: [
                          _PlatformButton(
                            label: 'Use E-Mail',
                            icon: Icons.email_outlined,
                            iconPath: 'assets/images/email_icon.png',
                            isLoading: false,
                            onTap: () {
                              context.pushNamed<String>(
                                'loginEmail',
                                extra: widget.redirect,
                              );
                            },
                          ),
                          const SizedBox(height: 15),
                          Consumer(
                            builder: (_, ref, __) {
                              final isLoading =
                                  ref.watch(authProvider).isLoading;
                              return _GoogleSignInButton(
                                label: 'Continue with Google',
                                isLoading: isLoading,
                                onTap: () async {
                                  if (!_appIsInForeground) return;
                                  _startGoogleWarmUpIfNeeded();
                                  debugPrint('[LoginPage] Google button tapped');
                                  ref.read(authProvider.notifier).clearError();
                                  await Future<void>.delayed(Duration.zero);
                                  final success = await ref
                                      .read(authProvider.notifier)
                                      .signInWithGoogle();
                                  if (!mounted || !_appIsInForeground) return;
                                  final errorMessage = ref.read(authProvider).errorMessage;
                                  debugPrint('[LoginPage] Google sign-in returned success=$success error=$errorMessage');
                                  if (success) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      _navigateAfterLogin();
                                    });
                                    return;
                                  }
                                  _showMessage(
                                    errorMessage ?? 'Google sign-in did not complete. Please try again.',
                                    isError: true,
                                  );
                                },
                              );
                            },
                          ),
                          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
                            const SizedBox(height: 16),
                            Consumer(
                              builder: (_, ref, __) {
                                final isLoading =
                                    ref.watch(authProvider).isLoading;
                                return _PlatformButton(
                                  label: 'Continue with Apple',
                                  icon: Icons.apple,
                                  iconPath: 'assets/images/apple_icon.png',
                                  isLoading: isLoading,
                                  isApple: true,
                                  onTap: () async {
                                    ref
                                        .read(authProvider.notifier)
                                        .clearError();
                                    final success = await ref
                                        .read(authProvider.notifier)
                                        .signInWithApple();
                                    if (success) {
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        _navigateAfterLogin();
                                      });
                                    }
                                  },
                                );
                              },
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => context.push('/auth/register'),
                    child: Center(
                      child: RichText(
                        text: TextSpan(
                          text: 'Do not have StoryDrama account? ',
                          style: const TextStyle(
                            color: Color(0xFF999999),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          children: const [
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

class _PlatformButton extends StatelessWidget {
  const _PlatformButton({
    required this.label,
    required this.icon,
    required this.isLoading,
    required this.onTap,
    this.isApple = false,
    this.iconPath,
  });

  final String label;
  final IconData icon;
  final bool isLoading;
  final VoidCallback onTap;
  final bool isApple;
  final String? iconPath;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isLoading ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 50,
        decoration: BoxDecoration(
          color: isApple ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(30),
        ),
        child: (isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: isApple ? Colors.white : Colors.black,
                ),
              )
            : iconPath != null
            ? Row(
                children: [
                  const SizedBox(width: 28),
                  Image.asset(
                    iconPath!,
                    width: 30,
                    height: 30,
                    errorBuilder: (_, __, ___) =>
                        Icon(icon, color: Colors.black, size: 30),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 58),
                ],
              )
            : Row(
                children: [
                  const SizedBox(width: 28),
                  Image.asset(
                    'assets/images/google_icon.png',
                    width: 22,
                    height: 22,
                    errorBuilder: (_, __, ___) =>
                        Icon(icon, color: Colors.black, size: 22),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: isApple ? Colors.white : Colors.black,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                ],
              )),
      ),
    );
  }
}

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.label,
    required this.isLoading,
    required this.onTap,
  });

  final String label;
  final bool isLoading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFDADCE0)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/google_icon.png',
                  width: 30,
                  height: 30,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox(
                    width: 30,
                    height: 30,
                    child: Center(
                      child: Text(
                        'G',
                        style: TextStyle(
                          color: Color(0xFF4285F4),
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Opacity(
                        opacity: isLoading ? 0 : 1,
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF1F1F1F),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                      if (isLoading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF1F1F1F),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 46),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

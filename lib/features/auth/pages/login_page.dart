import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.redirect});

  final String? redirect;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
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
                      GestureDetector(
                        onTap: () {
                          final navigator = Navigator.of(context);
                          if (navigator.canPop()) {
                            navigator.pop();
                          } else {
                            context.go('/');
                          }
                        },
                        child: Image.asset(
                          'assets/images/back.png',
                          width: 20,
                          height: 20,
                          color: Colors.white,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.arrow_forward,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
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
                      const SizedBox(width: 20),
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
                              return _PlatformButton(
                                label: 'Continue with Google',
                                icon: Icons.g_mobiledata,
                                iconPath: 'assets/images/google_icon.png',
                                isLoading: isLoading,
                                onTap: () async {
                                  ref.read(authProvider.notifier).clearError();
                                  final success = await ref
                                      .read(authProvider.notifier)
                                      .signInWithGoogle();
                                  if (success) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      _navigateAfterLogin();
                                    });
                                  }
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
                    onTap: () => context.push('/auth/register/email'),
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

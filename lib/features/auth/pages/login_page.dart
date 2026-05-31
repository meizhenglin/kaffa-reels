import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';

class LoginPage extends ConsumerWidget {
  const LoginPage({super.key, this.redirect});

  final String? redirect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final auth = ref.watch(authProvider);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image
          Image.asset(
            'assets/images/login_bg.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF1A1A2A)),
          ),
          // Content overlay
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 18),
                  // Back button + Title row
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
                  // Logo
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
                        // child: const Icon(
                        //   Icons.play_arrow_rounded,
                        //   color: Colors.white,
                        //   size: 36,
                        // ),
                      ),
                    ),
                  ),
                  // const SizedBox(height: 24),
                  // Title
                  // Center(
                  //   child: Text(
                  //     l10n?.login ?? 'Log in to Qahwa Tv',
                  //     style: const TextStyle(
                  //       color: Colors.white,
                  //       fontSize: 24,
                  //       fontWeight: FontWeight.bold,
                  //     ),
                  //   ),
                  // ),
                  const SizedBox(height: 63),
                  // Platform buttons
                  _PlatformButton(
                    label: 'Use E-Mail',
                    icon: Icons.email_outlined,
                    iconPath: 'assets/images/email_icon.png',
                    isLoading: false,
                    onTap: () =>
                        context.pushNamed('loginEmail', extra: redirect),
                  ),
                  const SizedBox(height: 15),
                  _PlatformButton(
                    label: 'Continue with Google',
                    icon: Icons.g_mobiledata,
                    iconPath: 'assets/images/google_icon.png',
                    isLoading: auth.isLoading,
                    onTap: () async {
                      ref.read(authProvider.notifier).clearError();
                      final success = await ref
                          .read(authProvider.notifier)
                          .signInWithGoogle();
                      if (success) {
                        final r = redirect;
                        if (r != null && r.isNotEmpty) {
                          context.go(r);
                        } else {
                          context.go('/');
                        }
                      }
                    },
                  ),
                  if (Platform.isIOS) ...[
                    const SizedBox(height: 16),
                    _PlatformButton(
                      label: 'Continue with Apple',
                      icon: Icons.apple,
                      iconPath: 'assets/images/apple_icon.png',
                      isLoading: auth.isLoading,
                      isApple: true,
                      onTap: () async {
                        ref.read(authProvider.notifier).clearError();
                        final success = await ref
                            .read(authProvider.notifier)
                            .signInWithApple();
                        if (success) {
                          final r = redirect;
                          if (r != null && r.isNotEmpty) {
                            context.go(r);
                          } else {
                            context.go('/');
                          }
                        }
                      },
                    ),
                  ],
                  const Spacer(),
                  // const SizedBox(height: 24),
                  // Sign up link
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
                        children: [
                          TextSpan(
                            text: 'Sign up',
                            style: const TextStyle(
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

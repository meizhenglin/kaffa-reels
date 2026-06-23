import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../../../components/rtl_back_button.dart';
import '../../home/pages/main_page.dart' show currentTabIndexProvider;
import '../../payment/providers/membership_provider.dart' show memberStateProvider;
import '../../../app/providers/app_providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key, this.redirect, this.backTarget = '/'});

  final String? redirect;
  final String backTarget;

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> with WidgetsBindingObserver {
  bool _appIsInForeground = true;
  bool _googleSignInInProgress = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        if (_googleSignInInProgress) {
          _googleSignInInProgress = false;
        }
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
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/login_bg.png',
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.cover,
            gaplessPlayback: true,
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
                        onPressed: () async {
                          // 如果目标是 short-video 页面，发送登录返回通知
                          final effectiveTarget = (widget.redirect != null &&
                                  widget.redirect!.isNotEmpty &&
                                  widget.redirect != '/profile')
                              ? widget.redirect
                              : widget.backTarget;
                          if (effectiveTarget == '/short-video') {
                            ref.read(loginReturnProvider.notifier).state++;
                          }

                          final navigator = Navigator.of(context);
                          final didPop = await navigator.maybePop();
                          if (!context.mounted) return;
                          if (!didPop) {
                            context.go(widget.backTarget);
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
                              final backTarget = Uri.encodeComponent('/auth/login?back=${Uri.encodeComponent(widget.backTarget)}');
                              final redirect = widget.redirect == null
                                  ? null
                                  : Uri.encodeComponent(widget.redirect!);
                              final route = StringBuffer('/auth/login/email?back=$backTarget');
                              if (redirect != null) {
                                route.write('&redirect=$redirect');
                              }
                              context.push(route.toString());
                            },
                          ),
                          const SizedBox(height: 15),
                          Consumer(
                            builder: (_, ref, __) {
                              final repository = ref.watch(authRepositoryProvider);
                              if (!repository.isGoogleSignInSupported) {
                                return const SizedBox.shrink();
                              }

                              final isLoading =
                                  ref.watch(authProvider).isLoading;
                              return _GoogleSignInButton(
                                label: 'Continue with Google',
                                isLoading: isLoading,
                                onTap: () async {
                                  if (!_appIsInForeground || _googleSignInInProgress) return;
                                  debugPrint('[LoginPage] Google button tapped');
                                  _googleSignInInProgress = true;

                                  // Show loading dialog
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    barrierColor: Colors.black54,
                                    builder: (context) => WillPopScope(
                                      onWillPop: () async => false,
                                      child: Center(
                                        child: ConstrainedBox(
                                          constraints: const BoxConstraints(
                                            minWidth: 120,
                                            maxWidth: 150,
                                            minHeight: 100,
                                            maxHeight: 100,
                                          ),
                                          child: Container(
                                            height: 100,
                                            alignment: Alignment.center,
                                            padding: const EdgeInsets.symmetric(horizontal: 24),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox(
                                                  width: 28,
                                                  height: 28,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                ),
                                                const SizedBox(height: 8),
                                                const Text(
                                                  'Signing in...',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );

                                  ref.read(authProvider.notifier).clearError();
                                  await Future<void>.delayed(Duration.zero);
                                  final success = await ref
                                      .read(authProvider.notifier)
                                      .signInWithGoogle();
                                  _googleSignInInProgress = false;

                                  debugPrint('[LoginPage] Google sign-in returned success=$success error=${ref.read(authProvider).errorMessage}');

                                  if (!mounted) return;

                                  if (success) {
                                    // Close loading dialog
                                    Navigator.of(context, rootNavigator: true).pop();
                                    // Show success dialog - auto close and navigate after 1 second
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (dialogContext) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF4CAF50),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.check,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            const Text(
                                              'Login Successful!',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    // Auto close and navigate after 1 second
                                    Future.delayed(const Duration(seconds: 1), () {
                                      if (!mounted) return;

                                      // 关闭成功弹窗
                                      Navigator.of(context).pop();

                                      // 触发 loginReturnProvider，刷新 ShortVideoPage 的视频列表
                                      if (widget.redirect != null && widget.redirect!.contains('/short-video')) {
                                        Future.delayed(Duration.zero, () {
                                          ref.read(loginReturnProvider.notifier).state++;
                                          debugPrint('[LoginPage] Google triggered loginReturnProvider');
                                        });
                                      }

                                      // 获取 root navigator 并连续 pop 两个页面回到 ShortVideoPage
                                      final rootNav = Navigator.of(context, rootNavigator: true);

                                      Future.delayed(const Duration(milliseconds: 100), () {
                                        debugPrint('[LoginPage] Google step 1: pop LoginPage');
                                        rootNav.pop();
                                      }).then((_) {
                                        return Future.delayed(Duration.zero, () {
                                          debugPrint('[LoginPage] Google step 2: pop LoginEmailPage if exists');
                                          if (Navigator.canPop(context)) {
                                            rootNav.pop();
                                          }
                                        });
                                      });
                                    });
                                    return;
                                  }

                                  // Close loading dialog
                                  Navigator.of(context, rootNavigator: true).pop();

                                  // Show error dialog - auto close after 2 seconds
                                  final errorMsg = ref.read(authProvider).errorMessage ?? 'Login failed. Please try again.';
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (dialogContext) => AlertDialog(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 36,
                                            height: 36,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFE53935),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            errorMsg,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  // Auto close after 2 seconds
                                  Future.delayed(const Duration(seconds: 2), () {
                                    if (mounted && Navigator.canPop(context)) {
                                      Navigator.of(context, rootNavigator: true).pop();
                                    }
                                  });
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
                                    if (!_appIsInForeground) return;

                                    // Show loading dialog
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      barrierColor: Colors.black54,
                                      builder: (context) => WillPopScope(
                                        onWillPop: () async => false,
                                        child: Center(
                                          child: ConstrainedBox(
                                            constraints: const BoxConstraints(
                                              minWidth: 120,
                                              maxWidth: 150,
                                            ),
                                            child: Container(
                                              height: 100,
                                              alignment: Alignment.center,
                                              padding: const EdgeInsets.symmetric(horizontal: 24),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  const SizedBox(
                                                    width: 28,
                                                    height: 28,
                                                    child: CircularProgressIndicator(strokeWidth: 2),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  const Text(
                                                    'Signing in...',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w500,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );

                                    ref
                                        .read(authProvider.notifier)
                                        .clearError();
                                    await Future<void>.delayed(Duration.zero);
                                    final success = await ref
                                        .read(authProvider.notifier)
                                        .signInWithApple();

                                    if (!mounted) return;

                                    if (success) {
                                      // Close loading dialog
                                      Navigator.of(context, rootNavigator: true).pop();
                                      // Show success dialog - auto close and navigate after 1 second
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (dialogContext) => AlertDialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 36,
                                                height: 36,
                                                decoration: const BoxDecoration(
                                                  color: Color(0xFF4CAF50),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.check,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                              const SizedBox(height: 10),
                                              const Text(
                                                'Login Successful!',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                      // Auto close and navigate after 1 second
                                      Future.delayed(const Duration(seconds: 1), () {
                                        if (!mounted) return;

                                        // 关闭成功弹窗
                                        Navigator.of(context).pop();

                                        // 触发 loginReturnProvider，刷新 ShortVideoPage 的视频列表
                                        if (widget.redirect != null && widget.redirect!.contains('/short-video')) {
                                          Future.delayed(Duration.zero, () {
                                            ref.read(loginReturnProvider.notifier).state++;
                                            debugPrint('[LoginPage] Apple triggered loginReturnProvider');
                                          });
                                        }

                                        // 获取 root navigator 并连续 pop 两个页面回到 ShortVideoPage
                                        final rootNav = Navigator.of(context, rootNavigator: true);

                                        Future.delayed(const Duration(milliseconds: 100), () {
                                          debugPrint('[LoginPage] Apple step 1: pop LoginPage');
                                          rootNav.pop();
                                        }).then((_) {
                                          return Future.delayed(Duration.zero, () {
                                            debugPrint('[LoginPage] Apple step 2: pop LoginEmailPage if exists');
                                            if (Navigator.canPop(context)) {
                                              rootNav.pop();
                                            }
                                          });
                                        });
                                      });
                                      return;
                                    }

                                    // Close loading dialog
                                    Navigator.of(context, rootNavigator: true).pop();

                                    // Show error dialog - auto close after 2 seconds
                                    final errorMsg = ref.read(authProvider).errorMessage ?? 'Login failed. Please try again.';
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (dialogContext) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 36,
                                              height: 36,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFFE53935),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.close,
                                                color: Colors.white,
                                                size: 20,
                                              ),
                                            ),
                                            const SizedBox(height: 10),
                                            Text(
                                              errorMsg,
                                              textAlign: TextAlign.center,
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    // Auto close after 2 seconds
                                    Future.delayed(const Duration(seconds: 2), () {
                                      if (mounted && Navigator.canPop(context)) {
                                        Navigator.of(context, rootNavigator: true).pop();
                                      }
                                    });
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
                    onTap: () {
                      final registerBackTarget = Uri.encodeComponent('/auth/login?back=${Uri.encodeComponent(widget.backTarget)}');
                      context.push('/auth/register/email?back=$registerBackTarget');
                    },
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
      enabled: !isLoading,
      child: GestureDetector(
        onTap: isLoading ? null : onTap,
        child: Container(
          width: double.infinity,
          height: 50,
          decoration: BoxDecoration(
            color: isLoading ? Colors.grey.shade200 : Colors.white,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: const Color(0xFFDADCE0)),
            boxShadow: isLoading
                ? null
                : const [
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
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isLoading ? const Color(0xFFAAAAAA) : const Color(0xFF1F1F1F),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.1,
                    ),
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

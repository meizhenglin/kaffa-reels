import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/router/router_config.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../core/network/api_service.dart';
import '../../../core/utils/app_restart.dart';
import '../../auth/providers/auth_provider.dart';

class DeleteAccountPage extends ConsumerStatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  ConsumerState<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends ConsumerState<DeleteAccountPage> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  RtlBackButton(
                    onPressed: () => context.pop(),
                    color: Colors.white,
                  ),
                  const Expanded(
                    child: Center(
                      child: Text(
                        'Delete account',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const Opacity(
                    opacity: 0,
                    child: RtlBackButton(
                      onPressed: null,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'Are you sure you want to delete your account?',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'After deletion, all your data will be permanently erased and cannot be recovered.',
                      style: TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 40),
                    GestureDetector(
                      onTap: _isLoading ? null : _deleteAccount,
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B6B),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Delete',
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
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    setState(() => _isLoading = true);

    final messenger = ScaffoldMessenger.of(context);
    final response = await apiServiceProvider.cancelAccount();

    if (!mounted) return;

    if (!response.isSuccess) {
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(response.error ?? 'Failed to delete account'),
          backgroundColor: const Color(0xFFFF6B6B),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      const SnackBar(
        content: Text('Account deleted successfully'),
        backgroundColor: Color(0xFF5D4391),
        duration: Duration(milliseconds: 1200),
      ),
    );

    await ref.read(authProvider.notifier).signOut();
    if (!mounted) return;

    setState(() => _isLoading = false);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    final rootNavigator = rootNavigatorKey.currentState;
    while (rootNavigator != null && rootNavigator.canPop()) {
      rootNavigator.pop();
    }

    context.go('/');
    await AppRestart.restart();
  }
}

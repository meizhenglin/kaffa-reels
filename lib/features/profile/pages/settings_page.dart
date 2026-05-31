import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import 'language_page.dart';
import 'message_settings_page.dart';
import 'recharge_agreement_page.dart';
import 'delete_account_page.dart';
import 'about_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Image.asset(
                      'assets/images/back_icon.png',
                      width: 20,
                      height: 20,
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        l10n?.settings ?? 'Settings',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // Change Language
                    _SettingsItem(
                      title: 'Change Language',
                      trailing: const Text(
                        'English',
                        style: TextStyle(
                          color: Color(0xFF999999),
                          fontSize: 15,
                        ),
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LanguagePage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // User Agreement
                    _SettingsItem(
                      title: 'User Agreement',
                      trailing: const _ArrowIcon(),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => AboutPage()),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // Privacy Policy
                    _SettingsItem(
                      title: 'Privacy Policy',
                      trailing: const _ArrowIcon(),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => AboutPage()),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // User Recharge Agreement
                    _SettingsItem(
                      title: 'User Recharge Agreement',
                      trailing: const _ArrowIcon(),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RechargeAgreementPage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // Message Settings
                    _SettingsItem(
                      title: 'Message Settings',
                      trailing: const _ArrowIcon(),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const MessageSettingsPage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // Version Number
                    _SettingsItem(
                      title: 'Version Number',
                      trailing: const Text(
                        '1.0.0',
                        style: TextStyle(
                          // color: Color(0xFF999999),
                          fontSize: 15,
                        ),
                      ),
                      onTap: () {},
                    ),

                    const SizedBox(height: 14),

                    // Delete account
                    _SettingsItem(
                      title: 'Delete account',
                      trailing: const _ArrowIcon(),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const DeleteAccountPage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    // Log out
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        width: double.infinity,
                        height: 50,
                        decoration: BoxDecoration(
                          color: const Color(0xFF464950),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            'Log out',
                            style: TextStyle(
                              color: Color(0xFFFFFFFF),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    // const Spacer(),

                    // Copyright
                    Text(
                      '© 2024 QahwaTV. All rights reserved.',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 11,
                      ),
                    ),

                    const SizedBox(height: 32),
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

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  final String title;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF464950),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child:               Text(
                title,
                style: const TextStyle(
                  color: Color(0xFFFFFFFF),
                  fontSize: 15,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _ArrowIcon extends StatelessWidget {
  const _ArrowIcon();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.chevron_right, color: Color(0xFF999999), size: 22);
  }
}

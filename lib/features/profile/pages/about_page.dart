import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;

    return GradientScaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // 返回按钮
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // App Logo and Name
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2025),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF5D4391), Color(0xFF1F2025)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(
                        Icons.play_circle_fill,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Qahwa TV',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Version 1.0.0',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.appDescription,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Links Section
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2025),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    _buildLinkItem(
                      icon: Icons.privacy_tip,
                      title: l10n.privacyPolicy,
                      onTap: () => _launchUrl('https://arabicdrama.com/privacy'),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    _buildLinkItem(
                      icon: Icons.description,
                      title: l10n.termsOfService,
                      onTap: () => _launchUrl('https://arabicdrama.com/terms'),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    _buildLinkItem(
                      icon: Icons.email,
                      title: l10n.contactUs,
                      onTap: () => _launchUrl('mailto:support@arabicdrama.com'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Social Media Section
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2025),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      l10n.followUs,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildSocialButton(
                          icon: Icons.facebook,
                          color: const Color(0xFF1877F2),
                          onTap: () => _launchUrl('https://facebook.com/arabicdrama'),
                        ),
                        _buildSocialButton(
                          icon: Icons.camera_alt,
                          color: const Color(0xFFE4405F),
                          onTap: () => _launchUrl('https://instagram.com/arabicdrama'),
                        ),
                        _buildSocialButton(
                          icon: Icons.link,
                          color: const Color(0xFF25D366),
                          onTap: () => _launchUrl('https://wa.me/966XXXXXXXX'),
                        ),
                        _buildSocialButton(
                          icon: Icons.video_library,
                          color: const Color(0xFFFF0000),
                          onTap: () => _launchUrl('https://youtube.com/@arabicdrama'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '© 2026 Qahwa TV. All rights reserved.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLinkItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
      onTap: onTap,
    );
  }

  Widget _buildSocialButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 24),
      ),
    );
  }
}

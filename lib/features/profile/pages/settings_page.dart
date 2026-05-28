import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';

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
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => context.pop(),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n?.settings ?? 'Settings',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // General Section
                    _buildSectionTitle('General'),
                    const SizedBox(height: 8),
                    _buildSettingsCard([
                      _buildToggleItem(
                        icon: Icons.notifications,
                        title: l10n?.notifications ?? 'Notifications',
                        value: true,
                        onChanged: (v) {},
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      _buildNavigationItem(
                        icon: Icons.language,
                        title: l10n?.profile_language ?? 'Language',
                        subtitle: 'English',
                        onTap: () {},
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      _buildToggleItem(
                        icon: Icons.dark_mode,
                        title: l10n?.darkMode ?? 'Dark Mode',
                        value: true,
                        onChanged: (v) {},
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // Playback Section
                    _buildSectionTitle('Playback'),
                    const SizedBox(height: 8),
                    _buildSettingsCard([
                      _buildToggleItem(
                        icon: Icons.play_arrow,
                        title: 'Auto-play Next Episode',
                        value: true,
                        onChanged: (v) {},
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      _buildNavigationItem(
                        icon: Icons.speed,
                        title: 'Video Quality',
                        subtitle: 'Auto',
                        onTap: () {},
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      _buildToggleItem(
                        icon: Icons.subtitles,
                        title: 'Auto Subtitles',
                        value: false,
                        onChanged: (v) {},
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // Account Section
                    _buildSectionTitle('Account'),
                    const SizedBox(height: 8),
                    _buildSettingsCard([
                      _buildNavigationItem(
                        icon: Icons.lock,
                        title: 'Change Password',
                        onTap: () => context.push('/change-password'),
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      _buildNavigationItem(
                        icon: Icons.delete_forever,
                        title: 'Delete Account',
                        titleColor: Colors.redAccent,
                        onTap: () {},
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // About Section
                    _buildSectionTitle(l10n?.aboutUs ?? 'About'),
                    const SizedBox(height: 8),
                    _buildSettingsCard([
                      _buildNavigationItem(
                        icon: Icons.description,
                        title: l10n?.termsOfService ?? 'Terms of Service',
                        onTap: () => context.push('/about'),
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      _buildNavigationItem(
                        icon: Icons.privacy_tip,
                        title: l10n?.privacyPolicy ?? 'Privacy Policy',
                        onTap: () => context.push('/about'),
                      ),
                      const Divider(height: 1, color: Colors.white12),
                      _buildNavigationItem(
                        icon: Icons.info,
                        title: 'App Version',
                        subtitle: '1.0.0',
                        onTap: () {},
                      ),
                    ]),

                    const SizedBox(height: 32),

                    // Logout
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {},
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                          foregroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          l10n?.logout ?? 'Log out',
                          style: const TextStyle(fontWeight: FontWeight.bold),
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

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildSettingsCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2025),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildToggleItem({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 22),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: const Color(0xFF7B2FFF),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70, size: 22),
      title: Text(
        title,
        style: TextStyle(color: titleColor ?? Colors.white, fontSize: 15),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            )
          : null,
      trailing: Icon(Icons.chevron_right, color: Colors.grey[600], size: 22),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    );
  }
}

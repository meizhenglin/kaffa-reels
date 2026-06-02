import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              const SizedBox(height: 24),
              _buildUserSection(context),
              const SizedBox(height: 20),
              _buildVipBanner(context),
              const SizedBox(height: 24),
              _buildFunctionIcons(context),
              const SizedBox(height: 24),
              _buildSettingsList(context),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserSection(BuildContext context) {
    return Row(
      children: [
        // 头像
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.person, size: 40, color: Colors.white54),
        ),
        const SizedBox(width: 16),
        // 用户信息
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Guest63739',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Login to unlock more features',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        // 登录按钮
        GestureDetector(
          onTap: () => context.push('/auth/login?redirect=/profile'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF9843FF),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Text(
              'Log in',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVipBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFB800), Color(0xFFFF8C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'VIP Member',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Unlock all series with one tap',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => context.go('/membership'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(25),
              ),
              child: const Text(
                'Activate',
                style: TextStyle(
                  color: Color(0xFFFF8C00),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFunctionIcons(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildIconButton(
          context,
          icon: Icons.play_circle_outline,
          label: 'Watching History',
          color: const Color(0xFFFFD700),
          onTap: () => context.push('/history'),
        ),
        _buildIconButton(
          context,
          icon: Icons.star_outline,
          label: 'Favourites',
          color: const Color(0xFF9843FF),
          onTap: () => context.push('/favorites'),
        ),
        _buildIconButton(
          context,
          icon: Icons.article_outlined,
          label: 'Complaint',
          color: const Color(0xFF64B5F6),
          onTap: () => context.push('/complaint'),
        ),
      ],
    );
  }

  Widget _buildIconButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsList(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2025),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildSettingsItem(
            icon: Icons.language,
            title: l10n.language,
            trailing: const Text(
              'العربية / English',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            onTap: () {},
          ),
          const Divider(height: 1, color: Colors.white12),
          _buildSettingsItem(
            icon: Icons.settings,
            title: l10n.settings,
            onTap: () {},
          ),
          const Divider(height: 1, color: Colors.white12),
          _buildSettingsItem(
            icon: Icons.info_outline,
            title: l10n.aboutUs,
            onTap: () => context.push('/about'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white70),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.white38),
    );
  }
}

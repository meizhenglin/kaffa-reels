import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/recommend/utils/drama_navigation.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/sign_provider.dart';
import '../models/sign_model.dart';

/// Sign-in widget for profile page
class SignInWidget extends ConsumerStatefulWidget {
  const SignInWidget({super.key});

  @override
  ConsumerState<SignInWidget> createState() => _SignInWidgetState();
}

class _SignInWidgetState extends ConsumerState<SignInWidget> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(signStateProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signState = ref.watch(signStateProvider);
    final config = signState.config;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD700).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.calendar_today,
                  color: Color(0xFFFFD700),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.dailyCheckIn,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (config?.continueDay ?? 0) > 0
                          ? l10n.consecutiveDays(config?.continueDay ?? 0)
                          : l10n.signInDailyHint,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // Sign button or status
              if (signState.isLoading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFFFD700),
                  ),
                )
              else if ((config?.isTodaySigned ?? false))
                _buildSignedBadge(l10n)
              else
                _buildSignButton(),
            ],
          ),

          // Rewards preview
          if (config != null && config.rewards.isNotEmpty) ...[
            const SizedBox(height: 16),
            _buildRewardsPreview(config, l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildSignedBadge(AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.green.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withOpacity(0.5)),
      ),
      child: Center(
        child: Text(
          l10n.signed,
          style: const TextStyle(
            color: Colors.green,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildSignButton() {
    return GestureDetector(
      onTap: _handleSign,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
          ),
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        child: const Text(
          'Sign In',
          style: TextStyle(
            color: Color(0xFF1A1A1A),
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildRewardsPreview(SignConfig config, AppLocalizations l10n) {
    final currentDay = (config.continueDay) + 1;
    final displayRewards = config.rewards.take(7).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.weeklyRewards,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(displayRewards.length, (index) {
            final reward = displayRewards[index];
            final isCurrentDay = (index + 1) == currentDay;
            final isSigned = (index + 1) < currentDay;

            return Expanded(
              child: Container(
                margin: EdgeInsets.only(right: index < displayRewards.length - 1 ? 6 : 0),
                child: _RewardDayItem(
                  day: index + 1,
                  coins: reward.coins,
                  isCurrentDay: isCurrentDay,
                  isSigned: isSigned,
                  onTap: () => _showRewardDialog(context, reward),
                  l10n: l10n,
                ),
              ),
            );
          }),
        ),
        if (config.rewards.length > 7) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _showAllRewardsDialog(context, config),
            child: Text(
              l10n.viewAllRewards,
              style: const TextStyle(
                color: Color(0xFFFFD700),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _handleSign() async {
    final l10n = AppLocalizations.of(context);
    final authState = ref.read(authProvider);
    
    // 游客不能签到（签到会获得金币）
    if (!authState.isAuthenticated || (authState.user?.isTourist ?? true)) {
      await openMembershipPage(context, ref);
      return;
    }
    
    final signState = ref.read(signStateProvider);
    final config = signState.config;
    final todayReward = config?.rewards.isNotEmpty == true
        ? config!.rewards[config.isTodaySigned ? config.continueDay : config.continueDay]
        : null;
    
    final success = await ref.read(signStateProvider.notifier).sign();
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.signInSuccessful(todayReward?.coins ?? 0)),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showRewardDialog(BuildContext context, SignDayReward reward) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(
          l10n.day(reward.day),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          l10n.getReward(reward.coins),
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }

  void _showAllRewardsDialog(BuildContext context, SignConfig config) {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2A2A2A),
        title: Text(
          l10n.allRewards,
          style: const TextStyle(color: Colors.white),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: config.rewards.length,
            itemBuilder: (context, index) {
              final reward = config.rewards[index];
              return ListTile(
                title: Text(
                  l10n.day(reward.day),
                  style: const TextStyle(color: Colors.white),
                ),
                trailing: Text(
                  '${reward.coins} K',
                  style: const TextStyle(color: Color(0xFFFFD700)),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
        ],
      ),
    );
  }
}

class _RewardDayItem extends StatelessWidget {
  final int day;
  final int coins;
  final bool isCurrentDay;
  final bool isSigned;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  const _RewardDayItem({
    required this.day,
    required this.coins,
    required this.isCurrentDay,
    required this.isSigned,
    required this.onTap,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color borderColor;
    Color textColor;

    if (isSigned) {
      bgColor = Colors.green.withOpacity(0.2);
      borderColor = Colors.green.withOpacity(0.5);
      textColor = Colors.green;
    } else if (isCurrentDay) {
      bgColor = const Color(0xFFFFD700).withOpacity(0.2);
      borderColor = const Color(0xFFFFD700);
      textColor = const Color(0xFFFFD700);
    } else {
      bgColor = const Color(0xFF2A2A2A);
      borderColor = Colors.white24;
      textColor = Colors.white54;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isCurrentDay ? 2 : 1),
        ),
        child: Column(
          children: [
            Text(
              l10n.day(day),
              style: TextStyle(
                color: textColor,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$coins',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  'K',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
            if (isSigned)
              const Icon(Icons.check_circle, color: Colors.green, size: 12)
            else if (isCurrentDay)
              const Icon(Icons.star, color: Color(0xFFFFD700), size: 12),
          ],
        ),
      ),
    );
  }
}

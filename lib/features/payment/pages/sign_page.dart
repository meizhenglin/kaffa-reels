import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../features/home/models/home_card_layout.dart';
import '../../../features/recommend/utils/drama_navigation.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/sign_provider.dart';
import '../models/sign_model.dart';

/// Sign-in page
/// Shows sign-in config, user sign-in info, and sign-in button
class SignPage extends ConsumerStatefulWidget {
  const SignPage({super.key});

  @override
  ConsumerState<SignPage> createState() => _SignPageState();
}

class _SignPageState extends ConsumerState<SignPage> {
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
    final isTodaySigned = config?.isTodaySigned ?? false;

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: HomeCardLayout.sectionHorizontalPadding(context),
                vertical: HomeCardLayout.scaled(context, 8),
              ),
              child: Row(
                children: [
                  RtlBackButton(
                    color: Colors.white,
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Text(
                      l10n.dailyCheckIn,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: HomeCardLayout.scaled(context, 17),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: HomeCardLayout.scaled(context, 24)),
                ],
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Column(
                  children: [
                    // User status card
                    _buildStatusCard(config, isTodaySigned, l10n),
                    const SizedBox(height: 20),
                    
                    // Sign-in button
                    _buildActionButton(isTodaySigned),
                    
                    const SizedBox(height: 24),
                    
                    // Rewards calendar
                    if (config != null)
                      _buildRewardsCalendar(config, l10n),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(SignConfig? config, bool isTodaySigned, AppLocalizations l10n) {
    final continueDay = config?.continueDay ?? 0;
    final todayReward = _getTodayReward(config);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF5D4391),
            Color(0xFF3A266A),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isTodaySigned ? Icons.check_circle : Icons.calendar_today,
                color: Colors.white,
                size: 32,
              ),
              const SizedBox(width: 12),
              Text(
                isTodaySigned ? l10n.signedToday : l10n.notSignedYet,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _StatusItem(
                  icon: Icons.local_fire_department,
                  label: l10n.consecutiveDaysLabel,
                  value: '$continueDay',
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white30,
              ),
              Expanded(
                child: _StatusItem(
                  icon: Icons.monetization_on,
                  label: l10n.todaysReward,
                  value: '$todayReward K',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _getTodayReward(SignConfig? config) {
    if (config == null || config.rewards.isEmpty) return 0;
    // Today is day (continueDay + 1) or day 1 if not signed
    final dayIndex = config.isTodaySigned ? config.continueDay : config.continueDay;
    if (dayIndex <= 0 || dayIndex > config.rewards.length) return 0;
    return config.rewards[dayIndex - 1].coins;
  }

  Widget _buildActionButton(bool isTodaySigned) {
    final button = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        gradient: isTodaySigned
            ? LinearGradient(
                colors: [Colors.green.shade400, Colors.green.shade600],
              )
            : const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
              ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isTodaySigned ? Icons.check_circle : Icons.card_giftcard,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              isTodaySigned ? 'Signed In Today' : 'Sign In Now',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );

    if (!isTodaySigned) {
      return GestureDetector(onTap: _handleSign, child: button);
    }

    return button;
  }

  Widget _buildRewardsCalendar(SignConfig config, AppLocalizations l10n) {
    final rewards = config.rewards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.weeklyRewards,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2D2D3A),
                Color(0xFF1A1A24),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.1),
            ),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemCount: rewards.length > 0 ? rewards.length : 7,
            itemBuilder: (context, index) {
              if (index >= rewards.length) {
                return _RewardItemWidget(
                  dayLabel: l10n.day(index + 1),
                  coins: 0,
                  isSigned: false,
                  isCurrent: false,
                  isEmpty: true,
                );
              }

              final reward = rewards[index];
              final dayIndex = index + 1;
              final isSigned = config.isDaySigned(reward.signGoodsId);
              final isCurrent = dayIndex == config.continueDay + 1 && !config.isTodaySigned;

              return _RewardItemWidget(
                dayLabel: l10n.day(dayIndex),
                coins: reward.coins,
                isSigned: isSigned,
                isCurrent: isCurrent,
                isEmpty: false,
              );
            },
          ),
        ),
        const SizedBox(height: 16),
        // Rules
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.rules,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              _buildRuleItem('1. ${l10n.signRule1}'),
              _buildRuleItem('2. ${l10n.signRule2}'),
              _buildRuleItem('3. ${l10n.signRule3}'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRuleItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
        ),
      ),
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
    
    final success = await ref.read(signStateProvider.notifier).sign();
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.signInSuccessful(0)),
          backgroundColor: Colors.green,
        ),
      );
    }
  }
}

class _StatusItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatusItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _RewardItemWidget extends StatelessWidget {
  final String dayLabel;
  final int coins;
  final bool isSigned;
  final bool isCurrent;
  final bool isEmpty;

  const _RewardItemWidget({
    required this.dayLabel,
    required this.coins,
    required this.isSigned,
    required this.isCurrent,
    required this.isEmpty,
  });

  @override
  Widget build(BuildContext context) {
    // Colors based on state
    final Color bgColor;
    final Color borderColor;
    final Color textColor;
    final Color iconColor;
    final IconData icon;

    if (isEmpty) {
      bgColor = Colors.white.withValues(alpha: 0.05);
      borderColor = Colors.white.withValues(alpha: 0.1);
      textColor = Colors.white30;
      iconColor = Colors.white30;
      icon = Icons.remove;
    } else if (isSigned) {
      bgColor = const Color(0xFF2E7D32).withValues(alpha: 0.3);
      borderColor = const Color(0xFF4CAF50);
      textColor = const Color(0xFF4CAF50);
      iconColor = const Color(0xFF4CAF50);
      icon = Icons.check_circle;
    } else if (isCurrent) {
      bgColor = const Color(0xFFFF8F00).withValues(alpha: 0.25);
      borderColor = const Color(0xFFFFB300);
      textColor = const Color(0xFFFFD54F);
      iconColor = const Color(0xFFFFD54F);
      icon = Icons.star;
    } else {
      bgColor = const Color(0xFF3A3A4A);
      borderColor = Colors.white.withValues(alpha: 0.2);
      textColor = Colors.white54;
      iconColor = Colors.white38;
      icon = Icons.lock_outline;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bgColor,
            bgColor.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: 1.5,
        ),
        boxShadow: isCurrent
            ? [
                BoxShadow(
                  color: const Color(0xFFFFD700).withValues(alpha: 0.3),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          // Day label at top
          Positioned(
            top: 3,
            left: 0,
            right: 0,
            child: Text(
              dayLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor.withValues(alpha: 0.7),
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // Center content
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: iconColor, size: 24),
                  const SizedBox(height: 8),
                  if (!isEmpty) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '$coins',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            height: 1,
                          ),
                        ),
                        Text(
                          'K',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.7),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          // Glow effect for current day
          if (isCurrent)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD700),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFFD700).withValues(alpha: 0.8),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

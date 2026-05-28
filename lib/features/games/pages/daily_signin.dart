import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../providers/games_provider.dart';

class DailySigninPage extends ConsumerStatefulWidget {
  const DailySigninPage({super.key});

  @override
  ConsumerState<DailySigninPage> createState() => _DailySigninPageState();
}

class _DailySigninPageState extends ConsumerState<DailySigninPage> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      setState(() => _isLoading = false);
    });
  }

  Future<void> _signIn() async {
    final notifier = ref.read(gameScoresProvider.notifier);
    final scores = ref.read(gameScoresProvider);

    await notifier.signIn();

    if (!mounted) return;

    // Show reward dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.card_giftcard, color: Colors.amber),
            const SizedBox(width: 8),
            const Text('签到成功!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.stars,
              size: 64,
              color: Colors.amber,
            ),
            const SizedBox(height: 16),
            Text(
              '+10 积分',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 8),
            if (scores.signInStreak + 1 >= 7)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withAlpha(51),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  children: [
                    Text(
                      '🎉 连续签到奖励!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text('连续7天签到可获得VIP一天'),
                  ],
                ),
              ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final scores = ref.watch(gameScoresProvider);
    final today = DateTime.now().weekday - 1; // 0 = Monday
    final lastSignInDate = scores.lastSignInDate.isNotEmpty
        ? DateTime.tryParse(scores.lastSignInDate)
        : null;
    final hasSignedToday = lastSignInDate != null &&
        lastSignInDate.year == DateTime.now().year &&
        lastSignInDate.month == DateTime.now().month &&
        lastSignInDate.day == DateTime.now().day;

    return GradientScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 返回按钮
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    '每日签到',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // Streak card
              Card(
                color: const Color(0xFF1F2025),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.local_fire_department,
                            color: Colors.orange,
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '连续签到 ${scores.signInStreak} 天',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                      if (scores.signInStreak >= 7)
                        Container(
                          margin: const EdgeInsets.only(top: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Colors.amber, Colors.orange],
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.emoji_events, color: Colors.white, size: 20),
                              SizedBox(width: 8),
                              Text(
                                '连续7天达成!',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Calendar
              Text(
                '签到日历',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 12),

              // Week day headers
              Row(
                children: ['一', '二', '三', '四', '五', '六', '日']
                    .map((day) => Expanded(
                          child: Center(
                            child: Text(
                              day,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: day == '六' || day == '日'
                                        ? Theme.of(context).colorScheme.error
                                        : null,
                                  ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 8),

              // Days
              Row(
                children: List.generate(7, (index) {
                  final dayNumber = index + 1;
                  final isToday = index == today;
                  final isPast = index < today;
                  final isSigned = isPast || (isToday && hasSignedToday);
                  final isFuture = index > today;

                  return Expanded(
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSigned
                                ? Theme.of(context).colorScheme.primaryContainer
                                : isToday
                                    ? Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: isToday
                                ? Border.all(
                                    color: Theme.of(context).colorScheme.primary,
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '$dayNumber',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      fontWeight: isToday
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                              ),
                              if (isSigned)
                                const Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: Colors.green,
                                )
                              else if (index == 6)
                                const Icon(
                                  Icons.stars,
                                  size: 14,
                                  color: Colors.amber,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Rewards info
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.card_giftcard, color: Colors.amber),
                          const SizedBox(width: 8),
                          Text(
                            '签到奖励',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _RewardItem(
                        days: '每日签到',
                        reward: '+10 积分',
                      ),
                      _RewardItem(
                        days: '连续3天',
                        reward: '+30 积分',
                      ),
                      _RewardItem(
                        days: '连续7天',
                        reward: 'VIP 一天',
                        isSpecial: true,
                      ),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Sign in button
              FilledButton.icon(
                onPressed: hasSignedToday ? null : _signIn,
                icon: Icon(hasSignedToday ? Icons.check_circle : Icons.touch_app),
                label: Text(
                  hasSignedToday ? '今日已签到' : '立即签到',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RewardItem extends StatelessWidget {
  const _RewardItem({
    required this.days,
    required this.reward,
    this.isSpecial = false,
  });

  final String days;
  final String reward;
  final bool isSpecial;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: isSpecial
                  ? Colors.amber.withAlpha(51)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              days,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            reward,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSpecial ? Colors.amber[700] : null,
                ),
          ),
        ],
      ),
    );
  }
}

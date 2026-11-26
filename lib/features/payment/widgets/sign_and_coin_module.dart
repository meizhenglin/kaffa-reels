import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../providers/coin_record_provider.dart';
import '../providers/sign_provider.dart';
import '../models/sign_model.dart';

/// Combined Sign-in and K-coin widget for profile page
/// Displays in a horizontal row layout
/// Left: K-Coin, Right: Sign-in
class SignAndCoinModule extends ConsumerStatefulWidget {
  const SignAndCoinModule({super.key});

  @override
  ConsumerState<SignAndCoinModule> createState() => _SignAndCoinModuleState();
}

class _SignAndCoinModuleState extends ConsumerState<SignAndCoinModule> {
  @override
  void initState() {
    super.initState();
    // 注意：coinBalanceInfoProvider 的首次加载由 ProfileTab._loadUserInfo()
    // 统一触发，这里不再重复调用，避免 userPersonalCenter 接口被并发触发两次。
    // 如果将来需要单独使用 SignAndCoinModule（脱离 ProfileTab），再恢复：
    //   Future.microtask(() {
    //     ref.read(coinBalanceInfoProvider.notifier).load();
    //     ref.read(signStateProvider.notifier).load();
    //   });
    Future.microtask(() {
      ref.read(signStateProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // K-Coin Module (Left)
        const Expanded(child: _KCoinModule()),
        const SizedBox(width: 12),
        // Sign-in Module (Right)
        Expanded(child: _SignInModule(signState: ref.watch(signStateProvider))),
      ],
    );
  }
}

/// K-Coin Module - Same style as Sign-in (gradient purple background)
class _KCoinModule extends ConsumerWidget {
  const _KCoinModule();

  Future<void> _refreshBalanceAfterRecharge(WidgetRef ref) async {
    final balanceNotifier = ref.read(coinBalanceInfoProvider.notifier);
    var previousBalance = ref.read(coinBalanceInfoProvider).balance;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      await balanceNotifier.load(force: true);
      // 【提前收兵】余额一旦变化（充值已到账）就没必要继续轮询了——
      // 原来不管充值成功与否都固定打满 3 次 userPersonalCenter。
      final currentBalance = ref.read(coinBalanceInfoProvider).balance;
      if (currentBalance != previousBalance) return;
      previousBalance = currentBalance;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final coinBalance = ref.watch(coinBalanceInfoProvider);

    return GestureDetector(
      onTap: () async {
        await context.push('/coin-recharge');
        await _refreshBalanceAfterRecharge(ref);
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 130),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5D4391), Color(0xFF3A266A)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.monetization_on,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.kCoin,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white54,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Balance display
            Row(
              children: [
                const Icon(
                  Icons.account_balance_wallet,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '${coinBalance.balance}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              l10n.balance,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sign-in Module - Click to navigate to sign-in page
class _SignInModule extends ConsumerWidget {
  const _SignInModule({required this.signState});

  final SignState signState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final config = signState.config;
    final isTodaySigned = config?.isTodaySigned ?? false;
    final continueDay = config?.continueDay ?? 0;

    return GestureDetector(
      onTap: () => context.push('/sign'),
      child: Container(
        constraints: const BoxConstraints(minHeight: 130),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5D4391), Color(0xFF3A266A)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isTodaySigned ? Icons.check_circle : Icons.calendar_today,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.dailyCheckIn,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white54,
                  size: 18,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Status display - fixed height for consistent layout
            Container(
              width: double.infinity,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isTodaySigned ? l10n.signed : l10n.signInUpper,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF5D4391),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isTodaySigned && continueDay > 0) ...[
                      const SizedBox(height: 1),
                      Text(
                        l10n.consecutiveDays(continueDay),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF5D4391),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.tapToSign,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

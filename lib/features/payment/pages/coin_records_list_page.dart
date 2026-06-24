import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../l10n/app_localizations.dart';

/// K-coin records list page (similar to history/favorites page)
/// Shows three items: Recharge Records, Usage Records, Gift Records
class CoinRecordsListPage extends StatelessWidget {
  const CoinRecordsListPage({super.key});

  @override
  Widget build(BuildContext context) {
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
                  RtlBackButton(
                    onPressed: () => context.pop(),
                    color: Colors.white,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.kCoinRecords,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildRecordItem(
                    context,
                    title: l10n.rechargeRecords,
                    subtitle: l10n.rechargeHistory,
                    icon: Icons.add_circle_outline,
                    iconColor: const Color(0xFFFFD700),
                    onTap: () => context.push('/coin-records/recharge'),
                  ),
                  const SizedBox(height: 12),
                  _buildRecordItem(
                    context,
                    title: l10n.usageRecords,
                    subtitle: l10n.spendingHistory,
                    icon: Icons.receipt_long,
                    iconColor: Colors.red,
                    onTap: () => context.push('/coin-records/consume'),
                  ),
                  const SizedBox(height: 12),
                  _buildRecordItem(
                    context,
                    title: l10n.giftRecords,
                    subtitle: l10n.giftHistory,
                    icon: Icons.volunteer_activism,
                    iconColor: Colors.purple,
                    onTap: () => context.push('/coin-records/give'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Colors.white38,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

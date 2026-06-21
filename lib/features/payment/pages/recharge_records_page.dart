import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/app_empty_state.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../features/home/models/home_card_layout.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/coin_record_provider.dart';
import '../models/coin_record_model.dart';

/// Recharge records list page
class RechargeRecordsPage extends ConsumerStatefulWidget {
  const RechargeRecordsPage({super.key});

  @override
  ConsumerState<RechargeRecordsPage> createState() => _RechargeRecordsPageState();
}

class _RechargeRecordsPageState extends ConsumerState<RechargeRecordsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(rechargeRecordsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _buildRecordsPage(
      context,
      title: l10n.rechargeRecords,
      provider: rechargeRecordsProvider,
      emptyText: l10n.noRechargeRecords,
    );
  }

  Widget _buildRecordsPage(
    BuildContext context, {
    required String title,
    required StateNotifierProvider<CoinRecordsNotifier, CoinRecordListState> provider,
    required String emptyText,
  }) {
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
                      title,
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
              child: _buildRecordsList(provider, emptyText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordsList(
    StateNotifierProvider<CoinRecordsNotifier, CoinRecordListState> provider,
    String emptyText,
  ) {
    final state = ref.watch(provider);

    if (state.isLoading && state.records.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      );
    }

    if (state.records.isEmpty) {
      return AppEmptyState(message: emptyText);
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(provider.notifier).refresh(),
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1A1A1A),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.records.length + (state.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= state.records.length) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(
                  color: Color(0xFFFFD700),
                  strokeWidth: 2,
                ),
              ),
            );
          }

          final record = state.records[index];
          return _RecordItem(record: record);
        },
      ),
    );
  }
}

class _RecordItem extends StatelessWidget {
  final CoinRecord record;

  const _RecordItem({required this.record});

  @override
  Widget build(BuildContext context) {
    final isPositive = record.amount > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getIconBgColor().withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getIcon(),
              color: _getIconBgColor(),
              size: 24,
            ),
          ),

          const SizedBox(width: 14),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getTitle(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(record.createTime),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                if (record.description != null && record.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    record.description!,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Amount
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isPositive ? '+' : ''}${record.amount}',
                style: TextStyle(
                  color: isPositive ? Colors.green : Colors.red,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Bal: ${record.balance}',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getIconBgColor() {
    return const Color(0xFFFFD700);
  }

  IconData _getIcon() {
    return Icons.account_balance_wallet;
  }

  String _getTitle() {
    return 'K-Coin Recharge';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

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

/// Consume records list page
class ConsumeRecordsPage extends ConsumerStatefulWidget {
  const ConsumeRecordsPage({super.key});

  @override
  ConsumerState<ConsumeRecordsPage> createState() => _ConsumeRecordsPageState();
}

class _ConsumeRecordsPageState extends ConsumerState<ConsumeRecordsPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(consumeRecordsProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(consumeRecordsProvider);

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
                      l10n.usageRecords,
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
              child: _buildRecordsList(state, l10n),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordsList(CoinRecordListState consumeState, AppLocalizations l10n) {
    if (consumeState.isLoading && consumeState.records.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      );
    }

    if (consumeState.records.isEmpty) {
      return AppEmptyState(message: l10n.noUsageRecords);
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(consumeRecordsProvider.notifier).refresh(),
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1A1A1A),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: consumeState.records.length + (consumeState.hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= consumeState.records.length) {
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

          final record = consumeState.records[index];
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
              color: Colors.red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.shopping_cart,
              color: Colors.red,
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

  String _getTitle() {
    return 'K-Coin Used';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

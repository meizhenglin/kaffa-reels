import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/app_empty_state.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../features/home/models/home_card_layout.dart';
import '../../../l10n/app_localizations.dart';
import '../models/recharge_record_model.dart';
import '../providers/recharge_records_provider.dart';

/// 充值/消费记录列表页面（后端真实数据）
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
    final state = ref.watch(rechargeRecordsProvider);

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
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
                      l10n.rechargeRecords,
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
            Expanded(child: _buildBody(state, l10n)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(RechargeRecordListState state, AppLocalizations l10n) {
    if (state.isLoading && state.records.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      );
    }
    if (state.records.isEmpty) {
      return AppEmptyState(message: l10n.noRechargeRecords);
    }
    return RefreshIndicator(
      onRefresh: () => ref.read(rechargeRecordsProvider.notifier).refresh(),
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1A1A1A),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: state.records.length,
        itemBuilder: (context, index) {
          return _RechargeRecordItem(record: state.records[index]);
        },
      ),
    );
  }
}

class _RechargeRecordItem extends StatelessWidget {
  final RechargeRecord record;

  const _RechargeRecordItem({required this.record});

  @override
  Widget build(BuildContext context) {
    final isPaid = record.payStatus == 1;
    final l10n = AppLocalizations.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.account_balance_wallet,
              color: Color(0xFFFFD700),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.detail.isNotEmpty ? record.detail : l10n.recharge,
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
                const SizedBox(height: 2),
                Text(
                  'No. ${record.orderNo}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${record.payPrice.toStringAsFixed(2)}',
                style: TextStyle(
                  color: isPaid ? Colors.green : Colors.orange,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isPaid ? Colors.green : Colors.orange).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  record.payStatusStr.isNotEmpty
                      ? record.payStatusStr
                      : (isPaid ? 'Paid' : 'Unpaid'),
                  style: TextStyle(
                    color: isPaid ? Colors.green : Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../features/home/models/home_card_layout.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/coin_record_provider.dart';
import '../models/coin_record_model.dart';

/// K-coin records page (with tabs for recharge/consume/give)
class CoinRecordsPage extends ConsumerStatefulWidget {
  final String? initialTab;

  const CoinRecordsPage({super.key, this.initialTab});

  @override
  ConsumerState<CoinRecordsPage> createState() => _CoinRecordsPageState();
}

class _CoinRecordsPageState extends ConsumerState<CoinRecordsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    
    int initialIndex = 0;
    if (widget.initialTab == 'consume') {
      initialIndex = 1;
    } else if (widget.initialTab == 'give') {
      initialIndex = 2;
    }
    
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: initialIndex,
    );
    
    _tabController.addListener(_onTabChanged);
    
    // Load initial data
    Future.microtask(_loadInitialData);
  }

  void _loadInitialData() {
    ref.read(rechargeRecordsProvider.notifier).load();
    ref.read(consumeRecordsProvider.notifier).load();
    ref.read(giveRecordsProvider.notifier).load();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      switch (_tabController.index) {
        case 0:
          if (ref.read(rechargeRecordsProvider).records.isEmpty) {
            ref.read(rechargeRecordsProvider.notifier).load();
          }
          break;
        case 1:
          if (ref.read(consumeRecordsProvider).records.isEmpty) {
            ref.read(consumeRecordsProvider.notifier).load();
          }
          break;
        case 2:
          if (ref.read(giveRecordsProvider).records.isEmpty) {
            ref.read(giveRecordsProvider.notifier).load();
          }
          break;
      }
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
                      l10n.kCoinRecords,
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
            
            // Tab bar
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                labelColor: const Color(0xFF1A1A1A),
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                tabs: [
                  Tab(text: l10n.rechargeTab),
                  Tab(text: l10n.usageTab),
                  Tab(text: l10n.giftTab),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Tab content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _RecordListView(
                    provider: rechargeRecordsProvider,
                    emptyText: l10n.noRechargeRecords,
                    emptyIcon: Icons.add_circle_outline,
                  ),
                  _RecordListView(
                    provider: consumeRecordsProvider,
                    emptyText: l10n.noUsageRecords,
                    emptyIcon: Icons.receipt_long,
                  ),
                  _RecordListView(
                    provider: giveRecordsProvider,
                    emptyText: l10n.noGiftRecords,
                    emptyIcon: Icons.volunteer_activism,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordListView extends ConsumerStatefulWidget {
  final StateNotifierProvider<CoinRecordsNotifier, CoinRecordListState> provider;
  final String emptyText;
  final IconData emptyIcon;

  const _RecordListView({
    required this.provider,
    required this.emptyText,
    required this.emptyIcon,
  });

  @override
  ConsumerState<_RecordListView> createState() => _RecordListViewState();
}

class _RecordListViewState extends ConsumerState<_RecordListView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(widget.provider.notifier).loadMore();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(widget.provider);

    if (state.isLoading && state.records.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFFFD700)),
      );
    }

    if (state.records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              widget.emptyIcon,
              color: Colors.white30,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              widget.emptyText,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(widget.provider.notifier).refresh(),
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1A1A1A),
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16),
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

class _RecordItem extends ConsumerWidget {
  final CoinRecord record;

  const _RecordItem({required this.record});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isPositive = record.amount > 0;

    String _getTitle(AppLocalizations l10n) {
      switch (record.type) {
        case 'recharge':
          return l10n.kCoinRecharge;
        case 'consume':
          return l10n.kCoinUsed;
        case 'give':
          return l10n.kCoinGift;
        default:
          return l10n.kCoinTransaction;
      }
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _getIconBgColor().withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _getIcon(),
              color: _getIconBgColor(),
              size: 22,
            ),
          ),
          
          const SizedBox(width: 12),
          
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getTitle(l10n),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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
                '${l10n.balance}: ${record.balance}',
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
    switch (record.type) {
      case 'recharge':
        return const Color(0xFFFFD700);
      case 'consume':
        return Colors.red;
      case 'give':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getIcon() {
    switch (record.type) {
      case 'recharge':
        return Icons.account_balance_wallet;
      case 'consume':
        return Icons.shopping_cart;
      case 'give':
        return Icons.card_giftcard;
      default:
        return Icons.monetization_on;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

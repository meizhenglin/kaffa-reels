import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../../app/providers/app_providers.dart';
import '../models/coin_record_model.dart';

/// Record type enum
enum CoinRecordType {
  recharge,
  consume,
  give,
}

/// Current record type
final coinRecordTypeProvider = StateProvider<CoinRecordType>((ref) => CoinRecordType.recharge);

/// K-coin balance provider
final coinBalanceInfoProvider =
    StateNotifierProvider<CoinBalanceNotifier, CoinBalance>((ref) {
  final apiService = ApiService(
    dioClient: ref.read(dioClientProvider),
    storage: ref.read(storageServiceProvider),
  );
  return CoinBalanceNotifier(apiService);
});

class CoinBalanceNotifier extends StateNotifier<CoinBalance> {
  CoinBalanceNotifier(this._apiService) : super(const CoinBalance());

  final ApiService _apiService;

  /// Load coin balance from API
  Future<void> load() async {
    try {
      final resp = await _apiService.getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        state = CoinBalance.fromJson(data);
      }
    } catch (e) {
      // Handle error silently, keep current balance
    }
  }

  /// Update balance locally (after recharge or consume)
  void updateBalance(int newBalance) {
    state = CoinBalance(
      balance: newBalance,
      rechargeAmount: state.rechargeAmount,
      consumeAmount: state.consumeAmount,
      giveAmount: state.giveAmount,
    );
  }

  /// Deduct coins locally
  void deductCoins(int amount) {
    state = CoinBalance(
      balance: (state.balance - amount).clamp(0, state.balance),
      rechargeAmount: state.rechargeAmount,
      consumeAmount: state.consumeAmount + amount,
      giveAmount: state.giveAmount,
    );
  }

  /// Add coins locally (for refund)
  void addCoins(int amount) {
    state = CoinBalance(
      balance: state.balance + amount,
      rechargeAmount: state.rechargeAmount,
      consumeAmount: state.consumeAmount,
      giveAmount: state.giveAmount,
    );
  }
}

/// Recharge records provider
final rechargeRecordsProvider =
    StateNotifierProvider<CoinRecordsNotifier, CoinRecordListState>((ref) {
  final apiService = ApiService(
    dioClient: ref.read(dioClientProvider),
    storage: ref.read(storageServiceProvider),
  );
  return CoinRecordsNotifier(apiService, CoinRecordType.recharge);
});

/// Consume records provider
final consumeRecordsProvider =
    StateNotifierProvider<CoinRecordsNotifier, CoinRecordListState>((ref) {
  final apiService = ApiService(
    dioClient: ref.read(dioClientProvider),
    storage: ref.read(storageServiceProvider),
  );
  return CoinRecordsNotifier(apiService, CoinRecordType.consume);
});

/// Give records provider
final giveRecordsProvider =
    StateNotifierProvider<CoinRecordsNotifier, CoinRecordListState>((ref) {
  final apiService = ApiService(
    dioClient: ref.read(dioClientProvider),
    storage: ref.read(storageServiceProvider),
  );
  return CoinRecordsNotifier(apiService, CoinRecordType.give);
});

class CoinRecordsNotifier extends StateNotifier<CoinRecordListState> {
  CoinRecordsNotifier(this._apiService, this._type) : super(const CoinRecordListState());

  final ApiService _apiService;
  final CoinRecordType _type;

  /// Load records (initial load or refresh)
  Future<void> load() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final resp = await _getRecords(page: 1);
      if (resp.isSuccess && resp.data != null) {
        final records = _parseRecords(resp.data);
        state = state.copyWith(
          isLoading: false,
          records: records,
          page: 1,
          hasMore: records.length >= 20,
        );
      } else {
        state = state.copyWith(
          isLoading: false,
          errorMessage: resp.error,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load records',
      );
    }
  }

  /// Load more records (pagination)
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore) return;

    state = state.copyWith(isLoading: true);

    try {
      final resp = await _getRecords(page: state.page + 1);
      if (resp.isSuccess && resp.data != null) {
        final newRecords = _parseRecords(resp.data);
        state = state.copyWith(
          isLoading: false,
          records: [...state.records, ...newRecords],
          page: state.page + 1,
          hasMore: newRecords.length >= 20,
        );
      } else {
        state = state.copyWith(isLoading: false);
      }
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// Refresh records
  Future<void> refresh() async {
    state = state.copyWith(records: [], page: 1, hasMore: true);
    await load();
  }

  Future<ApiResponse> _getRecords({int page = 1, int pageSize = 20}) async {
    switch (_type) {
      case CoinRecordType.recharge:
        return _apiService.getRechargeRecordList(page: page, pageSize: pageSize);
      case CoinRecordType.consume:
        return _apiService.getConsumeRecordList(page: page, pageSize: pageSize);
      case CoinRecordType.give:
        return _apiService.getGiveRecordList(page: page, pageSize: pageSize);
    }
  }

  List<CoinRecord> _parseRecords(dynamic data) {
    if (data == null) return [];

    List<dynamic> rawList = [];
    if (data is List) {
      rawList = data;
    } else if (data is Map) {
      rawList = (data['list'] ?? data['rows'] ?? data['data'] ?? data['records']) as List? ?? [];
    }

    return rawList
        .map((e) => CoinRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

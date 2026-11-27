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

  /// 正在进行中的请求。
  ///
  /// 并发调用共享同一个请求，而不是直接 return —— 原来的 `_isLoading`
  /// 早退会让第二个调用方 `await load()` 立刻返回却读到**旧余额**
  /// （解锁页轮询余额判断充值是否到账，依赖 await 之后状态已更新）。
  Future<void>? _inFlight;

  /// 上次成功拉取时间，用于 TTL 节流。
  ///
  /// 【为什么需要】余额接口复用 `/api/user/userPersonalCenter`，充值页一进来
  /// K币组件、余额组件、解锁弹窗懒加载会先后触发多次 load()，每次都实打实
  /// 打一次用户中心接口——后端日志里表现成「进入充值页频繁调 usercenter」。
  /// 10 秒内的重复调用直接复用上一次结果（余额这种数据 10 秒的陈旧度足够）；
  /// 支付成功后要立刻刷新的地方传 [force] = true 绕过节流。
  static const _minLoadInterval = Duration(seconds: 10);
  DateTime? _lastLoadedAt;

  /// Load coin balance from API
  ///
  /// [force] = true 时无视节流强制请求（支付到账后刷新余额等场景）。
  Future<void> load({bool force = false}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;

    // TTL 节流：刚拉过就不再打接口。
    final lastLoadedAt = _lastLoadedAt;
    if (!force &&
        lastLoadedAt != null &&
        DateTime.now().difference(lastLoadedAt) < _minLoadInterval) {
      return Future.value();
    }

    final future = _loadFromApi();
    _inFlight = future;
    return future.whenComplete(() {
      _inFlight = null;
    });
  }

  Future<void> _loadFromApi() async {
    try {
      final resp = await _apiService.getUserCenter();
      if (resp.isSuccess && resp.data != null) {
        final data = resp.data as Map<String, dynamic>;
        state = CoinBalance.fromJson(data);
        _lastLoadedAt = DateTime.now();
      }
    } catch (e) {
      // Handle error silently, keep current balance
    }
  }

  /// Update balance from raw API response data (avoids a second HTTP request)
  void updateFromData(Map<String, dynamic> data) {
    state = CoinBalance(
      balance: data['balance'] as int? ??
          data['userAmount'] as int? ??
          0,
      rechargeAmount: data['rechargeAmount'] as int? ??
          data['recharge_amount'] as int? ??
          0,
      consumeAmount: data['consumeAmount'] as int? ??
          data['consume_amount'] as int? ??
          0,
      giveAmount: data['giveAmount'] as int? ??
          data['give_amount'] as int? ??
          0,
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

  /// 【退出登录】清零余额并重置节流状态。
  ///
  /// 之前登出后 state 里可能残留上一个账号的余额（串号风险），
  /// 而且节流时间戳没重置 —— 重新登录后 15 秒内触发的刷新会被跳过，
  /// 个人中心的 K币 余额就停留在 0，直到下一次充值强制刷新才恢复。
  /// 登出时统一 reset，一次解决。
  void reset() {
    _inFlight = null;
    _lastLoadedAt = null;
    state = const CoinBalance();
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

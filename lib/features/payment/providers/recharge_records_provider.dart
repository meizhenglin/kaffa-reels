import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/network/api_service.dart';
import '../models/recharge_record_model.dart';

/// 充值/消费订单记录 provider
/// 后端返回结构: {code:0, msg:"SUCCESS", data:{records:[{orderNo,...}]}}
final rechargeRecordsProvider = StateNotifierProvider<RechargeRecordsNotifier,
    RechargeRecordListState>((ref) {
  final apiService = ApiService(
    dioClient: ref.read(dioClientProvider),
    storage: ref.read(storageServiceProvider),
  );
  return RechargeRecordsNotifier(apiService);
});

class RechargeRecordsNotifier extends StateNotifier<RechargeRecordListState> {
  RechargeRecordsNotifier(this._apiService)
      : super(const RechargeRecordListState());

  final ApiService _apiService;

  Future<void> load({int page = 1, int pageSize = 20}) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final resp = await _apiService.getRechargeRecordList(
        page: page,
        pageSize: pageSize,
      );
      final records = _parse(resp);
      state = state.copyWith(
        isLoading: false,
        records: records,
        page: page,
        hasMore: records.length >= pageSize,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to load records',
      );
    }
  }

  Future<void> refresh() async {
    state = state.copyWith(records: [], page: 1, hasMore: true);
    await load();
  }

  List<RechargeRecord> _parse(ApiResponse resp) {
    if (!resp.isSuccess) return [];
    final body = resp.data;
    if (body == null) return [];
    List<dynamic> raw = [];
    if (body is List) {
      raw = body;
    } else if (body is Map) {
      raw = (body['records'] ??
              body['list'] ??
              body['rows'] ??
              body['data'] ??
              [])
          as List? ??
          [];
    }
    return raw
        .whereType<Map>()
        .map((e) => RechargeRecord.fromJson(e.cast<String, dynamic>()))
        .toList();
  }
}

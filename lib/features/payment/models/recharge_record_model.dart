/// 充值/消费订单记录模型
/// 对应后端返回结构：
/// ```
/// {
///   orderNo: "20260902122152903814771",
///   createTime: "2026-09-01T23:21:52.000+00:00",
///   detail: "整剧解锁",
///   payStatus: 0,
///   payStatusStr: "Chưa thanh toán",
///   payPrice: 1.0
/// }
/// ```
class RechargeRecord {
  final String orderNo;
  final DateTime createTime;
  final String detail;
  final int payStatus;
  final String payStatusStr;
  final double payPrice;

  const RechargeRecord({
    required this.orderNo,
    required this.createTime,
    required this.detail,
    required this.payStatus,
    required this.payStatusStr,
    required this.payPrice,
  });

  factory RechargeRecord.fromJson(Map<String, dynamic> json) {
    final raw = json['createTime'];
    DateTime parsed;
    if (raw is String) {
      parsed = DateTime.tryParse(raw)?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0);
    } else if (raw is int) {
      parsed = DateTime.fromMillisecondsSinceEpoch(raw).toLocal();
    } else {
      parsed = DateTime.fromMillisecondsSinceEpoch(0);
    }

    return RechargeRecord(
      orderNo: json['orderNo']?.toString() ?? '',
      createTime: parsed,
      detail: json['detail']?.toString() ?? '',
      payStatus: json['payStatus'] as int? ?? 0,
      payStatusStr: json['payStatusStr']?.toString() ?? '',
      payPrice: (json['payPrice'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

class RechargeRecordListState {
  final List<RechargeRecord> records;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String? errorMessage;

  const RechargeRecordListState({
    this.records = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 1,
    this.errorMessage,
  });

  RechargeRecordListState copyWith({
    List<RechargeRecord>? records,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? errorMessage,
    bool clearError = false,
  }) {
    return RechargeRecordListState(
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

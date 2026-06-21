/// K-coin record models

/// Base coin record
class CoinRecord {
  final String id;
  final int amount; // Positive for recharge/give, negative for consume
  final int balance; // Balance after this transaction
  final String type; // 'recharge', 'consume', 'give'
  final DateTime createTime;
  final String? description;

  const CoinRecord({
    required this.id,
    required this.amount,
    required this.balance,
    required this.type,
    required this.createTime,
    this.description,
  });

  factory CoinRecord.fromJson(Map<String, dynamic> json) {
    DateTime createTime;
    final createTimeStr = json['createTime'] ?? json['create_time'] ?? json['createTimeStr'];
    if (createTimeStr is String) {
      createTime = DateTime.tryParse(createTimeStr) ?? DateTime.now();
    } else if (createTimeStr is int) {
      createTime = DateTime.fromMillisecondsSinceEpoch(createTimeStr);
    } else {
      createTime = DateTime.now();
    }

    return CoinRecord(
      id: json['id']?.toString() ?? '',
      amount: json['amount'] as int? ?? 0,
      balance: json['balance'] as int? ?? json['amountBalance'] as int? ?? json['userAmount'] as int? ?? 0,
      type: json['type']?.toString() ?? '',
      createTime: createTime,
      description: json['description'] as String? ?? json['remark'] as String?,
    );
  }
}

/// Coin record list state
class CoinRecordListState {
  final List<CoinRecord> records;
  final bool isLoading;
  final bool hasMore;
  final int page;
  final String? errorMessage;

  const CoinRecordListState({
    this.records = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.page = 1,
    this.errorMessage,
  });

  CoinRecordListState copyWith({
    List<CoinRecord>? records,
    bool? isLoading,
    bool? hasMore,
    int? page,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CoinRecordListState(
      records: records ?? this.records,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// K-coin balance info
class CoinBalance {
  final int balance;
  final int rechargeAmount;
  final int consumeAmount;
  final int giveAmount;

  const CoinBalance({
    this.balance = 0,
    this.rechargeAmount = 0,
    this.consumeAmount = 0,
    this.giveAmount = 0,
  });

  factory CoinBalance.fromJson(Map<String, dynamic> json) {
    return CoinBalance(
      balance: json['balance'] as int? ?? json['userAmount'] as int? ?? 0,
      rechargeAmount: json['rechargeAmount'] as int? ?? json['recharge_amount'] as int? ?? 0,
      consumeAmount: json['consumeAmount'] as int? ?? json['consume_amount'] as int? ?? 0,
      giveAmount: json['giveAmount'] as int? ?? json['give_amount'] as int? ?? 0,
    );
  }
}

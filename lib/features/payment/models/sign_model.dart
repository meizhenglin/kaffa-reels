/// Sign-in data models

List<int> _toIntList(List<dynamic> list) {
  return list.map((dynamic e) {
    if (e is int) return e;
    final parsed = int.tryParse('$e');
    return parsed ?? 0;
  }).toList();
}

/// Sign-in configuration (daily rewards)
class SignConfig {
  final List<SignDayReward> rewards;
  final bool isTodaySigned;
  final List<int> signedGoodsIds;

  const SignConfig({
    required this.rewards,
    this.isTodaySigned = false,
    this.signedGoodsIds = const [],
  });

  factory SignConfig.fromJson(Map<String, dynamic> json) {
    final sign = json['sign'] as Map<String, dynamic>? ?? {};
    final configList = json['config'] as List<dynamic>? ?? [];

    final signedRaw = sign['signInfo'];
    List<int> signed = const [];
    if (signedRaw is List) {
      signed = _toIntList(signedRaw);
    }

    return SignConfig(
      rewards: configList
          .map((e) => SignDayReward.fromJson(e as Map<String, dynamic>))
          .toList(),
      isTodaySigned: sign['isSign'] as bool? ?? false,
      signedGoodsIds: signed,
    );
  }

  bool isDaySigned(int goodsId) {
    return signedGoodsIds.contains(goodsId);
  }

  int get continueDay {
    int days = 0;
    for (int i = 0; i < rewards.length; i++) {
      final goodsId = rewards[i].signGoodsId;
      if (goodsId > 0 && signedGoodsIds.contains(goodsId)) {
        days++;
      } else {
        break;
      }
    }
    return days;
  }
}

class SignDayReward {
  final int day;
  final int signGoodsId;
  final int coins;

  const SignDayReward({
    required this.day,
    this.signGoodsId = 0,
    required this.coins,
  });

  factory SignDayReward.fromJson(Map<String, dynamic> json) {
    return SignDayReward(
      day: json['signInSort'] as int? ?? json['day'] as int? ?? 0,
      signGoodsId: json['signGoodsId'] as int? ?? json['goodsId'] as int? ?? 0,
      coins: json['giveGoodsNum'] as int? ?? json['coins'] as int? ?? 0,
    );
  }
}

class UserSignInfo {
  final bool todaySigned;
  final int continueDay;
  final List<int> signHistory;

  const UserSignInfo({
    this.todaySigned = false,
    this.continueDay = 0,
    this.signHistory = const [],
  });

  factory UserSignInfo.fromJson(Map<String, dynamic> json) {
    final isSign = json['isSign'] as bool? ?? false;
    final signInfoRaw = json['signInfo'];

    List<int> history = const [];
    bool signed = false;

    if (signInfoRaw is List) {
      history = _toIntList(signInfoRaw);
      signed = history.any((e) => e != 0);
    } else {
      signed = isSign;
    }

    return UserSignInfo(
      todaySigned: signed,
      continueDay: history.where((e) => e != 0).length,
      signHistory: history,
    );
  }

  static List<int> _toIntList(List<dynamic> list) {
    return list.map((dynamic e) {
      if (e is int) return e;
      final parsed = int.tryParse('$e');
      return parsed ?? 0;
    }).toList();
  }
}

class SignState {
  final bool isLoading;
  final String? errorMessage;
  final SignConfig? config;

  const SignState({
    this.isLoading = false,
    this.errorMessage,
    this.config,
  });

  SignState copyWith({
    bool? isLoading,
    String? errorMessage,
    SignConfig? config,
    bool clearError = false,
  }) {
    return SignState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      config: config ?? this.config,
    );
  }
}

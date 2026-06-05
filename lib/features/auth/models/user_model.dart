import 'package:equatable/equatable.dart';

enum MembershipType {
  regular,
  premium;

  static MembershipType fromString(String? value) {
    return MembershipType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => MembershipType.regular,
    );
  }
}

class UserModel extends Equatable {
  const UserModel({
    required this.id,
    this.userName,
    this.email,
    this.displayName,
    this.nickname,
    this.photoURL,
    this.avatar,
    this.createdAt,
    this.isEmailVerified = false,
    this.membershipType = MembershipType.regular,
    this.membershipExpiryDate,
    this.isGuest = false,
    this.passportType,
  });

  final String id;
  final String? userName;
  final String? email;
  final String? displayName;
  final String? nickname;
  final String? photoURL;
  final String? avatar;
  final DateTime? createdAt;
  final bool isEmailVerified;
  final MembershipType membershipType;
  final DateTime? membershipExpiryDate;
  final bool isGuest;
  final int? passportType;

  String? get userNickname => nickname ?? displayName;

  /// 游客判定以显式游客标记和后端登录类型为准，避免把游客 UUID 误判成正式账号
  bool get isTourist {
    if (isGuest) {
      return true;
    }

    final normalizedPassportType = passportType;
    if (normalizedPassportType != null) {
      return normalizedPassportType == 0;
    }

    return (email == null || email!.trim().isEmpty);
  }

  bool get isPremium =>
      membershipType == MembershipType.premium &&
      (membershipExpiryDate == null ||
          membershipExpiryDate!.isAfter(DateTime.now()));

  bool get isVip => isPremium;
  DateTime? get vipExpireDate => membershipExpiryDate;

  factory UserModel.fromFirebaseData(Map<String, dynamic> data, {
    MembershipType membershipType = MembershipType.regular,
    DateTime? membershipExpiryDate,
  }) {
    return UserModel(
      id: data['uid']?.toString() ?? '',
      email: data['email'] as String?,
      displayName: data['displayName'] as String?,
      photoURL: data['photoURL'] as String?,
      createdAt: data['createdAt'] is DateTime
          ? data['createdAt'] as DateTime
          : null,
      isEmailVerified: data['isEmailVerified'] as bool? ?? false,
      membershipType: membershipType,
      membershipExpiryDate: membershipExpiryDate,
      isGuest: false,
    );
  }

  factory UserModel.guest(String guestId) {
    return UserModel(
      id: guestId,
      displayName: 'Guest',
      createdAt: DateTime.now(),
      isGuest: true,
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final isVip = json['isVip'] as int? ?? 0;
    return UserModel(
      id: json['userId']?.toString() ?? json['id']?.toString() ?? '',
      userName: json['userName'] as String?,
      email: json['email'] as String?,
      displayName: json['nickName'] as String? ?? json['nickname'] as String?,
      nickname: json['nickName'] as String? ?? json['nickname'] as String?,
      photoURL: json['userAvatar'] as String? ?? json['avatar'] as String?,
      avatar: json['userAvatar'] as String? ?? json['avatar'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      isEmailVerified: json['isEmailVerified'] as bool? ?? false,
      membershipType:
          isVip == 1 ? MembershipType.premium : MembershipType.regular,
      membershipExpiryDate: json['vipEndTime'] != null
          ? DateTime.tryParse(json['vipEndTime'] as String)
          : null,
      isGuest: json['isGuest'] as bool? ?? false,
      passportType: json['passportType'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'userId': id,
        'userName': userName,
        'email': email,
        'nickName': nickname,
        'displayName': displayName,
        'photoURL': photoURL,
        'avatar': avatar,
        'createdAt': createdAt?.toIso8601String(),
        'isEmailVerified': isEmailVerified,
        'membershipType': membershipType.name,
        'vipEndTime': membershipExpiryDate?.toIso8601String(),
        'isVip': membershipType == MembershipType.premium ? 1 : 0,
        'isGuest': isGuest,
        'passportType': passportType,
      };

  UserModel copyWith({
    String? id,
    String? userName,
    String? email,
    String? displayName,
    String? nickname,
    String? photoURL,
    String? avatar,
    DateTime? createdAt,
    bool? isEmailVerified,
    MembershipType? membershipType,
    DateTime? membershipExpiryDate,
    bool? isGuest,
    int? passportType,
  }) {
    return UserModel(
      id: id ?? this.id,
      userName: userName ?? this.userName,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      nickname: nickname ?? this.nickname,
      photoURL: photoURL ?? this.photoURL,
      avatar: avatar ?? this.avatar,
      createdAt: createdAt ?? this.createdAt,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
      membershipType: membershipType ?? this.membershipType,
      membershipExpiryDate:
          membershipExpiryDate ?? this.membershipExpiryDate,
      isGuest: isGuest ?? this.isGuest,
      passportType: passportType ?? this.passportType,
    );
  }

  @override
  List<Object?> get props => [
        id,
        email,
        displayName,
        nickname,
        photoURL,
        avatar,
        createdAt,
        isEmailVerified,
        membershipType,
        membershipExpiryDate,
        isGuest,
        passportType,
      ];
}

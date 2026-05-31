import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  String? get userNickname => nickname ?? displayName;

  bool get isPremium =>
      membershipType == MembershipType.premium &&
      (membershipExpiryDate == null ||
          membershipExpiryDate!.isAfter(DateTime.now()));

  bool get isVip => isPremium;
  DateTime? get vipExpireDate => membershipExpiryDate;

  factory UserModel.fromFirebaseUser(
    User user, {
    MembershipType membershipType = MembershipType.regular,
    DateTime? membershipExpiryDate,
  }) {
    return UserModel(
      id: user.uid,
      email: user.email,
      displayName: user.displayName,
      photoURL: user.photoURL,
      createdAt: user.metadata.creationTime,
      isEmailVerified: user.emailVerified,
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
      ];
}

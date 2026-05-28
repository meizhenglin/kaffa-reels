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
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String?,
      displayName: json['displayName'] as String?,
      nickname: json['nickname'] as String?,
      photoURL: json['photoURL'] as String?,
      avatar: json['avatar'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String)
          : null,
      isEmailVerified: json['isEmailVerified'] as bool? ?? false,
      membershipType:
          MembershipType.fromString(json['membershipType'] as String?),
      membershipExpiryDate: json['membershipExpiryDate'] != null
          ? DateTime.tryParse(json['membershipExpiryDate'] as String)
          : null,
      isGuest: json['isGuest'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'displayName': displayName,
        'nickname': nickname,
        'photoURL': photoURL,
        'avatar': avatar,
        'createdAt': createdAt?.toIso8601String(),
        'isEmailVerified': isEmailVerified,
        'membershipType': membershipType.name,
        'membershipExpiryDate': membershipExpiryDate?.toIso8601String(),
        'isGuest': isGuest,
      };

  UserModel copyWith({
    String? id,
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

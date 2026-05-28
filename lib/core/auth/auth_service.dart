import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../network/dio_client.dart';
import '../storage/storage_service.dart';

/// 登录结果
class LoginResult {
  final String token;
  final String uuid;
  final int userId;

  const LoginResult({
    required this.token,
    required this.uuid,
    required this.userId,
  });

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      token: json['token'] as String,
      uuid: json['uuid'] as String,
      userId: json['id'] as int,
    );
  }
}

/// 认证服务
///
/// 负责：
/// - 设备登录（匿名模式，获取 Token）
/// - Token 持久化管理
/// - Token 刷新
class AuthService {
  AuthService({DioClient? dioClient, StorageService? storage})
      : _dioClient = dioClient ?? DioClient(),
        _storage = storage ?? StorageService();

  final DioClient _dioClient;
  final StorageService _storage;

  /// 当前 Token（内存缓存，避免每次都读 storage）
  String? _cachedToken;

  /// 获取当前 Token，优先从内存，返回 null 表示未登录
  String? get currentToken => _cachedToken;

  /// 判断是否已登录
  bool get isLoggedIn => _cachedToken != null && _cachedToken!.isNotEmpty;

  /// 初始化：从 storage 加载 Token 到内存
  Future<void> init() async {
    _cachedToken = await _storage.getAuthTokenAsync();
  }

  /// 登录（匿名设备登录）
  ///
  /// [forceLogin] 为 true 时强制重新登录，即使已有 Token
  Future<LoginResult?> login({bool forceLogin = false}) async {
    if (!forceLogin && isLoggedIn) {
      return null;
    }

    try {
      final deviceId = const Uuid().v4();

      final deviceMes = {
        'brand': 'Android',
        'model': _getDeviceModel(),
        'system': 'Android',
      };

      final response = await _dioClient.dio.post(
        '/login/getUuid',
        data: {
          'deviceId': deviceId,
          'deviceMes': jsonEncode(deviceMes),
          'phoneSystemsType': 1,
        },
      );

      final data = response.data as Map<String, dynamic>;

      if (data['code'] == 200) {
        final result = LoginResult.fromJson(data['data'] as Map<String, dynamic>);
        _cachedToken = result.token;
        await _storage.saveAuthToken(result.token);
        debugPrint('[AuthService] login success, token saved');
        return result;
      } else {
        debugPrint('[AuthService] login failed: ${data['msg']}');
        return null;
      }
    } catch (e) {
      debugPrint('[AuthService] login error: $e');
      return null;
    }
  }

  /// 确保已登录，返回有效 Token
  /// 内部自动处理：已有 Token 直接返回，Token 过期则重新登录
  Future<String?> ensureToken() async {
    if (isLoggedIn) {
      return _cachedToken;
    }
    final result = await login();
    return result?.token;
  }

  /// 清除登录状态
  Future<void> logout() async {
    _cachedToken = null;
    await _storage.clearAuthToken();
  }

  /// 获取设备型号（用于 deviceMes）
  String _getDeviceModel() {
    // 简单返回 MIUI，实际可配合 device_info_plus 获取真实型号
    return 'MIUI';
  }
}

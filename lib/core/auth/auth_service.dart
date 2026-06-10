import 'dart:ui' show PlatformDispatcher;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../network/api_service.dart';
import '../storage/storage_service.dart';
import '../constants/app_constants.dart';

/// 验证码校验结果
class CheckCodeResult {
  final bool success;
  final String? message;

  const CheckCodeResult({required this.success, this.message});
}

/// 注册结果
class RegisterResult {
  final bool success;
  final String? token;
  final String? uuid;
  final String? message;

  const RegisterResult({
    required this.success,
    this.token,
    this.uuid,
    this.message,
  });

  factory RegisterResult.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>?;
    return RegisterResult(
      success: json['code'] == 200,
      token: data?['token'] as String?,
      uuid: data?['uuid'] as String?,
      message: json['msg'] as String?,
    );
  }
}

/// 登录结果
class LoginResult {
  final String token;
  final String uuid;

  const LoginResult({required this.token, required this.uuid});
}

/// 认证服务
///
/// 负责：
/// - 设备登录（匿名模式，获取 Token）
/// - Token 持久化管理
///
/// 【小程序原版对应】
/// - login() 对应小程序的 guestLogin() / getUuid 接口
/// - checkEmailCode() 对应小程序的 checkEmailCode 接口
/// - sendEmailCode() 对应小程序的 sendEmailCode 接口
/// - register() 对应小程序的 register 接口
class AuthService {
  AuthService({ApiService? apiService, StorageService? storage})
      : _apiService = apiService ?? apiServiceProvider,
        _storage = storage ?? StorageService();

  final ApiService _apiService;
  final StorageService _storage;

  /// 读取本地保存的用户数据
  Future<Map<String, dynamic>?> getUserData() => _storage.getUserData();

  /// 确保当前存在可用的游客 token。
  ///
  /// 这里只检查后端业务 token（user_token）。
  /// auth_token 仅用于 Firebase / 第三方登录辅助，不参与游客身份判定。
  /// 若本地已经有 user_token，则返回 null，表示无需再次发起游客登录。
  Future<LoginResult?> ensureGuestLogin() async {
    try {
      // 直接查 Storage，不依赖内存缓存；游客/后端鉴权统一只看 user_token。
      final cachedToken = await _storage.getToken();
      if (cachedToken != null && cachedToken.isNotEmpty) {
        debugPrint('[AuthService] backend token already exists in storage, skip guest login');
        return null;
      }

      debugPrint('[AuthService] no token found, performing guest login...');
      final deviceId = await _getOrCreateDeviceId();
      debugPrint('[AuthService] deviceId=$deviceId, calling guestLogin...');

      await _saveDeviceLanguage();

      final response = await _apiService.guestLogin(deviceId: deviceId);

      if (response.isSuccess && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final token = data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          await _storage.saveToken(token);
          debugPrint('[AuthService] guest login success, token saved');
          return LoginResult(token: token, uuid: deviceId);
        }
      }
      debugPrint('[AuthService] guest login failed: ${response.error}');
      return null;
    } catch (e) {
      debugPrint('[AuthService] ensureGuestLogin error: $e');
      return null;
    }
  }

  /// 清除登录状态
  Future<void> logout() async {
    await _storage.clearAuthToken();
    await _storage.removeToken();
    await _storage.removeUserData();
    await _storage.remove(AppConstants.userCacheKey);
  }

  /// 校验邮箱验证码
  Future<CheckCodeResult> checkEmailCode({
    required String email,
    required String code,
  }) async {
    try {
      debugPrint('[AuthService] checkEmailCode email: $email, code: $code');
      final response = await _apiService.checkEmailCode(
        email: email,
        code: code,
      );

      if (response.isSuccess) {
        return const CheckCodeResult(success: true);
      } else {
        return CheckCodeResult(
          success: false,
          message: response.error ?? 'Verification failed',
        );
      }
    } catch (e) {
      debugPrint('[AuthService] checkEmailCode error: $e');
      return CheckCodeResult(success: false, message: e.toString());
    }
  }

  /// 发送邮箱验证码
  Future<CheckCodeResult> sendEmailCode({required String email}) async {
    try {
      debugPrint('[AuthService] sendEmailCode email: $email');
      final response = await _apiService.sendEmailCode(email: email);

      if (response.isSuccess) {
        return const CheckCodeResult(success: true);
      } else {
        return CheckCodeResult(
          success: false,
          message: response.error ?? 'Failed to send code',
        );
      }
    } catch (e) {
      debugPrint('[AuthService] sendEmailCode error: $e');
      return CheckCodeResult(success: false, message: e.toString());
    }
  }

  /// 注册账号
  Future<RegisterResult> register({
    required String email,
    required String passportPassword,
  }) async {
    try {
      final response = await _apiService.register(
        email: email,
        passportPassword: passportPassword,
      );

      debugPrint('[AuthService] register response: ${response.data}');
      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        return RegisterResult(
          success: false,
          message: response.error ?? 'Registration failed',
        );
      }

      final result = RegisterResult.fromJson({'code': 200, 'data': data});
      if (result.success && result.token != null) {
        await _storage.saveToken(result.token!);
        debugPrint('[AuthService] register success');
      }
      return result;
    } catch (e) {
      debugPrint('[AuthService] register error: $e');
      return RegisterResult(success: false, message: e.toString());
    }
  }

  /// 获取或创建持久化的硬件设备 ID
  Future<String> _getOrCreateDeviceId() async {
    final storedId = await _storage.getDeviceUuid();
    if (storedId != null && storedId.isNotEmpty) {
      return storedId;
    }

    String deviceId;
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? const Uuid().v4();
      } else {
        deviceId = const Uuid().v4();
      }
    } catch (e) {
      debugPrint('[AuthService] Failed to get hardware deviceId, fallback to UUID: $e');
      deviceId = const Uuid().v4();
    }

    await _storage.saveDeviceUuid(deviceId);
    return deviceId;
  }

  /// 获取设备语言并保存到 Storage，用于 X-Client header
  Future<void> _saveDeviceLanguage() async {
    final savedLang = _storage.getString(AppConstants.deviceLangKey)?.trim();
    final savedLocale = _storage.getString(AppConstants.localeKey)?.trim();

    if (savedLang == 'ar-SA' || savedLang == 'en-US') {
      debugPrint('[AuthService] preserve saved device language: $savedLang');
      return;
    }

    if (savedLocale == 'ar' || savedLocale == 'en') {
      final lang = savedLocale == 'ar' ? 'ar-SA' : 'en-US';
      await _storage.setString(AppConstants.deviceLangKey, lang);
      debugPrint('[AuthService] device language restored from app locale: $lang');
      return;
    }

    final locale = PlatformDispatcher.instance.locale;
    final lang = locale.languageCode.toLowerCase() == 'ar' ? 'ar-SA' : 'en-US';
    await _storage.setString(AppConstants.deviceLangKey, lang);
    debugPrint('[AuthService] device language initialized from system locale: $lang');
  }
}

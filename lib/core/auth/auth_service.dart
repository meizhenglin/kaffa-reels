import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show PlatformDispatcher;
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

/// 认证服务
///
/// 负责：
/// - 设备登录（匿名模式，获取 Token）
/// - Token 持久化管理
/// - Token 刷新
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

  /// 当前 Token（内存缓存）
  String? _cachedToken;

  String? get currentToken => _cachedToken;

  bool get isLoggedIn => _cachedToken != null && _cachedToken!.isNotEmpty;

  Future<void> init() async {
    _cachedToken = await _storage.getToken();
    // Google/Apple 登录存的是 auth_token，也要读进来
    final authToken = await _storage.getAuthTokenAsync();
    if (_cachedToken == null || _cachedToken!.isEmpty) {
      _cachedToken = authToken;
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
        deviceId = androidInfo.id; // 硬件 Android ID（如 1a2b3c4d5e6f7890）
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

  /// 登录成功后获取并保存用户信息
  Future<void> _fetchAndSaveUserInfo() async {
    try {
      final response = await _apiService.getUserCenter();
      if (response.isSuccess && response.data != null) {
        await _storage.saveUserData(response.data as Map<String, dynamic>);
        debugPrint('[AuthService] user info saved');
      } else {
        debugPrint('[AuthService] getUserCenter failed: ${response.error}');
      }
    } catch (e) {
      debugPrint('[AuthService] getUserCenter error: $e');
    }
  }

  /// 对外暴露：获取用户信息（在 Profile Tab 切换时调用）
  Future<void> fetchUserInfo() => _fetchAndSaveUserInfo();

  /// 读取本地保存的用户数据
  Future<Map<String, dynamic>?> getUserData() => _storage.getUserData();

  /// 登录（匿名设备登录）
  ///
  /// [forceLogin] 为 true 时强制重新登录，即使已有 Token
  Future<LoginResult?> login({bool forceLogin = false}) async {
    debugPrint('[AuthService] login() called, isLoggedIn=$isLoggedIn');
    if (!forceLogin && isLoggedIn) {
      debugPrint('[AuthService] skip login, already logged in');
      return null;
    }

    try {
      debugPrint('[AuthService] getting deviceId...');
      final deviceId = await _getOrCreateDeviceId();
      debugPrint('[AuthService] deviceId=$deviceId, calling guestLogin...');

      // 游客登录前：获取并保存设备语言到 Storage，用于 X-Client header
      await _saveDeviceLanguage();

      final response = await _apiService.guestLogin(deviceId: deviceId);

      if (response.isSuccess && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final token = data['token'] as String?;
        if (token != null && token.isNotEmpty) {
          _cachedToken = token;
          await _storage.saveToken(token);
          debugPrint('[AuthService] login success, token saved');
          return LoginResult(token: token, uuid: deviceId);
        }
      }
      debugPrint('[AuthService] login failed: ${response.error}');
      return null;
    } catch (e) {
      debugPrint('[AuthService] login error: $e');
      return null;
    }
  }

  /// 确保已登录，返回有效 Token
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
    await _storage.removeToken();
    await _storage.removeUserData();
    // 清除 SharedPreferences 中的用户缓存，防止 initAsGuest 恢复旧账号
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
        _cachedToken = result.token;
        await _storage.saveToken(result.token!);
        debugPrint('[AuthService] register success');
      }
      return result;
    } catch (e) {
      debugPrint('[AuthService] register error: $e');
      return RegisterResult(success: false, message: e.toString());
    }
  }

  /// 获取设备语言并保存到 Storage，用于 X-Client header
  Future<void> _saveDeviceLanguage() async {
    final locale = PlatformDispatcher.instance.locale;
    // 格式如 "zh-CN" / "en-US" / "ar-SA"
    String lang = '${locale.languageCode}-${locale.countryCode ?? ''}';
    if (lang == '-' || lang.isEmpty) {
      lang = 'en-US';
    }
    await _storage.setString(AppConstants.deviceLangKey, lang);
    debugPrint('[AuthService] device language saved: $lang');
  }
}

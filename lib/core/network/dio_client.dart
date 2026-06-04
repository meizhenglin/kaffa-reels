import 'dart:async';
import 'dart:io';
import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import '../constants/api_error_code.dart';
import '../constants/app_constants.dart';
import '../storage/storage_service.dart';

/// ============================================================================
/// HTTP 网络客户端配置
///
/// 【功能说明】
/// 基于 Dio 库封装的网络请求客户端，负责：
/// - 配置全局 HTTP 请求参数（超时、头部等）
/// - 添加请求/响应日志拦截器
/// - 管理认证令牌
/// - 自动注入 X-Client 平台标识头
///
/// 【自动 Guest 登录机制】
/// 两种场景触发 guest 登录：
/// 1. 发起请求时 token 为空 → 先 guest 登录，拿到 token 后再发请求
/// 2. 请求返回 code=23（token 过期） → guest 登录后重试该请求
///
/// guest 登录为同步阻塞调用，并发多个请求时只执行一次，登录完成后统一重试。
/// ============================================================================
class DioClient {
  DioClient({Dio? dio, Logger? logger, StorageService? storage})
      : _logger = logger ?? Logger(),
        _dio = dio ?? Dio(),
        _storage = storage ?? StorageService() {
    _dio
      ..options = BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout:
            const Duration(milliseconds: AppConstants.connectTimeout),
        receiveTimeout:
            const Duration(milliseconds: AppConstants.receiveTimeout),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      )
      ..httpClientAdapter = _buildHttpClientAdapter()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            // 每次请求动态构建 X-Client header（语言取自 Storage）
            options.headers['X-Client'] = _buildXClientHeader();

            final token = await _storage.getToken();
            if (token != null && token.isNotEmpty) {
              options.headers['token'] = token;
            } else {
              // token 为空：先完成 guest 登录，再继续发请求
              final newToken = await _ensureGuestLogin();
              if (newToken != null) {
                options.headers['token'] = newToken;
              }
            }
            final clientParams = _storage.getString(AppConstants.clientParamsKey) ?? '';
            if (clientParams.isNotEmpty) {
              options.headers['client_params'] = clientParams;
              options.headers['clientparams'] = clientParams;
            }

            if (kDebugMode) {
              _logger.d('');
              _logger.d('【REQUEST】${options.method} ${options.uri}');
              _logger.d('【HEADERS】');
              options.headers.forEach((key, value) {
                if (key.toLowerCase() == 'token') {
                  _logger.d('  $key: ****（已隐藏）');
                } else {
                  _logger.d('  $key: $value');
                }
              });
              final requestData = options.data;
              if (requestData is Map) {
                _logger.d('【BODY】$requestData');
              } else if (requestData is FormData) {
                _logger.d('【BODY】FormData(${requestData.fields.length} fields)');
              } else if (requestData != null) {
                _logger.d('【BODY】$requestData');
              }
              _logger.d('');
            }

            handler.next(options);
          },
          onResponse: (response, handler) {
            if (kDebugMode) {
              final data = response.data;
              int? code;
              String? msg;
              if (data is Map) {
                code = data['code'] as int?;
                msg = data['msg'] as String?;
              }
              _logger.d('');
              _logger.d('【RESPONSE】${response.statusCode} ${response.requestOptions.uri}');
              _logger.d('【CODE】$code  【MSG】$msg');
              if (data != null) {
                _logger.d('【DATA】$data');
              }
              _logger.d('');
            }

            handler.next(response);
          },
          onError: (error, handler) async {
            final statusCode = error.response?.statusCode;
            final data = error.response?.data;
            int? code;
            String? msg;
            if (data is Map) {
              code = data['code'] as int?;
              msg = data['msg'] as String?;
            }

            if (kDebugMode) {
              _logger.e('');
              _logger.e('【ERROR】${error.type}');
              _logger.e('【HTTP STATUS】$statusCode');
              _logger.e('【URL】${error.requestOptions.uri}');
              _logger.e('【CODE】$code  【MSG】$msg');
              if (data != null) {
                _logger.e('【RESPONSE DATA】$data');
              }
              _logger.e('【ERROR MESSAGE】${error.message}');
              _logger.e('');
            }

            // 场景1：HTTP 401 → guest 登录后重试
            if (statusCode == ApiErrorCode.unauthorized) {
              _logger.w('【401】HTTP 401 detected, attempting guest login');
              await _handleGuestLoginAndRetry(error, handler);
              return;
            }

            // 场景2：业务 code=23（token 过期） → guest 登录后重试
            if (code == ApiErrorCode.tokenExpired) {
              _logger.w('【CODE 23】Token expired, attempting guest login');
              await _handleGuestLoginAndRetry(error, handler);
              return;
            }

            handler.next(error);
          },
        ),
      );
  }

  final Dio _dio;
  final Logger _logger;
  final StorageService _storage;
  Dio get dio => _dio;

  /// Guest 登录回调：返回新 token（登录成功）或 null（失败）
  /// 由外部（通常是 AuthService）注入
  Future<String?> Function()? _onGuestLogin;

  /// 注册 Guest 登录回调
  void setOnGuestLogin(Future<String?> Function()? callback) {
    _onGuestLogin = callback;
  }

  /// ============================================================
  /// Guest 登录并发控制
  /// ============================================================

  /// 正在执行 guest 登录时，等待登录结果的请求队列
  final List<_PendingRequest> _pendingRequests = [];

  /// 是否正在执行 guest 登录
  bool _isLoggingIn = false;

  /// 确保已完成 guest 登录，返回最新 token（供 onRequest 调用）
  Future<String?> _ensureGuestLogin() async {
    final token = await _storage.getToken();
    if (token != null && token.isNotEmpty) {
      return token;
    }

    return _doGuestLogin();
  }

  /// 执行一次 guest 登录，供 onRequest / onError 共用
  Future<String?> _doGuestLogin() async {
    if (_isLoggingIn) {
      // 已有登录在进行中，等待其完成
      final completer = Completer<String?>();
      _pendingRequests.add(_PendingRequest(completer));
      return completer.future;
    }

    _isLoggingIn = true;

    try {
      String? newToken;

      if (_onGuestLogin != null) {
        final result = _onGuestLogin!();
        if (result != null) {
          newToken = await result;
        }
      }

      if (newToken != null) {
        _logger.w('【GUEST LOGIN】success, token obtained');
        // 通知所有等待中的请求
        for (final pending in _pendingRequests) {
          pending.completer.complete(newToken);
        }
        _pendingRequests.clear();
        return newToken;
      } else {
        _logger.w('【GUEST LOGIN】failed, notifying pending requests');
        for (final pending in _pendingRequests) {
          pending.completer.complete(null);
        }
        _pendingRequests.clear();
        return null;
      }
    } finally {
      _isLoggingIn = false;
    }
  }

  /// Guest 登录完成后，重试原请求（供 onError 调用）
  Future<void> _handleGuestLoginAndRetry(
      DioException error, ErrorInterceptorHandler handler) async {
    final newToken = await _doGuestLogin();

    if (newToken != null) {
      _retryWithNewToken(error, newToken, handler);
    } else {
      handler.next(error);
    }
  }

  void _retryWithNewToken(
      DioException error, String newToken, ErrorInterceptorHandler handler) {
    final opts = error.requestOptions;
    opts.headers['token'] = newToken;
    _dio.fetch(opts).then(
      (response) => handler.resolve(response),
      onError: (e) => handler.reject(e as DioException),
    );
  }

  // ============================================================
  // 其他方法
  // ============================================================

  String _buildXClientHeader() {
    final savedLang = _storage.getString(AppConstants.deviceLangKey);
    final lang = _normalizeLang(savedLang);
    final xClient = AppConfig.currentXClient;
    final version = AppConfig.appVersion;
    final osName = AppConfig.platformType;
    return '$xClient;version=$version;osName=$osName;x-lang=$lang';
  }

  String _normalizeLang(String? value) {
    final normalized = value?.trim();
    if (normalized == 'ar-SA') {
      return 'ar-SA';
    }
    if (normalized == 'en-US') {
      return 'en-US';
    }
    if (normalized == 'ar') {
      return 'ar-SA';
    }
    if (normalized == 'en') {
      return 'en-US';
    }
    return _defaultLang;
  }

  static String get _defaultLang {
    try {
      return _normalizeLocale(PlatformDispatcher.instance.locale);
    } catch (_) {
      return 'en-US';
    }
  }

  static String _normalizeLocale(Locale locale) {
    final languageCode = locale.languageCode.toLowerCase();
    if (languageCode == 'ar') {
      return 'ar-SA';
    }
    return 'en-US';
  }

  void setAuthToken(String? token) {
    if (token == null || token.isEmpty) {
      _dio.options.headers.remove('token');
    } else {
      _dio.options.headers['token'] = token;
      _dio.options.headers['language'] = 'en';
    }
  }

  HttpClientAdapter _buildHttpClientAdapter() {
    if (kIsWeb) {
      return HttpClientAdapter();
    }
    return IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        if (kDebugMode) {
          client.badCertificateCallback = (cert, host, port) => true;
        }
        return client;
      },
    );
  }
}

/// 等待 guest 登录完成的请求（简化版，不再需要存储 DioException 和 handler）
class _PendingRequest {
  _PendingRequest(this.completer);
  final Completer<String?> completer;
}

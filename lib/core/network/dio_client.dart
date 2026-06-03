import 'dart:async';
import 'dart:io';

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
/// - Token 过期时自动刷新
///
/// 【Token 刷新机制】
/// 当收到 401 时，调用 onTokenExpired 回调获取新 token：
/// - 返回新 token → 用新 token 重试请求
/// - 返回 null → 回调内部已处理登出，原请求以 401 结束
/// - 并发 401 时，后面的请求等待刷新完成后再重试
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

            // Token 过期：401 或后端返回的特定 code
            if (statusCode == ApiErrorCode.unauthorized ||
                code == ApiErrorCode.unauthorized) {
              _logger.w('【TOKEN EXPIRED】401 detected, attempting token refresh');
              await _handleTokenExpired(error, handler);
              return; // 重试在 _handleTokenExpired 内部通过 handler.next/err 结束
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

  /// Token 过期回调，返回新 token（刷新成功）或 null（刷新失败/已登出）
  /// 签名兼容：支持 sync void 和 async Future<String?>
  Future<String?> Function()? _onTokenExpired;

  /// 注册 Token 过期回调
  void setOnTokenExpired(Future<String?> Function()? callback) {
    _onTokenExpired = callback;
  }

  /// ============================================================
  /// Token 刷新机制
  /// ============================================================

  /// 正在刷新时，等待刷新的请求队列（每个请求一个 Completer）
  final List<_PendingRequest> _pendingRequests = [];

  /// 是否正在刷新 token
  bool _isRefreshing = false;

  /// 刷新完成后，通知所有等待中的请求
  Future<void> _handleTokenExpired(
      DioException error, ErrorInterceptorHandler handler) async {
    if (_isRefreshing) {
      // 已有刷新在进行中，将请求加入等待队列，刷新完成后重试
      final completer = Completer<String?>();
      _pendingRequests.add(_PendingRequest(error, handler, completer));
      // 等待刷新完成，收到结果后重试
      final newToken = await completer.future;
      if (newToken != null) {
        _retryWithNewToken(error, newToken, handler);
      }
      // newToken == null 表示刷新失败，已在刷新流程中处理登出
      return;
    }

    _isRefreshing = true;

    try {
      String? newToken;

      if (_onTokenExpired != null) {
        // 调用回调获取新 token
        final result = _onTokenExpired!();
        if (result != null) {
          newToken = await result;
        }
        // result == null 表示回调内部已处理登出（如 token 已无效，强制登出）
      }

      if (newToken != null) {
        _logger.w('[TOKEN EXPIRED] refresh success, new token obtained');
        // 通知所有等待中的请求，用新 token 重试
        for (final pending in _pendingRequests) {
          pending.completer.complete(newToken);
        }
        _pendingRequests.clear();
        // 重试当前请求
        _retryWithNewToken(error, newToken, handler);
      } else {
        _logger.w('[TOKEN EXPIRED] refresh failed or returned null, rejecting pending requests');
        // 刷新失败，通知所有等待中的请求以原错误结束
        for (final pending in _pendingRequests) {
          pending.completer.complete(null);
        }
        _pendingRequests.clear();
        handler.reject(error);
      }
    } finally {
      _isRefreshing = false;
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
    final lang = (savedLang != null && savedLang.isNotEmpty)
        ? savedLang
        : _defaultLang;
    final xClient = AppConfig.currentXClient;
    final version = AppConfig.appVersion;
    final osName = AppConfig.platformType;
    return '$xClient;version=$version;osName=$osName;x-lang=$lang';
  }

  static String get _defaultLang {
    try {
      final locale = PlatformDispatcher.instance.locale;
      final lang = '${locale.languageCode}-${locale.countryCode ?? ''}';
      return lang.isNotEmpty ? lang : 'en-US';
    } catch (_) {
      return 'en-US';
    }
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

/// 等待 token 刷新的请求
class _PendingRequest {
  _PendingRequest(this.error, this.handler, this.completer);
  final DioException error;
  final ErrorInterceptorHandler handler;
  final Completer<String?> completer;
}

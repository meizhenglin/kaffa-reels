import 'dart:async';

import 'package:dio/dio.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

import 'http_client_adapter_stub.dart'
    if (dart.library.io) 'http_client_adapter_io.dart';

import '../config/app_config.dart';
import '../constants/api_error_code.dart';
import '../constants/app_constants.dart';
import '../model/api_endpoints.dart';
import '../storage/storage_service.dart';
import 'session_expired_bus.dart';
import 'x_client_header.dart';

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
/// 仅在一种场景下触发 guest 登录：
/// - 发起请求时 token 完全没有（用户从未登录过 / 已登出） → guest 登录拿 token 后再发
///
/// 【会话失效（code=23）处理】
/// 当业务 code=23（token 过期）时，**不再降级为游客**！
/// - 原因：降级会让"真实登录用户"变成"游客"，VIP/数据全丢，体验极差
/// - 处理：清掉本地 token + 通过 [SessionExpiredBus] 通知 App 跳登录页
/// - 后端应实现 refresh_token 机制，客户端可改为：调 refresh 接口换新 token 后重试
/// ============================================================================
class DioClient {
  DioClient({Dio? dio, Logger? logger, StorageService? storage})
    : _logger = logger ?? Logger(),
      _dio = dio ?? Dio(),
      _storage = storage ?? StorageService() {
    _dio
      ..options = BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(
          milliseconds: AppConstants.connectTimeout,
        ),
        receiveTimeout: const Duration(
          milliseconds: AppConstants.receiveTimeout,
        ),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      )
      ..httpClientAdapter = _buildHttpClientAdapter()
      // 连接类失败自动重试（必须加在业务拦截器之前，重试成功直接返回）。
      ..interceptors.add(_buildConnectionRetryInterceptor())
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            // 每次请求动态构建 X-Client header（语言取自 Storage）
            options.headers['X-Client'] = await _buildXClientHeader();

            final isGuestAuthRequest = options.path == ApiEndpoints.guestLogin;
            if (!isGuestAuthRequest) {
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
            }
            final clientParams =
                _storage.getString(AppConstants.clientParamsKey) ?? '';
            if (clientParams.isNotEmpty) {
              options.headers['client_params'] = clientParams;
              options.headers['clientparams'] = clientParams;
            }

            if (kDebugMode) {
              _logger.d('');
              _logger.d(
                '【REQUEST】${options.method} ${_redactUri(options.uri)}',
              );
              _logger.d('【HEADERS】');
              options.headers.forEach((key, value) {
                final normalizedKey = key.toString().toLowerCase().replaceAll(
                  '-',
                  '_',
                );
                if (_sensitiveLogKeys.contains(normalizedKey)) {
                  _logger.d('  $key: ***');
                } else {
                  _logger.d('  $key: $value');
                }
              });
              final requestData = options.data;
              if (requestData is Map) {
                _logger.d('【BODY】${_redactSensitiveData(requestData)}');
              } else if (requestData is FormData) {
                _logger.d(
                  '【BODY】FormData(${requestData.fields.length} fields)',
                );
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
              _logger.d(
                '【RESPONSE】${response.statusCode} ${_redactUri(response.requestOptions.uri)}',
              );
              _logger.d('【CODE】$code  【MSG】$msg');
              if (data != null) {
                _logger.d('【DATA】${_redactSensitiveData(data)}');
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
              _logger.e('【URL】${_redactUri(error.requestOptions.uri)}');
              _logger.e('【CODE】$code  【MSG】$msg');
              if (data != null) {
                _logger.e('【RESPONSE DATA】${_redactSensitiveData(data)}');
              }
              _logger.e('【ERROR MESSAGE】${error.message}');
              _logger.e('【UNDERLYING ERROR】${error.error}');
              _logger.e('【ERROR STACK】${error.stackTrace}');
              _logger.e('');
            }

            // 场景1：HTTP 401 → 视为会话失效（不降级为游客）
            if (statusCode == ApiErrorCode.unauthorized) {
              _logger.w('【401】HTTP 401 detected, notifying session expired');
              await _handleSessionExpired(
                error,
                handler,
                reason: 'http-401',
                message: 'HTTP 401 Unauthorized',
                httpStatus: statusCode,
                serverCode: code,
              );
              return;
            }

            // 场景2：业务 code=23（token 过期） → 视为会话失效（不降级为游客）
            if (code == ApiErrorCode.tokenExpired) {
              _logger.w('【CODE 23】Token expired, notifying session expired');
              await _handleSessionExpired(
                error,
                handler,
                reason: 'code-23',
                message: msg ?? 'Token expired',
                httpStatus: statusCode,
                serverCode: code,
              );
              return;
            }

            handler.next(error);
          },
        ),
      );
  }

  // ============================================================
  // 连接类失败自动重试
  // ============================================================

  /// 场景：iOS（尤其国行设备）首次启动会弹「允许 App 使用无线数据」
  /// 权限窗，弹窗期间发出的所有请求连接直接失败；用户点「允许」后
  /// iOS 不会自动恢复已失败的请求，页面就停在空白，只能杀掉重开。
  /// 这里对连接层失败做带退避的自动重试（最多 3 次），权限授予后
  /// 重试即成功，无需退出重进。
  ///
  /// 只重试「连接建立失败」这类错误（connectionError / connectionTimeout），
  /// 不重试 receiveTimeout / HTTP 4xx 5xx，避免重复请求慢接口或放大错误。
  Interceptor _buildConnectionRetryInterceptor() {
    return InterceptorsWrapper(
      onError: (error, handler) async {
        final opts = error.requestOptions;
        final attempt = (opts.extra['_connRetry'] as int?) ?? 0;

        if (attempt >= 3 || !_isConnectionLevelFailure(error)) {
          handler.next(error);
          return;
        }

        final delay = Duration(milliseconds: 800 * (attempt + 1));
        _logger.w(
          '【RETRY】连接失败(${error.type}), '
          '第 ${attempt + 1}/3 次重试, ${delay.inMilliseconds}ms 后: '
          '${opts.uri}',
        );
        await Future<void>.delayed(delay);
        opts.extra['_connRetry'] = attempt + 1;
        try {
          // fetch 会重新走完整拦截器链（token / X-Client 会重新注入）
          final response = await _dio.fetch(opts);
          handler.resolve(response);
        } on DioException catch (e) {
          handler.next(e);
        }
      },
    );
  }

  bool _isConnectionLevelFailure(DioException e) =>
      e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout;

  static const Set<String> _sensitiveLogKeys = {
    'access_token',
    'accesstoken',
    'authcode',
    'authorization',
    'client_secret',
    'clientsecret',
    'code',
    'code_verifier',
    'codeverifier',
    'id_token',
    'idtoken',
    'password',
    'refresh_token',
    'refreshtoken',
    'state',
    'token',
  };

  Uri _redactUri(Uri uri) {
    final redactedQuery = <String, List<String>>{};
    uri.queryParametersAll.forEach((key, values) {
      final normalizedKey = key.toLowerCase().replaceAll('-', '_');
      redactedQuery[key] = _sensitiveLogKeys.contains(normalizedKey)
          ? const ['***']
          : values;
    });
    return uri.replace(queryParameters: redactedQuery);
  }

  Object? _redactSensitiveData(Object? value) {
    if (value is Map) {
      return value.map((key, nestedValue) {
        final normalizedKey = key.toString().toLowerCase().replaceAll('-', '_');
        if (_sensitiveLogKeys.contains(normalizedKey)) {
          return MapEntry(key, '***');
        }
        return MapEntry(key, _redactSensitiveData(nestedValue));
      });
    }
    if (value is List) {
      return value.map(_redactSensitiveData).toList();
    }
    return value;
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
        newToken = await _onGuestLogin!();
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

  /// ============================================================
  /// 会话失效处理
  /// ============================================================

  /// 防止多个 401/23 并发触发多次事件
  bool _sessionExpiredNotified = false;

  /// 处理会话失效（HTTP 401 / code=23）
  ///
  /// 1. 清掉本地 token
  /// 2. 通过 [SessionExpiredBus] 通知 App
  /// 3. 拒绝原请求（让 UI 显示错误或跳转登录）
  Future<void> _handleSessionExpired(
    DioException error,
    ErrorInterceptorHandler handler, {
    required String reason,
    required String message,
    int? httpStatus,
    int? serverCode,
  }) async {
    // 清掉本地 token（让 onRequest 知道没有 token 了）
    try {
      await _storage.removeToken();
      _dio.options.headers.remove('token');
    } catch (e) {
      _logger.w('【SESSION EXPIRED】failed to clear token: $e');
    }

    // 只通知一次（避免多个并发 401 触发多次跳登录）
    if (!_sessionExpiredNotified) {
      _sessionExpiredNotified = true;
      SessionExpiredBus().notifySessionExpired(
        SessionExpiredReason(
          source: reason,
          message: message,
          httpStatus: httpStatus,
          serverCode: serverCode,
        ),
      );
      // 5 秒后允许再次通知（避免永久锁住）
      Timer(const Duration(seconds: 5), () {
        _sessionExpiredNotified = false;
      });
    }

    // 拒绝原请求
    handler.next(error);
  }

  // ============================================================
  // 其他方法
  // ============================================================

  /// 构造 `X-Client` 请求头。
  ///
  /// 格式和取值逻辑统一放在 [XClientHeader] 里 —— 之前这里和
  /// `api_service.dart` 各写了一份，而且内容不一样（这份少了
  /// `channel` 和 `build`）。因为 Dio 是「先合并 Options.headers、
  /// 再跑拦截器」，而这里是最后写 `X-Client` 的那个，所以实际发出去的
  /// 一直是这份少了两个字段的版本。
  Future<String> _buildXClientHeader() async {
    final savedLang = _storage.getString(AppConstants.deviceLangKey);
    final header = await XClientHeader.build(savedLang: savedLang);
    debugPrint(
      '[DioClient] X-Client built from deviceLang=$savedLang => $header',
    );
    return header;
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
    return createPlatformHttpClientAdapter();
  }
}

/// 等待 guest 登录完成的请求（简化版，不再需要存储 DioException 和 handler）
class _PendingRequest {
  _PendingRequest(this.completer);
  final Completer<String?> completer;
}

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
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
/// - Token 过期时自动跳转登录页
///
/// 【小程序原版对应】
/// 对应小程序的 common/http.js，核心逻辑完全对齐：
/// - X-Client 头 → 小程序 uni.request header
/// - Token 自动注入 → 小程序 header.token
/// - reLoad 重登录 → 小程序 reLoad() 跳转登录页
/// ============================================================================
class DioClient {
  DioClient({Dio? dio, Logger? logger})
      : _logger = logger ?? Logger(),
        _dio = dio ?? Dio(),
        _storage = StorageService() {
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
          // X-Client 在每次请求时动态构建（见 onRequest 拦截器）
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

            // ==================== 完整请求日志 ====================
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

            handler.next(options);
          },
          onResponse: (response, handler) {
            // ==================== 完整响应日志 ====================
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

            handler.next(response);
          },
          onError: (error, handler) async {
            // ==================== 完整错误日志 ====================
            final statusCode = error.response?.statusCode;
            final data = error.response?.data;
            int? code;
            String? msg;
            if (data is Map) {
              code = data['code'] as int?;
              msg = data['msg'] as String?;
            }
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

            // Token 过期：401 或后端返回的特定 code
            if (statusCode == 401 || code == 401) {
              _logger.w('【TOKEN EXPIRED】401 detected, triggering token expired flow');
              await _handleTokenExpired();
            }

            handler.next(error);
          },
        ),
      );
  }

  final Dio _dio;
  final Logger _logger;
  final StorageService _storage;
  bool _isRefreshing = false;

  Dio get dio => _dio;

  String _buildXClientHeader() {
    // 优先使用 Storage 中存储的语言（游客登录时保存的设备语言 / 用户设置页切换的语言）
    final savedLang = _storage.getString(AppConstants.deviceLangKey);
    final lang = (savedLang != null && savedLang.isNotEmpty)
        ? savedLang
        : _defaultLang;
    final xClient = AppConfig.currentXClient;
    final version = AppConfig.appVersion;
    final osName = AppConfig.platformType;
    return '$xClient;version=$version;osName=$osName;x-lang=$lang';
  }

  /// 设备默认语言，从系统获取
  static String get _defaultLang {
    // 延迟获取，回退到 en-US
    try {
      final locale = PlatformDispatcher.instance.locale;
      final lang = '${locale.languageCode}-${locale.countryCode ?? ''}';
      return lang.isNotEmpty ? lang : 'en-US';
    } catch (_) {
      return 'en-US';
    }
  }

  Future<void> _handleTokenExpired() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      await _storage.removeToken();
      if (_onTokenExpired != null) {
        _onTokenExpired!();
      }
    } finally {
      _isRefreshing = false;
    }
  }

  /// Token 过期回调，由外部（App 级别）注册，处理跳转登录页等全局逻辑
  void Function()? _onTokenExpired;

  /// 注册 Token 过期回调
  /// [callback] 触发时执行（如：跳转登录页、清理状态）
  void setOnTokenExpired(void Function() callback) {
    _onTokenExpired = callback;
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

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:logger/logger.dart';
import 'package:flutter/foundation.dart';

import '../constants/app_constants.dart';

/// ============================================================================
/// HTTP 网络客户端配置
///
/// 【功能说明】
/// 基于 Dio 库封装的网络请求客户端，负责：
/// - 配置全局 HTTP 请求参数（超时、头部等）
/// - 添加请求/响应日志拦截器
/// - 管理认证令牌
///
/// 【工作流程】
/// 1. 所有 API 请求通过 Dio 实例发送
/// 2. 请求拦截器在发送前记录日志
/// 3. 响应拦截器在收到响应后记录日志
/// 4. 错误拦截器统一处理请求错误
///
/// 【如何修改】
/// - 添加请求头：在 BaseOptions.headers 中添加
/// - 修改超时时间：在 app_constants.dart 中修改
/// - 添加新的拦截器：在 interceptors 中添加
/// ============================================================================
class DioClient {
  /// 构造函数
  /// [dio] 可选，自定义的 Dio 实例；如果不传则使用默认实例
  /// [logger] 可选，自定义的日志记录器；如果不传则使用默认 Logger
  DioClient({Dio? dio, Logger? logger})
      : _logger = logger ?? Logger(),
        _dio = dio ?? Dio() {
    // 配置 Dio 选项
    _dio
      ..options = BaseOptions(
        // API 基础地址，所有请求都会基于此地址
        // 【修改提示】在 app_constants.dart 中修改 AppConstants.apiBaseUrl
        baseUrl: AppConstants.apiBaseUrl,

        // 连接超时时间：与服务器建立连接的最大等待时间
        // 【修改提示】在 app_constants.dart 中修改 AppConstants.connectTimeout
        connectTimeout:
            const Duration(milliseconds: AppConstants.connectTimeout),

        // 接收超时时间：等待服务器返回数据的最大时间
        // 【修改提示】在 app_constants.dart 中修改 AppConstants.receiveTimeout
        receiveTimeout:
            const Duration(milliseconds: AppConstants.receiveTimeout),

        // 全局请求头
        headers: {
          // 指定请求数据类型为 JSON
          'Content-Type': 'application/json',
          // 期望接受的响应数据类型
          'Accept': 'application/json',
        },
      )
      // 在 Debug 模式下跳过 SSL 证书验证，解决开发环境证书过期问题
      // 【重要】生产环境默认不跳过，请确保生产服务器证书有效
      ..httpClientAdapter = _buildHttpClientAdapter()
      ..interceptors.add(
        InterceptorsWrapper(
          /// 请求拦截器：在请求发送之前执行
          onRequest: (options, handler) {
            // 打印请求日志：[METHOD] => URL
            // 【示例】REQUEST[GET] => https://api.example.com/dramas
            _logger.d('REQUEST[${options.method}] => ${options.uri}');
            // 打印 Authorization 头
            final auth = options.headers['Authorization'];
            if (auth != null) {
              _logger.d('AUTHORIZATION: $auth');
            }
            // 必须调用 handler.next(options) 才能继续发送请求
            handler.next(options);
          },

          /// 响应拦截器：在收到响应之后执行
          onResponse: (response, handler) {
            // 打印响应日志：[状态码] => URL
            // 【示例】RESPONSE[200] => https://api.example.com/dramas
            _logger.d(
              'RESPONSE[${response.statusCode}] => ${response.requestOptions.uri}',
            );
            // 必须调用 handler.next(response) 才能继续处理响应
            handler.next(response);
          },

          /// 错误拦截器：在请求出错时执行
          onError: (error, handler) {
            // 打印错误日志：[状态码] => URL
            // 【示例】ERROR[401] => https://api.example.com/user/profile
            _logger.e(
              'ERROR[${error.response?.statusCode}] => ${error.requestOptions.uri}',
              error: error,
            );
            // 【扩展点】可以在这里统一处理错误，如：
            // - 401 未授权：跳转到登录页
            // - 403 禁止访问：显示无权限提示
            // - 500 服务器错误：显示服务器异常提示
            handler.next(error);
          },
        ),
      );
  }

  /// Dio 实例
  final Dio _dio;

  /// Logger 实例，用于日志记录
  final Logger _logger;

  /// 获取 Dio 实例，外部可通过此访问 Dio 的 GET/POST 等方法
  Dio get dio => _dio;

  /// 设置认证令牌
  /// [token] 认证令牌，传 null 或空字符串表示清除令牌
  ///
  /// 【使用场景】
  /// - 用户登录成功后：传入从服务器获取的 JWT 令牌
  /// - 用户登出时：传入 null 清除令牌
  ///
  /// 【工作原理】
  /// 在请求头中添加 Authorization: Bearer {token}
  /// 后续所有请求都会自动带上这个头部
  void setAuthToken(String? token) {
    if (token == null || token.isEmpty) {
      // 清除 Authorization 头部
      _dio.options.headers.remove('Authorization');
    } else {
      // 设置 Bearer 令牌
      _dio.options.headers['authToken'] = '$token';
      _dio.options.headers['language'] = 'en';
    }
  }

  /// 构建 HTTP 客户端适配器，根据环境配置 SSL 行为
  ///
  /// Debug 模式：跳过 SSL 证书验证（用于开发环境证书过期的情况）
  /// Release 模式：使用系统默认 SSL 验证（保持生产环境安全性）
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

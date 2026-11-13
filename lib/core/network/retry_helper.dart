import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';

/// ============================================================================
/// 网络重试工具
///
/// 【功能】
/// 对网络请求做带指数退避的重试，常用于：
/// - 登录接口（弱网首次失败时重试）
/// - Token 同步
/// - 关键业务数据拉取（user center 等）
///
/// 【使用】
/// ```dart
/// final response = await RetryHelper.retry(
///   () => apiService.getUserCenter(),
///   maxAttempts: 3,
///   baseDelay: const Duration(milliseconds: 800),
/// );
/// ```
///
/// 【退避策略】
/// - 第 1 次失败：等 800ms
/// - 第 2 次失败：等 1600ms
/// - 第 3 次失败：抛错
///
/// 【注意】
/// - 不重试业务错误（code != 200/0），只重试网络错误 / 超时
/// - 不重试 401 / 403（这些是认证问题，重试无意义）
/// ============================================================================
class RetryHelper {
  RetryHelper._();

  static final _rand = math.Random();

  /// 带指数退避的重试
  ///
  /// [task] 要执行的任务
  /// [maxAttempts] 最大尝试次数（默认 3）
  /// [baseDelay] 基础延迟（默认 800ms）
  /// [maxDelay] 最大延迟（默认 5s）
  /// [retryOn] 哪些异常要重试（默认所有异常都重试）
  /// [onRetry] 每次重试前的回调（用于埋点）
  static Future<T> retry<T>(
    Future<T> Function() task, {
    int maxAttempts = 3,
    Duration baseDelay = const Duration(milliseconds: 800),
    Duration maxDelay = const Duration(seconds: 5),
    bool Function(Object error)? retryOn,
    void Function(int attempt, Object error)? onRetry,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await task();
      } catch (e) {
        lastError = e;

        // 最后一次失败：直接抛
        if (attempt >= maxAttempts) {
          rethrow;
        }

        // 自定义重试判断
        if (retryOn != null && !retryOn(e)) {
          rethrow;
        }

        // 默认不重试 401 / 403
        if (e is DioException) {
          final status = e.response?.statusCode;
          if (status == 401 || status == 403) {
            rethrow;
          }
        }

        // 指数退避 + 抖动
        final delayMs = math.min(
          baseDelay.inMilliseconds * (1 << (attempt - 1)),
          maxDelay.inMilliseconds,
        );
        final jittered = delayMs + _rand.nextInt(200);
        if (onRetry != null) {
          onRetry(attempt, e);
        }
        await Future.delayed(Duration(milliseconds: jittered));
      }
    }
    // 不会到这里，兜底
    throw lastError ?? StateError('RetryHelper: unreachable');
  }
}

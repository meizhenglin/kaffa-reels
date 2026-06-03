/// ============================================================================
/// API 错误码常量
///
/// 【功能说明】
/// 统一管理后端返回的业务错误码，便于搜索引用和日后的统一处理。
///
/// 【使用方式】
/// import '../constants/api_error_code.dart';
/// if (code == ApiErrorCode.success) { ... }
/// if (code == ApiErrorCode.tokenExpired) { ... }
///
/// 【维护提示】
/// 新增错误码时在此添加，保持与后端文档同步。
/// ============================================================================
class ApiErrorCode {
  ApiErrorCode._();

  // ==================== 通用成功码 ====================
  /// 请求成功（部分接口返回 0 表示成功）
  static const int success = 0;

  /// 请求成功（大多数接口返回 200 表示成功）
  static const int ok = 200;

  // ==================== 认证相关 ====================
  /// Token 已过期，需要重新登录或刷新 Token
  static const int tokenExpired = 23;

  /// Token 无效（401 HTTP 状态码）
  static const int unauthorized = 401;

  // ==================== 播放器相关 ====================
  /// 视频不存在或已被删除
  static const int videoNotFound = 20050007;

  // ==================== 业务错误码 ====================
  /// 参数错误
  static const int badRequest = 400;
  /// 禁止访问
  static const int forbidden = 403;
  /// 资源不存在
  static const int notFound = 404;
  /// 服务器内部错误
  static const int serverError = 500;
}

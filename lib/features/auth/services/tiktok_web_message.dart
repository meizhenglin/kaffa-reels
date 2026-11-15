/// TikTok Web OAuth 弹窗回调消息（全平台共享，不含 dart:html 依赖）。
class TiktokWebMessage {
  const TiktokWebMessage({
    this.code,
    this.state,
    this.error,
    this.cancelled = false,
  });

  /// TikTok 下发的授权码。
  final String? code;

  /// 回调带回的 state（用于 CSRF 校验）。
  final String? state;

  /// 错误标识：`popup-blocked`（浏览器拦截弹窗）/ `timeout` /
  /// TikTok 回调 URL 上的原始 error 值。
  final String? error;

  /// 用户手动关闭了弹窗（未完成授权）。
  final bool cancelled;
}

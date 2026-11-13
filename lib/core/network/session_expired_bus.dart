import 'dart:async';

import 'package:flutter/foundation.dart';

/// ============================================================================
/// 会话失效事件总线
///
/// 【作用】
/// 当后端返回 code=23（token 过期）时，dio_client 会调用 [notifySessionExpired]，
/// 通知 App 全局进入"会话失效"状态。
///
/// 监听方（通常是 App 入口 / AuthNotifier）订阅 [onSessionExpired] 事件流，
/// 收到事件后清空本地 token + 跳转到登录页。
///
/// 【为什么不直接在这里处理】
/// - dio_client 是底层网络层，不应依赖 AuthNotifier（避免循环依赖）
/// - 用事件总线（Stream）解耦
///
/// 【为什么不直接降级为游客】
/// - 降级为游客会让"真实登录用户"变成"游客"，体验糟（数据全丢，VIP 没了）
/// - 让用户重新登录比被降级为游客更好
/// ============================================================================
class SessionExpiredBus {
  SessionExpiredBus._();

  static final SessionExpiredBus _instance = SessionExpiredBus._();

  /// 全局单例
  factory SessionExpiredBus() => _instance;

  final StreamController<SessionExpiredReason> _controller =
      StreamController<SessionExpiredReason>.broadcast();

  /// 订阅会话失效事件
  Stream<SessionExpiredReason> get onSessionExpired => _controller.stream;

  /// 触发会话失效通知
  void notifySessionExpired(SessionExpiredReason reason) {
    if (_controller.isClosed) return;
    _controller.add(reason);
    debugPrint('[SessionExpiredBus] notified: $reason');
  }

  /// 释放资源（一般不用，除非 App 整体销毁）
  void dispose() {
    _controller.close();
  }
}

/// 会话失效原因
class SessionExpiredReason {
  const SessionExpiredReason({
    required this.source,
    required this.message,
    this.httpStatus,
    this.serverCode,
  });

  /// 触发源
  final String source;

  /// 详细原因描述
  final String message;

  /// HTTP 状态码（如果有）
  final int? httpStatus;

  /// 后端业务码（如果有）
  final int? serverCode;

  @override
  String toString() =>
      'SessionExpiredReason(source=$source, message=$message, httpStatus=$httpStatus, serverCode=$serverCode)';
}

import 'dart:async';

import 'package:flutter/material.dart';

/// 支付处理超时异常。
///
/// [PaymentLoadingOverlay.run] 里 task 超时时抛出；注意超时只是提前
/// 解除全屏遮罩，底层支付任务仍在后台继续（支付回调/结果提示照常执行），
/// 不会中断支付本身。
class PaymentProcessingTimeoutException implements Exception {
  @override
  String toString() => 'PaymentProcessingTimeoutException';
}

/// 【支付统一 loading】全屏遮罩 + 居中 loading。
///
/// 【设计目的】K币充值 / VIP 订阅 / 单集解锁等支付确认后，原来只有确认
/// 按钮上的小 loading，用户还能点屏幕其他地方（连点商品、关弹窗），
/// 容易造成重复支付/状态错乱。统一改为：确认后整屏遮罩拦住所有交互，
/// 正中间显示 loading，任何支付相关流程共用同一视觉与行为。
///
/// 【超时】task 超过 [timeout] 未完成时，自动解除遮罩并抛出
/// [PaymentProcessingTimeoutException]，由调用方给出超时提示。
/// 关键点：超时不会取消 task —— 商店支付/后端回调仍在后台进行，
/// 到账后原有的成功/失败提示会照常弹出，只是用户不再被挡着。
///
/// 【不适用场景】需要用户与外部页面交互的流程（如 HaiPay H5 收银台
/// webview）不要套这个遮罩 —— webview 虽然盖在遮罩上方可以操作，
/// 但用户返回 app 后会被残留的遮罩挡住，体验反而变差。
class PaymentLoadingOverlay {
  /// 默认超时：商店支付（用户要在系统支付弹窗里操作）给足时间。
  static const defaultTimeout = Duration(seconds: 60);

  /// 展示全屏遮罩并执行 [task]，返回 task 的结果。
  ///
  /// - 遮罩期间拦截所有点击/返回（PopScope canPop=false）。
  /// - task 里自己弹的对话框（确认框/渠道选择器）会盖在遮罩上方，可正常交互。
  /// - 超时抛 [PaymentProcessingTimeoutException]。
  static Future<T> run<T>(
    BuildContext context, {
    required Future<T> Function() task,
    String? message,
    Duration timeout = defaultTimeout,
  }) async {
    // 提前抓 root navigator：遮罩必须盖住 bottom sheet / 页面栈全部内容。
    final navigator = Navigator.of(context, rootNavigator: true);

    final dialogFuture = showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      useSafeArea: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ),
                ),
                if (message != null && message.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    try {
      return await task().timeout(timeout);
    } on TimeoutException {
      throw PaymentProcessingTimeoutException();
    } finally {
      // 只 pop 我们自己这层遮罩（它是栈顶时）；task 中途已经 pop 掉的话跳过。
      if (navigator.canPop()) navigator.pop();
      await dialogFuture;
    }
  }
}

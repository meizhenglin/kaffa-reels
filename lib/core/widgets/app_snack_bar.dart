import 'package:flutter/material.dart';

class AppSnackBar {
  static SnackBar standard({
    required String message,
    Duration duration = const Duration(seconds: 2),
  }) {
    return SnackBar(
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.black),
      ),
      backgroundColor: const Color(0xFFFFFFFF),
      duration: duration,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 2),
  }) {
    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) {
      return;
    }

    late OverlayEntry entry;

    Widget buildSnackBarWidget(BuildContext entryContext) {
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                // entry 可能已被定时器移除，直接 remove 会触发断言异常（红屏）。
                if (entry.mounted) {
                  entry.remove();
                }
              },
              child: Container(
                color: Colors.transparent,
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            // 【必须用 entry 自己的 context】不要用调用方的 context：
            // 调用方（比如解锁弹窗）常常在 show 之后立刻 pop，
            // 闭包里持有它的 context 会让 overlay entry 在 2 秒存活期内
            // 查询到已销毁的元素（deactivated widget's ancestor），
            // 表现为屏幕上偶发闪一下红色报错。
            bottom: MediaQuery.of(entryContext).viewPadding.bottom + 60,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    entry = OverlayEntry(
      builder: (entryContext) => buildSnackBarWidget(entryContext),
    );

    overlay.insert(entry);
    Future.delayed(duration, () {
      // 点击移除后 mounted 已为 false，二次 remove 会抛断言异常。
      if (entry.mounted) {
        entry.remove();
      }
    });
  }
}

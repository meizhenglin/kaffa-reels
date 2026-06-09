import 'package:flutter/material.dart';

/// 应用渐变背景组件
/// 顶部 182pt 为渐变背景，以下为纯色背景
class GradientScaffold extends StatelessWidget {
  const GradientScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomNavigationBar,
    this.resizeToAvoidBottomInset = true, // ✅ 添加参数，默认 true
    this.bottomBackgroundColor = const Color(0xFF1F2025),
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomNavigationBar;
  final bool resizeToAvoidBottomInset; // ✅ 添加
  final Color bottomBackgroundColor;
  

  @override
  Widget build(BuildContext context) {
    return Scaffold(
     resizeToAvoidBottomInset: resizeToAvoidBottomInset, // ✅ 使用参数
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 渐变背景
          Column(
            children: [
              // 渐变区域（固定 182pt）
              Container(
                height: 182,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF5D4391),
                      Color(0xFF1F2025),
                    ],
                  ),
                ),
              ),
              // 底部纯色（自适应填充剩余空间）
              Expanded(
                child: ColoredBox(color: bottomBackgroundColor),
              ),
            ],
          ),
          // 内容
          body,
        ],
      ),
      appBar: appBar,
      bottomNavigationBar: bottomNavigationBar,
    );
  }
}

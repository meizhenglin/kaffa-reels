import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qahwa_tv/core/widgets/mouse_drag_scroll.dart';

/// 这里刻意复刻 `main.dart` 里的接线方式：全局 `MaterialApp.scrollBehavior`。
Widget _buildApp({required bool enableMouseDrag}) {
  final pageView = PageView.builder(
    scrollDirection: Axis.vertical,
    itemCount: 3,
    itemBuilder: (context, index) => Center(child: Text('page $index')),
  );
  return MaterialApp(
    scrollBehavior: enableMouseDrag ? const MouseDragScrollBehavior() : null,
    home: pageView,
  );
}

Future<void> _dragWithMouse(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    const Offset(400, 500),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();
  await gesture.moveBy(const Offset(0, -200));
  await tester.pump();
  await gesture.moveBy(const Offset(0, -200));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('默认不响应鼠标拖拽（Web 上只能滚轮）', (tester) async {
    await tester.pumpWidget(_buildApp(enableMouseDrag: false));
    await _dragWithMouse(tester);

    expect(find.text('page 0'), findsOneWidget);
    expect(find.text('page 1'), findsNothing);
  });

  testWidgets('全局 MouseDragScrollBehavior 让页面支持鼠标拖拽翻页', (tester) async {
    await tester.pumpWidget(_buildApp(enableMouseDrag: true));
    await _dragWithMouse(tester);

    expect(find.text('page 1'), findsOneWidget);
  });
}

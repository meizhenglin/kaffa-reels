# arab_drama_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

$env:Path += ";D:\install\flutter\bin"

flutter clean
flutter pub get

# 查看可用设备
flutter devices

# 运行到 Chrome（Web）
flutter run -d chrome

# 运行到 Windows 桌面
flutter run -d windows

# 运行到 Edge
flutter run -d edge

# 让 Flutter 自动选择设备
flutter run

Windows：确保已启用 Windows 桌面支持
flutter config --enable-windows-desktop

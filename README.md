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


编译报错：flutter doctor
在 PowerShell 里依次执行这 5 条命令：
Invoke-WebRequest -Uri "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip" -OutFile "$env:TEMP\cmdline-tools.zip"

New-Item -ItemType Directory -Path "C:\Users\yewu\AppData\Local\Android\Sdk\cmdline-tools\latest" -Force | Out-Null

Expand-Archive -Path "$env:TEMP\cmdline-tools.zip" -DestinationPath "$env:TEMP\cmdline-tools-extract" -Force

Move-Item -Path "$env:TEMP\cmdline-tools-extract\cmdline-tools\*" -Destination "C:\Users\yewu\AppData\Local\Android\Sdk\cmdline-tools\latest\" -Force

& "C:\Users\yewu\AppData\Local\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" --version

echo y | & "C:\Users\yewu\AppData\Local\Android\Sdk\cmdline-tools\latest\bin\sdkmanager.bat" --licenses

flutter doctor


gradle

1. 下载地址

https://services.gradle.org/distributions/gradle-8.14-all.zip
（文件约 200MB，选 all 发行版，不是 bin）

2. 放置位置

下载完成后，把 zip 文件放到这个路径下（注意不要解压）：

C:\Users\yewu\.gradle\wrapper\dists\gradle-8.14-all\c2qonpi39x1mddn7hk5gh9iqj\gradle-8.14-all.zip
文件夹结构需要是：

C:\Users\yewu\.gradle\wrapper\dists\gradle-8.14-all\c2qonpi39x1mddn7hk5gh9iqj\
├── gradle-8.14-all.zip          ← 手动放入这个
└── gradle-8.14/                  ← 自动解压后生成
放入 zip 后，删除同目录下的 .lck 锁文件（如果有），然后重新运行 flutter run 即可。


ngrok http 8082
https://scolding-unbaked-refrain.ngrok-free.dev 
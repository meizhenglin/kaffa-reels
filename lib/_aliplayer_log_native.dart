/// Implementation for native platforms (Android/iOS/macOS/Windows/Linux).
library;

import 'package:flutter_aliplayer/flutter_aliplayer.dart';

class AliPlayerLog {
  static Future<void> init() async {
    FlutterAliplayer.enableConsoleLog(false);
    FlutterAliplayer.setLogLevel(LogLevel.AF_LOG_LEVEL_NONE);
  }
}

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

import 'firebase_options.dart';

/// Firebase 初始化服务
class FirebaseService {
  FirebaseService._();

  static final Logger _logger = Logger();
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  /// 在 runApp 之前调用
  static Future<void> initialize() async {
    if (_initialized) return;

    // 项目使用设备匿名登录，不依赖 Firebase Auth，所有平台跳过初始化
    _initialized = true;
    _logger.i('Firebase skipped (project uses device anonymous login)');
  }
}


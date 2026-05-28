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

    try {
      if (Firebase.apps.isNotEmpty) {
        _initialized = true;
        _logger.i('Firebase already initialized');
        return;
      }

      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _initialized = true;
      _logger.i('Firebase initialized successfully');
    } on FirebaseException catch (e, st) {
      if (e.code == 'duplicate-app' && e.message?.contains('[DEFAULT]') == true) {
        _initialized = true;
        _logger.w('Firebase default app already exists, continuing.');
        return;
      }
      _logger.e('Firebase initialization failed', error: e, stackTrace: st);
      if (kDebugMode) {
        _logger.w(
          'Run `dart pub global activate flutterfire_cli` then '
          '`flutterfire configure` to generate firebase_options.dart',
        );
      }
      rethrow;
    } catch (e, st) {
      _logger.e('Firebase initialization failed', error: e, stackTrace: st);
      if (kDebugMode) {
        _logger.w(
          'Run `dart pub global activate flutterfire_cli` then '
          '`flutterfire configure` to generate firebase_options.dart',
        );
      }
      rethrow;
    }
  }
}

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
        _logger.i('Firebase already initialized; reusing default app');
        return;
      }

      if (kIsWeb) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      } else {
        await Firebase.initializeApp();
      }
      _initialized = true;
      _logger.i('Firebase initialized successfully');
    } on FirebaseException catch (e, stackTrace) {
      if (e.code == 'duplicate-app') {
        _initialized = true;
        _logger.w('Firebase duplicate default app detected; treating as initialized');
        return;
      }
      _logger.e('Firebase initialize failed', error: e, stackTrace: stackTrace);
      rethrow;
    } catch (e, stackTrace) {
      _logger.e('Firebase initialize failed', error: e, stackTrace: stackTrace);
      rethrow;
    }
  }
}


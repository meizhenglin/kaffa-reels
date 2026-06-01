// Copyright © 2025 Alibaba Cloud. All rights reserved.
//
// Author: keria
// Date: 2025/2/19
// Brief: SharedPreferences 管理工具类

import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences 管理工具类（单例模式）
class SPManager {
  SPManager._internal() {
    _initPrefs();
  }

  static final SPManager _instance = SPManager._internal();
  static SPManager get instance => _instance;

  SharedPreferences? _prefs;
  bool _initialized = false;
  final List<Function(SharedPreferences)> _pendingCallbacks = [];

  void _initPrefs() {
    SharedPreferences.getInstance().then((prefs) {
      _prefs = prefs;
      _initialized = true;
      for (var callback in _pendingCallbacks) {
        callback(prefs);
      }
      _pendingCallbacks.clear();
    });
  }

  void _ensureInitialized(Function(SharedPreferences) callback) {
    if (_initialized && _prefs != null) {
      callback(_prefs!);
    } else {
      _pendingCallbacks.add(callback);
      if (_prefs == null && !_initialized && _pendingCallbacks.length == 1) {
        _initPrefs();
      }
    }
  }

  Future<bool> saveString(String key, String value) =>
      _saveOperation((prefs) => prefs.setString(key, value));

  String? getString(String key) =>
      _getOperation((prefs) => prefs.getString(key));

  Future<bool> saveInt(String key, int value) =>
      _saveOperation((prefs) => prefs.setInt(key, value));

  int? getInt(String key) =>
      _getOperation((prefs) => prefs.getInt(key));

  Future<bool> saveDouble(String key, double value) =>
      _saveOperation((prefs) => prefs.setDouble(key, value));

  double? getDouble(String key) =>
      _getOperation((prefs) => prefs.getDouble(key));

  Future<bool> saveBool(String key, bool value) =>
      _saveOperation((prefs) => prefs.setBool(key, value));

  bool? getBool(String key) =>
      _getOperation((prefs) => prefs.getBool(key));

  Future<bool> saveStringList(String key, List<String> value) =>
      _saveOperation((prefs) => prefs.setStringList(key, value));

  List<String>? getStringList(String key) =>
      _getOperation((prefs) => prefs.getStringList(key));

  Future<bool> remove(String key) =>
      _saveOperation((prefs) => prefs.remove(key));

  Future<bool> clearAll() =>
      _saveOperation((prefs) => prefs.clear());

  Future<bool> _saveOperation(
    Future<bool> Function(SharedPreferences) operation,
  ) async {
    Completer<bool> completer = Completer<bool>();
    _ensureInitialized((prefs) async {
      try {
        bool result = await operation(prefs);
        completer.complete(result);
      } catch (e) {
        completer.completeError(e);
      }
    });
    return completer.future;
  }

  T? _getOperation<T>(T? Function(SharedPreferences) operation) {
    if (!_initialized || _prefs == null) {
      if (!_initialized) {
        _initPrefs();
      }
      return null;
    }
    try {
      return operation(_prefs!);
    } catch (e) {
      return null;
    }
  }
}

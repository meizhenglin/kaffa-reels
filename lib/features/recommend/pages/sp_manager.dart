// SharedPreferences manager (copied from aliplayer_widget example)
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

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

  Future<bool> saveString(String key, String value) async {
    return _saveOperation((prefs) => prefs.setString(key, value));
  }

  String? getString(String key) {
    return _getOperation((prefs) => prefs.getString(key));
  }

  Future<bool> saveInt(String key, int value) async {
    return _saveOperation((prefs) => prefs.setInt(key, value));
  }

  int? getInt(String key) {
    return _getOperation((prefs) => prefs.getInt(key));
  }

  Future<bool> saveBool(String key, bool value) async {
    return _saveOperation((prefs) => prefs.setBool(key, value));
  }

  bool? getBool(String key) {
    return _getOperation((prefs) => prefs.getBool(key));
  }

  Future<bool> remove(String key) async {
    return _saveOperation((prefs) => prefs.remove(key));
  }

  Future<bool> clearAll() async {
    return _saveOperation((prefs) => prefs.clear());
  }

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

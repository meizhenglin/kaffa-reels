import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/storage/storage_service.dart';

final searchHistoryStorageProvider = Provider<SearchHistoryStorage>((ref) {
  return SearchHistoryStorage(ref.watch(storageServiceProvider));
});

class SearchHistoryStorage {
  SearchHistoryStorage(this._storage);

  final StorageService _storage;

  List<String> load() {
    final raw = _storage.getString(AppConstants.searchHistoryKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => e.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> add(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    final history = load()..remove(trimmed);
    history.insert(0, trimmed);
    if (history.length > AppConstants.maxSearchHistoryItems) {
      history.removeRange(AppConstants.maxSearchHistoryItems, history.length);
    }
    await _storage.setString(
      AppConstants.searchHistoryKey,
      jsonEncode(history),
    );
  }

  Future<void> remove(String keyword) async {
    final history = load()..remove(keyword);
    await _storage.setString(
      AppConstants.searchHistoryKey,
      jsonEncode(history),
    );
  }

  Future<void> clear() async {
    await _storage.remove(AppConstants.searchHistoryKey);
  }
}

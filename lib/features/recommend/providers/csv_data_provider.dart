import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/csv_data_service.dart';
import '../models/banner.dart';
import '../models/drama.dart';

/// CSV 数据Provider
/// 从 assets/data/dramas.csv 加载短剧数据
/// 这是一个全局缓存的Provider，所有页面共享同一份数据
final csvDataProvider = FutureProvider<List<CsvDramaData>>((ref) async {
  final service = CsvDataService.instance;

  try {
    // 优先从 assets 加载（适用于打包后的应用）
    final data = await service.loadFromAssets('assets/data/dramas.csv');
    if (data.isNotEmpty) return data;
  } catch (_) {}

  // 如果 assets 加载失败，尝试从文档目录加载（开发阶段）
  try {
    final data = await service.loadFromCsv(
      'C:\\Users\\admin\\Desktop\\新建 XLS 工作表.csv',
    );
    if (data.isNotEmpty) return data;
  } catch (_) {}

  return [];
});

/// CSV数据 → Drama列表 的转换Provider
final csvDramasProvider = FutureProvider<List<Drama>>((ref) async {
  final csvData = await ref.watch(csvDataProvider.future);

  if (csvData.isEmpty) return [];

  return csvData.map((d) => d.toDrama()).toList();
});

/// CSV数据 → Banner列表 的转换Provider
final csvBannersProvider = FutureProvider<List<BannerItem>>((ref) async {
  final csvData = await ref.watch(csvDataProvider.future);

  if (csvData.isEmpty) return [];

  // 取前5条作为Banner
  return csvData.take(5).map((d) => d.toBannerItem()).toList();
});

/// 解锁状态Provider
/// 跟踪用户解锁的短剧/剧集
final unlockedDramasProvider =
    StateNotifierProvider<UnlockedDramasNotifier, Set<String>>((ref) {
  return UnlockedDramasNotifier();
});

class UnlockedDramasNotifier extends StateNotifier<Set<String>> {
  UnlockedDramasNotifier() : super({}) {
    _loadUnlocked();
  }

  static const _key = 'unlocked_dramas';

  Future<void> _loadUnlocked() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? [];
      state = list.toSet();
    } catch (_) {}
  }

  Future<void> unlock(String dramaId) async {
    if (state.contains(dramaId)) return;

    state = {...state, dramaId};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, state.toList());
    } catch (_) {}
  }

  Future<void> unlockAll() async {
    state = {'*'};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, ['*']);
    } catch (_) {}
  }

  bool isUnlocked(String dramaId) {
    return state.contains('*') || state.contains(dramaId);
  }
}

/// 解锁对话框显示状态
final showUnlockDialogProvider = StateProvider<bool>((ref) => false);

/// 当前解锁的剧集ID
final currentUnlockingDramaProvider = StateProvider<String?>((ref) => null);

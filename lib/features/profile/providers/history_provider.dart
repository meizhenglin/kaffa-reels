import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../recommend/models/drama.dart';

/// 观看历史条目
class HistoryItem {
  final String id;
  final Drama drama;
  final DateTime watchedAt;
  final double progress; // 0.0 ~ 1.0

  const HistoryItem({
    required this.id,
    required this.drama,
    required this.watchedAt,
    required this.progress,
  });

  HistoryItem copyWith({double? progress, DateTime? watchedAt}) {
    return HistoryItem(
      id: id,
      drama: drama,
      watchedAt: watchedAt ?? this.watchedAt,
      progress: progress ?? this.progress,
    );
  }
}

/// 观看历史状态
class HistoryState {
  final List<HistoryItem> items;
  final bool isLoading;
  final bool isEditMode;

  const HistoryState({
    this.items = const [],
    this.isLoading = false,
    this.isEditMode = false,
  });

  bool get isEmpty => items.isEmpty;

  HistoryState copyWith({
    List<HistoryItem>? items,
    bool? isLoading,
    bool? isEditMode,
  }) {
    return HistoryState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      isEditMode: isEditMode ?? this.isEditMode,
    );
  }
}

final historyProvider = StateNotifierProvider<HistoryNotifier, HistoryState>((ref) {
  return HistoryNotifier();
});

class HistoryNotifier extends StateNotifier<HistoryState> {
  HistoryNotifier() : super(const HistoryState(isLoading: false)); // TODO: 接入后端时改为 true 并加载数据

  void addHistory(Drama drama) {
    final id = drama.id;
    final existingIndex = state.items.indexWhere((i) => i.drama.id == id);
    if (existingIndex >= 0) {
      // 更新已有条目
      state = state.copyWith(
        items: [
          state.items[existingIndex].copyWith(watchedAt: DateTime.now()),
          ...state.items.sublist(0, existingIndex),
          ...state.items.sublist(existingIndex + 1),
        ],
      );
    } else {
      state = state.copyWith(
        items: [
          HistoryItem(
            id: id,
            drama: drama,
            watchedAt: DateTime.now(),
            progress: 0,
          ),
          ...state.items,
        ],
      );
    }
  }

  void toggleEditMode() {
    state = state.copyWith(isEditMode: !state.isEditMode);
  }

  void deleteItem(String id) {
    state = state.copyWith(
      items: state.items.where((i) => i.id != id).toList(),
    );
  }

  void deleteSelected(Set<String> ids) {
    state = state.copyWith(
      items: state.items.where((i) => !ids.contains(i.id)).toList(),
    );
  }

  void updateProgress(String id, double progress) {
    state = state.copyWith(
      items: state.items.map((i) {
        if (i.id == id) return i.copyWith(progress: progress);
        return i;
      }).toList(),
    );
  }
}

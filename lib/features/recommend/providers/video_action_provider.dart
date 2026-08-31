import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_provider.dart' show apiServiceProviderRef;

class VideoActionState {
  const VideoActionState({
    this.likeStatus = const {},
    this.collectStatus = const {},
    this.likeCounts = const {},
    this.collectCounts = const {},
    this.pendingLikeIds = const {},
    this.pendingCollectIds = const {},
  });

  final Map<String, bool> likeStatus;
  final Map<String, bool> collectStatus;
  final Map<String, int> likeCounts;
  final Map<String, int> collectCounts;
  final Set<String> pendingLikeIds;
  final Set<String> pendingCollectIds;

  bool isLiked(String videoId, {bool fallback = false}) =>
      likeStatus[videoId] ?? fallback;
  bool isCollected(String videoId, {bool fallback = false}) =>
      collectStatus[videoId] ?? fallback;
  int likeCount(String videoId, {int fallback = 0}) =>
      likeCounts[videoId] ?? fallback;
  int collectCount(String videoId, {int fallback = 0}) =>
      collectCounts[videoId] ?? fallback;
  bool isLikePending(String videoId) => pendingLikeIds.contains(videoId);
  bool isCollectPending(String videoId) => pendingCollectIds.contains(videoId);

  VideoActionState copyWith({
    Map<String, bool>? likeStatus,
    Map<String, bool>? collectStatus,
    Map<String, int>? likeCounts,
    Map<String, int>? collectCounts,
    Set<String>? pendingLikeIds,
    Set<String>? pendingCollectIds,
  }) {
    return VideoActionState(
      likeStatus: likeStatus ?? this.likeStatus,
      collectStatus: collectStatus ?? this.collectStatus,
      likeCounts: likeCounts ?? this.likeCounts,
      collectCounts: collectCounts ?? this.collectCounts,
      pendingLikeIds: pendingLikeIds ?? this.pendingLikeIds,
      pendingCollectIds: pendingCollectIds ?? this.pendingCollectIds,
    );
  }
}

final videoActionProvider =
    StateNotifierProvider<VideoActionNotifier, VideoActionState>((ref) {
      return VideoActionNotifier(ref);
    });

class VideoActionNotifier extends StateNotifier<VideoActionState> {
  VideoActionNotifier(this._ref) : super(const VideoActionState());

  final Ref _ref;

  void syncInitialState({
    required String videoId,
    bool? isLiked,
    bool? isCollected,
    int? likeCount,
    int? collectCount,
    bool overwrite = false,
  }) {
    final nextLikeStatus = Map<String, bool>.from(state.likeStatus);
    final nextCollectStatus = Map<String, bool>.from(state.collectStatus);
    final nextLikeCounts = Map<String, int>.from(state.likeCounts);
    final nextCollectCounts = Map<String, int>.from(state.collectCounts);

    if (isLiked != null &&
        (overwrite || !nextLikeStatus.containsKey(videoId))) {
      nextLikeStatus[videoId] = isLiked;
    }
    if (isCollected != null &&
        (overwrite || !nextCollectStatus.containsKey(videoId))) {
      nextCollectStatus[videoId] = isCollected;
    }
    if (likeCount != null &&
        (overwrite || !nextLikeCounts.containsKey(videoId))) {
      nextLikeCounts[videoId] = likeCount;
    }
    if (collectCount != null &&
        (overwrite || !nextCollectCounts.containsKey(videoId))) {
      nextCollectCounts[videoId] = collectCount;
    }

    state = state.copyWith(
      likeStatus: nextLikeStatus,
      collectStatus: nextCollectStatus,
      likeCounts: nextLikeCounts,
      collectCounts: nextCollectCounts,
    );
  }

  Future<bool> toggleLike({
    required String videoId,
    String? episodesId,
    required bool currentValue,
    required int currentCount,
  }) async {
    if (state.isLikePending(videoId)) return currentValue;

    final nextValue = !currentValue;
    final nextLikeStatus = Map<String, bool>.from(state.likeStatus)
      ..[videoId] = nextValue;
    final nextLikeCounts = Map<String, int>.from(state.likeCounts)
      ..[videoId] = nextValue
          ? currentCount + 1
          : (currentCount > 0 ? currentCount - 1 : 0);
    final nextPendingLikeIds = Set<String>.from(state.pendingLikeIds)
      ..add(videoId);

    state = state.copyWith(
      likeStatus: nextLikeStatus,
      likeCounts: nextLikeCounts,
      pendingLikeIds: nextPendingLikeIds,
    );

    final response = await _ref
        .read(apiServiceProviderRef)
        .setVideoLike(
          videoId: videoId,
          episodesId: episodesId,
          type: nextValue ? 1 : 2,
        );

    final clearedPending = Set<String>.from(state.pendingLikeIds)
      ..remove(videoId);

    if (!response.isSuccess) {
      final rollback = Map<String, bool>.from(state.likeStatus)
        ..[videoId] = currentValue;
      final rollbackCounts = Map<String, int>.from(state.likeCounts)
        ..[videoId] = currentCount;
      state = state.copyWith(
        likeStatus: rollback,
        likeCounts: rollbackCounts,
        pendingLikeIds: clearedPending,
      );
      return currentValue;
    }

    state = state.copyWith(pendingLikeIds: clearedPending);
    return nextValue;
  }

  Future<bool> toggleCollect({
    required String videoId,
    String? episodesId,
    required bool currentValue,
    required int currentCount,
  }) async {
    if (state.isCollectPending(videoId)) return currentValue;

    final nextValue = !currentValue;
    final nextCollectStatus = Map<String, bool>.from(state.collectStatus)
      ..[videoId] = nextValue;
    final nextCollectCounts = Map<String, int>.from(state.collectCounts)
      ..[videoId] = nextValue
          ? currentCount + 1
          : (currentCount > 0 ? currentCount - 1 : 0);
    final nextPendingCollectIds = Set<String>.from(state.pendingCollectIds)
      ..add(videoId);

    state = state.copyWith(
      collectStatus: nextCollectStatus,
      collectCounts: nextCollectCounts,
      pendingCollectIds: nextPendingCollectIds,
    );

    final response = await _ref
        .read(apiServiceProviderRef)
        .setVideoCollect(
          videoId: videoId,
          episodesId: episodesId,
          type: nextValue ? 1 : 2,
        );

    final clearedPending = Set<String>.from(state.pendingCollectIds)
      ..remove(videoId);

    if (!response.isSuccess) {
      final rollback = Map<String, bool>.from(state.collectStatus)
        ..[videoId] = currentValue;
      final rollbackCounts = Map<String, int>.from(state.collectCounts)
        ..[videoId] = currentCount;
      state = state.copyWith(
        collectStatus: rollback,
        collectCounts: rollbackCounts,
        pendingCollectIds: clearedPending,
      );
      return currentValue;
    }

    state = state.copyWith(pendingCollectIds: clearedPending);
    return nextValue;
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../../core/providers/auth_provider.dart' show apiServiceProviderRef;

/// 最近一次观看记录的数据模型
class LastWatchedInfo {
  final String videoId;
  final int episodesId;
  final String videoName;
  final String coverUrl;
  final int watchedEpNum; // 已看到第几集
  final int totalEpisodes;

  LastWatchedInfo({
    required this.videoId,
    required this.episodesId,
    required this.videoName,
    required this.coverUrl,
    required this.watchedEpNum,
    required this.totalEpisodes,
  });

  String get episodeLabel => 'EP.$watchedEpNum / $totalEpisodes';

  bool get hasDisplayableContent =>
      videoId.isNotEmpty && videoName.trim().isNotEmpty && episodesId > 0;

  factory LastWatchedInfo.fromJson(Map<String, dynamic> json) {
    return LastWatchedInfo(
      videoId: (json['videoId'] ?? '').toString(),
      episodesId: (json['episodesId'] is int)
          ? json['episodesId']
          : int.tryParse((json['episodesId'] ?? '0').toString()) ?? 0,
      videoName: json['videoName'] ?? json['title'] ?? '',
      coverUrl:
          json['coverUrl'] ?? json['videoPicture'] ?? json['videoUrl'] ?? '',
      watchedEpNum:
          json['watchedEpNum'] ??
          json['episodesNum'] ??
          (json['episodesId'] is int ? json['episodesId'] : 1),
      totalEpisodes: json['totalEpisodes'] ?? json['videoEpisodes'] ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'episodesId': episodesId,
    'videoName': videoName,
    'coverUrl': coverUrl,
    'watchedEpNum': watchedEpNum,
    'totalEpisodes': totalEpisodes,
  };
}

class LastWatchedState {
  final LastWatchedInfo? info;
  final bool isLoading;
  final String? error;

  const LastWatchedState({this.info, this.isLoading = false, this.error});

  LastWatchedState copyWith({
    LastWatchedInfo? info,
    bool? isLoading,
    String? error,
  }) => LastWatchedState(
    info: info ?? this.info,
    isLoading: isLoading ?? this.isLoading,
    error: error,
  );
}

class LastWatchedNotifier extends StateNotifier<LastWatchedState> {
  LastWatchedNotifier(this._apiService) : super(const LastWatchedState());

  final ApiService _apiService;

  Future<void> load() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final resp = await _apiService.getLastUserViewHistoryOne();
      if (resp.isSuccess && resp.data != null) {
        final info = LastWatchedInfo.fromJson(
          resp.data as Map<String, dynamic>,
        );
        if (info.hasDisplayableContent) {
          state = LastWatchedState(info: info, isLoading: false);
        } else {
          state = const LastWatchedState(isLoading: false);
        }
      } else {
        state = const LastWatchedState(isLoading: false);
      }
    } catch (e) {
      state = LastWatchedState(isLoading: false, error: e.toString());
    }
  }

  void clear() {
    state = const LastWatchedState();
  }
}

final lastWatchedProvider =
    StateNotifierProvider<LastWatchedNotifier, LastWatchedState>(
      (ref) => LastWatchedNotifier(ref.read(apiServiceProviderRef)),
    );

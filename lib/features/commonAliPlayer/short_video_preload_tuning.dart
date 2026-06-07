class ShortVideoPreloadTuning {
  const ShortVideoPreloadTuning._();

  static const int watchMediaPreloadNearBufferDurationMs = 20000;
  static const int watchMediaPreloadFarBufferDurationMs = 10000;
  static const List<int> watchMediaPreloadNearOffsets = <int>[1, 2];
  static const List<int> watchMediaPreloadFarOffsets = <int>[3, 4];

  static const int mediaPreloadBufferDurationMs = 12000;
  static const List<int> mediaPreloadWindowOffsets = <int>[1, 2, 3];
  static const int mediaPreloadMaxPreparedPlayers = 4;
  static const Duration mediaPreloadIdleReleaseAfter = Duration(seconds: 12);

  static const int commonCoverPreloadLeftWindowSize = 5;
  static const int commonCoverPreloadRightWindowSize = 15;

  static const int recommendCoverPreloadLeftWindowSize = 3;
  static const int recommendCoverPreloadRightWindowSize = 10;

  static const List<int> pagePlayablePrefetchOffsets = <int>[0, 1, 2, 3, 4];
}

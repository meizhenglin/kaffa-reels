// // Video information data class — matches API response from /api/episodes/recommendIndex
// class VideoInfo {
//   final int id;           // episodesId
//   final int videoId;      // videoId
//   final String videoUrl;  // episodesUrl (may be invalid, use getEpisodeInfo for real URL)
//   final String? coverUrl; // videoPicture
//   final String? videoUrlOne;   // vipEpisodesUrl1080
//   final String? videoUrlTwo;   // vipEpisodesUrl1440
//   final int serialNum;    // episodesNum
//   final int longTime;     // 0 (not in API)
//   final int collectNum;   // 0 (not in API)
//   final int likeNum;      // thumbsNum
//   final int shareNum;     // 0 (not in API)
//   final int isCollect;    // isChasing
//   final int isLike;       // isLike
//   final int totalEpisodes; // videoEpisodes
//   final String title;     // videoName
//   final String content;   // video content / introduction / description
//   final int isCanPlay;   // isCanPlay（0=需解锁，1=可播放）
//   final int? unlockPrice;      // 单集解锁价格（K币）
//   final int? dramaUnlockPrice; // 整剧解锁价格（K币）
//   final int? episodeGoodsId;   // 单集解锁商品ID
//   final int? dramaGoodsId;     // 整剧解锁商品ID

//   const VideoInfo({
//     required this.id,
//     required this.videoId,
//     required this.videoUrl,
//     this.coverUrl,
//     this.videoUrlOne,
//     this.videoUrlTwo,
//     this.serialNum = 0,
//     this.longTime = 0,
//     this.collectNum = 0,
//     this.likeNum = 0,
//     this.shareNum = 0,
//     this.isCollect = 0,
//     this.isLike = 0,
//     this.totalEpisodes = 0,
//     this.title = '',
//     this.content = '',
//     this.isCanPlay = 1,
//     this.unlockPrice,
//     this.dramaUnlockPrice,
//     this.episodeGoodsId,
//     this.dramaGoodsId,
//   });

//   factory VideoInfo.fromJson(Map<String, dynamic> json) {
//     return VideoInfo(
//       id: (json['id'] as int?) ?? (json['episodesId'] as int?) ?? 0,
//       videoId: (json['videoId'] as int?) ?? 0,
//       videoUrl: (json['videoUrl'] as String?) ?? (json['url'] as String?) ?? (json['episodesUrl'] as String?) ?? '',
//       coverUrl: (json['coverUrl'] as String?) ?? (json['videoPicture'] as String?),
//       videoUrlOne: (json['videoUrlOne'] as String?) ?? (json['vipEpisodesUrl1080'] as String?),
//       videoUrlTwo: (json['videoUrlTwo'] as String?) ?? (json['vipEpisodesUrl1440'] as String?),
//       serialNum: (json['serialNum'] as int?) ?? (json['episodesNum'] as int?) ?? 0,
//       longTime: (json['longTime'] as int?) ?? 0,
//       collectNum: (json['collectNum'] as int?) ?? 0,
//       likeNum: (json['likeNum'] as int?) ?? (json['thumbsNum'] as int?) ?? 0,
//       shareNum: (json['shareNum'] as int?) ?? 0,
//       isCollect: (json['isCollect'] as int?) ?? (json['isChasing'] as int?) ?? 0,
//       isLike: (json['isLike'] as int?) ?? 0,
//       totalEpisodes: (json['totalEpisodes'] as int?) ?? (json['videoEpisodes'] as int?) ?? 0,
//       title: (json['title'] as String?) ?? (json['videoName'] as String?) ?? '',
//       content: (json['content'] as String?) ??
//           (json['description'] as String?) ??
//           (json['videoIntroduce'] as String?) ??
//           (json['videoDesc'] as String?) ??
//           (json['videoDescription'] as String?) ??
//           (json['introduction'] as String?) ??
//           (json['brief'] as String?) ??
//           '',
//       isCanPlay: (json['isCanPlay'] as int?) ?? 1,
//       unlockPrice: json['unlockPrice'] as int? ?? json['unlockNum'] as int?,
//       dramaUnlockPrice: json['dramaUnlockPrice'] as int? ?? json['allPrice'] as int?,
//       episodeGoodsId: json['episodeGoodsId'] as int? ?? json['goodsId'] as int?,
//       dramaGoodsId: json['dramaGoodsId'] as int?,
//     );
//   }

//   Map<String, dynamic> toJson() => {
//         'id': id,
//         'videoId': videoId,
//         'videoUrl': videoUrl,
//         'coverUrl': coverUrl,
//         'videoUrlOne': videoUrlOne,
//         'videoUrlTwo': videoUrlTwo,
//         'serialNum': serialNum,
//         'longTime': longTime,
//         'collectNum': collectNum,
//         'likeNum': likeNum,
//         'shareNum': shareNum,
//         'isCollect': isCollect,
//         'isLike': isLike,
//         'totalEpisodes': totalEpisodes,
//         'title': title,
//         'content': content,
//         'isCanPlay': isCanPlay,
//         'unlockPrice': unlockPrice,
//         'dramaUnlockPrice': dramaUnlockPrice,
//         'episodeGoodsId': episodeGoodsId,
//         'dramaGoodsId': dramaGoodsId,
//       };

//   VideoInfo copyWith({
//     int? id,
//     int? videoId,
//     String? videoUrl,
//     String? coverUrl,
//     String? videoUrlOne,
//     String? videoUrlTwo,
//     int? serialNum,
//     int? longTime,
//     int? collectNum,
//     int? likeNum,
//     int? shareNum,
//     int? isCollect,
//     int? isLike,
//     int? totalEpisodes,
//     String? title,
//     String? content,
//     int? isCanPlay,
//     int? unlockPrice,
//     int? dramaUnlockPrice,
//     int? episodeGoodsId,
//     int? dramaGoodsId,
//   }) {
//     return VideoInfo(
//       id: id ?? this.id,
//       videoId: videoId ?? this.videoId,
//       videoUrl: videoUrl ?? this.videoUrl,
//       coverUrl: coverUrl ?? this.coverUrl,
//       videoUrlOne: videoUrlOne ?? this.videoUrlOne,
//       videoUrlTwo: videoUrlTwo ?? this.videoUrlTwo,
//       serialNum: serialNum ?? this.serialNum,
//       longTime: longTime ?? this.longTime,
//       collectNum: collectNum ?? this.collectNum,
//       likeNum: likeNum ?? this.likeNum,
//       shareNum: shareNum ?? this.shareNum,
//       isCollect: isCollect ?? this.isCollect,
//       isLike: isLike ?? this.isLike,
//       totalEpisodes: totalEpisodes ?? this.totalEpisodes,
//       title: title ?? this.title,
//       content: content ?? this.content,
//       isCanPlay: isCanPlay ?? this.isCanPlay,
//       unlockPrice: unlockPrice ?? this.unlockPrice,
//       dramaUnlockPrice: dramaUnlockPrice ?? this.dramaUnlockPrice,
//       episodeGoodsId: episodeGoodsId ?? this.episodeGoodsId,
//       dramaGoodsId: dramaGoodsId ?? this.dramaGoodsId,
//     );
//   }

//   @override
//   String toString() => 'VideoInfo(id: $id, videoId: $videoId, title: $title)';
// }

// Video information data class — matches API response from /api/episodes/recommendIndex

class VideoInfo {
  final int id; // episodesId
  final int videoId; // videoId
  final String
  videoUrl; // episodesUrl (may be invalid, use getEpisodeInfo for real URL)
  final String? coverUrl; // videoPicture
  final String? videoUrlOne; // vipEpisodesUrl1080
  final String? videoUrlTwo; // vipEpisodesUrl1440
  final int serialNum; // episodesNum
  final int longTime; // 0 (not in API)
  final int collectNum; // 0 (not in API)
  final int likeNum; // thumbsNum
  final int shareNum; // 0 (not in API)
  final int isCollect; // isChasing
  final int isLike; // isLike
  final int totalEpisodes; // videoEpisodes
  final String title; // videoName
  final String content; // video content / introduction / description
  final int isCanPlay; // isCanPlay（0=需解锁，1=可播放）
  final int? unlockPrice; // 单集解锁价格（K币）
  final int? dramaUnlockPrice; // 整剧解锁价格（K币）
  final int? episodeGoodsId; // 单集解锁商品ID
  final int? dramaGoodsId; // 整剧解锁商品ID

  const VideoInfo({
    required this.id,
    required this.videoId,
    required this.videoUrl,
    this.coverUrl,
    this.videoUrlOne,
    this.videoUrlTwo,
    this.serialNum = 0,
    this.longTime = 0,
    this.collectNum = 0,
    this.likeNum = 0,
    this.shareNum = 0,
    this.isCollect = 0,
    this.isLike = 0,
    this.totalEpisodes = 0,
    this.title = '',
    this.content = '',
    this.isCanPlay = 1,
    this.unlockPrice,
    this.dramaUnlockPrice,
    this.episodeGoodsId,
    this.dramaGoodsId,
  });

  static int _readInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) {
        final parsed = int.tryParse(value.trim());
        if (parsed != null) return parsed;
      }
    }
    return 0;
  }

  static int? _readNullableInt(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (!json.containsKey(key) || json[key] == null) continue;
      return _readInt(json, [key]);
    }
    return null;
  }

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    final rawCollectNum = _readInt(json, const [
      'collectNum',
      'collectCount',
      'chasingNum',
      'chaseNum',
      'favoritesNum',
    ]);
    final rawLikeNum = _readInt(json, const [
      'likeNum',
      'thumbsNum',
      'likeCount',
      'thumbsUpNum',
      'praiseNum',
    ]);
    final isCollect = _readInt(json, const ['isCollect', 'isChasing']);
    final isLike = _readInt(json, const ['isLike']);

    return VideoInfo(
      id: _readInt(json, const ['id', 'episodesId']),
      videoId: _readInt(json, const ['videoId']),
      videoUrl:
          (json['videoUrl'] ?? json['url'] ?? json['episodesUrl'])
              ?.toString() ??
          '',
      coverUrl: (json['coverUrl'] ?? json['videoPicture'])?.toString(),
      videoUrlOne: (json['videoUrlOne'] ?? json['vipEpisodesUrl1080'])
          ?.toString(),
      videoUrlTwo: (json['videoUrlTwo'] ?? json['vipEpisodesUrl1440'])
          ?.toString(),
      serialNum: _readInt(json, const ['serialNum', 'episodesNum']),
      longTime: _readInt(json, const ['longTime']),
      collectNum: rawCollectNum,
      likeNum: rawLikeNum,
      shareNum: _readInt(json, const ['shareNum']),
      isCollect: isCollect,
      isLike: isLike,
      totalEpisodes: _readInt(json, const ['totalEpisodes', 'videoEpisodes']),
      title: (json['title'] ?? json['videoName'])?.toString() ?? '',
      content:
          (json['content'] as String?) ??
          (json['description'] as String?) ??
          (json['videoIntroduce'] as String?) ??
          (json['videoDesc'] as String?) ??
          (json['videoDescription'] as String?) ??
          (json['introduction'] as String?) ??
          (json['brief'] as String?) ??
          '',
      isCanPlay: _readNullableInt(json, const ['isCanPlay']) ?? 1,
      unlockPrice: _readNullableInt(json, const ['unlockPrice', 'unlockNum']),
      dramaUnlockPrice: _readNullableInt(json, const [
        'dramaUnlockPrice',
        'allPrice',
      ]),
      episodeGoodsId: _readNullableInt(json, const [
        'episodeGoodsId',
        'goodsId',
      ]),
      dramaGoodsId: _readNullableInt(json, const ['dramaGoodsId']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'videoId': videoId,
    'videoUrl': videoUrl,
    'coverUrl': coverUrl,
    'videoUrlOne': videoUrlOne,
    'videoUrlTwo': videoUrlTwo,
    'serialNum': serialNum,
    'longTime': longTime,
    'collectNum': collectNum,
    'likeNum': likeNum,
    'shareNum': shareNum,
    'isCollect': isCollect,
    'isLike': isLike,
    'totalEpisodes': totalEpisodes,
    'title': title,
    'content': content,
    'isCanPlay': isCanPlay,
    'unlockPrice': unlockPrice,
    'dramaUnlockPrice': dramaUnlockPrice,
    'episodeGoodsId': episodeGoodsId,
    'dramaGoodsId': dramaGoodsId,
  };

  VideoInfo copyWith({
    int? id,
    int? videoId,
    String? videoUrl,
    String? coverUrl,
    String? videoUrlOne,
    String? videoUrlTwo,
    int? serialNum,
    int? longTime,
    int? collectNum,
    int? likeNum,
    int? shareNum,
    int? isCollect,
    int? isLike,
    int? totalEpisodes,
    String? title,
    String? content,
    int? isCanPlay,
    int? unlockPrice,
    int? dramaUnlockPrice,
    int? episodeGoodsId,
    int? dramaGoodsId,
  }) {
    return VideoInfo(
      id: id ?? this.id,
      videoId: videoId ?? this.videoId,
      videoUrl: videoUrl ?? this.videoUrl,
      coverUrl: coverUrl ?? this.coverUrl,
      videoUrlOne: videoUrlOne ?? this.videoUrlOne,
      videoUrlTwo: videoUrlTwo ?? this.videoUrlTwo,
      serialNum: serialNum ?? this.serialNum,
      longTime: longTime ?? this.longTime,
      collectNum: collectNum ?? this.collectNum,
      likeNum: likeNum ?? this.likeNum,
      shareNum: shareNum ?? this.shareNum,
      isCollect: isCollect ?? this.isCollect,
      isLike: isLike ?? this.isLike,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      title: title ?? this.title,
      content: content ?? this.content,
      isCanPlay: isCanPlay ?? this.isCanPlay,
      unlockPrice: unlockPrice ?? this.unlockPrice,
      dramaUnlockPrice: dramaUnlockPrice ?? this.dramaUnlockPrice,
      episodeGoodsId: episodeGoodsId ?? this.episodeGoodsId,
      dramaGoodsId: dramaGoodsId ?? this.dramaGoodsId,
    );
  }

  @override
  String toString() => 'VideoInfo(id: $id, videoId: $videoId, title: $title)';
}

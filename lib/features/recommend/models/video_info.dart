// Video information data class — matches API response from /api/episodes/recommendIndex
class VideoInfo {
  final int id;           // episodesId
  final int videoId;      // videoId
  final String videoUrl;  // episodesUrl
  final String? coverUrl; // videoPicture
  final String? videoUrlOne;   // vipEpisodesUrl1080
  final String? videoUrlTwo;   // vipEpisodesUrl1440
  final int serialNum;    // episodesNum
  final int longTime;     // 0 (not in API)
  final int collectNum;   // 0 (not in API)
  final int likeNum;      // thumbsNum
  final int shareNum;     // 0 (not in API)
  final int isCollect;    // isChasing
  final int isLike;       // isLike
  final int totalEpisodes; // videoEpisodes
  final String title;     // videoName

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
  });

  factory VideoInfo.fromJson(Map<String, dynamic> json) {
    return VideoInfo(
      id: json['episodesId'] as int? ?? 0,
      videoId: json['videoId'] as int? ?? 0,
      videoUrl: json['episodesUrl'] as String? ?? '',
      coverUrl: json['videoPicture'] as String?,
      videoUrlOne: json['vipEpisodesUrl1080'] as String?,
      videoUrlTwo: json['vipEpisodesUrl1440'] as String?,
      serialNum: json['episodesNum'] as int? ?? 0,
      longTime: json['longTime'] as int? ?? 0,
      collectNum: json['collectNum'] as int? ?? 0,
      likeNum: json['thumbsNum'] as int? ?? 0,
      shareNum: json['shareNum'] as int? ?? 0,
      isCollect: json['isChasing'] as int? ?? 0,
      isLike: json['isLike'] as int? ?? 0,
      totalEpisodes: json['videoEpisodes'] as int? ?? 0,
      title: json['videoName'] as String? ?? '',
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
    );
  }

  @override
  String toString() => 'VideoInfo(id: $id, videoId: $videoId, title: $title)';
}

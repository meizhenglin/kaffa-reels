// Video information data class — matches API response from /api/video/recommendVideo
class VideoInfo {
  final int id;
  final int videoId;
  final String videoUrl;
  final String? videoUrlOne;
  final String? videoUrlTwo;
  final int serialNum;
  final int longTime;
  final int collectNum;
  final int likeNum;
  final int shareNum;
  final int isCollect;
  final int isLike;
  final int totalEpisodes;
  final String title;

  const VideoInfo({
    required this.id,
    required this.videoId,
    required this.videoUrl,
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
      id: json['id'] as int? ?? 0,
      videoId: json['videoId'] as int? ?? 0,
      videoUrl: json['videoUrl'] as String? ?? '',
      videoUrlOne: json['videoUrlOne'] as String?,
      videoUrlTwo: json['videoUrlTwo'] as String?,
      serialNum: json['serialNum'] as int? ?? 0,
      longTime: json['longTime'] as int? ?? 0,
      collectNum: json['collectNum'] as int? ?? 0,
      likeNum: json['likeNum'] as int? ?? 0,
      shareNum: json['shareNum'] as int? ?? 0,
      isCollect: json['isCollect'] as int? ?? 0,
      isLike: json['isLike'] as int? ?? 0,
      totalEpisodes: json['totalEpisodes'] as int? ?? 0,
      title: json['title'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'videoId': videoId,
        'videoUrl': videoUrl,
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

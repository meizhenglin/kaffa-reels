// Drama information data class (copied from aliplayer_widget example)
import '../models/video_info.dart';

class DramaInfo {
  final String title;
  final List<VideoInfo> dramas;

  const DramaInfo({required this.title, required this.dramas});

  factory DramaInfo.fromJson(Map<String, dynamic> json) {
    return DramaInfo(
      title: json['title'] as String? ?? '',
      dramas: (json['dramas'] as List<dynamic>?)
              ?.map((v) => VideoInfo.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

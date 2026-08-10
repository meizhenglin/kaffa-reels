// Stub for non-web platforms
// The actual implementation is in player_web.dart

export '../../components/common_video_player.dart' show CommonEpisode;

class WebFullscreenPlayer extends StatelessWidget {
  const WebFullscreenPlayer({super.key});
  
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

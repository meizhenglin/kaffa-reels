// Stub for aliplayer on web - types only, no implementation
// This is imported when building for web to avoid MissingPluginException

// Stub types for AliPlayerWidget
class AliPlayerWidget extends StatelessWidget {
  const AliPlayerWidget(this.controller, {super.key, this.slotBuilders, this.hiddenSlotElements});
  final AliPlayerWidgetController controller;
  final Map<Type, Widget Function(BuildContext context)>? slotBuilders;
  final Map<Type, Set<String>>? hiddenSlotElements;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class AliPlayerWidgetController {}

class AliPlayerWidgetData {
  AliPlayerWidgetData({required SceneType sceneType, required VideoSource videoSource, bool autoPlay = false});
  SceneType sceneType = SceneType.listPlayer;
  VideoSource videoSource = UrlVideoSource('');
  bool autoPlay = false;
}

enum SceneType { listPlayer, livePlayer, vodPlayer }

abstract class VideoSource {}
class UrlVideoSource extends VideoSource {
  UrlVideoSource(this.url);
  String url = '';
}

class AliPlayerView extends StatelessWidget {
  const AliPlayerView({super.key, required this.onCreated, this.x = 0, this.y = 0, this.width = 0, this.height = 0, this.aliPlayerViewType});
  final void Function(int viewId) onCreated;
  final double x, y, width, height;
  final AliPlayerViewTypeForAndroid? aliPlayerViewType;
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

enum AliPlayerViewTypeForAndroid { textureview, surfaceview }

enum SlotType { topBar }

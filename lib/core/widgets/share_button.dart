import 'package:flutter/material.dart';

import '../../features/recommend/models/video_info.dart';
import '../../services/share_service.dart';

/// 通用分享参数。业务方在不能直接用 [VideoInfo] 时（如分享排行榜、福利、纯链接等）
/// 可以用这个直接传。
class ShareContent {
  const ShareContent({
    required this.title,
    this.text,
    this.url,
    this.imageUrl,
  });

  final String title;
  final String? text;
  final String? url;
  final String? imageUrl;

  /// 从 [VideoInfo] 构造默认分享参数。
  /// [shareUrlBuilder] 允许业务方定制短剧页 URL（默认 `https://qahwatv.com/video/{id}`）。
  factory ShareContent.fromVideo(
    VideoInfo video, {
    String Function(VideoInfo)? shareUrlBuilder,
    String? hashtag,
  }) {
    final url = (shareUrlBuilder ?? _defaultShareUrlBuilder)(video);
    final buffer = StringBuffer()
      ..writeln('🎬 ${video.title}')
      ..writeln()
      ..writeln(url);
    if (hashtag != null && hashtag.isNotEmpty) {
      buffer
        ..writeln()
        ..write(hashtag);
    }
    return ShareContent(
      title: video.title,
      text: buffer.toString(),
      url: url,
      imageUrl: video.coverUrl,
    );
  }

  static String _defaultShareUrlBuilder(VideoInfo video) =>
      'https://qahwatv.com/video/${video.videoId}';
}

/// 显示分享平台选择 sheet，命中后调用 [ShareService.share]。
/// 返回用户最终选择的平台 id，未选则返回 null。
Future<String?> showShareSheet(BuildContext context, ShareContent content) async {
  final platform = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                child: Text(
                  'Share to',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              ..._kShareOptions.map(
                (o) => ListTile(
                  leading: const Icon(Icons.share, color: Colors.white70),
                  title: Text(
                    o.label,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () => Navigator.of(ctx).pop(o.id),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  if (platform == null) return null;
  ShareService.share(
    platformName: platform,
    title: content.title,
    text: content.text,
    url: content.url,
    imageUrl: content.imageUrl,
  );
  return platform;
}

typedef ShareContentBuilder = ShareContent Function();

/// 可复用的分享组件。两类用法：
///
/// 1. 视频场景（最常用），传入 [VideoInfo]：
/// ```dart
/// ShareButton.video(
///   videoInfo: videoInfo,
///   icon: const Icon(Icons.share),
/// )
/// ```
///
/// 2. 自定义场景，传入 [ShareContent]：
/// ```dart
/// ShareButton(
///   content: ShareContent(title: '...', url: '...'),
/// )
/// ```
class ShareButton extends StatelessWidget {
  const ShareButton({
    super.key,
    this.content,
    this.icon,
    this.label,
    this.tooltip,
    this.iconColor,
    this.iconSize = 24,
    this.dense = false,
    this.onShared,
    VideoInfo? videoInfo,
    String Function(VideoInfo)? shareUrlBuilder,
    String? hashtag,
  })  : _videoInfo = videoInfo,
        _shareUrlBuilder = shareUrlBuilder,
        _hashtag = hashtag;

  /// 视频快捷构造：内部基于 [VideoInfo] 构造 [ShareContent]。
  const ShareButton.video({
    super.key,
    required VideoInfo videoInfo,
    String Function(VideoInfo)? shareUrlBuilder,
    String? hashtag,
    this.icon,
    this.label,
    this.tooltip,
    this.iconColor,
    this.iconSize = 24,
    this.dense = false,
    this.onShared,
  })  : content = null,
        _videoInfo = videoInfo,
        _shareUrlBuilder = shareUrlBuilder,
        _hashtag = hashtag;

  final ShareContent? content;
  final Icon? icon;
  final String? label;
  final String? tooltip;
  final Color? iconColor;
  final double iconSize;
  final bool dense;
  final void Function(String platform)? onShared;

  // 仅用于 [ShareButton.video] 构造时保存参数。
  final VideoInfo? _videoInfo;
  final String Function(VideoInfo)? _shareUrlBuilder;
  final String? _hashtag;

  ShareContent _resolveContent() {
    if (content != null) return content!;
    return ShareContent.fromVideo(
      _videoInfo!,
      shareUrlBuilder: _shareUrlBuilder,
      hashtag: _hashtag,
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedIcon = icon ?? const Icon(Icons.share_outlined);
    return Builder(
      builder: (ctx) {
        Future<void> open() async {
          final platform = await showShareSheet(ctx, _resolveContent());
          if (platform != null) onShared?.call(platform);
        }

        if (label != null) {
          return TextButton.icon(
            onPressed: open,
            icon: Icon(resolvedIcon.icon, color: iconColor, size: iconSize),
            label: Text(label!),
            style: dense ? TextButton.styleFrom(padding: EdgeInsets.zero) : null,
          );
        }
        if (tooltip != null) {
          return IconButton(
            onPressed: open,
            tooltip: tooltip,
            icon: Icon(resolvedIcon.icon, color: iconColor, size: iconSize),
            visualDensity: dense ? VisualDensity.compact : null,
          );
        }
        return InkResponse(
          onTap: open,
          radius: iconSize,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(resolvedIcon.icon, color: iconColor, size: iconSize),
          ),
        );
      },
    );
  }
}

class _ShareOption {
  const _ShareOption(this.id, this.label);
  final String id;
  final String label;
}

const List<_ShareOption> _kShareOptions = [
  _ShareOption('facebook', 'Facebook'),
  _ShareOption('twitter', 'Twitter / X'),
  _ShareOption('whatsapp', 'WhatsApp'),
  _ShareOption('instagram', 'Instagram'),
  _ShareOption('linkedin', 'LinkedIn'),
  _ShareOption('telegram', 'Telegram'),
  _ShareOption('line', 'Line'),
];


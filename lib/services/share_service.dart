import 'package:sharesdk_plugin/sharesdk_plugin.dart';

class ShareService {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    _initialized = true;

    try {
      final register = ShareSDKRegister();
      register.setupFacebook(
        '1869879543763549',
        '0140b1faea8a36984552693d00b5592a',
        'https://qahwatv.com',
      );
      register.setupTwitter(
        'ZUV2bEZaNWtVYmFPUTljeDZhUzc6MTpjaQ',
        'TcZfOscMGrfbMwt84ceA7goYGYlZ173mKFHlurgxkco0ymOu3z',
        'https://qahwatv.com/twitter/callback',
      );
      SharesdkPlugin.regist(register);
    } catch (e) {
      print('[ShareService] init failed: $e');
    }
  }

  static void share({
    required String platformName,
    required String title,
    String? text,
    String? url,
    String? imageUrl,
  }) {
    try {
      final platform = _getPlatform(platformName);
      if (platform == null) {
        print('[ShareService] unknown platform: $platformName');
        return;
      }

      final params = SSDKMap();
      params.setGeneral(
        title,
        text ?? '',
        imageUrl == null ? null : [imageUrl],
        imageUrl ?? '',
        '',
        url ?? '',
        '',
        '',
        '',
        '',
        SSDKContentTypes.auto,
      );

      SharesdkPlugin.share(platform, params, (state, userData, contentEntity, error) {
        print('[ShareService] share $platformName state=$state err=${error.code}');
      });
    } catch (e) {
      print('[ShareService] share failed: $e');
    }
  }

  static ShareSDKPlatform? _getPlatform(String name) {
    switch (name.toLowerCase()) {
      case 'facebook':
        return ShareSDKPlatforms.facebook;
      case 'twitter':
        return ShareSDKPlatforms.twitter;
      case 'sina':
      case 'weibo':
        return ShareSDKPlatforms.sina;
      case 'instagram':
        return ShareSDKPlatforms.instagram;
      case 'whatsapp':
        return ShareSDKPlatforms.whatsApp;
      case 'linkedin':
        return ShareSDKPlatforms.linkedIn;
      case 'telegram':
        return ShareSDKPlatforms.telegram;
      case 'line':
        return ShareSDKPlatforms.line;
      case 'kakaotalk':
        return ShareSDKPlatforms.kakaoTalk;
      default:
        return null;
    }
  }
}
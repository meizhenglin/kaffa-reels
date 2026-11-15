import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Web 端 HLS 预热：把「playlist + 首分片」提前灌进**浏览器 HTTP 缓存**。
///
/// 【为什么 web 上必须换一套做法】
/// 原生端（ExoPlayer / AVPlayer）的预取只能靠"再开一个播放器实例静音播到
/// 有缓冲"，因为 Dart 侧下载的字节播放器用不上。web 上正好相反：
/// `<video>` 走的就是浏览器网络栈，**和 `fetch()` 共享 HTTP 缓存**。
///
/// 而现在的 web 预热其实是无效的：它创建离屏 `<video>` 然后
/// `setVolume(0) + play()`，但 video_player_web 只设 `volume = 0`、
/// 不设 `muted`，Chrome 的自动播放策略会直接抛 `NotAllowedError`
///（静音自动播放放行的是 `muted` 属性，不是音量为 0），异常被
/// `_createController` 的 catch 吞掉 —— 用户滑过去时依然是冷启动。
///
/// 【为什么这里可行】实测当前 CDN：
/// - `.ts` 分片：`Cache-Control: max-age=2592000`（30 天）+ `Access-Control-Allow-Origin: *`
/// - `.m3u8`：`no-cache` + ETag（每次 304 校验，几百字节，可忽略）
/// 所以一次 GET 就能让后续 `<video>` 的请求走本地缓存，起播不再等跨境 RTT。
class HlsPrefetcher {
  HlsPrefetcher._();

  /// 预热几个分片。
  ///
  /// 1 个就够：实测分片 1.93MB / 5s，一个分片已经超过"起播所需缓冲"；
  /// 再多就是明抢当前正在播的那一集的带宽。
  static const int _defaultSegments = 1;

  /// 已预热 URL 的记忆上限（防止长列表里无限增长）。
  static const int _cacheEntries = 24;

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      responseType: ResponseType.plain,
      validateStatus: (code) => code != null && code >= 200 && code < 300,
    ),
  );

  /// LRU：只记录"已经预热过"，不存字节（字节交给浏览器缓存）。
  static final LinkedHashSet<String> _warmed = LinkedHashSet<String>();
  static final Set<String> _inflight = <String>{};

  /// master playlist → 已选定的 media playlist（按清晰度分别缓存）。
  static final Map<String, String> _renditions = <String, String>{};

  static bool get isSupported => kIsWeb;

  /// CDN 的单码率媒体清单命名（实测所有资产一致）：
  /// `xxx_0.m3u8`=480p、`xxx_1.m3u8`=720p、`xxx_2.m3u8`=1080p。
  static final RegExp _numberedMediaPlaylist = RegExp(r'_\d+\.m3u8$');

  static String _renditionKey(String url, String quality) => '$quality|$url';

  /// 同步取已解析的播放地址（命中缓存时用，避免把一次 RTT 加到起播路径上）。
  static String? cachedRendition(
    String playlistUrl, {
    required String quality,
  }) {
    final url = playlistUrl.trim();
    if (url.isEmpty) return null;
    return _renditions[_renditionKey(url, quality)];
  }

  /// 把 master playlist 解析成**指定清晰度**的 media playlist。
  ///
  /// 【为什么必须要做这一步】后端返回的是多码率 master（实测同一集）：
  ///
  /// | rendition | 分辨率     | 码率                 | 首分片 403KB/1.70MB/2.13MB |
  /// |-----------|------------|----------------------|-----------------------------|
  /// | `_0`      | 270x480    | 831 kbps             | 实测下载 0.78s              |
  /// | `_1`      | 720x1280   | 峰值 4.39M/均值 3.35M | 实测下载 9.8s               |
  /// | `_2`      | 1080x1920  | 峰值 9.59M/均值 7.46M | 实测下载 12.6s+             |
  ///
  /// 直接把 master 丢给 `<video>`，浏览器 ABR 会自己挑 `_1`/`_2`，
  /// 首帧要等 10~50 秒 —— 而且 UI 上明明写着 "480P"，用户选了也没用。
  /// 这里按用户选的清晰度挑定一路，播放器就只会去下那一路的字节。
  static Future<String> resolveRendition(
    String playlistUrl, {
    required String quality,
  }) async {
    final url = playlistUrl.trim();
    if (url.isEmpty) return url;
    final key = _renditionKey(url, quality);
    final cached = _renditions[key];
    if (cached != null) return cached;
    // 【命名捷径】后端给的地址几乎都是 `xxx_N.m3u8` 单码率媒体清单。
    // 原流程要先下载它才能"发现"没有 #EXT-X-STREAM-INF，再去下载同级
    // master —— 第一趟纯属浪费，每次冷 init/预热多付一次跨境 RTT
    //（实测 rendition cost 509~917ms 里大半是它）。按命名直接跳到
    // master 选档；选档失败（个别资产没有 master）再走原路径兜底。
    if (_numberedMediaPlaylist.hasMatch(url)) {
      final reselected = await _reselectFromMaster(url, quality);
      if (reselected != null) {
        _rememberRendition(key, reselected);
        return reselected;
      }
    }
    try {
      final text = (await _dio.get<String>(url)).data ?? '';
      if (!text.contains('#EXT-X-STREAM-INF')) {
        // 【输入已是 media playlist，所有平台都要重新定档】后端部分集
        // 直接给某一码率的媒体清单（实测 480P 时拿到 `_1`=720x1280，
        // 首分片 1.70MB / 跨境下载 9.8s）。此时**没有任何 ABR 可言**——
        // 原生 ExoPlayer 拿到单码率清单也一样在原样播高码率。
        // 同级目录必有 master `index.m3u8`（所有实测资产都存在），
        // 用它按清晰度重选。
        final reselected = await _reselectFromMaster(url, quality);
        _rememberRendition(key, reselected ?? url);
        return reselected ?? url;
      }
      // 【master playlist 分平台】web 的浏览器 ABR 会挑 720p/1080p，
      // 必须按用户选的清晰度锁死；原生 ExoPlayer 有真 ABR，交给它
      // 按带宽自适应，不干预。
      if (!kIsWeb) return url;
      final picked = _pickVariant(text, quality);
      if (picked == null) return url;
      final resolved = _resolveUri(url, picked);
      _rememberRendition(key, resolved);
      debugPrint(
        '[HlsPrefetcher] rendition quality=$quality -> ${resolved.split('/').last}',
      );
      return resolved;
    } catch (e) {
      debugPrint('[HlsPrefetcher] resolveRendition failed url=$url error=$e');
      return url;
    }
  }

  /// 后端直接给了媒体清单（如 `xxx_1.m3u8`=720p）时，从同级
  /// `index.m3u8` 的 master 里按清晰度重新挑一路。任何一步失败都
  /// 返回 null，调用方回退用原地址——预取/起播零影响。
  static Future<String?> _reselectFromMaster(
    String mediaPlaylistUrl,
    String quality,
  ) async {
    try {
      final lastSlash = mediaPlaylistUrl.lastIndexOf('/');
      if (lastSlash <= 0) return null;
      final masterUrl = '${mediaPlaylistUrl.substring(0, lastSlash)}/index.m3u8';
      final text = (await _dio.get<String>(masterUrl)).data ?? '';
      if (!text.contains('#EXT-X-STREAM-INF')) {
        return _probeDefaultVariant(mediaPlaylistUrl, quality);
      }
      final picked = _pickVariant(text, quality);
      if (picked == null) return null;
      final resolved = _resolveUri(masterUrl, picked);
      debugPrint(
        '[HlsPrefetcher] reselect quality=$quality from=${mediaPlaylistUrl.split('/').last} '
        '-> ${resolved.split('/').last}',
      );
      return resolved;
    } catch (_) {
      // master 不存在（实测个别资产 404，rendition 白等 3s 后回退 720p）：
      // 按命名约定探测 `_0` 兜底，别把用户摔回 720p。
      return _probeDefaultVariant(mediaPlaylistUrl, quality);
    }
  }

  /// master 缺失时的最后兜底：按 CDN 命名约定直接探测 `_0.m3u8`
  ///（实测全部资产 `_0`=270x480）。只对 480P 生效，其余清晰度
  /// 无法从命名推断，返回 null 走原地址。
  static Future<String?> _probeDefaultVariant(
    String mediaPlaylistUrl,
    String quality,
  ) async {
    if (!quality.toUpperCase().contains('480')) return null;
    try {
      final lastSlash = mediaPlaylistUrl.lastIndexOf('/');
      if (lastSlash <= 0) return null;
      final probeUrl =
          '${mediaPlaylistUrl.substring(0, lastSlash)}/'
          '${mediaPlaylistUrl.substring(lastSlash + 1).replaceFirst(_numberedMediaPlaylist, '_0.m3u8')}';
      final text = (await _dio.get<String>(probeUrl)).data ?? '';
      // 必须是媒体清单（有分片、不是另一层 master）。
      if (text.contains('#EXT-X-STREAM-INF') || !text.contains('#EXTINF')) {
        return null;
      }
      debugPrint(
        '[HlsPrefetcher] probe fallback -> ${probeUrl.split('/').last}',
      );
      return probeUrl;
    } catch (_) {
      return null;
    }
  }

  static void _rememberRendition(String key, String value) {
    _renditions[key] = value;
    while (_renditions.length > _cacheEntries) {
      _renditions.remove(_renditions.keys.first);
    }
  }

  /// 从 master playlist 里挑一路。
  ///
  /// 【为什么不能按 RESOLUTION 高度挑】竖屏视频 RESOLUTION=宽x高
  /// （如 1080p 那路是 `1080x1920`，高度是 1920），而 "1080P" 标签指的是
  /// 短边；偏偏 `_0`(270x480) 的标签又对应长边——CDN 的分辨率标注
  /// 前后不一致，按「高度与目标值求最近距离」会系统性选错档：
  /// 实测选 1080P 拿到 `_1`(720p)、选 720P 拿到 `_0`(480p)，用户看着
  /// 低画质还以为自己在看 1080P。
  ///
  /// 改为两级匹配：
  /// 1. **命名索引**（首选）：CDN 约定 `xxx_N.m3u8` 的 N 与档位一一对应
  ///    （480P→`_0`、720P→`_1`、1080P→`_2`），实测全部资产一致；
  /// 2. **码率序兜底**：master 里没有对应命名的 variant 时，按 BANDWIDTH
  ///    升序取第 N 档；档位不足时取最高档（宁可选最接近的，不报错）。
  static String? _pickVariant(String text, String quality) {
    final variants = <_Variant>[];
    int? height;
    int? bandwidth;
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXT-X-STREAM-INF')) {
        bandwidth = _intAttr(line, 'BANDWIDTH');
        height = _resolutionHeight(line);
        continue;
      }
      if (line.startsWith('#')) continue;
      if (height != null || bandwidth != null) {
        variants.add(
          _Variant(
            uri: line,
            height: height ?? 0,
            bandwidth: bandwidth ?? 0,
          ),
        );
        height = null;
        bandwidth = null;
      }
    }
    if (variants.isEmpty) return null;
    final index = switch (quality.toUpperCase()) {
      '1080P' => 2,
      '720P' => 1,
      _ => 0,
    };
    // ① 命名索引匹配：`xxx_2.m3u8` 即 1080P 那一路。
    final suffix = RegExp('_$index\\.m3u8\$');
    for (final variant in variants) {
      if (suffix.hasMatch(variant.uri)) return variant.uri;
    }
    // ② 兜底：按 BANDWIDTH 升序取第 index 档；不够时取最高档。
    variants.sort((a, b) => a.bandwidth.compareTo(b.bandwidth));
    if (index < variants.length) return variants[index].uri;
    return variants.last.uri;
  }

  static int? _intAttr(String line, String name) {
    final match = RegExp('$name=(\\d+)').firstMatch(line);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  static int? _resolutionHeight(String line) {
    final match = RegExp('RESOLUTION=(\\d+)x(\\d+)').firstMatch(line);
    if (match == null) return null;
    return int.tryParse(match.group(2) ?? '');
  }

  /// 预热 [playlistUrl] 的前 [segments] 个分片。
  ///
  /// 返回 `true` 表示首分片已经在浏览器缓存里，调用方可以放心跳过
  /// "创建离屏 `<video>` 静音试播"这条路径。
  /// 任何异常都返回 `false`（调用方回退到原逻辑），绝不抛出。
  static Future<bool> warmUp(
    String playlistUrl, {
    int segments = _defaultSegments,
    String quality = '480P',
  }) async {
    if (!kIsWeb) return false;
    final master = playlistUrl.trim();
    if (master.isEmpty) return false;
    // 【先定档再下字节】预热必须下"播放器真正会用的那一路"的分片，
    // 否则字节进了缓存也白下：原来这里固定取 master 的第一个 variant，
    // 而播放器走 ABR 挑的是 720p/1080p，两者根本不是同一个 URL。
    final url = await resolveRendition(master, quality: quality);
    if (_warmed.contains(url)) return true;
    // 同一个 playlist 的预热只跑一次（拖拽期间会被反复触发）。
    // 已经在跑时返回 true：表示"这件事有人管了"，调用方不要因为 false
    // 退回离屏 `<video>` 那条在 web 上无效（且会被自动播放策略拒绝）的路径。
    if (!_inflight.add(url)) return true;
    try {
      final segmentUrls = await _resolveSegments(url);
      if (segmentUrls.isEmpty) return false;
      final targets = segmentUrls.take(segments).toList();
      for (final segment in targets) {
        // 顺序下载，刻意不并发：并发会和当前播放抢同一条连接的带宽。
        await _dio.get<dynamic>(
          segment,
          options: Options(responseType: ResponseType.bytes),
        );
      }
      _remember(url);
      debugPrint(
        '[HlsPrefetcher] warmed segments=${targets.length} url=$url',
      );
      return true;
    } catch (e) {
      // 预取失败必须对播放零影响，静默退回原路径即可。
      debugPrint('[HlsPrefetcher] warmUp failed url=$url error=$e');
      return false;
    } finally {
      _inflight.remove(url);
    }
  }

  /// 清空记忆（切剧、退出播放页时可调用，避免占着旧的缓存判断）。
  static void reset() {
    _warmed.clear();
    _inflight.clear();
    _renditions.clear();
  }

  static void _remember(String url) {
    _warmed.remove(url);
    _warmed.add(url);
    while (_warmed.length > _cacheEntries) {
      _warmed.remove(_warmed.first);
    }
  }

  /// 解析出真正要下字节的分片地址。
  ///
  /// 当前后端是**单码率 media playlist**（无 `#EXT-X-STREAM-INF`），
  /// 但仍兼容 master playlist：取第一个 variant 再解析一层，
  /// 这样后端哪天开多码率也不用改这里。
  static Future<List<String>> _resolveSegments(
    String playlistUrl, {
    int depth = 0,
  }) async {
    if (depth > 2) return const [];
    final response = await _dio.get<String>(playlistUrl);
    final text = response.data ?? '';
    if (!text.contains('#EXTM3U')) return const [];

    if (text.contains('#EXT-X-STREAM-INF')) {
      final variant = _firstUriLine(text);
      if (variant == null) return const [];
      return _resolveSegments(_resolveUri(playlistUrl, variant), depth: depth + 1);
    }

    final result = <String>[];
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      result.add(_resolveUri(playlistUrl, line));
    }
    return result;
  }

  /// master playlist 里第一条非注释行就是第一个 variant 的地址。
  static String? _firstUriLine(String text) {
    for (final rawLine in text.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      return line;
    }
    return null;
  }

  /// 把 playlist 中的相对地址解析成绝对地址。
  static String _resolveUri(String base, String reference) {
    final lower = reference.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return reference;
    }
    final uri = Uri.parse(base);
    if (reference.startsWith('/')) {
      return Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: reference,
      ).toString();
    }
    return uri.resolve(reference).toString();
  }
}

/// master playlist 里的一路码率。
class _Variant {
  const _Variant({
    required this.uri,
    required this.height,
    required this.bandwidth,
  });

  final String uri;
  final int height;
  final int bandwidth;
}

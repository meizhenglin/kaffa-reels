import 'dart:async';

/// 让「正在观看的剧集」优先占用网络带宽。
///
/// 【背景】
/// 后端返回的是**单码率 HLS**（实测约 3.2~6.7 Mbps，平均 4.4 Mbps），
/// 播放器无法自动降低清晰度；而 ExoPlayer 的读缓冲默认会一直下载到约
/// 50 秒，**暂停播放并不会停止下载**。
/// 因此只要多创建一个「下一集」播放器，它就会和当前集抢同一条链接，
/// 表现就是：缓存增长很慢，播放很快就追上缓存并卡住。
///
/// 【策略】
/// - 当前集缓冲领先 >= [prefetchStartAhead] 且最近没有卡顿，才允许预取；
/// - 当前集缓冲掉到 [prefetchStopAhead] 以下、或正在卡顿，立即禁止预取，
///   并通知已创建的预取播放器自行释放，把带宽让出来；
/// - 当前集刚卡过，[stallCooldown] 内不再预取。
class PlaybackBufferGuard {
  PlaybackBufferGuard._();

  /// 允许开始预取所需的最小缓冲领先量。
  ///
  /// 【为什么从 15s 降到 4s】原来要求当前集缓冲领先 15 秒才开始预取下一集。
  /// 但单码率 HLS 是 4.4Mbps：用户带宽只有 5~8Mbps 时，缓冲领先量长期
  /// 停在 2~6 秒（下载速度勉强追平播放速度），**15s 这个门槛几乎永远
  /// 打不开** —— 结果就是每次滑到下一集都是冷启动。
  /// 4s 是"当前集安全起播 + 够撑到预取那 3.5s 数据下载完"的经验值。
  ///
  /// 【480P 后再次下调 4s → 3s】锁 480p 后当前集只吃 ~736kbps，
  /// 预热一个分片也从 1.93MB 降到 403KB，带宽争抢烈度完全不同了。
  /// 门槛越低，center+1 的预热越早启动，快滑时 `prepared=true` 的
  /// 概率越高（快滑场景预热窗口只有 1~3 秒）。
  /// 【实测不能再降：2s 会让并发预热互相抢死】加入 center+2 预热后，
  /// 门槛降到 2s 时三个预热实例同时满足启动条件一起抢同一条跨境链路，
  /// 结果谁都下不动：`ready=0 / abandoned=6`，当前集缓冲也被拖到 0，
  /// 体感比 3s 明显更慢。3s 的作用不只是"留余量"，更是**把预热串起来**。
  static const Duration prefetchStartAhead = Duration(seconds: 3);

  /// 低于该缓冲领先量时，预取必须让出带宽。
  ///
  /// 【480P 后从 2s 下调到 1s】实测日志里频繁出现
  /// `releasing prefetch ... ahead=1s buffering=false`——当前集明明
  /// 没在卡顿，只因为缓冲领先量在冷启动初期短暂低于 2s，就把
  /// center+1 的预热整个杀掉（ExoPlayer 实例 dispose，已下载的分片
  /// 全部作废）。480p 下 1s 领先量 ≈ 已经握着下一个 403KB 分片，
  /// 足够安全。
  static const Duration prefetchStopAhead = Duration(seconds: 1);

  /// 当前集卡顿后的冷却时间，期间不预取。
  ///
  /// 25s 太长：短剧一集才 60~90s，冷却一次基本等于整集不再预取，
  /// 用户下一滑必然碰到冷启动。
  ///
  /// 【为什么从 8s 收到 3s】Watch 页一集 60~90s，一个分片要下 ~2.6s。
  /// 原来只要出现一次 buffering 就记 8s 冷却，而**每次冷启动必然出现一次
  /// buffering** —— 于是形成闭环：冷启动 → 冷却 8s → 下一集来不及预热 →
  /// 又冷启动。推荐页之所以没事，是因为它的片子短，
  /// `nearEnd`（最后 12s 无条件放行）几乎全程成立，把冷却绕过去了；
  /// 60s 的一集只有最后 12s 能享受这个豁免。
  /// 3s 足够把刚被抢走的带宽还给当前集，真正吃紧时还有
  /// [prefetchStopAhead] 和 [releaseGrace] 兜底。
  static const Duration stallCooldown = Duration(seconds: 3);

  /// 多长的缓冲才算「真卡顿」。
  ///
  /// 起播、seek 之后的短暂 buffering 是正常现象，不该记成卡顿：
  /// 一旦记成卡顿就会触发 [stallCooldown] 把下一集的预取拦掉，
  /// 结果就是每次切集都从冷启动开始。
  static const Duration stallSignificant = Duration(milliseconds: 1200);

  /// 让出带宽前的宽限期。
  ///
  /// 【为什么需要】预热一集要真金白银下 **1.93MB**（实测一个 5s 分片）。
  /// 原来 gate 一关闭就立刻回调 release，把刚下完的分片整个丢掉；
  /// 8s 冷却后重新预热又要再下 1.93MB。慢网下一次"预热→丢弃→再预热"
  /// 循环要多花近 4MB 带宽，正是"越滑越卡"的元凶。
  /// 只有 gate **连续**关闭超过这个宽限期才真正释放，避免瞬时抖动
  ///（seek、临时 buffering 抖动）把预热成果销毁。
  static const Duration releaseGrace = Duration(milliseconds: 1500);

  static final Set<void Function()> _backoffListeners = <void Function()>{};
  static Timer? _releaseGraceTimer;

  static Object? _activeOwner;

  /// 当前正在播放的清晰度（480P/720P/1080P）。
  ///
  /// 【为什么阈值要跟着清晰度走】所有秒数阈值都是在 480p（736kbps，
  /// 1s≈92KB）下调出来的。1080p 码率 ~4.4Mbps（1s≈550KB），同样的秒数
  /// 对应的字节量差 6 倍，且带宽余量极小（5~8Mbps 跨境 vs 4.4Mbps 码率），
  /// 播放中段抢带宽预热下一集必卡。高清晰度下阈值必须放宽。
  static String? _activeQuality;

  /// 允许开始预取的最小缓冲领先量（按清晰度自适应）。
  ///
  /// 480P: 3s（≈280KB）| 720P: 5s | 1080P: 8s（≈4.4MB，接近满带宽 1s+）
  static Duration get effectivePrefetchStartAhead => switch (_activeQuality) {
        '1080P' => const Duration(seconds: 8),
        '720P' => const Duration(seconds: 5),
        _ => prefetchStartAhead,
      };

  /// 低于该领先量时预取让出带宽（按清晰度自适应）。
  ///
  /// 480P 下 1s≈92KB 很安全；1080p 下 1s≈550KB，等于刚好悬在
  /// "下一口分片没到位"的边缘，门槛必须抬高到 5s。
  static Duration get effectivePrefetchStopAhead => switch (_activeQuality) {
        '1080P' => const Duration(seconds: 5),
        '720P' => const Duration(seconds: 3),
        _ => prefetchStopAhead,
      };

  /// 卡顿冷却（按清晰度自适应）：1080p 一次卡顿的恢复成本更高。
  static Duration get effectiveStallCooldown => switch (_activeQuality) {
        '1080P' => const Duration(seconds: 6),
        '720P' => const Duration(seconds: 4),
        _ => stallCooldown,
      };

  static Duration _activeAhead = Duration.zero;
  static bool _activeBuffering = false;
  static bool _activeAtStart = false;
  static bool _activeNearEnd = false;
  static DateTime? _lastStallAt;
  static DateTime? _bufferingSince;
  static bool _lastPrefetchAllowed = false;

  /// 供日志排查使用的决策快照。
  static String get debugState {
    final stallAgo = _lastStallAt == null
        ? 'none'
        : '${DateTime.now().difference(_lastStallAt!).inSeconds}s ago';
    return 'active=${_activeOwner != null} quality=${_activeQuality ?? '480P'} '
        'ahead=${_activeAhead.inSeconds}s '
        'buffering=$_activeBuffering '
        'lastStall=$stallAgo '
        'prefetch=$prefetchAllowed';
  }

  /// 当前是否允许创建/继续预取。
  ///
  /// 只有「确实有剧集在播放」时才预取：启动阶段、暂停、锁屏时都不占用带宽。
  static bool get prefetchAllowed {
    // 【关键修复】"没人在播" ≠ "不能预取"。
    //
    // 切集时 `_pauseAtIndex(旧集)` 会调 clearActive，`_activeOwner` 立刻变 null；
    // 而新的一集要 initialize + 等到第一个 tick 才重新 reportActive，
    // 中间有几百毫秒到几秒的空窗。原来第一行是
    // `if (_activeOwner == null) return false;` —— 这段空窗里所有预取请求
    // 都被拒（日志里就是 `active=false ahead=0s prefetch=false`）。
    // 而"新一集还没播起来"恰恰最需要预热下一集，
    // 于是闭环成立：切集 → active 清空 → 预取被拒 → 下一集又是冷启动。
    //
    // 没人在播说明带宽是空的，正是预取的最佳时机。
    if (_activeOwner == null) return true;
    // 【起播缓冲不算卡顿】新一集冷启动的头 1~2 秒必然 buffering，
    // 若因此封锁预取，快滑场景下 center+1 的预热永远赶不上——
    // 形成"每次切集都冷启动"的闭环。position 还在 0 附近
    //（_activeAtStart）时的缓冲是起播的一部分，放行预取；
    // 真正播起来后的卡顿依旧封锁。
    if (_activeBuffering && !_activeAtStart) return false;
    // 【起播豁免 ahead 判定】position 还在 0 附近时 ahead 天然是 0：这一集
    // 才刚开始下载，数据还没到，但这不代表带宽吃紧（实测同一时刻
    // buffering=false）。若此时连预取也封掉，下一集必然冷启动；冷启动的
    // 新集 ahead 又是 0，闭环成立 —— 实测 21 次切集里 8 次这样被拒。
    // atStart 结束后（position > 0.5s）仍严格按 ahead 判定。
    if (!_activeAtStart && _activeAhead < effectivePrefetchStopAhead) {
      return false;
    }

    // 当前集快播完了：此时它通常已缓存充足，而且马上要切集，
    // 值得提前准备下一集。
    if (_activeNearEnd) return true;

    // 【1080P 专用】码率 ~4.4Mbps 几乎吃满跨境带宽，播放中段（非 nearEnd）
    // 一律不放行预热——预热一次 ~2MB，抢的就是当前集的带宽，实测表现
    // 就是"1080p 很卡"。快滑时的预热走 `activeOwner == null` 空窗，不受影响。
    if (_activeQuality == '1080P') return false;

    final lastStall = _lastStallAt;
    if (lastStall != null &&
        DateTime.now().difference(lastStall) < effectiveStallCooldown) {
      return false;
    }
    return _activeAhead >= effectivePrefetchStartAhead;
  }

  /// **已经开始的**预热是否该让出带宽。
  ///
  /// 【与 prefetchAllowed 的区别】`prefetchAllowed` 回答的是"够不够格开始
  /// 一轮新预热"，其中包含 `startAhead`(3s) 门槛；而这个 getter 回答的是
  /// "已经下到一半的预热要不要中止"，只需要看当前集是否真的吃紧。
  ///
  /// 【为什么必须分开】预热循环原来用 `prefetchAllowed` 判 abort：
  /// 当前集缓冲 2s（高于 stopAhead 1s，完全安全）但低于 startAhead 3s，
  /// 于是刚下好的分片被 `_release()` 丢弃，重新预热又要再下一次 ——
  /// 实测 `abandoned state=... ahead=2s buffering=false` 正是这一类，
  /// 属于纯粹的白丢带宽。
  static bool get prefetchShouldYield {
    if (_activeOwner == null) return false;
    if (_activeAtStart) return false;
    if (_activeBuffering) return true;
    return _activeAhead < effectivePrefetchStopAhead;
  }

  /// 正在播放的组件上报自己的缓冲状态。
  ///
  /// [owner] 直接传组件 State 本身，用来识别「当前谁在占用带宽」。
  /// [atStart] 表示「这一集还没真正播起来」（位置还在 0 附近），
  /// 此时的 buffering 属于起播缓冲，不算卡顿。
  /// [quality] 当前清晰度，用于自适应阈值。
  static void reportActive({
    required Object owner,
    required bool buffering,
    required Duration bufferedAhead,
    bool nearEnd = false,
    bool atStart = false,
    String? quality,
  }) {
    final sameOwner = identical(owner, _activeOwner);
    final wasBuffering = _activeBuffering && sameOwner;
    _activeOwner = owner;
    _activeQuality = quality;
    _activeBuffering = buffering;
    _activeAhead = bufferedAhead;
    _activeAtStart = atStart;
    _activeNearEnd = nearEnd;

    // 【只有「真卡顿」才计入冷却】原来在 buffering 开始的那一刻就记冷却，
    // 而冷启动 / seek 之后必然有一段正常 buffering —— 等于每次切集都自我
    // 触发一次冷却，把下一集的预取拦掉。
    // 现在：起播缓冲不计，且只在缓冲**结束**时按持续时长判定。
    if (buffering) {
      if (!wasBuffering && !atStart) _bufferingSince = DateTime.now();
    } else {
      final since = _bufferingSince;
      _bufferingSince = null;
      if (wasBuffering &&
          since != null &&
          DateTime.now().difference(since) >= stallSignificant) {
        _lastStallAt = DateTime.now();
      }
    }
    _updatePrefetchGate();
  }

  /// 当前播放器暂停/销毁后清除，避免旧状态影响预取判断。
  static void clearActive(Object owner) {
    if (!identical(owner, _activeOwner)) return;
    _activeOwner = null;
    _activeQuality = null;
    _activeAhead = Duration.zero;
    _activeBuffering = false;
    _activeAtStart = false;
    _activeNearEnd = false;
    _bufferingSince = null;
    _updatePrefetchGate();
  }

  /// 预取组件注册：一旦需要让出带宽，会被回调。
  static void addBackoffListener(void Function() listener) {
    _backoffListeners.add(listener);
  }

  static void removeBackoffListener(void Function() listener) {
    _backoffListeners.remove(listener);
  }

  /// 等待一个允许预取的时间窗口。
  ///
  /// 返回 `true` 表示可以开始预取；`false` 表示等待期间被取消/超时，
  /// 或者当前集一直需要带宽。
  ///
  /// 超时从 20s 收紧到 8s：等待超过 8 秒还没空出来，说明当前集确实吃紧，
  /// 与其继续挂着空等，不如直接放弃这一轮、交给下一次翻页重新评估。
  static Future<bool> waitForPrefetchSlot({
    required bool Function() isCancelled,
    Duration timeout = const Duration(seconds: 8),
    Duration pollInterval = const Duration(milliseconds: 250),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!isCancelled() && DateTime.now().isBefore(deadline)) {
      if (prefetchAllowed) return true;
      await Future<void>.delayed(pollInterval);
    }
    return !isCancelled() && prefetchAllowed;
  }

  static void _updatePrefetchGate() {
    final allowed = prefetchAllowed;
    if (allowed == _lastPrefetchAllowed) return;
    _lastPrefetchAllowed = allowed;
    if (allowed) {
      // 带宽又空出来了：撤销待执行的释放，保住已经下好的预热数据。
      _releaseGraceTimer?.cancel();
      _releaseGraceTimer = null;
      return;
    }
    if (_backoffListeners.isEmpty) return;
    _releaseGraceTimer?.cancel();
    _releaseGraceTimer = Timer(releaseGrace, () {
      _releaseGraceTimer = null;
      // 宽限期内已经恢复健康：这次抖动不该销毁预热成果。
      if (prefetchAllowed) return;
      for (final listener in List<void Function()>.of(_backoffListeners)) {
        listener();
      }
    });
  }
}

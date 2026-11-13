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
  static const Duration prefetchStartAhead = Duration(seconds: 15);

  /// 低于该缓冲领先量时，预取必须让出带宽。
  static const Duration prefetchStopAhead = Duration(seconds: 8);

  /// 当前集卡顿后的冷却时间，期间不预取。
  static const Duration stallCooldown = Duration(seconds: 25);

  static final Set<void Function()> _backoffListeners = <void Function()>{};

  static Object? _activeOwner;
  static Duration _activeAhead = Duration.zero;
  static bool _activeBuffering = false;
  static bool _activeNearEnd = false;
  static DateTime? _lastStallAt;
  static bool _lastPrefetchAllowed = false;

  /// 供日志排查使用的决策快照。
  static String get debugState {
    final stallAgo = _lastStallAt == null
        ? 'none'
        : '${DateTime.now().difference(_lastStallAt!).inSeconds}s ago';
    return 'active=${_activeOwner != null} '
        'ahead=${_activeAhead.inSeconds}s '
        'buffering=$_activeBuffering '
        'lastStall=$stallAgo '
        'prefetch=$prefetchAllowed';
  }

  /// 当前是否允许创建/继续预取。
  ///
  /// 只有「确实有剧集在播放」时才预取：启动阶段、暂停、锁屏时都不占用带宽。
  static bool get prefetchAllowed {
    if (_activeOwner == null) return false;
    if (_activeBuffering) return false;
    if (_activeAhead < prefetchStopAhead) return false;

    // 当前集快播完了：此时它通常已缓存充足，而且马上要切集，
    // 值得提前准备下一集。
    if (_activeNearEnd) return true;

    final lastStall = _lastStallAt;
    if (lastStall != null &&
        DateTime.now().difference(lastStall) < stallCooldown) {
      return false;
    }
    return _activeAhead >= prefetchStartAhead;
  }

  /// 正在播放的组件上报自己的缓冲状态。
  ///
  /// [owner] 直接传组件 State 本身，用来识别「当前谁在占用带宽」。
  static void reportActive({
    required Object owner,
    required bool buffering,
    required Duration bufferedAhead,
    bool nearEnd = false,
  }) {
    final sameOwner = identical(owner, _activeOwner);
    final wasBuffering = _activeBuffering && sameOwner;
    _activeOwner = owner;
    _activeBuffering = buffering;
    _activeAhead = bufferedAhead;
    _activeNearEnd = nearEnd;

    if (buffering && !wasBuffering) {
      _lastStallAt = DateTime.now();
    }
    _updatePrefetchGate();
  }

  /// 当前播放器暂停/销毁后清除，避免旧状态影响预取判断。
  static void clearActive(Object owner) {
    if (!identical(owner, _activeOwner)) return;
    _activeOwner = null;
    _activeAhead = Duration.zero;
    _activeBuffering = false;
    _activeNearEnd = false;
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
  static Future<bool> waitForPrefetchSlot({
    required bool Function() isCancelled,
    Duration timeout = const Duration(seconds: 20),
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
    if (allowed) return;
    if (_backoffListeners.isEmpty) return;
    for (final listener in List<void Function()>.of(_backoffListeners)) {
      listener();
    }
  }
}

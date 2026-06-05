import 'package:flutter/material.dart';

import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../presentation/player_controller.dart';

/// ============================================================================
/// 选集面板组件
///
/// 【功能】上拉显示剧集列表，支持选集播放和解锁状态显示
/// 【解锁逻辑】
/// - 免费集（isUnlocked=true）：所有人可看
/// - VIP剧锁定集（isVipOnly=true, isUnlocked=false）：
///   - 游客 → 显示登录弹窗
///   - 已登录非VIP → 显示VIP订阅弹窗
///   - VIP会员 → 允许播放
/// - 普通剧锁定集（isVipOnly=false）：直接播放
/// ============================================================================
class EpisodeSheet extends StatelessWidget {
  const EpisodeSheet({
    super.key,
    required this.episodes,
    required this.currentIndex,
    required this.onEpisodeTap,
    this.isVipOnly = false,
    this.authState,
    this.memberState,
    this.onUnlock,
  });

  final List<EpisodeData> episodes;
  final int currentIndex;
  final void Function(int index) onEpisodeTap;
  final bool isVipOnly;
  final AuthState? authState;
  final MemberState? memberState;
  final void Function(int index)? onUnlock;

  bool _isLockedForCurrentUser(EpisodeData episode) {
    if (!episode.isUnlocked) {
      if (isVipOnly) {
        final bool isGuest =
            authState == null || !authState!.isAuthenticated || authState!.user?.isGuest == true;
        if (isGuest) return true;
        final bool needsVip =
            memberState == null || !memberState!.isVip || memberState!.isExpired;
        return needsVip;
      }
      return false; // 普通剧直接可看
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(context),
          _buildEpisodeList(context),
        ],
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsetsDirectional.only(top: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.grey.shade400,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        textDirection: Directionality.of(context),
        children: [
          Text(
            'Episodes',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${episodes.length} Episodes',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEpisodeList(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.5,
      ),
      child: GridView.builder(
        shrinkWrap: true,
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 32),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.0,
        ),
        itemCount: episodes.length,
        itemBuilder: (context, index) {
          final episode = episodes[index];
          final isCurrent = index == currentIndex;
          final isLocked = _isLockedForCurrentUser(episode);

          return _EpisodeItem(
            index: index + 1,
            isCurrent: isCurrent,
            isLocked: isLocked,
            onTap: () {
              if (isLocked) {
                _showLockedDialog(context, index);
              } else {
                onEpisodeTap(index);
              }
            },
          );
        },
      ),
    );
  }

  void _showLockedDialog(BuildContext context, int episodeIndex) {
    final bool isGuest =
        authState == null || !authState!.isAuthenticated || authState!.user?.isGuest == true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isGuest ? 'Login Required' : 'VIP Required'),
        content: Text(
          isGuest
              ? 'Episode ${episodeIndex + 1} is locked. Please login to continue.'
              : 'Episode ${episodeIndex + 1} requires VIP membership.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onUnlock?.call(episodeIndex);
            },
            child: Text(isGuest ? 'Login' : 'Subscribe'),
          ),
        ],
      ),
    );
  }
}

class _EpisodeItem extends StatelessWidget {
  const _EpisodeItem({
    required this.index,
    required this.isCurrent,
    required this.isLocked,
    required this.onTap,
  });

  final int index;
  final bool isCurrent;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isCurrent
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: isCurrent
              ? Border.all(
                  color: Theme.of(context).colorScheme.primary,
                  width: 2,
                )
              : null,
        ),
        child: Center(
          child: isLocked
              ? Icon(
                  Icons.lock_rounded,
                  color: Colors.grey.shade600,
                  size: 24,
                )
              : Text(
                  '$index',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isCurrent
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
        ),
      ),
    );
  }
}

/// 显示选集面板
Future<void> showEpisodeSheet(
  BuildContext context, {
  required List<EpisodeData> episodes,
  required int currentIndex,
  required void Function(int index) onEpisodeTap,
  bool isVipOnly = false,
  AuthState? authState,
  MemberState? memberState,
  void Function(int index)? onUnlock,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => EpisodeSheet(
      episodes: episodes,
      currentIndex: currentIndex,
      onEpisodeTap: onEpisodeTap,
      isVipOnly: isVipOnly,
      authState: authState,
      memberState: memberState,
      onUnlock: onUnlock,
    ),
  );
}

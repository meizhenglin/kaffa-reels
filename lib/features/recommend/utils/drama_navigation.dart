import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../l10n/app_localizations.dart';
import '../models/drama.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../../profile/providers/history_provider.dart';
import '../../home/providers/last_watched_provider.dart';

/// VIP 访问结果
enum VipAccessResult {
  granted,          // 直接访问
  loginRequired,     // 需要登录
  vipRequired,       // 需要开通 VIP
}

/// 检查用户是否有权观看该短剧
///
/// [drama] 要访问的短剧
/// [authState] 当前认证状态
/// [memberState] 当前会员状态
VipAccessResult checkVipAccess({
  required Drama drama,
  required AuthState authState,
  required MemberState memberState,
}) {
  if (!drama.isVipOnly) return VipAccessResult.granted;
  if (!authState.isAuthenticated || authState.user?.isGuest == true) {
    return VipAccessResult.loginRequired;
  }
  if (!memberState.isVip || memberState.isExpired) {
    return VipAccessResult.vipRequired;
  }
  return VipAccessResult.granted;
}

/// 显示 VIP 权限拒绝弹窗
Future<void> showVipAccessDeniedDialog(
  BuildContext context,
  VipAccessResult result,
) async {
  final l10n = AppLocalizations.of(context);
  final isLogin = result == VipAccessResult.loginRequired;

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(isLogin ? l10n.login : l10n.vipMembership),
      content: Text(isLogin ? l10n.loginSubtitle : l10n.vipSubtitle),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(isLogin ? 'Cancel' : 'Maybe Later'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(ctx);
            if (isLogin) {
              context.push('/login');
            } else {
              context.push('/membership');
            }
          },
          child: Text(isLogin ? l10n.login : l10n.subscribe),
        ),
      ],
    ),
  );
}

/// 访问短剧（含 VIP 权限检查）
///
/// 对于 VIP 剧，游客可以进入播放器观看前3集免费内容，
/// 到锁定集时检查登录状态和会员状态再决定是否弹窗。
///
/// [drama] 短剧
/// [authState] 认证状态（来自 ref.watch(authProvider)）
/// [memberState] 会员状态（来自 ref.watch(memberStateProvider)）
Future<void> openDramaPlayerWithVipCheck({
  required BuildContext context,
  required Drama drama,
  required AuthState authState,
  required MemberState memberState,
}) async {
  await openDramaPlayer(context, drama);
}

/// ============================================================================
/// 短剧播放器导航工具
///
/// 【功能】封装跳转到播放器的逻辑
/// 【使用】在其他页面点击短剧时调用 openDramaPlayer(context, drama)
/// 【说明】只传 videoId，ShortVideoPage 内部请求真实数据
Future<void> openDramaPlayer(BuildContext context, Drama drama) async {
  try {
    final container = ProviderScope.containerOf(context);
    await context.push('/short-video', extra: {'videoId': drama.id});
    container.read(lastWatchedProvider.notifier).load();
    container.read(historyProvider.notifier).refresh();
  } catch (_) {}
}

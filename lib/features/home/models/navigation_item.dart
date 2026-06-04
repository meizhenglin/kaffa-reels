import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

/// ============================================================================
/// 底部导航项配置
///
/// 【功能说明】
/// 定义底部导航栏的每个 Tab 项的配置：
/// - id: 唯一标识符
/// - titleBuilder: 标题构建器（支持国际化）
/// - icon / activeIcon: 未选中/选中状态的图标
/// - routePath: 对应的路由路径
/// - flipIconInRtl: RTL 布局下是否翻转图标
///
/// 【如何修改】
/// - 添加新 Tab：在 items() 方法中添加新的 NavigationItem
/// - 修改 Tab 顺序：调整 items() 方法中的顺序
/// - 修改 Tab 图标：修改 icon 和 activeIcon 参数
/// - 修改路由路径：修改 routePath 参数
/// ============================================================================

/// 导航项数据模型
class NavigationItem {
  const NavigationItem({
    required this.id,
    required this.titleBuilder,
    required this.icon,
    required this.activeIcon,
    required this.routePath,
    this.flipIconInRtl = false,
  });

  /// 唯一标识符（如 'home', 'explore'）
  final String id;

  /// 标题构建器，传入国际化对象返回对应语言的标题
  final String Function(AppLocalizations l10n) titleBuilder;

  /// 未选中状态的图标
  // final IconData icon;
  final Widget icon;

  /// 选中状态的图标
  // final IconData activeIcon;
  final Widget activeIcon;

  /// 对应的路由路径
  final String routePath;

  /// RTL 布局下是否水平翻转图标（如箭头图标需要翻转）
  final bool flipIconInRtl;

  /// 获取标题文本
  String title(AppLocalizations l10n) => titleBuilder(l10n);
}

/// 底部导航配置类
class NavigationConfig {
  NavigationConfig._();

  /// 各 Tab 对应的路由路径
  /// 【修改提示】如果修改了路由配置，需要同步修改这里
  static const List<String> branchPaths = [
    '/', // 首页
    '/explore', // 发现
    '/recommend', // 推荐
    '/games', // 游戏
    '/profile', // 我的
  ];

  /// Tab 的唯一标识符列表
  static const List<String> tabIds = [
    'home',
    'explore',
    'recommend',
    'games',
    'profile',
  ];

  /// 构建导航项列表
  /// [l10n] 国际化对象
  /// 【修改提示】要修改底部导航栏的显示，在这里调整
  static List<NavigationItem> items(AppLocalizations l10n) => [
    NavigationItem(
      id: 'home',
      titleBuilder: (_) => 'Main Page',
      // icon: const Icon(Icons.home_outlined, size: 24),
      // icon: const Image.asset('assets/images/mainPage_icon.png', width: 24, height: 24),
      icon: Image(
        image: AssetImage('assets/images/mainPage_icon.png'),
        width: 24,
        height: 24,
      ),

      activeIcon: Image(
        image: AssetImage('assets/images/mainPage_icon_active.png'),
        width: 24,
        height: 24,
      ),
      routePath: '/',
    ),
    NavigationItem(
      id: 'explore',
      titleBuilder: (l) => l.explore,
      icon: Image(
        image: AssetImage('assets/images/explore_icon.png'),
        width: 24,
        height: 24,
      ),

      activeIcon: Image(
        image: AssetImage('assets/images/explore_icon_active.png'),
        width: 24,
        height: 24,
      ),
      routePath: '/explore',
      flipIconInRtl: true,
    ),
    NavigationItem(
      id: 'recommend',
      titleBuilder: (l) => l.recommended,
       icon: Image(
        image: AssetImage('assets/images/recommend_icon.png'),
        width: 24,
        height: 24,
      ),

      activeIcon: Image(
        image: AssetImage('assets/images/recommend_icon_active.png'),
        width: 24,
        height: 24,
      ),
      routePath: '/recommend',
    ),
    NavigationItem(
      id: 'games',
      titleBuilder: (l) => l.games,
        icon: Image(
        image: AssetImage('assets/images/game_icon.png'),
        width: 24,
        height: 24,
      ),

      activeIcon: Image(
        image: AssetImage('assets/images/game_icon_active.png'),
        width: 24,
        height: 24,
      ),
      routePath: '/games',
    ),
    NavigationItem(
      id: 'profile',
      titleBuilder: (l) => l.profile,
        icon: Image(
        image: AssetImage('assets/images/profile_icon.png'),
        width: 24,
        height: 24,
      ),

      activeIcon: Image(
        image: AssetImage('assets/images/profile_icon_active.png'),
        width: 24,
        height: 24,
      ),
      routePath: '/profile',
    ),
  ];

  /// 根据路由路径获取对应的 Tab 索引
  /// [path] 路由路径
  /// 返回对应的索引，如果未找到则返回 0（首页）
  static int indexForPath(String path) {
    final normalized = path.split('?').first;
    for (var i = 0; i < branchPaths.length; i++) {
      if (normalized == branchPaths[i] ||
          normalized.startsWith('${branchPaths[i]}/')) {
        return i;
      }
    }
    return 0;
  }

  /// 根据索引获取对应的 Tab ID
  /// [index] Tab 索引
  static String idForIndex(int index) {
    if (index < 0 || index >= tabIds.length) return tabIds.first;
    return tabIds[index];
  }
}

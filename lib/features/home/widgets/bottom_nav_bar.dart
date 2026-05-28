import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../models/navigation_item.dart';

/// 底部导航栏组件
/// 提供 5 个 Tab：Home、Discover、Recommend、Games、Profile
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<NavigationItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (index) {
              final item = items[index];
              final isSelected = index == currentIndex;

              return Expanded(
                child: GestureDetector(
                  onTap: () => onTap(index),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    // decoration: BoxDecoration(
                    //   color: Colors.transparent,
                    //   borderRadius: BorderRadius.circular(12),
                    // ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconTheme(
                          data: IconThemeData(
                            color: isSelected ? Colors.white : const Color(0xFF999999),
                            size: 24,
                          ),
                          child: isSelected ? item.activeIcon : item.icon,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.title(AppLocalizations.of(context)),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isSelected ? FontWeight.normal : FontWeight.normal,
                            color: isSelected
                                ? const Color(0xFF8F4EFF)
                                : const Color(0xFF999999),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

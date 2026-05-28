import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../providers/history_provider.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final Set<String> _selectedIds = {};

  void _toggleEdit() {
    if (_selectedIds.isNotEmpty) {
      ref.read(historyProvider.notifier).deleteSelected(_selectedIds);
      _selectedIds.clear();
    }
    ref.read(historyProvider.notifier).toggleEditMode();
    setState(() {});
  }

  void _onDelete(String id) {
    ref.read(historyProvider.notifier).deleteItem(id);
  }

  @override
  Widget build(BuildContext context) {
    final history = ref.watch(historyProvider);
    final isEditMode = history.isEditMode;

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部栏
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Image.asset(
                      'assets/images/back.png',
                      width: 24,
                      height: 24,
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'Watching History',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!history.isEmpty)
                    GestureDetector(
                      onTap: _toggleEdit,
                      child: Text(
                        isEditMode ? 'Done' : 'Edit',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 40),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 内容区
            Expanded(
              child: history.isEmpty
                  ? _buildEmptyState()
                  : _buildHistoryList(history.items),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/images/noData.png',
            width: 200,
            height: 200,
          ),
          const SizedBox(height: 16),
          const Text(
            'No data',
            style: TextStyle(
              color: Color(0xFFFFFFFF),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(List<HistoryItem> items) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = items[index];
        return _HistoryListItem(
          item: item,
          isEditMode: ref.watch(historyProvider).isEditMode,
          isSelected: _selectedIds.contains(item.id),
          onTap: () => openDramaPlayer(context, item.drama),
          onDelete: () => _onDelete(item.id),
          onToggleSelect: () {
            setState(() {
              if (_selectedIds.contains(item.id)) {
                _selectedIds.remove(item.id);
              } else {
                _selectedIds.add(item.id);
              }
            });
          },
        );
      },
    );
  }
}

class _HistoryListItem extends StatelessWidget {
  final HistoryItem item;
  final bool isEditMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleSelect;

  const _HistoryListItem({
    required this.item,
    required this.isEditMode,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isEditMode ? onToggleSelect : onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面图
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Image.network(
                  item.drama.coverUrl,
                  width: 120,
                  height: 80,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 120,
                    height: 80,
                    color: Colors.grey[800],
                    child: const Icon(Icons.movie, color: Colors.white54),
                  ),
                ),
                // 进度条
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 3,
                    color: Colors.grey[700],
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: item.progress.clamp(0.0, 1.0),
                      child: Container(color: const Color(0xFF9843FF)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // 标题
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  item.drama.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${(item.progress * 100).toInt()}%',
                  style: const TextStyle(
                    color: Color(0xFF9843FF),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 删除按钮
          if (isEditMode)
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF9843FF) : Colors.transparent,
                border: Border.all(
                  color: isSelected ? const Color(0xFF9843FF) : Colors.white54,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            )
          else
            GestureDetector(
              onTap: onDelete,
              child: Image.asset(
                'assets/images/delete.png',
                width: 20,
                height: 20,
              ),
            ),
        ],
      ),
    );
  }
}

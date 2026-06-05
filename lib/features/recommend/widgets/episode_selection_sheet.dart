import 'package:flutter/material.dart';
import 'mini_player_controller.dart';

/// Episode selection sheet — 2/3 screen height.
///
/// Shows: cover image, title, description, episode grid with lock icons.
/// Locked episode tap → navigate to membership page.
class EpisodeSelectionSheet extends StatelessWidget {
  const EpisodeSelectionSheet({
    super.key,
    required this.title,
    this.coverUrl,
    required this.episodes,
    required this.onEpisodeTap,
    required this.onUnlockTap,
  });

  final String title;
  final String? coverUrl;
  final List<MiniEpisode> episodes;
  final void Function(int index) onEpisodeTap;
  final VoidCallback onUnlockTap;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;

    return Container(
      height: screenHeight * 2 / 3,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          _buildHandle(),
          // Header: cover + title + description
          _buildHeader(context),
          // Episode grid
          Expanded(child: _buildEpisodeGrid(context)),
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
        color: Colors.white24,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        textDirection: Directionality.of(context),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: coverUrl != null
                ? Image.network(
                    coverUrl!,
                    width: 72,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholderCover(),
                  )
                : _placeholderCover(),
          ),
          const SizedBox(width: 12),
          // Title + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  '${episodes.length} Episodes',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 4),
                Text(
                  'Current: Episode 1 / ${episodes.length}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderCover() {
    return Container(
      width: 72,
      height: 96,
      color: Colors.grey.shade800,
      child: const Icon(Icons.movie_outlined, color: Colors.white38),
    );
  }

  Widget _buildEpisodeGrid(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 32),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: episodes.length,
      itemBuilder: (context, index) {
        final ep = episodes[index];
        return _EpisodeTile(
          index: index + 1,
          isLocked: !ep.isUnlocked,
          onTap: () {
            if (!ep.isUnlocked) {
              onUnlockTap();
            } else {
              onEpisodeTap(index);
            }
          },
        );
      },
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.index,
    required this.isLocked,
    required this.onTap,
  });

  final int index;
  final bool isLocked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isLocked ? Colors.grey.shade800 : Colors.white12,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: Stack(
          children: [
            // Episode number
            Center(
              child: Text(
                '$index',
                style: TextStyle(
                  color: isLocked ? Colors.grey.shade500 : Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            // Lock icon overlay
            if (isLocked)
              PositionedDirectional(
                bottom: 4,
                end: 4,
                child: Icon(
                  Icons.lock_rounded,
                  color: Colors.grey.shade500,
                  size: 14,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Show the episode selection sheet.
Future<void> showEpisodeSelectionSheet(
  BuildContext context, {
  required String title,
  String? coverUrl,
  required List<MiniEpisode> episodes,
  required void Function(int index) onEpisodeTap,
  required VoidCallback onUnlockTap,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => EpisodeSelectionSheet(
      title: title,
      coverUrl: coverUrl,
      episodes: episodes,
      onEpisodeTap: onEpisodeTap,
      onUnlockTap: onUnlockTap,
    ),
  );
}

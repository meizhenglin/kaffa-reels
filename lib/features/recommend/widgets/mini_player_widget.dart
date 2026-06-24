import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_aliplayer/flutter_aliplayer.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../../core/widgets/app_snack_bar.dart';
import '../utils/drama_navigation.dart';
import 'mini_player_controller.dart';
import 'episode_selection_sheet.dart';

/// Mini player shown at the top of the Recommend tab.
///
/// - Aliyun player video area (16:9)
/// - Vertical action buttons (like, favorite, share, Episode) bottom-right overlay
/// - Progress bar below player
/// - Tap Episode → show episode selection sheet (2/3 screen)
/// - Tap Watch button → navigate to shared short-video page
class MiniPlayerWidget extends ConsumerStatefulWidget {
  const MiniPlayerWidget({super.key});

  @override
  ConsumerState<MiniPlayerWidget> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayerWidget>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    final playerState = ref.read(miniPlayerProvider);
    final controller = ref.read(miniPlayerProvider.notifier);
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (playerState.isPlaying) {
          controller.togglePlay();
        }
        break;
      case AppLifecycleState.resumed:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(miniPlayerProvider);
    final controller = ref.read(miniPlayerProvider.notifier);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final playerHeight = screenWidth * 9 / 16;
    final l10n = AppLocalizations.of(context);

    // No video loaded yet — show nothing
    if (state.videoUrl.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // Player area with action buttons overlay
        Stack(
          children: [
            RepaintBoundary(
              child: SizedBox(
                width: screenWidth,
                height: playerHeight,
                child: AliPlayerView(
                  onCreated: (viewId) {
                    controller.setViewId(viewId);
                  },
                  x: 0,
                  y: 0,
                  width: screenWidth.toDouble(),
                  height: playerHeight,
                  aliPlayerViewType: AliPlayerViewTypeForAndroid.surfaceview,
                ),
              ),
            ),

            // Loading indicator
            if (state.isLoading)
              Positioned.fill(
                child: Container(
                  color: Colors.black38,
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              ),

            // Error overlay
            if (state.hasError)
              Positioned.fill(
                child: Container(
                  color: Colors.black54,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, color: Colors.white54, size: 40),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: () => controller.playDrama(
                            videoUrl: state.videoUrl,
                            title: state.title,
                            coverUrl: state.coverUrl,
                            dramaId: state.dramaId,
                            episodes: state.episodes,
                          ),
                          child: const Text('Retry', style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Tap to toggle play
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: controller.togglePlay,
                child: AnimatedOpacity(
                  opacity: state.isPlaying ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Icon(
                          state.isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Title overlay at top
            PositionedDirectional(
              start: 0,
              end: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black54, Colors.transparent],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Text(
                    state.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),

            // Vertical action buttons — bottom-right
            PositionedDirectional(
              end: 12,
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ActionButton(
                    icon: Icons.thumb_up_outlined,
                    label: 'Like',
                    onTap: () => _showToast(context, 'Like'),
                  ),
                  const SizedBox(height: 16),
                  _ActionButton(
                    icon: Icons.favorite_outline,
                    label: 'Fav',
                    onTap: () => _showToast(context, 'Favorite'),
                  ),
                  const SizedBox(height: 16),
                  _ActionButton(
                    icon: Icons.list_outlined,
                    label: l10n.episode,
                    onTap: () => _showEpisodeSheet(context, state, controller),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Progress bar
        _MiniProgressBar(
          progress: state.progress,
          onSeek: controller.seekTo,
        ),

        // Watch button
        _WatchButton(
          dramaId: state.dramaId,
          videoUrl: state.videoUrl,
          title: state.title,
          coverUrl: state.coverUrl,
          episodes: state.episodes,
        ),
      ],
    );
  }

  void _showEpisodeSheet(
    BuildContext context,
    MiniPlayerState state,
    MiniPlayerController controller,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EpisodeSelectionSheet(
        title: state.title,
        coverUrl: state.coverUrl,
        episodes: state.episodes,
        onEpisodeTap: (index) {
          Navigator.pop(ctx);
          final ep = state.episodes[index];
          controller.playDrama(
            videoUrl: ep.videoUrl,
            title: ep.title,
            coverUrl: ep.coverUrl,
            dramaId: state.dramaId,
            episodes: state.episodes,
          );
        },
        onUnlockTap: () {
          Navigator.pop(ctx);
          openMembershipPage(context, ref);
        },
      ),
    );
  }

  void _showToast(BuildContext context, String action) {
    AppSnackBar.show(context, message: '$action tapped');
  }
}

/// Vertical action button (icon + label stacked).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: Color(0x80000000),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

/// Progress bar with drag-to-seek.
class _MiniProgressBar extends StatelessWidget {
  const _MiniProgressBar({
    required this.progress,
    required this.onSeek,
  });

  final double progress;
  final void Function(double progress) onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            final ratio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            onSeek(ratio);
          },
          onTapUp: (details) {
            final ratio = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
            onSeek(ratio);
          },
          child: Container(
            height: 24,
            color: Colors.transparent,
            child: Center(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Watch button → shared short-video player page.
class _WatchButton extends StatelessWidget {
  const _WatchButton({
    required this.dramaId,
    required this.videoUrl,
    required this.title,
    required this.coverUrl,
    required this.episodes,
  });

  final String? dramaId;
  final String videoUrl;
  final String title;
  final String? coverUrl;
  final List<MiniEpisode> episodes;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
      child: GestureDetector(
        onTap: () {
          final videoId = dramaId;
          if (videoId == null || videoId.isEmpty) return;
          context.push(
            '/short-video',
            extra: {'videoId': videoId},
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Text(
              'WATCH',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../models/game_detail.dart';

class GameDetailPage extends ConsumerStatefulWidget {
  const GameDetailPage({
    super.key,
    required this.id,
    this.gameName,
  });

  final String id;
  final String? gameName;

  @override
  ConsumerState<GameDetailPage> createState() => _GameDetailPageState();
}

class _GameDetailPageState extends ConsumerState<GameDetailPage> {
  bool _isLoading = true;
  String? _errorMessage;
  GameDetail? _gameDetail;

  @override
  void initState() {
    super.initState();
    _loadGameDetail();
  }

  Future<void> _loadGameDetail() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProviderRef);
      final response = await apiService.getGameDetail(id: widget.id);

      if (response.isSuccess && response.data is Map<String, dynamic>) {
        final detail = GameDetail.fromJson(response.data as Map<String, dynamic>);
        setState(() {
          _gameDetail = detail;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.error ?? 'Failed to load game details';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _handlePlayAction() async {
    final game = _gameDetail;
    if (game == null) return;

    final l10n = AppLocalizations.of(context);

    if (game.isH5Game) {
      if (game.h5Url != null && game.h5Url!.isNotEmpty) {
        final uri = Uri.parse(game.h5Url!);
        try {
          if (await canLaunchUrl(uri)) {
            await launchUrl(
              uri,
              mode: LaunchMode.inAppWebView,
              webViewConfiguration: const WebViewConfiguration(
                enableJavaScript: true,
                enableDomStorage: true,
              ),
            );
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n.error}: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (game.isAppGame) {
      if (game.downloadUrl != null && game.downloadUrl!.isNotEmpty) {
        final uri = Uri.parse(game.downloadUrl!);
        try {
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n.error}: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.gameName ?? l10n.games,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _buildBody(theme, l10n),
    );
  }

  Widget _buildBody(ThemeData theme, AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadGameDetail,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.retry),
              ),
            ],
          ),
        ),
      );
    }

    final game = _gameDetail;
    if (game == null) {
      return Center(
        child: Text(
          l10n.noContentAvailable,
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(theme, game),
                const SizedBox(height: 16),
                _buildBannerImages(game),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        _buildBottomAction(theme, l10n, game),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme, GameDetail game) {
    final iconUrl = game.icon;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (iconUrl != null && iconUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              iconUrl,
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _buildIconPlaceholder(),
            ),
          )
        else
          _buildIconPlaceholder(),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                game.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              if (game.description != null && game.description!.isNotEmpty)
                Text(
                  game.description!,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIconPlaceholder() {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF2A2A2A),
      ),
      child: const Icon(
        Icons.videogame_asset,
        size: 36,
        color: Colors.white54,
      ),
    );
  }

  Widget _buildBannerImages(GameDetail game) {
    final urls = _parseBannerUrls(game.banner);
    if (urls.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 220,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final url = urls[index];
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              width: 160,
              height: 220,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                );
              },
              errorBuilder: (context, error, stackTrace) => _buildBannerPlaceholder(),
            ),
          );
        },
      ),
    );
  }

  List<String> _parseBannerUrls(String? banner) {
    if (banner == null || banner.isEmpty) return [];
    return banner
        .split(RegExp(r'[;\n\t]+'))
        .map((part) => part.trim())
        .where((part) => part.startsWith('http'))
        .toList();
  }

  Widget _buildBannerPlaceholder() {
    return Container(
      width: 260,
      height: 160,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF2A2A2A),
      ),
      child: const Icon(
        Icons.image,
        size: 48,
        color: Colors.white54,
      ),
    );
  }

  Widget _buildBottomAction(
      ThemeData theme, AppLocalizations l10n, GameDetail game) {
    final actionText = game.isH5Game ? 'Start Playing' : 'Download';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
          ),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _handlePlayAction,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
          child: Text(actionText),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/widgets/app_snack_bar.dart';
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

  // Popup state
  bool _showRewardPopup = false;

  @override
  void initState() {
    super.initState();
    _loadGameDetail();
  }

  @override
  void dispose() {
    super.dispose();
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
        final l10n = AppLocalizations.of(context);
        setState(() {
          _errorMessage = response.error ?? l10n.failedToLoadGameDetails;
          _isLoading = false;
        });
      }
    } catch (e) {
      final l10n = AppLocalizations.of(context);
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
      // H5 游戏 - 使用 h5Url 在应用内打开
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
          AppSnackBar.show(context, message: '${l10n.error}: $e');
        }
      }
    } else if (game.isAppGame) {
      // App 游戏 - 使用 downloadUrl 外部下载
      if (game.downloadUrl != null && game.downloadUrl!.isNotEmpty) {
        final uri = Uri.parse(game.downloadUrl!);
        try {
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        } catch (e) {
          if (!mounted) return;
          AppSnackBar.show(context, message: '${l10n.error}: $e');
        }
      }
    }
  }

  void _toggleRewardPopup() {
    setState(() {
      _showRewardPopup = !_showRewardPopup;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return GradientScaffold(
      body: Stack(
        children: [
          _buildMainContent(theme, l10n),
          if (_showRewardPopup) _buildRewardPopup(l10n),
        ],
      ),
    );
  }

  Widget _buildMainContent(ThemeData theme, AppLocalizations l10n) {
    final game = _gameDetail;

    return Stack(
      children: [
        // Scrollable content
        SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 50), // Space for fixed back button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (game != null) ...[
                        _buildHeader(game, l10n),
                        const SizedBox(height: 20),
                        _buildRatingsDownload(game, l10n),
                        const SizedBox(height: 20),
                        _buildInstallButton(game, l10n),
                        const SizedBox(height: 24),
                        _buildShareRow(l10n),
                        const SizedBox(height: 24),
                        _buildScreenshots(game, l10n),
                        const SizedBox(height: 24),
                        _buildAboutSection(game, l10n),
                        const SizedBox(height: 24),
                        _buildDeveloperInfo(game, l10n),
                        const SizedBox(height: 24),
                        _buildReviewsSection(game, l10n),
                        const SizedBox(height: 24),
                      ] else ...[
                        _buildHeaderSkeleton(),
                        const SizedBox(height: 20),
                        _buildRatingsDownloadSkeleton(),
                        const SizedBox(height: 20),
                        _buildInstallButtonSkeleton(),
                        const SizedBox(height: 24),
                        _buildShareRow(l10n),
                        const SizedBox(height: 24),
                        _buildScreenshotsSkeleton(),
                        const SizedBox(height: 24),
                        _buildAboutSectionSkeleton(),
                        const SizedBox(height: 24),
                        _buildDeveloperInfoSkeleton(),
                        const SizedBox(height: 24),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Fixed back button
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingOverlay(AppLocalizations l10n) {
    return Container(
      color: const Color(0xFF13131A),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.loadingLower,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(ThemeData theme, AppLocalizations l10n) {
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

  Widget _buildHeader(GameDetail? game, AppLocalizations l10n) {
    final iconUrl = game?.icon;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // App icon with progress indicator
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: (iconUrl != null && iconUrl.isNotEmpty)
                    ? Image.network(
                        iconUrl,
                        width: 80,
                        height: 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildIconPlaceholder(),
                      )
                    : _buildIconPlaceholder(),
              ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row with game name and verified badge
              Row(
                children: [
                  Flexible(
                    child: Text(
                      game?.name ?? '',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Image.asset(
                    'assets/images/gamename.png',
                    width: 16,
                    height: 16,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Developer/Category with green background pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF028760).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  game?.description ?? '',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF028760),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              // Verified by Play Protect
              Row(
                children: [
                  Container(
                    width: 14,
                    height: 16,
                    decoration: BoxDecoration(
                      color: const Color(0xFF028760),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Icon(
                      Icons.shield,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.verifiedByPlayProtect,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF555555),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderSkeleton() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 20,
                width: 150,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                height: 16,
                width: 100,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                height: 12,
                width: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIconPlaceholder() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: const Color(0xFFF5F5F5),
      ),
      child: const Icon(
        Icons.videogame_asset,
        size: 40,
        color: Color(0xFFCCCCCC),
      ),
    );
  }

  Widget _buildRatingsDownload(GameDetail game, AppLocalizations l10n) {
    // Generate mock data for demo
    const rating = '5.0';
    const reviewCount = '193';
    const downloadCount = '24K+';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildRatingItem(rating, reviewCount, l10n),
          _buildDivider(),
          _buildDownloadItem(downloadCount, l10n),
          _buildDivider(),
          _buildEditorChoice(l10n),
        ],
      ),
    );
  }

  Widget _buildRatingsDownloadSkeleton() {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildInstallButtonSkeleton() {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFF028760),
        borderRadius: BorderRadius.circular(25),
      ),
    );
  }

  Widget _buildScreenshotsSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 20,
          width: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, __) => Container(
              width: 120,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRatingItem(String rating, String reviewCount, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rating,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 2),
            const Text(
              '★',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFFBB33),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$reviewCount ${l10n.reviewsCount}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadItem(String count, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.downloadsLower,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildEditorChoice(AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/cp.png',
          width: 16,
          height: 16,
          color: const Color(0xFFFFD700),
          errorBuilder: (_, __, ___) => const Icon(
            Icons.star,
            size: 16,
            color: Color(0xFFFFD700),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          l10n.editorsChoice,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w400,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      height: 30,
      width: 1,
      color: Colors.white24,
    );
  }

  Widget _buildInstallButton(GameDetail game, AppLocalizations l10n) {
    final isDownload = game.isAppGame;
    final buttonText = isDownload ? l10n.install : l10n.playNow;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _handlePlayAction,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF028760),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isDownload) ...[
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
              ),
                child: const Icon(
                  Icons.shield,
                  size: 14,
                  color: Color(0xFFFFE336),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              buttonText,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShareRow(AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildShareItem('assets/images/share.png', l10n.shareLower),
        const SizedBox(width: 24),
        _buildShareItem('assets/images/addwishlist.png', l10n.addToWishlist),
      ],
    );
  }

  Widget _buildShareItem(String iconPath, String label) {
    return GestureDetector(
      onTap: () {},
      child: Row(
        children: [
          Image.asset(
            iconPath,
            width: 17,
            height: 20,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.share,
              size: 17,
              color: Color(0xFF00A173),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF00A173),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScreenshots(GameDetail game, AppLocalizations l10n) {
    final urls = _parseBannerUrls(game.banner);
    if (urls.isEmpty) {
      return _buildMockScreenshots(l10n);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.screenshots,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 15),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: urls.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final url = urls[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  width: 120,
                  height: 200,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: 120,
                      height: 200,
                      color: const Color(0xFF2A2A2A),
                      child: const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) =>
                      _buildScreenshotPlaceholder(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMockScreenshots(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.screenshots,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 15),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              return Container(
                width: 120,
                height: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Color.lerp(
                    const Color(0xFF2A2A2A),
                    const Color(0xFF3A3A3A),
                    index * 0.1,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.screenshot,
                        size: 40,
                        color: Colors.white38,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Screenshot ${index + 1}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScreenshotPlaceholder() {
    return Container(
      width: 120,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: const Color(0xFF2A2A2A),
      ),
      child: const Center(
        child: Icon(
          Icons.image,
          size: 40,
          color: Colors.white38,
        ),
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

  Widget _buildAboutSection(GameDetail game, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.aboutThisGame,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          game.description ?? l10n.noDescriptionAvailable,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white70,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildAboutSectionSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 20,
          width: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }

  Widget _buildDeveloperInfoSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 20,
          width: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.white.withValues(alpha: 0.1),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 16,
          width: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.white.withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }

  Widget _buildDeveloperInfo(GameDetail game, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.developer,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          game.gameTypeDesc ?? l10n.unknownDeveloper,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildReviewsSection(GameDetail game, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.ratingsAndReviews,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 15),
        // Mock reviews for demo
        _buildReviewItem('Ahmed K.', 5, 'Best game I\'ve played in months! Highly addictive gameplay.'),
        const SizedBox(height: 10),
        _buildReviewItem('Sarah M.', 5, 'Amazing graphics and smooth performance. Love it!'),
        const SizedBox(height: 10),
        _buildReviewItem('Mohammed R.', 4, 'Great story mode, but could use more characters.'),
        const SizedBox(height: 10),
        _buildReviewItem('Fatima H.', 4, 'Fun and entertaining. Would recommend to friends.'),
        const SizedBox(height: 10),
        _buildReviewItem('Omar B.', 5, 'Absolutely fantastic! Can\'t stop playing.'),
      ],
    );
  }

  Widget _buildReviewItem(String userName, int rating, String content) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                userName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Row(
                children: List.generate(5, (index) {
                  return Text(
                    index < rating ? '★' : '☆',
                    style: const TextStyle(
                      color: Color(0xFFFFBB33),
                      fontSize: 14,
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardPopup(AppLocalizations l10n) {
    final game = _gameDetail;
    if (game == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _toggleRewardPopup,
      child: Container(
        color: Colors.black.withValues(alpha: 0.5),
        child: Center(
          child: GestureDetector(
            onTap: () {},
        child: Container(
          width: MediaQuery.of(context).size.width * 0.85,
          constraints: const BoxConstraints(maxWidth: 400),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/img_reward.png',
                    width: 166,
                    height: 80,
                    errorBuilder: (_, __, ___) => Container(
                      width: 166,
                      height: 80,
                      color: const Color(0xFFF5F5F5),
                      child: const Icon(Icons.card_giftcard, size: 40),
                    ),
                  ),
                  const SizedBox(height: 20),
                  RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 17,
                        color: Color(0xFF333333),
                        height: 24,
                      ),
                      children: [
                        TextSpan(
                          text: l10n.rewardCollectingReviews('objective'),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  _buildRewardAppInfo(game),
                  const SizedBox(height: 15),
                  _buildRewardDetails(l10n),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        _toggleRewardPopup();
                        _handlePlayAction();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF028760),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(5),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        l10n.install,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRewardAppInfo(GameDetail game) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: game.icon != null && game.icon!.isNotEmpty
                ? Image.network(
                    game.icon!,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildIconPlaceholder(),
                  )
                : _buildIconPlaceholder(),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        game.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF222222),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Image.asset(
                      'assets/images/gamename.png',
                      width: 20,
                      height: 20,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  game.description ?? 'Short drama series',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF777777),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Image.asset(
                      'assets/images/dunpan.png',
                      width: 10,
                      height: 14,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      'Verified by Play Protect',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFF333333),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRewardDetails(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/images/google_play_img.png',
          width: 70,
          height: 70,
          errorBuilder: (_, __, ___) => Container(
            width: 70,
            height: 70,
            color: const Color(0xFFF5F5F5),
            child: const Icon(Icons.card_giftcard, size: 30),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF000000),
                height: 18,
              ),
              children: [
                TextSpan(
                  text: l10n.rewardDownloadApp,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: ' ${l10n.rewardLeaveReview('objective')}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: ', ${l10n.rewardChance('\$20')}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

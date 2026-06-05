import 'package:flutter/material.dart';
import 'dart:async' show Timer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../../../components/preload_network_image.dart';
import '../../auth/providers/auth_provider.dart';
import '../../payment/providers/membership_provider.dart';
import '../../recommend/models/drama.dart';
import '../../recommend/utils/drama_navigation.dart';
import '../providers/search_page_provider.dart';

/// ============================================================================
/// 搜索结果页
///
/// 【功能】
/// - 进入默认显示排行列表
/// - 输入搜索词 → 显示搜索结果
/// - 搜索词为空 → 回到排行列表
/// ============================================================================
class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage>
    with SingleTickerProviderStateMixin {
  late final FocusNode _searchFocusNode;
  late final TextEditingController _searchController;
  late final AnimationController _hintAnimController;
  Timer? _hintTimer;

  int _displayedWordIndex = 0;

  /// 排行数据（默认显示）
  List<Drama> get _rankingDramas {
    final search = ref.watch(searchPageProvider);
    if (search.hasActiveSearch) return [];
    return ref.watch(rankingDramasProvider).value ?? [];
  }

  List<String> get _words =>
      ref.watch(recommendedSearchListProvider).value ?? [];

  @override
  void initState() {
    super.initState();
    _searchFocusNode = FocusNode();
    _searchController = TextEditingController(text: widget.initialQuery ?? '');
    _hintAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _searchFocusNode.addListener(_onFocusChanged);
    Future.microtask(() {
      if (mounted) {
        ref.read(searchPageProvider.notifier).clearSearch();
        if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
          ref.read(searchPageProvider.notifier).submitSearch(widget.initialQuery!);
        } else {
          _startHintScroll();
        }
      }
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    _hintAnimController.dispose();
    _searchFocusNode.unfocus();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onDramaTap(Drama drama) {
    openDramaPlayerWithVipCheck(
      context: context,
      drama: drama,
      authState: ref.watch(authProvider),
      memberState: ref.watch(memberStateProvider),
    );
  }

  @override
  Widget build(BuildContext context) {
    final search = ref.watch(searchPageProvider);
    final hasSearch = search.hasActiveSearch;

    // 使用 RepaintBoundary 包裹整个页面，避免不必要的重绘
    return RepaintBoundary(
      child: GradientScaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildSearchBar(),
              const SizedBox(height: 12),
              if (!hasSearch) ...[
                const Padding(
                  padding: EdgeInsetsDirectional.symmetric(horizontal: 16),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'Popularity Hot List',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: hasSearch
                    ? _buildSearchResults(search)
                    : _buildRankingList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onFocusChanged() {
    if (_searchFocusNode.hasFocus) {
      _hintTimer?.cancel();
      setState(() {});
    } else if (_searchController.text.isEmpty) {
      _startHintScroll();
      setState(() {});
    }
  }

  void _startHintScroll() {
    _hintTimer?.cancel();
    _hintAnimController.forward(from: 0);
    _hintTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() {
        _displayedWordIndex = (_displayedWordIndex + 1) % _words.length;
      });
      _hintAnimController.forward(from: 0);
    });
  }

  void _onSubmitted(String query) {
    // 不强制取消焦点，让系统自然处理键盘
    if (query.trim().isEmpty) return;
    ref.read(searchPageProvider.notifier).submitSearch(query);
  }

  Widget _buildSearchBar() {
    final words = _words;
    final isFocused = _searchFocusNode.hasFocus;
    final showHint = words.isNotEmpty && !isFocused;
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 15, 16, 12),
        child: Row(
          children: [
            RtlBackButton(
              onPressed: () => context.pop(),
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 34,
                child: showHint
                  ? Stack(
                      children: [
                        _buildTextField(),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(start: 46),
                                child: ClipRect(
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.5),
                                      end: Offset.zero,
                                    ).animate(CurvedAnimation(
                                      parent: _hintAnimController,
                                      curve: Curves.easeOut,
                                    )),
                                    child: FadeTransition(
                                      opacity: _hintAnimController,
                                      child: Text(
                                        words[_displayedWordIndex % words.length],
                                        style: const TextStyle(
                                          color: Color(0x80FFFFFF),
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : _buildTextField(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Padding(
          padding: EdgeInsetsDirectional.only(start: 14, end: 6),
          child: Image(
            image: AssetImage('assets/images/searchPage_icon.png'),
            width: 14,
            height: 14,
          ),
        ),
        suffixIcon: _searchController.text.isNotEmpty
            ? GestureDetector(
                onTap: () {
                  _searchController.clear();
                  ref.read(searchPageProvider.notifier).clearSearch();
                  setState(() {});
                },
                child: const Icon(Icons.clear, color: Color(0xFF999999), size: 18),
              )
            : null,
        filled: true,
        fillColor: const Color(0x1AFFFFFF),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(50),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        hintStyle: const TextStyle(color: Color(0x80FFFFFF), fontSize: 14),
      ),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      onChanged: (v) {
        ref.read(searchPageProvider.notifier).setQuery(v);
        setState(() {});
      },
      onSubmitted: _onSubmitted,
    );
  }

  Widget _buildRankingList() {
    final dramas = _rankingDramas;
    return RepaintBoundary(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        itemCount: dramas.length,
        itemBuilder: (context, index) => _RankingListItem(
          key: ValueKey(dramas[index].id),
          drama: dramas[index],
          rank: index + 1,
          onTap: () => _onDramaTap(dramas[index]),
        ),
      ),
    );
  }

  Widget _buildSearchResults(SearchPageState search) {
    if (search.isLoadingResults && search.searchResults.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF8F4EFF)),
      );
    }

    if (search.searchResults.isEmpty && !search.isLoadingResults) {
      return Center(
        child: Text(
          'No results found',
          style: TextStyle(color: Colors.grey[500], fontSize: 14),
        ),
      );
    }

    return RepaintBoundary(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is ScrollEndNotification) {
            final metrics = notification.metrics;
            if (metrics.pixels >= metrics.maxScrollExtent - 240) {
              ref.read(searchPageProvider.notifier).loadMoreSearch();
            }
          }
          return false;
        },
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: search.searchResults.length,
          itemBuilder: (context, index) => _SearchResultItem(
            key: ValueKey(search.searchResults[index].id),
            drama: search.searchResults[index],
            onTap: () => _onDramaTap(search.searchResults[index]),
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// 搜索结果卡片（ListView 风格）
///
/// 封面图 + 标题 + 观看数 + 评分
/// ============================================================================
class _SearchResultItem extends StatelessWidget {
  const _SearchResultItem({
    super.key,
    required this.drama,
    required this.onTap,
  });

  final Drama drama;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 105,
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: PreloadNetworkImage(
                  imageUrl: drama.coverUrl,
                  preloadAsset: 'assets/images/small_preload_bg.png',
                  width: 74,
                  height: 105,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              // 文字区
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      drama.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      drama.description,
                      style: const TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Translated Series',
                      style: TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// 排行列表卡片
///
/// 左侧排名号 + 封面图 + 标题 + 观看数 + 评分
/// ============================================================================
class _RankingListItem extends StatelessWidget {
  const _RankingListItem({
    super.key,
    required this.drama,
    required this.rank,
    required this.onTap,
  });

  final Drama drama;
  final int rank;
  final VoidCallback onTap;

  String get _rankAsset {
    switch (rank) {
      case 1:
        return 'assets/images/search_top_1.png';
      case 2:
        return 'assets/images/search_top_2.png';
      case 3:
        return 'assets/images/search_top_3.png';
      default:
        return '';
    }
  }

  bool get _hasRankImage => rank <= 3;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 105,
          margin: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              // 排行标签
              SizedBox(
                width: 24,
                child: _hasRankImage
                    ? Image.asset(_rankAsset, width: 24, height: 24)
                    : Text(
                        '$rank',
                        style: const TextStyle(
                          color: Color(0xFF999999),
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
              const SizedBox(width: 7),
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: PreloadNetworkImage(
                  imageUrl: drama.coverUrl,
                  preloadAsset: 'assets/images/small_preload_bg.png',
                  width: 74,
                  height: 105,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 10),
              // 文字区
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      drama.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      drama.description,
                      style: const TextStyle(
                        color: Color(0xFF999999),
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Translated Series',
                      style: TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              // 热度
              Row(
                textDirection: TextDirection.ltr,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Image(
                    image: AssetImage('assets/images/search_hot_icon.png'),
                    width: 18,
                    height: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    drama.formattedViews,
                    style: const TextStyle(
                      color: Color(0xFFFFB92E),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
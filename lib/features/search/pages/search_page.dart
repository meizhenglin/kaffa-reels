import 'package:flutter/material.dart';
import 'dart:async' show Timer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../home/models/home_card_layout.dart';
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color.fromRGBO(255, 255, 255, 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: TextField(
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
          prefixIconConstraints: const BoxConstraints(
            minWidth: 34,
            minHeight: 34,
          ),
          suffixIcon: _searchController.text.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    ref.read(searchPageProvider.notifier).clearSearch();
                    setState(() {});
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Image(
                      image: AssetImage('assets/images/search_del_icon.png'),
                      width: 18,
                      height: 18,
                    ),
                  ),
                )
              : null,
          filled: true,
          fillColor: Colors.transparent,
          hintText: '',
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(999),
            borderSide: BorderSide.none,
          ),
        ),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        cursorColor: Colors.white,
        onChanged: (value) {
          setState(() {});
          ref.read(searchPageProvider.notifier).setQuery(value);
        },
        onSubmitted: _onSubmitted,
      ),
    );
  }

  Widget _buildSearchResults(SearchPageState search) {
    if (search.isLoadingResults && search.searchResults.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (search.errorMessage != null && search.searchResults.isEmpty) {
      return Center(
        child: Text(
          search.errorMessage!,
          style: const TextStyle(color: Colors.white70),
        ),
      );
    }
    if (search.searchResults.isEmpty) {
      return const Center(
        child: Text(
          'No results',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >=
            notification.metrics.maxScrollExtent - 200) {
          ref.read(searchPageProvider.notifier).loadMoreSearch();
        }
        return false;
      },
      child: ListView.builder(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
        itemCount: search.searchResults.length + (search.isLoadingResults ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= search.searchResults.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return _SearchResultItem(
            drama: search.searchResults[index],
            onTap: () => _onDramaTap(search.searchResults[index]),
          );
        },
      ),
    );
  }

  Widget _buildRankingList() {
    final dramas = _rankingDramas;
    if (dramas.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 24),
      itemCount: dramas.length,
      itemBuilder: (context, index) {
        return _RankingListItem(
          drama: dramas[index],
          rank: index + 1,
          onTap: () => _onDramaTap(dramas[index]),
        );
      },
    );
  }
}

class _SearchResultItem extends StatelessWidget {
  const _SearchResultItem({
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

class _SearchTagSeparator extends StatelessWidget {
  const _SearchTagSeparator({required this.gap});

  final double gap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gap),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xFF999999),
          shape: BoxShape.circle,
        ),
        child: SizedBox(width: 3, height: 3),
      ),
    );
  }
}

class _RankingListItem extends StatelessWidget {
  const _RankingListItem({
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

  double _titleMaxWidth(BuildContext context) {
    return HomeCardLayout.bannerScaled(context, 153);
  }

  List<String> get _labelItems =>
      drama.videoLabelNames
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();

  @override
  Widget build(BuildContext context) {
    final rankWidth = HomeCardLayout.bannerScaled(context, 24);
    final rankGap = HomeCardLayout.bannerScaled(context, 7);
    final coverWidth = HomeCardLayout.bannerScaled(context, 74);
    final coverHeight = HomeCardLayout.bannerScaled(context, 105);
    final coverGap = HomeCardLayout.bannerScaled(context, 10);
    final rowGap = HomeCardLayout.bannerScaled(context, 4);
    final hotIconSize = HomeCardLayout.bannerScaled(context, 18);
    final hotGap = HomeCardLayout.bannerScaled(context, 4);

    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: HomeCardLayout.bannerScaled(context, 12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: rankWidth,
                  child: _hasRankImage
                      ? Image.asset(
                          _rankAsset,
                          width: rankWidth,
                          height: rankWidth,
                        )
                      : Text(
                          '$rank',
                          style: TextStyle(
                            color: const Color(0xFF999999),
                            fontSize: HomeCardLayout.bannerScaled(context, 18),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
                SizedBox(width: rankGap),
                ClipRRect(
                  borderRadius: BorderRadius.circular(
                    HomeCardLayout.bannerScaled(context, 10),
                  ),
                  child: PreloadNetworkImage(
                    imageUrl: drama.coverUrl,
                    preloadAsset: 'assets/images/small_preload_bg.png',
                    width: coverWidth,
                    height: coverHeight,
                    fit: BoxFit.cover,
                  ),
                ),
                SizedBox(width: coverGap),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: _titleMaxWidth(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        drama.title,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: HomeCardLayout.bannerScaled(context, 14),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: rowGap),
                      Text(
                        drama.description,
                        style: TextStyle(
                          color: const Color(0xFF999999),
                          fontSize: HomeCardLayout.bannerScaled(context, 11),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_labelItems.isNotEmpty) ...[
                        SizedBox(height: rowGap),
                        SizedBox(
                          width: _titleMaxWidth(context),
                          child: Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              for (var i = 0; i < _labelItems.length; i++) ...[
                                if (i > 0) _SearchTagSeparator(gap: HomeCardLayout.bannerScaled(context, 8)),
                                Text(
                                  _labelItems[i],
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    fontSize: HomeCardLayout.bannerScaled(context, 12),
                                    color: const Color(0xFF999999),
                                    height: 18 / 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                Row(
                  textDirection: TextDirection.ltr,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/search_hot_icon.png',
                      width: hotIconSize,
                      height: hotIconSize,
                    ),
                    SizedBox(width: hotGap),
                    Text(
                      '${drama.hotIndex}',
                      style: TextStyle(
                        color: const Color(0xFFFFB92E),
                        fontSize: HomeCardLayout.bannerScaled(context, 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

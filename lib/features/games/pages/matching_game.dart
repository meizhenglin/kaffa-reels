import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../providers/games_provider.dart';

class MatchingItem {
  final String id;
  final String title;
  final String imageUrl;
  bool isFlipped;
  bool isMatched;

  MatchingItem({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.isFlipped = false,
    this.isMatched = false,
  });

  MatchingItem copyWith({
    bool? isFlipped,
    bool? isMatched,
  }) {
    return MatchingItem(
      id: id,
      title: title,
      imageUrl: imageUrl,
      isFlipped: isFlipped ?? this.isFlipped,
      isMatched: isMatched ?? this.isMatched,
    );
  }
}

class MatchingGamePage extends ConsumerStatefulWidget {
  const MatchingGamePage({super.key});

  @override
  ConsumerState<MatchingGamePage> createState() => _MatchingGamePageState();
}

class _MatchingGamePageState extends ConsumerState<MatchingGamePage> {
  late List<MatchingItem> _items;
  int? _firstIndex;
  int? _secondIndex;
  bool _isProcessing = false;
  int _elapsedSeconds = 0;
  Timer? _timer;
  bool _gameStarted = false;
  bool _gameCompleted = false;

  @override
  void initState() {
    super.initState();
    _initGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _initGame() {
    final pairs = [
      _createPair('d1', 'Desert Love / حب الصحراء',
          'https://picsum.photos/seed/drama1/200/280'),
      _createPair('d2', 'Cairo Nights / ليالي القاهرة',
          'https://picsum.photos/seed/drama2/200/280'),
      _createPair('d3', 'Golden Sands / الرمال الذهبية',
          'https://picsum.photos/seed/drama3/200/280'),
      _createPair('d4', 'Royal Secret / سر ملكي',
          'https://picsum.photos/seed/drama4/200/280'),
    ];

    final allItems = pairs.expand((pair) => pair).toList();
    allItems.shuffle(Random());

    setState(() {
      _items = allItems;
      _firstIndex = null;
      _secondIndex = null;
      _isProcessing = false;
      _elapsedSeconds = 0;
      _gameStarted = false;
      _gameCompleted = false;
    });

    _timer?.cancel();
  }

  List<MatchingItem> _createPair(String id, String title, String imageUrl) {
    return [
      MatchingItem(id: '${id}_img', title: '', imageUrl: imageUrl),
      MatchingItem(id: '${id}_txt', title: title, imageUrl: ''),
    ];
  }

  void _startTimer() {
    if (_gameStarted) return;
    setState(() => _gameStarted = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  void _flipCard(int index) {
    if (_isProcessing || _items[index].isFlipped || _items[index].isMatched) {
      return;
    }

    _startTimer();

    setState(() {
      _items[index] = _items[index].copyWith(isFlipped: true);
    });

    if (_firstIndex == null) {
      _firstIndex = index;
    } else {
      _secondIndex = index;
      _checkMatch();
    }
  }

  void _checkMatch() {
    _isProcessing = true;

    final first = _items[_firstIndex!];
    final second = _items[_secondIndex!];

    // Extract pair ID from item ID
    final firstPairId = first.id.replaceAll('_img', '').replaceAll('_txt', '');
    final secondPairId = second.id.replaceAll('_img', '').replaceAll('_txt', '');

    if (firstPairId == secondPairId) {
      // Match!
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        setState(() {
          _items[_firstIndex!] = _items[_firstIndex!].copyWith(isMatched: true);
          _items[_secondIndex!] = _items[_secondIndex!].copyWith(isMatched: true);
          _firstIndex = null;
          _secondIndex = null;
          _isProcessing = false;
        });

        _checkCompletion();
      });
    } else {
      // No match
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (!mounted) return;
        setState(() {
          _items[_firstIndex!] = _items[_firstIndex!].copyWith(isFlipped: false);
          _items[_secondIndex!] = _items[_secondIndex!].copyWith(isFlipped: false);
          _firstIndex = null;
          _secondIndex = null;
          _isProcessing = false;
        });
      });
    }
  }

  void _checkCompletion() {
    if (_items.every((item) => item.isMatched)) {
      _timer?.cancel();
      setState(() => _gameCompleted = true);

      ref.read(gameScoresProvider.notifier).updateMatchingTime(_elapsedSeconds);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.celebration, color: Colors.amber),
              const SizedBox(width: 8),
              const Text('恭喜通关!'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatTime(_elapsedSeconds),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              const SizedBox(height: 8),
              const Text('完成时间'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: const Text('返回'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _initGame();
              },
              child: const Text('再玩一次'),
            ),
          ],
        ),
      );
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              // 返回按钮和时间
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    _formatTime(_elapsedSeconds),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '将剧集名称与图片配对',
                style: TextStyle(
                  color: Colors.grey[400],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    childAspectRatio: 0.7,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    return _buildCard(_items[index], index);
                  },
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _initGame,
                icon: const Icon(Icons.refresh),
                label: const Text('重新开始'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(MatchingItem item, int index) {
    return GestureDetector(
      onTap: () => _flipCard(index),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (child, animation) {
          return ScaleTransition(scale: animation, child: child);
        },
        child: item.isFlipped || item.isMatched
            ? _buildFront(item)
            : _buildBack(),
      ),
    );
  }

  Widget _buildBack() {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          Icons.question_mark,
          size: 32,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildFront(MatchingItem item) {
    final isImage = item.imageUrl.isNotEmpty;

    return Card(
      color: item.isMatched
          ? Colors.green.withAlpha(51)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isImage)
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    item.imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.movie),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: Center(
                  child: Text(
                    item.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (item.isMatched)
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
          ],
        ),
      ),
    );
  }
}

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../components/rtl_back_button.dart';
import '../providers/games_provider.dart';

class GuessLineQuestion {
  final String imageUrl;
  final String correctAnswer;
  final List<String> options;
  final String hint;

  const GuessLineQuestion({
    required this.imageUrl,
    required this.correctAnswer,
    required this.options,
    required this.hint,
  });
}

class GuessLineMockData {
  static const _covers = [
    'https://picsum.photos/seed/drama1/400/600',
    'https://picsum.photos/seed/drama2/400/720',
    'https://picsum.photos/seed/drama3/400/540',
    'https://picsum.photos/seed/drama4/400/680',
    'https://picsum.photos/seed/drama5/400/620',
    'https://picsum.photos/seed/drama6/400/700',
  ];

  static final _questions = [
    GuessLineQuestion(
      imageUrl: _covers[0],
      correctAnswer: '我等了你一千年',
      options: ['我等了你一千年', '我们该分开了', '你永远不懂我', '这是我们的约定'],
      hint: '这句经典台词来自...',
    ),
    GuessLineQuestion(
      imageUrl: _covers[1],
      correctAnswer: '你的笑容是我的全部',
      options: ['我们只是朋友', '你的笑容是我的全部', '我不爱你了', '这是谎言'],
      hint: '男主角对女主说的话',
    ),
    GuessLineQuestion(
      imageUrl: _covers[2],
      correctAnswer: '为了你，我愿意放弃一切',
      options: ['金钱更重要', '为了你，我愿意放弃一切', '这不可能', '你是谁'],
      hint: '感人至深的告白',
    ),
    GuessLineQuestion(
      imageUrl: _covers[3],
      correctAnswer: '命中注定我们相遇',
      options: ['这是巧合', '命中注定我们相遇', '我不认识你', '别缠着我'],
      hint: '命运安排的相遇',
    ),
    GuessLineQuestion(
      imageUrl: _covers[4],
      correctAnswer: '我会永远守护你',
      options: ['我会永远守护你', '我们分手吧', '你太弱了', '这是命令'],
      hint: '骑士的誓言',
    ),
    GuessLineQuestion(
      imageUrl: _covers[5],
      correctAnswer: '爱让我们在一起',
      options: ['爱让我们在一起', '爱是痛苦的', '我恨你', '一切都是假的'],
      hint: 'happy ending 台词',
    ),
  ];

  static List<GuessLineQuestion> getDailyQuestions(int count) {
    final random = Random(DateTime.now().day);
    final shuffled = List<GuessLineQuestion>.from(_questions)..shuffle(random);
    return shuffled.take(count).toList();
  }
}

class GuessLineGamePage extends ConsumerStatefulWidget {
  const GuessLineGamePage({super.key});

  @override
  ConsumerState<GuessLineGamePage> createState() => _GuessLineGamePageState();
}

class _GuessLineGamePageState extends ConsumerState<GuessLineGamePage> {
  late List<GuessLineQuestion> _questions;
  int _currentIndex = 0;
  int _score = 0;
  int? _selectedIndex;
  bool _answered = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadQuestions();
  }

  void _loadQuestions() {
    final notifier = ref.read(gameScoresProvider.notifier);
    final hasPlayed = notifier.hasPlayedGuessLineToday();

    setState(() {
      _questions = GuessLineMockData.getDailyQuestions(5);
      _isLoading = false;
      if (hasPlayed) {
        // Show completion state
      }
    });
  }

  void _selectAnswer(int index) {
    if (_answered) return;

    setState(() {
      _selectedIndex = index;
      _answered = true;

      if (_questions[_currentIndex].options[index] ==
          _questions[_currentIndex].correctAnswer) {
        _score += 20;
      }
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;

      if (_currentIndex < _questions.length - 1) {
        setState(() {
          _currentIndex++;
          _selectedIndex = null;
          _answered = false;
        });
      } else {
        _showResult();
      }
    });
  }

  void _showResult() {
    ref.read(gameScoresProvider.notifier).updateGuessLineScore(_score);
    ref.read(gameScoresProvider.notifier).markGuessLinePlayed(_questions.length);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _score >= 80
                  ? Icons.emoji_events
                  : _score >= 40
                      ? Icons.thumb_up
                      : Icons.sentiment_neutral,
              color: _score >= 80
                  ? Colors.amber
                  : _score >= 40
                      ? Colors.green
                      : Colors.grey,
            ),
            const SizedBox(width: 8),
            const Text('本轮结束'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '得分: $_score / 100',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 16),
            Text(
              _score >= 80
                  ? '太棒了！你是剧迷！'
                  : _score >= 40
                      ? '不错，继续加油！'
                      : '明天再来挑战吧！',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
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
          if (_score < 80)
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _currentIndex = 0;
                  _score = 0;
                  _selectedIndex = null;
                  _answered = false;
                });
              },
              child: const Text('再玩一次'),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final question = _questions[_currentIndex];

    return GradientScaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 返回按钮和分数
              Row(
                children: [
                  RtlBackButton(
                    color: Colors.white,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Spacer(),
                  Text(
                    '$_score 分',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Progress
              Row(
                children: [
                  Text(
                    '第 ${_currentIndex + 1} / ${_questions.length} 题',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  LinearProgressIndicator(
                    value: (_currentIndex + 1) / _questions.length,
                    backgroundColor: Colors.grey[800],
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF5D4391)),
                  ).expandHorizontally(width: 120),
                ],
              ),
              const SizedBox(height: 24),

              // Hint
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text(question.hint)),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Screenshot
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    question.imageUrl,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey[300],
                      child: const Icon(Icons.movie, size: 64),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Options
              Expanded(
                flex: 2,
                child: Column(
                  children: question.options.asMap().entries.map((entry) {
                    final index = entry.key;
                    final option = entry.value;
                    final isSelected = _selectedIndex == index;
                    final isCorrect = option == question.correctAnswer;

                    Color? bgColor;
                    Color? borderColor;
                    if (_answered) {
                      if (isCorrect) {
                        bgColor = Colors.green.withAlpha(51);
                        borderColor = Colors.green;
                      } else if (isSelected && !isCorrect) {
                        bgColor = Colors.red.withAlpha(51);
                        borderColor = Colors.red;
                      }
                    }

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Material(
                          color: bgColor ?? Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            onTap: _answered ? null : () => _selectAnswer(index),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: borderColor ??
                                      Theme.of(context)
                                          .colorScheme
                                          .outline
                                          .withAlpha(128),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              alignment: Alignment.centerLeft,
                              child: Row(
                                children: [
                                  Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: borderColor ??
                                          Theme.of(context)
                                              .colorScheme
                                              .primaryContainer,
                                    ),
                                    child: Center(
                                      child: Text(
                                        String.fromCharCode(65 + index),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: borderColor ?? Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      option,
                                      style: Theme.of(context).textTheme.bodyMedium,
                                    ),
                                  ),
                                  if (_answered && isCorrect)
                                    const Icon(Icons.check_circle,
                                        color: Colors.green),
                                  if (_answered && isSelected && !isCorrect)
                                    const Icon(Icons.cancel, color: Colors.red),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _WidgetExt on Widget {
  Widget expandHorizontally({required double width}) {
    return SizedBox(width: width, child: this);
  }
}

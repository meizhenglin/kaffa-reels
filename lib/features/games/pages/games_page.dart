import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/widgets/gradient_scaffold.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/games_provider.dart';
import '../widgets/game_entry_card.dart';
import 'guess_line_game.dart';
import 'matching_game.dart';
import 'daily_signin.dart';

/// ============================================================================
/// 游戏中心页
///
/// 【功能】
/// - 展示多个游戏入口（看剧猜台词、短剧连连看、每日签到）
/// - 显示各游戏最高分/最佳记录
/// - 点击进入对应游戏页面
///
/// 【游戏列表】
/// - 看剧猜台词：猜截图中的经典台词
/// - 短剧连连看：匹配剧集名称和海报
/// - 每日签到：每日签到获取奖励
///
/// 【如何修改】
/// - 添加新游戏：在 games 列表中添加 _GameInfo
/// - 修改分数显示格式：修改 _formatTime 方法
/// ============================================================================
class GamesPage extends ConsumerWidget {
  const GamesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final gameScores = ref.watch(gameScoresProvider);

    final games = [
      _GameInfo(
        icon: Icons.quiz_outlined,
        title: '看剧猜台词',
        description: 'Guess the famous lines from drama screenshots',
        highScore: gameScores.guessLineHighScore > 0 ? '最高 ${gameScores.guessLineHighScore} 分' : null,
        page: const GuessLineGamePage(),
      ),
      _GameInfo(
        icon: Icons.grid_view_rounded,
        title: '短剧连连看',
        description: 'Match drama titles with their posters',
        highScore: gameScores.matchingBestTime > 0 ? '最佳 ${_formatTime(gameScores.matchingBestTime)}' : null,
        page: const MatchingGamePage(),
      ),
      _GameInfo(
        icon: Icons.calendar_today_outlined,
        title: '每日签到',
        description: 'Sign in daily to earn rewards',
        highScore: gameScores.signInStreak > 0 ? '连续 ${gameScores.signInStreak} 天' : null,
        page: const DailySigninPage(),
      ),
    ];

    return GradientScaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '趣味游戏',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.85,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: games.length,
                  itemBuilder: (context, index) {
                    final game = games[index];
                    return GameEntryCard(
                      icon: game.icon,
                      title: game.title,
                      description: game.description,
                      highScore: game.highScore,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => game.page),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

/// 游戏信息数据类
class _GameInfo {
  const _GameInfo({
    required this.icon,
    required this.title,
    required this.description,
    this.highScore,
    required this.page,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? highScore;
  final Widget page;
}

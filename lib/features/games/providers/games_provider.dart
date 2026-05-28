import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for SharedPreferences instance
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) async {
  return await SharedPreferences.getInstance();
});

/// Game scores provider
final gameScoresProvider =
    StateNotifierProvider<GameScoresNotifier, GameScores>((ref) {
  return GameScoresNotifier(ref);
});

class GameScores {
  final int guessLineHighScore;
  final int matchingBestTime; // in seconds, 0 means not played
  final int signInStreak;
  final String lastSignInDate;

  const GameScores({
    this.guessLineHighScore = 0,
    this.matchingBestTime = 0,
    this.signInStreak = 0,
    this.lastSignInDate = '',
  });

  GameScores copyWith({
    int? guessLineHighScore,
    int? matchingBestTime,
    int? signInStreak,
    String? lastSignInDate,
  }) {
    return GameScores(
      guessLineHighScore: guessLineHighScore ?? this.guessLineHighScore,
      matchingBestTime: matchingBestTime ?? this.matchingBestTime,
      signInStreak: signInStreak ?? this.signInStreak,
      lastSignInDate: lastSignInDate ?? this.lastSignInDate,
    );
  }
}

class GameScoresNotifier extends StateNotifier<GameScores> {
  final Ref _ref;
  SharedPreferences? _prefs;

  static const _keyGuessLineHighScore = 'guess_line_high_score';
  static const _keyMatchingBestTime = 'matching_best_time';
  static const _keySignInStreak = 'sign_in_streak';
  static const _keyLastSignInDate = 'last_sign_in_date';
  static const _keyGuessLinePlayedDate = 'guess_line_played_date';
  static const _keyGuessLineQuestionsAnswered = 'guess_line_questions_answered';

  GameScoresNotifier(this._ref) : super(const GameScores()) {
    _loadScores();
  }

  Future<void> _loadScores() async {
    _prefs = await _ref.read(sharedPreferencesProvider.future);
    if (_prefs == null) return;

    state = GameScores(
      guessLineHighScore: _prefs!.getInt(_keyGuessLineHighScore) ?? 0,
      matchingBestTime: _prefs!.getInt(_keyMatchingBestTime) ?? 0,
      signInStreak: _prefs!.getInt(_keySignInStreak) ?? 0,
      lastSignInDate: _prefs!.getString(_keyLastSignInDate) ?? '',
    );
  }

  String _todayString() {
    return DateTime.now().toIso8601String().substring(0, 10);
  }

  Future<void> updateGuessLineScore(int score) async {
    _prefs ??= await _ref.read(sharedPreferencesProvider.future);
    if (_prefs == null) return;

    final highScore = _prefs!.getInt(_keyGuessLineHighScore) ?? 0;
    if (score > highScore) {
      await _prefs!.setInt(_keyGuessLineHighScore, score);
      state = state.copyWith(guessLineHighScore: score);
    }
  }

  Future<void> updateMatchingTime(int timeSeconds) async {
    _prefs ??= await _ref.read(sharedPreferencesProvider.future);
    if (_prefs == null) return;

    final bestTime = _prefs!.getInt(_keyMatchingBestTime) ?? 0;
    if (bestTime == 0 || timeSeconds < bestTime) {
      await _prefs!.setInt(_keyMatchingBestTime, timeSeconds);
      state = state.copyWith(matchingBestTime: timeSeconds);
    }
  }

  Future<void> signIn() async {
    _prefs ??= await _ref.read(sharedPreferencesProvider.future);
    if (_prefs == null) return;

    final today = _todayString();
    final lastDate = _prefs!.getString(_keyLastSignInDate) ?? '';

    if (lastDate == today) {
      return; // Already signed in today
    }

    int newStreak = 1;
    if (lastDate.isNotEmpty) {
      final last = DateTime.parse(lastDate);
      final diff = DateTime.now().difference(last).inDays;
      if (diff == 1) {
        // Consecutive day
        newStreak = (_prefs!.getInt(_keySignInStreak) ?? 0) + 1;
      }
    }

    await _prefs!.setString(_keyLastSignInDate, today);
    await _prefs!.setInt(_keySignInStreak, newStreak);
    state = state.copyWith(
      signInStreak: newStreak,
      lastSignInDate: today,
    );
  }

  bool hasPlayedGuessLineToday() {
    _prefs ??= _ref.read(sharedPreferencesProvider).maybeWhen(
          data: (p) => p,
          orElse: () => null,
        );
    if (_prefs == null) return false;

    final playedDate = _prefs!.getString(_keyGuessLinePlayedDate) ?? '';
    return playedDate == _todayString();
  }

  Future<void> markGuessLinePlayed(int questionsAnswered) async {
    _prefs ??= await _ref.read(sharedPreferencesProvider.future);
    if (_prefs == null) return;

    await _prefs!.setString(_keyGuessLinePlayedDate, _todayString());
    await _prefs!.setInt(_keyGuessLineQuestionsAnswered, questionsAnswered);
  }

  int getGuessLineQuestionsAnswered() {
    return _prefs?.getInt(_keyGuessLineQuestionsAnswered) ?? 0;
  }
}

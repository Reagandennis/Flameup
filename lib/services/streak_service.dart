import 'package:shared_preferences/shared_preferences.dart';

/// Tracks daily task-completion streaks locally in SharedPreferences.
class StreakRecord {
  const StreakRecord({
    required this.current,
    required this.longest,
    required this.totalCompleted,
    required this.lastDate,
  });

  final int current;
  final int longest;
  final int totalCompleted;
  final String lastDate;

  bool get completedToday => lastDate == StreakService._todayKey();
}

class StreakService {
  StreakService._();

  static final StreakService _instance = StreakService._();

  factory StreakService() => _instance;

  static const String _prefix = 'flameup.streak.';

  Future<StreakRecord> getStreak(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _readRecord(prefs, userId);
  }

  /// Call whenever a task is marked done. Idempotent within the same day.
  Future<StreakRecord> recordCompletion(String userId) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final StreakRecord current = _readRecord(prefs, userId);

    final String today = _todayKey();
    final String yesterday = _yesterdayKey();

    int streak = current.current;
    int longest = current.longest;
    int total = current.totalCompleted;
    String lastDate = current.lastDate;

    total += 1;
    if (lastDate == today) {
      // Already counted today — only bump total
    } else if (lastDate == yesterday) {
      streak += 1; // consecutive day
    } else {
      streak = 1; // broken streak or first time
    }
    lastDate = today;
    if (streak > longest) longest = streak;

    await prefs.setInt('$_prefix$userId.current', streak);
    await prefs.setInt('$_prefix$userId.longest', longest);
    await prefs.setInt('$_prefix$userId.total', total);
    await prefs.setString('$_prefix$userId.lastDate', lastDate);

    return StreakRecord(
      current: streak,
      longest: longest,
      totalCompleted: total,
      lastDate: lastDate,
    );
  }

  StreakRecord _readRecord(SharedPreferences prefs, String userId) {
    return StreakRecord(
      current: prefs.getInt('$_prefix$userId.current') ?? 0,
      longest: prefs.getInt('$_prefix$userId.longest') ?? 0,
      totalCompleted: prefs.getInt('$_prefix$userId.total') ?? 0,
      lastDate: prefs.getString('$_prefix$userId.lastDate') ?? '',
    );
  }

  static String _todayKey() {
    final DateTime now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  static String _yesterdayKey() {
    final DateTime y = DateTime.now().subtract(const Duration(days: 1));
    return '${y.year}-${y.month.toString().padLeft(2, '0')}-'
        '${y.day.toString().padLeft(2, '0')}';
  }
}

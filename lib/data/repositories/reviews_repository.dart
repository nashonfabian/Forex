import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/clock.dart';
import '../../core/db/table_changes.dart';
import '../../core/format.dart';
import '../../core/rows.dart';
import 'base_repository.dart';

class WeeklyStats {
  const WeeklyStats({
    required this.lessonsCompleted,
    required this.studyDays,
    required this.minutes,
    required this.casesCreated,
    required this.casesClosed,
    required this.supported,
    required this.contradicted,
    required this.inconclusive,
    required this.demoTrades,
    required this.liveTrades,
    required this.brokenRules,
    required this.openQuestions,
  });

  final int lessonsCompleted;
  final int studyDays;
  final int minutes;
  final int casesCreated;
  final int casesClosed;
  final int supported;
  final int contradicted;
  final int inconclusive;
  final int demoTrades;
  final int liveTrades;
  final int brokenRules;
  final List<String> openQuestions;

  Map<String, Object?> toJson() => {
        'lessons_completed': lessonsCompleted,
        'study_days': studyDays,
        'minutes': minutes,
        'cases_created': casesCreated,
        'cases_closed': casesClosed,
        'supported': supported,
        'contradicted': contradicted,
        'inconclusive': inconclusive,
        'demo_trades': demoTrades,
        'live_trades': liveTrades,
        'broken_rules': brokenRules,
        'open_questions': openQuestions.length,
      };
}

class ReviewsRepository extends BaseRepository {
  ReviewsRepository(super.app, super.changes, super.clock);

  Future<Rec?> reviewFor(String kind, String periodStart) async {
    final rows = await (await db).query(
      'reviews',
      where: 'kind = ? AND period_start = ? AND deleted_at IS NULL',
      whereArgs: [kind, periodStart],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Stream<Rec?> watchReview(String kind, String periodStart) =>
      watchQuery(changes, {'reviews'}, () => reviewFor(kind, periodStart));

  Future<List<Rec>> listReviews(String kind) async => (await db).query(
        'reviews',
        where: 'kind = ? AND deleted_at IS NULL',
        whereArgs: [kind],
        orderBy: 'period_start DESC',
        limit: 200,
      );

  Stream<List<Rec>> watchReviews(String kind) =>
      watchQuery(changes, {'reviews'}, () => listReviews(kind));

  static Map<String, String> answersOf(Rec? review) {
    if (review == null) return {};
    try {
      final decoded = jsonDecode(review.s('answers_json', '{}'));
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry('$k', '$v'));
      }
    } catch (_) {}
    return {};
  }

  // ------------------------------------------------------------ daily
  /// Facts gathered automatically for a day (no typing needed).
  Future<Map<String, int>> dailyFacts(String ymd) async {
    final b = utcBounds(ymd, ymd);
    final database = await db;
    Future<int> count(String sql) async =>
        Sqflite.firstIntValue(await database.rawQuery(sql, b)) ?? 0;
    return {
      'lessons': await count(
          'SELECT COUNT(*) FROM lessons WHERE deleted_at IS NULL AND status = \'completed\' AND completed_at >= ? AND completed_at < ?'),
      'notes': await count(
          'SELECT COUNT(*) FROM notes WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?'),
      'cases': await count(
          'SELECT COUNT(*) FROM research_cases WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?'),
      'minutes': await count(
          'SELECT COALESCE(SUM(minutes), 0) FROM study_sessions WHERE deleted_at IS NULL AND started_at >= ? AND started_at < ?'),
    };
  }

  /// Saves the review for [ymd] and turns the "next action" into a task for tomorrow.
  Future<String> saveDaily({
    required String ymd,
    required Map<String, String> answers,
    required String nextAction,
  }) =>
      write(['reviews', 'daily_tasks'], (txn, now) async {
        final tomorrow = addDaysYmd(ymd, 1);
        final existing = await txn.query('reviews',
            where: "kind = 'daily' AND period_start = ? AND deleted_at IS NULL",
            whereArgs: [ymd],
            limit: 1);

        String? taskId;
        if (existing.isNotEmpty) {
          taskId = answersOf(existing.first)['next_task_id'];
        }
        final action = nextAction.trim();
        if (action.isNotEmpty) {
          var reuse = false;
          if (taskId != null) {
            final found = await txn.query('daily_tasks',
                columns: ['id'], where: 'id = ? AND deleted_at IS NULL', whereArgs: [taskId], limit: 1);
            reuse = found.isNotEmpty;
          }
          if (reuse && taskId != null) {
            await updateIn(txn, 'daily_tasks', taskId, {'title': action, 'plan_date': tomorrow}, now);
          } else {
            taskId = await insertIn(txn, 'daily_tasks', {
              'plan_date': tomorrow,
              'title': action,
              'kind': 'next_action',
              'status': 'todo',
            }, now);
          }
        }

        final json = jsonEncode({
          ...answers,
          if (taskId != null) 'next_task_id': taskId,
        });
        final values = <String, Object?>{
          'kind': 'daily',
          'period_start': ymd,
          'period_end': ymd,
          'answers_json': json,
          'next_actions': action,
        };
        if (existing.isNotEmpty) {
          final id = existing.first['id'] as String;
          await updateIn(txn, 'reviews', id, values, now);
          return id;
        }
        return insertIn(txn, 'reviews', values, now);
      });

  // ------------------------------------------------------------ weekly
  Future<WeeklyStats> weeklyStats(String weekStart) async {
    final weekEnd = addDaysYmd(weekStart, 6);
    final b = utcBounds(weekStart, weekEnd);
    final database = await db;

    Future<int> count(String sql, [List<Object?>? args]) async =>
        Sqflite.firstIntValue(await database.rawQuery(sql, args ?? b)) ?? 0;

    final days = <String>{};
    void addDay(Object? iso) {
      final parsed = iso is String ? DateTime.tryParse(iso) : null;
      if (parsed != null) days.add(formatDate(parsed.toLocal()));
    }

    final completed = await database.rawQuery(
        "SELECT completed_at FROM lessons WHERE deleted_at IS NULL AND status = 'completed' AND completed_at >= ? AND completed_at < ?",
        b);
    for (final r in completed) {
      addDay(r['completed_at']);
    }
    final sessions = await database.rawQuery(
        'SELECT started_at FROM study_sessions WHERE deleted_at IS NULL AND started_at >= ? AND started_at < ?',
        b);
    for (final r in sessions) {
      addDay(r['started_at']);
    }

    var supported = 0;
    var contradicted = 0;
    var inconclusive = 0;
    final verdicts = await database.rawQuery(
        'SELECT hypothesis_verdict AS v, COUNT(*) AS c FROM research_cases '
        'WHERE deleted_at IS NULL AND outcome_at >= ? AND outcome_at < ? GROUP BY hypothesis_verdict',
        b);
    for (final r in verdicts) {
      final c = r.i('c');
      switch (r.s('v')) {
        case 'supported':
          supported += c;
          break;
        case 'contradicted':
          contradicted += c;
          break;
        default:
          inconclusive += c;
      }
    }

    var demo = 0;
    var live = 0;
    final trades = await database.rawQuery(
        'SELECT account_type AS a, COUNT(*) AS c FROM trades '
        'WHERE deleted_at IS NULL AND opened_at >= ? AND opened_at < ? GROUP BY account_type',
        b);
    for (final r in trades) {
      if (r.s('a') == 'live') {
        live += r.i('c');
      } else {
        demo += r.i('c');
      }
    }

    final questions = await database.rawQuery(
        "SELECT COALESCE(title, body_md) AS t FROM notes WHERE deleted_at IS NULL AND kind = 'question' "
        "AND COALESCE(question_status, 'open') = 'open' ORDER BY created_at DESC LIMIT 15");

    return WeeklyStats(
      lessonsCompleted: await count(
          "SELECT COUNT(*) FROM lessons WHERE deleted_at IS NULL AND status = 'completed' AND completed_at >= ? AND completed_at < ?"),
      studyDays: days.length,
      minutes: await count(
          'SELECT COALESCE(SUM(minutes), 0) FROM study_sessions WHERE deleted_at IS NULL AND started_at >= ? AND started_at < ?'),
      casesCreated: await count(
          'SELECT COUNT(*) FROM research_cases WHERE deleted_at IS NULL AND created_at >= ? AND created_at < ?'),
      casesClosed: await count(
          'SELECT COUNT(*) FROM research_cases WHERE deleted_at IS NULL AND outcome_at >= ? AND outcome_at < ?'),
      supported: supported,
      contradicted: contradicted,
      inconclusive: inconclusive,
      demoTrades: demo,
      liveTrades: live,
      brokenRules: await count(
          "SELECT COUNT(*) FROM trades WHERE deleted_at IS NULL AND rule_adherence = 'broken' AND opened_at >= ? AND opened_at < ?"),
      openQuestions: questions.map((r) => r.s('t')).where((t) => t.isNotEmpty).toList(),
    );
  }

  Future<String> saveWeekly({
    required String weekStart,
    required Map<String, String> answers,
    required WeeklyStats stats,
    required String priorities,
  }) =>
      write(['reviews'], (txn, now) async {
        final existing = await txn.query('reviews',
            where: "kind = 'weekly' AND period_start = ? AND deleted_at IS NULL",
            whereArgs: [weekStart],
            limit: 1);
        final values = <String, Object?>{
          'kind': 'weekly',
          'period_start': weekStart,
          'period_end': addDaysYmd(weekStart, 6),
          'answers_json': jsonEncode(answers),
          'next_actions': priorities.trim(),
          'stats_snapshot_json': jsonEncode(stats.toJson()),
        };
        if (existing.isNotEmpty) {
          final id = existing.first['id'] as String;
          await updateIn(txn, 'reviews', id, values, now);
          return id;
        }
        return insertIn(txn, 'reviews', values, now);
      });
}

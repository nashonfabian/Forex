import '../../core/clock.dart';
import '../../core/db/table_changes.dart';
import '../../core/format.dart';
import '../../core/rows.dart';
import '../seed/curriculum_seed.dart';
import 'base_repository.dart';

class TodayData {
  const TodayData({
    required this.ymd,
    required this.tasks,
    required this.totalLessons,
    required this.completedLessons,
    required this.phaseTotal,
    required this.phaseCompleted,
    this.tomorrowTasks = const [],
    this.plan,
    this.todayLesson,
    this.continueLesson,
    this.phaseTitle,
  });

  final String ymd;
  final Rec? plan;
  final Rec? todayLesson;
  final Rec? continueLesson;
  final List<Rec> tasks;
  final List<Rec> tomorrowTasks;
  final int totalLessons;
  final int completedLessons;
  final String? phaseTitle;
  final int phaseTotal;
  final int phaseCompleted;
}

class LearningRepository extends BaseRepository {
  LearningRepository(super.app, super.changes, super.clock);

  // ------------------------------------------------------------ plan
  Future<Rec?> activePlan() async {
    final rows = await (await db).query(
      'study_plans',
      where: "deleted_at IS NULL AND status = 'active'",
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Stream<Rec?> watchActivePlan() =>
      watchQuery(changes, {'study_plans'}, activePlan);

  /// Creates the starter 90-day programme beginning on [start].
  Future<String> createDefaultPlan(DateTime start) {
    final startYmd = formatDate(start);
    return write(['study_plans', 'lessons'], (txn, now) async {
      final existing = await txn.query('study_plans', where: 'deleted_at IS NULL', limit: 1);
      if (existing.isNotEmpty) return existing.first['id'] as String;

      final planId = await insertIn(txn, 'study_plans', {
        'title': '90-Day Auction Theory and Trading Research',
        'description': 'Starter outline. Edit it under Settings > Curriculum.',
        'start_date': startYmd,
        'length_days': 90,
        'status': 'active',
      }, now);

      var order = 0;
      for (var w = 0; w < curriculumSeed.length; w++) {
        final week = curriculumSeed[w];
        for (var d = 0; d < 7; d++) {
          final dayNo = w * 7 + d + 1;
          if (dayNo > 90) break;
          final scheduled = formatDate(DateTime(start.year, start.month, start.day + dayNo - 1));

          String title;
          String objective;
          String? assignment;
          var milestone = false;
          if (d < 5) {
            title = week.lessons[d].title;
            objective = week.lessons[d].objective;
          } else if (d == 5) {
            title = 'Chart review and catch-up';
            objective = 'Revisit this week\'s charts and notes, and close any gaps.';
            if (week.endsPhase) {
              milestone = true;
              assignment = 'Phase milestone: summarise what you learned in "${week.phaseTitle}" in your own words.';
            }
          } else {
            title = 'Rest and light reflection';
            objective = 'No new material. Rest, or read lightly.';
          }

          await insertIn(txn, 'lessons', {
            'plan_id': planId,
            'phase_no': week.phaseNo,
            'phase_title': week.phaseTitle,
            'week_no': w + 1,
            'day_no': dayNo,
            'order_index': order++,
            'title': title,
            'objective': objective,
            'assignment': assignment,
            'is_milestone': milestone ? 1 : 0,
            'status': 'not_started',
            'scheduled_date': scheduled,
          }, now);
        }
      }
      return planId;
    });
  }

  /// Moves every scheduled lesson so that day 1 falls on [start].
  Future<void> rescheduleFrom(String planId, DateTime start) =>
      write(['study_plans', 'lessons'], (txn, now) async {
        await updateIn(txn, 'study_plans', planId, {'start_date': formatDate(start)}, now);
        final lessons = await txn.query('lessons',
            where: 'plan_id = ? AND deleted_at IS NULL AND day_no IS NOT NULL', whereArgs: [planId]);
        for (final l in lessons) {
          final dayNo = l.i('day_no');
          final scheduled = formatDate(DateTime(start.year, start.month, start.day + dayNo - 1));
          await updateIn(txn, 'lessons', l.s('id'), {'scheduled_date': scheduled}, now);
        }
      });

  // ------------------------------------------------------------ lessons
  Future<List<Rec>> lessonsForPlan(String planId) async => (await db).query(
        'lessons',
        where: 'plan_id = ? AND deleted_at IS NULL',
        whereArgs: [planId],
        orderBy: 'order_index ASC',
      );

  Stream<List<Rec>> watchLessons(String planId) =>
      watchQuery(changes, {'lessons'}, () => lessonsForPlan(planId));

  Stream<Rec?> watchLesson(String id) =>
      watchQuery(changes, {'lessons'}, () => getById('lessons', id));

  Future<void> setLessonStatus(String id, String status) =>
      write(['lessons'], (txn, now) => updateIn(txn, 'lessons', id, {
            'status': status,
            'completed_at': status == 'completed' ? now : null,
          }, now));

  Future<void> updateLesson(String id, Map<String, Object?> values) =>
      write(['lessons'], (txn, now) => updateIn(txn, 'lessons', id, values, now));

  Future<String> addLesson(String planId, Map<String, Object?> values) =>
      write(['lessons'], (txn, now) async {
        final max = await txn.rawQuery(
            'SELECT COALESCE(MAX(order_index), -1) AS m FROM lessons WHERE plan_id = ?', [planId]);
        final next = ((max.first['m'] as num?) ?? -1).toInt() + 1;
        return insertIn(txn, 'lessons', {
          'status': 'not_started',
          ...values,
          'plan_id': planId,
          'order_index': next,
        }, now);
      });

  Future<void> deleteLesson(String id) =>
      write(['lessons'], (txn, now) => softDeleteIn(txn, 'lessons', id, now));

  // ------------------------------------------------------------ today
  Future<TodayData> loadToday(String ymd) async {
    final tasks = await tasksFor(ymd);
    final tomorrowTasks = await tasksFor(addDaysYmd(ymd, 1));
    final plan = await activePlan();
    if (plan == null) {
      return TodayData(
        ymd: ymd,
        tasks: tasks,
        tomorrowTasks: tomorrowTasks,
        totalLessons: 0,
        completedLessons: 0,
        phaseTotal: 0,
        phaseCompleted: 0,
      );
    }

    final lessons = await lessonsForPlan(plan.s('id'));
    Rec? todayLesson;
    Rec? inProgress;
    Rec? firstOpen;
    var completed = 0;
    for (final l in lessons) {
      final status = l.s('status', 'not_started');
      if (status == 'completed') completed++;
      if (todayLesson == null && l.s('scheduled_date') == ymd) todayLesson = l;
      if (status == 'in_progress') inProgress ??= l;
      if (status != 'completed') firstOpen ??= l;
    }
    final cont = inProgress ?? firstOpen;
    final anchor = todayLesson ?? cont ?? (lessons.isEmpty ? null : lessons.last);

    var phaseTotal = 0;
    var phaseDone = 0;
    String? phaseTitle;
    if (anchor != null) {
      final phaseNo = anchor.iN('phase_no');
      phaseTitle = anchor.sn('phase_title');
      for (final l in lessons) {
        if (l.iN('phase_no') == phaseNo) {
          phaseTotal++;
          if (l.s('status') == 'completed') phaseDone++;
        }
      }
    }

    return TodayData(
      ymd: ymd,
      plan: plan,
      todayLesson: todayLesson,
      continueLesson: cont,
      tasks: tasks,
      tomorrowTasks: tomorrowTasks,
      totalLessons: lessons.length,
      completedLessons: completed,
      phaseTitle: phaseTitle,
      phaseTotal: phaseTotal,
      phaseCompleted: phaseDone,
    );
  }

  Stream<TodayData> watchToday(String ymd) =>
      watchQuery(changes, {'study_plans', 'lessons', 'daily_tasks'}, () => loadToday(ymd));

  // ------------------------------------------------------------ tasks
  Future<List<Rec>> tasksFor(String ymd) async => (await db).query(
        'daily_tasks',
        where: 'plan_date = ? AND deleted_at IS NULL',
        whereArgs: [ymd],
        orderBy: 'order_index ASC, created_at ASC',
      );

  Future<String> addTask(String ymd, String title, {String kind = 'custom', String? lessonId}) =>
      write(['daily_tasks'], (txn, now) => insertIn(txn, 'daily_tasks', {
            'plan_date': ymd,
            'title': title,
            'kind': kind,
            'lesson_id': lessonId,
            'status': 'todo',
          }, now));

  Future<void> setTaskDone(String id, bool done) => write(
      ['daily_tasks'],
      (txn, now) => updateIn(txn, 'daily_tasks', id, {'status': done ? 'done' : 'todo'}, now));

  Future<void> deleteTask(String id) =>
      write(['daily_tasks'], (txn, now) => softDeleteIn(txn, 'daily_tasks', id, now));

  // ------------------------------------------------------------ study sessions
  Future<void> logSession({String? lessonId, required int minutes, String? focus}) =>
      write(['study_sessions'], (txn, now) => insertIn(txn, 'study_sessions', {
            'lesson_id': lessonId,
            'started_at': now,
            'minutes': minutes,
            'focus': focus,
          }, now));

  Future<int> minutesForLesson(String lessonId) async {
    final rows = await rawQuery(
        'SELECT COALESCE(SUM(minutes), 0) AS m FROM study_sessions WHERE lesson_id = ? AND deleted_at IS NULL',
        [lessonId]);
    return rows.first.i('m');
  }

  Stream<int> watchMinutesForLesson(String lessonId) =>
      watchQuery(changes, {'study_sessions'}, () => minutesForLesson(lessonId));
}

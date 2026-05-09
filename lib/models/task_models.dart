import 'package:appwrite/models.dart' as models;
import 'package:flutter/material.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum TaskPriority {
  high(Color(0xFFF0632A)),
  medium(Color(0xFFF3B447)),
  low(Color(0xFF4EAF7A));

  const TaskPriority(this.color);
  final Color color;

  String get label => switch (this) {
        TaskPriority.high => 'High',
        TaskPriority.medium => 'Medium',
        TaskPriority.low => 'Low',
      };
}

TaskPriority taskPriorityFromName(String name) => TaskPriority.values
    .firstWhere((p) => p.name == name, orElse: () => TaskPriority.medium);

enum SmartListType { today, inbox, upcoming }

SmartListType smartListTypeFromName(String name) => SmartListType.values
    .firstWhere((b) => b.name == name, orElse: () => SmartListType.inbox);

enum TaskListKind { smart, custom }

enum RecurrenceType {
  none,
  daily,
  weekly;

  String get label => switch (this) {
        RecurrenceType.none => 'None',
        RecurrenceType.daily => 'Daily',
        RecurrenceType.weekly => 'Weekly',
      };
}

RecurrenceType recurrenceFromName(String name) => RecurrenceType.values
    .firstWhere((r) => r.name == name, orElse: () => RecurrenceType.none);

// ─── TaskListItem ─────────────────────────────────────────────────────────────

class TaskListItem {
  const TaskListItem.smart({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.smartType,
  })  : kind = TaskListKind.smart;

  const TaskListItem.custom({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
  })  : kind = TaskListKind.custom,
        smartType = null;

  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final TaskListKind kind;
  final SmartListType? smartType;
}

// ─── FlameTask ────────────────────────────────────────────────────────────────

class FlameTask {
  FlameTask({
    required this.id,
    required this.title,
    required this.note,
    required this.dueLabel,
    required this.dueAt,
    required this.listId,
    required this.bucket,
    required this.priority,
    required this.checklistDone,
    required this.checklistTotal,
    required this.isFlagged,
    this.tags = const <String>[],
    this.isDone = false,
    this.recurrence = RecurrenceType.none,
  });

  final String id;
  final String title;
  final String note;
  final String dueLabel;
  final DateTime? dueAt;
  final String listId;
  final SmartListType bucket;
  final TaskPriority priority;
  final int checklistDone;
  final int checklistTotal;
  final bool isFlagged;
  final List<String> tags;
  bool isDone;
  final RecurrenceType recurrence;

  DateTime? get effectiveDueAt => dueAt ?? parseDueAtFromLabel(dueLabel);
  String get displayDueLabel =>
      formatDueLabel(effectiveDueAt, fallback: dueLabel);

  FlameTask copyWith({
    String? id,
    String? title,
    String? note,
    String? dueLabel,
    DateTime? dueAt,
    String? listId,
    SmartListType? bucket,
    TaskPriority? priority,
    int? checklistDone,
    int? checklistTotal,
    bool? isFlagged,
    List<String>? tags,
    bool? isDone,
    RecurrenceType? recurrence,
  }) {
    return FlameTask(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      dueLabel: dueLabel ?? this.dueLabel,
      dueAt: dueAt ?? this.dueAt,
      listId: listId ?? this.listId,
      bucket: bucket ?? this.bucket,
      priority: priority ?? this.priority,
      checklistDone: checklistDone ?? this.checklistDone,
      checklistTotal: checklistTotal ?? this.checklistTotal,
      isFlagged: isFlagged ?? this.isFlagged,
      tags: tags ?? this.tags,
      isDone: isDone ?? this.isDone,
      recurrence: recurrence ?? this.recurrence,
    );
  }

  // ─── JSON (local / SharedPreferences legacy) ────────────────────────────

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'note': note,
        'dueLabel': dueLabel,
        'dueAt': dueAt?.toIso8601String(),
        'listId': listId,
        'bucket': bucket.name,
        'priority': priority.name,
        'checklistDone': checklistDone,
        'checklistTotal': checklistTotal,
        'isFlagged': isFlagged,
        'tags': tags,
        'isDone': isDone,
        'recurrence': recurrence.name,
      };

  factory FlameTask.fromJson(Map<String, dynamic> json) =>
      FlameTask.fromMap(json);

  // ─── Appwrite ────────────────────────────────────────────────────────────

  /// Serialise for Appwrite document create/update.
  Map<String, dynamic> toAppwriteMap() => <String, dynamic>{
        'title': title,
        'note': note,
        'dueLabel': dueLabel,
        'dueAt': dueAt?.toIso8601String(),
        'listId': listId,
        'bucket': bucket.name,
        'priority': priority.name,
        'checklistDone': checklistDone,
        'checklistTotal': checklistTotal,
        'isFlagged': isFlagged,
        'tags': tags,
        'isDone': isDone,
        'recurrence': recurrence.name,
      };

  /// Create from an Appwrite [Document].
  factory FlameTask.fromDocument(models.Document doc) =>
      FlameTask.fromMap({...doc.data, r'$id': doc.$id});

  /// Create from a raw map (Realtime payload or JSON).
  factory FlameTask.fromMap(Map<String, dynamic> m) {
    final String rawId = (m[r'$id'] as String?) ?? (m['id'] as String? ?? '');
    final DateTime? parsedDueAt = parseDueAt(m['dueAt'] as String?);
    final String storedLabel = m['dueLabel'] as String? ?? 'Inbox';
    final DateTime? effectiveDue =
        parsedDueAt ?? parseDueAtFromLabel(storedLabel);
    final SmartListType bucket = effectiveDue != null
        ? bucketForDueAt(effectiveDue)
        : smartListTypeFromName(m['bucket'] as String? ?? 'inbox');

    return FlameTask(
      id: rawId,
      title: m['title'] as String? ?? '',
      note: m['note'] as String? ?? '',
      dueLabel: storedLabel,
      dueAt: effectiveDue,
      listId: m['listId'] as String? ?? 'personal',
      bucket: bucket,
      priority: taskPriorityFromName(m['priority'] as String? ?? 'medium'),
      checklistDone: m['checklistDone'] as int? ?? 0,
      checklistTotal: m['checklistTotal'] as int? ?? 1,
      isFlagged: m['isFlagged'] as bool? ?? false,
      tags: (m['tags'] as List<dynamic>? ?? <dynamic>[])
          .whereType<String>()
          .toList(),
      isDone: m['isDone'] as bool? ?? false,
      recurrence: recurrenceFromName(m['recurrence'] as String? ?? 'none'),
    );
  }
}

// ─── Seed data ────────────────────────────────────────────────────────────────

List<TaskListItem> buildSeedTaskLists() => const <TaskListItem>[
      TaskListItem.smart(
        id: 'today',
        name: 'Today',
        icon: Icons.today_rounded,
        color: Color(0xFFF0632A),
        smartType: SmartListType.today,
      ),
      TaskListItem.smart(
        id: 'inbox',
        name: 'Inbox',
        icon: Icons.inbox_rounded,
        color: Color(0xFF4C8BF5),
        smartType: SmartListType.inbox,
      ),
      TaskListItem.smart(
        id: 'upcoming',
        name: 'Upcoming',
        icon: Icons.calendar_month_rounded,
        color: Color(0xFF7C61FF),
        smartType: SmartListType.upcoming,
      ),
      TaskListItem.custom(
        id: 'work',
        name: 'Work',
        icon: Icons.work_outline_rounded,
        color: Color(0xFF4EAF7A),
      ),
      TaskListItem.custom(
        id: 'personal',
        name: 'Personal',
        icon: Icons.favorite_border_rounded,
        color: Color(0xFFE457A1),
      ),
      TaskListItem.custom(
        id: 'team',
        name: 'Team',
        icon: Icons.groups_2_outlined,
        color: Color(0xFFF3B447),
      ),
    ];

List<FlameTask> buildSeedTasks() {
  final DateTime now = DateTime.now();
  final DateTime todayMorning = DateTime(now.year, now.month, now.day, 6, 30);
  final DateTime todayLate = DateTime(now.year, now.month, now.day, 9, 0);
  final DateTime todayMidday = DateTime(now.year, now.month, now.day, 11, 30);
  final DateTime tomorrow = startOfDay(now.add(const Duration(days: 1)));
  final DateTime nextFriday = nextWeekday(now, DateTime.friday);
  return <FlameTask>[
    FlameTask(
      id: 'seed-1',
      title: 'Morning workout',
      note: '30 min cardio and mobility before the first meeting.',
      dueLabel: formatDueLabel(todayMorning, fallback: 'Today'),
      dueAt: todayMorning,
      listId: 'personal',
      bucket: bucketForDueAt(todayMorning),
      priority: TaskPriority.high,
      checklistDone: 2,
      checklistTotal: 3,
      isFlagged: false,
      tags: <String>['health', 'morning'],
      isDone: true,
      recurrence: RecurrenceType.daily,
    ),
    FlameTask(
      id: 'seed-2',
      title: 'Finalize onboarding copy',
      note: 'Tighten CTA, simplify empty state, ship revised first-run flow.',
      dueLabel: formatDueLabel(todayLate, fallback: 'Today'),
      dueAt: todayLate,
      listId: 'work',
      bucket: bucketForDueAt(todayLate),
      priority: TaskPriority.high,
      checklistDone: 1,
      checklistTotal: 4,
      isFlagged: true,
      tags: <String>['launch', 'copy'],
    ),
    FlameTask(
      id: 'seed-3',
      title: 'Design sprint review',
      note: 'Review backlog priorities and confirm next sprint scope.',
      dueLabel: formatDueLabel(todayMidday, fallback: 'Today'),
      dueAt: todayMidday,
      listId: 'team',
      bucket: bucketForDueAt(todayMidday),
      priority: TaskPriority.medium,
      checklistDone: 0,
      checklistTotal: 2,
      isFlagged: false,
      tags: <String>['planning'],
    ),
    FlameTask(
      id: 'seed-4',
      title: 'Water the plants',
      note: 'Balcony planters and the fern by the entryway.',
      dueLabel: 'Inbox',
      dueAt: null,
      listId: 'personal',
      bucket: SmartListType.inbox,
      priority: TaskPriority.low,
      checklistDone: 0,
      checklistTotal: 1,
      isFlagged: false,
      tags: <String>['home'],
    ),
    FlameTask(
      id: 'seed-5',
      title: 'Plan content calendar',
      note: 'Outline next week campaign posts and lock the approval window.',
      dueLabel: formatDueLabel(tomorrow, fallback: 'Tomorrow'),
      dueAt: tomorrow,
      listId: 'work',
      bucket: bucketForDueAt(tomorrow),
      priority: TaskPriority.medium,
      checklistDone: 2,
      checklistTotal: 5,
      isFlagged: true,
      tags: <String>['marketing', 'planning'],
    ),
    FlameTask(
      id: 'seed-6',
      title: 'Book dentist appointment',
      note: 'Call Dr. Muli before noon and confirm the insurance details.',
      dueLabel: formatDueLabel(nextFriday, fallback: 'Friday'),
      dueAt: nextFriday,
      listId: 'personal',
      bucket: bucketForDueAt(nextFriday),
      priority: TaskPriority.low,
      checklistDone: 0,
      checklistTotal: 1,
      isFlagged: false,
      tags: <String>['errands'],
    ),
  ];
}

// ─── Utility functions ────────────────────────────────────────────────────────

List<String> parseTags(String raw) {
  if (raw.trim().isEmpty) return <String>[];
  final List<String> tags = raw
      .split(RegExp(r'[;,]'))
      .map((t) => t.trim().replaceAll('#', '').toLowerCase())
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList()
    ..sort();
  return tags;
}

String formatTags(List<String> tags) => tags.join(', ');

DateTime startOfDay(DateTime date) => DateTime(date.year, date.month, date.day);

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isToday(DateTime date, DateTime now) => isSameDay(date, now);

bool isTomorrow(DateTime date, DateTime now) =>
    isSameDay(date, now.add(const Duration(days: 1)));

SmartListType bucketForDueAt(DateTime? dueAt, {DateTime? reference}) {
  if (dueAt == null) return SmartListType.inbox;
  final DateTime now = reference ?? DateTime.now();
  if (isToday(dueAt, now) || dueAt.isBefore(startOfDay(now))) {
    return SmartListType.today;
  }
  return SmartListType.upcoming;
}

String formatHeaderDate(DateTime now) {
  return '${_weekdayNames[now.weekday - 1]}, ${_monthNames[now.month - 1]} ${now.day}';
}

String formatUpcomingHeader(DateTime date, {DateTime? reference}) {
  final DateTime now = reference ?? DateTime.now();
  if (isToday(date, now)) return 'Today';
  if (isTomorrow(date, now)) return 'Tomorrow';
  final int diff = startOfDay(date).difference(startOfDay(now)).inDays;
  if (diff >= 0 && diff < 7) return _weekdayNames[date.weekday - 1];
  return '${_monthNames[date.month - 1]} ${date.day}';
}

String formatDueLabel(DateTime? dueAt, {String? fallback, DateTime? reference}) {
  if (dueAt == null) return fallback ?? 'Inbox';
  final DateTime now = reference ?? DateTime.now();
  final String suffix =
      _formatTime(dueAt).isEmpty ? '' : ', ${_formatTime(dueAt)}';
  if (isToday(dueAt, now)) return 'Today$suffix';
  if (isTomorrow(dueAt, now)) return 'Tomorrow$suffix';
  final int diff = startOfDay(dueAt).difference(startOfDay(now)).inDays;
  if (diff >= 0 && diff < 7) return '${_weekdayNames[dueAt.weekday - 1]}$suffix';
  return '${_monthNames[dueAt.month - 1]} ${dueAt.day}$suffix';
}

DateTime? parseDueAt(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

DateTime? parseDueAtFromLabel(String label, {DateTime? reference}) {
  final String trimmed = label.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'inbox') return null;
  final DateTime now = reference ?? DateTime.now();
  DateTime baseDate;
  if (trimmed.startsWith('Today')) {
    baseDate = startOfDay(now);
  } else if (trimmed.startsWith('Tomorrow')) {
    baseDate = startOfDay(now.add(const Duration(days: 1)));
  } else {
    final String dayLabel = trimmed.split(',').first;
    final int idx = _weekdayNames.indexOf(dayLabel);
    if (idx != -1) {
      baseDate = nextWeekday(now, idx + 1);
    } else {
      return null;
    }
  }
  final RegExp timeRx = RegExp(r'(\d{1,2}):(\d{2})\s?(AM|PM)');
  final RegExpMatch? m = timeRx.firstMatch(trimmed);
  if (m == null) return baseDate;
  int hour = int.parse(m.group(1)!);
  final int minute = int.parse(m.group(2)!);
  final String period = m.group(3)!;
  if (period == 'PM' && hour != 12) hour += 12;
  if (period == 'AM' && hour == 12) hour = 0;
  return DateTime(baseDate.year, baseDate.month, baseDate.day, hour, minute);
}

DateTime nextWeekday(DateTime from, int weekday) {
  int daysAhead = weekday - from.weekday;
  if (daysAhead <= 0) daysAhead += 7;
  return startOfDay(from.add(Duration(days: daysAhead)));
}

String _formatTime(DateTime date) {
  if (date.hour == 0 && date.minute == 0) return '';
  int hour = date.hour % 12;
  if (hour == 0) hour = 12;
  final String minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${date.hour >= 12 ? 'PM' : 'AM'}';
}

const List<String> _weekdayNames = <String>[
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

const List<String> _monthNames = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

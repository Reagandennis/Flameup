#!/usr/bin/env python3
import os

BASE = '/Users/reaganenochowiti/Desktop/Flameup/lib'

def write(rel, content):
    path = os.path.join(BASE, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w') as f:
        f.write(content)
    print(f'OK  {rel}')

# ─── services/auth_service.dart ───────────────────────────────────────────────
write('services/auth_service.dart', r"""import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/enums.dart' as enums;
import 'package:appwrite/models.dart' as models;

import 'appwrite_client.dart';

/// Singleton auth service backed by Appwrite Account.
class AuthService {
  AuthService._();
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;

  final AppwriteClient _aw = AppwriteClient.instance;

  final StreamController<models.User?> _userCtrl =
      StreamController<models.User?>.broadcast();

  models.User? _currentUser;

  Stream<models.User?> get userStream => _userCtrl.stream;
  models.User? get currentUser => _currentUser;
  String? get uid => _currentUser?.$id;

  String get displayName =>
      (_currentUser?.name.isNotEmpty == true) ? _currentUser!.name : 'Flameup member';

  String get email => _currentUser?.email ?? '';

  Future<void> initialize() async {
    try {
      _currentUser = await _aw.account.get();
    } on AppwriteException {
      _currentUser = null;
    }
    _userCtrl.add(_currentUser);
  }

  Future<models.User?> signUpWithEmail(
      String email, String password, String name) async {
    await _aw.account.create(
      userId: ID.unique(),
      email: email.trim(),
      password: password,
      name: name.trim(),
    );
    return signInWithEmail(email, password);
  }

  Future<models.User?> signInWithEmail(String email, String password) async {
    await _aw.account.createEmailPasswordSession(
      email: email.trim(),
      password: password,
    );
    _currentUser = await _aw.account.get();
    _userCtrl.add(_currentUser);
    return _currentUser;
  }

  Future<void> signInWithGoogle() async {
    await _aw.account.createOAuth2Session(
      provider: enums.OAuthProvider.google,
    );
    _currentUser = await _aw.account.get();
    _userCtrl.add(_currentUser);
  }

  Future<void> signOut() async {
    try {
      await _aw.account.deleteSession(sessionId: 'current');
    } on AppwriteException {
      // already expired - ignore
    }
    _currentUser = null;
    _userCtrl.add(null);
  }

  Future<void> sendPasswordReset(String email) async {
    await _aw.account.createRecovery(
      email: email.trim(),
      url: '${AppwriteClient.endpoint}/account/recovery',
    );
  }

  Future<void> updateDisplayName(String name) async {
    _currentUser = await _aw.account.updateName(name: name.trim());
    _userCtrl.add(_currentUser);
  }

  static String friendlyError(Object e) {
    if (e is AppwriteException) {
      final String msg = (e.message ?? '').toLowerCase();
      if (msg.contains('invalid credentials') ||
          msg.contains('user_invalid_credentials')) {
        return 'Incorrect email or password.';
      }
      if (msg.contains('user_already_exists') || msg.contains('already exists')) {
        return 'An account with this email already exists.';
      }
      if (msg.contains('user_not_found')) {
        return 'No account found with that email.';
      }
      if (msg.contains('password')) {
        return 'Password must be at least 8 characters.';
      }
      return e.message ?? 'Authentication error. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
""")

# ─── services/task_store.dart ─────────────────────────────────────────────────
write('services/task_store.dart', r"""import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';

import '../models/task_models.dart';
import 'appwrite_client.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'streak_service.dart';

/// Manages tasks in Appwrite Databases, scoped per authenticated user.
/// Uses optimistic updates with rollback on failure.
class TaskStore extends ChangeNotifier {
  final AppwriteClient _aw = AppwriteClient.instance;
  final AuthService _auth = AuthService();
  final NotificationService _notifications = NotificationService();

  /// Static smart + custom lists (user-visible navigation).
  final List<TaskListItem> lists = buildSeedTaskLists();

  List<FlameTask> _tasks = <FlameTask>[];
  bool _isLoaded = false;
  bool _isLoading = false;
  String? _error;
  RealtimeSubscription? _subscription;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  String? get error => _error;
  List<FlameTask> get tasks => List<FlameTask>.unmodifiable(_tasks);

  @override
  void dispose() {
    _subscription?.close();
    super.dispose();
  }

  // ─── Load ─────────────────────────────────────────────────────────────────

  Future<void> load() async {
    if (_isLoaded || _isLoading) return;
    final String? userId = _auth.uid;
    if (userId == null) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final models.DocumentList result = await _aw.databases.listDocuments(
        databaseId: AppwriteClient.databaseId,
        collectionId: AppwriteClient.tasksCollectionId,
        queries: [
          Query.equal('userId', userId),
          Query.limit(500),
          Query.orderDesc(r'$createdAt'),
        ],
      );

      _tasks = result.documents.map(FlameTask.fromDocument).toList();

      if (_tasks.isEmpty) {
        // First run — seed sample tasks
        final List<FlameTask> seeds = buildSeedTasks();
        for (final FlameTask seed in seeds) {
          final FlameTask t = seed.copyWith(id: ID.unique());
          await _createDocument(t, userId);
          _tasks.add(t);
        }
      }

      _isLoaded = true;
      _isLoading = false;
      await _notifications.syncTasks(_tasks);
      notifyListeners();
      _subscribeRealtime(userId);
    } on AppwriteException catch (e) {
      _error = e.message ?? 'Failed to load tasks.';
      _isLoading = false;
      notifyListeners();
    } catch (_) {
      _error = 'Failed to load tasks. Check your connection.';
      _isLoading = false;
      notifyListeners();
    }
  }

  // ─── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> addTask(FlameTask task) async {
    final String? userId = _auth.uid;
    if (userId == null) return;

    final FlameTask t = task.copyWith(id: ID.unique());
    _tasks = <FlameTask>[t, ..._tasks];
    notifyListeners();

    try {
      await _createDocument(t, userId);
      await _notifications.scheduleTaskReminder(t);
    } catch (_) {
      _tasks = _tasks.where((x) => x.id != t.id).toList();
      notifyListeners();
    }
  }

  Future<void> updateTask(FlameTask task) async {
    final int i = _tasks.indexWhere((t) => t.id == task.id);
    if (i == -1) return;
    final FlameTask old = _tasks[i];
    _tasks[i] = task;
    notifyListeners();

    try {
      await _aw.databases.updateDocument(
        databaseId: AppwriteClient.databaseId,
        collectionId: AppwriteClient.tasksCollectionId,
        documentId: task.id,
        data: task.toAppwriteMap(),
      );
      if (task.isDone) {
        await _notifications.cancelTaskReminder(task.id);
        if (_auth.uid != null) await StreakService().recordCompletion(_auth.uid!);
      } else {
        await _notifications.scheduleTaskReminder(task);
      }
    } catch (_) {
      _tasks[i] = old;
      notifyListeners();
    }
  }

  Future<void> deleteTask(String taskId) async {
    final int i = _tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final FlameTask removed = _tasks[i];
    _tasks.removeAt(i);
    notifyListeners();

    try {
      await _aw.databases.deleteDocument(
        databaseId: AppwriteClient.databaseId,
        collectionId: AppwriteClient.tasksCollectionId,
        documentId: taskId,
      );
      await _notifications.cancelTaskReminder(taskId);
    } catch (_) {
      _tasks.insert(i, removed);
      notifyListeners();
    }
  }

  Future<void> toggleTaskCompletion(String taskId, bool isDone) async {
    final int i = _tasks.indexWhere((t) => t.id == taskId);
    if (i == -1) return;
    final FlameTask old = _tasks[i];
    _tasks[i] = old.copyWith(isDone: isDone);
    notifyListeners();

    try {
      await _aw.databases.updateDocument(
        databaseId: AppwriteClient.databaseId,
        collectionId: AppwriteClient.tasksCollectionId,
        documentId: taskId,
        data: {'isDone': isDone},
      );
      if (isDone) {
        await _notifications.cancelTaskReminder(taskId);
        if (_auth.uid != null) await StreakService().recordCompletion(_auth.uid!);
      } else {
        await _notifications.scheduleTaskReminder(_tasks[i]);
      }
    } catch (_) {
      _tasks[i] = old;
      notifyListeners();
    }
  }

  // ─── Realtime ─────────────────────────────────────────────────────────────

  void _subscribeRealtime(String userId) {
    _subscription?.close();
    _subscription = _aw.realtime.subscribe([
      'databases.${AppwriteClient.databaseId}'
      '.collections.${AppwriteClient.tasksCollectionId}.documents',
    ]);

    _subscription!.stream.listen((RealtimeMessage event) {
      final Map<String, dynamic> payload = event.payload;
      if (payload['userId'] != userId) return;

      final String docId = (payload[r'$id'] as String?) ?? '';

      if (event.events.any((e) => e.endsWith('.delete'))) {
        _tasks = _tasks.where((t) => t.id != docId).toList();
        notifyListeners();
        return;
      }

      try {
        final FlameTask task = FlameTask.fromMap(payload);
        final int idx = _tasks.indexWhere((t) => t.id == task.id);
        if (idx == -1) {
          _tasks = <FlameTask>[task, ..._tasks];
        } else {
          _tasks[idx] = task;
        }
        notifyListeners();
      } catch (_) {}
    });
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  Future<void> _createDocument(FlameTask task, String userId) async {
    await _aw.databases.createDocument(
      databaseId: AppwriteClient.databaseId,
      collectionId: AppwriteClient.tasksCollectionId,
      documentId: task.id,
      data: {
        ...task.toAppwriteMap(),
        'userId': userId,
      },
      permissions: [
        Permission.read(Role.user(userId)),
        Permission.update(Role.user(userId)),
        Permission.delete(Role.user(userId)),
      ],
    );
  }
}
""")

# ─── models/task_models.dart — add recurrence + Appwrite converters ───────────
# We append to the existing FlameTask class via a helper approach.
# Instead, rewrite the entire file.
write('models/task_models.dart', r"""import 'package:appwrite/models.dart' as models;
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
""")

# ─── services/notification_service.dart — fix timezone ───────────────────────
write('services/notification_service.dart', r"""import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/task_models.dart';

class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _available = true;
  static const bool _isTest = bool.fromEnvironment('FLUTTER_TEST');

  static const int _dailyReminderId = 90001;
  static const int _focusCompleteId = 90002;

  Future<void> initialize() async {
    if (_isTest || kIsWeb || _initialized) return;

    tzdata.initializeTimeZones();
    try {
      final String localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();

    try {
      await _plugin.initialize(
        const InitializationSettings(android: androidSettings, iOS: iosSettings),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } on MissingPluginException {
      _available = false;
      return;
    } on PlatformException {
      _available = false;
      return;
    }
    _initialized = true;
  }

  Future<void> scheduleDailyReminder({int hour = 9, int minute = 0}) async {
    if (_isTest || !_available || !_initialized) return;
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));
    await _safeZonedSchedule(
      _dailyReminderId,
      'Keep the streak alive',
      'Open Flameup to stay on top of your tasks.',
      scheduled,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> scheduleTaskReminder(FlameTask task) async {
    if (_isTest || !_available || !_initialized) return;
    final DateTime? dueAt = task.effectiveDueAt;
    if (dueAt == null || task.isDone) return;
    if (!dueAt.isAfter(DateTime.now())) return;
    await _safeZonedSchedule(
      _taskNotificationId(task.id),
      task.title,
      'Due ${task.displayDueLabel}',
      tz.TZDateTime.from(dueAt, tz.local),
    );
  }

  Future<void> cancelTaskReminder(String taskId) async {
    if (_isTest || !_available || !_initialized) return;
    await _plugin.cancel(_taskNotificationId(taskId));
  }

  Future<void> syncTasks(List<FlameTask> tasks) async {
    if (_isTest || !_available || !_initialized) return;
    for (final FlameTask task in tasks) {
      if (task.isDone) {
        await cancelTaskReminder(task.id);
      } else {
        await scheduleTaskReminder(task);
      }
    }
  }

  Future<void> scheduleFocusComplete(Duration duration) async {
    if (_isTest || !_available || !_initialized || duration.inSeconds <= 0) return;
    await _safeZonedSchedule(
      _focusCompleteId,
      'Focus session complete',
      'Great job. Take a short break.',
      tz.TZDateTime.now(tz.local).add(duration),
    );
  }

  Future<void> cancelFocusComplete() async {
    if (_isTest || !_available || !_initialized) return;
    await _plugin.cancel(_focusCompleteId);
  }

  NotificationDetails _defaultDetails() {
    const AndroidNotificationDetails android = AndroidNotificationDetails(
      'flameup_reminders',
      'Reminders',
      channelDescription: 'Task due reminders and focus notifications.',
      importance: Importance.high,
      priority: Priority.high,
    );
    return const NotificationDetails(android: android, iOS: DarwinNotificationDetails());
  }

  Future<void> _safeZonedSchedule(
    int id,
    String title,
    String body,
    tz.TZDateTime scheduled, {
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    if (!_available || !_initialized) return;
    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        scheduled,
        _defaultDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: matchDateTimeComponents,
      );
    } on PlatformException catch (error) {
      if (error.code == 'exact_alarms_not_permitted') {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          scheduled,
          _defaultDetails(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: matchDateTimeComponents,
        );
        return;
      }
      rethrow;
    }
  }

  int _taskNotificationId(String taskId) => _stableHash(taskId) % 50000 + 10000;

  int _stableHash(String input) {
    int hash = 0;
    for (final int cu in input.codeUnits) {
      hash = (hash * 31 + cu) & 0x7fffffff;
    }
    return hash;
  }
}
""")

# ─── main.dart ────────────────────────────────────────────────────────────────
write('main.dart', r"""import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/forgot_password_screen.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'services/appwrite_client.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';

// ─── Riverpod providers ───────────────────────────────────────────────────────

final authServiceProvider = Provider<AuthService>((_) => AuthService());

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (_) => ThemeModeNotifier(),
);

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = prefs.getString('theme_mode') ?? 'system';
    state = switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode.name);
  }
}

// ─── GoRouter ─────────────────────────────────────────────────────────────────

final GoRouter _router = GoRouter(
  initialLocation: '/splash',
  routes: <RouteBase>[
    GoRoute(
      path: '/splash',
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (_, __) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: '/signup',
      builder: (_, __) => const SignupScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (_, __) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const SettingsScreen(),
    ),
  ],
);

// ─── Entry point ──────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Appwrite (synchronous — just sets up the SDK client)
  AppwriteClient.instance.initialize();

  // Hydrate auth session from Appwrite before rendering
  await AuthService().initialize();

  // Local notifications
  await NotificationService().initialize();
  await NotificationService().scheduleDailyReminder();

  runApp(const ProviderScope(child: FlameupApp()));
}

// ─── Root widget ──────────────────────────────────────────────────────────────

class FlameupApp extends ConsumerWidget {
  const FlameupApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeMode themeMode = ref.watch(themeModeProvider);

    const Color primaryColor = Color(0xFFF6511D);
    const Color secondaryColor = Color(0xFF04151F);

    final ColorScheme lightScheme = ColorScheme.light(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: const Color(0xFFF6F2EB),
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: const Color(0xFF201A17),
    );
    final ColorScheme darkScheme = ColorScheme.dark(
      primary: primaryColor,
      secondary: secondaryColor,
      surface: secondaryColor,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: Colors.white,
    );

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Flameup',
      routerConfig: _router,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(),
        scaffoldBackgroundColor: lightScheme.surface,
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        scaffoldBackgroundColor: darkScheme.surface,
      ),
      themeMode: themeMode,
    );
  }
}
""")

# ─── screens/splash_screen.dart ───────────────────────────────────────────────
write('screens/splash_screen.dart', r"""import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 2), _goNext);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    final bool isLoggedIn = AuthService().currentUser != null;
    context.go(isLoggedIn ? '/home' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      backgroundColor: surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: const Color(0xFFFFE2D4),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.local_fire_department_rounded,
                size: 56,
                color: Color(0xFFF0632A),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Flameup',
              style: TextStyle(
                color: onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Keep the streak alive',
              style: TextStyle(
                color: onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
""")

# ─── screens/login_screen.dart ────────────────────────────────────────────────
write('screens/login_screen.dart', r"""import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      await AuthService().signInWithEmail(_emailCtrl.text, _pwCtrl.text);
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(AuthService.friendlyError(e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signInGoogle() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      await AuthService().signInWithGoogle();
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(AuthService.friendlyError(e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Icon(Icons.local_fire_department_rounded,
                      size: 80, color: Color(0xFFF0632A)),
                  const SizedBox(height: 24),
                  const Text(
                    'Welcome Back!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign in to continue to Flameup',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 48),
                  // Email
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required';
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Password
                  TextFormField(
                    controller: _pwCtrl,
                    obscureText: _obscure,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 8) return 'Password must be at least 8 characters';
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.push('/forgot-password'),
                      child: const Text('Forgot password?',
                          style: TextStyle(color: Color(0xFFF0632A))),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else ...<Widget>[
                    ElevatedButton(
                      onPressed: _signIn,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        backgroundColor: const Color(0xFFF0632A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      child: const Text('Login',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _signInGoogle,
                      icon: const Icon(Icons.g_mobiledata,
                          size: 28, color: Color(0xFF4285F4)),
                      label: const Text('Sign in with Google',
                          style: TextStyle(
                              fontSize: 16, color: Colors.black87)),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: BorderSide(color: Colors.grey.shade300),
                        backgroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const Text("Don't have an account?",
                            style: TextStyle(color: Colors.black54)),
                        TextButton(
                          onPressed: () => context.push('/signup'),
                          child: const Text('Sign up',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFF0632A))),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
""")

# ─── screens/signup_screen.dart ───────────────────────────────────────────────
write('screens/signup_screen.dart', r"""import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      await AuthService().signUpWithEmail(
          _emailCtrl.text, _pwCtrl.text, _nameCtrl.text);
      if (!mounted) return;
      // Navigate to onboarding on first sign-up
      context.go('/onboarding');
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
          SnackBar(content: Text(AuthService.friendlyError(e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Create Account',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign up to get started!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                  const SizedBox(height: 48),
                  // Name
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Name is required';
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Display Name',
                      prefixIcon: const Icon(Icons.person_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Email
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Email is required';
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Password
                  TextFormField(
                    controller: _pwCtrl,
                    obscureText: _obscure,
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Password is required';
                      if (v.length < 8) return 'Password must be at least 8 characters';
                      return null;
                    },
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_isLoading)
                    const Center(child: CircularProgressIndicator())
                  else
                    ElevatedButton(
                      onPressed: _signUp,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        backgroundColor: const Color(0xFFF0632A),
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      child: const Text('Sign Up',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Text('Already have an account?',
                          style: TextStyle(color: Colors.black54)),
                      TextButton(
                        onPressed: () => context.pop(),
                        child: const Text('Login',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFFF0632A))),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
""")

# ─── screens/forgot_password_screen.dart ─────────────────────────────────────
write('screens/forgot_password_screen.dart', r"""import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _sent = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isLoading = true);
    try {
      await AuthService().sendPasswordReset(_emailCtrl.text);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
          SnackBar(content: Text(AuthService.friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: onSurface),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _sent ? _SuccessView() : _FormView(
              formKey: _formKey,
              emailCtrl: _emailCtrl,
              isLoading: _isLoading,
              onSubmit: _submit,
            ),
          ),
        ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  const _FormView({
    required this.formKey,
    required this.emailCtrl,
    required this.isLoading,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final bool isLoading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Icon(Icons.lock_reset_rounded, size: 72, color: Color(0xFFF0632A)),
          const SizedBox(height: 24),
          const Text('Reset Password',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Enter your email and we'll send a reset link.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54)),
          const SizedBox(height: 48),
          TextFormField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                return 'Enter a valid email address';
              }
              return null;
            },
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: const Icon(Icons.email_outlined),
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 24),
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else
            ElevatedButton(
              onPressed: onSubmit,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                backgroundColor: const Color(0xFFF0632A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Send Reset Link',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        const Icon(Icons.mark_email_read_rounded,
            size: 72, color: Color(0xFF4EAF7A)),
        const SizedBox(height: 24),
        const Text('Check your inbox',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('We sent a password reset link to your email.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black54)),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: () => context.pop(),
          style: ElevatedButton.styleFrom(
            padding:
                const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
            backgroundColor: const Color(0xFFF0632A),
            foregroundColor: Colors.white,
          ),
          child: const Text('Back to Login'),
        ),
      ],
    );
  }
}
""")

# ─── screens/onboarding_screen.dart ───────────────────────────────────────────
write('screens/onboarding_screen.dart', r"""import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;

  static const List<_OnboardingPage> _pages = <_OnboardingPage>[
    _OnboardingPage(
      icon: Icons.local_fire_department_rounded,
      iconColor: Color(0xFFF0632A),
      title: 'Welcome to Flameup',
      description:
          'Your habit tracker that keeps the flame burning.\n'
          'Capture tasks, set due dates, and stay focused every single day.',
    ),
    _OnboardingPage(
      icon: Icons.whatshot_rounded,
      iconColor: Color(0xFFF3B447),
      title: 'Build Your Streak',
      description:
          'Complete at least one task each day to grow your streak.\n'
          'The longer the chain, the stronger the habit.',
    ),
    _OnboardingPage(
      icon: Icons.timer_outlined,
      iconColor: Color(0xFF4EAF7A),
      title: 'Focus & Flow',
      description:
          'Use the built-in 25-minute Focus timer to eliminate distractions\n'
          'and get deep work done — one task at a time.',
    ),
  ];

  Future<void> _finish() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    if (!mounted) return;
    context.go('/home');
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isLast = _currentPage == _pages.length - 1;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: Text('Skip',
                    style: TextStyle(
                        color: scheme.onSurface.withValues(alpha: 0.5))),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageCtrl,
                itemCount: _pages.length,
                onPageChanged: (int i) => setState(() => _currentPage = i),
                itemBuilder: (BuildContext context, int index) {
                  final _OnboardingPage page = _pages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: page.iconColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(36),
                          ),
                          child: Icon(page.icon,
                              size: 64, color: page.iconColor),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.65),
                            fontSize: 16,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Page indicator dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(_pages.length, (int i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _currentPage ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _currentPage
                        ? const Color(0xFFF0632A)
                        : const Color(0xFFF0632A).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isLast
                      ? _finish
                      : () => _pageCtrl.nextPage(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF0632A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  child: Text(
                    isLast ? "Let's Go!" : 'Next',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage {
  const _OnboardingPage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
}
""")

# ─── screens/settings_screen.dart ────────────────────────────────────────────
write('screens/settings_screen.dart', r"""import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/auth_service.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color muted = onSurface.withValues(alpha: 0.7);
    final ThemeMode mode = ref.watch(themeModeProvider);
    final ThemeModeNotifier notifier = ref.read(themeModeProvider.notifier);
    final AuthService auth = AuthService();

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: onSurface),
          onPressed: () => context.pop(),
        ),
        title: Text('Settings',
            style:
                TextStyle(color: onSurface, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: <Widget>[
            _ProfileCard(
              displayName: auth.displayName,
              email: auth.email,
            ),
            const SizedBox(height: 18),
            Text('Appearance',
                style:
                    TextStyle(color: muted, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _SettingsCard(
              children: <Widget>[
                RadioListTile<ThemeMode>(
                  value: ThemeMode.system,
                  groupValue: mode,
                  onChanged: (v) => notifier.setMode(v!),
                  title: const Text('System'),
                ),
                const Divider(height: 1),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.light,
                  groupValue: mode,
                  onChanged: (v) => notifier.setMode(v!),
                  title: const Text('Light'),
                ),
                const Divider(height: 1),
                RadioListTile<ThemeMode>(
                  value: ThemeMode.dark,
                  groupValue: mode,
                  onChanged: (v) => notifier.setMode(v!),
                  title: const Text('Dark'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('Account',
                style:
                    TextStyle(color: muted, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            _SettingsCard(
              children: <Widget>[
                ListTile(
                  leading: const Icon(Icons.person_outline_rounded),
                  title: const Text('Update display name'),
                  onTap: () =>
                      _showUpdateNameDialog(context, auth),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Delete account'),
                  subtitle:
                      const Text('This action is permanent and cannot be undone.'),
                  onTap: () => _confirmDeleteAccount(context, auth),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.displayName, required this.email});

  final String displayName;
  final String email;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String initials = displayName.isNotEmpty
        ? displayName.trim().split(' ').map((w) => w[0]).take(2).join().toUpperCase()
        : '?';
    return _SettingsCard(
      children: <Widget>[
        ListTile(
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: scheme.primaryContainer,
            child: Text(initials,
                style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold)),
          ),
          title: Text(displayName,
              style: TextStyle(
                  color: scheme.onSurface, fontWeight: FontWeight.w800)),
          subtitle: Text(email,
              style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.7))),
        ),
      ],
    );
  }
}

Future<void> _showUpdateNameDialog(
    BuildContext context, AuthService auth) async {
  final TextEditingController ctrl =
      TextEditingController(text: auth.displayName);
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Update display name'),
      content: TextField(
        controller: ctrl,
        decoration: const InputDecoration(labelText: 'Display Name'),
        autofocus: true,
      ),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save')),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;
  try {
    await auth.updateDisplayName(ctrl.text);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Display name updated.')));
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}

Future<void> _confirmDeleteAccount(
    BuildContext context, AuthService auth) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: const Text('Delete account?'),
      content: const Text(
          'All your data will be permanently removed. This cannot be undone.'),
      actions: <Widget>[
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true || !context.mounted) return;

  try {
    // Delete the current session — full account deletion requires a server function.
    // Send an email request in the meantime.
    await auth.signOut();
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@flameup.app',
      queryParameters: <String, String>{
        'subject': 'Account deletion request',
        'body': 'Please delete my Flameup account.\n\nEmail: ${auth.email}',
      },
    );
    await launchUrl(emailUri, mode: LaunchMode.externalApplication);
    if (context.mounted) context.go('/login');
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }
}
""")

print('\nAll files written successfully.')

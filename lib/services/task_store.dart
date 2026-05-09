import 'package:appwrite/appwrite.dart';
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

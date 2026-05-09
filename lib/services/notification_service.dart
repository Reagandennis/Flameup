import 'package:flutter/foundation.dart';
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

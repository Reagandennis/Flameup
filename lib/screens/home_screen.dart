import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../models/task_models.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/streak_service.dart';
import '../services/task_store.dart';
import 'task_editor_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final TaskStore _store = TaskStore();

  String _selectedListId = 'today';
  int _selectedNavIndex = 0;
  int _selectedSegmentIndex = 0;
  late DateTime _calendarSelectedDate;
  static const Duration _focusDuration = Duration(minutes: 25);
  Duration _focusRemaining = _focusDuration;
  bool _isFocusRunning = false;
  Timer? _focusTimer;
  String? _focusedTaskId;
  String _browseQuery = '';
  final TextEditingController _browseController = TextEditingController();
  _SortOption _sortOption = _SortOption.defaultOrder;

  static const List<_TaskSegment> _segments = <_TaskSegment>[
    _TaskSegment.all,
    _TaskSegment.open,
    _TaskSegment.done,
  ];

  @override
  void initState() {
    super.initState();
    _calendarSelectedDate = startOfDay(DateTime.now());
    _store.addListener(_handleStoreUpdated);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_handleStoreUpdated);
    _store.dispose();
    _browseController.dispose();
    _focusTimer?.cancel();
    super.dispose();
  }

  void _handleStoreUpdated() {
    if (mounted) {
      setState(() {});
    }
  }

  TaskListItem get _selectedList =>
      _store.lists.firstWhere((list) => list.id == _selectedListId);

  List<FlameTask> get _baseVisibleTasks {
    final TaskListItem selectedList = _selectedList;
    if (selectedList.kind == TaskListKind.smart) {
      return _store.tasks
          .where((task) => task.bucket == selectedList.smartType)
          .toList();
    }

    return _store.tasks
        .where((task) => task.listId == selectedList.id)
        .toList();
  }

  List<FlameTask> get _visibleTasks {
    final List<FlameTask> baseTasks = _baseVisibleTasks;
    switch (_segments[_selectedSegmentIndex]) {
      case _TaskSegment.all:
        return baseTasks;
      case _TaskSegment.open:
        return baseTasks.where((task) => !task.isDone).toList();
      case _TaskSegment.done:
        return baseTasks.where((task) => task.isDone).toList();
    }
  }

  int _openCountForList(TaskListItem list) {
    return _store.tasks.where((task) {
      final bool inList = list.kind == TaskListKind.smart
          ? task.bucket == list.smartType
          : task.listId == list.id;
      return inList && !task.isDone;
    }).length;
  }

  String _sectionSubtitle(int openCount) {
    final String taskLabel = openCount == 1 ? 'task' : 'tasks';
    if (_selectedList.kind == TaskListKind.smart) {
      return '$openCount open $taskLabel';
    }

    return '${_selectedList.name} list · $openCount open $taskLabel';
  }

  Future<void> _openQuickAddSheet() async {
    String selectedListId = _selectedList.kind == TaskListKind.custom
        ? _selectedList.id
        : 'work';
    String title = '';
    String note = '';
    String tagsText = '';
    final DateTime now = DateTime.now();
    _DuePreset selectedDuePreset = switch (_selectedList.smartType) {
      SmartListType.today => _DuePreset.today,
      SmartListType.upcoming => _DuePreset.tomorrow,
      SmartListType.inbox || null => _DuePreset.inbox,
    };
    DateTime? selectedDueAt = switch (selectedDuePreset) {
      _DuePreset.today => startOfDay(now),
      _DuePreset.tomorrow => startOfDay(now.add(const Duration(days: 1))),
      _DuePreset.inbox => null,
      _DuePreset.custom => null,
    };
    TaskPriority selectedPriority = TaskPriority.medium;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder:
              (
                BuildContext context,
                void Function(void Function()) setSheetState,
              ) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                    top: 16,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F4EE),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              const Expanded(
                                child: Text(
                                  'Quick Add',
                                  style: TextStyle(
                                    color: Color(0xFF201A17),
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            key: const ValueKey<String>('add-task-title'),
                            autofocus: true,
                            onChanged: (String value) {
                              title = value;
                            },
                            decoration: InputDecoration(
                              hintText: 'Task title',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const ValueKey<String>('add-task-note'),
                            minLines: 2,
                            maxLines: 4,
                            onChanged: (String value) {
                              note = value;
                            },
                            decoration: InputDecoration(
                              hintText: 'Notes',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            key: const ValueKey<String>('add-task-tags'),
                            onChanged: (String value) {
                              tagsText = value;
                            },
                            decoration: InputDecoration(
                              hintText: 'Tags (e.g. design, launch)',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Due',
                            style: TextStyle(
                              color: Color(0xFF6C6159),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _DuePreset.values
                                .where((preset) => preset != _DuePreset.custom)
                                .map((preset) {
                                  return _ChoiceChipButton(
                                    label: preset.label,
                                    isSelected: selectedDuePreset == preset,
                                    onTap: () {
                                      setSheetState(() {
                                        selectedDuePreset = preset;
                                        selectedDueAt = switch (preset) {
                                          _DuePreset.today => startOfDay(now),
                                          _DuePreset.tomorrow => startOfDay(
                                            now.add(const Duration(days: 1)),
                                          ),
                                          _DuePreset.inbox => null,
                                          _DuePreset.custom => selectedDueAt,
                                        };
                                      });
                                    },
                                  );
                                })
                                .toList(),
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            key: const ValueKey<String>(
                              'quick-add-date-picker',
                            ),
                            onPressed: () async {
                              final DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDueAt ?? now,
                                firstDate: startOfDay(
                                  now.subtract(const Duration(days: 365)),
                                ),
                                lastDate: startOfDay(
                                  now.add(const Duration(days: 365 * 3)),
                                ),
                                builder: (BuildContext context, Widget? child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: Color(0xFFF0632A),
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked == null) {
                                return;
                              }
                              setSheetState(() {
                                selectedDueAt = startOfDay(picked);
                                selectedDuePreset = _DuePreset.custom;
                              });
                            },
                            icon: const Icon(
                              Icons.calendar_today_rounded,
                              size: 18,
                            ),
                            label: Text(
                              selectedDueAt == null
                                  ? 'Pick a date'
                                  : formatDueLabel(
                                      selectedDueAt,
                                      fallback: 'Inbox',
                                    ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF4A413C),
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextButton.icon(
                            key: const ValueKey<String>(
                              'quick-add-time-picker',
                            ),
                            onPressed: () async {
                              final TimeOfDay initialTime =
                                  selectedDueAt != null
                                  ? TimeOfDay.fromDateTime(selectedDueAt!)
                                  : TimeOfDay.fromDateTime(now);
                              final TimeOfDay? picked = await showTimePicker(
                                context: context,
                                initialTime: initialTime,
                                builder: (BuildContext context, Widget? child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: Color(0xFFF0632A),
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked == null) {
                                return;
                              }
                              setSheetState(() {
                                final DateTime base =
                                    selectedDueAt ?? startOfDay(now);
                                selectedDueAt = DateTime(
                                  base.year,
                                  base.month,
                                  base.day,
                                  picked.hour,
                                  picked.minute,
                                );
                                selectedDuePreset = _DuePreset.custom;
                              });
                            },
                            icon: const Icon(
                              Icons.access_time_rounded,
                              size: 18,
                            ),
                            label: Text(
                              selectedDueAt == null
                                  ? 'Pick a time'
                                  : MaterialLocalizations.of(
                                      context,
                                    ).formatTimeOfDay(
                                      TimeOfDay.fromDateTime(selectedDueAt!),
                                    ),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF4A413C),
                              backgroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'List',
                            style: TextStyle(
                              color: Color(0xFF6C6159),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: _store.lists
                                .where(
                                  (list) => list.kind == TaskListKind.custom,
                                )
                                .map((list) {
                                  return _ChoiceChipButton(
                                    label: list.name,
                                    isSelected: selectedListId == list.id,
                                    leadingColor: list.color,
                                    onTap: () {
                                      setSheetState(() {
                                        selectedListId = list.id;
                                      });
                                    },
                                  );
                                })
                                .toList(),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Priority',
                            style: TextStyle(
                              color: Color(0xFF6C6159),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: TaskPriority.values.map((priority) {
                              return _ChoiceChipButton(
                                label: priority.label,
                                isSelected: selectedPriority == priority,
                                leadingColor: priority.color,
                                onTap: () {
                                  setSheetState(() {
                                    selectedPriority = priority;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              key: const ValueKey<String>('save-task-button'),
                              onPressed: () async {
                                final NavigatorState navigator = Navigator.of(
                                  context,
                                );
                                final String trimmedTitle = title.trim();
                                final String trimmedNote = note.trim();
                                if (trimmedTitle.isEmpty) {
                                  return;
                                }

                                final SmartListType bucket = bucketForDueAt(
                                  selectedDueAt,
                                );

                                final FlameTask task = FlameTask(
                                  id: 'task-${DateTime.now().microsecondsSinceEpoch}',
                                  title: trimmedTitle,
                                  note: trimmedNote.isEmpty
                                      ? 'No extra notes yet.'
                                      : trimmedNote,
                                  dueLabel: formatDueLabel(
                                    selectedDueAt,
                                    fallback: selectedDuePreset.label,
                                  ),
                                  dueAt: selectedDueAt,
                                  listId: selectedListId,
                                  bucket: bucket,
                                  priority: selectedPriority,
                                  checklistDone: 0,
                                  checklistTotal: 1,
                                  isFlagged:
                                      selectedPriority == TaskPriority.high,
                                  tags: parseTags(tagsText),
                                );
                                await _store.addTask(task);
                                if (!mounted) {
                                  return;
                                }
                                setState(() {
                                  _selectedListId = _selectedListForTask(task);
                                  _selectedSegmentIndex = 0;
                                });

                                navigator.pop();
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFF0632A),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text(
                                'Create Task',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
        );
      },
    );
  }

  String _selectedListForTask(FlameTask task) {
    if (_selectedList.kind == TaskListKind.custom) {
      return task.listId;
    }

    return switch (task.bucket) {
      SmartListType.today => 'today',
      SmartListType.inbox => 'inbox',
      SmartListType.upcoming => 'upcoming',
    };
  }

  Future<void> _openTaskEditor(FlameTask task) async {
    final TaskEditorResult? result = await Navigator.of(context)
        .push<TaskEditorResult>(
          MaterialPageRoute<TaskEditorResult>(
            builder: (BuildContext context) => TaskEditorScreen(
              task: task,
              lists: _store.lists,
              allTags: _allTags,
            ),
          ),
        );

    if (result == null) {
      return;
    }

    if (result.isDelete) {
      await _store.deleteTask(result.deletedTaskId!);
      return;
    }

    if (result.task != null) {
      await _store.updateTask(result.task!);
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedListId = _selectedListForTask(result.task!);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_store.isLoaded) {
      return const Scaffold(
        backgroundColor: Color(0xFFF6F2EB),
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: Color(0xFFF0632A)),
          ),
        ),
      );
    }

    final Color background = Theme.of(context).colorScheme.surface;
    final List<FlameTask> visibleTasks = _visibleTasks;
    final int doneCount = _baseVisibleTasks.where((task) => task.isDone).length;
    final int openCount = _baseVisibleTasks.length - doneCount;
    final String headerDate = formatHeaderDate(DateTime.now());
    final FlameTask? suggestedTask = _store.tasks
        .where((task) => !task.isDone && task.priority == TaskPriority.high)
        .firstOrNull;
    final List<Widget> taskItems = _buildTaskItems(visibleTasks);

    final Widget body = switch (_selectedNavIndex) {
      0 => _buildListBody(
        headerDate: headerDate,
        openCount: openCount,
        doneCount: doneCount,
        suggestedTask: suggestedTask,
        visibleTasks: visibleTasks,
        taskItems: taskItems,
      ),
      1 => _buildCalendarBody(headerDate),
      2 => _buildFocusBody(headerDate),
      _ => _buildBrowseBody(headerDate),
    };

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: background,
      drawer: _TaskDrawer(
        lists: _store.lists,
        selectedListId: _selectedListId,
        countForList: _openCountForList,
        onSelectList: (TaskListItem list) {
          setState(() {
            _selectedListId = list.id;
            _selectedSegmentIndex = 0;
          });
          Navigator.of(context).pop();
        },
        onSettings: () {
          Navigator.of(context).pop();
          context.push('/settings');
        },
        onLogout: () async {
          Navigator.of(context).pop();
          await AuthService().signOut();
          if (mounted) context.go('/login');
        },
      ),
      floatingActionButton: FloatingActionButton(
        key: const ValueKey<String>('quick-add-button'),
        onPressed: _openQuickAddSheet,
        backgroundColor: const Color(0xFFF0632A),
        foregroundColor: Colors.white,
        elevation: 2,
        child: const Icon(Icons.add, size: 28),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _DashboardBottomBar(
        currentIndex: _selectedNavIndex,
        onSelected: (int index) {
          setState(() {
            _selectedNavIndex = index;
          });
        },
      ),
      body: body,
    );
  }

  Widget _buildListBody({
    required String headerDate,
    required int openCount,
    required int doneCount,
    required FlameTask? suggestedTask,
    required List<FlameTask> visibleTasks,
    required List<Widget> taskItems,
  }) {
    return SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            sliver: SliverList(
              delegate: SliverChildListDelegate(<Widget>[
                _DashboardHeader(
                  selectedList: _selectedList,
                  headerDate: headerDate,
                  onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                const SizedBox(height: 20),
                _OverviewCard(
                  selectedList: _selectedList,
                  openCount: openCount,
                  doneCount: doneCount,
                  progress: _baseVisibleTasks.isEmpty
                      ? 0
                      : doneCount / _baseVisibleTasks.length,
                  userId: AuthService().uid,
                ),
                if (suggestedTask != null) ...<Widget>[
                  const SizedBox(height: 18),
                  _SuggestedTaskCard(
                    task: suggestedTask,
                    onTap: () => _openTaskEditor(suggestedTask),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _segments.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final _TaskSegment segment = _segments[index];
                      final bool isSelected = index == _selectedSegmentIndex;
                      final int count = switch (segment) {
                        _TaskSegment.all => _baseVisibleTasks.length,
                        _TaskSegment.open =>
                          _baseVisibleTasks
                              .where((task) => !task.isDone)
                              .length,
                        _TaskSegment.done =>
                          _baseVisibleTasks.where((task) => task.isDone).length,
                      };

                      return _FilterPill(
                        label: segment.label,
                        count: count,
                        isSelected: isSelected,
                        onTap: () {
                          setState(() {
                            _selectedSegmentIndex = index;
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: _selectedList.name,
                  subtitle: _sectionSubtitle(openCount),
                  sortLabel: _sortOption.label,
                  onSortSelected: (value) {
                    setState(() {
                      _sortOption = value;
                    });
                  },
                ),
                const SizedBox(height: 14),
              ]),
            ),
          ),
          if (visibleTasks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _EmptyStateCard(listName: _selectedList.name),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverList(delegate: SliverChildListDelegate(taskItems)),
            ),
        ],
      ),
    );
  }

  Widget _buildCalendarBody(String headerDate) {
    final List<FlameTask> datedTasks = _store.tasks
        .where((task) => task.effectiveDueAt != null)
        .toList();
    final Map<DateTime, int> weekCounts = _weekTaskCounts(datedTasks);
    final List<FlameTask> selectedTasks = datedTasks
        .where((task) => isSameDay(task.effectiveDueAt!, _calendarSelectedDate))
        .toList();
    final List<_TaskSection> sections = selectedTasks.isEmpty
        ? <_TaskSection>[]
        : <_TaskSection>[
            _TaskSection(
              title: formatUpcomingHeader(_calendarSelectedDate),
              tasks: selectedTasks,
            ),
          ];

    return SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            sliver: SliverList(
              delegate: SliverChildListDelegate(<Widget>[
                _SimpleHeader(
                  title: 'Calendar',
                  subtitle: headerDate,
                  onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                const SizedBox(height: 18),
                _WeekStrip(
                  reference: DateTime.now(),
                  selectedDate: _calendarSelectedDate,
                  countsByDate: weekCounts,
                  onSelected: (DateTime date) {
                    setState(() {
                      _calendarSelectedDate = date;
                    });
                  },
                ),
                const SizedBox(height: 24),
              ]),
            ),
          ),
          if (sections.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _PlaceholderCard(
                  title:
                      'No tasks on ${formatUpcomingHeader(_calendarSelectedDate)}',
                  subtitle: 'Add a due date or pick another day.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _buildCalendarItems(sections),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildCalendarItems(List<_TaskSection> sections) {
    final List<Widget> items = <Widget>[];
    for (int sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final _TaskSection section = sections[sectionIndex];
      items.add(_UpcomingSectionHeader(title: section.title));
      items.add(const SizedBox(height: 12));
      for (int index = 0; index < section.tasks.length; index++) {
        final FlameTask task = section.tasks[index];
        items.add(_buildTaskTile(task));
        if (index != section.tasks.length - 1) {
          items.add(const SizedBox(height: 12));
        }
      }
      if (sectionIndex != sections.length - 1) {
        items.add(const SizedBox(height: 20));
      }
    }
    return items;
  }

  Map<DateTime, int> _weekTaskCounts(List<FlameTask> tasks) {
    final DateTime start = startOfDay(DateTime.now());
    final DateTime end = start.add(const Duration(days: 7));
    final Map<DateTime, int> counts = <DateTime, int>{};
    for (final FlameTask task in tasks) {
      final DateTime due = startOfDay(task.effectiveDueAt!);
      if (due.isBefore(start) || !due.isBefore(end)) {
        continue;
      }
      counts[due] = (counts[due] ?? 0) + 1;
    }
    return counts;
  }

  Widget _buildBrowseBody(String headerDate) {
    final List<FlameTask> tasks = _store.tasks;
    final String query = _browseQuery.trim().toLowerCase();
    final List<String> topTags = _topTags(tasks);
    final Map<String, TaskListItem> listLookup = {
      for (final TaskListItem list in _store.lists) list.id: list,
    };

    final List<FlameTask> matches = query.isEmpty
        ? <FlameTask>[]
        : tasks.where((task) {
            final TaskListItem? list = listLookup[task.listId];
            final String haystack = [
              task.title,
              task.note,
              task.displayDueLabel,
              task.tags.join(' '),
              list?.name ?? '',
            ].join(' ').toLowerCase();
            return haystack.contains(query);
          }).toList();

    return SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            sliver: SliverList(
              delegate: SliverChildListDelegate(<Widget>[
                _SimpleHeader(
                  title: 'Browse',
                  subtitle: headerDate,
                  onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey<String>('browse-search-field'),
                  controller: _browseController,
                  onChanged: (String value) {
                    setState(() {
                      _browseQuery = value;
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search tasks or lists',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _browseController.clear();
                              setState(() {
                                _browseQuery = '';
                              });
                            },
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (topTags.isNotEmpty) ...<Widget>[
                  const Text(
                    'Tags',
                    style: TextStyle(
                      color: Color(0xFF6C6159),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: topTags.map((tag) {
                      return ActionChip(
                        label: Text('#$tag'),
                        backgroundColor: const Color(0xFFF1ECF7),
                        labelStyle: const TextStyle(
                          color: Color(0xFF6C6159),
                          fontWeight: FontWeight.w700,
                        ),
                        onPressed: () {
                          _browseController.text = tag;
                          _browseController.selection =
                              TextSelection.fromPosition(
                                TextPosition(offset: tag.length),
                              );
                          setState(() {
                            _browseQuery = tag;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                ],
              ]),
            ),
          ),
          if (query.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _PlaceholderCard(
                  title: 'Search everything',
                  subtitle: 'Find tasks, notes, and lists instantly from here.',
                ),
              ),
            )
          else if (matches.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _PlaceholderCard(
                  title: 'No matches',
                  subtitle: 'Try another keyword or clear your search.',
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
              sliver: SliverList.separated(
                itemCount: matches.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(height: 12),
                itemBuilder: (BuildContext context, int index) {
                  final FlameTask task = matches[index];
                  return _buildTaskTile(task);
                },
              ),
            ),
        ],
      ),
    );
  }

  List<String> _topTags(List<FlameTask> tasks) {
    final Map<String, int> counts = <String, int>{};
    for (final FlameTask task in tasks) {
      for (final String tag in task.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final List<String> tags = counts.keys.toList();
    tags.sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return tags.take(8).toList();
  }

  Widget _buildFocusBody(String headerDate) {
    final double progress = _focusRemaining.inSeconds <= 0
        ? 0
        : _focusRemaining.inSeconds / _focusDuration.inSeconds;
    final String timeLabel = _formatDuration(_focusRemaining);
    final List<FlameTask> openTasks = _store.tasks
        .where((task) => !task.isDone)
        .toList();
    final FlameTask? focusedTask = _resolveFocusedTask(openTasks);

    return SafeArea(
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            sliver: SliverList(
              delegate: SliverChildListDelegate(<Widget>[
                _SimpleHeader(
                  title: 'Focus',
                  subtitle: headerDate,
                  onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                ),
                const SizedBox(height: 24),
                _FocusCard(
                  timeLabel: timeLabel,
                  progress: progress,
                  taskTitle: focusedTask?.title,
                ),
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey<String>('focus-toggle-button'),
                        onPressed: _toggleFocusTimer,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF201A17),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Text(
                          _isFocusRunning ? 'Pause' : 'Start',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey<String>('focus-reset-button'),
                        onPressed: _resetFocusTimer,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF8A7F76),
                          side: const BorderSide(color: Color(0xFFE6DED6)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: const Text(
                          'Reset',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _FocusTaskSection(
                  tasks: openTasks,
                  focusedTaskId: focusedTask?.id,
                  onSelectTask: (FlameTask task) {
                    setState(() {
                      _focusedTaskId = task.id;
                    });
                  },
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleFocusTimer() {
    if (_isFocusRunning) {
      _focusTimer?.cancel();
      NotificationService().cancelFocusComplete();
      setState(() {
        _isFocusRunning = false;
      });
      return;
    }

    _focusTimer?.cancel();
    setState(() {
      _isFocusRunning = true;
    });

    NotificationService().scheduleFocusComplete(_focusRemaining);

    _focusTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_focusRemaining.inSeconds <= 1) {
          _focusRemaining = Duration.zero;
          _isFocusRunning = false;
          timer.cancel();
        } else {
          _focusRemaining -= const Duration(seconds: 1);
        }
      });
    });
  }

  void _resetFocusTimer() {
    _focusTimer?.cancel();
    NotificationService().cancelFocusComplete();
    setState(() {
      _focusRemaining = _focusDuration;
      _isFocusRunning = false;
    });
  }

  String _formatDuration(Duration duration) {
    final int minutes = duration.inMinutes.remainder(60);
    final int seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  FlameTask? _resolveFocusedTask(List<FlameTask> openTasks) {
    if (openTasks.isEmpty) {
      return null;
    }
    if (_focusedTaskId == null) {
      return openTasks.first;
    }
    return openTasks.firstWhere(
      (task) => task.id == _focusedTaskId,
      orElse: () => openTasks.first,
    );
  }

  List<Widget> _buildTaskItems(List<FlameTask> tasks) {
    final List<Widget> items = <Widget>[];
    if (tasks.isEmpty) {
      return items;
    }

    final List<FlameTask> sortedTasks = _sortedTasks(tasks);

    final bool isUpcoming =
        _selectedList.kind == TaskListKind.smart &&
        _selectedList.smartType == SmartListType.upcoming;

    if (!isUpcoming) {
      for (int index = 0; index < sortedTasks.length; index++) {
        final FlameTask task = sortedTasks[index];
        items.add(_buildTaskTile(task));
        if (index != sortedTasks.length - 1) {
          items.add(const SizedBox(height: 12));
        }
      }
      return items;
    }

    final List<_TaskSection> sections = _buildUpcomingSections(sortedTasks);
    for (int sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final _TaskSection section = sections[sectionIndex];
      items.add(_UpcomingSectionHeader(title: section.title));
      items.add(const SizedBox(height: 12));
      for (int index = 0; index < section.tasks.length; index++) {
        final FlameTask task = section.tasks[index];
        items.add(_buildTaskTile(task));
        if (index != section.tasks.length - 1) {
          items.add(const SizedBox(height: 12));
        }
      }
      if (sectionIndex != sections.length - 1) {
        items.add(const SizedBox(height: 20));
      }
    }

    return items;
  }

  Widget _buildTaskTile(FlameTask task) {
    final TaskListItem list = _store.lists.firstWhere(
      (item) => item.id == task.listId,
    );
    return _TaskTile(
      task: task,
      list: list,
      onTap: () => _openTaskEditor(task),
      onChanged: (bool? value) async {
        await _store.toggleTaskCompletion(task.id, value ?? false);
      },
    );
  }

  List<_TaskSection> _buildUpcomingSections(List<FlameTask> tasks) {
    final SplayTreeMap<DateTime, List<FlameTask>> grouped =
        SplayTreeMap<DateTime, List<FlameTask>>();
    final List<FlameTask> undated = <FlameTask>[];
    final List<FlameTask> sorted = List<FlameTask>.from(tasks)
      ..sort(_compareTasksByDueThenSort);

    for (final FlameTask task in sorted) {
      final DateTime? dueAt = task.effectiveDueAt;
      if (dueAt == null) {
        undated.add(task);
        continue;
      }
      final DateTime key = startOfDay(dueAt);
      grouped.putIfAbsent(key, () => <FlameTask>[]).add(task);
    }

    final List<_TaskSection> sections = <_TaskSection>[];
    for (final MapEntry<DateTime, List<FlameTask>> entry in grouped.entries) {
      entry.value.sort(_compareTasksForSort);
      sections.add(
        _TaskSection(
          title: formatUpcomingHeader(entry.key),
          tasks: entry.value,
        ),
      );
    }

    if (undated.isNotEmpty) {
      undated.sort(_compareTasksForSort);
      sections.add(_TaskSection(title: 'Someday', tasks: undated));
    }

    return sections;
  }

  List<String> get _allTags {
    final Set<String> tags = <String>{};
    for (final FlameTask task in _store.tasks) {
      tags.addAll(task.tags);
    }
    final List<String> result = tags.toList()..sort();
    return result;
  }

  List<FlameTask> _sortedTasks(List<FlameTask> tasks) {
    if (_sortOption == _SortOption.defaultOrder) {
      return tasks;
    }
    final List<FlameTask> sorted = List<FlameTask>.from(tasks);
    sorted.sort(_compareTasksForSort);
    return sorted;
  }

  int _compareTasksByDueThenSort(FlameTask a, FlameTask b) {
    final DateTime? dueA = a.effectiveDueAt;
    final DateTime? dueB = b.effectiveDueAt;
    if (dueA == null && dueB == null) {
      return _compareTasksForSort(a, b);
    }
    if (dueA == null) {
      return 1;
    }
    if (dueB == null) {
      return -1;
    }
    final int dateCompare = dueA.compareTo(dueB);
    if (dateCompare != 0) {
      return dateCompare;
    }
    return _compareTasksForSort(a, b);
  }

  int _compareTasksForSort(FlameTask a, FlameTask b) {
    switch (_sortOption) {
      case _SortOption.dueDate:
        return _compareByDueDate(a, b);
      case _SortOption.priority:
        return _compareByPriority(a, b);
      case _SortOption.title:
        return a.title.compareTo(b.title);
      case _SortOption.defaultOrder:
        return 0;
    }
  }

  int _compareByDueDate(FlameTask a, FlameTask b) {
    final DateTime? dueA = a.effectiveDueAt;
    final DateTime? dueB = b.effectiveDueAt;
    if (dueA == null && dueB == null) {
      return a.title.compareTo(b.title);
    }
    if (dueA == null) {
      return 1;
    }
    if (dueB == null) {
      return -1;
    }
    final int dateCompare = dueA.compareTo(dueB);
    if (dateCompare != 0) {
      return dateCompare;
    }
    return a.title.compareTo(b.title);
  }

  int _compareByPriority(FlameTask a, FlameTask b) {
    final int rankA = _priorityRank(a.priority);
    final int rankB = _priorityRank(b.priority);
    if (rankA != rankB) {
      return rankA.compareTo(rankB);
    }
    return a.title.compareTo(b.title);
  }

  int _priorityRank(TaskPriority priority) {
    return switch (priority) {
      TaskPriority.high => 0,
      TaskPriority.medium => 1,
      TaskPriority.low => 2,
    };
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.selectedList,
    required this.headerDate,
    required this.onMenuTap,
  });

  final TaskListItem selectedList;
  final String headerDate;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      children: <Widget>[
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey<String>('open-drawer-button'),
            borderRadius: BorderRadius.circular(16),
            onTap: onMenuTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Icon(Icons.menu_rounded, color: scheme.onSurface),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                headerDate,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                selectedList.name,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: selectedList.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(selectedList.icon, color: selectedList.color),
        ),
      ],
    );
  }
}

class _OverviewCard extends StatefulWidget {
  const _OverviewCard({
    required this.selectedList,
    required this.openCount,
    required this.doneCount,
    required this.progress,
    this.userId,
  });

  final TaskListItem selectedList;
  final int openCount;
  final int doneCount;
  final double progress;
  final String? userId;

  @override
  State<_OverviewCard> createState() => _OverviewCardState();
}

class _OverviewCardState extends State<_OverviewCard> {
  StreakRecord? _streak;

  @override
  void initState() {
    super.initState();
    _loadStreak();
  }

  Future<void> _loadStreak() async {
    if (widget.userId == null) return;
    final StreakRecord record =
        await StreakService().getStreak(widget.userId!);
    if (mounted) setState(() => _streak = record);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFF1F1A17), Color(0xFF3A312D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  widget.selectedList.kind == TaskListKind.smart
                      ? 'Smart List'
                      : 'Project List',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              if (_streak != null) ...<Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0632A).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.local_fire_department_rounded,
                          size: 16, color: Color(0xFFF7A674)),
                      const SizedBox(width: 4),
                      Text(
                        '${_streak!.current} day streak',
                        style: const TextStyle(
                          color: Color(0xFFF7A674),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Icon(widget.selectedList.icon, color: widget.selectedList.color),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Keep ${widget.selectedList.name.toLowerCase()} moving',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Quick capture, edit, and sync to the cloud. Every task, every day.',
            style: TextStyle(color: Color(0xFFD9D0CA), height: 1.45),
          ),
          const SizedBox(height: 22),
          Row(
            children: <Widget>[
              Expanded(
                child: _OverviewMetric(
                  value: '${widget.openCount}',
                  label: 'Open tasks',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OverviewMetric(
                    value: '${widget.doneCount}', label: 'Completed'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: widget.progress,
              backgroundColor: Colors.white.withValues(alpha: 0.12),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFF7A674),
              ),
            ),
          ),
        ],
      ),
    );
  }

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD9D0CA),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestedTaskCard extends StatelessWidget {
  const _SuggestedTaskCard({required this.task, required this.onTap});

  final FlameTask task;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey<String>('suggested-task-card'),
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: scheme.onSecondaryContainer.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text(
                      'Suggested Task',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.title,
                      style: TextStyle(
                        color: scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_right_rounded,
                color: scheme.onSecondaryContainer,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? scheme.primary : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? scheme.onPrimary : scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? scheme.onPrimary.withValues(alpha: 0.2)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: isSelected
                        ? scheme.onPrimary
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.sortLabel,
    required this.onSortSelected,
  });

  final String title;
  final String subtitle;
  final String sortLabel;
  final ValueChanged<_SortOption> onSortSelected;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: scheme.onSurface.withValues(alpha: 0.6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        PopupMenuButton<_SortOption>(
          onSelected: onSortSelected,
          itemBuilder: (BuildContext context) {
            return _SortOption.values.map((option) {
              return PopupMenuItem<_SortOption>(
                value: option,
                child: Text(option.label),
              );
            }).toList();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.sort_rounded, size: 18, color: scheme.onSurface),
                const SizedBox(width: 6),
                Text(
                  sortLabel,
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _SortOption {
  defaultOrder('Default'),
  dueDate('Due date'),
  priority('Priority'),
  title('Title');

  const _SortOption(this.label);

  final String label;
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.list,
    required this.onTap,
    required this.onChanged,
  });

  final FlameTask task;
  final TaskListItem list;
  final VoidCallback onTap;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDone = task.isDone;
    final DateTime? dueAt = task.effectiveDueAt;
    final bool isOverdue =
        dueAt != null && dueAt.isBefore(startOfDay(DateTime.now())) && !isDone;
    return Material(
      key: ValueKey<String>('task-tile-${task.id}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDone
                ? scheme.surfaceContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Transform.scale(
                scale: 1.08,
                child: Checkbox(
                  key: ValueKey<String>('checkbox-${task.title}'),
                  value: isDone,
                  onChanged: onChanged,
                  activeColor: scheme.primary,
                  side: BorderSide(color: scheme.outlineVariant, width: 1.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            task.title,
                            style: TextStyle(
                              color: scheme.onSurface,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              decoration: isDone
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: scheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ),
                        if (task.isFlagged)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.flag_rounded,
                              size: 18,
                              color: task.priority.color,
                            ),
                          ),
                        _PriorityDot(priority: task.priority),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      task.note,
                      style: TextStyle(
                        color: isDone
                            ? scheme.onSurface.withValues(alpha: 0.55)
                            : scheme.onSurface.withValues(alpha: 0.7),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        if (isOverdue) const _OverdueChip(),
                        _MetaChip(
                          icon: Icons.access_time_rounded,
                          label: task.displayDueLabel,
                        ),
                        _MetaChip(icon: list.icon, label: list.name),
                        _MetaChip(
                          icon: Icons.checklist_rounded,
                          label: '${task.checklistDone}/${task.checklistTotal}',
                        ),
                        for (final String tag in task.tags)
                          _TagChip(label: tag),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverdueChip extends StatelessWidget {
  const _OverdueChip();

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.warning_rounded, size: 14, color: scheme.onErrorContainer),
          const SizedBox(width: 6),
          Text(
            'Overdue',
            style: TextStyle(
              color: scheme.onErrorContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.tag_rounded, size: 14, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            '#$label',
            style: TextStyle(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriorityDot extends StatelessWidget {
  const _PriorityDot({required this.priority});

  final TaskPriority priority;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: priority.color, shape: BoxShape.circle),
    );
  }
}

class _TaskDrawer extends StatelessWidget {
  const _TaskDrawer({
    required this.lists,
    required this.selectedListId,
    required this.countForList,
    required this.onSelectList,
    required this.onSettings,
    required this.onLogout,
  });

  final List<TaskListItem> lists;
  final String selectedListId;
  final int Function(TaskListItem list) countForList;
  final ValueChanged<TaskListItem> onSelectList;
  final VoidCallback onSettings;
  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    final List<TaskListItem> smartLists = lists
        .where((list) => list.kind == TaskListKind.smart)
        .toList();
    final List<TaskListItem> customLists = lists
        .where((list) => list.kind == TaskListKind.custom)
        .toList();

    return Drawer(
      backgroundColor: const Color(0xFFF8F4EE),
      child: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE2D4),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.checklist_rounded,
                      color: Color(0xFFF0632A),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Flameup',
                          style: TextStyle(
                            color: Color(0xFF201A17),
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Tasks, lists, and focus',
                          style: TextStyle(
                            color: Color(0xFF8A7F76),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: <Widget>[
                  const _DrawerSectionLabel(label: 'Smart Lists'),
                  for (final TaskListItem list in smartLists)
                    _DrawerListTile(
                      list: list,
                      isSelected: selectedListId == list.id,
                      count: countForList(list),
                      onTap: () => onSelectList(list),
                    ),
                  const SizedBox(height: 16),
                  const _DrawerSectionLabel(label: 'My Lists'),
                  for (final TaskListItem list in customLists)
                    _DrawerListTile(
                      list: list,
                      isSelected: selectedListId == list.id,
                      count: countForList(list),
                      onTap: () => onSelectList(list),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: <Widget>[
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    tileColor: Colors.white,
                    leading: const Icon(Icons.settings_rounded),
                    title: const Text(
                      'Settings',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: onSettings,
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    tileColor: Colors.white,
                    leading: const Icon(Icons.logout_rounded),
                    title: const Text(
                      'Log out',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: onLogout,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF8A7F76),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DrawerListTile extends StatelessWidget {
  const _DrawerListTile({
    required this.list,
    required this.isSelected,
    required this.count,
    required this.onTap,
  });

  final TaskListItem list;
  final bool isSelected;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey<String>('drawer-list-${list.id}'),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      tileColor: isSelected ? list.color.withValues(alpha: 0.14) : null,
      leading: Icon(list.icon, color: list.color),
      title: Text(
        list.name,
        style: TextStyle(
          color: const Color(0xFF201A17),
          fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '$count',
          style: const TextStyle(
            color: Color(0xFF6C6159),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

class _DashboardBottomBar extends StatelessWidget {
  const _DashboardBottomBar({
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const List<_NavItem> items = <_NavItem>[
      _NavItem(icon: Icons.today_rounded, label: 'Today'),
      _NavItem(icon: Icons.calendar_month_rounded, label: 'Calendar'),
      _NavItem(icon: Icons.timer_outlined, label: 'Focus'),
      _NavItem(icon: Icons.search_rounded, label: 'Browse'),
    ];

    return BottomAppBar(
      padding: EdgeInsets.zero,
      height: 82,
      color: Colors.white,
      shape: const CircularNotchedRectangle(),
      notchMargin: 10,
      child: Row(
        children: <Widget>[
          for (int index = 0; index < 2; index++)
            Expanded(
              child: _BottomBarButton(
                item: items[index],
                isSelected: currentIndex == index,
                onTap: () => onSelected(index),
              ),
            ),
          const SizedBox(width: 72),
          for (int index = 2; index < items.length; index++)
            Expanded(
              child: _BottomBarButton(
                item: items[index],
                isSelected: currentIndex == index,
                onTap: () => onSelected(index),
              ),
            ),
        ],
      ),
    );
  }
}

class _BottomBarButton extends StatelessWidget {
  const _BottomBarButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = isSelected
        ? const Color(0xFFF0632A)
        : const Color(0xFF8A7F76);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(item.icon, color: color),
            const SizedBox(height: 4),
            Text(
              item.label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceChipButton extends StatelessWidget {
  const _ChoiceChipButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.leadingColor,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? leadingColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF201A17) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF201A17)
                : const Color(0xFFE6DED6),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (leadingColor != null) ...<Widget>[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: leadingColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF4A413C),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.listName});

  final String listName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8DB),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.done_all_rounded,
              size: 36,
              color: Color(0xFFF0632A),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Nothing in ${listName.toLowerCase()}',
            style: const TextStyle(
              color: Color(0xFF201A17),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This view is clear. Add something new from quick capture below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8A7F76), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _FocusCard extends StatelessWidget {
  const _FocusCard({
    required this.timeLabel,
    required this.progress,
    this.taskTitle,
  });

  final String timeLabel;
  final double progress;
  final String? taskTitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        children: <Widget>[
          Text(
            'Focus session',
            style: const TextStyle(
              color: Color(0xFF8A7F76),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            timeLabel,
            style: const TextStyle(
              color: Color(0xFF201A17),
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            taskTitle == null ? 'No task selected' : 'Working on',
            style: const TextStyle(
              color: Color(0xFF8A7F76),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (taskTitle != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              taskTitle!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF201A17),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: const Color(0xFFF4EFE9),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFF0632A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE8DB),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              size: 32,
              color: Color(0xFFF0632A),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF201A17),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8A7F76), height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _FocusTaskSection extends StatelessWidget {
  const _FocusTaskSection({
    required this.tasks,
    required this.focusedTaskId,
    required this.onSelectTask,
  });

  final List<FlameTask> tasks;
  final String? focusedTaskId;
  final ValueChanged<FlameTask> onSelectTask;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return const _PlaceholderCard(
        title: 'No open tasks',
        subtitle: 'Add a task to start a focus session.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Pick a task to focus',
          style: TextStyle(
            color: Color(0xFF6C6159),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        for (final FlameTask task in tasks.take(5)) ...<Widget>[
          _FocusTaskTile(
            task: task,
            isSelected: task.id == focusedTaskId,
            onTap: () => onSelectTask(task),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _FocusTaskTile extends StatelessWidget {
  const _FocusTaskTile({
    required this.task,
    required this.isSelected,
    required this.onTap,
  });

  final FlameTask task;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF201A17) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF201A17)
                  : const Color(0xFFE6DED6),
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: isSelected ? Colors.white : const Color(0xFF8A7F76),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF201A17),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                task.displayDueLabel,
                style: TextStyle(
                  color: isSelected ? Colors.white70 : const Color(0xFF8A7F76),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimpleHeader extends StatelessWidget {
  const _SimpleHeader({
    required this.title,
    required this.subtitle,
    required this.onMenuTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey<String>('open-drawer-button'),
            borderRadius: BorderRadius.circular(16),
            onTap: onMenuTap,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6DED6)),
              ),
              child: const Icon(Icons.menu_rounded, color: Color(0xFF201A17)),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF8A7F76),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                key: const ValueKey<String>('simple-header-title'),
                style: const TextStyle(
                  color: Color(0xFF201A17),
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF7C61FF).withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.calendar_month_rounded,
            color: Color(0xFF7C61FF),
          ),
        ),
      ],
    );
  }
}

class _WeekStrip extends StatelessWidget {
  const _WeekStrip({
    required this.reference,
    required this.selectedDate,
    required this.countsByDate,
    required this.onSelected,
  });

  final DateTime reference;
  final DateTime selectedDate;
  final Map<DateTime, int> countsByDate;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final DateTime today = startOfDay(reference);
    final List<DateTime> days = List<DateTime>.generate(
      7,
      (int index) => startOfDay(today.add(Duration(days: index))),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: days.map((date) {
        final bool isSelected = isSameDay(date, selectedDate);
        final int count = countsByDate[date] ?? 0;
        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => onSelected(date),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF201A17) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF201A17)
                      : const Color(0xFFE6DED6),
                ),
              ),
              child: Column(
                children: <Widget>[
                  Text(
                    _weekdayShort[date.weekday - 1],
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF8A7F76),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFF201A17),
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  if (count > 0) ...<Widget>[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.18)
                            : const Color(0xFFF1ECF7),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : const Color(0xFF7C61FF),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _UpcomingSectionHeader extends StatelessWidget {
  const _UpcomingSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF201A17),
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: const Color(0xFFE7DFD6))),
      ],
    );
  }
}

class _TaskSection {
  const _TaskSection({required this.title, required this.tasks});

  final String title;
  final List<FlameTask> tasks;
}

enum _TaskSegment {
  all('All'),
  open('Open'),
  done('Done');

  const _TaskSegment(this.label);

  final String label;
}

enum _DuePreset {
  today('Today'),
  tomorrow('Tomorrow'),
  inbox('Inbox'),
  custom('Custom');

  const _DuePreset(this.label);

  final String label;
}

class _NavItem {
  const _NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

const List<String> _weekdayShort = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

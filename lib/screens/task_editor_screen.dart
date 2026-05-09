import 'package:flutter/material.dart';

import '../models/task_models.dart';

class TaskEditorScreen extends StatefulWidget {
  const TaskEditorScreen({
    required this.task,
    required this.lists,
    required this.allTags,
    super.key,
  });

  final FlameTask task;
  final List<TaskListItem> lists;
  final List<String> allTags;

  @override
  State<TaskEditorScreen> createState() => _TaskEditorScreenState();
}

class _TaskEditorScreenState extends State<TaskEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late final TextEditingController _tagsController;
  late String _selectedListId;
  late TaskPriority _selectedPriority;
  late _DuePreset _selectedDuePreset;
  DateTime? _selectedDueAt;
  late bool _isDone;
  late bool _isFlagged;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _noteController = TextEditingController(text: widget.task.note);
    _tagsController = TextEditingController(text: formatTags(widget.task.tags));
    _selectedListId = widget.task.listId;
    _selectedPriority = widget.task.priority;
    _selectedDueAt = widget.task.effectiveDueAt;
    _selectedDuePreset = _presetForDate(_selectedDueAt);
    _isDone = widget.task.isDone;
    _isFlagged = widget.task.isFlagged;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  void _save() {
    final String title = _titleController.text.trim();
    if (title.isEmpty) {
      return;
    }

    final FlameTask updatedTask = widget.task.copyWith(
      title: title,
      note: _noteController.text.trim().isEmpty
          ? 'No extra notes yet.'
          : _noteController.text.trim(),
      tags: parseTags(_tagsController.text),
      dueLabel: formatDueLabel(
        _selectedDueAt,
        fallback: _selectedDuePreset.label,
      ),
      dueAt: _selectedDueAt,
      listId: _selectedListId,
      bucket: bucketForDueAt(_selectedDueAt),
      priority: _selectedPriority,
      isDone: _isDone,
      isFlagged: _isFlagged,
    );

    Navigator.of(context).pop(TaskEditorResult.save(updatedTask));
  }

  void _delete() {
    Navigator.of(context).pop(TaskEditorResult.delete(widget.task.id));
  }

  @override
  Widget build(BuildContext context) {
    final List<TaskListItem> customLists = widget.lists
        .where((list) => list.kind == TaskListKind.custom)
        .toList();
    final List<String> suggestedTags = widget.allTags
        .where((tag) => tag.isNotEmpty)
        .toList();

    final Color background = Theme.of(context).colorScheme.surface;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        elevation: 0,
        title: const Text(
          'Edit Task',
          style: TextStyle(
            color: Color(0xFF201A17),
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF201A17)),
        actions: <Widget>[
          TextButton(
            onPressed: _save,
            child: const Text(
              'Save',
              style: TextStyle(
                color: Color(0xFFF0632A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: <Widget>[
                    TextField(
                      key: const ValueKey<String>('editor-title'),
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(
                        color: Color(0xFF201A17),
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Divider(height: 1),
                    TextField(
                      key: const ValueKey<String>('editor-note'),
                      controller: _noteController,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        border: InputBorder.none,
                      ),
                    ),
                    const Divider(height: 1),
                    TextField(
                      key: const ValueKey<String>('editor-tags'),
                      controller: _tagsController,
                      decoration: const InputDecoration(
                        labelText: 'Tags (comma separated)',
                        border: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
              if (suggestedTags.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                const _EditorSectionTitle(title: 'Suggested tags'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: suggestedTags.map((tag) {
                    return ActionChip(
                      label: Text('#$tag'),
                      backgroundColor: const Color(0xFFF1ECF7),
                      labelStyle: const TextStyle(
                        color: Color(0xFF6C6159),
                        fontWeight: FontWeight.w700,
                      ),
                      onPressed: () {
                        final List<String> updated = parseTags(
                          _tagsController.text,
                        );
                        if (!updated.contains(tag)) {
                          updated.add(tag);
                        }
                        _tagsController.text = formatTags(updated);
                        _tagsController.selection = TextSelection.fromPosition(
                          TextPosition(offset: _tagsController.text.length),
                        );
                      },
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 18),
              const _EditorSectionTitle(title: 'Due'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _DuePreset.values
                    .where((preset) => preset != _DuePreset.custom)
                    .map((preset) {
                      return _ChoiceChipButton(
                        label: preset.label,
                        isSelected: _selectedDuePreset == preset,
                        onTap: () {
                          setState(() {
                            _selectedDuePreset = preset;
                            final DateTime now = DateTime.now();
                            _selectedDueAt = switch (preset) {
                              _DuePreset.today => startOfDay(now),
                              _DuePreset.tomorrow => startOfDay(
                                now.add(const Duration(days: 1)),
                              ),
                              _DuePreset.inbox => null,
                              _DuePreset.custom => _selectedDueAt,
                            };
                          });
                        },
                      );
                    })
                    .toList(),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                key: const ValueKey<String>('editor-date-picker'),
                onPressed: () async {
                  final DateTime now = DateTime.now();
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDueAt ?? now,
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
                  setState(() {
                    _selectedDueAt = startOfDay(picked);
                    _selectedDuePreset = _DuePreset.custom;
                  });
                },
                icon: const Icon(Icons.calendar_today_rounded, size: 18),
                label: Text(
                  _selectedDueAt == null
                      ? 'Pick a date'
                      : formatDueLabel(_selectedDueAt, fallback: 'Inbox'),
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
                key: const ValueKey<String>('editor-time-picker'),
                onPressed: () async {
                  final DateTime now = DateTime.now();
                  final TimeOfDay initialTime = _selectedDueAt != null
                      ? TimeOfDay.fromDateTime(_selectedDueAt!)
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
                  setState(() {
                    final DateTime base = _selectedDueAt ?? startOfDay(now);
                    _selectedDueAt = DateTime(
                      base.year,
                      base.month,
                      base.day,
                      picked.hour,
                      picked.minute,
                    );
                    _selectedDuePreset = _DuePreset.custom;
                  });
                },
                icon: const Icon(Icons.access_time_rounded, size: 18),
                label: Text(
                  _selectedDueAt == null
                      ? 'Pick a time'
                      : MaterialLocalizations.of(context).formatTimeOfDay(
                          TimeOfDay.fromDateTime(_selectedDueAt!),
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
              const _EditorSectionTitle(title: 'List'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: customLists.map((list) {
                  return _ChoiceChipButton(
                    label: list.name,
                    isSelected: _selectedListId == list.id,
                    leadingColor: list.color,
                    onTap: () {
                      setState(() {
                        _selectedListId = list.id;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              const _EditorSectionTitle(title: 'Priority'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: TaskPriority.values.map((priority) {
                  return _ChoiceChipButton(
                    label: priority.label,
                    isSelected: _selectedPriority == priority,
                    leadingColor: priority.color,
                    onTap: () {
                      setState(() {
                        _selectedPriority = priority;
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      key: const ValueKey<String>('editor-done-switch'),
                      contentPadding: EdgeInsets.zero,
                      value: _isDone,
                      onChanged: (bool value) {
                        setState(() {
                          _isDone = value;
                        });
                      },
                      title: const Text(
                        'Completed',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      key: const ValueKey<String>('editor-flagged-switch'),
                      contentPadding: EdgeInsets.zero,
                      value: _isFlagged,
                      onChanged: (bool value) {
                        setState(() {
                          _isFlagged = value;
                        });
                      },
                      title: const Text(
                        'Flagged',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey<String>('editor-delete-button'),
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('Delete Task'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB74D2D),
                    side: const BorderSide(color: Color(0xFFE3C4B7)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
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

class TaskEditorResult {
  const TaskEditorResult._({this.task, this.deletedTaskId});

  factory TaskEditorResult.save(FlameTask task) {
    return TaskEditorResult._(task: task);
  }

  factory TaskEditorResult.delete(String taskId) {
    return TaskEditorResult._(deletedTaskId: taskId);
  }

  final FlameTask? task;
  final String? deletedTaskId;

  bool get isDelete => deletedTaskId != null;
}

enum _DuePreset {
  today('Today'),
  tomorrow('Tomorrow'),
  inbox('Inbox'),
  custom('Custom');

  const _DuePreset(this.label);

  final String label;
}

_DuePreset _presetForDate(DateTime? date) {
  if (date == null) {
    return _DuePreset.inbox;
  }
  final DateTime now = DateTime.now();
  if (isToday(date, now)) {
    return _DuePreset.today;
  }
  if (isTomorrow(date, now)) {
    return _DuePreset.tomorrow;
  }
  return _DuePreset.custom;
}

class _EditorSectionTitle extends StatelessWidget {
  const _EditorSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF6C6159),
        fontWeight: FontWeight.w800,
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

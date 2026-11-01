// wannabeYPT — planner view
// Copyright (C) 2026 redwedding
//
// This file is part of wannabeYPT. This program is free software: you can
// redistribute it and/or modify it under the terms of the GNU Affero General
// Public License as published by the Free Software Foundation, version 3.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../main.dart' show kBrand, kCard;
import 'timer_view.dart' show fmtMs;

/// To-Do in the shape of the official YPT app's To-Do screen:
/// pure black, no cards — a week strip with small day squares,
/// subject groups with a coloured bar and a ⊕ add button, tasks
/// as colour circles. (The day's session plot lives in Statistics;
/// a timetable here was dead weight and was removed 2026-10-21.)
/// Tasks from the official app (reload's `tks`) show with a small
/// YPT tag and tap to pick Done / Half-done / Not done via
/// /study/study-plan/rest;
/// tasks added here are created on the server first (so the app
/// sees them) and fall back to this device with a note if the
/// server doesn't confirm. Server tasks have no delete option here
/// (no working server delete exists) — delete them in the official
/// app instead.
class PlannerView extends StatefulWidget {
  const PlannerView({super.key});
  @override
  State<PlannerView> createState() => _PlannerViewState();
}

class _PlannerViewState extends State<PlannerView> {
  DateTime _selected = DateTime.now();
  DayDetail? _detail;
  bool _loading = false;
  final _taskCtl = TextEditingController();
  String? _addingSubject; // null = inline add closed; '' = General

  static const _square = Color(0xFF1D1D21);
  static const _hair = Color(0xFF1B1B1F);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _taskCtl.dispose();
    super.dispose();
  }

  String get _key => AppState.dateStr(_selected);

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await context.read<AppState>().fetchDay(_key);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _pick(DateTime d) {
    setState(() {
      _selected = d;
      _addingSubject = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = _selected.subtract(Duration(days: _selected.weekday - 1));
    final week = List.generate(7, (i) => monday.add(Duration(days: i)));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
      children: [
        // Header: "Wed, 10/21" like the official To-Do screen.
        Row(
          children: [
            Text(
              '${DateFormat('EEE').format(_selected)}, ${DateFormat('M/d').format(_selected)}',
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _pick(today),
              child: const Text('Today', style: TextStyle(fontSize: 13)),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.chevron_left, size: 20, color: Colors.grey[400]),
              onPressed: () =>
                  _pick(_selected.subtract(const Duration(days: 7))),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.chevron_right, size: 20, color: Colors.grey[400]),
              onPressed: () => _pick(_selected.add(const Duration(days: 7))),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Week strip: day label + a small square (✓ when selected or
        // when the day's tasks are all done, – otherwise).
        Row(
          children: [
            for (final d in week)
              Expanded(
                child: InkWell(
                  onTap: () => _pick(d),
                  child: Column(
                    children: [
                      Text(
                        '${d.day}.${DateFormat('E').format(d)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppState.dateStr(d) == _key
                              ? Colors.white
                              : Colors.grey[500],
                          fontWeight: AppState.dateStr(d) == _key
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _daySquare(st, d),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_detail != null)
          Text(
            'Total ${_detail!.totalMs > 0 ? fmtMs(_detail!.totalMs) : '0:00:00'}'
            '${_detail!.sessions.isEmpty ? '' : ' · ${_detail!.sessions.length} sessions'}',
            style: TextStyle(color: Colors.grey[500], fontSize: 12.5),
          ),
        const SizedBox(height: 6),
        const Divider(height: 1, color: _hair),
        if (st.plannerNotice != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(st.plannerNotice!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[400])),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: st.dismissPlannerNotice,
                  borderRadius: BorderRadius.circular(10),
                  child: Icon(Icons.close, size: 15, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        // To-Do groups
        ..._todoSection(st),
        const SizedBox(height: 18),
        Text('Tasks tagged YPT sync with the official app — tap a circle to set Done, Half-done, or Not done.',
            style: TextStyle(fontSize: 10.5, color: Colors.grey[600])),
      ],
    );
  }

  Widget _daySquare(AppState st, DateTime d) {
    final key = AppState.dateStr(d);
    final selected = key == _key;
    final local = st.tasksFor(key);
    final server = (st.user?.tasks ?? const <YptTask>[])
        .where((t) => t.date == key)
        .toList();
    final hasTasks = local.isNotEmpty || server.isNotEmpty;
    final allDone = hasTasks &&
        local.every((t) => t.done) &&
        server.every((t) => st.serverTaskDone(t));
    return Container(
      width: 25,
      height: 25,
      decoration: BoxDecoration(
        color: selected ? kBrand.withValues(alpha: 0.20) : _square,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Center(
        child: (selected || allDone)
            ? const Icon(Icons.check, size: 14, color: kBrand)
            : Text('–',
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ),
    );
  }

  Color _colorFor(AppState st, String title) {
    final norm = title.trim().toLowerCase();
    for (final s in st.user?.subjects ?? const <Subject>[]) {
      if (s.title.trim().toLowerCase() == norm) return s.color;
    }
    return kBrand;
  }

  String _subjectTitleFor(AppState st, int id) {
    for (final s in st.user?.subjects ?? const <Subject>[]) {
      if (s.id == id) return s.title;
    }
    return '';
  }

  List<Widget> _todoSection(AppState st) {
    final subjects = st.user?.subjects ?? const <Subject>[];
    final local = st.tasksFor(_key);
    final localGroups = <String, List<TodoTask>>{};
    for (final t in local) {
      localGroups.putIfAbsent(t.subject, () => []).add(t);
    }
    final serverGroups = <String, List<YptTask>>{};
    for (final t in st.user?.tasks ?? const <YptTask>[]) {
      if (t.date != _key) continue;
      serverGroups
          .putIfAbsent(_subjectTitleFor(st, t.subjectId), () => [])
          .add(t);
    }
    // Official order: every subject (even empty), then stray local
    // subjects, then General.
    final keys = <String>[
      for (final s in subjects) s.title,
      for (final k in localGroups.keys)
        if (k != '' && !subjects.any((s) => s.title == k)) k,
      '',
    ];
    return [
      for (final key in keys)
        if (key != '' ||
            (localGroups['']?.isNotEmpty ?? false) ||
            (serverGroups['']?.isNotEmpty ?? false) ||
            _addingSubject == '')
          _group(st, key,
              color: key == '' ? Colors.grey : _colorFor(st, key),
              local: localGroups[key] ?? const [],
              server: serverGroups[key] ?? const []),
    ];
  }

  Widget _group(AppState st, String key,
      {required Color color,
      required List<TodoTask> local,
      required List<YptTask> server}) {
    final adding = _addingSubject == key;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 15,
                decoration: BoxDecoration(
                    color: color, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 8),
              Text(key.isEmpty ? 'General' : key,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              InkWell(
                onTap: () => setState(() {
                  _addingSubject = adding ? null : key;
                  _taskCtl.clear();
                }),
                borderRadius: BorderRadius.circular(12),
                child: Icon(
                    adding ? Icons.remove_circle_outline : Icons.add_circle_outline,
                    size: 19,
                    color: Colors.grey[400]),
              ),
            ],
          ),
        ),
        for (final t in local)
          _taskRow(
            color: color,
            text: t.text,
            done: t.done,
            onToggle: () => st.toggleTask(t.id),
            onDelete: () => st.deleteTask(t.id),
          ),
        for (final t in server)
          _taskRow(
            color: color,
            text: t.title,
            done: st.serverTaskDone(t),
            server: true,
            serverScore: st.serverTaskScore(t),
            onStatusMenu: (iconCtx) => _showStatusMenu(iconCtx, st, t),
          ),
        if (adding)
          Padding(
            padding: const EdgeInsets.only(left: 11, top: 2, bottom: 4),
            child: TextField(
              controller: _taskCtl,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Add a task…',
                hintStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: _hair)),
                focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: kBrand)),
              ),
              onSubmitted: (_) {
                st.addTaskWithServer(_key, key, _taskCtl.text);
                _taskCtl.clear();
                setState(() => _addingSubject = null);
              },
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 10),
          child: Divider(height: 1, color: _hair),
        ),
      ],
    );
  }

  /// Status menu for a server task, in the official app's shape:
  /// menu items use circle-outline = Done, triangle = Half-done,
  /// X = Not done (the current state is bold + brand-coloured).
  /// Menu values are server scores: 3 Done, [kTaskHalfDoneScore]
  /// Half-done, 0 Not done (written as null); a dismissed menu
  /// returns null and changes nothing.
  Future<void> _showStatusMenu(
      BuildContext iconCtx, AppState st, YptTask t) async {
    final box = iconCtx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset.zero);
    final current = st.serverTaskScore(t);
    final picked = await showMenu<int>(
      context: iconCtx,
      color: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
          pos.dx, pos.dy + box.size.height, pos.dx + box.size.width, pos.dy),
      items: [
        _statusMenuItem(3, Icons.radio_button_unchecked, 'Done', current),
        _statusMenuItem(
            kTaskHalfDoneScore, Icons.change_history, 'Half-done', current),
        _statusMenuItem(0, Icons.close, 'Not done', current),
      ],
    );
    if (picked == null || !mounted) return;
    st.setServerTaskStatus(t, picked == 0 ? null : picked);
  }

  PopupMenuItem<int> _statusMenuItem(
      int value, IconData icon, String label, int current) {
    final selected = value == current;
    return PopupMenuItem<int>(
      value: value,
      child: Row(
        children: [
          Icon(icon,
              size: 18, color: selected ? kBrand : Colors.grey[400]),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? kBrand : Colors.grey[100])),
        ],
      ),
    );
  }

  Widget _taskRow({
    required Color color,
    required String text,
    required bool done,
    bool server = false,
    int? serverScore,
    VoidCallback? onToggle,
    void Function(BuildContext)? onStatusMenu,
    VoidCallback? onDelete,
  }) {
    // Row display: done = filled check, half-done = triangle,
    // not done = empty circle. Server rows use the score; local
    // rows keep their binary `done`.
    final score = serverScore ?? (done ? 3 : 0);
    final isDone = score == 3;
    final isHalf = score == kTaskHalfDoneScore;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Builder(
            builder: (iconCtx) => InkWell(
              onTap: onStatusMenu != null
                  ? () => onStatusMenu(iconCtx)
                  : onToggle,
              borderRadius: BorderRadius.circular(11),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.6),
                ),
                child: isDone
                    ? Icon(Icons.check, size: 12, color: color)
                    : isHalf
                        ? Icon(Icons.change_history,
                            size: 12, color: color)
                        : null,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: isDone ? Colors.grey[500] : Colors.grey[100],
              ),
            ),
          ),
          if (server)
            Text('YPT',
                style: TextStyle(fontSize: 10, color: Colors.grey[600])),
          if (onDelete != null) ...[
            if (server) const SizedBox(width: 8),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(10),
              child: Icon(Icons.close, size: 15, color: Colors.grey[600]),
            ),
          ],
        ],
      ),
    );
  }
}

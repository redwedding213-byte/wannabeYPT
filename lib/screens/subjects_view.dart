import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../main.dart' show yptCardColor, yptGrey400, yptGrey500;
import '../models.dart';
import 'timer_view.dart' show fmtMs;

/// Local archive overrides, persisted per subject id. The server's
/// archive call can return success while the reloaded subject list
/// still carries dl=false — without these, an archived subject pops
/// back to active after reload (Tara51's report). Overrides win
/// over the server flag until the server agrees with them, exactly
/// like the task done-overrides in AppState.reloadProfile.
const _kArchivedIdsKey = 'wannabe_archived_subject_ids';
const _kUnarchivedIdsKey = 'wannabe_unarchived_subject_ids';

/// Subject management: add, rename, recolour, archive/unarchive and
/// delete subjects on the server. Archived subjects come from the raw
/// reload payload (the account's subject list filters them out), so
/// this page reads reloadRaw directly. All writes are Desky-derived
/// and unproven live — a failed write shows a notice, never a crash.
class SubjectsPage extends StatefulWidget {
  const SubjectsPage({super.key});
  @override
  State<SubjectsPage> createState() => _SubjectsPageState();
}

/// Colour choices for new / edited subjects, including the brand
/// orange and a neutral grey.
const _palette = <int>[
  0xFFE8552D,
  4292557552,
  4294924032,
  4281775359,
  4280549375,
  4282827050,
  4294947910,
  0xFF888888,
];

class _SubjectsPageState extends State<SubjectsPage> {
  bool _loading = false;
  bool _failed = false;
  bool _busy = false;
  List<Subject> _subjects = [];
  Set<int> _archivedIds = {};
  Set<int> _unarchivedIds = {};

  @override
  void initState() {
    super.initState();
    _loadOverrides();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _loadOverrides() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final archived = sp.getStringList(_kArchivedIdsKey) ?? const [];
      final unarchived = sp.getStringList(_kUnarchivedIdsKey) ?? const [];
      if (!mounted) return;
      setState(() {
        _archivedIds =
            archived.map((e) => int.tryParse(e) ?? 0).where((e) => e > 0).toSet();
        _unarchivedIds = unarchived
            .map((e) => int.tryParse(e) ?? 0)
            .where((e) => e > 0)
            .toSet();
      });
    } catch (_) {}
  }

  Future<void> _saveOverrides() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_kArchivedIdsKey,
          _archivedIds.map((e) => e.toString()).toList());
      await sp.setStringList(_kUnarchivedIdsKey,
          _unarchivedIds.map((e) => e.toString()).toList());
    } catch (_) {}
  }

  /// The user's own archive choice wins over the server's dl flag
  /// until a reload shows the server agreeing with it.
  Subject _applyOverrides(Subject s) {
    if (_archivedIds.contains(s.id)) return s.copyWith(archived: true);
    if (_unarchivedIds.contains(s.id)) return s.copyWith(archived: false);
    return s;
  }

  void _dropAgreedOverrides(List<Subject> fresh) {
    final byId = {for (final s in fresh) s.id: s.archived};
    _archivedIds.removeWhere((id) => byId[id] == true);
    _unarchivedIds.removeWhere((id) => byId[id] == false);
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final st = context.read<AppState>();
      final raw = await st.api.reloadRaw();
      final ss = raw['ss'] is List ? raw['ss'] as List : const [];
      final all = ss
          .whereType<Map<String, dynamic>>()
          .map(Subject.fromJson)
          .where((s) => s.title.isNotEmpty)
          .map(_applyOverrides)
          .toList()
        ..sort((a, b) {
          if (a.archived != b.archived) return a.archived ? 1 : -1;
          return a.order.compareTo(b.order);
        });
      // Fresh server state is ground truth: drop overrides the
      // server now agrees with; keep the rest (propagation lag).
      _dropAgreedOverrides(all);
      unawaited(_saveOverrides());
      if (!mounted) return;
      setState(() {
        _subjects = all;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _afterWrite(bool ok) async {
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Could not save that — check connection and try again.')));
      }
      return;
    }
    // Server state is ground truth: refresh the account, then this list.
    await context.read<AppState>().reloadProfile();
    await _load();
  }

  Future<void> _editDialog({Subject? subject}) async {
    final titleCtrl = TextEditingController(text: subject?.title ?? '');
    var color = subject?.colorValue ?? _palette.first;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          backgroundColor: yptCardColor(context),
          title: Text(subject == null ? 'Add subject' : 'Edit subject',
              style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(hintText: 'Subject name'),
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setDialog(() {}),
              ),
              const SizedBox(height: 16),
              Text('Colour',
                  style: TextStyle(fontSize: 12, color: yptGrey500(context))),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _palette)
                    InkWell(
                      onTap: () => setDialog(() => color = c),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: color == c
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: titleCtrl.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) {
      titleCtrl.dispose();
      return;
    }
    final st = context.read<AppState>();
    setState(() => _busy = true);
    final ok = subject == null
        ? await st.api.createSubject(
            title: titleCtrl.text.trim(), colorInt: color)
        : await st.api.editSubject(
            id: subject.id,
            title: titleCtrl.text.trim(),
            colorInt: color,
            archived: subject.archived,
          );
    if (mounted) setState(() => _busy = false);
    titleCtrl.dispose();
    await _afterWrite(ok);
  }

  Future<void> _toggleArchive(Subject s) async {
    final st = context.read<AppState>();
    setState(() => _busy = true);
    final target = !s.archived;
    final ok = await st.api.archiveSubject(id: s.id, archived: target);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      // Record the user's choice so the subject stays archived (or
      // unarchived) even if the reload still shows the old dl flag,
      // and flip it in the list right away — no waiting on reload.
      if (target) {
        _archivedIds.add(s.id);
        _unarchivedIds.remove(s.id);
      } else {
        _unarchivedIds.add(s.id);
        _archivedIds.remove(s.id);
      }
      unawaited(_saveOverrides());
      setState(() {
        _subjects = _subjects
            .map((x) => x.id == s.id ? x.copyWith(archived: target) : x)
            .toList()
          ..sort((a, b) {
            if (a.archived != b.archived) return a.archived ? 1 : -1;
            return a.order.compareTo(b.order);
          });
      });
    }
    await _afterWrite(ok);
  }

  Future<void> _delete(Subject s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yptCardColor(context),
        title: const Text('Delete subject',
            style: TextStyle(fontSize: 16)),
        content: Text('Delete "${s.title}" permanently?',
            style: TextStyle(fontSize: 13, color: yptGrey500(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final st = context.read<AppState>();
    setState(() => _busy = true);
    final ok = await st.api.hardDeleteSubject(s.id);
    if (mounted) setState(() => _busy = false);
    await _afterWrite(ok);
  }

  @override
  Widget build(BuildContext context) {
    final active = _subjects.where((s) => !s.archived).toList();
    final archived = _subjects.where((s) => s.archived).toList();
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('Subjects',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Add subject',
            icon: const Icon(Icons.add, size: 22),
            onPressed: _busy ? null : () => _editDialog(),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Could not load subjects',
                          style: TextStyle(
                              color: yptGrey500(context), fontSize: 12)),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    for (final s in active) _row(s),
                    if (archived.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('Archived',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: yptGrey400(context))),
                      const SizedBox(height: 8),
                      for (final s in archived) _row(s),
                    ],
                    if (_subjects.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Text('No subjects yet.',
                              style: TextStyle(
                                  color: yptGrey500(context), fontSize: 12)),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _row(Subject s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
          color: yptCardColor(context), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(
              width: 11,
              height: 11,
              decoration:
                  BoxDecoration(color: s.color, shape: BoxShape.circle)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: s.archived ? yptGrey500(context) : null)),
                if (s.studyMs > 0)
                  Text('Today ${fmtMs(s.studyMs)}',
                      style:
                          TextStyle(color: yptGrey500(context), fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 19),
            color: yptGrey400(context),
            onPressed: _busy ? null : () => _editDialog(subject: s),
          ),
          IconButton(
            tooltip: s.archived ? 'Unarchive' : 'Archive',
            icon: Icon(
                s.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                size: 19),
            color: yptGrey400(context),
            onPressed: _busy ? null : () => _toggleArchive(s),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline, size: 19),
            color: Colors.redAccent,
            onPressed: _busy ? null : () => _delete(s),
          ),
        ],
      ),
    );
  }
}

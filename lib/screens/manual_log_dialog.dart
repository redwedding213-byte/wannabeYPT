import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../main.dart' show yptCardColor;
import '../models.dart';
import '../ypt_api.dart' show YptApiException;
import 'timer_view.dart' show fmtMs;

/// Manual study record dialog: subject, date, and start/end times.
/// All user-entered, nothing pre-filled. Only time actually studied goes
/// in — writes a real retroactive session to the YPT server via POST /study/add.
class ManualLogDialog extends StatefulWidget {
  final DateTime initialDay;
  final List<Subject> subjects;
  final Subject? initialSubject;

  const ManualLogDialog({
    super.key,
    required this.initialDay,
    required this.subjects,
    this.initialSubject,
  });

  @override
  State<ManualLogDialog> createState() => _ManualLogDialogState();
}

class _ManualLogDialogState extends State<ManualLogDialog> {
  late DateTime _day;
  Subject? _subject;
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = widget.initialDay;
    _day = DateTime(d.year, d.month, d.day);
    _subject = widget.initialSubject;
  }

  DateTime _at(TimeOfDay t) =>
      DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  String? _getValidationError(AppState st) {
    if (_subject == null) return 'Please choose a subject.';
    if (_start == null) return 'Please choose a start time.';
    if (_end == null) return 'Please choose an end time.';

    final startAt = _at(_start!);
    final stopAt = _at(_end!);

    if (!stopAt.isAfter(startAt)) {
      return 'End time must be after start time.';
    }

    final now = DateTime.now();
    if (stopAt.isAfter(now)) {
      return 'Cannot log time in the future.';
    }
    if (startAt.isAfter(now)) {
      return 'Start time cannot be in the future.';
    }

    // Check overlap with active running session
    if (st.studying && st.timerStartedAt != null) {
      final runningStart = st.timerStartedAt!;
      if (startAt.isBefore(now) && stopAt.isAfter(runningStart)) {
        return 'Cannot overlap with your currently running study session.';
      }
    }

    return null;
  }

  bool get _valid => _getValidationError(context.read<AppState>()) == null;

  int? get _ms {
    if (_start == null || _end == null) return null;
    final d = _at(_end!).difference(_at(_start!)).inMilliseconds;
    return d > 0 ? d : null;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day.isAfter(now) ? now : _day,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _day = DateTime(picked.year, picked.month, picked.day);
      _error = null;
    });
  }

  Future<void> _pick(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          (isStart ? _start : _end) ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = picked;
      } else {
        _end = picked;
      }
      _error = null;
    });
  }

  Future<void> _save() async {
    final st = context.read<AppState>();
    final validationError = _getValidationError(st);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ok = await st.logManualStudy(
        subjectTitle: _subject!.title,
        startAt: _at(_start!),
        stopAt: _at(_end!),
      );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _saving = false;
          _error = 'Failed to save manual study session.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e is YptApiException
            ? e.message
            : 'Could not save — check connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final validationMsg = _getValidationError(st);
    final dateLabel = DateFormat('EEE, MMM d, yyyy').format(_day);

    return AlertDialog(
      backgroundColor: yptCardColor(context),
      title: const Text('Log study time', style: TextStyle(fontSize: 16)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: _saving ? null : _pickDate,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 13, color: Colors.grey[400]),
                    const SizedBox(width: 7),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        color: Colors.grey[300],
                        fontSize: 13,
                        decoration: TextDecoration.underline,
                        decorationStyle: TextDecorationStyle.dotted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<Subject>(
              initialValue: _subject,
              hint: const Text('Choose a subject'),
              items: [
                for (final s in widget.subjects)
                  DropdownMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                                color: s.color, shape: BoxShape.circle)),
                        const SizedBox(width: 9),
                        Text(s.title),
                      ],
                    ),
                  ),
              ],
              onChanged: _saving ? null : (v) => setState(() {
                _subject = v;
                _error = null;
              }),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _pick(true),
                    child: Text(_start == null
                        ? 'Start time'
                        : _start!.format(context)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => _pick(false),
                    child: Text(
                        _end == null ? 'End time' : _end!.format(context)),
                  ),
                ),
              ],
            ),
            if (_ms != null) ...[
              const SizedBox(height: 10),
              Text('Duration: ${fmtMs(_ms!)}',
                  style: const TextStyle(fontSize: 12.5)),
            ],
            if (_start != null && _end != null && validationMsg != null) ...[
              const SizedBox(height: 10),
              Text(validationMsg,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            const Text(
              'Enter only time you actually studied. This adds real time to your YPT record.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(color: Colors.redAccent, fontSize: 12)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _valid && !_saving ? _save : null,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }
}

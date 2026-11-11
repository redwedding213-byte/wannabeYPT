import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../models.dart';
import '../main.dart' show kBrand, yptCardColor, yptCard2Color, yptGrey300, yptGrey400, yptGrey500, yptGrey600;
import 'manual_log_dialog.dart';
import 'timer_view.dart' show fmtMs;

/// Statistics in the shape of the official app:
/// Day — a month heatmap; tapping a day opens its detail (totals, max
/// focus, start/end, per-subject split, an hour strip and the session
/// timeline). Week / Month / Trend summarise the same per-day data.
class StatsView extends StatefulWidget {
  const StatsView({super.key});
  @override
  State<StatsView> createState() => _StatsViewState();
}

String fmtHM(int ms) {
  final d = Duration(milliseconds: ms);
  return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';
}

String fmtHMSummary(int ms) {
  final d = Duration(milliseconds: ms);
  if (d.inHours > 0) return '${d.inHours}H ${d.inMinutes % 60}M';
  return '${d.inMinutes}M';
}

String fmtClock(DateTime? t) =>
    t == null ? '—' : DateFormat('a h:mm').format(t);

class _StatsViewState extends State<StatsView> {
  String _period = 'Day';
  DateTime _monthCursor = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _selected = DateTime.now();
  final Map<String, DayDetail> _days = {};
  final Set<String> _failed = {};
  bool _monthLoading = false;
  int _yearCursor = DateTime.now().year;
  Map<String, int> _yearData = {};
  bool _yearLoading = false;
  bool _yearFailed = false;
  int? _ownId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMonth(_monthCursor));
  }

  String _key(DateTime d) => AppState.dateStr(d);

  Future<void> _loadDay(DateTime d, {bool force = false}) async {
    final key = _key(d);
    if (!force && (_days.containsKey(key) || _failed.contains(key))) return;
    try {
      final detail =
          await context.read<AppState>().fetchDay(key, force: force);
      if (!mounted) return;
      setState(() {
        _days[key] = detail;
        _failed.remove(key);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed.add(key));
    }
  }

  Future<void> _loadMonth(DateTime month) async {
    setState(() => _monthLoading = true);
    final now = DateTime.now();
    final last = DateTime(month.year, month.month + 1, 0).day;
    final futs = <Future<void>>[];
    for (var day = 1; day <= last; day++) {
      final d = DateTime(month.year, month.month, day);
      if (d.isAfter(now)) break;
      futs.add(_loadDay(d));
    }
    await Future.wait(futs);
    if (!mounted) return;
    setState(() => _monthLoading = false);
  }

  Future<void> _loadRange(DateTime from, DateTime to) async {
    final futs = <Future<void>>[];
    for (var d = from; !d.isAfter(to); d = d.add(const Duration(days: 1))) {
      futs.add(_loadDay(d));
    }
    await Future.wait(futs);
  }

  int _totalOf(DateTime d) => _days[_key(d)]?.totalMs ?? 0;

  @override
  Widget build(BuildContext context) {
    // Stats stays at a readable width even on wide screens — the
    // month heatmap is a grid, and full width balloons its cells.
    // (Home / To-Do deliberately go full width like the official app.)
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 96),
      children: [
        const Text('Statistics',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'Day', label: Text('Day')),
            ButtonSegment(value: 'Week', label: Text('Week')),
            ButtonSegment(value: 'Month', label: Text('Month')),
            ButtonSegment(value: 'Trend', label: Text('Trend')),
            ButtonSegment(value: 'Year', label: Text('Year')),
          ],
          selected: {_period},
          onSelectionChanged: (s) {
            setState(() => _period = s.first);
            if (_period == 'Week') {
              final sel = _selected;
              final monday = sel.subtract(Duration(days: sel.weekday - 1));
              _loadRange(monday, monday.add(const Duration(days: 6)));
            } else if (_period == 'Trend') {
              final now = DateTime.now();
              _loadRange(now.subtract(const Duration(days: 29)), now);
            } else if (_period == 'Month') {
              _loadMonth(_monthCursor);
            } else if (_period == 'Year') {
              _loadYear(_yearCursor);
            }
          },
        ),
        const SizedBox(height: 16),
        if (_period == 'Day') ..._daySection(),
        if (_period == 'Week') ..._weekSection(),
        if (_period == 'Month') ..._monthSection(),
        if (_period == 'Trend') ..._trendSection(),
        if (_period == 'Year') ..._yearSection(),
          const SizedBox(height: 28),
        ],
        ),
      ),
    );
  }

  // ── Day: month heatmap + selected-day detail ─────────────────────
  List<Widget> _daySection() {
    final month = _monthCursor;
    final monthName = DateFormat('MMMM yyyy').format(month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    var monthTotal = 0;
    for (var i = 1; i <= daysInMonth; i++) {
      monthTotal += _totalOf(DateTime(month.year, month.month, i));
    }
    final now = DateTime.now();
    final canNext =
        month.year < now.year || (month.year == now.year && month.month < now.month);

    final cells = <Widget>[];
    final firstWeekday = DateTime(month.year, month.month, 1).weekday; // Mon=1
    for (var i = 1; i < firstWeekday; i++) {
      cells.add(const SizedBox());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final d = DateTime(month.year, month.month, day);
      final total = _totalOf(d);
      final isFuture = d.isAfter(DateTime(now.year, now.month, now.day));
      final isSelected = _key(d) == _key(_selected);
      final isToday = _key(d) == _key(now);
      final intensity = (total / (10 * 3600 * 1000)).clamp(0.0, 1.0);
      cells.add(InkWell(
        onTap: isFuture
            ? null
            : () {
                setState(() => _selected = d);
                _loadDay(d);
              },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
          decoration: BoxDecoration(
            color: isFuture
                ? Colors.transparent
                : total > 0
                    ? kBrand.withValues(alpha: 0.10 + 0.55 * intensity)
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 1.4)
                : Border.all(color: Colors.transparent, width: 1.4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                      color: isFuture
                          ? Colors.grey[700]
                          : isToday
                              ? kBrand
                              : yptGrey300(context))),
              const SizedBox(height: 1),
              Text(total > 0 ? fmtHM(total) : '',
                  style: TextStyle(fontSize: 9, color: yptGrey400(context))),
            ],
          ),
        ),
      ));
    }

    return [
      Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 20),
            onPressed: () {
              final m = DateTime(month.year, month.month - 1);
              setState(() => _monthCursor = m);
              _loadMonth(m);
            },
          ),
          Expanded(
            child: Text(monthName,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 20),
            onPressed: canNext
                ? () {
                    final m = DateTime(month.year, month.month + 1);
                    setState(() => _monthCursor = m);
                    _loadMonth(m);
                  }
                : null,
          ),
        ],
      ),
      Row(
        children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
            .map((w) => Expanded(
                  child: Center(
                    child: Text(w,
                        style:
                            TextStyle(fontSize: 10.5, color: yptGrey500(context))),
                  ),
                ))
            .toList(),
      ),
      const SizedBox(height: 6),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.05,
        children: cells,
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Text('Less', style: TextStyle(fontSize: 10, color: yptGrey500(context))),
          const SizedBox(width: 5),
          for (final a in [0.10, 0.28, 0.46, 0.65])
            Container(
              width: 11,
              height: 11,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                color: kBrand.withValues(alpha: a),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          Text('More', style: TextStyle(fontSize: 10, color: yptGrey500(context))),
          const Spacer(),
          if (_monthLoading)
            const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.6)),
          const SizedBox(width: 8),
          Text(
              '${DateFormat('MMM').format(month)}: ${fmtHMSummary(monthTotal)}',
              style: TextStyle(fontSize: 11.5, color: yptGrey400(context))),
        ],
      ),
      const SizedBox(height: 20),
      ..._dayDetail(),
    ];
  }

  List<Widget> _dayDetail() {
    final key = _key(_selected);
    final detail = _days[key];
    final title = DateFormat('EEE, MMM d, yyyy').format(_selected);
    if (detail == null) {
      return [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Center(
          child: _failed.contains(key)
              ? Text('Could not load this day',
                  style: TextStyle(color: yptGrey500(context), fontSize: 12))
              : const CircularProgressIndicator(),
        ),
      ];
    }
    final st = context.read<AppState>();
    final subjectMs = <String, int>{};
    detail.subjects.byTitle.forEach((k, v) {
      if (v > 0) subjectMs[k] = (subjectMs[k] ?? 0) + v;
    });
    for (final entry in detail.subjects.byId.entries) {
      final titleForId = st.user?.subjects
          .where((s) => s.id == entry.key)
          .map((s) => s.title)
          .firstOrNull;
      if (titleForId != null &&
          !subjectMs.containsKey(titleForId) &&
          entry.value > 0) {
        subjectMs[titleForId] = entry.value;
      }
    }
    final subjectTotal =
        subjectMs.values.fold(0, (a, b) => a + b);
    final sortedSubjects = subjectMs.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: yptCardColor(context), borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            Row(
              children: [
                _dayStat('Total study time', fmtMs(detail.totalMs)),
                _dayStat('Max focus time', fmtMs(detail.maxMs)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _dayStat('Start time', fmtClock(detail.dayStart)),
                _dayStat('End time', fmtClock(detail.dayEnd)),
              ],
            ),
            if (detail.addedMs > 0 || detail.restMs > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  if (detail.addedMs > 0)
                    _chip('Added ${fmtMs(detail.addedMs)}'),
                  if (detail.restMs > 0) ...[
                    const SizedBox(width: 8),
                    _chip('Rest ${fmtMs(detail.restMs)}'),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        onPressed: _showManualLog,
        icon: const Icon(Icons.add_circle_outline, size: 18),
        label: const Text('Log study time manually'),
        style: OutlinedButton.styleFrom(
          foregroundColor: kBrand,
          side: BorderSide(color: kBrand.withValues(alpha: 0.5)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      if (sortedSubjects.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('By subject',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        const SizedBox(height: 8),
        ...sortedSubjects.map((e) {
          final pct = subjectTotal == 0
              ? 0
              : (e.value * 100 / subjectTotal).round();
          final color = _subjectColor(st, e.key);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                    width: 9,
                    height: 9,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 9),
                SizedBox(
                  width: 130,
                  child: Text(e.key, overflow: TextOverflow.ellipsis),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value:
                          subjectTotal == 0 ? 0 : e.value / subjectTotal,
                      minHeight: 9,
                      backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text('${fmtMs(e.value)} · $pct%',
                    style: TextStyle(
                        color: yptGrey500(context),
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ),
          );
        }),
      ],
      if (detail.sessions.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Text('Timeline',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        const SizedBox(height: 10),
        _hourStrip(detail),
        const SizedBox(height: 12),
        ...detail.sessions.map((s) => _sessionRow(st, s)),
      ] else if (detail.totalMs > 0) ...[
        const SizedBox(height: 14),
        Text('This day has totals, but the server sent no session detail.',
            style: TextStyle(color: yptGrey500(context), fontSize: 12)),
      ],
    ];
  }

  Future<void> _showManualLog() async {
    final st = context.read<AppState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ManualLogDialog(
        initialDay: _selected,
        subjects: st.user?.subjects ?? const <Subject>[],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _days.remove(_key(_selected));
      _failed.remove(_key(_selected));
    });
    await _loadDay(_selected, force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Manual study time logged.')));
  }

  Widget _dayStat(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: kBrand, fontSize: 11)),
          const SizedBox(height: 3),
          Text(value,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
          color: yptCard2Color(context), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(fontSize: 11.5)),
    );
  }

  Color _subjectColor(AppState st, String title) {
    if (title.startsWith('#')) return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);
    final norm = title.trim().toLowerCase();
    for (final s in st.user?.subjects ?? const <Subject>[]) {
      if (s.title.trim().toLowerCase() == norm) return s.color;
    }
    return yptGrey500(context);
  }

  /// 24 hour cells starting 05:00 (the official day grid runs 5 AM–4 AM).
  Widget _hourStrip(DayDetail detail) {
    final cells = <Widget>[];
    for (var i = 0; i < 24; i++) {
      final hour = (5 + i) % 24;
      DaySession? hit;
      for (final s in detail.sessions) {
        final cellStart = DateTime(
            _selected.year, _selected.month, _selected.day, hour);
        final cellEnd = cellStart.add(const Duration(hours: 1));
        if (s.start.isBefore(cellEnd) && s.end.isAfter(cellStart)) {
          hit = s;
          if (s.kind == 'study') break;
        }
      }
      final color = hit == null
          ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05)
          : hit.kind == 'study'
              ? kBrand.withValues(alpha: 0.8)
              : hit.kind == 'rest'
                  ? Colors.blueGrey.withValues(alpha: 0.7)
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.28);
      cells.add(Expanded(
        child: Container(
          height: 15,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: cells),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: ['5 AM', '11 AM', '5 PM', '11 PM', '5 AM']
              .map((t) =>
                  Text(t, style: TextStyle(fontSize: 9, color: yptGrey600(context))))
              .toList(),
        ),
      ],
    );
  }

  Widget _sessionRow(AppState st, DaySession s) {
    final color = s.kind == 'study'
        ? _subjectColor(st, s.subject)
        : s.kind == 'rest'
            ? Colors.blueGrey
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);
    return InkWell(
      onTap: () => _showSession(st, s),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
            color: yptCardColor(context), borderRadius: BorderRadius.circular(10)),
        child: Row(
          children: [
            Container(width: 3.5, height: 34, color: color),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.subject,
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w500)),
                  Text(
                      '${DateFormat('h:mm a').format(s.start)} ~ ${DateFormat('h:mm a').format(s.end)}',
                      style:
                          TextStyle(fontSize: 11, color: yptGrey500(context))),
                ],
              ),
            ),
            Text(fmtMs(s.durationMs),
                style: const TextStyle(
                    fontSize: 12.5,
                    fontFeatures: [FontFeature.tabularFigures()])),
            Icon(Icons.more_vert, size: 16, color: yptGrey500(context)),
          ],
        ),
      ),
    );
  }

  void _showSession(AppState st, DaySession s) {
    showModalBottomSheet(
      context: context,
      backgroundColor: yptCardColor(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.subject,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(
                '${fmtMs(s.durationMs)} · ${DateFormat('h:mm a').format(s.start)} ~ ${DateFormat('h:mm a').format(s.end)}',
                style: TextStyle(color: yptGrey400(context), fontSize: 12.5)),
            const SizedBox(height: 14),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.edit_outlined, size: 20),
              title: const Text('Edit log', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                  'Not available on web — YPT only accepts log edits inside the official app.',
                  style: TextStyle(fontSize: 11.5)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline,
                  size: 20, color: Colors.redAccent),
              title: const Text('Delete log',
                  style: TextStyle(fontSize: 14, color: Colors.redAccent)),
              subtitle: const Text(
                  'Same — delete from the official app.',
                  style: TextStyle(fontSize: 11.5)),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── Week ─────────────────────────────────────────────────────────
  List<Widget> _weekSection() {
    final sel = _selected;
    final monday = DateTime(sel.year, sel.month, sel.day)
        .subtract(Duration(days: sel.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final totals = days.map(_totalOf).toList();
    final maxMs = totals.fold(1, (a, b) => a > b ? a : b);
    final weekTotal = totals.fold(0, (a, b) => a + b);
    final now = DateTime.now();
    final elapsedDays =
        days.where((d) => !d.isAfter(DateTime(now.year, now.month, now.day))).length;
    final avg = elapsedDays == 0 ? 0 : weekTotal ~/ elapsedDays;
    var bestDay = days.first;
    for (final d in days) {
      if (_totalOf(d) > _totalOf(bestDay)) bestDay = d;
    }
    return [
      Text(
          'Week of ${DateFormat('MMM d').format(monday)} – ${DateFormat('MMM d').format(days.last)}',
          style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Column(
                children: [
                  Text(totals[i] > 0 ? fmtHM(totals[i]) : '',
                      style:
                          TextStyle(fontSize: 10, color: yptGrey400(context))),
                  const SizedBox(height: 5),
                  Container(
                    height: 110 * (totals[i] / maxMs),
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: _key(days[i]) == _key(now)
                          ? kBrand
                          : kBrand.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(DateFormat('EEE').format(days[i]),
                      style:
                          TextStyle(fontSize: 10.5, color: yptGrey400(context))),
                  Text(DateFormat('d').format(days[i]),
                      style:
                          TextStyle(fontSize: 10.5, color: yptGrey500(context))),
                ],
              ),
            ),
        ],
      ),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _summaryStat('Week total', fmtMs(weekTotal)),
          _summaryStat('Daily average', fmtMs(avg)),
          _summaryStat(
              'Best day', '${DateFormat('EEE').format(bestDay)} · ${fmtHM(_totalOf(bestDay))}'),
        ],
      ),
    ];
  }

  // ── Month ────────────────────────────────────────────────────────
  List<Widget> _monthSection() {
    final month = _monthCursor;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    var total = 0;
    var activeDays = 0;
    var best = 0;
    DateTime? bestDay;
    final weekTotals = <int>[];
    var runningWeek = 0;
    for (var i = 1; i <= daysInMonth; i++) {
      final d = DateTime(month.year, month.month, i);
      final t = _totalOf(d);
      total += t;
      runningWeek += t;
      if (t > 0) activeDays++;
      if (t > best) {
        best = t;
        bestDay = d;
      }
      if (d.weekday == 7 || i == daysInMonth) {
        weekTotals.add(runningWeek);
        runningWeek = 0;
      }
    }
    return [
      Text(DateFormat('MMMM yyyy').format(month),
          style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _summaryStat('Month total', fmtMs(total)),
          _summaryStat('Days studied', '$activeDays'),
          _summaryStat('Avg / active day',
              activeDays == 0 ? '—' : fmtMs(total ~/ activeDays)),
          _summaryStat('Best day',
              bestDay == null
                  ? '—'
                  : '${DateFormat('MMM d').format(bestDay)} · ${fmtHM(best)}'),
        ],
      ),
      const SizedBox(height: 18),
      const Text('By week',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
      const SizedBox(height: 8),
      for (var i = 0; i < weekTotals.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(width: 70, child: Text('Week ${i + 1}')),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: weekTotals.fold(1, (a, b) => a > b ? a : b) == 0
                        ? 0
                        : weekTotals[i] /
                            weekTotals.fold(1, (a, b) => a > b ? a : b),
                    minHeight: 10,
                    backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation(kBrand),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(fmtHM(weekTotals[i]),
                  style: TextStyle(
                      color: yptGrey500(context),
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      const SizedBox(height: 10),
      Text('Tip: switch to the Day tab and use the month arrows for other months.',
          style: TextStyle(fontSize: 11, color: yptGrey600(context))),
    ];
  }

  // ── Trend ────────────────────────────────────────────────────────
  List<Widget> _trendSection() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days =
        List.generate(30, (i) => today.subtract(Duration(days: 29 - i)));
    final totals = days.map(_totalOf).toList();
    final maxMs = totals.fold(1, (a, b) => a > b ? a : b);
    final sum = totals.fold(0, (a, b) => a + b);
    return [
      const Text('Last 30 days',
          style: TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 30; i++)
            Expanded(
              child: Container(
                height: 8 + 100 * (totals[i] / maxMs),
                margin: const EdgeInsets.symmetric(horizontal: 1.2),
                decoration: BoxDecoration(
                  color: i == 29
                      ? kBrand
                      : kBrand.withValues(alpha: 0.4 + 0.4 * (totals[i] / maxMs)),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 8),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(DateFormat('MMM d').format(days.first),
              style: TextStyle(fontSize: 10.5, color: yptGrey500(context))),
          Text(DateFormat('MMM d').format(days.last),
              style: TextStyle(fontSize: 10.5, color: yptGrey500(context))),
        ],
      ),
      const SizedBox(height: 16),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _summaryStat('30-day total', fmtMs(sum)),
          _summaryStat('Daily average', fmtMs(sum ~/ 30)),
        ],
      ),
    ];
  }

  // ── Year: annual heatmap from /logs/range/days ──────────────────
  Future<void> _loadYear(int year) async {
    if (_yearLoading) return;
    setState(() {
      _yearLoading = true;
      _yearFailed = false;
    });
    try {
      final st = context.read<AppState>();
      var uid = _ownId;
      if (uid == null) {
        final raw = await st.api.reloadRaw();
        uid = _extractOwnId(raw);
        if (uid != null) _ownId = uid;
      }
      if (uid == null) throw Exception('own id not found');
      final now = DateTime.now();
      final end = year >= now.year
          ? DateTime(now.year, now.month, now.day)
          : DateTime(year, 12, 31);
      final data = await st.api.fetchRangeDays(
        userId: uid,
        startDate: '$year-01-01',
        endDate: AppState.dateStr(end),
      );
      if (!mounted) return;
      setState(() {
        _yearData = data;
        _yearLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _yearLoading = false;
        _yearFailed = true;
      });
    }
  }

  int? _extractOwnId(Map<String, dynamic> raw) {
    for (final m in [raw, raw['p']]) {
      if (m is Map<String, dynamic>) {
        for (final key in ['id', 'ud', 'userId', 'user_id']) {
          final v = intOrNull(m[key]);
          if (v != null && v > 0) return v;
        }
      }
    }
    return null;
  }

  List<Widget> _yearSection() {
    final year = _yearCursor;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final canNext = year < now.year;
    final header = Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: () {
            setState(() => _yearCursor = year - 1);
            _loadYear(year - 1);
          },
        ),
        Expanded(
          child: Text('$year',
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: canNext
              ? () {
                  setState(() => _yearCursor = year + 1);
                  _loadYear(year + 1);
                }
              : null,
        ),
      ],
    );
    if (_yearLoading) {
      return [
        header,
        const SizedBox(height: 24),
        const Center(child: CircularProgressIndicator()),
      ];
    }
    if (_yearFailed) {
      return [
        header,
        const SizedBox(height: 24),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load $year',
                  style: TextStyle(color: yptGrey500(context), fontSize: 12)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _loadYear(year),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ];
    }
    // GitHub-style grid: weeks as columns, Mon–Sun rows.
    final jan1 = DateTime(year, 1, 1);
    final dec31 = DateTime(year, 12, 31);
    final end = dec31.isAfter(today) ? today : dec31;
    final start = jan1.subtract(Duration(days: jan1.weekday - 1));
    final weeks = <List<DateTime>>[];
    var cursor = start;
    while (!cursor.isAfter(end)) {
      weeks.add(List.generate(7, (i) => cursor.add(Duration(days: i))));
      cursor = cursor.add(const Duration(days: 7));
    }
    var total = 0;
    var activeDays = 0;
    var best = 0;
    DateTime? bestDay;
    for (final e in _yearData.entries) {
      total += e.value;
      if (e.value > 0) activeDays++;
      if (e.value > best) {
        best = e.value;
        bestDay = DateTime.tryParse(e.key);
      }
    }
    const cell = 12.0;
    const gap = 3.0;
    Widget dayCell(DateTime d) {
      final blank = d.isAfter(end) || d.year != year;
      final ms = blank ? 0 : (_yearData[_key(d)] ?? 0);
      final intensity = (ms / (10 * 3600 * 1000)).clamp(0.0, 1.0);
      return InkWell(
        onTap: blank
            ? null
            : () {
                setState(() {
                  _selected = d;
                  _monthCursor = DateTime(d.year, d.month);
                  _period = 'Day';
                });
                _loadDay(d);
              },
        borderRadius: BorderRadius.circular(3),
        child: Container(
          width: cell,
          height: cell,
          decoration: BoxDecoration(
            color: blank
                ? Colors.transparent
                : ms > 0
                    ? kBrand.withValues(alpha: 0.10 + 0.55 * intensity)
                    : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
    }
    // Month labels: the abbreviation sits on the first week column
    // that contains the 1st of a month.
    final labels = weeks.map((week) {
      String label = '';
      for (final d in week) {
        if (d.year == year && d.day == 1) {
          label = DateFormat('MMM').format(d);
          break;
        }
      }
      return SizedBox(
        width: cell + gap,
        child:
            Text(label, style: TextStyle(fontSize: 9, color: yptGrey500(context))),
      );
    }).toList();
    return [
      header,
      const SizedBox(height: 14),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _summaryStat('Year total', fmtMs(total)),
          _summaryStat('Days studied', '$activeDays'),
          _summaryStat('Best day',
              bestDay == null
                  ? '—'
                  : '${DateFormat('MMM d').format(bestDay)} · ${fmtHM(best)}'),
        ],
      ),
      const SizedBox(height: 16),
      if (_yearData.isEmpty)
        Text('No study data for $year yet.',
            style: TextStyle(fontSize: 12, color: yptGrey500(context)))
      else
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: labels),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final week in weeks)
                    Padding(
                      padding: const EdgeInsets.only(right: gap),
                      child: Column(
                        children: [
                          for (final d in week) ...[
                            dayCell(d),
                            const SizedBox(height: gap),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      const SizedBox(height: 8),
      Text('Tap a day to open its detail.',
          style: TextStyle(fontSize: 11, color: yptGrey600(context))),
    ];
  }

  Widget _summaryStat(String label, String value) {
    return Container(
      width: 148,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
          color: yptCardColor(context), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: yptGrey400(context), fontSize: 11.5)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 16.5,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

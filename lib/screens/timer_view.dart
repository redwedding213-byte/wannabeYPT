import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../main.dart' show kBrand, kCard, kCard2;
import '../models.dart';
import 'books_view.dart';
import 'home_screen.dart' show TabBus;
import 'leaderboards_view.dart';
import 'manual_log_dialog.dart';
import 'notifications_view.dart';
import 'subjects_view.dart';
import 'timetable_view.dart';

String fmt(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  // Official style: no leading zero on the hour (0:05:28, 7:12:38).
  return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}

String fmtMs(int ms) => fmt(Duration(milliseconds: ms));

/// Official YPT style idle/rest counter: under 1m as '10s', under 1h as '45m 57s',
/// longer as h:mm:ss.
String fmtAgo(Duration d) {
  if (d.inHours >= 1) return fmt(d);
  if (d.inMinutes == 0) return '${d.inSeconds}s';
  return '${d.inMinutes}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
}

/// The Home (Timer) screen, mirroring the official YPT app: D-Day chip
/// and date on top, the big thin day total, a text tab strip, flat
/// subject rows with solid play buttons, and an Edit subject pill.
class TimerView extends StatefulWidget {
  const TimerView({super.key});
  @override
  State<TimerView> createState() => _TimerViewState();
}

class _TimerViewState extends State<TimerView> {
  DayDetail? _todayDetail;
  Timer? _ticker;
  bool _wasStudying = false;
  bool _compact = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadToday());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final st = context.read<AppState>();
      if (_wasStudying && !st.studying) {
        // A session just ended: force a fresh fetch so the break
        // counter's "last end" comes from the session that just
        // ended, not the stale cached day detail. The delayed second
        // reload covers the case where this tick fired before the
        // stop call landed on the server.
        _loadToday(force: true);
        Future.delayed(const Duration(seconds: 3), () {
          if (!mounted) return;
          if (!context.read<AppState>().studying) _loadToday(force: true);
        });
      }
      _wasStudying = st.studying;
      if (st.studying || _shouldShowIdleTimer) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime? get _lastEnd {
    final d = _todayDetail;
    if (d == null || d.sessions.isEmpty) return null;
    return d.dayEnd;
  }

  /// Official YPT behaviour: idle/rest counter only displays for the first 3 hours.
  /// After 3 hours of inactivity, it disappears completely leaving a clean clock.
  bool get _shouldShowIdleTimer {
    final end = _lastEnd;
    if (end == null) return false;
    final diff = DateTime.now().difference(end);
    return diff >= Duration.zero && diff < const Duration(hours: 3);
  }

  Future<void> _loadToday({bool force = false}) async {
    try {
      final d = await context
          .read<AppState>()
          .fetchDay(AppState.todayStr(), force: force);
      if (!mounted) return;
      setState(() => _todayDetail = d);
    } catch (_) {}
  }

  /// Slim progress line under the day total once a daily goal is
  /// set — without it the goal was invisible on the Home screen.
  Widget _goalProgress(int liveMs, int goalMinutes) {
    final goalMs = goalMinutes * 60000;
    final frac =
        goalMs == 0 ? 0.0 : (liveMs / goalMs).clamp(0.0, 1.0).toDouble();
    final left = goalMs - liveMs;
    return Column(
      children: [
        Container(
          width: 170,
          height: 3,
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(2)),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: frac,
              child: Container(
                  decoration: BoxDecoration(
                      color: kBrand,
                      borderRadius: BorderRadius.circular(2))),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          left > 0 ? '${fmtMs(left)} to goal' : 'Goal reached',
          style: TextStyle(
              color: Colors.grey[500],
              fontSize: 11,
              fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final user = st.user!;
    final baseMs = st.todayStudyMs;
    final liveMs = baseMs + (st.studying ? st.elapsed.inMilliseconds : 0);
    final active = st.activeSubject;

    return Column(
      children: [
        const SizedBox(height: 10),
        _header(context, st),
        const SizedBox(height: 12),
        // Timer header: the circle shows ONLY while Pomodoro is on
        // (official app: Pomodoro-off homepage has no circle, just
        // the plain big time). The circle is display-only; timing
        // still starts from the subject rows below, as before.
        if (st.pomoOn)
          Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: kBrand),
                child: const Icon(
                    Icons.water_drop,
                    color: Colors.white,
                    size: 40),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TOTAL TODAY',
                        style: TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(fmtMs(liveMs),
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w300,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 16,
                      child: st.studying
                          ? Text(fmtAgo(st.elapsed),
                              style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11.5,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ]))
                          : _shouldShowIdleTimer
                              ? Text(
                                  fmtAgo(
                                      DateTime.now().difference(_lastEnd!)),
                                  style: TextStyle(
                                      color: Colors.grey[500],
                                      fontSize: 11.5,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ]))
                              : const SizedBox(),
                    ),
                    if (st.goalMinutes > 0) ...[
                      const SizedBox(height: 7),
                      _goalProgress(liveMs, st.goalMinutes),
                    ],
                  ],
                ),
              ),
            ],
          ),
        )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(fmtMs(liveMs),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.w300,
                            fontFeatures: [FontFeature.tabularFigures()])),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: "Today's total study time (resets at 5:00 AM)",
                      child: Icon(Icons.help_outline_rounded,
                          size: 15, color: Colors.grey[500]),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                SizedBox(
                  height: 16,
                  child: st.studying
                      ? Text(fmtAgo(st.elapsed),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: Colors.grey[500],
                              fontSize: 11.5,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ]))
                      : _shouldShowIdleTimer
                          ? Text(
                              fmtAgo(
                                  DateTime.now().difference(_lastEnd!)),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 11.5,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ]))
                          : const SizedBox(),
                ),
                if (st.goalMinutes > 0) ...[
                  const SizedBox(height: 7),
                  _goalProgress(liveMs, st.goalMinutes),
                ],
              ],
            ),
          ),
        if (active != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 3),
              decoration: BoxDecoration(
                  color: active.color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16)),
              child: Text(active.title,
                  style: TextStyle(
                      color: active.color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
          ),
        ],
        if (st.timerErrorText != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(st.timerErrorText!,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        ],
        const SizedBox(height: 8),
        _tabStrip(context),
        if (st.pomoNoticeTitle != null) const _PomoNoticeBanner(),
        if (st.pomoOn) const _PomoPanel(),
        const SizedBox(height: 4),
        Expanded(
          child: user.subjects.isEmpty
              ? Center(
                  child: st.profileLoading
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('No subjects loaded',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 13)),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () =>
                                  context.read<AppState>().reloadProfile(),
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('Refresh'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: kBrand,
                                side: BorderSide(
                                    color: kBrand.withValues(alpha: 0.5)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ],
                        ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 96),
                  children: [
                    for (var i = 0; i < user.subjects.length; i++) ...[
                      _SubjectRow(
                          subject: user.subjects[i], compact: _compact),
                      _todayTasks(st, user.subjects[i]),
                      if (i < user.subjects.length - 1)
                        const Divider(
                            height: 1,
                            indent: 60,
                            endIndent: 16,
                            color: Color(0x0DFFFFFF)),
                    ],
                    const SizedBox(height: 18),
                    // Edit subject pill — flows under the rows, like the official app.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: InkWell(
                          onTap: () => _subjectNote(context),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                                color: kCard2,
                                borderRadius: BorderRadius.circular(8)),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.edit_outlined,
                                    size: 13, color: Colors.grey[400]),
                                const SizedBox(width: 6),
                                Text('Edit subject',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[300])),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  // Today's tasks for one subject, nested under its row — the
  // official Home shows them there. Server rows show the true
  // state (done = filled check, half-done = triangle, else empty
  // circle) and tapping the circle opens the same Done/Half-done/
  // Not done menu as the To-Do tab. Local rows stay binary.

  /// Status menu for a server task, in the official app's shape:
  /// menu items use circle-outline = Done, triangle = Half-done,
  /// X = Not done (the current state is bold + brand-coloured).
  /// Menu values are server scores: 3 Done, [kTaskHalfDoneScore]
  /// Half-done, 0 Not done (written as null); a dismissed menu
  /// returns null and changes nothing. Replicated from the
  /// Planner menu (a private method there, not importable).
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
  Widget _todayTasks(AppState st, Subject s) {
    final today = AppState.todayStr();
    final server = (st.user?.tasks ?? const <YptTask>[])
        .where((t) =>
            t.date == today &&
            _titleForSubjectId(st, t.subjectId) == s.title)
        .toList();
    final local =
        st.tasksFor(today).where((t) => t.subject == s.title).toList();
    if (server.isEmpty && local.isEmpty) return const SizedBox.shrink();
    // Server row: true state display + status menu on tap. Local
    // rows below stay binary (local tasks have no half-done state).
    Widget serverRow(YptTask t) {
      final score = st.serverTaskScore(t);
      final isDone = score == 3;
      final isHalf = score == kTaskHalfDoneScore;
      return Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Row(
          children: [
            Builder(
              builder: (iconCtx) => InkWell(
                onTap: () => _showStatusMenu(iconCtx, st, t),
                customBorder: const CircleBorder(),
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: s.color, width: 1.4),
                  ),
                  child: isDone
                      ? Icon(Icons.check, size: 9, color: s.color)
                      : isHalf
                          ? Icon(Icons.change_history,
                              size: 9, color: s.color)
                          : null,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(t.title,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: isDone ? Colors.grey[600] : Colors.grey[400])),
            ),
          ],
        ),
      );
    }

    Widget row(String text, bool done, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Row(
            children: [
              InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: s.color, width: 1.4),
                  ),
                  child: done ? Icon(Icons.check, size: 9, color: s.color) : null,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: done ? Colors.grey[600] : Colors.grey[400])),
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(59, 1, 16, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final t in server) serverRow(t),
          for (final t in local)
            row(t.text, t.done, () => st.toggleTask(t.id)),
        ],
      ),
    );
  }

  String _titleForSubjectId(AppState st, int id) {
    for (final s in st.user?.subjects ?? const <Subject>[]) {
      if (s.id == id) return s.title;
    }
    return '';
  }

  // ── Header: D-Day chip · date · grid icon ────────────────────────
  Widget _header(BuildContext context, AppState st) {
    final now = DateTime.now();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => _editDday(context),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: kCard2, borderRadius: BorderRadius.circular(8)),
                child: Text(_ddayLabel(st),
                    style: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          Center(
            child: Text(
              DateFormat('EEE, M/d').format(now),
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: _compact ? 'Comfortable rows' : 'Compact rows',
                  icon: const Icon(Icons.view_sidebar_outlined, size: 20),
                  color: Colors.grey[300],
                  onPressed: () => setState(() => _compact = !_compact),
                ),
                IconButton(
                  tooltip: 'Features',
                  icon: const Icon(Icons.grid_view, size: 21),
                  color: Colors.grey[300],
                  onPressed: () => _showGridMenu(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _ddayLabel(AppState st) {
    final raw = st.ddayStr;
    if (raw == null) return 'D-Day';
    final d = DateTime.tryParse(raw);
    if (d == null) return 'D-Day';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = target.difference(today).inDays;
    if (diff > 0) return 'D-$diff';
    if (diff == 0) return 'D-Day';
    return 'D+${-diff}';
  }

  // ── Tab strip: Timer · Books · Statistics ────────────────────────
  Widget _tabStrip(BuildContext context) {
    Widget item(String label, bool activeTab, VoidCallback? onTap) {
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      color: activeTab ? Colors.white : Colors.grey[500],
                      fontWeight:
                          activeTab ? FontWeight.w600 : FontWeight.w400)),
              const SizedBox(height: 7),
              Container(
                height: 2,
                width: 28,
                decoration: BoxDecoration(
                  color: activeTab ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.only(bottom: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: Row(
        children: [
          item('Timer', true, null),
          item('Books', false, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BooksPage()),
            );
          }),
          item('Statistics', false, () => TabBus.index.value = 2),
        ],
      ),
    );
  }

  // ── Grid menu (the official app's top-right features popover with liquid glass) ──
  void _showGridMenu(BuildContext context) {
    final st = context.read<AppState>();
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.50),
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) {
          final isPomo = st.pomoOn;
          return Align(
            alignment: Alignment.topRight,
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 44, 16, 16),
              constraints: const BoxConstraints(maxWidth: 370),
              decoration: BoxDecoration(
                color: const Color(0xF21C1C24),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.14),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Material(
                type: MaterialType.transparency,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left column: Main features + Goals
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _gridCategoryTitle('Main features'),
                            _gridItem(
                              Icons.bar_chart_outlined, 'Statistics',
                              () {
                                Navigator.pop(dlgCtx);
                                TabBus.index.value = 2;
                              },
                            ),
                            _gridItem(
                              Icons.star_outline_rounded, 'Rankings',
                              () {
                                Navigator.pop(dlgCtx);
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const LeaderboardsPage(),
                                  ),
                                );
                              },
                            ),
                            _gridItem(
                              isPomo ? Icons.timer : Icons.timer_outlined,
                              'Pomodoro',
                              () {
                                st.setPomoOn(!st.pomoOn);
                                setDlgState(() {});
                              },
                              badge: isPomo ? 'ON' : null,
                            ),
                            _gridItem(
                              Icons.edit_outlined, 'Edit log',
                              () {
                                Navigator.pop(dlgCtx);
                                _showManualLog();
                              },
                            ),
                            const SizedBox(height: 18),
                            _gridCategoryTitle('Goals & Target'),
                            _gridItem(
                              Icons.flag_outlined,
                              'D-Day · ${_ddayLabel(st)}',
                              () {
                                Navigator.pop(dlgCtx);
                                _editDday(context);
                              },
                            ),
                            _gridItem(
                              Icons.track_changes_outlined,
                              st.goalMinutes > 0
                                  ? 'Daily goal (${st.goalMinutes ~/ 60}h)'
                                  : 'Daily goal',
                              () {
                                Navigator.pop(dlgCtx);
                                _editGoal(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Right column: Extra features + More
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _gridCategoryTitle('Extra features'),
                            _gridItem(
                              Icons.menu_book_outlined, 'Books',
                              () {
                                Navigator.pop(dlgCtx);
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const BooksPage(),
                                  ),
                                );
                              },
                            ),
                            _gridItem(
                              Icons.calendar_view_week_outlined,
                              'Timetable',
                              () {
                                Navigator.pop(dlgCtx);
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const TimetablePage(),
                                  ),
                                );
                              },
                            ),
                            _gridItem(
                              Icons.notifications_outlined,
                              'Notifications',
                              () {
                                Navigator.pop(dlgCtx);
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const NotificationsPage(),
                                  ),
                                );
                              },
                            ),
                            _gridItem(
                              Icons.groups_outlined, 'Groups',
                              () {
                                Navigator.pop(dlgCtx);
                                TabBus.index.value = 3;
                              },
                            ),
                            const SizedBox(height: 18),
                            _gridCategoryTitle('More'),
                            _gridItem(
                              Icons.help_outline, 'Help',
                              () {
                                Navigator.pop(dlgCtx);
                                _showHelpDialog(context);
                              },
                            ),
                            _gridItem(
                              Icons.logout_rounded,
                              'Log out',
                              () {
                                Navigator.pop(dlgCtx);
                                st.logout();
                              },
                              color: Colors.redAccent,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _gridCategoryTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _gridItem(IconData icon, String label, VoidCallback onTap,
      {String? badge, Color? color}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color ?? Colors.grey[300]),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  color: color ?? Colors.white,
                  fontWeight: FontWeight.w400,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: kBrand,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('wannabeYPT Help', style: TextStyle(fontSize: 16)),
        content: const Text(
          'wannabeYPT is an unofficial YPT client tailored for laptop/PC study.\n\n'
          '• Timers sync with your YPT account in real time.\n'
          '• Close guard protects your session if you close the tab.\n'
          '• Support / Feedback: Telegram @wannabeypt',
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _subjectNote(BuildContext context) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SubjectsPage()));
  }

  Future<void> _showManualLog() async {
    final st = context.read<AppState>();
    final subjects = st.user?.subjects ?? const <Subject>[];
    if (subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No subjects available to log time to.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ManualLogDialog(
        initialDay: DateTime.now(),
        subjects: subjects,
        initialSubject: st.activeSubject,
      ),
    );
    if (ok == true && mounted) {
      await _loadToday(force: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Study time logged successfully.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _editDday(BuildContext context) async {
    final st = context.read<AppState>();
    final current = st.ddayStr == null ? null : DateTime.tryParse(st.ddayStr!);
    final action = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('D-Day', style: TextStyle(fontSize: 16)),
        content: const Text(
            'A countdown chip for your target date (exam day, for example). Stored on this device only.',
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        actions: [
          if (current != null)
            TextButton(
              onPressed: () => Navigator.pop(context, 'clear'),
              child: const Text('Remove'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'pick'),
            child: Text(current == null ? 'Pick a date' : 'Change date'),
          ),
        ],
      ),
    );
    if (action == 'clear') {
      st.setDday(null);
    } else if (action == 'pick' && context.mounted) {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: current ?? now.add(const Duration(days: 30)),
        firstDate: now.subtract(const Duration(days: 365)),
        lastDate: now.add(const Duration(days: 365 * 3)),
      );
      if (picked != null) st.setDday(picked);
    }
  }

  Future<void> _editGoal(BuildContext context) async {
    final st = context.read<AppState>();
    final hCtl = TextEditingController(
        text: st.goalMinutes > 0 ? '${st.goalMinutes ~/ 60}' : '');
    final mCtl = TextEditingController(
        text: st.goalMinutes > 0 ? '${st.goalMinutes % 60}' : '');
    final result = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Daily goal', style: TextStyle(fontSize: 16)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: hCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Hours'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: mCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
            ),
          ],
        ),
        actions: [
          if (st.goalMinutes > 0)
            TextButton(
              onPressed: () => Navigator.pop(context, -1),
              child: const Text('Remove'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final h = int.tryParse(hCtl.text.trim()) ?? 0;
              final m = int.tryParse(mCtl.text.trim()) ?? 0;
              Navigator.pop(context, h * 60 + m);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == -1) {
      st.setGoalMinutes(0);
    } else if (result != null) {
      st.setGoalMinutes(result);
    }
  }
}

/// One flat subject row: solid colour play button, name, today's time,
/// and a ⋮ — the official app's timer list, no cards.
class _SubjectRow extends StatelessWidget {
  final Subject subject;
  final bool compact;
  const _SubjectRow({required this.subject, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final s = subject;
    final active = st.activeSubject?.id == s.id;
    final disabled = st.timerLoading;
    final today = st.subjectStudyMs(s);
    final liveMs = today + (active ? st.elapsed.inMilliseconds : 0);
    final circle = compact ? 26.0 : 30.0;

    return Opacity(
      opacity: disabled && !active ? 0.55 : 1,
      child: InkWell(
        onTap: disabled
            ? null
            : () {
                final app = context.read<AppState>();
                if (active) {
                  app.stopTimer();
                } else {
                  app.startTimer(s);
                }
              },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 8 : 15),
          child: Row(
            children: [
              Container(
                width: circle,
                height: circle,
                decoration:
                    BoxDecoration(color: s.color, shape: BoxShape.circle),
                child: Icon(
                    active ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: compact ? 15 : 17),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Text(s.title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            active ? FontWeight.bold : FontWeight.w600,
                        color: active ? s.color : null)),
              ),
              Text(fmtMs(liveMs),
                  style: TextStyle(
                      color: active ? s.color : Colors.grey[300],
                      fontWeight: active ? FontWeight.bold : FontWeight.normal,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.more_vert, size: 17, color: Colors.grey[500]),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubjectsPage()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Persistent Pomodoro phase-end banner: the reliable phase-end
/// signal (a system notification may never surface from this webview,
/// and a lone beep is easy to miss). Stays until dismissed, and names
/// the phase that ended plus what comes next.
class _PomoNoticeBanner extends StatelessWidget {
  const _PomoNoticeBanner();

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final title = st.pomoNoticeTitle;
    final body = st.pomoNoticeBody;
    if (title == null || body == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: kBrand.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBrand.withValues(alpha: 0.5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.notifications_active, color: kBrand, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(body, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            InkWell(
              onTap: () => context.read<AppState>().dismissPomoNotice(),
              child: const Icon(Icons.close, size: 18, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pomodoro panel (shown while Pomodoro is on): the live phase
/// countdown plus steppers to edit the focus / break lengths.
class _PomoPanel extends StatelessWidget {
  const _PomoPanel();

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: st.pomoPhase != 'idle'
                ? kBrand.withValues(alpha: 0.4)
                : Colors.white10),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Text('Pomodoro',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              Switch(
                value: st.pomoOn,
                activeThumbColor: kBrand,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => st.setPomoOn(v),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _phaseArea(st),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stepper(context, 'Focus', st.focusMin, 5,
                  (v) => st.setPomoTimes(v, st.breakMin),
                  icon: Icons.notifications_outlined),
              _stepper(context, 'Break', st.breakMin, 1,
                  (v) => st.setPomoTimes(st.focusMin, v),
                  icon: Icons.notifications_outlined),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _stepper(context, 'Long break', st.longBreakMin, 5,
                  (v) => st.setPomoExtras(v, st.cyclesBeforeLong)),
              _stepper(context, 'Cycles', st.cyclesBeforeLong, 1,
                  (v) => st.setPomoExtras(st.longBreakMin, v),
                  min: 2,
                  unit: ''),
            ],
          ),
          const SizedBox(height: 8),
          _cycleDots(st),
          if (st.notifyPerm == 'default' || st.notifyPerm == 'unknown')
            TextButton.icon(
              onPressed: () => context.read<AppState>().enableNotifications(),
              icon: const Icon(Icons.notifications_outlined, size: 16),
              label: const Text('Enable end notifications'),
            )
          else if (st.notifyPerm == 'denied')
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                  'Notifications are blocked in the browser — the banner and beep will still alert you.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  Widget _phaseArea(AppState st) {
    if (st.pomoPhase == 'focus') {
      if (st.pomoOvertime) {
        // Overtime: the focus clock hit zero — count up, study timer
        // keeps running. Circle progress stays at 100 % (value=1).
        return Column(
          children: [
            const Text('OVERTIME',
                style: TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('+${fmt(st.overtimeElapsed)}',
                style: const TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w300,
                    fontFeatures: [FontFeature.tabularFigures()])),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                value: 1.0,
                minHeight: 5,
                backgroundColor: Colors.white10,
                valueColor: AlwaysStoppedAnimation(Colors.orangeAccent),
              ),
            ),
          ],
        );
      }
      final total = st.focusTotal.inMilliseconds;
      final left = st.phaseLeft.inMilliseconds;
      return Column(
        children: [
          const Text('FOCUS',
              style: TextStyle(
                  color: kBrand,
                  fontSize: 11,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(fmt(st.phaseLeft),
              style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w300,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : 1 - left / total,
              minHeight: 5,
              backgroundColor: Colors.white10,
              valueColor: const AlwaysStoppedAnimation(kBrand),
            ),
          ),
        ],
      );
    }
    if (st.pomoPhase == 'break') {
      return Column(
        children: [
          Text(st.pomoBreakLong ? 'LONG BREAK' : 'BREAK',
              style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 11,
                  letterSpacing: 3,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(fmt(st.phaseLeft),
              style: const TextStyle(
                  fontSize: 27,
                  fontWeight: FontWeight.w300,
                  fontFeatures: [FontFeature.tabularFigures()])),
          const Text('Tap a subject to skip the break',
              style: TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      );
    }
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Text('Pomodoro ready — tap a subject to start a focus round',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
    );
  }

  /// Dots for the current set of focus rounds: filled = rounds done
  /// (a running long break shows the set complete). Cycles reset when
  /// Pomodoro is turned off or a long break ends.
  Widget _cycleDots(AppState st) {
    final n = st.cyclesBeforeLong;
    final filled = st.pomoBreakLong ? n : st.pomoCycles % n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < n; i++)
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? kBrand : Colors.white24,
            ),
          ),
        const SizedBox(width: 8),
        Text('$filled/$n rounds done',
            style: TextStyle(fontSize: 11, color: Colors.grey[400])),
      ],
    );
  }

  Widget _stepper(BuildContext context, String label, int value, int step,
      void Function(int) onChange,
      {int min = 1,
      String unit = 'min',
      IconData? icon}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 13, color: Colors.grey),
          const SizedBox(width: 3),
        ],
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove_circle_outline, size: 19),
          onPressed: value - step >= min ? () => onChange(value - step) : null,
        ),
        SizedBox(
          width: 52,
          child: Text(unit.isEmpty ? '$value' : '$value $unit',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 13, fontFeatures: [FontFeature.tabularFigures()])),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add_circle_outline, size: 19),
          onPressed: () => onChange(value + step),
        ),
      ],
    );
  }
}

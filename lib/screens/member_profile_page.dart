// wannabeYPT — member profile side panel
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

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../main.dart' show kBrand, kCard, kBg;
import '../models.dart';
import 'timer_view.dart' show fmtMs;

/// Opens a member's profile as a panel sliding in from the right
/// (web-style), instead of pushing a whole new page.
Future<void> showMemberProfile(
  BuildContext context, {
  required GroupMember member,
  required int groupId,
  required bool isMe,
}) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Member profile',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, __) {
      final w = MediaQuery.of(dialogContext).size.width;
      return Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: math.min(430, w),
          height: double.infinity,
          child: MemberProfilePanel(
              member: member, groupId: groupId, isMe: isMe),
        ),
      );
    },
    transitionBuilder: (_, anim, __, child) {
      final curved =
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(curved),
        child: child,
      );
    },
  );
}

/// A group member's profile, like the official app opens on tap:
/// header, today's time, and their study pattern. Full day detail
/// (month heatmap, subject split) exists only for your own profile —
/// the API serves day logs for the signed-in user only. Other members
/// get today + this week's per-day totals.
///
/// Data note: the per-day ranks route silently leaves some members
/// out (seen live: a member with 3:21 today got an empty week), so
/// today's bar is seeded from the member's own room data and the week
/// total is cross-checked against the week-aggregate call.
class MemberProfilePanel extends StatefulWidget {
  final GroupMember member;
  final int groupId;
  final bool isMe;
  const MemberProfilePanel({
    super.key,
    required this.member,
    required this.groupId,
    required this.isMe,
  });
  @override
  State<MemberProfilePanel> createState() => _MemberProfilePanelState();
}

class _MemberProfilePanelState extends State<MemberProfilePanel> {
  Timer? _ticker;
  final Map<String, int> _weekMs = {};
  int _weekAggregate = 0;
  bool _weekLoading = true;
  final Map<String, DayDetail> _days = {};
  bool _monthLoading = false;
  DateTime _selected = DateTime.now();
  bool _shaking = false;

  GroupMember get m => widget.member;

  @override
  void initState() {
    super.initState();
    if (m.isLive) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
    if (widget.isMe) {
      _loadMonth();
    } else {
      _loadWeek();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// A shake is a nudge to another person, so it always asks first.
  /// Success and failure both show the server's real answer — a
  /// rejection surfaces its `m` message instead of a generic error.
  Future<void> _confirmShake(BuildContext context) async {
    // Capture these before the awaits: using `context` across an
    // async gap is what the linter flags, and the State's `mounted`
    // does not guard it.
    final api = context.read<AppState>().api;
    final from = context.read<AppState>().user?.nickname ?? '';
    final messenger = ScaffoldMessenger.of(context);
    final send = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: kCard,
        title: Text('Shake ${m.nickname}?'),
        content: const Text(
            'They will get a nudge to get back to studying.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child:
                Text('Cancel', style: TextStyle(color: Colors.grey[400])),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Shake', style: TextStyle(color: kBrand)),
          ),
        ],
      ),
    );
    if (send != true || !mounted) return;
    setState(() => _shaking = true);
    try {
      await api.shakeMember(
          groupId: widget.groupId, targetUserId: m.userId, from: from);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
            content: Text('Shake sent to ${m.nickname}!'),
            backgroundColor: kBrand),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _shaking = false);
    }
  }

  bool _isMember(GroupMember r) =>
      (m.userId != 0 && r.userId == m.userId) || r.nickname == m.nickname;

  Future<void> _loadWeek() async {
    try {
      final st = context.read<AppState>();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monday = today.subtract(Duration(days: today.weekday - 1));
      for (var d = monday;
          !d.isAfter(today);
          d = d.add(const Duration(days: 1))) {
        final ranks =
            await st.fetchGroupRanks(widget.groupId, AppState.dateStr(d), 'day');
        for (final r in ranks) {
          if (_isMember(r)) _weekMs[AppState.dateStr(d)] = r.studyMs;
        }
      }
      // Week aggregate (Monday-anchored) as the total's ground truth.
      final week = await st.fetchGroupRanks(
          widget.groupId, AppState.dateStr(monday), 'week');
      for (final r in week) {
        if (_isMember(r)) _weekAggregate = r.studyMs;
      }
      // Seed today from the member object itself — the ranks route
      // cannot be trusted to include everyone.
      final todayKey = AppState.dateStr(today);
      final displayToday = m.liveDisplayMs(now);
      if (displayToday > (_weekMs[todayKey] ?? 0)) {
        _weekMs[todayKey] = displayToday;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _weekLoading = false);
  }

  Future<void> _loadMonth() async {
    setState(() => _monthLoading = true);
    try {
      final st = context.read<AppState>();
      final now = DateTime.now();
      final last = DateTime(now.year, now.month + 1, 0).day;
      final futs = <Future<void>>[];
      for (var day = 1; day <= last; day++) {
        final d = DateTime(now.year, now.month, day);
        if (d.isAfter(now)) break;
        futs.add(() async {
          try {
            _days[AppState.dateStr(d)] =
                await st.fetchDay(AppState.dateStr(d));
          } catch (_) {}
        }());
      }
      await Future.wait(futs);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _monthLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final live = m.isLive;
    final displayMs = m.liveDisplayMs(DateTime.now());
    return Material(
      color: kBg,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 10, 10, 0),
              child: IconButton(
                icon: Icon(Icons.close, size: 20, color: Colors.grey[400]),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 40),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 64,
                      height: 48,
                      child: live
                          ? const Icon(Icons.stay_current_portrait,
                              color: kBrand, size: 42)
                          : CustomPaint(
                              size: const Size(64, 48),
                              painter: _DeskGlyphPainter(),
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.nickname,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(
                              m.category.isNotEmpty
                                  ? m.category
                                  : 'YPT member',
                              style: TextStyle(
                                  color: Colors.grey[500], fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    if (live) ...[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: kBrand, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      const Text('Studying now',
                          style: TextStyle(
                              color: kBrand,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 14),
                    ] else
                      Text('Today',
                          style:
                              TextStyle(color: Colors.grey[400], fontSize: 13)),
                    Text(fmtMs(displayMs),
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: live ? kBrand : Colors.grey[200],
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                  ],
                ),
                const SizedBox(height: 26),
                if (!widget.isMe) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _shaking ? null : () => _confirmShake(context),
                      icon: const Icon(Icons.notifications_active_outlined,
                          size: 17),
                      label: Text(_shaking ? 'Sending…' : 'Shake ${m.nickname}'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kBrand,
                        side:
                            BorderSide(color: kBrand.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                ],
                if (widget.isMe) ..._selfSections() else ..._otherSections(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Someone else: this week's per-day totals ─────────────────────
  List<Widget> _otherSections() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final maxMs = _weekMs.values.fold(0, (a, b) => b > a ? b : a);
    final perDayTotal = _weekMs.values.fold(0, (a, b) => a + b);
    final weekTotal =
        perDayTotal > _weekAggregate ? perDayTotal : _weekAggregate;
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return [
      const Text('This week',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      if (_weekLoading)
        const Center(
            child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator()))
      else ...[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(
                  children: [
                    Text(
                        _weekMs[AppState.dateStr(days[i])] != null &&
                                _weekMs[AppState.dateStr(days[i])]! > 0
                            ? _fmtHM(_weekMs[AppState.dateStr(days[i])]!)
                            : '',
                        style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 11,
                            fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                    const SizedBox(height: 5),
                    Container(
                      width: 30,
                      height: 8 +
                          74 *
                              ((_weekMs[AppState.dateStr(days[i])] ?? 0) /
                                  (maxMs == 0 ? 1 : maxMs)),
                      decoration: BoxDecoration(
                        color: days[i].isAfter(today)
                            ? Colors.white.withValues(alpha: 0.05)
                            : kBrand.withValues(
                                alpha: _weekMs[AppState.dateStr(days[i])] ==
                                        null
                                    ? 0.12
                                    : 0.85),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(labels[i],
                        style: TextStyle(
                            color: days[i] == today
                                ? Colors.white
                                : Colors.grey[500],
                            fontSize: 11.5,
                            fontWeight: days[i] == today
                                ? FontWeight.w700
                                : FontWeight.w400)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Week total ${_fmtHM(weekTotal)}',
            style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        const SizedBox(height: 22),
        Text('Full history for other members is only in the official app.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12)),
      ],
    ];
  }

  // ── Yourself: month heatmap + selected day detail ────────────────
  List<Widget> _selfSections() {
    final now = DateTime.now();
    final monthName = DateFormat('MMMM yyyy').format(now);
    final sel = _days[AppState.dateStr(_selected)];
    return [
      Row(
        children: [
          const Text('Focus time',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text(monthName,
              style: TextStyle(color: Colors.grey[400], fontSize: 13)),
        ],
      ),
      const SizedBox(height: 12),
      if (_monthLoading && _days.isEmpty)
        const Center(
            child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator()))
      else
        _heatmap(now),
      const SizedBox(height: 22),
      if (sel != null) ...[
        Text(DateFormat('EEE, MMM d').format(_selected),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        _dayCard(sel),
        ..._subjectSplit(sel),
      ] else if (!_monthLoading)
        Text('No study recorded on this day.',
            style: TextStyle(color: Colors.grey[500], fontSize: 13)),
    ];
  }

  Widget _heatmap(DateTime now) {
    final first = DateTime(now.year, now.month, 1);
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final offset = first.weekday - 1; // Monday-first
    var maxMs = 0;
    for (final d in _days.values) {
      if (d.totalMs > maxMs) maxMs = d.totalMs;
    }
    final cells = <Widget>[];
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    for (final l in labels) {
      cells.add(Center(
          child: Text(l,
              style: TextStyle(color: Colors.grey[500], fontSize: 11))));
    }
    for (var i = 0; i < offset; i++) {
      cells.add(const SizedBox());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final d = DateTime(now.year, now.month, day);
      final detail = _days[AppState.dateStr(d)];
      final ms = detail?.totalMs ?? 0;
      final future = d.isAfter(DateTime(now.year, now.month, now.day));
      final selected = d.year == _selected.year &&
          d.month == _selected.month &&
          d.day == _selected.day;
      final frac = maxMs == 0 ? 0.0 : ms / maxMs;
      cells.add(GestureDetector(
        onTap: future ? null : () => setState(() => _selected = d),
        child: Container(
          decoration: BoxDecoration(
            color: future
                ? Colors.transparent
                : ms > 0
                    ? kBrand.withValues(alpha: 0.18 + 0.62 * frac)
                    : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(6),
            border: selected
                ? Border.all(color: Colors.white, width: 1.4)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$day',
                  style: TextStyle(
                      color: future ? Colors.grey[700] : Colors.grey[300],
                      fontSize: 11.5,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w400)),
              if (ms > 0) ...[
                const SizedBox(height: 2),
                Text(_fmtHM(ms),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontFeatures: [FontFeature.tabularFigures()])),
              ],
            ],
          ),
        ),
      ));
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 5,
      crossAxisSpacing: 5,
      childAspectRatio: 1.05,
      children: cells,
    );
  }

  Widget _dayCard(DayDetail d) {
    String hm(DateTime? t) =>
        t == null ? '—' : DateFormat('hh:mm a').format(t);
    Widget cell(String label, String value) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(color: kBrand, fontSize: 12)),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ],
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: kCard, borderRadius: BorderRadius.circular(14)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: cell('Total study time', fmtMs(d.totalMs))),
              Expanded(child: cell('Max focus time', fmtMs(d.maxMs))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: cell('Start time', hm(d.dayStart))),
              Expanded(child: cell('End time', hm(d.dayEnd))),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _subjectSplit(DayDetail d) {
    final st = context.read<AppState>();
    final titleById = <int, String>{
      for (final s in st.user?.subjects ?? const <Subject>[])
        if (s.id > 0) s.id: s.title,
    };
    final colorByTitle = <String, Color>{
      for (final s in st.user?.subjects ?? const <Subject>[]) s.title: s.color,
    };
    final merged = <String, int>{};
    d.subjects.byTitle.forEach((k, v) {
      if (v > 0) merged[k] = (merged[k] ?? 0) + v;
    });
    d.subjects.byId.forEach((k, v) {
      if (v <= 0) return;
      final t = titleById[k];
      if (t != null && !merged.containsKey(t)) merged[t] = v;
    });
    if (merged.isEmpty) return const [];
    final entries = merged.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold(0, (a, e) => a + e.value);
    const palette = [
      Color(0xFFE91E63),
      Color(0xFF2196F3),
      Color(0xFF9C27B0),
      Color(0xFFFF9800),
      Color(0xFF4CAF50),
      Color(0xFF00BCD4),
    ];
    Color colorFor(int i, String title) =>
        colorByTitle[title] ?? palette[i % palette.length];
    return [
      const SizedBox(height: 22),
      Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(128, 128),
            painter: _DonutPainter([
              for (var i = 0; i < entries.length; i++)
                (entries[i].value / total, colorFor(i, entries[i].key)),
            ]),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                                color: colorFor(i, entries[i].key),
                                shape: BoxShape.circle)),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(entries[i].key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13.5)),
                        ),
                        Text(
                            '${_fmtHM(entries[i].value)} · ${(entries[i].value / total * 100).round()}%',
                            style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 12.5,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ])),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ];
  }
}

String _fmtHM(int ms) {
  final d = Duration(milliseconds: ms);
  return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';
}

class _DonutPainter extends CustomPainter {
  final List<(double, Color)> slices;
  const _DonutPainter(this.slices);
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;
    var start = -math.pi / 2;
    for (final (frac, color) in slices) {
      final sweep = frac * math.pi * 2;
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 24;
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius),
          start, sweep, false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) => true;
}

/// The official app's idle desk + lamp glyph.
class _DeskGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF7A7A82)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final w = size.width;
    final h = size.height;
    final deskY = h * 0.70;
    canvas.drawLine(Offset(w * 0.08, deskY), Offset(w * 0.92, deskY), p);
    canvas.drawLine(Offset(w * 0.16, deskY), Offset(w * 0.16, h * 0.95), p);
    canvas.drawLine(Offset(w * 0.84, deskY), Offset(w * 0.84, h * 0.95), p);
    canvas.drawLine(Offset(w * 0.64, deskY), Offset(w * 0.82, deskY), p);
    canvas.drawLine(Offset(w * 0.73, deskY), Offset(w * 0.73, h * 0.38), p);
    final shade = Path()
      ..moveTo(w * 0.60, h * 0.38)
      ..lineTo(w * 0.86, h * 0.38)
      ..lineTo(w * 0.79, h * 0.18)
      ..lineTo(w * 0.67, h * 0.18)
      ..close();
    canvas.drawPath(shade, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

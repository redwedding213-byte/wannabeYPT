import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../main.dart' show kBrand, yptCard2Color, yptGrey300, yptGrey400, yptGrey500;
import '../models.dart';
import 'home_screen.dart' show TabBus;
import 'leaderboards_view.dart';
import 'manual_log_dialog.dart';
import 'notifications_view.dart';
import 'subjects_view.dart';
import 'timetable_view.dart';

/// Red analog Pomodoro dial clock face (YPT 1:1 fidelity, Screenshot 3).
class PomodoroDialWidget extends StatelessWidget {
  final Duration elapsed;
  final Duration phaseLeft;
  final int focusMinutes;
  final double size;

  const PomodoroDialWidget({
    super.key,
    required this.elapsed,
    required this.phaseLeft,
    this.focusMinutes = 50,
    this.size = 72,
  });

  @override
  Widget build(BuildContext context) {
    // Total focus duration in seconds
    final totalSec = focusMinutes * 60;
    final leftSec = phaseLeft.inSeconds.clamp(0, totalSec);
    final fraction = totalSec > 0 ? (leftSec / totalSec) : 0.0;

    return CustomPaint(
      size: Size(size, size),
      painter: _PomodoroDialPainter(
        fraction: fraction,
        targetMinutes: focusMinutes,
        foreground: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _PomodoroDialPainter extends CustomPainter {
  final double fraction; // 1.0 (full) down to 0.0 (done)
  final int targetMinutes;
  final Color foreground; // onSurface: needle/ticks stay visible in both themes

  _PomodoroDialPainter({
    required this.fraction,
    required this.targetMinutes,
    required this.foreground,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final r = math.min(size.width, size.height) / 2;

    // Outer circle ticks (60 minute markers)
    final tickPaint = Paint()
      ..color = foreground.withValues(alpha: 0.4)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final majorTickPaint = Paint()
      ..color = foreground.withValues(alpha: 0.85)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < 60; i++) {
      final angle = (i * 6 - 90) * math.pi / 180;
      final isMajor = i % 5 == 0;
      final startR = isMajor ? r * 0.84 : r * 0.90;
      final endR = r * 0.96;
      final p1 = Offset(center.dx + startR * math.cos(angle),
          center.dy + startR * math.sin(angle));
      final p2 = Offset(center.dx + endR * math.cos(angle),
          center.dy + endR * math.sin(angle));
      canvas.drawLine(p1, p2, isMajor ? majorTickPaint : tickPaint);
    }

    // Numbers 5, 10, ..., 60
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (var m = 5; m <= 60; m += 5) {
      final angle = (m * 6 - 90) * math.pi / 180;
      final numR = r * 0.72;
      final pos = Offset(center.dx + numR * math.cos(angle),
          center.dy + numR * math.sin(angle));
      textPainter.text = TextSpan(
        text: '$m',
        style: TextStyle(
          color: foreground.withValues(alpha: 0.65),
          fontSize: size.width > 70 ? 7.5 : 6.5,
          fontWeight: FontWeight.w600,
        ),
      );
      textPainter.layout();
      textPainter.paint(
          canvas,
          Offset(pos.dx - textPainter.width / 2,
              pos.dy - textPainter.height / 2));
    }

    // Red sector (the Pomodoro slice from 12 o'clock clockwise to remaining minute mark)
    final sweepAngle = (fraction * targetMinutes / 60) * 2 * math.pi;
    if (sweepAngle > 0.01) {
      final redPaint = Paint()
        ..color = const Color(0xFFE84D3D)
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: r * 0.66),
        -math.pi / 2,
        sweepAngle,
        true,
        redPaint,
      );
    }

    // Center pivot & pointer hand pointing to current fraction
    final needleAngle = -math.pi / 2 + sweepAngle;
    final needlePaint = Paint()
      ..color = foreground
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final handTip = Offset(center.dx + (r * 0.68) * math.cos(needleAngle),
        center.dy + (r * 0.68) * math.sin(needleAngle));
    canvas.drawLine(center, handTip, needlePaint);

    final hubPaint = Paint()..color = const Color(0xFF1E1E26);
    canvas.drawCircle(center, 3.5, hubPaint);
    final hubBorder = Paint()
      ..color = foreground
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, 3.5, hubBorder);
  }

  @override
  bool shouldRepaint(covariant _PomodoroDialPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.targetMinutes != targetMinutes;
}

/// Authentic YPT desk vector line art with student and study glow (Screenshot 1, 2, 3).
class YptDeskWidget extends StatelessWidget {
  final bool studying;
  final bool hasStudied;
  final double width;
  final double height;

  const YptDeskWidget({
    super.key,
    required this.studying,
    this.hasStudied = false,
    this.width = 44,
    this.height = 32,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(width, height),
      painter: _YptDeskVectorPainter(
        studying: studying,
        hasStudied: hasStudied,
      ),
    );
  }
}

class _YptDeskVectorPainter extends CustomPainter {
  final bool studying;
  final bool hasStudied;

  _YptDeskVectorPainter({required this.studying, required this.hasStudied});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final deskY = h * 0.72;

    final strokeColor = studying ? kBrand : const Color(0xFF7A7A82);
    final p = Paint()
      ..color = strokeColor
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // 1. Desk top
    canvas.drawLine(Offset(w * 0.08, deskY), Offset(w * 0.92, deskY), p);

    // 2. Desk legs
    canvas.drawLine(Offset(w * 0.16, deskY), Offset(w * 0.16, h * 0.96), p);
    canvas.drawLine(Offset(w * 0.84, deskY), Offset(w * 0.84, h * 0.96), p);

    // 3. Desk reading lamp (on right)
    canvas.drawLine(Offset(w * 0.64, deskY), Offset(w * 0.82, deskY), p);
    canvas.drawLine(Offset(w * 0.73, deskY), Offset(w * 0.73, h * 0.38), p);

    final shade = Path()
      ..moveTo(w * 0.60, h * 0.38)
      ..lineTo(w * 0.86, h * 0.38)
      ..lineTo(w * 0.79, h * 0.18)
      ..lineTo(w * 0.67, h * 0.18)
      ..close();
    canvas.drawPath(shade, p);

    if (studying) {
      // 4. Seated student
      final headCenter = Offset(w * 0.35, h * 0.36);
      canvas.drawCircle(headCenter, h * 0.13, p);

      // Torso & leaning arm
      canvas.drawLine(Offset(w * 0.35, h * 0.49), Offset(w * 0.35, deskY), p);
      canvas.drawLine(Offset(w * 0.35, h * 0.54), Offset(w * 0.52, deskY), p);

      // 5. Radio study glow arcs (two concentric waves above & to left of head)
      final wavePaint = Paint()
        ..color = kBrand
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      canvas.drawArc(
        Rect.fromCircle(center: headCenter, radius: h * 0.22),
        -math.pi * 0.75,
        math.pi * 0.50,
        false,
        wavePaint,
      );
      canvas.drawArc(
        Rect.fromCircle(center: headCenter, radius: h * 0.33),
        -math.pi * 0.75,
        math.pi * 0.50,
        false,
        wavePaint,
      );
    } else if (hasStudied) {
      // Clock badge (🕒) above the desk indicating break / resting
      final clockCenter = Offset(w * 0.28, h * 0.34);
      final clockR = h * 0.16;

      final clockPaint = Paint()
        ..color = const Color(0xFF8E8E93)
        ..strokeWidth = 1.4
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(clockCenter, clockR, clockPaint);
      canvas.drawLine(clockCenter,
          Offset(clockCenter.dx, clockCenter.dy - clockR * 0.65), clockPaint);
      canvas.drawLine(clockCenter,
          Offset(clockCenter.dx + clockR * 0.60, clockCenter.dy), clockPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _YptDeskVectorPainter oldDelegate) =>
      oldDelegate.studying != studying || oldDelegate.hasStudied != hasStudied;
}

/// Break log dialog popup (YPT 1:1 fidelity, Screenshot 2).
class BreakLogDialog extends StatefulWidget {
  final Duration duration;
  final VoidCallback onStop;

  const BreakLogDialog({
    super.key,
    required this.duration,
    required this.onStop,
  });

  static Future<void> show(BuildContext context,
      {required Duration duration, required VoidCallback onStop}) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (_) => BreakLogDialog(duration: duration, onStop: onStop),
    );
  }

  @override
  State<BreakLogDialog> createState() => _BreakLogDialogState();
}

class _BreakLogDialogState extends State<BreakLogDialog> {
  final List<String> _tags = const [
    '#meals',
    '#bathroom',
    '#rest',
    '#other',
    '#distractionop',
    '#break',
  ];
  String? _selectedTag;

  String _fmtBreak(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes % 60}m ${d.inSeconds % 60}s';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: const Color(0xF21C1C24),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.16),
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
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Break log ${_fmtBreak(widget.duration)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Record your break reason',
                    child: Icon(Icons.help_outline,
                        size: 15, color: yptGrey500(context)),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 2-column grid of tags
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _tags.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 3.2,
                ),
                itemBuilder: (_, i) {
                  final tag = _tags[i];
                  final isSel = _selectedTag == tag;
                  return InkWell(
                    onTap: () {
                      setState(() => _selectedTag = tag);
                      Navigator.of(context).pop();
                      widget.onStop();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSel
                            ? kBrand.withValues(alpha: 0.25)
                            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSel ? kBrand : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              isSel ? FontWeight.bold : FontWeight.w500,
                          color: isSel ? kBrand : yptGrey300(context),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

              // Footer: Edit tags & No log
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Tag customization coming soon!')),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: yptGrey400(context),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                    child: const Text('Edit tags',
                        style: TextStyle(fontSize: 12.5)),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onStop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('No log',
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating study bottom dock (Screenshot 2, 3).
class StudyBottomDock extends StatelessWidget {
  final VoidCallback? onHome;
  const StudyBottomDock({super.key, this.onHome});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xF21C1C24),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.16),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dockItem(
              context,
              icon: Icons.home,
              label: 'Home',
              onTap: onHome ?? () => TabBus.index.value = 0,
            ),
            _dockItem(
              context,
              icon: Icons.check_box_outlined,
              label: 'To-Do',
              onTap: () {
                onHome?.call();
                TabBus.index.value = 1;
              },
            ),
            _dockItem(
              context,
              icon: Icons.calendar_today_outlined,
              label: 'Calendar',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const TimetablePage()),
                );
              },
            ),
            _dockItem(
              context,
              icon: Icons.menu_book_outlined,
              label: 'Books',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SubjectsPage()),
                );
              },
            ),
            Container(
              height: 20,
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
            ),
            InkWell(
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    backgroundColor: yptCard2Color(context),
                    title: const Text('Study Mode',
                        style: TextStyle(fontSize: 16)),
                    content: Text(
                      '• Active session syncs live with YPT servers.\n'
                      '• Tap the pause icon to take a break and log your tag.\n'
                      '• Use the swap icon at the top to change subject.',
                      style: TextStyle(fontSize: 13, color: yptGrey500(context)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Got it'),
                      ),
                    ],
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                child: Icon(Icons.help_outline,
                    size: 17, color: yptGrey500(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dockItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: yptGrey300(context)),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: yptGrey400(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String yptDdayLabel(AppState st) {
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

void showYptFeaturesMenu(BuildContext context) {
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
            margin: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            constraints: const BoxConstraints(maxWidth: 360),
            decoration: BoxDecoration(
              color: const Color(0xF21C1C24),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.16),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left column: Main features + Goals
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _yptCategoryTitle(context, 'Main features'),
                          _yptMenuItem(
                            dlgCtx,
                            Icons.bar_chart_outlined,
                            'Statistics',
                            () {
                              Navigator.pop(dlgCtx);
                              TabBus.index.value = 2;
                            },
                          ),
                          _yptMenuItem(
                            dlgCtx,
                            Icons.star_outline_rounded,
                            'Rankings',
                            () {
                              Navigator.pop(dlgCtx);
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const LeaderboardsPage(),
                                ),
                              );
                            },
                          ),
                          _yptMenuItem(
                            dlgCtx,
                            isPomo ? Icons.timer : Icons.timer_outlined,
                            'Pomodoro',
                            () {
                              st.setPomoOn(!st.pomoOn);
                              setDlgState(() {});
                            },
                            badge: isPomo ? 'ON' : null,
                          ),
                          _yptMenuItem(
                            dlgCtx,
                            Icons.edit_outlined,
                            'Edit log',
                            () {
                              Navigator.pop(dlgCtx);
                              _yptManualLog(context);
                            },
                          ),
                          const SizedBox(height: 18),
                          _yptCategoryTitle(context, 'Goals & Target'),
                          _yptMenuItem(
                            dlgCtx,
                            Icons.flag_outlined,
                            'D-Day · ${yptDdayLabel(st)}',
                            () {
                              Navigator.pop(dlgCtx);
                              _yptEditDday(context, st);
                            },
                          ),
                          _yptMenuItem(
                            dlgCtx,
                            Icons.track_changes_outlined,
                            st.goalMinutes > 0
                                ? 'Daily goal (${st.goalMinutes ~/ 60}h)'
                                : 'Daily goal',
                            () {
                              Navigator.pop(dlgCtx);
                              _yptEditGoal(context, st);
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
                          _yptCategoryTitle(context, 'Extra features'),
                          _yptMenuItem(
                            dlgCtx,
                            Icons.menu_book_outlined,
                            'Books',
                            () {
                              Navigator.pop(dlgCtx);
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const SubjectsPage(),
                                ),
                              );
                            },
                          ),
                          _yptMenuItem(
                            dlgCtx,
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
                          _yptMenuItem(
                            dlgCtx,
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
                          _yptMenuItem(
                            dlgCtx,
                            Icons.groups_outlined,
                            'Groups',
                            () {
                              Navigator.pop(dlgCtx);
                              TabBus.index.value = 3;
                            },
                          ),
                          const SizedBox(height: 18),
                          _yptCategoryTitle(context, 'More'),
                          _yptMenuItem(
                            dlgCtx,
                            Icons.help_outline,
                            'Help',
                            () {
                              Navigator.pop(dlgCtx);
                              _yptHelpDialog(context);
                            },
                          ),
                          _yptMenuItem(
                            dlgCtx,
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

Widget _yptCategoryTitle(BuildContext context, String title) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: yptGrey500(context),
        letterSpacing: 0.3,
      ),
    ),
  );
}

Widget _yptMenuItem(BuildContext context, IconData icon, String label,
    VoidCallback onTap,
    {String? badge, Color? color}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color ?? yptGrey300(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: color ?? Theme.of(context).colorScheme.onSurface,
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

Future<void> _yptManualLog(BuildContext context) async {
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
  if (ok == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Study time logged successfully.'),
        duration: Duration(seconds: 3),
      ),
    );
  }
}

Future<void> _yptEditDday(BuildContext context, AppState st) async {
  final current = st.ddayStr == null ? null : DateTime.tryParse(st.ddayStr!);
  final action = await showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: yptCard2Color(context),
      title: const Text('D-Day', style: TextStyle(fontSize: 16)),
      content: Text(
        'A countdown chip for your target date (exam day, for example).',
        style: TextStyle(fontSize: 13, color: yptGrey500(context)),
      ),
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

Future<void> _yptEditGoal(BuildContext context, AppState st) async {
  final hCtl = TextEditingController(
      text: st.goalMinutes > 0 ? '${st.goalMinutes ~/ 60}' : '');
  final mCtl = TextEditingController(
      text: st.goalMinutes > 0 ? '${st.goalMinutes % 60}' : '');
  final result = await showDialog<int>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: yptCard2Color(context),
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
            onPressed: () => Navigator.pop(context, 0),
            child: const Text('Clear'),
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
  if (result != null) st.setGoalMinutes(result);
}

void _yptHelpDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: yptCard2Color(context),
      title: const Text('wannabeYPT Help', style: TextStyle(fontSize: 16)),
      content: Text(
        'wannabeYPT is an unofficial YPT client tailored for laptop/PC study.\n\n'
        '• Timers sync with your YPT account in real time.\n'
        '• Close guard protects your session if you close the tab.\n'
        '• Support / Feedback: Telegram @wannabeypt',
        style: TextStyle(fontSize: 13, color: yptGrey500(context)),
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

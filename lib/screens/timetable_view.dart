import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../main.dart' show yptCardColor, yptGrey400, yptGrey500, yptGrey600;
import '../models.dart';

/// Weekly timetable grid (read-only): the account's timetable
/// blocks laid out Mon–Sun against the hours they cover. The
/// endpoint and the 1 = Monday day convention are Desky-derived and
/// unproven live, a failed load shows an error with a retry.
class TimetablePage extends StatefulWidget {
  const TimetablePage({super.key});
  @override
  State<TimetablePage> createState() => _TimetablePageState();
}

const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class _TimetablePageState extends State<TimetablePage> {
  bool _loading = false;
  bool _failed = false;
  List<TimetableBlock> _blocks = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final blocks = await context.read<AppState>().api.fetchTimetable();
      if (!mounted) return;
      setState(() {
        // Only renderable blocks: a valid weekday and a positive span.
        _blocks = blocks
            .where((b) =>
                b.dayOfWeek >= 1 &&
                b.dayOfWeek <= 7 &&
                b.endHour > b.startHour)
            .toList();
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

  String _hourLabel(int h) {
    if (h == 0) return '12 AM';
    if (h < 12) return '$h AM';
    if (h == 12) return '12 PM';
    if (h == 24) return '12 AM';
    return '${h - 12} PM';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('Timetable',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
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
                      Text('Could not load timetable',
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
              : _blocks.isEmpty
                  ? Center(
                      child: Text('No timetable set yet.',
                          style: TextStyle(
                              color: yptGrey500(context), fontSize: 12)),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      children: [
                        _grid(),
                        const SizedBox(height: 18),
                        Text('This view is read-only.',
                            style: TextStyle(
                                fontSize: 11, color: yptGrey600(context))),
                        const SizedBox(height: 12),
                        for (final b in _blocks) _blockRow(b),
                      ],
                    ),
    );
  }

  Widget _grid() {
    var minHour = _blocks.map((b) => b.startHour).reduce((a, b) => a < b ? a : b);
    var maxHour = _blocks.map((b) => b.endHour).reduce((a, b) => a > b ? a : b);
    minHour = minHour.clamp(0, 23);
    maxHour = maxHour.clamp(1, 24);
    if (maxHour <= minHour) maxHour = minHour + 1;
    final hours = [for (var h = minHour; h < maxHour; h++) h];
    const cellH = 30.0;
    const cellW = 104.0;
    TimetableBlock? covering(int day, int hour) {
      for (final b in _blocks) {
        if (b.dayOfWeek == day && b.startHour <= hour && hour < b.endHour) {
          return b;
        }
      }
      return null;
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Hour labels.
          Column(
            children: [
              const SizedBox(height: 22),
              for (final h in hours)
                SizedBox(
                  height: cellH,
                  child: Center(
                    child: Text(_hourLabel(h),
                        style: TextStyle(
                            fontSize: 10, color: yptGrey500(context))),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 6),
          for (var day = 1; day <= 7; day++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Column(
                children: [
                  SizedBox(
                    width: cellW,
                    height: 22,
                    child: Center(
                      child: Text(_dayNames[day - 1],
                          style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                  for (final h in hours)
                    Builder(
                      builder: (_) {
                        final b = covering(day, h);
                        final isFirst = b != null && b.startHour == h;
                        return Container(
                          width: cellW,
                          height: cellH,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          decoration: BoxDecoration(
                            color: b == null
                                ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03)
                                : Color(b.colorInt)
                                    .withValues(alpha: 0.30),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Colors.black.withValues(alpha: 0.3)),
                          ),
                          alignment: Alignment.centerLeft,
                          child: isFirst
                              ? Text(b.subjectTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11))
                              : null,
                        );
                      },
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _blockRow(TimetableBlock b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: yptCardColor(context), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                  color: Color(b.colorInt), shape: BoxShape.circle)),
          const SizedBox(width: 11),
          Expanded(
            child: Text(b.subjectTitle,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Text(
              '${_dayNames[b.dayOfWeek - 1]} · ${_hourLabel(b.startHour)} – ${_hourLabel(b.endHour)}',
              style: TextStyle(color: yptGrey400(context), fontSize: 12)),
        ],
      ),
    );
  }
}

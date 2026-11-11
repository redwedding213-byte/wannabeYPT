import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../main.dart' show kBrand, yptCardColor, yptGrey400, yptGrey500;
import '../models.dart';
import 'timer_view.dart' show fmtMs;

/// Global / category leaderboards (read-only): the category's
/// members ranked by study time, plus the signed-in user's own rank.
/// The ranks endpoint is Desky-derived and unproven live — a failed
/// load shows an error with a retry, never a crash or a fake list.
class LeaderboardsPage extends StatefulWidget {
  const LeaderboardsPage({super.key});
  @override
  State<LeaderboardsPage> createState() => _LeaderboardsPageState();
}

class _LeaderboardsPageState extends State<LeaderboardsPage> {
  String _period = 'day';
  bool _loading = false;
  bool _failed = false;
  List<RankMember> _ranks = [];
  int? _myRank;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  /// Reference date the ranks endpoint wants, without zero-padding:
  /// today for day, the week's Monday for week, the 1st for month.
  String _refDate() {
    final now = DateTime.now();
    late final DateTime ref;
    if (_period == 'month') {
      ref = DateTime(now.year, now.month, 1);
    } else if (_period == 'week') {
      final monday = now.subtract(Duration(days: now.weekday - 1));
      ref = DateTime(monday.year, monday.month, monday.day);
    } else {
      ref = DateTime(now.year, now.month, now.day);
    }
    return '${ref.year}-${ref.month}-${ref.day}';
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final st = context.read<AppState>();
      final user = st.user;
      if (user == null) throw Exception('not signed in');
      final ranks = await st.api.categoryRanks(
        user.categoryId,
        user.countryId,
        date: _refDate(),
        type: _period,
      );
      final mine = await st.api.myCategoryRank(user.categoryId, user.countryId);
      if (!mounted) return;
      setState(() {
        _ranks = ranks;
        _myRank = mine;
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

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final category = st.user?.category ?? '';
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text('Leaderboards',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: _load,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'day', label: Text('Day')),
              ButtonSegment(value: 'week', label: Text('Week')),
              ButtonSegment(value: 'month', label: Text('Month')),
            ],
            selected: {_period},
            onSelectionChanged: (s) {
              setState(() => _period = s.first);
              _load();
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: yptCardColor(context), borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.emoji_events_outlined,
                    size: 20, color: kBrand),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _myRank != null
                        ? 'My rank · Ranked #$_myRank'
                        : 'My rank · —',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13.5),
                  ),
                ),
                if (category.isNotEmpty)
                  Text(category,
                      style:
                          TextStyle(color: yptGrey400(context), fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Center(
                child: Padding(
              padding: EdgeInsets.only(top: 24),
              child: CircularProgressIndicator(),
            ))
          else if (_failed)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 24),
                  Text('Could not load rankings',
                      style:
                          TextStyle(color: yptGrey500(context), fontSize: 12)),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            )
          else if (_ranks.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text('No rankings for this period.',
                    style: TextStyle(color: yptGrey500(context), fontSize: 12)),
              ),
            )
          else
            for (var i = 0; i < _ranks.length; i++)
              _rankRow(i + 1, _ranks[i]),
        ],
      ),
    );
  }

  Widget _rankRow(int rank, RankMember m) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: yptCardColor(context), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: rank <= 3 ? kBrand : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12),
            child: Text('$rank',
                style: TextStyle(
                    fontSize: 10.5,
                    color: rank <= 3 ? Colors.white : (Theme.of(context).brightness == Brightness.light ? Colors.grey[700] : Colors.grey[300]),
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          if (m.studiconId > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Image.network(
                studiconUrl(
                    m.studiconId,
                    studiconPoseFile(
                        studying: true, studyMs: m.studyMs)),
                width: 30,
                height: 30,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox(width: 30),
              ),
            ),
          Expanded(
            child: Text(m.nickname,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Text(fmtMs(m.studyMs),
              style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }
}

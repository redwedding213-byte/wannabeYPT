import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../app_state.dart';
import '../main.dart' show kBrand, yptCardColor;
import '../models.dart';
import '../ypt_api.dart';

/// Challenges (Desky parity, built 2026-11-06).
/// Group study targets over a date range — e.g. "wake up on time"
/// (WAKEUP) or "study 4h a day" (STUDY). Browse + join, my
/// challenges with server-reported progress, and daily logs
/// (mine + my group's). Nothing here touches study time or the
/// timer.
///
/// Deliberately NO check-in button: Desky's screen fakes one (it
/// shows a success snackbar with no API call behind it) and neither
/// Desky nor the captured-traffic spec has a check-in endpoint.
/// Progress comes from the server only — check-ins happen through
/// the timer/study itself in the official app.
///
/// The join/cancel/my endpoints are Desky-only (not in the spec),
/// so the live test (list + join one challenge) is the real proof
/// for them; a rejection shows the server's `m` message.
class ChallengesPage extends StatefulWidget {
  const ChallengesPage({super.key});
  @override
  State<ChallengesPage> createState() => _ChallengesPageState();
}

class _ChallengesPageState extends State<ChallengesPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  bool _loading = false;
  bool _failed = false;
  String? _error;
  bool _busy = false;
  List<StudyChallenge> _available = [];
  List<StudyChallenge> _mine = [];

  // Daily logs (loaded lazily when the Logs tab opens).
  bool _logsLoading = false;
  bool _logsLoaded = false;
  String? _logsError;
  String? _groupLogsError;
  List<ChallengeDailyLog> _myLogs = [];
  List<ChallengeDailyLog> _groupLogs = [];
  Group? _groupForLogs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index == 2 && !_logsLoaded && !_logsLoading) _loadLogs();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  YptApi get _api => context.read<AppState>().api;

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _failed = false;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.fetchChallenges(),
        _api.fetchMyChallenges(),
      ]);
      if (!mounted) return;
      final available = results[0];
      var mine = results[1];
      // The /my endpoint is Desky-only and may not exist — fall
      // back to the joined items of the available list.
      if (mine.isEmpty) {
        mine = available.where((c) => c.isJoined).toList();
      }
      setState(() {
        _available = available;
        _mine = mine;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
        _error = _readable(e);
      });
    }
  }

  Future<void> _loadLogs() async {
    if (_logsLoading) return;
    setState(() {
      _logsLoading = true;
      _logsError = null;
      _groupLogsError = null;
    });
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final groups = context.read<AppState>().joinedGroups;
    final group = groups.isNotEmpty ? groups.first : null;
    List<ChallengeDailyLog> myLogs = [];
    List<ChallengeDailyLog> groupLogs = [];
    String? logsError;
    String? groupLogsError;
    try {
      myLogs = await _api.fetchChallengeDailyLogs(
        start: today.subtract(const Duration(days: 6)),
        end: today.add(const Duration(days: 1)),
      );
    } catch (e) {
      logsError = _readable(e);
    }
    if (group != null) {
      try {
        groupLogs = await _api.fetchGroupChallengeDailyLogs(
          groupId: group.id,
          date: today,
        );
      } catch (e) {
        groupLogsError = _readable(e);
      }
    }
    if (!mounted) return;
    setState(() {
      _myLogs = myLogs;
      _groupLogs = groupLogs;
      _groupForLogs = group;
      _logsError = logsError;
      _groupLogsError = groupLogsError;
      _logsLoading = false;
      _logsLoaded = true;
    });
  }

  String _readable(Object e) {
    final s = e.toString().replaceFirst('YptApiException: ', '');
    // YptApiException messages already carry the server's `m`.
    return s;
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _joinDialog(StudyChallenge challenge) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yptCardColor(context),
        title: Text('Join: ${challenge.name}',
            style: const TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(challenge.description,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
            if (challenge.rules.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(challenge.rules,
                  style:
                      const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
            const SizedBox(height: 12),
            Text(
              challenge.flameCost > 0
                  ? 'Entry: ${challenge.flameCost} flames'
                  : 'Entry: free',
              style: const TextStyle(
                  color: kBrand, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Goal: ${(challenge.successThreshold * 100).toInt()}% of days · '
              '${_dateRange(challenge)}',
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Join', style: TextStyle(color: kBrand)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _api.joinChallenge(
        challengeId: challenge.id,
        flameBet: challenge.flameCost,
      );
      if (!mounted) return;
      _showMessage('Joined ${challenge.name}');
      await _load();
    } catch (e) {
      _showMessage(_readable(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveDialog(StudyChallenge challenge) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: yptCardColor(context),
        title: Text('Leave: ${challenge.name}',
            style: const TextStyle(fontSize: 16)),
        content: const Text(
          'Your progress in this challenge will be lost.',
          style: TextStyle(color: Colors.grey, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final ok = await _api.cancelChallenge(challenge.id);
      if (!mounted) return;
      _showMessage(ok
          ? 'Left ${challenge.name}'
          : 'Could not leave that challenge.');
      if (ok) await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dateRange(StudyChallenge c) {
    final df = DateFormat('d MMM');
    return '${df.format(c.startDate)} – ${df.format(c.endDate)}';
  }

  Widget _challengeCard(StudyChallenge c, {bool isMine = false}) {
    final progress = c.progress;
    return Container(
      decoration: BoxDecoration(
        color: yptCardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: c.isJoined ? kBrand : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
          width: c.isJoined ? 1.5 : 1,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (c.emoji != null && c.emoji!.isNotEmpty)
                Text(c.emoji!, style: const TextStyle(fontSize: 20)),
              if (c.emoji != null && c.emoji!.isNotEmpty)
                const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.name,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: kBrand.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  c.flameCost > 0 ? '🔥 ${c.flameCost}' : 'Free',
                  style: const TextStyle(
                      color: kBrand,
                      fontWeight: FontWeight.bold,
                      fontSize: 11),
                ),
              ),
            ],
          ),
          if (c.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              c.description,
              style: const TextStyle(color: Colors.grey, fontSize: 12.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (c.type.isNotEmpty) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(c.type,
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 11)),
                ),
                const SizedBox(width: 8),
              ],
              const Icon(Icons.calendar_today,
                  size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text(_dateRange(c),
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
              const Spacer(),
              const Icon(Icons.people_outline,
                  size: 13, color: Colors.grey),
              const SizedBox(width: 4),
              Text('${c.participantCount}',
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
            ],
          ),
          if (isMine || c.isJoined) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Progress',
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
                Text('${(progress * 100).toInt()}%',
                    style: const TextStyle(
                        color: kBrand,
                        fontWeight: FontWeight.bold,
                        fontSize: 11)),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                color: kBrand,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Goal: ${(c.successThreshold * 100).toInt()}% of days',
              style: const TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: c.isJoined
                ? OutlinedButton(
                    onPressed: _busy ? null : () => _leaveDialog(c),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.redAccent.withValues(alpha: 0.6)),
                    ),
                    child: const Text('Leave challenge',
                        style: TextStyle(color: Colors.redAccent)),
                  )
                : ElevatedButton(
                    onPressed: _busy ? null : () => _joinDialog(c),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBrand,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Join challenge',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _challengeList(List<StudyChallenge> list, {bool isMine = false}) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.emoji_events_outlined,
                size: 56, color: Colors.grey),
            const SizedBox(height: 14),
            Text(
              isMine
                  ? 'You have not joined any challenge yet.'
                  : 'No challenges available right now.',
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: kBrand,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) =>
            _challengeCard(list[i], isMine: isMine),
      ),
    );
  }

  Widget _logRow(ChallengeDailyLog log) {
    final df = DateFormat('d MMM, h:mm a');
    final when = log.startAt != null ? df.format(log.startAt!) : '';
    return Container(
      decoration: BoxDecoration(
        color: yptCardColor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  log.title.isNotEmpty ? log.title : 'Challenge log',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (log.type.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(log.type,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 11)),
                ),
              ],
            ],
          ),
          if (log.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              log.description,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              if (when.isNotEmpty)
                Text(when,
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
              if (log.groupTitle.isNotEmpty) ...[
                const SizedBox(width: 8),
                const Icon(Icons.group, size: 12, color: Colors.grey),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(log.groupTitle,
                      style:
                          const TextStyle(color: Colors.grey, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _logsTab() {
    if (_logsLoading) {
      return const Center(
          child: CircularProgressIndicator(color: kBrand));
    }
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _logsLoaded = false);
        await _loadLogs();
      },
      color: kBrand,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('My logs · last 7 days',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          if (_logsError != null)
            Text(_logsError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          if (_logsError == null && _myLogs.isEmpty)
            const Text('No challenge logs in the last 7 days.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          if (_logsError == null)
            ..._myLogs.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _logRow(l),
                )),
          const SizedBox(height: 18),
          Text(
            _groupForLogs != null
                ? 'Group logs · ${_groupForLogs!.title} · today'
                : 'Group logs · today',
            style:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          if (_groupForLogs == null)
            const Text('Join a group to see group challenge logs.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          if (_groupForLogs != null && _groupLogsError != null)
            Text(_groupLogsError!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          if (_groupForLogs != null &&
              _groupLogsError == null &&
              _groupLogs.isEmpty)
            const Text('No group challenge logs today.',
                style: TextStyle(color: Colors.grey, fontSize: 12)),
          if (_groupForLogs != null && _groupLogsError == null)
            ..._groupLogs.map((l) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _logRow(l),
                )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenges',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
            tooltip: 'Reload',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: kBrand,
          labelColor: Theme.of(context).colorScheme.onSurface,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Available'),
            Tab(text: 'My challenges'),
            Tab(text: 'Daily logs'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kBrand))
          : _failed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off_outlined,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 14),
                        Text(
                          _error ?? 'Could not load challenges.',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _load,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kBrand,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : TabBarView(
                  controller: _tabs,
                  children: [
                    _challengeList(_available),
                    _challengeList(_mine, isMine: true),
                    _logsTab(),
                  ],
                ),
    );
  }
}

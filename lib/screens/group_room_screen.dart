import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../app_state.dart';
import '../models.dart';
import '../main.dart' show kBrand, kBg, kCard, kCard2;
import 'timer_view.dart' show fmtMs;
import 'stats_view.dart' show fmtHM;
import 'member_profile_page.dart';
import 'active_study_components.dart';

/// Group room in the shape of the official YPT app: bottom tabs for
/// Home (the member desk grid), Attendance (the week table), Rankings
/// (daily / weekly) and Invite (QR + link).
///
/// "Studying" comes from the server's own live flag (`dl.is`) — the
/// member-level `im` flag is true for everyone and means nothing. A live
/// member's timer is their completed total plus the running session
/// (now − `dl.st`), exactly what the official app shows.
class GroupRoomScreen extends StatefulWidget {
  final Group group;
  const GroupRoomScreen({super.key, required this.group});
  @override
  State<GroupRoomScreen> createState() => _GroupRoomScreenState();
}

class _GroupRoomScreenState extends State<GroupRoomScreen> {
  List<GroupMember>? _members;
  bool _error = false;
  Timer? _ticker;
  Timer? _refresher;
  Timer? _earlyRefresh;

  int _tab = 0;
  String _rankMode = 'Daily';

  // Chat tab state (5th tab). Polling runs only while the chat tab
  // is open — a web tab stays open, so background polling is a real
  // cost, and the timer is cancelled on leaving the tab or screen,
  // same discipline as the room's other timers.
  List<ChatMessage>? _chatMessages;
  bool _chatLoading = false;
  bool _chatError = false;
  bool _chatTried = false;
  String? _chatDiag;
  String? _chatNotice;
  Timer? _chatPoll;
  bool _chatPollRunning = false;
  bool _chatSending = false;
  final _chatCtrl = TextEditingController();
  final _chatScroll = ScrollController();
  bool _chatScrolledOnce = false;
  bool _showStickers = false;
  List<StickerSet>? _stickerSets;
  bool _stickersLoading = false;
  int _stickerSetIdx = 0;
  final Set<int> _reacting = {};

  // Weekly data (Attendance + weekly Rankings) comes from the group
  // ranks route: type=week anchored on the week's Monday gives week
  // totals, and one type=day call per day gives the attendance table.
  // The members endpoint ignores dates entirely — never use it here.
  bool _weekLoading = false;
  bool _weekTried = false;
  bool _weekRankOk = false;
  bool _attOk = false;
  List<GroupMember> _weekMembers = [];
  List<DateTime> _weekDays = [];

  Map<String, GroupMember> get _weekByNick =>
      {for (final m in _weekMembers) m.nickname: m};
  Map<String, int> _weekTotals = {};
  Map<String, Map<String, int>> _weekDaily = {};

  @override
  void initState() {
    super.initState();
    // Remember the open room so a browser refresh can land back here.
    SharedPreferences.getInstance().then((sp) {
      sp.setInt('openGroupId', widget.group.id);
      sp.setInt('openGroupAt', DateTime.now().millisecondsSinceEpoch);
    });
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_members?.any((m) => m.isLive) ?? false)) {
        setState(() {});
      }
    });
    // One quick re-poll so live members light up fast, then settle to 20 s.
    _earlyRefresh = Timer(const Duration(seconds: 8), () {
      _load(silent: true);
    });
    _refresher = Timer.periodic(const Duration(seconds: 20), (_) {
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    SharedPreferences.getInstance().then((sp) {
      sp.remove('openGroupId');
      sp.remove('openGroupAt');
    });
    _ticker?.cancel();
    _refresher?.cancel();
    _earlyRefresh?.cancel();
    _stopChatPoll();
    _chatCtrl.dispose();
    _chatScroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    try {
      final list =
          await context.read<AppState>().fetchMembers(widget.group.id);
      if (!mounted) return;
      // Official order: most time first.
      final now = DateTime.now();
      list.sort(
          (a, b) => b.liveDisplayMs(now).compareTo(a.liveDisplayMs(now)));
      setState(() {
        _members = list;
        _error = false;
      });
    } catch (_) {
      if (!mounted) return;
      if (_members == null && !silent) setState(() => _error = true);
    }
  }

  int _displayMs(GroupMember m) => m.liveDisplayMs(DateTime.now());

  void _selectTab(int i) {
    setState(() => _tab = i);
    if (i == 4) {
      _startChatPoll();
    } else {
      _stopChatPoll();
    }
    if ((i == 1 || (i == 2 && _rankMode == 'Weekly')) && !_weekTried) {
      _loadWeek();
    }
  }

  Future<void> _loadWeek() async {
    if (_weekTried || _weekLoading) return;
    _weekLoading = true;
    if (mounted) setState(() {});
    final st = context.read<AppState>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = <DateTime>[];
    for (var i = 0; i < 7; i++) {
      final d = monday.add(Duration(days: i));
      if (d.isAfter(today)) break;
      days.add(d);
    }
    // Week totals: one ranks call anchored on Monday — the only date
    // the server accepts for type=week (today's date returns empty).
    var rankOk = false;
    var weekMembers = <GroupMember>[];
    final totals = <String, int>{};
    try {
      weekMembers = await st.fetchGroupRanks(
          widget.group.id, AppState.dateStr(monday), 'week');
      for (final m in weekMembers) {
        totals[m.nickname] = m.studyMs;
      }
      rankOk = weekMembers.isNotEmpty;
    } catch (_) {}
    // Attendance: one type=day ranks call per day. If every day comes
    // back identical to today while today is non-zero, the server
    // ignored the dates — show the honest fallback instead of a table
    // that repeats today seven times.
    var attOk = false;
    final daily = <String, Map<String, int>>{};
    try {
      final perDay = <String, List<GroupMember>>{};
      for (final d in days) {
        perDay[AppState.dateStr(d)] = await st.fetchGroupRanks(
            widget.group.id, AppState.dateStr(d), 'day');
      }
      var identical = days.length > 1;
      if (identical) {
        final ref = perDay[AppState.dateStr(days.last)]!;
        for (final d in days) {
          final list = perDay[AppState.dateStr(d)]!;
          if (list.length != ref.length) {
            identical = false;
            break;
          }
          final map = {for (final m in list) m.nickname: m.studyMs};
          for (final m in ref) {
            if (map[m.nickname] != m.studyMs) {
              identical = false;
              break;
            }
          }
          if (!identical) break;
        }
      }
      final todaySum =
          (perDay[AppState.dateStr(today)] ?? const <GroupMember>[])
              .fold(0, (a, m) => a + m.studyMs);
      attOk = !(identical && todaySum > 0);
      if (attOk) {
        for (final d in days) {
          final key = AppState.dateStr(d);
          for (final m in perDay[key]!) {
            daily.putIfAbsent(m.nickname, () => {})[key] = m.studyMs;
          }
        }
        // Week call empty/failed? Sum the days for the totals instead.
        if (!rankOk) {
          daily.forEach((nick, byDay) {
            totals[nick] = byDay.values.fold(0, (a, v) => a + v);
          });
          rankOk = totals.isNotEmpty;
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _weekDays = days;
      _weekTotals = totals;
      _weekDaily = daily;
      _weekMembers = weekMembers;
      _weekRankOk = rankOk;
      _attOk = attOk;
      _weekTried = true;
      _weekLoading = false;
    });
  }

  void _showInfo() {
    final g = widget.group;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        title: Text(g.title, style: const TextStyle(fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (g.slogan.isNotEmpty) ...[
              Text(g.slogan, style: TextStyle(color: Colors.grey[300])),
              const SizedBox(height: 12),
            ],
            Text('Category: ${g.category}',
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            const SizedBox(height: 4),
            Text('Owner: ${g.owner}',
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
            const SizedBox(height: 4),
            Text('Members: ${g.memberCount}',
                style: TextStyle(color: Colors.grey[400], fontSize: 13)),
          ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _fmtDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  void _pickSubject(AppState st) {
    final subjects = st.user?.subjects ?? const <Subject>[];
    if (subjects.isEmpty) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xF21C1C24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (bCtx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: Text('Select Subject',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
              for (final s in subjects)
                ListTile(
                  leading: Container(
                    width: 22,
                    height: 22,
                    decoration:
                        BoxDecoration(color: s.color, shape: BoxShape.circle),
                  ),
                  title: Text(s.title, style: const TextStyle(fontSize: 14)),
                  trailing: Text(fmtMs(st.subjectStudyMs(s))),
                  onTap: () {
                    Navigator.pop(bCtx);
                    st.startTimer(s);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _roomAppBar(AppState st, Group g) {
    if (!st.studying) {
      return AppBar(
        backgroundColor: kBg,
        elevation: 0,
        centerTitle: true,
        title: Text(g.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            tooltip: 'Group info',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showInfo,
          ),
        ],
      );
    }

    final sub = st.activeSubject;
    final subTime = sub != null
        ? Duration(
            milliseconds:
                st.subjectStudyMs(sub) + st.elapsed.inMilliseconds)
        : st.elapsed;

    return AppBar(
      backgroundColor: kBg,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: InkWell(
        onTap: () => _pickSubject(st),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                sub?.title ?? 'freestyle',
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Text(
                _fmtDuration(subTime),
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Switch subject',
          icon: const Icon(Icons.swap_horiz, size: 21),
          onPressed: () => _pickSubject(st),
        ),
        IconButton(
          tooltip: 'View mode',
          icon: const Icon(Icons.aspect_ratio, size: 20),
          onPressed: () {},
        ),
        IconButton(
          tooltip: 'Features',
          icon: const Icon(Icons.grid_view, size: 21),
          onPressed: () => showYptFeaturesMenu(context),
        ),
      ],
    );
  }

  Widget _studyHeader(AppState st) {
    final liveTotalMs = st.todayStudyMs + st.elapsed.inMilliseconds;
    final pomoOn = st.pomoOn;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      decoration: const BoxDecoration(
        color: kBg,
        border: Border(bottom: BorderSide(color: Color(0x14FFFFFF))),
      ),
      child: pomoOn
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                PomodoroDialWidget(
                  elapsed: st.elapsed,
                  phaseLeft: st.phaseLeft,
                  focusMinutes: st.focusMin,
                  size: 64,
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Remaining time',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmtDuration(st.phaseLeft),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w300,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => BreakLogDialog.show(
                          context,
                          duration: st.elapsed,
                          onStop: () => st.stopTimer(),
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.pause,
                              size: 18, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const YptDeskWidget(studying: true, width: 38, height: 26),
                    const SizedBox(height: 3),
                    Text(
                      fmtMs(liveTotalMs),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: kBrand,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current focus time',
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            _fmtDuration(st.elapsed),
                            style: const TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w300,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 14),
                          InkWell(
                            onTap: () => BreakLogDialog.show(
                              context,
                              duration: st.elapsed,
                              onStop: () => st.stopTimer(),
                            ),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(Icons.pause,
                                  size: 18, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const YptDeskWidget(studying: true, width: 38, height: 26),
                    const SizedBox(height: 3),
                    Text(
                      fmtMs(liveTotalMs),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: kBrand,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = context.watch<AppState>();
    final g = widget.group;
    final myNick = st.user?.nickname;
    final members = _members;
    final liveCount = members?.where((m) => m.isLive).length ?? 0;

    if (st.studying) {
      return Scaffold(
        backgroundColor: kBg,
        appBar: _roomAppBar(st, g),
        body: Column(
          children: [
            _studyHeader(st),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  Text(
                    g.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$liveCount members Studying',
                    style: const TextStyle(
                      fontSize: 12,
                      color: kBrand,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.more_horiz, size: 18),
                    color: Colors.grey[500],
                    onPressed: _showInfo,
                  ),
                ],
              ),
            ),
            Expanded(child: _body(members, myNick)),
            StudyBottomDock(onHome: () => Navigator.of(context).pop()),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: kBg,
      appBar: _roomAppBar(st, g),
      body: Column(
        children: [
          Expanded(
            child: switch (_tab) {
              1 => _attendanceTab(myNick),
              2 => _rankingsTab(myNick),
              3 => _inviteTab(),
              4 => _chatTab(),
              _ => _homeTab(members, myNick, liveCount),
            },
          ),
          _tabBar(),
        ],
      ),
    );
  }

  Widget _tabBar() {
    final items = <(IconData, IconData, String)>[
      (Icons.home_outlined, Icons.home, 'Home'),
      (Icons.fact_check_outlined, Icons.fact_check, 'Attendance'),
      (Icons.leaderboard_outlined, Icons.leaderboard, 'Rankings'),
      (Icons.qr_code_outlined, Icons.qr_code, 'Invite'),
      (Icons.chat_bubble_outline, Icons.chat_bubble, 'Chat'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: kCard,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => _selectTab(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_tab == i ? items[i].$2 : items[i].$1,
                          size: 21,
                          color: _tab == i ? kBrand : Colors.grey[500]),
                      const SizedBox(height: 2),
                      Text(items[i].$3,
                          style: TextStyle(
                              fontSize: 10.5,
                              color: _tab == i ? kBrand : Colors.grey[500],
                              fontWeight: _tab == i
                                  ? FontWeight.w700
                                  : FontWeight.w500)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Home tab: intro bar + studying count + desk grid ─────────────
  Widget _homeTab(List<GroupMember>? members, String? myNick, int liveCount) {
    final g = widget.group;
    return Column(
      children: [
        // Group introduction / rules bar
        Container(
          margin: const EdgeInsets.fromLTRB(14, 4, 14, 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
              color: kCard, borderRadius: BorderRadius.circular(10)),
          child: Row(
            children: [
              const Icon(Icons.campaign_outlined, size: 17, color: kBrand),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  g.slogan.isNotEmpty ? g.slogan : 'Group introduction/rules',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[300], fontSize: 13),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: Colors.grey[600]),
            ],
          ),
        ),
        // Studying count + refresh
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 13),
                  children: [
                    const TextSpan(
                        text: 'Studying ',
                        style: TextStyle(color: Colors.white70)),
                    TextSpan(
                      text: '$liveCount members',
                      style: const TextStyle(
                          color: kBrand, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () => _load(silent: true),
                borderRadius: BorderRadius.circular(11),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                      color: kCard2, shape: BoxShape.circle),
                  child: const Icon(Icons.refresh,
                      size: 13, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body(members, myNick)),
      ],
    );
  }

  Widget _body(List<GroupMember>? members, String? myNick) {
    if (members == null) {
      if (_error) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load members',
                  style: TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _load(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (members.isEmpty) {
      return Center(
        child: Text('No members visible (private group)',
            style: TextStyle(color: Colors.grey[600])),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 18),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 235,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.85,
      ),
      itemCount: members.length,
      itemBuilder: (_, i) {
        final m = members[i];
        final me = myNick != null && m.nickname == myNick;
        return _MemberTile(
          member: m,
          studying: m.isLive,
          displayMs: _displayMs(m),
          isMe: me,
          onTap: () {
            if (me) {
              final st = context.read<AppState>();
              if (st.studying) {
                BreakLogDialog.show(
                  context,
                  duration: st.elapsed,
                  onStop: () => st.stopTimer(),
                );
              } else {
                _pickSubject(st);
              }
            } else {
              showMemberProfile(context,
                  member: m, groupId: widget.group.id, isMe: me);
            }
          },
        );
      },
    );
  }

  // ── Attendance tab: the week table ───────────────────────────────
  Widget _attendanceTab(String? myNick) {
    if (_weekLoading || !_weekTried) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_attOk) return _weekUnavailable();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    final sorted = _weekTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final myRank = sorted.indexWhere((e) => e.key == myNick);
    final presentTotal = sorted.fold(0, (a, e) => a + e.value);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Attendance',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(
                '${DateFormat('M/d').format(monday)} ~ ${DateFormat('M/d').format(sunday)} · Weekly',
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
                myRank >= 0 ? 'My rank · Ranked #${myRank + 1}' : 'My rank · —',
                style: const TextStyle(
                    color: kBrand, fontWeight: FontWeight.w600, fontSize: 13)),
            const Spacer(),
            Text('Group week total ${fmtHM(presentTotal)}',
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < sorted.length; i++)
          _attendanceRow(i + 1, sorted[i].key, sorted[i].value,
              isMe: sorted[i].key == myNick),
      ],
    );
  }

  Widget _attendanceRow(int rank, String nick, int weekMs,
      {required bool isMe}) {
    final daily = _weekDaily[nick] ?? const <String, int>{};
    var present = 0;
    for (final d in _weekDays) {
      if ((daily[AppState.dateStr(d)] ?? 0) > 0) present++;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(10),
        border: isMe
            ? Border.all(color: Colors.white.withValues(alpha: 0.3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: rank <= 3 ? kBrand : Colors.white12,
                child: Text('$rank',
                    style: TextStyle(
                        fontSize: 10.5,
                        color: rank <= 3 ? Colors.white : Colors.grey[300],
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(nick,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight:
                            isMe ? FontWeight.bold : FontWeight.w500)),
              ),
              Text(fmtMs(weekMs),
                  style: const TextStyle(
                      fontFeatures: [FontFeature.tabularFigures()])),
              const SizedBox(width: 8),
              Text('$present d',
                  style: TextStyle(color: Colors.grey[500], fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 10,
            children: [
              for (final d in _weekDays)
                Text(
                  '${DateFormat('E').format(d)[0]} ${fmtHM(daily[AppState.dateStr(d)] ?? 0)}',
                  style: TextStyle(
                      fontSize: 10.5,
                      color: (daily[AppState.dateStr(d)] ?? 0) > 0
                          ? Colors.grey[300]
                          : Colors.grey[600],
                      fontFeatures: const [FontFeature.tabularFigures()]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Rankings tab: daily (live) + weekly ──────────────────────────
  Widget _rankingsTab(String? myNick) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              const Text('Rankings',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              ChoiceChip(
                label: const Text('Daily'),
                selected: _rankMode == 'Daily',
                onSelected: (_) => setState(() => _rankMode = 'Daily'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Weekly'),
                selected: _rankMode == 'Weekly',
                onSelected: (_) {
                  setState(() => _rankMode = 'Weekly');
                  if (!_weekTried) _loadWeek();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _rankMode == 'Daily'
              ? _dailyRankings(myNick)
              : _weeklyRankings(myNick),
        ),
      ],
    );
  }

  Widget _dailyRankings(String? myNick) {
    final members = _members;
    if (members == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final now = DateTime.now();
    final sorted = [...members]
      ..sort((a, b) => b.liveDisplayMs(now).compareTo(a.liveDisplayMs(now)));
    final total = sorted.fold(0, (a, m) => a + m.liveDisplayMs(now));
    final avg = sorted.isEmpty ? 0 : total ~/ sorted.length;
    final myRank = sorted.indexWhere((m) => m.nickname == myNick);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      children: [
        Row(
          children: [
            Text('Total time ${fmtMs(total)}',
                style: TextStyle(color: Colors.grey[400], fontSize: 12.5)),
            const SizedBox(width: 14),
            Text('Average time ${fmtMs(avg)}',
                style: TextStyle(color: Colors.grey[400], fontSize: 12.5)),
            const Spacer(),
            if (myRank >= 0)
              Text('My rank #${myRank + 1}',
                  style: const TextStyle(
                      color: kBrand,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5)),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < sorted.length; i++)
          _rankRow(i + 1, sorted[i].nickname, sorted[i].liveDisplayMs(now),
              live: sorted[i].isLive,
              category: sorted[i].category,
              isMe: sorted[i].nickname == myNick),
      ],
    );
  }

  Widget _weeklyRankings(String? myNick) {
    if (_weekLoading || !_weekTried) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_weekRankOk) return _weekUnavailable();
    final now = DateTime.now();
    final byNick = _weekByNick;
    final sorted = _weekTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold(0, (a, e) => a + e.value);
    final avg = sorted.isEmpty ? 0 : total ~/ sorted.length;
    final myRank = sorted.indexWhere((e) => e.key == myNick);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      children: [
        Row(
          children: [
            Text('Week total ${fmtMs(total)}',
                style: TextStyle(color: Colors.grey[400], fontSize: 12.5)),
            const SizedBox(width: 14),
            Text('Average ${fmtMs(avg)}',
                style: TextStyle(color: Colors.grey[400], fontSize: 12.5)),
            const Spacer(),
            if (myRank >= 0)
              Text('My rank #${myRank + 1}',
                  style: const TextStyle(
                      color: kBrand,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.5)),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < sorted.length; i++)
          _rankRow(
              i + 1,
              sorted[i].key,
              byNick[sorted[i].key]?.liveDisplayMs(now) ?? sorted[i].value,
              live: byNick[sorted[i].key]?.isLive ?? false,
              category: byNick[sorted[i].key]?.category ?? '',
              isMe: sorted[i].key == myNick),
      ],
    );
  }

  Widget _rankRow(int rank, String nick, int ms,
      {required bool live, required String category, required bool isMe}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(10),
        border: isMe
            ? Border.all(color: Colors.white.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Text('$rank',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: rank <= 3 ? kBrand : Colors.grey[400])),
          ),
          if (live) ...[
            Container(
              width: 7,
              height: 7,
              decoration:
                  const BoxDecoration(color: kBrand, shape: BoxShape.circle),
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(nick,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontWeight:
                              isMe ? FontWeight.bold : FontWeight.w500,
                          color: live ? kBrand : null)),
                ),
                if (category.isNotEmpty) ...[
                  const SizedBox(width: 7),
                  Text(category,
                      style:
                          TextStyle(fontSize: 10.5, color: Colors.grey[500])),
                ],
              ],
            ),
          ),
          Text(fmtMs(ms),
              style: TextStyle(
                  color: live ? kBrand : Colors.grey[300],
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  Widget _weekUnavailable() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Weekly data could not be loaded from the server right now. Daily rankings work as usual — try again in a bit.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _weekTried = false);
                _loadWeek();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Check again'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Chat tab: messages, reactions, stickers, image URLs ────────
  // Better than the official app's chat, same classic foundation:
  // roomier bubbles, day separators, readable names and times.
  String? get _myNick => context.read<AppState>().user?.nickname;

  int get _myId {
    final nick = _myNick;
    if (nick == null || nick.isEmpty) return 0;
    for (final m in _members ?? const <GroupMember>[]) {
      if (m.nickname == nick) return m.userId;
    }
    return 0;
  }

  bool _isOwn(ChatMessage m) {
    if (_myId > 0 && m.senderId == _myId) return true;
    final nick = _myNick;
    return nick != null && nick.isNotEmpty && m.senderName == nick;
  }

  void _startChatPoll() {
    if (_chatPollRunning) return;
    _chatPollRunning = true;
    // Always refresh on entering the tab, silently after the first load.
    _loadChat(silent: _chatTried);
    _chatPoll = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted || _tab != 4 || _chatSending) return;
      _loadChat(silent: true);
    });
  }

  void _stopChatPoll() {
    _chatPoll?.cancel();
    _chatPoll = null;
    _chatPollRunning = false;
  }

  Future<void> _loadChat({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _chatLoading = true;
        _chatError = false;
      });
    }
    try {
      final res =
          await context.read<AppState>().api.fetchChatMessages(widget.group.id);
      if (!mounted) return;
      final msgs = [...res.messages]
        ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
      // A reload confirms optimistic temps (negative ids): drop them
      // unless a send is still in flight, so no duplicates appear.
      final temps = _chatSending
          ? (_chatMessages?.where((m) => m.id < 0).toList() ??
              const <ChatMessage>[])
          : const <ChatMessage>[];
      String? diag;
      if (msgs.isEmpty && res.httpOk) {
        final hasListKey = res.rawKeys.contains('m') ||
            res.rawKeys.contains('messages');
        diag = res.serverMessage ??
            (hasListKey
                ? null
                : 'Server returned keys: ${res.rawKeys.join(', ')}');
      }
      setState(() {
        _chatMessages = [...msgs, ...temps];
        _chatLoading = false;
        _chatError = !res.httpOk;
        _chatTried = true;
        _chatDiag = diag;
      });
      // First successful load always lands on the newest messages;
      // later loads only follow if the user is already near the bottom.
      _maybeScrollChatToBottom(force: !_chatScrolledOnce);
      _chatScrolledOnce = true;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _chatLoading = false;
        _chatError = true;
      });
    }
  }

  void _maybeScrollChatToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScroll.hasClients) return;
      final pos = _chatScroll.position;
      final nearBottom = pos.pixels >= pos.maxScrollExtent - 200;
      if (force || nearBottom) {
        if (pos.maxScrollExtent > 0) _chatScroll.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  Future<void> _sendChat({
    String text = '',
    String? stickerUrl,
    String? imageUrl,
  }) async {
    final nick = _myNick ?? '';
    if (_chatSending) return;
    if (text.trim().isEmpty && stickerUrl == null && imageUrl == null) {
      return;
    }
    final temp = ChatMessage(
      id: -DateTime.now().millisecondsSinceEpoch,
      senderId: _myId,
      senderName: nick,
      studiconId: 0,
      text: text.isNotEmpty ? text : (imageUrl != null ? 'Photo' : ''),
      stickerUrl: stickerUrl,
      imageUrl: imageUrl,
      sentAt: DateTime.now(),
    );
    setState(() {
      _chatMessages = [...?_chatMessages, temp];
      _chatSending = true;
      _chatNotice = null;
    });
    _chatCtrl.clear();
    _maybeScrollChatToBottom(force: true);
    final sent = await context.read<AppState>().api.sendChatMessage(
          groupId: widget.group.id,
          nickname: nick,
          // The group's real category STRING — never Desky's int 0.
          category: widget.group.category,
          userId: _myId,
          message: temp.text,
          stickerUrl: stickerUrl,
          imageUrl: imageUrl,
        );
    if (!mounted) return;
    setState(() => _chatSending = false);
    if (sent == null) {
      setState(() {
        _chatMessages =
            _chatMessages?.where((m) => m.id != temp.id).toList();
        _chatNotice =
            'Could not send that message — check connection and try again.';
      });
      return;
    }
    await _loadChat(silent: true);
    _maybeScrollChatToBottom(force: true);
  }

  Future<void> _toggleReaction(ChatMessage m, String emoji) async {
    if (_reacting.contains(m.id)) return;
    final myId = _myId;
    final reacted =
        myId > 0 && (m.reactions[emoji] ?? const []).contains(myId);
    final updated = Map<String, List<int>>.from(m.reactions);
    if (myId > 0) {
      if (reacted) {
        final list = [...(updated[emoji] ?? const <int>[])]..remove(myId);
        if (list.isEmpty) {
          updated.remove(emoji);
        } else {
          updated[emoji] = list;
        }
      } else {
        updated[emoji] = [...(updated[emoji] ?? []), myId];
      }
    }
    setState(() {
      _reacting.add(m.id);
      _chatMessages = _chatMessages
          ?.map((x) => x.id == m.id ? x.copyWith(reactions: updated) : x)
          .toList();
    });
    final ok = await context.read<AppState>().api.sendChatReaction(
          groupId: widget.group.id,
          messageId: m.id,
          emoji: emoji,
        );
    if (!mounted) return;
    setState(() => _reacting.remove(m.id));
    if (!ok) {
      setState(
          () => _chatNotice = 'Could not send that reaction — try again.');
    }
    await _loadChat(silent: true);
  }

  void _showReactionPicker(ChatMessage m) {
    const emojis = ['👍', '❤️', '🔥', '😂', '😮', '😢', '😡'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
        content: Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          children: [
            for (final e in emojis)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _toggleReaction(m, e);
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(e, style: const TextStyle(fontSize: 26)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadStickers() async {
    if (_stickerSets != null || _stickersLoading) return;
    setState(() => _stickersLoading = true);
    final sets = await context.read<AppState>().api.fetchStickerSets();
    if (!mounted) return;
    setState(() {
      _stickerSets = sets;
      _stickersLoading = false;
      _stickerSetIdx = 0;
    });
  }

  void _showImageUrlDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Send an image', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Paste an image URL',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) {
            Navigator.of(ctx).pop();
            final url = ctrl.text.trim();
            if (url.isNotEmpty) _sendChat(imageUrl: url);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final url = ctrl.text.trim();
              if (url.isNotEmpty) _sendChat(imageUrl: url);
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  Widget _chatTab() {
    return Column(
      children: [
        if (_chatNotice != null)
          Container(
            margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
                color: kCard, borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Expanded(
                  child: Text(_chatNotice!,
                      style: TextStyle(color: Colors.grey[300], fontSize: 12.5)),
                ),
                InkWell(
                  onTap: () => setState(() => _chatNotice = null),
                  child: Icon(Icons.close, size: 16, color: Colors.grey[500]),
                ),
              ],
            ),
          ),
        Expanded(child: _chatList()),
        if (_showStickers) _stickerPanel(),
        _composer(),
      ],
    );
  }

  Widget _chatList() {
    final msgs = _chatMessages;
    if (msgs == null) {
      if (_chatLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      if (_chatError) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Could not load chat',
                  style: TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _loadChat(),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }
    if (msgs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _chatDiag ??
                    'No messages yet — say hi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[400], fontSize: 13.5),
              ),
              if (_chatDiag != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _loadChat(),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Reload'),
                ),
              ],
            ],
          ),
        ),
      );
    }
    // Chronological, newest at bottom, with day separators.
    final rows = <Widget>[];
    DateTime? lastDay;
    for (final m in msgs) {
      final day = DateTime(m.sentAt.year, m.sentAt.month, m.sentAt.day);
      if (lastDay == null || day != lastDay) {
        rows.add(_daySeparator(day));
        lastDay = day;
      }
      rows.add(_chatRow(m));
    }
    return ListView(
      controller: _chatScroll,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      children: rows,
    );
  }

  Widget _daySeparator(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final label = day == today
        ? 'Today'
        : day == yesterday
            ? 'Yesterday'
            : DateFormat('MMM d, y').format(day);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
              color: kCard2, borderRadius: BorderRadius.circular(12)),
          child: Text(label,
              style: TextStyle(color: Colors.grey[400], fontSize: 11.5)),
        ),
      ),
    );
  }

  Widget _chatRow(ChatMessage m) {
    final own = _isOwn(m);
    if (m.isNotice) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text(m.text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            own ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!own) ...[
            _chatAvatar(m),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  own ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (!own)
                  Padding(
                    padding: const EdgeInsets.only(left: 2, bottom: 3),
                    child: Text(m.senderName,
                        style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                GestureDetector(
                  onSecondaryTap: () => _showReactionPicker(m),
                  child: InkWell(
                    onLongPress: () => _showReactionPicker(m),
                    borderRadius: BorderRadius.circular(16),
                    child: _chatBubble(m, own),
                  ),
                ),
                if (m.reactions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Wrap(
                      spacing: 5,
                      children: [
                        for (final e in m.reactions.entries)
                          _reactionPill(e.key, e.value),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 3, left: 2, right: 2),
                  child: Text(DateFormat('HH:mm').format(m.sentAt),
                      style: TextStyle(
                          color: Colors.grey[600], fontSize: 10.5)),
                ),
              ],
            ),
          ),
          if (own) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _reactionPill(String emoji, List<int> userIds) {
    final self = _myId > 0 && userIds.contains(_myId);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: self ? kBrand.withValues(alpha: 0.25) : kCard2,
        borderRadius: BorderRadius.circular(11),
        border: self ? Border.all(color: kBrand) : null,
      ),
      child: Text('$emoji ${userIds.length}',
          style: const TextStyle(fontSize: 11.5)),
    );
  }

  Widget _chatAvatar(ChatMessage m) {
    if (m.studiconId > 0) {
      return ClipOval(
        child: Image.network(
          studiconUrl(m.studiconId, 'mini.png'),
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initialCircle(m.senderName),
        ),
      );
    }
    return _initialCircle(m.senderName);
  }

  Widget _initialCircle(String name) {
    final ch = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 16,
      backgroundColor: kCard2,
      child: Text(ch,
          style: TextStyle(color: Colors.grey[300], fontSize: 14)),
    );
  }

  Widget _chatBubble(ChatMessage m, bool own) {
    final bg = own ? kBrand : kCard2;
    final fg = own ? Colors.white : Colors.grey[100];
    Widget content;
    if (m.isSticker) {
      content = Image.network(
        m.stickerUrl!,
        height: 140,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image,
            size: 40, color: Colors.white54),
      );
    } else if (m.isImage) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          m.displayImageUrl!,
          height: 180,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            height: 120,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image,
                size: 36, color: Colors.white54),
          ),
        ),
      );
    } else {
      content = Text(m.text,
          style: TextStyle(color: fg, fontSize: 14.5, height: 1.35));
    }
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: m.isSticker
          ? const EdgeInsets.all(2)
          : const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: m.isSticker ? Colors.transparent : bg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: content,
    );
  }

  Widget _stickerPanel() {
    final sets = _stickerSets;
    return Container(
      height: 230,
      decoration: const BoxDecoration(
        color: kCard,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: _stickersLoading || sets == null
          ? const Center(child: CircularProgressIndicator())
          : sets.isEmpty
              ? Center(
                  child: Text('No sticker sets available',
                      style: TextStyle(color: Colors.grey[500], fontSize: 13)),
                )
              : Column(
                  children: [
                    SizedBox(
                      height: 46,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        itemCount: sets.length,
                        itemBuilder: (_, i) {
                          final s = sets[i];
                          final sel = i == _stickerSetIdx;
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text(s.title),
                              selected: sel,
                              onSelected: (_) =>
                                  setState(() => _stickerSetIdx = i),
                            ),
                          );
                        },
                      ),
                    ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(10),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                        itemCount: sets[_stickerSetIdx].items.length,
                        itemBuilder: (_, i) {
                          final item = sets[_stickerSetIdx].items[i];
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              setState(() => _showStickers = false);
                              _sendChat(stickerUrl: item.url);
                            },
                            child: Image.network(
                              item.url,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(
                                  Icons.broken_image,
                                  color: Colors.grey[600]),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _composer() {
    return Container(
      decoration: const BoxDecoration(
        color: kCard,
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            tooltip: 'Stickers',
            icon: Icon(Icons.emoji_emotions_outlined,
                color: _showStickers ? kBrand : Colors.grey[400]),
            onPressed: () {
              setState(() => _showStickers = !_showStickers);
              if (_showStickers) _loadStickers();
            },
          ),
          IconButton(
            tooltip: 'Send image by URL',
            icon: Icon(Icons.image_outlined, color: Colors.grey[400]),
            onPressed: _showImageUrlDialog,
          ),
          Expanded(
            child: TextField(
              controller: _chatCtrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: 'Message...',
                hintStyle: TextStyle(color: Colors.grey[600]),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 9),
              ),
              onSubmitted: (_) => _sendChat(text: _chatCtrl.text),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Send',
            icon: const Icon(Icons.send, color: kBrand),
            onPressed: _chatSending ? null : () => _sendChat(text: _chatCtrl.text),
          ),
        ],
      ),
    );
  }

  // ── Invite tab: QR + link ────────────────────────────────────────
  String get _inviteLink {
    final payload = '?type=groupInvite&id=${widget.group.id}';
    return 'https://link.yeolpumta.com/${base64Encode(utf8.encode(payload))}';
  }

  Widget _inviteTab() {
    final link = _inviteLink;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Invite friends',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: QrImageView(
              data: link,
              version: QrVersions.auto,
              size: 190,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(
          link,
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[400], fontSize: 11.5),
        ),
        const SizedBox(height: 14),
        Center(
          child: FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invite link copied')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy link'),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Share this link with friends you want to study with — opening it joins them to this group. Test it once on your phone before sharing it widely.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[500], fontSize: 12),
        ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final GroupMember member;
  final bool studying;
  final int displayMs;
  final bool isMe;
  final VoidCallback? onTap;
  const _MemberTile({
    required this.member,
    required this.studying,
    required this.displayMs,
    required this.isMe,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final m = member;
    final accent = studying ? kBrand : null;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isMe
                ? Border.all(
                    color: studying
                        ? kBrand
                        : Colors.white.withValues(alpha: 0.30),
                    width: 1.2,
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 36,
                child: Center(child: _avatar()),
              ),
              const SizedBox(height: 6),
              Text(
                m.nickname,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: accent ?? Colors.grey[300],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                fmtMs(displayMs),
                style: TextStyle(
                  fontSize: 12.5,
                  color: accent ?? Colors.grey[500],
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Doll avatar from the studicon CDN when the payload carries a
  /// studicon id, pose by live state and today's time. Falls back to
  /// the vector YPT desk when there is no id or the image fails to load.
  Widget _avatar() {
    final si = member.studiconId;
    if (si <= 0) return _glyph();
    return Image.network(
      studiconUrl(
          si, studiconPoseFile(studying: studying, studyMs: displayMs)),
      height: 36,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _glyph(),
    );
  }

  Widget _glyph() {
    return YptDeskWidget(
      studying: studying,
      hasStudied: displayMs > 0,
      width: 44,
      height: 32,
    );
  }
}

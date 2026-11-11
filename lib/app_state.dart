import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'offline_sync.dart';
import 'online_events.dart';
import 'ypt_api.dart';
import 'models.dart';
import 'notify.dart';
import 'social_auth.dart';

class AppState extends ChangeNotifier {
  final YptApi api = YptApi();

  AppState() {
    _loadLocal();
    _syncWebState();
    // Hotspot back → flush any queued stops right away. The 60s retry
    // timer is the backstop if this event never fires.
    listenForOnline(() => syncPendingSessions());
  }
  UserData? user;
  bool loading = false;
  String? errorText;

  // 타이머 상태
  Subject? activeSubject;
  int? _startedAtMs;
  DateTime? get timerStartedAt =>
      _startedAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(_startedAtMs!);
  Timer? _ticker;
  Duration elapsed = Duration.zero;
  bool timerLoading = false;
  String? timerErrorText;

  // 오프라인 동기화 큐 — 핫스팟이 끊긴 채 정지한 세션.
  // A stop that never reached the server is queued with its real
  // start/stop times and replayed on reconnect — never lost, never typed.
  final OfflineSyncQueue _offlineQueue = OfflineSyncQueue();
  int pendingSyncCount = 0;
  bool syncingPending = false;
  String? lastSyncError;
  Timer? _syncRetryTimer;

  /// Replays queued stops in order. Safe to call any time: no-ops when
  /// logged out, already syncing, or when nothing is pending. On success
  /// refreshes today's totals; failures stay queued with the server's
  /// message and the retry timer keeps trying.
  Future<void> syncPendingSessions() async {
    if (user == null || syncingPending) return;
    List<OfflineSession> pending;
    try {
      pending = await _offlineQueue.getPending();
    } catch (_) {
      return;
    }
    if (pending.isEmpty) {
      pendingSyncCount = 0;
      lastSyncError = null;
      _stopSyncRetryTimer();
      notifyListeners();
      return;
    }
    syncingPending = true;
    lastSyncError = null;
    notifyListeners();
    SyncResult result;
    try {
      result = await _offlineQueue.syncAll(api);
    } catch (_) {
      // Storage failure mid-sync: keep the count, try again later.
      syncingPending = false;
      _startSyncRetryTimer();
      notifyListeners();
      return;
    }
    pendingSyncCount = result.remaining;
    lastSyncError = result.failed > 0 ? result.lastError : null;
    syncingPending = false;
    if (result.synced > 0) {
      try {
        user = await api.reloadInfo();
        await _refreshSubjectTimesQuietly();
      } catch (_) {}
    }
    if (result.remaining > 0) {
      _startSyncRetryTimer();
    } else {
      _stopSyncRetryTimer();
    }
    notifyListeners();
  }

  void _startSyncRetryTimer() {
    _syncRetryTimer ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => syncPendingSessions(),
    );
  }

  void _stopSyncRetryTimer() {
    _syncRetryTimer?.cancel();
    _syncRetryTimer = null;
  }

  // 과목별 오늘 공부시간. /logs/day 응답이 비거나 제목 표기가 살짝 달라도
  // reload/info 의 subject 시간 값을 fallback으로 쓴다.
  Map<int, int> subjectTimesById = {};
  Map<String, int> subjectTimes = {};

  /// 오늘 총 공부시간 = 과목별 합(타이머+수동추가 포함, dl.sm+dl.ad와 일치).
  /// 과목별 데이터 없으면 dl.sm 폴백.
  int get todayStudyMs {
    if (subjectTimes.isNotEmpty) {
      return subjectTimes.values.fold(0, (a, b) => a + b);
    }
    return user?.dayLog?.studyMs ?? 0;
  }

  // 프로필/과목 재동기화 (새로고침 버튼용)
  bool profileLoading = false;

  Future<void> reloadProfile() async {
    if (api.jwt == null) return;
    profileLoading = true;
    errorText = null;
    notifyListeners();
    try {
      user = await api.reloadInfo();
      // Fresh server state is ground truth: drop optimistic toggles
      // the server now agrees with; keep the rest (propagation lag).
      if (_serverDoneOverrides.isNotEmpty) {
        final fresh = <int, bool>{
          for (final t in user?.tasks ?? const <YptTask>[]) t.id: t.done
        };
        _serverDoneOverrides.removeWhere((id, v) => fresh[id] == v);
      }
      // Archive overrides: the reloaded active list is ground truth.
      // An archived override is done once the subject leaves the
      // active list; an unarchived override is done once it is back.
      if (archivedSubjectIds.isNotEmpty ||
          unarchivedSubjectIds.isNotEmpty) {
        final activeIds = {
          for (final s in user?.subjects ?? const <Subject>[]) s.id
        };
        final beforeA = archivedSubjectIds.length;
        final beforeU = unarchivedSubjectIds.length;
        archivedSubjectIds.removeWhere((id) => !activeIds.contains(id));
        unarchivedSubjectIds.removeWhere((id) => activeIds.contains(id));
        if (archivedSubjectIds.length != beforeA ||
            unarchivedSubjectIds.length != beforeU) {
          unawaited(_saveArchiveOverrides());
        }
      }
      await _refreshSubjectTimesQuietly();
    } catch (e) {
      errorText = 'Could not load subjects: ${_readableError(e)}';
    }
    profileLoading = false;
    notifyListeners();
  }

  Future<void> refreshSubjectTimes() async {
    final loggedTimes = await api.dayLogSubjects(_currentLogDate());
    final mergedTimes = _mergedSubjectTimes(loggedTimes);
    subjectTimesById = mergedTimes.byId;
    subjectTimes = mergedTimes.byTitle;
    notifyListeners();
  }

  // 통계 상태
  int? myRank;
  List<RankMember> ranks = [];
  bool statsLoading = false;
  String? statsErrorText;

  // 그룹 상태
  List<Group> groups = [];
  List<Group> joinedGroups = [];
  bool groupsLoading = false;
  String? groupsErrorText;

  Future<void> loadGroups() async {
    if (user == null) return;
    groupsLoading = true;
    groupsErrorText = null;
    notifyListeners();
    try {
      joinedGroups = await api.myGroups();
      groups = const [];
    } catch (e) {
      groupsErrorText = 'Could not load groups: ${_readableError(e)}';
    }
    groupsLoading = false;
    notifyListeners();
  }

  Future<List<GroupMember>> fetchMembers(int groupId) =>
      api.groupMembers(groupId, user!.countryId);

  Future<List<Map<String, dynamic>>> fetchMembersRaw(int groupId) =>
      api.groupMembersRaw(groupId, user!.countryId);

  // ── Local settings (device-only): D-Day, daily goal ──────────────
  String? ddayStr; // yyyy-MM-dd
  int goalMinutes = 0;

  /// White mode (Tara51 + AL.. asked for a light theme). Persisted
  /// in SharedPreferences; defaults to the classic dark YPT look.
  bool lightTheme = false;

  void setLightTheme(bool value) {
    lightTheme = value;
    _saveLocal();
    notifyListeners();
  }

  // ── Pomodoro ─────────────────────────────────────────────────────
  bool pomoOn = false;
  int focusMin = 50;
  int breakMin = 10;
  int longBreakMin = 15;
  int cyclesBeforeLong = 4;
  int pomoCycles = 0; // completed focus rounds in the current run
  bool pomoBreakLong = false; // the running break is a long one
  String pomoPhase = 'idle'; // idle | focus | break | overtime
  bool pomoOvertime = false; // true once the focus clock hits zero
  DateTime? _phaseEndsAt;
  Duration phaseLeft = Duration.zero; // counts down during focus/break
  Duration overtimeElapsed = Duration.zero; // counts up after focus end
  DateTime? _overtimeStartedAt;
  Timer? _pomoTicker;
  bool _pomoAuto = false;
  String notifyPerm = 'unknown';

  /// Persistent in-app phase-end notice: the reliable signal, since a
  /// system notification may never surface from this webview and a
  /// lone beep is easy to miss. Set when a phase ends; cleared on
  /// dismiss, on a new phase, or when Pomodoro is reset/turned off.
  String? pomoNoticeTitle;
  String? pomoNoticeBody;

  void dismissPomoNotice() {
    pomoNoticeTitle = null;
    pomoNoticeBody = null;
    notifyListeners();
  }

  Duration get focusTotal => Duration(minutes: focusMin);
  Duration get breakTotal => Duration(minutes: breakMin);

  // ── Planner to-dos (device-only for now) ─────────────────────────
  List<TodoTask> tasks = [];

  // ── Day-detail cache for Statistics / Planner ────────────────────
  final Map<String, DayDetail> _dayCache = {};

  Future<void> _loadLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      ddayStr = sp.getString('dday');
      goalMinutes = sp.getInt('goalMin') ?? 0;
      lightTheme = sp.getBool('wannabe_theme_light') ?? false;
      pomoOn = sp.getBool('pomoOn') ?? false;
      focusMin = sp.getInt('focusMin') ?? 50;
      breakMin = sp.getInt('breakMin') ?? 10;
      longBreakMin = sp.getInt('longBreakMin') ?? 15;
      cyclesBeforeLong = sp.getInt('cyclesBeforeLong') ?? 4;
      final tj = sp.getString('todoTasks');
      if (tj != null && tj.isNotEmpty) {
        final decoded = jsonDecode(tj);
        if (decoded is List) {
          tasks = decoded
              .whereType<Map<String, dynamic>>()
              .map(TodoTask.fromJson)
              .where((t) => t.id.isNotEmpty)
              .toList();
        }
      }
      notifyPerm = notifyPermissionState();
      final archivedIds =
          sp.getStringList(_kArchivedSubjectIdsKey) ?? const [];
      final unarchivedIds =
          sp.getStringList(_kUnarchivedSubjectIdsKey) ?? const [];
      archivedSubjectIds
        ..clear()
        ..addAll(archivedIds
            .map((e) => int.tryParse(e) ?? 0)
            .where((e) => e > 0));
      unarchivedSubjectIds
        ..clear()
        ..addAll(unarchivedIds
            .map((e) => int.tryParse(e) ?? 0)
            .where((e) => e > 0));
      notifyListeners();
    } catch (_) {}
    if (!_archiveOverridesReady.isCompleted) {
      _archiveOverridesReady.complete();
    }
  }

  Future<void> _saveLocal() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (ddayStr == null) {
        await sp.remove('dday');
      } else {
        await sp.setString('dday', ddayStr!);
      }
      await sp.setInt('goalMin', goalMinutes);
      await sp.setBool('wannabe_theme_light', lightTheme);
      await sp.setBool('pomoOn', pomoOn);
      await sp.setInt('focusMin', focusMin);
      await sp.setInt('breakMin', breakMin);
      await sp.setInt('longBreakMin', longBreakMin);
      await sp.setInt('cyclesBeforeLong', cyclesBeforeLong);
    } catch (_) {}
  }

  Future<void> _saveTasks() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(
          'todoTasks', jsonEncode(tasks.map((t) => t.toJson()).toList()));
    } catch (_) {}
  }

  void setDday(DateTime? d) {
    ddayStr = d == null ? null : dateStr(d);
    _saveLocal();
    notifyListeners();
  }

  void setGoalMinutes(int minutes) {
    goalMinutes = minutes < 0 ? 0 : minutes;
    _saveLocal();
    notifyListeners();
  }

  static String dateStr(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  // ── Pomodoro engine ──────────────────────────────────────────────
  void setPomoOn(bool on) {
    pomoOn = on;
    // Gesture tap: unlock WebAudio now so the phase-end beep can
    // actually sound later (a context first created at phase-end
    // time, with no gesture in progress, may stay suspended).
    if (on) unlockAudio();
    _saveLocal();
    if (!on) {
      pomoCycles = 0;
      _resetPomo();
    } else if (studying && pomoPhase == 'idle') {
      _beginPhase('focus');
    }
    notifyListeners();
  }

  void setPomoTimes(int focus, int brk) {
    focusMin = focus.clamp(1, 600);
    breakMin = brk.clamp(1, 120);
    _saveLocal();
    notifyListeners();
  }

  void setPomoExtras(int longMin, int cycles) {
    longBreakMin = longMin.clamp(1, 120);
    cyclesBeforeLong = cycles.clamp(2, 8);
    _saveLocal();
    notifyListeners();
  }

  void _beginPhase(String phase, {bool longBreak = false}) {
    // A new phase supersedes any stale phase-end banner.
    pomoNoticeTitle = null;
    pomoNoticeBody = null;
    pomoPhase = phase;
    pomoOvertime = false;
    overtimeElapsed = Duration.zero;
    _overtimeStartedAt = null;
    final mins =
        phase == 'focus' ? focusMin : (longBreak ? longBreakMin : breakMin);
    pomoBreakLong = phase == 'break' && longBreak;
    _phaseEndsAt = DateTime.now().add(Duration(minutes: mins));
    _syncPhaseLeft();
    _pomoTicker?.cancel();
    _pomoTicker =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _pomoTick());
    notifyListeners();
  }

  void _syncPhaseLeft() {
    final end = _phaseEndsAt;
    if (end == null) {
      phaseLeft = Duration.zero;
      return;
    }
    final d = end.difference(DateTime.now());
    phaseLeft = d.isNegative ? Duration.zero : d;
  }

  void _syncOvertime() {
    final started = _overtimeStartedAt;
    if (started == null) {
      overtimeElapsed = Duration.zero;
      return;
    }
    overtimeElapsed = DateTime.now().difference(started);
  }

  Future<void> _pomoTick() async {
    if (pomoOvertime) {
      // Overtime: count up; study timer keeps running.
      _syncOvertime();
      notifyListeners();
      return;
    }
    _syncPhaseLeft();
    notifyListeners();
    if (phaseLeft > Duration.zero || _phaseEndsAt == null) return;
    if (pomoPhase == 'focus') {
      // Focus done: notify and enter overtime. Study timer keeps running.
      // The round is only counted once (pomoOvertime guards re-entry).
      pomoCycles++;
      pomoOvertime = true;
      _overtimeStartedAt = DateTime.now();
      // phaseLeft stays zero; we no longer need _phaseEndsAt.
      _phaseEndsAt = null;
      // In-app persistent banner.
      pomoNoticeTitle = 'Focus over';
      pomoNoticeBody = 'The study timer keeps running \u2014 pause when you want a break.';
      // System notification / beep.
      showAppNotification('Focus complete', pomoNoticeBody!);
      notifyListeners();
    } else if (pomoPhase == 'break') {
      // Break end never auto-starts focus — that stays a deliberate
      // choice. A finished long break also closes the set.
      final wasLong = pomoBreakLong;
      if (wasLong) pomoCycles = 0;
      _resetPomo();
      pomoNoticeTitle = wasLong ? 'Long break over' : 'Break over';
      pomoNoticeBody = 'Tap a subject to start the next focus round.';
      showAppNotification(pomoNoticeTitle!, pomoNoticeBody!);
      notifyListeners();
    }
  }

  void _resetPomo() {
    _pomoTicker?.cancel();
    _pomoTicker = null;
    pomoPhase = 'idle';
    pomoOvertime = false;
    pomoBreakLong = false;
    _phaseEndsAt = null;
    phaseLeft = Duration.zero;
    overtimeElapsed = Duration.zero;
    _overtimeStartedAt = null;
    pomoNoticeTitle = null;
    pomoNoticeBody = null;
  }

  Future<void> enableNotifications() async {
    unlockAudio();
    notifyPerm = await requestNotifyPermission();
    notifyListeners();
  }

  // ── To-dos ───────────────────────────────────────────────────────
  /// One-line status for the Planner when a server write falls back
  /// (e.g. created locally because the server didn't confirm). Null
  /// means nothing to report; the Planner shows and dismisses it.
  String? plannerNotice;

  void dismissPlannerNotice() {
    plannerNotice = null;
    notifyListeners();
  }

  /// Optimistic done-state for server tasks, keyed by task id. The
  /// server row's YptTask is immutable, so toggles live here until a
  /// reload confirms (or corrects) them.
  final Map<int, bool> _serverDoneOverrides = {};
  final Set<int> _serverToggling = {};

  /// Optimistic status-score overrides for server tasks, keyed by
  /// task id — the three-state menu path. Values: 3 done,
  /// [kTaskHalfDoneScore] half-done, null not done. Checked before
  /// [_serverDoneOverrides] so a menu pick wins over a stale binary
  /// toggle for the same task.
  final Map<int, int?> _serverStatusOverrides = {};

  /// Effective server score: menu override, then binary-toggle
  /// override, then the task's own status (0 reads as not done).
  int serverTaskScore(YptTask t) {
    if (_serverStatusOverrides.containsKey(t.id)) {
      return _serverStatusOverrides[t.id] ?? 0;
    }
    if (_serverDoneOverrides.containsKey(t.id)) {
      return _serverDoneOverrides[t.id]! ? 3 : 0;
    }
    return t.status;
  }

  bool serverTaskDone(YptTask t) => serverTaskScore(t) == 3;

  /// Local archive overrides, persisted per subject id. The server's
  /// archive call can return success while the reloaded subject list
  /// still carries dl=false — without these, an archived subject pops
  /// back to active after reload (Tara51's report). Overrides win
  /// over the server flag until the server agrees with them, exactly
  /// like the task done-overrides above. They live here, not in
  /// SubjectsPage, so the Home timer list sees the same archived
  /// state as the Subjects view.
  static const _kArchivedSubjectIdsKey = 'wannabe_archived_subject_ids';
  static const _kUnarchivedSubjectIdsKey =
      'wannabe_unarchived_subject_ids';

  /// Subject ids the user archived but the server still lists active.
  final Set<int> archivedSubjectIds = {};

  /// Subject ids the user unarchived but the server still lists archived.
  final Set<int> unarchivedSubjectIds = {};

  /// True once the local archive overrides have been read from storage.
  final Completer<void> _archiveOverridesReady = Completer<void>();
  Future<void> get archiveOverridesReady => _archiveOverridesReady.future;

  Future<void> _saveArchiveOverrides() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_kArchivedSubjectIdsKey,
          archivedSubjectIds.map((e) => e.toString()).toList());
      await sp.setStringList(_kUnarchivedSubjectIdsKey,
          unarchivedSubjectIds.map((e) => e.toString()).toList());
    } catch (_) {}
  }

  /// Record the user's own archive choice for a subject. It flips in
  /// every list at once (Home included) and persists until a reload
  /// shows the server agreeing with it.
  void recordSubjectArchive(int id, bool archived) {
    if (archived) {
      archivedSubjectIds.add(id);
      unarchivedSubjectIds.remove(id);
    } else {
      unarchivedSubjectIds.add(id);
      archivedSubjectIds.remove(id);
    }
    unawaited(_saveArchiveOverrides());
    notifyListeners();
  }

  /// Drop overrides the freshly loaded server list now agrees with.
  /// Runs on the raw server list, not on subjects with overrides
  /// already applied, or an override would agree with itself and be
  /// deleted on the very first reload.
  void dropAgreedArchiveOverrides(List<Subject> fresh) {
    final byId = {for (final s in fresh) s.id: s.archived};
    final beforeA = archivedSubjectIds.length;
    final beforeU = unarchivedSubjectIds.length;
    archivedSubjectIds.removeWhere((id) => byId[id] == true);
    unarchivedSubjectIds.removeWhere((id) => byId[id] == false);
    if (archivedSubjectIds.length != beforeA ||
        unarchivedSubjectIds.length != beforeU) {
      unawaited(_saveArchiveOverrides());
      notifyListeners();
    }
  }

  /// Toggle a server ('YPT') task's done state via PUT
  /// /study/study-plan/rest. Optimistic: the checkbox flips at once
  /// and flips back with a notice if the server doesn't confirm.
  Future<void> toggleServerTask(YptTask task) async {
    if (_serverToggling.contains(task.id)) return;
    final target = !serverTaskDone(task);
    _serverDoneOverrides[task.id] = target;
    plannerNotice = null;
    notifyListeners();
    _serverToggling.add(task.id);
    bool ok = false;
    try {
      ok = await api.toggleStudyPlanTask(task: task, done: target);
    } catch (_) {
      ok = false;
    }
    _serverToggling.remove(task.id);
    if (!ok) {
      _serverDoneOverrides.remove(task.id);
      plannerNotice =
          'Couldn\'t update that task — it flipped back. Check connection and try again.';
      showAppNotification('Task not updated',
          'The server didn\'t confirm the change.');
    }
    notifyListeners();
  }

  /// Set a server ('YPT') task's status via PUT
  /// /study/study-plan/rest (three-state menu path). Same
  /// optimistic + rollback + notice pattern as the toggle, and the
  /// same in-flight guard set, so a menu pick and a toggle can't
  /// race on one task. The binary toggle above is left untouched.
  Future<void> setServerTaskStatus(YptTask task, int? score) async {
    if (_serverToggling.contains(task.id)) return;
    _serverStatusOverrides[task.id] = score;
    plannerNotice = null;
    notifyListeners();
    _serverToggling.add(task.id);
    bool ok = false;
    try {
      ok = await api.setStudyPlanTaskScore(task: task, score: score);
    } catch (_) {
      ok = false;
    }
    _serverToggling.remove(task.id);
    if (!ok) {
      _serverStatusOverrides.remove(task.id);
      plannerNotice =
          'Couldn\'t update that task — it flipped back. Check connection and try again.';
      showAppNotification('Task not updated',
          'The server didn\'t confirm the change.');
    }
    notifyListeners();
  }

  /// Add a task, preferring the server so it also appears in the
  /// official app. On success the profile reloads and the task shows
  /// with its YPT tag; if the server doesn't confirm, or the reload
  /// can't see the new task, it falls back to a local task plus a
  /// visible note — the task is never silently lost.
  Future<void> addTaskWithServer(
      String date, String subjectTitle, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    plannerNotice = null;
    int? subjectId;
    for (final s in user?.subjects ?? const <Subject>[]) {
      if (s.title == subjectTitle) {
        subjectId = s.id;
        break;
      }
    }
    bool serverOk = false;
    if (api.jwt != null) {
      try {
        serverOk = await api.createStudyPlanTask(
            title: trimmed, subjectId: subjectId, dateYmd: date);
      } catch (_) {
        serverOk = false;
      }
    }
    if (serverOk) {
      try {
        await reloadProfile();
      } catch (_) {}
      final found = (user?.tasks ?? const <YptTask>[])
          .any((t) => t.date == date && t.title == trimmed);
      if (found) {
        notifyListeners();
        return;
      }
      addTask(date, subjectTitle, trimmed);
      plannerNotice =
          'Created on the server, but this site\'s list couldn\'t confirm it yet — check the official app. It\'s also saved here so it isn\'t lost.';
      notifyListeners();
      return;
    }
    addTask(date, subjectTitle, trimmed);
    plannerNotice =
        'Couldn\'t reach the server — saved on this device only. It won\'t show in the official app yet.';
    notifyListeners();
  }

  List<TodoTask> tasksFor(String date) {
    final list = tasks.where((t) => t.date == date).toList();
    list.sort((a, b) {
      if (a.done != b.done) return a.done ? 1 : -1;
      final s = a.subject.compareTo(b.subject);
      return s != 0 ? s : a.text.compareTo(b.text);
    });
    return list;
  }

  void addTask(String date, String subject, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    tasks.add(TodoTask(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      date: date,
      subject: subject,
      text: trimmed,
    ));
    _saveTasks();
    notifyListeners();
  }

  void toggleTask(String id) {
    for (final t in tasks) {
      if (t.id == id) {
        t.done = !t.done;
        break;
      }
    }
    _saveTasks();
    notifyListeners();
  }

  void deleteTask(String id) {
    tasks.removeWhere((t) => t.id == id);
    _saveTasks();
    notifyListeners();
  }

  // ── Day details ──────────────────────────────────────────────────
  Future<DayDetail> fetchDay(String date, {bool force = false}) async {
    if (!force) {
      final hit = _dayCache[date];
      if (hit != null) return hit;
    }
    final raw = await api.dayLogRaw(date);
    final byId = <int, String>{
      for (final s in user?.subjects ?? const <Subject>[])
        if (s.id > 0) s.id: s.title,
    };
    final detail = DayDetail.fromRaw(date, raw,
        subjectTitleById: byId,
        archivedTitles: user?.archivedTitles ?? const {});
    _dayCache[date] = detail;
    return detail;
  }

  Future<List<GroupMember>> fetchMembersOnDate(int groupId, String date) async {
    final raw = await api.groupMembersRawOnDate(groupId, user!.countryId, date);
    return raw.map(GroupMember.fromJson).toList();
  }

  /// Group ranks route: type=day for one date, type=week anchored on
  /// the week's Monday for week aggregates.
  Future<List<GroupMember>> fetchGroupRanks(
          int groupId, String date, String type) =>
      api.groupRanks(groupId, user!.countryId, date, type);

  bool get loggedIn => user != null && api.jwt != null;
  bool get studying => activeSubject != null;

  int subjectStudyMs(Subject subject) {
    // 과목별 오늘 시간은 ls에 title로만 와서 byTitle에 있음. byId는 0 기본값이라
    // containsKey만 보면 0을 반환해 버림 → byId/byTitle 중 큰 값 채택.
    final byTitle = subjectTimes[_subjectKey(subject.title)] ?? 0;
    final byId = subject.id > 0 ? (subjectTimesById[subject.id] ?? 0) : 0;
    final best = byId > byTitle ? byId : byTitle;
    return best > 0 ? best : subject.studyMs;
  }

  static String todayStr() {
    final d = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  String _currentLogDate() {
    final date = user?.dayLog?.date.trim();
    if (date != null && date.length >= 10) return date.substring(0, 10);
    return todayStr();
  }

  Future<void> loadStats() async {
    if (user == null) return;
    statsLoading = true;
    statsErrorText = null;
    notifyListeners();
    // 각각 독립 실행 — 하나 실패해도 나머지는 로드 (랭킹이 과목시간 실패에 막히지 않게)
    try {
      await refreshSubjectTimes();
    } catch (_) {}
    try {
      myRank = await api.myCategoryRank(user!.categoryId, user!.countryId);
    } catch (e) {
      statsErrorText = 'Could not load rank: ${_readableError(e)}';
    }
    try {
      ranks = await api.categoryRanks(user!.categoryId, user!.countryId,
          date: todayStr(), type: 'day');
    } catch (_) {}
    statsLoading = false;
    notifyListeners();
  }

  Future<void> tryAutoLogin() async {
    final sp = await SharedPreferences.getInstance();
    final t = sp.getString('jwt');
    if (t == null || t.isEmpty) return;
    api.jwt = t;
    loading = true;
    notifyListeners();
    try {
      user = await api.reloadInfo();
      await _refreshSubjectTimesQuietly(); // 과목별 오늘 시간
    } catch (_) {
      api.jwt = null; // 만료/오류
      user = null;
      await sp.remove('jwt');
    }
    loading = false;
    notifyListeners();
    if (user != null) unawaited(syncPendingSessions());
  }

  Future<bool> login(String email, String password) async {
    loading = true;
    errorText = null;
    notifyListeners();
    try {
      final res = await api.signIn(email, password);
      switch (res) {
        case SignInOk(:final data):
          user = data;
          final sp = await SharedPreferences.getInstance();
          await sp.setString('jwt', data.jwt!);
          await _refreshSubjectTimesQuietly(); // 과목별 오늘 시간
          loading = false;
          notifyListeners();
          unawaited(syncPendingSessions());
          return true;
        case SignInError(:final code):
          errorText = errorMessage(code);
      }
    } catch (e) {
      errorText = 'Network error: ${_readableError(e)}';
    }
    loading = false;
    notifyListeners();
    return false;
  }

  /// 소셜 로그인 (Kakao/Naver): 시스템 브라우저 OAuth → YPT 교환 → jwt 저장.
  /// 반환: true=성공, false=실패/취소.
  Future<bool> socialLogin(SocialProvider provider) async {
    loading = true;
    errorText = null;
    notifyListeners();
    final auth = SocialAuth(provider);
    try {
      final cred = await auth.authenticate();
      final res = await api.socialSignIn(cred);
      switch (res) {
        case SignInOk(:final data):
          user = data;
          final sp = await SharedPreferences.getInstance();
          await sp.setString('jwt', data.jwt!);
          // sign-up-jwt 응답은 과목(ss)을 비워 줄 수 있어 전체 데이터로 동기화
          try {
            user = await api.reloadInfo();
          } catch (_) {}
          await _refreshSubjectTimesQuietly();
          loading = false;
          notifyListeners();
          unawaited(syncPendingSessions());
          return true;
        case SignInError(:final code):
          errorText = errorMessage(code);
      }
    } on SocialAuthCancelled {
      // 사용자가 로그인 안 함(취소/타임아웃) — 조용히 무시
    } catch (e) {
      errorText = '${provider.name} login failed: ${_readableError(e)}';
    } finally {
      auth.close();
    }
    loading = false;
    notifyListeners();
    return false;
  }

  Future<void> logout() async {
    await stopTimer(silent: true);
    final sp = await SharedPreferences.getInstance();
    await sp.remove('jwt');
    api.jwt = null;
    user = null;
    subjectTimesById = {};
    subjectTimes = {};
    myRank = null;
    ranks = [];
    groups = [];
    joinedGroups = [];
    _dayCache.clear();
    errorText = null;
    timerErrorText = null;
    statsErrorText = null;
    groupsErrorText = null;
    // The queue itself stays in SharedPreferences — its sessions belong
    // to the account and sync on the next login.
    _stopSyncRetryTimer();
    pendingSyncCount = 0;
    syncingPending = false;
    lastSyncError = null;
    notifyListeners();
  }

  Future<void> startTimer(Subject s) async {
    // Subject tap is a gesture: unlock WebAudio now so the
    // phase-end beep can sound later.
    unlockAudio();
    if (timerLoading) return;
    if (studying) await stopTimer();
    if (studying) return;
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    timerLoading = true;
    timerErrorText = null;
    notifyListeners();
    try {
      await api.studyStart(s.title, taskId: null);
      activeSubject = s;
      _startedAtMs = startedAtMs;
      _startTicker();
      if (pomoOn) _beginPhase('focus');
    } catch (e) {
      timerErrorText = 'Could not start timer: ${_readableError(e)}';
    }
    // Network is up (start just succeeded) — flush any queued stops.
    if (activeSubject != null) unawaited(syncPendingSessions());
    timerLoading = false;
    notifyListeners();
  }

  Future<void> stopTimer({bool silent = false}) async {
    if (timerLoading && !silent) return;
    final previousSubject = activeSubject;
    final started = _startedAtMs;
    if (previousSubject == null || started == null) {
      _clearTimer();
      return;
    }
    _clearTimer();
    if (!_pomoAuto) _resetPomo();
    if (silent) {
      notifyListeners();
      return;
    }
    timerLoading = true;
    timerErrorText = null;
    notifyListeners(); // 멈추는 즉시 UI 갱신 (네트워크 기다리지 않음)
    try {
      await api.studyStop(started);
      // The just-ended session changes today's logs: drop the cached
      // day detail so the next fetch (e.g. the break counter's "last
      // end") reads the fresh logs instead of a stale, pre-session
      // snapshot.
      _dayCache.remove(todayStr());
      user = await api.reloadInfo(); // 오늘 총시간 갱신
      await _refreshSubjectTimesQuietly(); // 과목별 시간 갱신
    } catch (e) {
      if (isNetworkError(e)) {
        // Hotspot dropped while stopping: the session is real, so keep
        // it. Queue the stop with the real start/stop times; it replays
        // on reconnect. The local timer stays stopped.
        final stopAtMs = DateTime.now().millisecondsSinceEpoch;
        final studyMs = stopAtMs - started;
        if (studyMs > 0) {
          await _offlineQueue.enqueue(OfflineSession(
            id: '${started}_${previousSubject.id}',
            subjectId: previousSubject.id,
            subjectTitle: previousSubject.title,
            startAtMs: started,
            stopAtMs: stopAtMs,
            studyMs: studyMs,
            createdAtMs: stopAtMs,
          ));
          pendingSyncCount = (await _offlineQueue.getPending()).length;
          lastSyncError = null;
          timerErrorText = null;
          _startSyncRetryTimer();
        } else {
          timerErrorText = 'Could not stop timer: ${_readableError(e)}';
        }
      } else {
        // Server rejected the stop — keep the old behaviour: restore the
        // timer so the user can stop again, show the server's message.
        activeSubject = previousSubject;
        _startedAtMs = started;
        _startTicker();
        timerErrorText = 'Could not stop timer: ${_readableError(e)}';
      }
    }
    timerLoading = false;
    notifyListeners();
  }

  /// Manually log a completed study session via POST /study/add.
  /// On success, clears day caches, refreshes user totals + subject times,
  /// and notifies listeners.
  Future<bool> logManualStudy({
    required String subjectTitle,
    required DateTime startAt,
    required DateTime stopAt,
  }) async {
    final ok = await api.logManualStudy(
      subjectTitle: subjectTitle,
      startAt: startAt,
      stopAt: stopAt,
    );
    if (ok) {
      _dayCache.remove(dateStr(startAt));
      _dayCache.remove(todayStr());
      try {
        user = await api.reloadInfo();
        await _refreshSubjectTimesQuietly();
      } catch (_) {}
      notifyListeners();
    }
    return ok;
  }

  void _startTicker() {
    _ticker?.cancel();
    _syncElapsed();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      _syncElapsed();
      notifyListeners();
    });
  }

  void _syncElapsed() {
    final started = _startedAtMs;
    if (started == null) {
      elapsed = Duration.zero;
      return;
    }
    final current = DateTime.now().millisecondsSinceEpoch - started;
    elapsed = Duration(milliseconds: current < 0 ? 0 : current);
  }

  void _clearTimer() {
    _ticker?.cancel();
    _ticker = null;
    activeSubject = null;
    _startedAtMs = null;
    elapsed = Duration.zero;
  }

  Future<void> _refreshSubjectTimesQuietly() async {
    try {
      await refreshSubjectTimes();
    } catch (_) {}
  }

  SubjectTimeSnapshot _mergedSubjectTimes(SubjectTimeSnapshot loggedTimes) {
    final byId = <int, int>{};
    final byTitle = <String, int>{};

    void merge(SubjectTimeSnapshot snapshot) {
      for (final entry in snapshot.byId.entries) {
        if (entry.value > 0 || !byId.containsKey(entry.key)) {
          byId[entry.key] = entry.value;
        }
      }
      for (final entry in snapshot.byTitle.entries) {
        final key = _subjectKey(entry.key);
        if (entry.value > 0 || !byTitle.containsKey(key)) {
          byTitle[key] = entry.value;
        }
      }
    }

    for (final subject in user?.subjects ?? const <Subject>[]) {
      if (subject.id > 0) byId[subject.id] = subject.studyMs;
      byTitle[_subjectKey(subject.title)] = subject.studyMs;
    }
    final dayLogTimes = user?.dayLog?.subjectTimes;
    if (dayLogTimes != null) merge(dayLogTimes);
    merge(loggedTimes);
    return SubjectTimeSnapshot(byId: byId, byTitle: byTitle);
  }

  static String _subjectKey(String title) =>
      title.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static String _readableError(Object e) {
    final text = e.toString();
    if (text.startsWith('TimeoutException')) return 'request timed out';
    // 소셜 네이티브 인터셉터 미구현 플랫폼(현재 Windows/macOS)
    if (text.startsWith('MissingPluginException')) {
      return 'not supported on this platform yet';
    }
    if (text.startsWith('Exception: ')) return text.substring(11);
    return text;
  }

  String _lastWebTitle = '';
  bool _lastCloseGuard = false;

  void _syncWebState() {
    final guard = studying;
    if (guard != _lastCloseGuard) {
      _lastCloseGuard = guard;
      setWebCloseGuard(guard);
    }

    final String title;
    if (studying && activeSubject != null) {
      final sub = activeSubject!.title;
      if (pomoOn && pomoPhase == 'focus') {
        if (pomoOvertime) {
          title = '+${_fmtTabDuration(overtimeElapsed)} OVERTIME · $sub · wannabeYPT';
        } else {
          title = '${_fmtTabDuration(phaseLeft)} Focus · $sub · wannabeYPT';
        }
      } else {
        title = '▶ ${_fmtTabDuration(elapsed)} $sub · wannabeYPT';
      }
    } else if (pomoPhase == 'break') {
      final breakType = pomoBreakLong ? 'Long Break' : 'Break';
      title = '${_fmtTabDuration(phaseLeft)} $breakType · wannabeYPT';
    } else {
      title = 'wannabeYPT';
    }

    if (title != _lastWebTitle) {
      _lastWebTitle = title;
      setWebPageTitle(title);
    }
  }

  static String _fmtTabDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _syncWebState();
  }

  @override
  void dispose() {
    setWebCloseGuard(false);
    setWebPageTitle('wannabeYPT');
    _ticker?.cancel();
    _syncRetryTimer?.cancel();
    api.close();
    super.dispose();
  }
}

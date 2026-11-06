import 'package:flutter/material.dart';

/// YPT API 응답 모델. 키 해독은 RE 스펙(key_dictionary) 기반.
/// 응답은 축약 키를 쓴다: s=success, jwt=토큰, ss=과목배열, dl=오늘로그, p=프로필.

int intValue(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

int? intOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String stringValue(Object? value) => value?.toString() ?? '';

String? firstStringValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null) return stringValue(value);
  }
  return null;
}

int firstIntValue(Map<String, dynamic> json, List<String> keys,
    {int fallback = 0}) {
  for (final key in keys) {
    final value = intOrNull(json[key]);
    if (value != null) return value;
  }
  return fallback;
}

/// Normalized subject title for archived matching: case-insensitive,
/// collapsed whitespace. Mirrors AppState._subjectKey.
String normSubjectTitle(String t) =>
    t.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

bool boolValue(Object? value, {bool fallback = false}) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return fallback;
}

List<Map<String, dynamic>> mapListValue(Object? value) {
  final list = value is List ? value : const [];
  return list.whereType<Map<String, dynamic>>().toList();
}

SubjectTimeSnapshot subjectTimeSnapshotFromJson(
  Map<String, dynamic> json, {
  Map<int, String> titleByIndex = const {},
}) {
  final byId = <int, int>{};
  final byTitle = <String, int>{};

  void addEntries(Object? value) {
    for (final entry in mapListValue(value)) {
      final studyMs = _studyMsFromLog(entry);
      if (studyMs <= 0) continue;
      final id = _subjectIdFromLog(entry);
      final title = _subjectTitleFromLog(entry, titleByIndex);
      if (id != null && id > 0) byId[id] = (byId[id] ?? 0) + studyMs;
      if (title != null && title.trim().isNotEmpty) {
        byTitle[title] = (byTitle[title] ?? 0) + studyMs;
      }
    }
  }

  addEntries(json['ls']);
  addEntries(json['ss']);
  addEntries(json['ts']);
  return SubjectTimeSnapshot(byId: byId, byTitle: byTitle);
}

int? _subjectIdFromLog(Map<String, dynamic> json) {
  final direct = intOrNull(json['si']) ??
      intOrNull(json['sid']) ??
      intOrNull(json['subjectId']) ??
      intOrNull(json['subjectID']) ??
      intOrNull(json['id']);
  if (direct != null) return direct;
  final sb = json['sb'];
  return sb is String ? null : intOrNull(sb);
}

String? _subjectTitleFromLog(
  Map<String, dynamic> json,
  Map<int, String> titleByIndex,
) {
  final direct = firstStringValue(json, const [
    'subject',
    'subjectName',
    'subjectTitle',
    'title',
    'tt',
    't',
  ]);
  if (direct != null && direct.trim().isNotEmpty) return direct;
  final sb = json['sb'];
  if (sb is String && sb.trim().isNotEmpty) return sb;
  final index = intOrNull(json['sbi']) ??
      intOrNull(json['subjectIndex']) ??
      intOrNull(json['subjectBookIndex']) ??
      intOrNull(sb);
  if (index != null) return titleByIndex[index];
  return null;
}

int _studyMsFromLog(Map<String, dynamic> json) {
  final direct = firstIntValue(json, const [
    'sm',
    'studyMs',
    'studyMS',
    'studyTime',
    'todayStudyMs',
    'todayStudyMS',
    'todayStudyTime',
    'todayMs',
    'durationMs',
    'duration',
    'ms',
    'sd',
  ]);
  if (direct > 0) return direct;

  final start = firstIntValue(json, const [
    'startedAt',
    'startAt',
    'start',
    'st',
    'from',
  ]);
  final end = firstIntValue(json, const [
    'endedAt',
    'endAt',
    'end',
    'et',
    'to',
  ]);
  final elapsed = end - start;
  if (start > 0 && elapsed > 0 && elapsed <= 24 * 60 * 60 * 1000) {
    return elapsed;
  }
  return 0;
}

class Subject {
  final int id;
  final String title; // tt
  final int studyMs; // sm — 오늘 이 과목 공부 ms
  final int order; // or
  final int colorValue; // co — ARGB int
  final bool archived; // dl: 보관 여부로 추정(미확정). dl이 true일 때만 숨김 → 안전

  Subject({
    required this.id,
    required this.title,
    required this.studyMs,
    required this.order,
    required this.colorValue,
    required this.archived,
  });

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: firstIntValue(j, const [
          'id',
          'sid',
          'subjectId',
          'subjectID',
          'si',
        ]),
        title: firstStringValue(j, const [
              'tt',
              't',
              'title',
              'subject',
              'subjectName',
              'subjectTitle',
            ]) ??
            '',
        studyMs: firstIntValue(j, const [
          'sm',
          'studyMs',
          'studyMS',
          'studyTime',
          'todayStudyMs',
          'todayStudyMS',
          'todayStudyTime',
          'todayMs',
          'totalStudyMs',
          'ms',
        ]),
        order: intValue(j['or']),
        colorValue: firstIntValue(j, const ['co', 'c'], fallback: 0xFF888888),
        archived: boolValue(j['dl']),
      );

  Color get color => Color(colorValue == 0 ? 0xFF888888 : colorValue);
}

class DayLog {
  final int studyMs; // sm
  final int restMs; // rm
  final int maxStudyMs; // mm
  final int addedMs; // ad
  final String date; // dt
  final SubjectTimeSnapshot subjectTimes;

  DayLog({
    required this.studyMs,
    required this.restMs,
    required this.maxStudyMs,
    required this.addedMs,
    required this.date,
    required this.subjectTimes,
  });

  factory DayLog.fromJson(Map<String, dynamic> j) => DayLog(
        studyMs: intValue(j['sm']),
        restMs: intValue(j['rm']),
        maxStudyMs: intValue(j['mm']),
        addedMs: intValue(j['ad']),
        date: stringValue(j['dt']),
        subjectTimes: subjectTimeSnapshotFromJson(j),
      );
}

class SubjectTimeSnapshot {
  final Map<int, int> byId;
  final Map<String, int> byTitle;

  const SubjectTimeSnapshot({
    this.byId = const {},
    this.byTitle = const {},
  });
}

/// 로그인/리로드 응답 묶음 (sign-in-jwt, reload/info 공통 구조)
/// A task (to-do) from reload/info's `tks` array — decoded from
/// real samples (2026-10-21): {id, t:title, sa:day (ISO, UTC
/// midnight), s:status (null = open, 3 = done — confirmed by a
/// before/after diff: ticking the sample task done flipped only
/// s → 3 and bumped ua), d:? (stayed null when done), u:userId,
/// sd:subject id, o:order, ca/ua:created/updated, ad:?, dl:deleted}.
/// Server score for half-done tasks (official-app parity). Score 1
/// is PROVEN not half-done: the site showed a triangle for 1 while
/// the official app showed a cross (user-verified 2026-10-29). The
/// next candidate is 2, on a 1/2/3 scale theory (1 = not done,
/// 2 = half-done, 3 = done) — which also explains why Desky's
/// "done = 1" shows as not-done in the app. Still UNPROVEN until
/// live verification shows a triangle in the app — keep every
/// half-done read/write going through this constant.
const int kTaskHalfDoneScore = 2;

class YptTask {
  final int id;
  final String title; // t
  final String date; // sa → yyyy-MM-dd
  final int subjectId; // sd
  final int status; // s — 3 means done, 2 is the half-done candidate, 1 means not done in the official app
  final bool deleted; // dl
  final int order; // o

  const YptTask({
    required this.id,
    required this.title,
    required this.date,
    required this.subjectId,
    required this.status,
    required this.deleted,
    required this.order,
  });

  bool get done => status == 3;

  factory YptTask.fromJson(Map<String, dynamic> j) {
    final sa = stringValue(j['sa']);
    return YptTask(
      id: intValue(j['id']),
      title: stringValue(j['t']),
      date: sa.length >= 10 ? sa.substring(0, 10) : sa,
      subjectId: intValue(j['sd']),
      status: intValue(j['s']),
      deleted: boolValue(j['dl']),
      order: intValue(j['o']),
    );
  }
}

class UserData {
  final String? jwt; // jwt (로그인 시에만)
  final String nickname; // n
  final String category; // ct (예: HS11)
  final String? email; // e
  final List<Subject> subjects; // ss (archived ones filtered out)
  final Set<String> archivedTitles; // normalized titles of dl-flagged
  // subjects in ss — kept so stats can hide their historical names.
  final DayLog? dayLog; // dl
  final int categoryId; // ci
  final int countryId; // coid
  final List<YptTask> tasks; // tks

  UserData({
    this.jwt,
    required this.nickname,
    required this.category,
    this.email,
    required this.subjects,
    this.archivedTitles = const {},
    this.dayLog,
    this.categoryId = 0,
    this.countryId = 0,
    this.tasks = const [],
  });

  factory UserData.fromJson(Map<String, dynamic> j) {
    final ssList = j['ss'] is List ? j['ss'] as List : const [];
    final allSubjects = ssList
        .whereType<Map<String, dynamic>>()
        .map(Subject.fromJson)
        .toList();
    final archivedTitles = <String>{
      for (final s in allSubjects)
        if (s.archived && s.title.trim().isNotEmpty)
          normSubjectTitle(s.title),
    };
    final subjects = allSubjects.where((s) => !s.archived).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    DayLog? dl;
    if (j['dl'] is Map<String, dynamic>) dl = DayLog.fromJson(j['dl']);
    final tksList = j['tks'] is List ? j['tks'] as List : const [];
    final tasks = tksList
        .whereType<Map<String, dynamic>>()
        .map(YptTask.fromJson)
        .where((t) => !t.deleted && t.title.isNotEmpty)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return UserData(
      jwt: j['jwt'] == null ? null : stringValue(j['jwt']),
      nickname: stringValue(j['n']),
      category: stringValue(j['ct']),
      email: j['e'] == null ? null : stringValue(j['e']),
      subjects: subjects,
      archivedTitles: archivedTitles,
      dayLog: dl,
      categoryId: intValue(j['ci']),
      countryId: intValue(j['coid']),
      tasks: tasks,
    );
  }
}

/// 카테고리 랭킹 멤버 (/logs/category/member/ranks 의 ms 항목)
class RankMember {
  final String nickname; // n
  final int userId; // ud
  final int studyMs; // dl.sm
  final int studiconId; // si

  RankMember({
    required this.nickname,
    required this.userId,
    required this.studyMs,
    required this.studiconId,
  });

  factory RankMember.fromJson(Map<String, dynamic> j) {
    // 공부시간: dl.sm 우선, 없으면 sd 폴백 (둘 다 study ms 후보)
    int sm = 0;
    if (j['dl'] is Map<String, dynamic>) sm = intValue(j['dl']['sm']);
    if (sm <= 0) sm = intValue(j['sd']);
    return RankMember(
      nickname: stringValue(j['n']),
      userId: intValue(j['ud']),
      studyMs: sm,
      studiconId: intValue(j['si']),
    );
  }
}

/// 스터디 그룹 (/group/list-new-2, /group/groups/v2 의 gs 항목)
class Group {
  final int id; // id (멤버 API가 쓰는 groupID. gd는 별개 id이므로 쓰지 않음)
  final String title; // t
  final String category; // c
  final String owner; // on (방장 닉네임)
  final String slogan; // sn
  final int memberCount; // mc

  Group({
    required this.id,
    required this.title,
    required this.category,
    required this.owner,
    required this.slogan,
    required this.memberCount,
  });

  factory Group.fromJson(Map<String, dynamic> j) => Group(
        id: intValue(j['id'] ?? j['gd']), // groupID = id (멤버 API가 쓰는 값)
        title: stringValue(j['t']),
        category: stringValue(j['c']),
        owner: stringValue(j['on']),
        slogan: stringValue(j['sn']),
        memberCount: intValue(j['mc']),
      );
}

/// 그룹 멤버 (/logs/group/members/v2 의 ms 항목)
/// Studicon doll CDN image, official YPT style:
/// https://alicdn.tgclab.com/sc.v2/<id>/<pose>.png
String studiconUrl(int studiconId, String poseFile) =>
    'https://alicdn.tgclab.com/sc.v2/$studiconId/$poseFile';

/// Doll pose file for a study state, following the official app's
/// time thresholds: under 1h normal, then sweat (1/2/3h), smoke
/// (4/5h), ignite (6/7h), fire (8h), explosion (10h+). Not studying
/// always shows the normal pose.
String studiconPoseFile({required bool studying, required int studyMs}) {
  if (!studying) return 'normal1.png';
  if (studyMs >= 36000000) return 'explosion1.png'; // >= 10h
  if (studyMs >= 28800000) return 'fire1.png'; // >= 8h
  if (studyMs >= 25200000) return 'ignite2.png'; // >= 7h
  if (studyMs >= 21600000) return 'ignite1.png'; // >= 6h
  if (studyMs >= 18000000) return 'smoke2.png'; // >= 5h
  if (studyMs >= 14400000) return 'smoke1.png'; // >= 4h
  if (studyMs >= 10800000) return 'sweat3.png'; // >= 3h
  if (studyMs >= 7200000) return 'sweat2.png'; // >= 2h
  if (studyMs >= 3600000) return 'sweat1.png'; // >= 1h
  return 'normal1.png';
}

class GroupMember {
  final int userId; // ud
  final String nickname; // n
  final String category; // ct
  final int studyMs; // dl.sm — 오늘 공부시간 (완료된 세션 합계)
  final bool studying; // dl.is — 서버의 실시간 공부 중 플래그 (im은 전원 true라 무의미)
  final DateTime? startedAt; // dl.st — 최근 세션 시작 (UTC)
  final DateTime? stoppedAt; // dl.sp — 최근 세션 종료 (UTC)
  final int studiconId; // si — top-level when the payload carries it, else 0 (no doll)

  GroupMember({
    required this.userId,
    required this.nickname,
    required this.category,
    required this.studyMs,
    required this.studying,
    this.startedAt,
    this.stoppedAt,
    this.studiconId = 0,
  });

  factory GroupMember.fromJson(Map<String, dynamic> j) {
    int sm = 0;
    bool liveFlag = false;
    DateTime? st;
    DateTime? sp;
    var si = intValue(j['si']);
    if (j['dl'] is Map<String, dynamic>) {
      final dl = j['dl'] as Map<String, dynamic>;
      sm = intValue(dl['sm']);
      liveFlag = boolValue(dl['is']);
      st = DateTime.tryParse(stringValue(dl['st']));
      sp = DateTime.tryParse(stringValue(dl['sp']));
      if (si <= 0) si = intValue(dl['si']);
    }
    return GroupMember(
      userId: intValue(j['ud']),
      nickname: stringValue(j['n']),
      category: stringValue(j['ct']),
      studyMs: sm,
      studying: liveFlag,
      startedAt: st,
      stoppedAt: sp,
      studiconId: si,
    );
  }

  /// Live right now: server flag set, and the last session has not
  /// already been closed (sp after st means it ended).
  bool get isLive {
    if (!studying) return false;
    final st = startedAt, sp = stoppedAt;
    if (st != null && sp != null && sp.isAfter(st)) return false;
    return true;
  }

  /// What the official app shows: completed total + the running
  /// session's elapsed time (now − session start).
  int liveDisplayMs(DateTime now) {
    if (!isLive) return studyMs;
    final st = startedAt;
    if (st == null) return studyMs;
    final extra = now.difference(st).inMilliseconds;
    if (extra <= 0 || extra > 24 * 3600 * 1000) return studyMs;
    return studyMs + extra;
  }
}

/// 로그인 결과
sealed class SignInResult {}

class SignInOk extends SignInResult {
  final UserData data;
  SignInOk(this.data);
}

class SignInError extends SignInResult {
  final String code; // c — 113=계정/비번오류 등
  SignInError(this.code);
}


/// A time value from the API: epoch ms int, epoch seconds, numeric
/// string, or an ISO-8601 string. Returns null when unparseable.
DateTime? parseLogTime(Object? v) {
  if (v == null) return null;
  if (v is num) {
    if (v <= 0) return null;
    final ms = v < 100000000000 ? (v * 1000).toInt() : v.toInt();
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
  var s = v.toString().trim();
  if (s.isEmpty) return null;
  final asInt = int.tryParse(s);
  if (asInt != null) return parseLogTime(asInt);
  // The API sometimes uses a space instead of 'T' ("2026-09-06 07:19:22…").
  if (s.contains(' ') && !s.contains('T')) {
    s = s.replaceFirst(' ', 'T');
  }
  return DateTime.tryParse(s);
}

/// One timed entry from a day log — a single study/rest session.
/// Parsed leniently from the raw /logs/day payload; the raw entry is
/// kept so the exact server shape stays visible while it is pinned down.
class DaySession {
  final int? id;
  final String subject;
  final DateTime start;
  final DateTime end;
  final String kind; // 'study' | 'rest' | 'other'
  final Map<String, dynamic> raw;

  const DaySession({
    this.id,
    required this.subject,
    required this.start,
    required this.end,
    required this.kind,
    required this.raw,
  });

  int get durationMs => end.difference(start).inMilliseconds;

  static DaySession? fromEntry(
    Map<String, dynamic> e, {
    Map<int, String> titleByIndex = const {},
    Map<int, String> subjectTitleById = const {},
  }) {
    // The real YPT shapes (confirmed from a live payload):
    //  study: {sb: 'Physics', sm: <duration ms>, st: <start ISO>, ia, ad}
    //         — start + duration, no end, no own id.
    //  rest:  {sp: <end ISO>, rm: <duration ms>, tg: 'meals'|'rest'|…}
    //         — end + duration.
    final durMs = intOrNull(e['sm']);
    final restMs = intOrNull(e['rm']);
    final stVal = parseLogTime(
        e['st'] ?? e['startedAt'] ?? e['startAt'] ?? e['start'] ?? e['from']);
    final spVal = parseLogTime(
        e['sp'] ?? e['et'] ?? e['endedAt'] ?? e['endAt'] ?? e['end'] ?? e['to']);
    DateTime? start;
    DateTime? end;
    var isRest = false;
    if (stVal != null && durMs != null && durMs > 0 && spVal == null) {
      start = stVal;
      end = stVal.add(Duration(milliseconds: durMs));
    } else if (spVal != null && restMs != null && restMs > 0 && stVal == null) {
      end = spVal;
      start = spVal.subtract(Duration(milliseconds: restMs));
      isRest = true;
    } else if (stVal != null && spVal != null) {
      start = stVal;
      end = spVal;
    }
    if (start == null || end == null || !end.isAfter(start)) return null;
    if (end.difference(start).inHours > 24) return null;

    var label = firstStringValue(e, const [
      'subject',
      'subjectName',
      'subjectTitle',
      'title',
      'tt',
      't',
    ]);
    if (label == null || label.trim().isEmpty) {
      // study entries carry the subject in 'sb' as a plain string
      final sbv = e['sb'];
      if (sbv is String && sbv.trim().isNotEmpty) label = sbv;
    }
    if (label == null || label.trim().isEmpty) {
      final tag = firstStringValue(e, const ['tg', 'tag', 'hashtag']);
      if (tag != null && tag.trim().isNotEmpty) {
        label = tag.startsWith('#') ? tag : '# $tag';
      }
    }
    if (label == null || label.trim().isEmpty) {
      final sb = e['sb'];
      final idx = intOrNull(e['sbi']) ?? intOrNull(sb);
      if (idx != null && titleByIndex[idx] != null) label = titleByIndex[idx];
    }
    if (label == null || label.trim().isEmpty) {
      final sid = intOrNull(e['si']) ??
          intOrNull(e['sid']) ??
          intOrNull(e['subjectId']) ??
          intOrNull(e['subjectID']);
      if (sid != null && subjectTitleById[sid] != null) {
        label = subjectTitleById[sid];
      }
    }
    label = (label == null || label.trim().isEmpty)
        ? (isRest ? 'Rest' : 'Session')
        : label.trim();

    var kind = 'study';
    if (isRest) {
      kind = 'rest';
    } else if (label.startsWith('#') ||
        label.toLowerCase() == 'other') {
      kind = 'other';
    }

    return DaySession(
      id: intOrNull(e['id']) ?? intOrNull(e['lid']) ?? intOrNull(e['logId']),
      subject: label,
      start: start,
      end: end,
      kind: kind,
      raw: e,
    );
  }
}

/// A full day's data from GET /logs/day — totals plus timed sessions.
class DayDetail {
  final String date; // yyyy-MM-dd
  final int studyMs; // dl.sm
  final int restMs; // dl.rm
  final int maxMs; // dl.mm — longest single focus
  final int addedMs; // dl.ad — manually added time
  final SubjectTimeSnapshot subjects;
  final List<DaySession> sessions; // sorted by start
  final DateTime? dlStart; // dl.st — the day's own start stamp
  final DateTime? dlEnd; // dl.sp — the day's own end stamp
  final Map<String, dynamic> raw;

  const DayDetail({
    required this.date,
    required this.studyMs,
    required this.restMs,
    required this.maxMs,
    required this.addedMs,
    required this.subjects,
    required this.sessions,
    this.dlStart,
    this.dlEnd,
    required this.raw,
  });

  int get totalMs => studyMs + addedMs;

  DateTime? get dayStart =>
      dlStart ?? (sessions.isEmpty ? null : sessions.first.start);
  DateTime? get dayEnd =>
      dlEnd ?? (sessions.isEmpty ? null : sessions.last.end);

  factory DayDetail.fromRaw(
    String date,
    Map<String, dynamic> raw, {
    Map<int, String> subjectTitleById = const {},
    Set<String> archivedTitles = const {},
  }) {
    final dl = raw['dl'] is Map<String, dynamic>
        ? raw['dl'] as Map<String, dynamic>
        : const <String, dynamic>{};

    // Archived subjects must not show their names in stats: the
    // official app hides archived subjects, but day payloads still
    // carry their historical entries (direct titles and subject-book
    // indices). Collect them here — from this payload's subject book
    // (dl-flagged entries) plus the caller's profile set — and hide
    // only their names below. Day totals are untouched.
    // NOTE: titleByIndex stays positional (every entry, archived or
    // not) so index lookups never shift onto the wrong title.
    final archived = <String>{...archivedTitles};
    final titleByIndex = <int, String>{};
    final sbs = mapListValue(raw['sbs']);
    for (var i = 0; i < sbs.length; i++) {
      final t = firstStringValue(sbs[i], const ['t', 'title']);
      if (t != null && t.trim().isNotEmpty) {
        titleByIndex[i] = t;
        if (boolValue(sbs[i]['dl'])) archived.add(normSubjectTitle(t));
      }
    }

    final byId = <int, int>{};
    final byTitle = <String, int>{};
    void merge(SubjectTimeSnapshot s) {
      s.byId.forEach((k, v) => byId[k] = (byId[k] ?? 0) + v);
      s.byTitle.forEach((k, v) => byTitle[k] = (byTitle[k] ?? 0) + v);
    }

    if (dl.isNotEmpty) {
      merge(subjectTimeSnapshotFromJson(dl, titleByIndex: titleByIndex));
    }
    merge(subjectTimeSnapshotFromJson(raw, titleByIndex: titleByIndex));

    // Timed sessions: scan the entry lists the day payload carries.
    final sessions = <DaySession>[];
    final seen = <String>{};
    void scan(Object? list) {
      for (final e in mapListValue(list)) {
        final s = DaySession.fromEntry(
          e,
          titleByIndex: titleByIndex,
          subjectTitleById: subjectTitleById,
        );
        if (s == null) continue;
        final key =
            '${s.start.millisecondsSinceEpoch}|${s.end.millisecondsSinceEpoch}|${s.subject}';
        if (seen.add(key)) sessions.add(s);
      }
    }

    scan(dl['ls']);
    scan(raw['ls']);
    scan(dl['rs']);
    scan(raw['rs']);
    scan(dl['as']);
    scan(dl['ts']);
    scan(raw['ts']);
    sessions.sort((a, b) => a.start.compareTo(b.start));

    if (archived.isNotEmpty) {
      // Hide archived names from the per-subject breakdown…
      byTitle.removeWhere((title, _) => archived.contains(normSubjectTitle(title)));
      // …and from the timeline (the block stays, under the generic
      // label the app already uses for untitled sessions).
      for (var i = 0; i < sessions.length; i++) {
        final s = sessions[i];
        if (s.kind == 'study' && archived.contains(normSubjectTitle(s.subject))) {
          sessions[i] = DaySession(
            id: s.id,
            subject: 'Session',
            start: s.start,
            end: s.end,
            kind: s.kind,
            raw: s.raw,
          );
        }
      }
    }

    // dl.st / dl.sp are the day's own start/end stamps — trust them
    // only when they look sane (off days carry a 2019 sentinel).
    DateTime? sane(Object? v) {
      final t = parseLogTime(v);
      if (t == null) return null;
      if (t.year < 2020 || t.year > 2100) return null;
      return t;
    }

    var dlStart = sane(dl['st']);
    var dlEnd = sane(dl['sp']);
    if (dlStart != null && dlEnd != null && dlEnd.isBefore(dlStart)) {
      dlStart = null;
      dlEnd = null;
    }

    return DayDetail(
      date: date,
      studyMs: intValue(dl['sm'] ?? raw['sm']),
      restMs: intValue(dl['rm'] ?? raw['rm']),
      maxMs: intValue(dl['mm'] ?? raw['mm']),
      addedMs: intValue(dl['ad'] ?? raw['ad']),
      subjects: SubjectTimeSnapshot(byId: byId, byTitle: byTitle),
      sessions: sessions,
      dlStart: dlStart,
      dlEnd: dlEnd,
      raw: raw,
    );
  }
}

/// A planner to-do. Stored on the device for now; the entry keeps a
/// server-shaped id slot so a tasks endpoint can adopt it later.
class TodoTask {
  final String id;
  final String date; // yyyy-MM-dd
  final String subject; // '' = general
  final String text;
  bool done;

  TodoTask({
    required this.id,
    required this.date,
    required this.subject,
    required this.text,
    this.done = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'subject': subject,
        'text': text,
        'done': done,
      };

  factory TodoTask.fromJson(Map<String, dynamic> j) => TodoTask(
        id: stringValue(j['id']),
        date: stringValue(j['date']),
        subject: stringValue(j['subject']),
        text: stringValue(j['text']),
        done: boolValue(j['done']),
      );
}

/// A YPT notification, parsed leniently (Desky's shape: i1/i2/i3
/// text parts, nt/type, c/created_at, ir/is_read, id).
class NotificationItem {
  final int id;
  final String title;
  final String message;
  final String type;
  final DateTime createdAt;
  final bool isRead;

  const NotificationItem({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    this.isRead = false,
  });

  factory NotificationItem.fromJson(Map<String, dynamic> j) {
    final rawI1 = (j['i1'] ?? j['title'] ?? j['t'] ?? '').toString().trim();
    final rawI2 = (j['i2'] ?? '').toString().trim();
    final rawI3 = (j['i3'] ?? '').toString().trim();
    final rawMsg = (j['content'] ?? j['message'] ?? j['body'] ?? j['m'] ?? '')
        .toString()
        .trim();
    String title;
    String message;
    if (rawI2.isNotEmpty && rawI3.isNotEmpty) {
      title = rawI1.isNotEmpty ? '$rawI1 • $rawI2' : rawI2;
      message = rawI3;
    } else if (rawI1.isNotEmpty && rawI2.isNotEmpty) {
      title = rawI1;
      message = rawI2;
    } else if (rawI1.isNotEmpty && rawMsg.isNotEmpty) {
      title = rawI1;
      message = rawMsg;
    } else if (rawMsg.isNotEmpty) {
      title = rawI1.isNotEmpty ? rawI1 : 'YPT notification';
      message = rawMsg;
    } else {
      title = rawI1.isNotEmpty ? rawI1 : 'YPT notification';
      message = rawI2.isNotEmpty ? rawI2 : 'No details';
    }
    final type = (j['nt'] ?? j['type'] ?? j['tp'] ?? 'info').toString();
    final dateStr = j['c'] ?? j['created_at'];
    final createdAt = dateStr != null
        ? DateTime.tryParse(dateStr.toString()) ?? DateTime.now()
        : DateTime.now();
    final isRead = boolValue(j['ir']) ||
        boolValue(j['is_read']) ||
        boolValue(j['read']);
    return NotificationItem(
      id: intValue(j['id']),
      title: title,
      message: message,
      type: type,
      createdAt: createdAt,
      isRead: isRead,
    );
  }
}

/// One weekly timetable block (Desky's shape). Day convention is
/// assumed 1 = Monday .. 7 = Sunday — unproven live.
class TimetableBlock {
  final int id;
  final int subjectId;
  final String subjectTitle;
  final int colorInt;
  final int dayOfWeek;
  final int startHour;
  final int endHour;

  const TimetableBlock({
    required this.id,
    required this.subjectId,
    required this.subjectTitle,
    required this.colorInt,
    required this.dayOfWeek,
    required this.startHour,
    required this.endHour,
  });

  factory TimetableBlock.fromJson(Map<String, dynamic> j) =>
      TimetableBlock(
        id: intValue(j['id']),
        subjectId:
            firstIntValue(j, const ['subject_id', 'subjectId']),
        subjectTitle:
            firstStringValue(j, const ['subject_title', 'subjectTitle']) ??
                'Subject',
        colorInt: firstIntValue(j, const ['color', 'colorInt'],
            fallback: 4292557552),
        dayOfWeek:
            firstIntValue(j, const ['day_of_week', 'dayOfWeek'], fallback: 1),
        startHour:
            firstIntValue(j, const ['start_hour', 'startHour'], fallback: 8),
        endHour:
            firstIntValue(j, const ['end_hour', 'endHour'], fallback: 10),
      );
}

/// Resolve a chat media path to a full URL: absolute URLs pass
/// through, relative paths hang off the YPT media CDN (same host the
/// safe batch uses for studicon dolls).
String chatMediaUrl(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  if (raw.startsWith('http')) return raw;
  final path = raw.startsWith('/') ? raw : '/$raw';
  return 'https://alicdn.tgclab.com$path';
}

/// One group chat message (GET /chat/group/messages, POST
/// /chat/group/message — both captured in the Desky spec). The list
/// item shape itself was never captured (the spec example is empty),
/// so fromJson covers Desky's fallback keys. NOTE: `did` is a
/// composite string (groupId_idx_timestamp) in the send response —
/// it is NEVER a studicon id, so it is never parsed as one, or
/// avatars break until reload.
class ChatMessage {
  final int id; // idx/id
  final int senderId; // uid/ud
  final String senderName; // nn/n
  final int studiconId; // sd/st/si only — never did
  final String text; // msg/m/text
  final String? photoUrl; // photo (CDN-resolved)
  final String? stickerUrl; // stickerUrl/sticker
  final String? imageUrl; // img/imageUrl (CDN-resolved)
  final String? thumbUrl; // th/thumbUrl (CDN-resolved)
  final DateTime sentAt; // ts (float seconds or ms)/ca/createdAt
  final bool isNotice; // isNotice/sn
  final Map<String, List<int>> reactions; // reactions/rc: emoji -> user ids

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.studiconId,
    required this.text,
    this.photoUrl,
    this.stickerUrl,
    this.imageUrl,
    this.thumbUrl,
    required this.sentAt,
    this.isNotice = false,
    this.reactions = const {},
  });

  bool get isSticker => stickerUrl != null && stickerUrl!.isNotEmpty;
  bool get isImage =>
      !isSticker &&
      ((imageUrl != null && imageUrl!.isNotEmpty) ||
          (photoUrl != null && photoUrl!.isNotEmpty));
  String? get displayImageUrl => imageUrl ?? photoUrl;

  ChatMessage copyWith({
    int? id,
    int? senderId,
    String? senderName,
    int? studiconId,
    String? text,
    String? photoUrl,
    String? stickerUrl,
    String? imageUrl,
    String? thumbUrl,
    DateTime? sentAt,
    bool? isNotice,
    Map<String, List<int>>? reactions,
  }) =>
      ChatMessage(
        id: id ?? this.id,
        senderId: senderId ?? this.senderId,
        senderName: senderName ?? this.senderName,
        studiconId: studiconId ?? this.studiconId,
        text: text ?? this.text,
        photoUrl: photoUrl ?? this.photoUrl,
        stickerUrl: stickerUrl ?? this.stickerUrl,
        imageUrl: imageUrl ?? this.imageUrl,
        thumbUrl: thumbUrl ?? this.thumbUrl,
        sentAt: sentAt ?? this.sentAt,
        isNotice: isNotice ?? this.isNotice,
        reactions: reactions ?? this.reactions,
      );

  static DateTime _parseTime(Object? raw) {
    if (raw is num) {
      // Float seconds (captured: 1786320605.48488) or ms.
      return raw > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(raw.toInt())
          : DateTime.fromMillisecondsSinceEpoch((raw * 1000).toInt());
    }
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    return DateTime.now();
  }

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    String? photo;
    final photoRaw = j['photo'];
    if (photoRaw != null && photoRaw.toString().isNotEmpty) {
      photo = chatMediaUrl(photoRaw.toString());
    }
    final rawImg = j['img'] ?? j['imageUrl'];
    final image = rawImg != null && rawImg.toString().isNotEmpty
        ? chatMediaUrl(rawImg.toString())
        : null;
    final rawThumb = j['th'] ?? j['thumbUrl'];
    final thumb = rawThumb != null && rawThumb.toString().isNotEmpty
        ? chatMediaUrl(rawThumb.toString())
        : null;
    final stickerRaw = j['stickerUrl'] ?? j['sticker'];
    final sticker = stickerRaw != null && stickerRaw.toString().isNotEmpty
        ? chatMediaUrl(stickerRaw.toString())
        : null;
    final reactionsMap = <String, List<int>>{};
    final rawReactions = j['reactions'] ?? j['rc'];
    if (rawReactions is Map) {
      rawReactions.forEach((k, v) {
        if (v is List) {
          reactionsMap[k.toString()] =
              v.map((e) => intValue(e)).toList();
        }
      });
    }
    return ChatMessage(
      id: firstIntValue(j, const ['idx', 'id'],
          fallback: DateTime.now().millisecondsSinceEpoch),
      senderId: firstIntValue(j, const ['uid', 'ud']),
      senderName:
          firstStringValue(j, const ['nn', 'n']) ?? 'Unknown',
      // sd/st/si only — did is a composite string, never an id.
      studiconId: firstIntValue(j, const ['sd', 'st', 'si']),
      text: firstStringValue(j, const ['msg', 'm', 'text']) ?? '',
      photoUrl: photo,
      stickerUrl: sticker,
      imageUrl: image,
      thumbUrl: thumb,
      sentAt: _parseTime(j['ts'] ?? j['ca'] ?? j['createdAt']),
      isNotice: boolValue(j['isNotice'] ?? j['sn']),
      reactions: reactionsMap,
    );
  }
}

/// Result of a chat list fetch, carrying diagnostics so an empty
/// list is never silent: if the server's shape differs from every
/// tried key, the UI can show the raw top-level keys instead of
/// guessing further.
class ChatListResult {
  final List<ChatMessage> messages;
  final List<String> rawKeys;
  final String? serverMessage;
  final bool httpOk;

  const ChatListResult({
    required this.messages,
    required this.rawKeys,
    this.serverMessage,
    required this.httpOk,
  });
}

/// One official YPT sticker set (GET /chat/sticker/sets — captured
/// spec shape: {r: [{id, code, title, title_en, cover_image,
/// items: [{item_id, is_active, order}]}]}). Sticker URLs are
/// derived from items[].item_id: item ids are bare per-set
/// filenames ("1.png"), so the set code scopes the CDN path.
class StickerItem {
  final String itemId;
  final String url;

  const StickerItem({required this.itemId, required this.url});
}

class StickerSet {
  final int id;
  final String code;
  final String title;
  final String coverUrl;
  final List<StickerItem> items;

  const StickerSet({
    required this.id,
    required this.code,
    required this.title,
    required this.coverUrl,
    required this.items,
  });

  static String _stickerUrl(String code, String file) =>
      'https://alicdn.tgclab.com/sticker/$code/$file';

  factory StickerSet.fromJson(Map<String, dynamic> j) {
    final code = stringValue(j['code']);
    final itemsRaw = j['items'] is List ? j['items'] as List : const [];
    final withOrder = <(int, StickerItem)>[];
    for (final raw in itemsRaw) {
      if (raw is! Map<String, dynamic>) continue;
      // Inactive items are not shown; a missing flag defaults to active.
      if (raw['is_active'] == false) continue;
      final itemId = stringValue(raw['item_id']);
      if (itemId.isEmpty) continue;
      withOrder.add((intValue(raw['order']),
          StickerItem(itemId: itemId, url: _stickerUrl(code, itemId))));
    }
    withOrder.sort((a, b) => a.$1.compareTo(b.$1));
    final items = withOrder.map((e) => e.$2).toList();
    final cover = stringValue(j['cover_image']);
    return StickerSet(
      id: intValue(j['id']),
      code: code,
      title: firstStringValue(j, const ['title_en', 'title']) ?? 'Stickers',
      coverUrl: cover.isEmpty ? '' : _stickerUrl(code, cover),
      items: items,
    );
  }
}

/// Flashcards / Books (Desky parity, built 2026-11-06).
/// Deck = a "book" on the server: POST /card/book/*. Card = one
/// front/back pair: POST /card/*. The server owns SM-2 scheduling —
/// the client only reports the ease factor (1 hard, 2 good, 3 easy)
/// through POST /card/review.
class FlashcardDeck {
  final int id;
  final String title; // name
  final String? description;
  final int colorValue; // color — ARGB int
  final int cardCount;
  final DateTime? createdAt;

  FlashcardDeck({
    required this.id,
    required this.title,
    this.description,
    required this.colorValue,
    this.cardCount = 0,
    this.createdAt,
  });

  factory FlashcardDeck.fromJson(Map<String, dynamic> j) {
    var createdMs = firstIntValue(j, const ['created_at', 'createdAt', 'ct']);
    return FlashcardDeck(
      id: firstIntValue(j, const ['id', 'book_id', 'bookId']),
      title: firstStringValue(j, const ['name', 'title']) ?? 'Deck',
      description: firstStringValue(j, const ['description', 'desc']),
      colorValue:
          firstIntValue(j, const ['color', 'co', 'c'], fallback: 0xFFE8552D),
      cardCount:
          firstIntValue(j, const ['card_count', 'count', 'cardCount', 'cc']),
      createdAt: createdMs > 0
          ? DateTime.fromMillisecondsSinceEpoch(createdMs)
          : null,
    );
  }

  Color get color => Color(colorValue == 0 ? 0xFFE8552D : colorValue);

  FlashcardDeck copyWith({int? cardCount}) => FlashcardDeck(
        id: id,
        title: title,
        description: description,
        colorValue: colorValue,
        cardCount: cardCount ?? this.cardCount,
        createdAt: createdAt,
      );
}

class Flashcard {
  final int id;
  final int deckId;
  final String front; // question
  final String back; // answer
  final String? hint;
  final int reviewCount;
  final int easeFactor; // 1 hard, 2 good, 3 easy
  final bool mastered;

  Flashcard({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    this.hint,
    this.reviewCount = 0,
    this.easeFactor = 2,
    this.mastered = false,
  });

  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
        id: firstIntValue(j, const ['id', 'card_id', 'cardId']),
        deckId: firstIntValue(j, const ['book_id', 'deck_id', 'deckId']),
        front: firstStringValue(j, const ['question', 'front', 'q']) ?? '',
        back: firstStringValue(j, const ['answer', 'back', 'a']) ?? '',
        hint: firstStringValue(j, const ['hint', 'h']),
        reviewCount: firstIntValue(
            j, const ['review_count', 'reviewCount', 'rc']),
        easeFactor:
            firstIntValue(j, const ['ease_factor', 'easeFactor', 'ef'],
                fallback: 2),
        mastered: boolValue(j['is_mastered']),
      );
}

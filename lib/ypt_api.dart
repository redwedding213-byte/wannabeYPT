import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'social_auth.dart';

/// YPT API 클라이언트. RE 스펙(YPT_API_SPEC_FINAL.md) 기반.
/// base=https://pi.tgclab.com, 인증=Authorization: JWT <token>.
class YptApi {
  static const String base = 'https://pi.tgclab.com';
  static const Duration requestTimeout = Duration(seconds: 15);

  // 실제 앱과 동일하게 보이도록 — 안드로이드 기기 모델 + dart:io UA.
  // (실제 앱은 Build.MODEL 과 Dart/<버전> (dart:io) 를 보낸다.)
  static const String deviceModel = 'SM-S921N'; // Galaxy S24 (흔한 한국 모델)
  static const String userAgent = 'Dart/3.11 (dart:io)';

  final http.Client _client;
  String? jwt;

  YptApi({http.Client? client}) : _client = client ?? http.Client();

  Map<String, String> _headers({bool auth = true}) => {
        'Content-Type': 'application/json',
        'Accept-Encoding': 'gzip',
        'User-Agent': userAgent, // 실제 앱과 동일 (Dart/3.11 dart:io)
        if (auth && jwt != null) 'authorization': 'JWT $jwt',
      };

  Uri _u(String path) => Uri.parse('$base$path');

  Future<http.Response> _get(String path) =>
      _client.get(_u(path), headers: _headers()).timeout(requestTimeout);

  Future<http.Response> _post(
    String path,
    Map<String, Object?> body, {
    bool auth = true,
  }) =>
      _client
          .post(_u(path), headers: _headers(auth: auth), body: jsonEncode(body))
          .timeout(requestTimeout);

  Future<http.Response> _put(String path, Map<String, Object?> body) =>
      _client
          .put(_u(path), headers: _headers(), body: jsonEncode(body))
          .timeout(requestTimeout);

  Map<String, dynamic> _decodeObject(http.Response r) {
    final decoded = jsonDecode(utf8.decode(r.bodyBytes));
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw const FormatException('Expected a JSON object response.');
  }

  void _ensureOk(http.Response r, String endpoint) {
    if (r.statusCode != 200) {
      throw YptApiException('$endpoint HTTP ${r.statusCode}');
    }
  }

  void close() {
    _client.close();
  }

  /// POST /user/sign-in-jwt — 이메일 로그인. 성공 시 jwt 저장.
  Future<SignInResult> signIn(String email, String password) async {
    final r = await _post(
        '/user/sign-in-jwt',
        {
          'email': email,
          'password': password,
          'loginProvider': 'Email',
          'new': true,
          'getx': true,
          'language': 'en',
        },
        auth: false);
    if (r.statusCode != 200) return SignInError('http_${r.statusCode}');
    final j = _decodeObject(r);
    if (j['s'] == true) {
      final token = j['jwt']?.toString();
      if (token == null || token.isEmpty) return SignInError('missing_jwt');
      jwt = token;
      return SignInOk(UserData.fromJson(j));
    }
    return SignInError(j['c']?.toString() ?? 'unknown');
  }

  /// POST /user/social/sign-up-jwt — 소셜 로그인/가입(멱등). 성공 시 jwt 저장.
  /// 실제 앱과 동일 바디: {accessToken, providerId, email, loginProvider, new, getx, version}.
  /// providerId가 신규면 가입, 기존이면 그 계정으로 로그인 (RE: spec/SOCIAL_LOGIN.md).
  Future<SignInResult> socialSignIn(SocialCredential cred) async {
    final r = await _post(
        '/user/social/sign-up-jwt',
        {
          'accessToken': cred.accessToken,
          'providerId': cred.providerId,
          'email': cred.email,
          'loginProvider': cred.loginProvider,
          'new': true,
          'getx': true,
          'version': 810046,
        },
        auth: false);
    if (r.statusCode != 200) return SignInError('http_${r.statusCode}');
    final j = _decodeObject(r);
    if (j['s'] == true) {
      final token = j['jwt']?.toString();
      if (token == null || token.isEmpty) return SignInError('missing_jwt');
      jwt = token;
      return SignInOk(UserData.fromJson(j));
    }
    return SignInError(j['c']?.toString() ?? 'unknown');
  }

  /// POST /user/v2/reload/info — 프로필/과목/오늘로그 갱신.
  /// 실제 앱과 동일: cd 값을 전부 null로 보내야 전체 데이터(ss 등)를 받는다.
  /// (오래된 타임스탬프를 보내면 델타만 와서 과목이 빠짐 — 캡처로 확인)
  Future<UserData> reloadInfo() async {
    final r = await _post('/user/v2/reload/info', {
      'pv': 0,
      'cd': {
        'su': null,
        'sbu': null,
        'cu': null,
        'eu': null,
        'du': null,
        'tu': null,
      },
    });
    _ensureOk(r, 'reload/info');
    return UserData.fromJson(_decodeObject(r));
  }

  /// POST /study/study-plan/rest — create a planner task on the server
  /// (Desky parity, found 2026-10-29; the Oct 21 hunt never tried this
  /// path). Returns true when the server confirms (HTTP 200 + s == true).
  Future<bool> createStudyPlanTask({
    required String title,
    int? subjectId,
    required String dateYmd,
  }) async {
    try {
      final r = await _post('/study/study-plan/rest', {
        'title': title,
        'subject_id': subjectId,
        'start_at': '${dateYmd}T00:00:00.000Z',
        'all_day': false,
        'order': 0,
        'score': null,
        'duration': null,
      });
      if (r.statusCode != 200) return false;
      return _decodeObject(r)['s'] == true;
    } catch (_) {
      return false;
    }
  }

  /// PUT /study/study-plan/rest — toggle/edit a planner task on the server.
  /// Done is written as score 3: that matches the observed official-app
  /// `tks` data and this client's `s == 3` read rule, and it also passes
  /// Desky's any-nonzero read rule — so 3 satisfies all three readers,
  /// while Desky's 1 would break this client's own read side after a
  /// reload. Undone is written as score null. Returns true on confirm.
  Future<bool> toggleStudyPlanTask({
    required YptTask task,
    required bool done,
  }) async {
    try {
      final r = await _put('/study/study-plan/rest', {
        'id': task.id,
        'title': task.title,
        // sd 0 means no subject (General) — the server takes null there.
        'subject_id': task.subjectId == 0 ? null : task.subjectId,
        'start_at': '${task.date}T00:00:00.000Z',
        'all_day': false,
        'order': task.order,
        'score': done ? 3 : null,
        'duration': null,
      });
      if (r.statusCode != 200) return false;
      return _decodeObject(r)['s'] == true;
    } catch (_) {
      return false;
    }
  }

  /// PUT /study/study-plan/rest — set a planner task's status
  /// score directly (three-state menu path). Same full payload as
  /// the toggle: Done writes 3, Half-done writes
  /// [kTaskHalfDoneScore] (second candidate: 1 proven not half-done
  /// by official-app display), Not done writes null. Returns true
  /// on confirm (200 + `s == true`). The binary toggle above is
  /// left untouched.
  Future<bool> setStudyPlanTaskScore({
    required YptTask task,
    required int? score,
  }) async {
    try {
      final r = await _put('/study/study-plan/rest', {
        'id': task.id,
        'title': task.title,
        // sd 0 means no subject (General) — the server takes null there.
        'subject_id': task.subjectId == 0 ? null : task.subjectId,
        'start_at': '${task.date}T00:00:00.000Z',
        'all_day': false,
        'order': task.order,
        'score': score,
        'duration': null,
      });
      if (r.statusCode != 200) return false;
      return _decodeObject(r)['s'] == true;
    } catch (_) {
      return false;
    }
  }

  /// GET /logs/my-category-rank — 내 카테고리 등수. 응답 {s, mr}.
  Future<int?> myCategoryRank(int categoryId, int countryId) async {
    final r = await _get(
        '/logs/my-category-rank?category_id=$categoryId&country_id=$countryId');
    _ensureOk(r, 'logs/my-category-rank');
    final j = _decodeObject(r);
    if (j['s'] == true) return intOrNull(j['mr']);
    return null;
  }

  /// GET /logs/category/member/ranks — 카테고리 랭킹 멤버 (type=day/week/month).
  /// 응답 {s, ms:[{n,sd,ud,si,...}], tc}. sd=공부ms, n=닉네임, si=studiconID.
  /// Desky hits the metadata CDN (picf) for this endpoint while this
  /// client used pi; try pi first, then picf, and take the first
  /// response that actually carries a member list. Read-only, so a
  /// fallback fetch is harmless.
  Future<List<RankMember>> categoryRanks(int categoryId, int countryId,
      {String type = 'day', int page = 1, required String date}) async {
    final query =
        'logs/category/member/ranks?date=$date&categoryID=$categoryId&countryID=$countryId&page=$page&type=$type';
    for (final host in [base, 'https://picf.tgclab.com']) {
      try {
        final r = await _client
            .get(Uri.parse('$host/$query'), headers: _headers())
            .timeout(requestTimeout);
        if (r.statusCode != 200) continue;
        final j = _decodeObject(r);
        if (j['s'] != true) continue;
        final ms = j['ms'] is List ? j['ms'] as List : const [];
        if (ms.isEmpty) continue;
        return ms
            .whereType<Map<String, dynamic>>()
            .map(RankMember.fromJson)
            .toList();
      } catch (_) {
        continue;
      }
    }
    return [];
  }

  /// POST /logs/range/days — per-day totals for a date range.
  /// Returns date (yyyy-MM-dd) → study ms, parsed leniently: the day
  /// list may sit under 'ls', 'ds', 'days', 'data', 'result' or
  /// 'items', each entry carrying a date-like and an ms-like key.
  /// Throws [YptApiException] when the server rejects the call, so
  /// the caller shows an error instead of a blank year.
  Future<Map<String, int>> fetchRangeDays({
    required int userId,
    required String startDate,
    required String endDate,
  }) async {
    final r = await _post('/logs/range/days', {
      'id': userId,
      'isMember': true,
      'startDate': startDate,
      'endDate': endDate,
    });
    _ensureOk(r, 'logs/range/days');
    final j = _decodeObject(r);
    if (j['s'] != true) {
      throw YptApiException(j['m']?.toString() ?? 'logs/range/days failed');
    }
    final out = <String, int>{};
    List? list;
    for (final candidate in [
      j['ls'],
      j['ds'],
      j['days'],
      j['data'],
      j['result'],
      j['items'],
    ]) {
      if (candidate is List) {
        list = candidate;
        break;
      }
      if (candidate is Map) {
        final inner = candidate['ls'] ??
            candidate['days'] ??
            candidate['list'] ??
            candidate['items'];
        if (inner is List) {
          list = inner;
          break;
        }
      }
    }
    if (list == null) return out;
    for (final entry in list) {
      if (entry is! Map) continue;
      final m = entry is Map<String, dynamic>
          ? entry
          : entry.cast<String, dynamic>();
      final rawDate =
          firstStringValue(m, const ['d', 'date', 'day', 'dt', 'ymd']);
      if (rawDate == null || rawDate.isEmpty) continue;
      var key = rawDate.length >= 10 ? rawDate.substring(0, 10) : rawDate;
      final parts = key.split('-');
      if (parts.length == 3) {
        key =
            '${parts[0]}-${parts[1].padLeft(2, '0')}-${parts[2].padLeft(2, '0')}';
      }
      var ms = firstIntValue(m, const [
        'sm',
        'ms',
        'studyMs',
        'totalMs',
        'tm',
        'study_ms',
        'total',
      ]);
      if (ms <= 0 && m['dl'] is Map) {
        ms = intValue((m['dl'] as Map)['sm']);
      }
      if (ms > 0) out[key] = (out[key] ?? 0) + ms;
    }
    return out;
  }

  /// Subject management (Desky-derived, unproven live).
  /// POST /user/subject/create {title, color} → s == true.
  Future<bool> createSubject(
      {required String title, required int colorInt}) async {
    try {
      final r = await _post(
          '/user/subject/create', {'title': title, 'color': colorInt});
      if (r.statusCode != 200) return false;
      return _decodeObject(r)['s'] == true;
    } catch (_) {
      return false;
    }
  }

  /// POST /user/subject/edit {id, title, color, is_archived} → s == true.
  Future<bool> editSubject({
    required int id,
    required String title,
    required int colorInt,
    bool archived = false,
  }) async {
    try {
      final r = await _post('/user/subject/edit', {
        'id': id,
        'title': title,
        'color': colorInt,
        'is_archived': archived,
      });
      if (r.statusCode != 200) return false;
      return _decodeObject(r)['s'] == true;
    } catch (_) {
      return false;
    }
  }

  /// POST /user/subject/archive/change {id, is_archived, new} → s == true.
  Future<bool> archiveSubject(
      {required int id, required bool archived}) async {
    try {
      final r = await _post('/user/subject/archive/change',
          {'id': id, 'is_archived': archived, 'new': true});
      if (r.statusCode != 200) return false;
      return _decodeObject(r)['s'] == true;
    } catch (_) {
      return false;
    }
  }

  /// POST /user/subject/hard-delete {id} → s == true. A different
  /// endpoint from the parked task delete — this one is in scope.
  Future<bool> hardDeleteSubject(int id) async {
    try {
      final r = await _post('/user/subject/hard-delete', {'id': id});
      if (r.statusCode != 200) return false;
      return _decodeObject(r)['s'] == true;
    } catch (_) {
      return false;
    }
  }

  /// POST /study/add — a manual study record (retroactive session).
  /// Returns true on s == true, else throws with the server's message
  /// when present. End time is not sent; it is implied by stm + ms.
  /// The caller supplies user-entered values only: no auto-fill, no
  /// defaults that inflate time.
  Future<bool> logManualStudy({
    required String subjectTitle,
    required DateTime startAt,
    required DateTime stopAt,
  }) async {
    final studyMs = stopAt.difference(startAt).inMilliseconds;
    if (studyMs <= 0) {
      throw const YptApiException('End time must be after start time.');
    }
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${startAt.year}-${two(startAt.month)}-${two(startAt.day)}';
    final r = await _post('/study/add', {
      'sb': subjectTitle,
      'date': date,
      'ms': studyMs,
      'stm': startAt.millisecondsSinceEpoch,
      'addVersion': false,
    });
    if (r.statusCode != 200) {
      throw YptApiException('study/add HTTP ${r.statusCode}');
    }
    final j = _decodeObject(r);
    if (j['s'] == true) return true;
    throw YptApiException(j['m']?.toString() ?? 'Manual study record failed.');
  }

  /// Notifications (Desky-derived, unproven live).
  /// GET /user/notifications, falling back to GET /notice/list.
  /// Throws when neither endpoint answers, so the caller can tell a
  /// failed load apart from a genuinely empty inbox.
  Future<List<NotificationItem>> fetchNotifications() async {
    var answered = false;
    for (final path in [
      '/user/notifications?page=1&is_new=false',
      '/notice/list',
    ]) {
      try {
        final r = await _get(path);
        if (r.statusCode != 200) continue;
        final j = _decodeObject(r);
        answered = true;
        final list = j['ns'] ?? j['notices'] ?? j['list'];
        if (list is! List) continue;
        return list
            .whereType<Map<String, dynamic>>()
            .map(NotificationItem.fromJson)
            .toList();
      } catch (_) {
        continue;
      }
    }
    if (answered) return [];
    throw const YptApiException('Could not load notifications.');
  }

  /// POST /notice/read {noticeID, id} → s == true.
  Future<bool> markNotificationRead(int id) async {
    try {
      final r = await _post('/notice/read', {'noticeID': id, 'id': id});
      if (r.statusCode != 200) return false;
      return _decodeObject(r)['s'] == true;
    } catch (_) {
      return false;
    }
  }

  /// POST /user/notifications/read-all {all} → s == true, falling
  /// back to POST /notice/read-all.
  Future<bool> markAllNotificationsRead() async {
    try {
      final r = await _post('/user/notifications/read-all', {'all': true});
      if (r.statusCode == 200 && _decodeObject(r)['s'] == true) return true;
    } catch (_) {}
    try {
      final r = await _post('/notice/read-all', {});
      if (r.statusCode == 200 && _decodeObject(r)['s'] == true) return true;
    } catch (_) {}
    return false;
  }

  /// GET /timetable/timetables — weekly timetable blocks, read-only.
  /// Throws when the endpoint doesn't answer, so the caller can tell
  /// a failed load apart from a genuinely empty timetable.
  Future<List<TimetableBlock>> fetchTimetable() async {
    try {
      final r = await _get('/timetable/timetables');
      if (r.statusCode != 200) {
        throw const YptApiException('timetable/timetables unavailable');
      }
      final j = _decodeObject(r);
      final list = j['timetables'] ?? j['t'] ?? j['blocks'];
      if (list is! List) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(TimetableBlock.fromJson)
          .toList();
    } catch (e) {
      if (e is YptApiException) rethrow;
      throw const YptApiException('Could not load timetable.');
    }
  }

  /// GET /logs/day?date= — 오늘 과목별 공부시간 (dayLog.ls).
  /// API 버전에 따라 과목 식별자가 제목 또는 id 계열 키로 내려올 수 있다.
  Future<SubjectTimeSnapshot> dayLogSubjects(String date) async {
    final r = await _get('/logs/day?date=$date');
    _ensureOk(r, 'logs/day');
    final j = _decodeObject(r);
    final dl = j['dl'];
    final subjectBooks = mapListValue(j['sbs']);
    final titleByIndex = <int, String>{};
    for (var i = 0; i < subjectBooks.length; i++) {
      final title = firstStringValue(subjectBooks[i], const ['t', 'title']);
      if (title != null && title.trim().isNotEmpty) titleByIndex[i] = title;
    }

    final byId = <int, int>{};
    final byTitle = <String, int>{};

    void merge(SubjectTimeSnapshot snapshot) {
      for (final entry in snapshot.byId.entries) {
        byId[entry.key] = (byId[entry.key] ?? 0) + entry.value;
      }
      for (final entry in snapshot.byTitle.entries) {
        byTitle[entry.key] = (byTitle[entry.key] ?? 0) + entry.value;
      }
    }

    if (dl is Map<String, dynamic>) {
      merge(subjectTimeSnapshotFromJson(dl, titleByIndex: titleByIndex));
    }
    merge(subjectTimeSnapshotFromJson(j, titleByIndex: titleByIndex));
    return SubjectTimeSnapshot(byId: byId, byTitle: byTitle);
  }

  /// GET /group/list-new-2 — 둘러보기(신규) 그룹 목록. 응답 {s, gs:[...]}.
  Future<List<Group>> browseGroups(int countryId, {int page = 1}) async {
    final r = await _get(
        '/group/list-new-2?category_id=0&order_type=promotedAt&only_available=false&only_open=false&only_cam=false&page=$page&country_id=$countryId&p=true');
    _ensureOk(r, 'group/list-new-2');
    final j = _decodeObject(r);
    final gs = j['gs'] is List ? j['gs'] as List : const [];
    return gs.whereType<Map<String, dynamic>>().map(Group.fromJson).toList();
  }

  /// GET /group/groups/v2 — 내가 속한 그룹. 응답 {s, gs, ms, cs, ps} 4개 배열에 분산.
  Future<List<Group>> myGroups() async {
    final r = await _get('/group/groups/v2');
    _ensureOk(r, 'group/groups/v2');
    final j = _decodeObject(r);
    final out = <Group>[];
    final seen = <int>{};
    for (final key in ['gs', 'ms', 'cs', 'ps']) {
      final list = j[key] is List ? j[key] as List : const [];
      for (final item in list.whereType<Map<String, dynamic>>()) {
        final g = Group.fromJson(item);
        if (g.title.isNotEmpty && seen.add(g.id)) out.add(g);
      }
    }
    return out;
  }

  /// GET /logs/group/members/v2 — 그룹 멤버(공부 현황). 응답 {s, ms:[...]}.
  Future<List<GroupMember>> groupMembers(int groupId, int countryId) async {
    final raw = await groupMembersRaw(groupId, countryId);
    return raw.map(GroupMember.fromJson).toList();
  }

  /// Same endpoint, unparsed — for debugging the real response shape.
  Future<List<Map<String, dynamic>>> groupMembersRaw(
      int groupId, int countryId) async {
    final r = await _get(
        '/logs/group/members/v2?groupID=$groupId&countryID=$countryId&isLooking=true&version=810046');
    _ensureOk(r, 'logs/group/members/v2');
    final j = _decodeObject(r);
    final ms = j['ms'] is List ? j['ms'] as List : const [];
    return ms.whereType<Map<String, dynamic>>().toList();
  }

  /// POST /study/start — 타이머 시작. 응답에 dayLog 포함.
  Future<DayLog?> studyStart(String subject, {int? taskId}) async {
    final r = await _post('/study/start',
        {'subject': subject, 'deviceModel': deviceModel, 'taskId': taskId});
    _ensureOk(r, 'study/start');
    final j = _decodeObject(r);
    if (j['s'] == true && j['dl'] is Map<String, dynamic>) {
      return DayLog.fromJson(j['dl']);
    }
    throw YptApiException(j['c']?.toString() ?? 'study/start failed');
  }

  /// POST /study/stop — 타이머 정지. startedAt=시작 epoch(ms).
  Future<DayLog?> studyStop(int startedAtMs) async {
    final r = await _post(
        '/study/stop', {'startedAt': startedAtMs, 'deviceModel': deviceModel});
    _ensureOk(r, 'study/stop');
    final j = _decodeObject(r);
    if (j['s'] == true && j['dl'] is Map<String, dynamic>) {
      return DayLog.fromJson(j['dl']);
    }
    throw YptApiException(j['c']?.toString() ?? 'study/stop failed');
  }

  /// GET /logs/day?date= — raw payload (totals + timed sessions).
  Future<Map<String, dynamic>> dayLogRaw(String date) async {
    final r = await _get('/logs/day?date=$date');
    _ensureOk(r, 'logs/day');
    return _decodeObject(r);
  }

  /// POST /user/v2/reload/info — raw payload, for shape discovery.
  Future<Map<String, dynamic>> reloadRaw() async {
    final r = await _post('/user/v2/reload/info', {
      'pv': 0,
      'cd': {
        'su': null,
        'sbu': null,
        'cu': null,
        'eu': null,
        'du': null,
        'tu': null,
      },
    });
    _ensureOk(r, 'reload/info');
    return _decodeObject(r);
  }

  /// GET /logs/group/members/v2 with an explicit date — whether the
  /// server honours it decides if weekly attendance/rankings can exist.
  Future<List<Map<String, dynamic>>> groupMembersRawOnDate(
      int groupId, int countryId, String date) async {
    final r = await _get(
        '/logs/group/members/v2?groupID=$groupId&countryID=$countryId&isLooking=true&version=810046&date=$date');
    _ensureOk(r, 'logs/group/members/v2?date');
    final j = _decodeObject(r);
    final ms = j['ms'] is List ? j['ms'] as List : const [];
    return ms.whereType<Map<String, dynamic>>().toList();
  }

  /// GET /logs/group/member/ranks — per-member logs for a group.
  /// type=day honours its date; type=week needs the week's MONDAY as
  /// the date (any other day returns an empty list) and its dl.sm is
  /// the week aggregate. Entries share the members shape
  /// ({ud, n, ct, dl:{sm, is, st, sp}}), so GroupMember parses them.
  Future<List<GroupMember>> groupRanks(
      int groupId, int countryId, String date, String type) async {
    final r = await _get(
        '/logs/group/member/ranks?groupID=$groupId&countryID=$countryId&date=$date&type=$type');
    _ensureOk(r, 'logs/group/member/ranks');
    final j = _decodeObject(r);
    final ms = j['ms'] is List ? j['ms'] as List : const [];
    return ms
        .whereType<Map<String, dynamic>>()
        .map(GroupMember.fromJson)
        .toList();
  }

  /// Read-only probe: HTTP status for a candidate route, -1 on error.
  /// GET is used for read candidates, OPTIONS for write candidates —
  /// neither mutates anything server-side.
  Future<int> probeStatus(String method, String path) async {
    try {
      final req = http.Request(method, _u(path));
      req.headers.addAll(_headers());
      final streamed = await _client.send(req).timeout(requestTimeout);
      await streamed.stream.drain();
      return streamed.statusCode;
    } catch (_) {
      return -1;
    }
  }

  /// GET probe that also returns a short body snippet, so a 200's
  /// shape is visible in one screenshot.
  Future<(int, String)> probeGetText(String path) async {
    try {
      final r = await _get(path);
      var body = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (body.length > 420) body = '${body.substring(0, 420)}…';
      return (r.statusCode, body);
    } catch (e) {
      return (-1, '$e');
    }
  }

  /// Write-path probe: reload/info with an extra empty `tks` array in
  /// the body. If the server treats reload as a state push, the reply's
  /// task list changes; if it ignores the field, tasks return as-is.
  /// Returns (status, short summary of the returned task list).
  Future<(int, String)> probeReloadWithTasks() async {
    try {
      final r = await _post('/user/v2/reload/info', {
        'pv': 0,
        'cd': {
          'su': null,
          'sbu': null,
          'cu': null,
          'eu': null,
          'du': null,
          'tu': null,
        },
        'tks': const [],
      });
      if (r.statusCode != 200) return (r.statusCode, '');
      final j = _decodeObject(r);
      final tks = j['tks'] is List ? j['tks'] as List : const [];
      final first = tks.isNotEmpty && tks.first is Map
          ? (tks.first as Map)['t']?.toString() ?? ''
          : '';
      return (
        r.statusCode,
        'tks: ${tks.length}${first.isEmpty ? '' : ' (first: $first)'}'
      );
    } catch (e) {
      return (-1, '$e');
    }
  }

  /// Decisive edit-log write test (user-approved 2026-10-21): push an
  /// OLD day's log (never today's) back through reload/info with one
  /// session's duration +1 ms — first with the day array inside `cd`
  /// (where day logs live in reload responses), then at the top
  /// level. If a variant sticks, immediately push the original back
  /// through the same route and verify, so the test leaves no trace.
  /// Returns (status, summary).
  Future<(int, String)> probeDayLogPush() async {
    try {
      final raw = await reloadRaw();
      final cd = raw['cd'];
      final ds = (cd is Map<String, dynamic> && cd['ds'] is List)
          ? cd['ds'] as List
          : const [];
      final todayDt =
          raw['dl'] is Map ? (raw['dl'] as Map)['dt']?.toString() : null;
      Map<String, dynamic>? day;
      for (final e in ds) {
        if (e is Map<String, dynamic> &&
            e['dt']?.toString() != todayDt &&
            e['ls'] is List &&
            (e['ls'] as List).isNotEmpty) {
          day = e;
          break;
        }
      }
      if (day == null) return (0, 'skipped — no past day with sessions');
      final dt = day['dt'].toString();
      final origSessionSm = intValue((day['ls'] as List).first['sm']);

      Map<String, dynamic> variant(int delta) {
        final clone = jsonDecode(jsonEncode(day)) as Map<String, dynamic>;
        final ls = clone['ls'] as List;
        (ls.first as Map)['sm'] = origSessionSm + delta;
        clone['sm'] = intValue(clone['sm']) + delta;
        return clone;
      }

      const cdBase = <String, Object?>{
        'su': null,
        'sbu': null,
        'cu': null,
        'eu': null,
        'du': null,
        'tu': null,
      };

      Future<bool> stuck() async {
        final check = await dayLogRaw(dt);
        final dl = check['dl'];
        if (dl is Map && dl['ls'] is List && (dl['ls'] as List).isNotEmpty) {
          return intValue((dl['ls'] as List).first['sm']) ==
              origSessionSm + 1;
        }
        return false;
      }

      Future<bool> pushAndCheck(Map<String, Object?> body) async {
        final r = await _post('/user/v2/reload/info', body);
        if (r.statusCode != 200) return false;
        return stuck();
      }

      String? route;
      if (await pushAndCheck({
        'pv': 0,
        'cd': {...cdBase, 'ds': [variant(1)]},
      })) {
        route = 'cd.ds';
      } else if (await pushAndCheck({
        'pv': 0,
        'cd': cdBase,
        'ds': [variant(1)],
      })) {
        route = 'top-level ds';
      }
      if (route == null) {
        return (
          200,
          '$dt session ${origSessionSm}ms · neither push changed anything — edit-log stays read-only'
        );
      }
      // It stuck — push the original back through the winning route.
      final revertBody = route == 'cd.ds'
          ? <String, Object?>{
              'pv': 0,
              'cd': {...cdBase, 'ds': [variant(0)]},
            }
          : <String, Object?>{
              'pv': 0,
              'cd': cdBase,
              'ds': [variant(0)],
            };
      final rr = await _post('/user/v2/reload/info', revertBody);
      var reverted = false;
      if (rr.statusCode == 200) {
        final check = await dayLogRaw(dt);
        final dl = check['dl'];
        if (dl is Map && dl['ls'] is List && (dl['ls'] as List).isNotEmpty) {
          reverted =
              intValue((dl['ls'] as List).first['sm']) == origSessionSm;
        }
      }
      return (
        200,
        '$dt · route: $route · +1ms STUCK · reverted: ${reverted ? 'yes, data clean' : 'FAILED — 1ms remains'} · EDIT/DELETE LOG WRITES WORK via $route'
      );
    } catch (e) {
      return (-1, '$e');
    }
  }

  /// Decisive task-write test (user-approved 2026-10-21): push the
  /// disposable task titled 'test' (or 'test2') back through
  /// reload/info with only its title flipped, then re-read. If the
  /// new title sticks, the server accepts task writes via reload
  /// (delta-push); if not, the field is ignored and tasks stay
  /// read-only. Running it again flips the title back. Touches ONLY
  /// that one dummy task.
  Future<(int, String)> probeTaskRename() async {
    try {
      final before = await reloadRaw();
      final tks = before['tks'] is List ? before['tks'] as List : const [];
      Map<String, dynamic>? target;
      for (final e in tks) {
        if (e is Map<String, dynamic> &&
            (e['t'] == 'test' || e['t'] == 'test2')) {
          target = e;
          break;
        }
      }
      if (target == null) {
        return (0, 'skipped — no task titled test/test2 found');
      }
      final from = target['t'] as String;
      final to = from == 'test' ? 'test2' : 'test';
      final targetId = target['id'];
      final modified = Map<String, dynamic>.from(target);
      modified['t'] = to;
      modified['ua'] = DateTime.now().toUtc().toIso8601String();
      final r = await _post('/user/v2/reload/info', {
        'pv': 0,
        'cd': {
          'su': null,
          'sbu': null,
          'cu': null,
          'eu': null,
          'du': null,
          'tu': null,
        },
        'tks': [modified],
      });
      if (r.statusCode != 200) return (r.statusCode, 'push rejected');
      String titleIn(Map<String, dynamic> payload) {
        final list =
            payload['tks'] is List ? payload['tks'] as List : const [];
        for (final e in list) {
          if (e is Map && e['id'] == targetId) {
            return e['t']?.toString() ?? '?';
          }
        }
        return '(task missing)';
      }

      final pushTitle = titleIn(_decodeObject(r));
      final freshTitle = titleIn(await reloadRaw());
      final verdict = freshTitle == to
          ? 'WRITE WORKS — task writes go through reload/info'
          : 'no change — reload ignores pushed tasks (read-only)';
      return (
        r.statusCode,
        '$from → $to · push-response title: $pushTitle · fresh reload title: $freshTitle · $verdict'
      );
    } catch (e) {
      return (-1, '$e');
    }
  }

  /// POST probe with an empty body — a real route should reject it
  /// with 400/422 rather than create anything; 404 means no route.
  Future<int> probePostEmpty(String path) async {
    try {
      final r = await _post(path, const {});
      return r.statusCode;
    } catch (_) {
      return -1;
    }
  }

  // ---- Group chat (Desky parity, built 2026-10-29) ----
  // List + send are backed by captured traffic in the Desky spec;
  // reactions are code-only (toggle semantics assumed, never shown);
  // sticker sets follow the SPEC shape ({r: [...]}) — Desky's
  // data['sets']/data['s'] parser contradicts the spec and is NOT
  // copied. Media upload is dead code in Desky and is skipped: v1
  // sends image URLs only.

  /// GET /chat/group/messages?group_id=<id>&include_meta=true →
  /// {m: [...], s: true} (fallback `messages`). The item shape was
  /// never captured, so ChatMessage.fromJson covers Desky's
  /// fallbacks. Diagnostics ride along: an empty list with
  /// unexpected keys is surfaced by the UI, never silently guessed.
  Future<ChatListResult> fetchChatMessages(int groupId) async {
    try {
      final r = await _get(
          '/chat/group/messages?group_id=$groupId&include_meta=true');
      if (r.statusCode != 200) {
        return const ChatListResult(
            messages: [], rawKeys: [], httpOk: false);
      }
      final j = _decodeObject(r);
      final keys = j.keys.toList();
      final m = j['m'] ?? j['messages'];
      if (m is String) {
        // Server rejection carried in `m` instead of a list.
        return ChatListResult(
            messages: const [],
            rawKeys: keys,
            serverMessage: m,
            httpOk: true);
      }
      if (m is! List) {
        return ChatListResult(
            messages: const [], rawKeys: keys, httpOk: true);
      }
      return ChatListResult(
        messages: m
            .whereType<Map<String, dynamic>>()
            .map(ChatMessage.fromJson)
            .toList(),
        rawKeys: keys,
        httpOk: true,
      );
    } catch (_) {
      return const ChatListResult(
          messages: [], rawKeys: [], httpOk: false);
    }
  }

  /// POST /chat/group/message — captured body. `category` MUST be
  /// the group's real category STRING (Group.category, from `c`);
  /// Desky's int 0 default is wrong against the captured example.
  /// Returns the sent message, or null on rejection. The response's
  /// `did` is a composite string, never a studicon id.
  Future<ChatMessage?> sendChatMessage({
    required int groupId,
    required String nickname,
    required String category,
    required int userId,
    String message = '',
    String? stickerUrl,
    String? imageUrl,
    String? thumbUrl,
  }) async {
    try {
      final payload = <String, Object?>{
        'group_id': groupId,
        'nickname': nickname,
        'category': category,
        'userID': userId,
        'message': message.isNotEmpty ? message : (imageUrl != null ? 'Photo' : ''),
        'createdAt': null,
        'updatedAt': null,
      };
      if (stickerUrl != null) payload['stickerUrl'] = stickerUrl;
      if (imageUrl != null) {
        payload['img'] = imageUrl;
        payload['imageUrl'] = imageUrl;
      }
      if (thumbUrl != null) payload['th'] = thumbUrl;
      final r = await _post('/chat/group/message', payload);
      if (r.statusCode != 200) return null;
      final j = _decodeObject(r);
      if (j['s'] != true && j['idx'] == null) return null;
      return ChatMessage.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  /// POST /chat/group/reaction {group_id, idx, reaction} → s == true.
  /// Code-only in Desky: toggle semantics are assumed (sending the
  /// same emoji again is expected to remove it) and were never
  /// shown — the UI verifies add and remove separately live.
  Future<bool> sendChatReaction({
    required int groupId,
    required int messageId,
    required String emoji,
  }) async {
    try {
      final r = await _post('/chat/group/reaction', {
        'group_id': groupId,
        'idx': messageId,
        'reaction': emoji,
      });
      if (r.statusCode != 200) return false;
      return _decodeObject(r)['s'] == true;
    } catch (_) {
      return false;
    }
  }

  /// GET /chat/sticker/sets → {r: [{id, code, title, title_en,
  /// cover_image, items: [{item_id, is_active, order}]}]}. Only the
  /// SPEC shape is parsed; Desky's data['sets']/data['s'] keys are
  /// deliberately not read.
  Future<List<StickerSet>> fetchStickerSets() async {
    try {
      final r = await _get('/chat/sticker/sets');
      if (r.statusCode != 200) return [];
      final j = _decodeObject(r);
      final list = j['r'];
      if (list is! List) return [];
      return list
          .whereType<Map<String, dynamic>>()
          .map(StickerSet.fromJson)
          .where((s) => s.items.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Members endpoint with an arbitrary extra query string — used to
  /// test whether other params (dt=, type=) change what comes back.
  Future<List<GroupMember>> groupMembersWithQuery(
      int groupId, int countryId, String extraQuery) async {
    final r = await _get(
        '/logs/group/members/v2?groupID=$groupId&countryID=$countryId&isLooking=true&version=810046&$extraQuery');
    _ensureOk(r, 'logs/group/members/v2?custom');
    final j = _decodeObject(r);
    final ms = j['ms'] is List ? j['ms'] as List : const [];
    return ms
        .whereType<Map<String, dynamic>>()
        .map(GroupMember.fromJson)
        .toList();
  }
}

class YptApiException implements Exception {
  final String message;
  const YptApiException(this.message);

  @override
  String toString() => message;
}

/// 로그인 에러코드 → 사람이 읽을 메시지 (RE 스펙 에러카탈로그)
String errorMessage(String code) {
  switch (code) {
    case '113':
      return 'Sign in failed — incorrect email or password.';
    case '112':
      return 'Authentication failed — check your account.';
    case '104':
      return 'Request rejected.';
    case 'alert_server_error_msg':
      return 'A server error occurred.';
    case 'missing_jwt':
      return 'Sign in failed — the server did not return a session token.';
    default:
      if (code.startsWith('http_')) {
        return 'Request failed (HTTP ${code.substring(5)}).';
      }
      return 'Error (code: $code)';
  }
}

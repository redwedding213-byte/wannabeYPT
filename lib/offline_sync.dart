// wannabeYPT, offline study-session sync queue
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

// Offline sync queue (Desky port #3): when the phone hotspot drops while
// stopping the timer, the session is real, so it is kept, not lost.
// A queued stop replays POST /study/stop with the ORIGINAL startedAt and
// the real elapsed ms, in order, on reconnect. The queue only ever holds
// genuine timer sessions (created from a real start/stop); there is no
// free-form time entry anywhere in this feature.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ypt_api.dart';

/// One genuine timer session whose /study/stop never reached the server.
class OfflineSession {
  final String id; // '<startAtMs>_<subjectId>', dedupes repeat stops.
  final int subjectId;
  final String subjectTitle;
  final int startAtMs;
  final int stopAtMs;
  final int studyMs;
  final int createdAtMs;
  final int retryCount;
  final String? lastError;

  const OfflineSession({
    required this.id,
    required this.subjectId,
    required this.subjectTitle,
    required this.startAtMs,
    required this.stopAtMs,
    required this.studyMs,
    required this.createdAtMs,
    this.retryCount = 0,
    this.lastError,
  });

  factory OfflineSession.fromJson(Map<String, dynamic> j) {
    int asInt(Object? v, [int fallback = 0]) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? fallback;
      return fallback;
    }

    return OfflineSession(
      id: j['id']?.toString() ?? '',
      subjectId: asInt(j['subjectId']),
      subjectTitle: j['subjectTitle']?.toString() ?? '',
      startAtMs: asInt(j['startAtMs']),
      stopAtMs: asInt(j['stopAtMs']),
      studyMs: asInt(j['studyMs']),
      createdAtMs: asInt(j['createdAtMs']),
      retryCount: asInt(j['retryCount']),
      lastError: j['lastError']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectId': subjectId,
        'subjectTitle': subjectTitle,
        'startAtMs': startAtMs,
        'stopAtMs': stopAtMs,
        'studyMs': studyMs,
        'createdAtMs': createdAtMs,
        'retryCount': retryCount,
        'lastError': lastError,
      };

  OfflineSession copyWith({int? retryCount, String? lastError}) =>
      OfflineSession(
        id: id,
        subjectId: subjectId,
        subjectTitle: subjectTitle,
        startAtMs: startAtMs,
        stopAtMs: stopAtMs,
        studyMs: studyMs,
        createdAtMs: createdAtMs,
        retryCount: retryCount ?? this.retryCount,
        lastError: lastError ?? this.lastError,
      );
}

class SyncResult {
  final int synced;
  final int failed;
  final int remaining;
  final String? lastError;

  const SyncResult({
    required this.synced,
    required this.failed,
    required this.remaining,
    this.lastError,
  });
}

/// True when the request never produced a usable server answer.
/// [YptApiException] means the server responded (HTTP error or s == false)
/// - a server rejection, not a dropped connection. Everything else
/// (ClientException, TimeoutException, FormatException, ...) is treated as
/// "never reached the server", so the session is safe to queue.
bool isNetworkError(Object e) => e is! YptApiException;

/// SharedPreferences-backed queue of genuine timer sessions awaiting
/// a successful /study/stop. Same shape as Desky's
/// OfflineSyncRepository (key, JSON string list, replay in order).
class OfflineSyncQueue {
  static const String storageKey = 'wannabe_offline_study_sessions';

  Future<List<OfflineSession>> getPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(storageKey) ?? const [];
      final out = <OfflineSession>[];
      for (final item in raw) {
        try {
          final decoded = jsonDecode(item);
          if (decoded is Map<String, dynamic>) {
            final s = OfflineSession.fromJson(decoded);
            if (s.id.isNotEmpty && s.studyMs > 0) out.add(s);
          }
        } catch (_) {
          // One corrupt entry must not poison the whole queue.
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<OfflineSession> sessions) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      storageKey,
      sessions.map((s) => jsonEncode(s.toJson())).toList(),
    );
  }

  /// Adds a session. A second stop for the same (subject, startedAt)
  /// replaces the first, one real session can never be credited twice
  /// from this queue.
  Future<void> enqueue(OfflineSession session) async {
    final current = await getPending();
    final updated = [
      for (final s in current)
        if (s.id != session.id) s,
      session,
    ];
    await _save(updated);
  }

  Future<void> remove(String id) async {
    final current = await getPending();
    await _save(current.where((s) => s.id != id).toList());
  }

  /// Replays every queued stop in order via POST /study/stop with the
  /// original startedAt + real elapsed ms. A stop the server accepts is
  /// removed; a failure stays queued with its error so the user can see
  /// why, and a later retry tries it again.
  Future<SyncResult> syncAll(YptApi api) async {
    final pending = await getPending();
    if (pending.isEmpty) {
      return const SyncResult(synced: 0, failed: 0, remaining: 0);
    }
    var synced = 0;
    var failed = 0;
    String? lastError;
    final remaining = <OfflineSession>[];
    for (final session in pending) {
      try {
        await api.studyStop(session.startAtMs, studyMs: session.studyMs);
        synced++;
      } catch (e) {
        failed++;
        // YptApiException.toString() is the message itself (the server's
        // `m` where available); anything else is a transport failure.
        final msg = e.toString();
        lastError = msg.isEmpty ? 'sync failed' : msg;
        remaining.add(session.copyWith(
          retryCount: session.retryCount + 1,
          lastError: lastError,
        ));
      }
    }
    await _save(remaining);
    return SyncResult(
      synced: synced,
      failed: failed,
      remaining: remaining.length,
      lastError: lastError,
    );
  }
}

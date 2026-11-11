// wannabeYPT — Discord Rich Presence protocol helpers (pure Dart)
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

// Pure-Dart builders for Discord's local RPC-over-WebSocket protocol, so the
// URL and payload shapes can be unit-tested on the Dart VM (the socket
// itself lives in discord_rpc_web.dart, which needs dart:html).
//
// Protocol (docs.discord.com/developers/topics/rpc, "RPC over WebSocket"):
//   ws://127.0.0.1:PORT/?v=1&client_id=CLIENT_ID&encoding=json
//   PORT in 6463..6472, tried in order. Discord answers with a READY
//   dispatch, then accepts JSON commands such as SET_ACTIVITY.
// Two hard gates this code cannot work around:
//   1. Discord verifies the Origin header against the RPC Origins
//      registered for the app on the Developer Portal — a mismatched
//      origin is disconnected instantly. A real Discord application with
//      https://wannabeypt.vercel.app registered is required.
//   2. Per the docs, RPC commands require authentication (error 4006
//      otherwise): AUTHORIZE -> user approves in Discord -> code ->
//      exchange for an access token (needs the app's client_secret, so
//      it cannot happen in the browser) -> AUTHENTICATE. SET_ACTIVITY
//      is attempted without that flow first; a 4006 is treated as
//      "needs auth" and the service stops retrying silently.
class DiscordRpcProtocol {
  static const int rpcVersion = 1;
  static const int firstPort = 6463;
  static const int lastPort = 6472;

  /// The WebSocket URL for one port, exactly as Discord documents it.
  static String rpcUrl(int port, String clientId) =>
      'ws://127.0.0.1:$port/?v=1&client_id=$clientId&encoding=json';

  /// SET_ACTIVITY: show the current study subject as Rich Presence.
  /// [startedAtMs] is the session start in unix milliseconds; Discord
  /// renders it as an elapsed timer. No assets: image keys need art
  /// uploaded to the Discord application, which a placeholder app has none of.
  static Map<String, dynamic> setActivityPayload({
    required int pid,
    required String details,
    required String state,
    required int startedAtMs,
    required String nonce,
  }) {
    return {
      'cmd': 'SET_ACTIVITY',
      'args': {
        'pid': pid,
        'activity': {
          'details': details,
          'state': state,
          'timestamps': {'start': startedAtMs},
        },
      },
      'nonce': nonce,
    };
  }

  /// SET_ACTIVITY with a null activity: clears the presence.
  static Map<String, dynamic> clearActivityPayload({
    required int pid,
    required String nonce,
  }) {
    return {
      'cmd': 'SET_ACTIVITY',
      'args': {'pid': pid, 'activity': null},
      'nonce': nonce,
    };
  }

  /// AUTHORIZE: asks Discord to show the user an approval modal for the
  /// app. The response carries a `code` that must be exchanged for an
  /// access token off-device (client_secret); see discord_rpc.dart.
  static Map<String, dynamic> authorizePayload({
    required String clientId,
    required List<String> scopes,
    required String nonce,
  }) {
    return {
      'cmd': 'AUTHORIZE',
      'args': {'client_id': clientId, 'scopes': scopes},
      'nonce': nonce,
    };
  }

  /// Classify one decoded JSON frame from the RPC server.
  /// Returns 'ready' for the READY dispatch, 'error' for an ERROR
  /// dispatch (with the numeric code in [RpcFrame.code]), 'authorize'
  /// for an AUTHORIZE response carrying a code, and 'other' otherwise.
  static RpcFrame classify(Map<String, dynamic> json) {
    final evt = json['evt'];
    if (evt == 'READY') return const RpcFrame('ready');
    if (evt == 'ERROR') {
      final data = json['data'];
      var code = -1;
      if (data is Map<String, dynamic>) {
        final c = data['code'];
        if (c is int) code = c;
      }
      return RpcFrame('error', code: code);
    }
    if (json['cmd'] == 'AUTHORIZE') {
      final data = json['data'];
      if (data is Map<String, dynamic> && data['code'] is String) {
        return RpcFrame('authorize', codeString: data['code'] as String);
      }
      return const RpcFrame('authorize');
    }
    return const RpcFrame('other');
  }
}

/// One classified RPC frame.
class RpcFrame {
  /// 'ready' | 'error' | 'authorize' | 'other'.
  final String kind;

  /// Numeric error code for 'error' frames (e.g. 4006 = not authenticated).
  final int code;

  /// OAuth code for a successful 'authorize' frame.
  final String? codeString;

  const RpcFrame(this.kind, {this.code = -1, this.codeString});
}

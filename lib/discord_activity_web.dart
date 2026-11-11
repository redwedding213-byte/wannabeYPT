// wannabeYPT — Discord Rich Presence via Discord Activities
// (Embedded App SDK) — web implementation
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

// Shows the current study subject on Discord through the official
// Embedded App SDK, via the JS bridge in web/discord-bridge.js
// (window.wannabeDiscord). The bridge only talks to Discord when the
// page is running inside a Discord Activity iframe; in a normal
// browser tab every call resolves false immediately and nothing is
// fetched. Auth is PKCE in the browser (no backend, no client_secret):
// authorize -> exchange the code at Discord's token endpoint ->
// authenticate -> setActivity. Two portal settings are required or
// the exchange fails silently: the app must be a Public Client and
// https://127.0.0.1 must be a registered OAuth2 redirect.
//
// This REPLACES the old local RPC WebSocket implementation
// (discord_rpc_web.dart, deleted): Discord removed RPC Origin
// registration from the Developer Portal, so a website origin can no
// longer be allowlisted and the local RPC server disconnects every
// web connection instantly. Activities are Discord's supported route
// for web apps, and they work on desktop and mobile Discord.
//
// Everything here fails silently: not in Discord, SDK load failure,
// user denies the approval modal, token exchange rejected, Discord
// rejects the update — no crash, no UI error, no retry loop. The
// next study start tries again.
import 'dart:async';
import 'dart:js_interop';

/// The JS bridge (window.wannabeDiscord), or null if the bridge
/// script failed to load.
@JS('wannabeDiscord')
external JSObject? get _bridge;

@JS('wannabeDiscord.setActivity')
external JSPromise<JSBoolean> _bridgeSetActivity(
  String details,
  String state,
  int startedAtMs,
);

@JS('wannabeDiscord.clearActivity')
external JSPromise<JSBoolean> _bridgeClearActivity();

class DiscordActivity {
  static final DiscordActivity instance = DiscordActivity._();

  DiscordActivity._();

  /// The wannabeYPT Discord application client ID.
  static const String clientId = '1570010774070362212';

  bool _enabled = false;
  bool get enabled => _enabled;

  bool _connected = false;
  bool get connected => _connected;

  /// 'off' | 'idle' | 'ready' | 'unavailable'
  String _status = 'off';
  String get status => _status;

  /// Last failure, for diagnostics only. Never surfaced in the UI.
  String? _lastError;
  String? get lastError => _lastError;

  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      // Best effort: clear the presence, then mark off.
      unawaited(clearActivity());
      _connected = false;
      _status = 'off';
    } else if (_status == 'off') {
      _status = 'idle';
    }
  }

  /// Show the current study subject on Discord. No-ops (silently)
  /// when disabled, when not inside a Discord Activity, or when
  /// Discord rejects the update.
  Future<void> setActivity({
    required String subject,
    required int startedAtMs,
  }) async {
    if (!_enabled) return;
    try {
      if (_bridge == null) {
        _status = 'unavailable';
        _lastError = 'discord bridge not loaded';
        return;
      }
      final ok = (await _bridgeSetActivity(
        'Studying $subject',
        'wannabeYPT',
        startedAtMs,
      ).toDart)
          .toDart;
      _connected = ok;
      _status = ok ? 'ready' : 'unavailable';
      if (!ok) _lastError = 'discord activity not available';
    } catch (_) {
      // Silent by design: presence is a bonus, never an error surface.
      _connected = false;
      _status = 'unavailable';
    }
  }

  /// Clear the Rich Presence. Safe to call when not connected.
  Future<void> clearActivity() async {
    try {
      if (_bridge == null || !_connected) return;
      await _bridgeClearActivity().toDart;
      _connected = false;
    } catch (_) {
      _connected = false;
    }
  }

  void dispose() {}
}

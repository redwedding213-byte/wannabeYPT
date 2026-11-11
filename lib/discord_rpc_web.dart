// wannabeYPT — Discord Rich Presence over the local RPC WebSocket (web)
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

// Talks to the Discord desktop client's local RPC server from the web app.
// EXPERIMENTAL — the browser is the awkward part, not the protocol:
//
//  * Chrome 147+ gates ws:// connections from a public HTTPS page to
//    loopback behind a Local Network Access permission prompt
//    ("loopback-network"); the user must allow it once. Safari blocks
//    ws:// from HTTPS pages as mixed content even to loopback. Firefox
//    allows it (loopback is a potentially trustworthy origin).
//  * Discord verifies the Origin header against the RPC Origins
//    registered for the application. A placeholder client ID (below)
//    is disconnected instantly; a real Discord application with
//    https://wannabeypt.vercel.app registered as an RPC Origin is
//    required before anything can show on Discord.
//  * Per Discord's docs, RPC commands require authentication (error
//    4006 otherwise). authorize() sends AUTHORIZE and returns the
//    OAuth code, but exchanging it for an access token needs the
//    application's client_secret, which cannot live in a browser —
//    that step needs a server and is NOT implemented here. SET_ACTIVITY
//    is attempted without auth first; a 4006 is treated as "needs
//    auth" and the service stops retrying until re-enabled.
//
// Everything here fails silently: Discord not running, connection
// refused, origin rejected, auth missing — no crash, no UI error,
// no retry loop. The next study start tries again.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'discord_rpc_protocol.dart';

class DiscordRpc {
  static final DiscordRpc instance = DiscordRpc._();

  DiscordRpc._();

  /// PLACEHOLDER — not a real application. Create an application at
  /// discord.com/developers, copy its client ID here, and register
  /// https://wannabeypt.vercel.app as an RPC Origin for it. Until
  /// then Discord disconnects every connection attempt instantly.
  static const String clientId = '1570010774070362212';

  /// Browsers have no process id; 0 is the placeholder web RPC clients use.
  static const int _pid = 0;

  static const Duration _portTimeout = Duration(milliseconds: 1500);
  static const Duration _readyTimeout = Duration(seconds: 3);

  bool _enabled = false;
  bool get enabled => _enabled;

  web.WebSocket? _socket;
  bool _connected = false;
  bool get connected => _connected;

  /// 'off' | 'idle' | 'connecting' | 'ready' | 'needs_auth' | 'unavailable'
  String _status = 'off';
  String get status => _status;

  /// Last failure, for diagnostics only. Never surfaced in the UI.
  String? _lastError;
  String? get lastError => _lastError;

  bool _connecting = false;
  bool _needsAuth = false;
  int _nonceCounter = 0;
  Completer<String?>? _authorizeCompleter;

  String _nonce() =>
      'wannabe-${DateTime.now().millisecondsSinceEpoch}-${_nonceCounter++}';

  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      _needsAuth = false;
      // Best effort: clear the presence, then drop the socket.
      unawaited(_sendRaw(DiscordRpcProtocol.clearActivityPayload(
        pid: _pid,
        nonce: _nonce(),
      )));
      _close();
      _status = 'off';
    } else if (_status == 'off') {
      _status = 'idle';
    }
  }

  /// Show the current study subject on Discord. Connects lazily on
  /// first use; no-ops (silently) when disabled or when Discord is absent.
  Future<void> setActivity({
    required String subject,
    required int startedAtMs,
  }) async {
    if (!_enabled || _needsAuth) return;
    try {
      if (!_connected) {
        final ok = await _connect();
        if (!ok) return;
      }
      await _sendRaw(DiscordRpcProtocol.setActivityPayload(
        pid: _pid,
        details: 'Studying $subject',
        state: 'wannabeYPT',
        startedAtMs: startedAtMs,
        nonce: _nonce(),
      ));
    } catch (_) {
      // Silent by design: presence is a bonus, never an error surface.
    }
  }

  /// Clear the Rich Presence. Safe to call when not connected.
  Future<void> clearActivity() async {
    try {
      if (!_connected) return;
      await _sendRaw(DiscordRpcProtocol.clearActivityPayload(
        pid: _pid,
        nonce: _nonce(),
      ));
    } catch (_) {}
  }

  /// Ask Discord to show the user an approval modal for this app and
  /// return the OAuth code, or null on timeout/denial. NOT called
  /// automatically: exchanging the code needs the client_secret on a
  /// server, so this only proves the modal path works.
  Future<String?> authorize() async {
    if (!_enabled) return null;
    try {
      if (!_connected) {
        final ok = await _connect();
        if (!ok) return null;
      }
      _authorizeCompleter = Completer<String?>();
      await _sendRaw(DiscordRpcProtocol.authorizePayload(
        clientId: clientId,
        scopes: const ['rpc'],
        nonce: _nonce(),
      ));
      return await _authorizeCompleter!.future.timeout(
        const Duration(seconds: 120),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    } finally {
      _authorizeCompleter = null;
    }
  }

  void dispose() => _close();

  // -- connection -------------------------------------------------------

  /// Try ports 6463..6472 in order; the first that answers READY wins.
  /// Returns false on every failure, without throwing.
  Future<bool> _connect() async {
    if (_connected) return true;
    if (_connecting) return false;
    _connecting = true;
    _status = 'connecting';
    try {
      for (var port = DiscordRpcProtocol.firstPort;
          port <= DiscordRpcProtocol.lastPort;
          port++) {
        try {
          final ready = await _tryPort(port).timeout(
            _portTimeout + _readyTimeout,
            onTimeout: () => false,
          );
          if (ready) {
            _status = 'ready';
            return true;
          }
        } catch (_) {
          // Next port.
        }
      }
      _status = 'unavailable';
      _lastError = 'no Discord RPC server on ports 6463-6472';
      return false;
    } finally {
      _connecting = false;
    }
  }

  /// Open one port and wait for the READY dispatch. False on any failure.
  Future<bool> _tryPort(int port) async {
    final url = DiscordRpcProtocol.rpcUrl(port, clientId);
    final socket = web.WebSocket(url);
    final open = Completer<bool>();

    void settle(bool value) {
      if (!open.isCompleted) open.complete(value);
    }

    socket.onopen = ((web.Event _) => settle(true)).toJS;
    socket.onerror = ((web.Event _) => settle(false)).toJS;
    socket.onclose = ((web.CloseEvent _) => settle(false)).toJS;

    final opened = await open.future.timeout(
      _portTimeout,
      onTimeout: () => false,
    );
    if (!opened) {
      try {
        socket.close();
      } catch (_) {}
      return false;
    }

    // Connected: attach the message pump and wait for READY.
    _socket = socket;
    final ready = Completer<bool>();
    socket.onmessage = ((web.MessageEvent e) {
      final data = e.data?.dartify();
      if (data is String) {
        _onMessage(data);
        if (!ready.isCompleted && _connected) ready.complete(true);
      }
    }).toJS;
    socket.onclose = ((web.CloseEvent _) {
      _connected = false;
      if (_socket == socket) _socket = null;
      if (!ready.isCompleted) ready.complete(false);
      if (_status == 'ready') _status = 'idle';
    }).toJS;
    socket.onerror = ((web.Event _) {
      _connected = false;
      if (!ready.isCompleted) ready.complete(false);
    }).toJS;

    final gotReady = await ready.future.timeout(
      _readyTimeout,
      onTimeout: () => false,
    );
    if (!gotReady) {
      _close();
      return false;
    }
    return true;
  }

  void _onMessage(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      final frame = DiscordRpcProtocol.classify(decoded);
      switch (frame.kind) {
        case 'ready':
          _connected = true;
          _needsAuth = false;
        case 'error':
          _lastError = 'discord rpc error ${frame.code}';
          if (frame.code == 4006) {
            // Not authenticated: stop retrying until re-enabled.
            _needsAuth = true;
            _status = 'needs_auth';
            _close();
          }
        case 'authorize':
          if (frame.codeString != null) {
            _authorizeCompleter?.complete(frame.codeString);
          } else {
            _authorizeCompleter?.complete(null);
          }
      }
    } catch (_) {}
  }

  Future<void> _sendRaw(Map<String, dynamic> payload) async {
    final socket = _socket;
    if (socket == null || socket.readyState != web.WebSocket.OPEN) return;
    socket.send(jsonEncode(payload).toJS);
  }

  void _close() {
    _connected = false;
    final socket = _socket;
    _socket = null;
    if (socket != null) {
      try {
        socket.close();
      } catch (_) {}
    }
  }
}

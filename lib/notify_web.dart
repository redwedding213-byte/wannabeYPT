// wannabeYPT — notification bridge (web implementation)
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

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSFunction? _fn(String name) {
  try {
    final v = globalContext.getProperty(name.toJS);
    if (v == null) return null;
    return v as JSFunction;
  } catch (_) {
    return null;
  }
}

/// Unlocks the shared WebAudio context from a user gesture, so the
/// phase-end beep actually sounds later (a context first created at
/// phase-end time, with no gesture in progress, may stay suspended).
void unlockAudio() {
  try {
    _fn('yptUnlockAudio')?.callAsFunction(null);
  } catch (_) {}
}

/// Shows a browser notification (and beep) via window.yptNotify.
void showAppNotification(String title, String body) {
  try {
    _fn('yptNotify')?.callAsFunction(null, title.toJS, body.toJS);
  } catch (_) {}
}

/// Shows a browser notification for a new group chat message via
/// window.yptNotifyChat. Clicking the toast opens that group's chat
/// through window.yptOnChatNotifyClick (see registerChatNotifyClick).
void showChatNotification(String title, String body, int groupId) {
  try {
    _fn('yptNotifyChat')
        ?.callAsFunction(null, title.toJS, body.toJS, groupId.toJS);
  } catch (_) {}
}

/// Registers the Dart callback invoked when a chat toast is clicked.
/// The JS side (web/index.html) calls window.yptOnChatNotifyClick
/// with the group id.
void registerChatNotifyClick(void Function(int groupId) onClick) {
  try {
    final cb = ((JSNumber v) {
      onClick(v.toDartInt);
    }).toJS;
    globalContext.setProperty('yptOnChatNotifyClick'.toJS, cb);
  } catch (_) {}
}

/// Current Notification.permission without prompting.
String notifyPermissionState() {
  try {
    final r = _fn('yptNotifyState')?.callAsFunction(null);
    if (r != null && r.isA<JSString>()) return (r as JSString).toDart;
  } catch (_) {}
  return 'unknown';
}

/// Asks for notification permission; resolves to the resulting state
/// ('granted' / 'denied' / 'default' / 'unsupported').
Future<String> requestNotifyPermission() async {
  try {
    final f = _fn('yptNotifyPerm');
    if (f == null) return 'unsupported';
    final res = f.callAsFunction(null);
    if (res != null && res.isA<JSPromise<JSString>>()) {
      final v = await (res as JSPromise<JSString>).toDart;
      return v.toDart;
    }
  } catch (_) {}
  return notifyPermissionState();
}

/// Updates document.title on web.
void setWebPageTitle(String title) {
  try {
    _fn('yptSetTitle')?.callAsFunction(null, title.toJS);
  } catch (_) {}
}

/// Sets whether the beforeunload close guard should prompt on exit.
void setWebCloseGuard(bool enabled) {
  try {
    _fn('yptSetCloseGuard')?.callAsFunction(null, enabled.toJS);
  } catch (_) {}
}

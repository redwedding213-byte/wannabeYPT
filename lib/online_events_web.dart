// wannabeYPT, browser online event bridge (web implementation)
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

@JS('window')
external JSObject get _jsWindow;

/// Registers [onOnline] to run when the browser regains connectivity
/// (e.g. the phone hotspot comes back). Failures to attach are swallowed,
/// the 60s retry timer in AppState is the backstop, so a missed event only
/// delays the sync, it never loses a session.
void listenForOnline(void Function() onOnline) {
  try {
    void handler(JSObject _) => onOnline();
    _jsWindow.callMethod(
      'addEventListener'.toJS,
      'online'.toJS,
      handler.toJS,
    );
  } catch (_) {}
}

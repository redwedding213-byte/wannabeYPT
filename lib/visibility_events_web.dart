// wannabeYPT, tab visibility event bridge (web implementation)
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

@JS('document')
external JSObject get _jsDocument;

@JS('window')
external JSObject get _jsWindow;

/// Calls [onVisible] when the tab becomes visible again
/// (visibilitychange to visible) or the window regains focus.
/// Focus is a backstop: some browsers restore a tab without a
/// visibilitychange. Failures to attach are swallowed; the 3s
/// chat poller is the backstop, so a missed event only delays a
/// toast, it never loses one.
void listenForVisible(void Function() onVisible) {
  try {
    void visHandler(JSObject _) {
      try {
        final state = _jsDocument.getProperty('visibilityState'.toJS);
        if (state != null &&
            state.isA<JSString>() &&
            (state as JSString).toDart == 'visible') {
          onVisible();
        }
      } catch (_) {}
    }
    _jsDocument.callMethod(
      'addEventListener'.toJS,
      'visibilitychange'.toJS,
      visHandler.toJS,
    );
    void focusHandler(JSObject _) => onVisible();
    _jsWindow.callMethod(
      'addEventListener'.toJS,
      'focus'.toJS,
      focusHandler.toJS,
    );
  } catch (_) {}
}

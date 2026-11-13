// wannabeYPT, file download bridge (web implementation)
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

/// Triggers a browser download of [url] saved as [filename].
/// Same-origin only: the download attribute is ignored for
/// cross-origin URLs, so the browser would navigate instead.
/// Chat images are served same-origin (/cdn-chat, /cdn-tg), so
/// this downloads the file instead of opening it.
void downloadFile(String url, String filename) {
  try {
    final a =
        _jsDocument.callMethod('createElement'.toJS, 'a'.toJS) as JSObject;
    a.setProperty('href'.toJS, url.toJS);
    a.setProperty('download'.toJS, filename.toJS);
    final body = _jsDocument.getProperty('body'.toJS);
    if (body != null) {
      final bodyObj = body as JSObject;
      bodyObj.callMethod('appendChild'.toJS, a);
      a.callMethod('click'.toJS);
      bodyObj.callMethod('removeChild'.toJS, a);
    }
  } catch (_) {}
}

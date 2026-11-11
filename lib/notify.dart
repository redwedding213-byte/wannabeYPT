// wannabeYPT, notification bridge
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

// Cross-platform notification bridge. On web this talks to the
// yptNotify helpers defined in web/index.html (Notification API +
// a short beep); everywhere else it is a no-op.
export 'notify_stub.dart'
    if (dart.library.js_interop) 'notify_web.dart';

// wannabeYPT, tab visibility event bridge
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

// Cross-platform bridge for the tab becoming visible again. On web
// this listens to document 'visibilitychange' and window 'focus';
// everywhere else it is a no-op. The 3s chat poller is the backstop,
// so a missed event only delays a toast, it never loses one.
export 'visibility_events_stub.dart'
    if (dart.library.js_interop) 'visibility_events_web.dart';

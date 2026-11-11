// wannabeYPT, browser online/offline event bridge
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

// Cross-platform bridge for the browser's `online` event. On web this
// listens to window 'online' (e.g. the phone hotspot comes back);
// everywhere else it is a no-op. The 60s retry timer in AppState is the
// backstop, so a missed event only delays the sync, it never loses it.
export 'online_events_stub.dart'
    if (dart.library.js_interop) 'online_events_web.dart';

// wannabeYPT — Discord Activity service (platform bridge)
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

// Discord Rich Presence through Discord Activities (Embedded App
// SDK). Web gets the real implementation (discord_activity_web.dart,
// via the JS bridge in web/discord-bridge.js); every other platform
// gets a no-op stub, because Activities only exist inside the Discord
// client. See discord_activity_web.dart for the flow and its two
// portal requirements (Public Client on, https://127.0.0.1 redirect).
export 'discord_activity_stub.dart'
    if (dart.library.js_interop) 'discord_activity_web.dart';

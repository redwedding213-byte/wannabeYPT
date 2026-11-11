// wannabeYPT — Discord Rich Presence service (platform bridge)
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

// Discord Rich Presence over the local RPC WebSocket. Web gets the real
// implementation (discord_rpc_web.dart); every other platform gets a
// no-op stub, because the RPC server only exists next to a running
// Discord desktop client and a browser page can only reach it via
// ws://127.0.0.1. See discord_rpc_protocol.dart for the protocol notes
// and the two hard gates (registered RPC Origin, OAuth authentication).
export 'discord_rpc_stub.dart'
    if (dart.library.js_interop) 'discord_rpc_web.dart';

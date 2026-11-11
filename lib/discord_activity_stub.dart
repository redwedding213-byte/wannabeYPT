// wannabeYPT — Discord Activity stub (non-web platforms)
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

// No-op DiscordActivity for non-web builds: same API as
// discord_activity_web.dart, every call silently does nothing.
class DiscordActivity {
  static final DiscordActivity instance = DiscordActivity._();

  DiscordActivity._();

  bool get enabled => false;
  bool get connected => false;

  /// 'off' on the stub, always.
  String get status => 'off';

  String? get lastError => null;

  void setEnabled(bool value) {}

  Future<void> setActivity({
    required String subject,
    required int startedAtMs,
  }) async {}

  Future<void> clearActivity() async {}

  void dispose() {}
}

# wannabeYPT

YPT (열품타) in your browser. The official app has no web or PC version, so
this is an unofficial web client: your real YPT account — timers, groups,
stats — running in a browser tab. Live at
<https://wannabeypt.vercel.app>.

Built on the open-source client
[deveworld/ypt_client](https://github.com/deveworld/ypt_client) (MIT),
with the web layer, Google login, stats, planner and group features added
on top. Full credit to deveworld for the base client — see NOTICE.

Honestly built: the code was written by an AI assistant under the
project owner's direction; the idea, name, design, features, testing and
launch are his.

## Important Notice

- This project is **unofficial**. It is not affiliated with, sponsored by,
  or endorsed by YPT, Pallo Inc., or related rights holders.
- It is intended only for your own account's interop — real timers on the
  real service. It is not for manipulating another account, automation
  abuse, or study-time fabrication.
- It talks to YPT's undocumented HTTPS API at `pi.tgclab.com`. Behavior can
  break without warning and may conflict with the service's terms.
- Login goes from your browser straight to YPT's servers. The session JWT
  is stored in your browser's localStorage (`flutter.jwt`). Nobody else's
  server sees your password.

## What It Does

- Email + Google login (Google via the `/google-login.html` OAuth helper —
  exchanges your Google profile for a YPT JWT, written to localStorage)
- Per-subject study timer with D-Day chip and device-local daily goal
- Rebuilt Statistics: month heatmap, day detail, week/month/trend views
- Planner tab: week strip, day timetable from sessions, per-day to-dos
  (task toggle and create work on the server)
- Group room: Home / Attendance / Rankings / Invite (QR + invite link)
- Group chat: message list, send, reactions, stickers, image-URL paste
- Member profiles as a right-side panel; self-profile with focus heatmap
- Pomodoro panel with focus/break steppers and phase-end notifications
- Classic YPT look, kept deliberately familiar

Deliberately not built: Books/flashcards, Challenge, Music, Timelapse.
Beyond reading, the app writes timer start/stop, task toggles/creation,
and group chat messages to the server.

## Build & Deploy

```bash
flutter pub get
flutter build web --release
```

Every deploy must also copy the three static files into the deploy root:

- `static/google-login.html` — Google OAuth helper for YPT login
- `static/privacy.html` — Privacy policy
- `static/terms.html` — Terms of service

```bash
cp static/google-login.html static/privacy.html static/terms.html <deploy-root>/
```

The deployed Flutter output on this machine is staged at
`~/workspace/ypt-web-dist` and pushed to Vercel with:

```bash
python3 skills/vercel-deploy/bin/deploy.py ypt-web-dist --project ypt-web
```

Note for future maintainers: the Flutter web build needs
`TAR_OPTIONS=--no-same-owner` when the SDK archive is extracted as root.

## Project Layout

```text
lib/                 Flutter app source
  ypt_api.dart       YPT API client (undocumented API kept isolated here)
  app_state.dart     Provider state: auth, timer, stats, groups
  models.dart        API response models
  screens/           login, home, timer, stats, planner, group room,
                     member profiles
  notify*.dart       Cross-platform notification bridge (web-only)
static/              google-login.html, privacy.html, terms.html —
                     copied into the deploy root on every deploy
web/                 Flutter web target (title, manifest, icons)
landing/             Leftover Next.js landing from the base client
linux/ macos/        Flutter desktop targets (from the base client;
windows/             desktop direction is Windows-first, future work)
```

## API Notes (hard-won)

- Weekly ranks (`GET /logs/group/member/ranks?...&type=week`) only work
  when `date` is the week's **Monday**; today's date or Sunday → empty.
- The members endpoint ignores `&date`; per-day ranks routes silently omit
  some members — match by `userId` **or** nickname.
- `GET /logs/group/attendance` is a dead end (errors on every variant) —
  the Attendance tab is built client-side from per-day type=day ranks calls.
- A day log with `id: -1` is today; past days carry real ids.

## Contributing

Pull requests welcome. Keep undocumented API behavior isolated in
`lib/ypt_api.dart`, parse defensively (the API changes field names without
warning), and don't build write-paths that fake study data — read-only
honesty about server limits is a standing rule.

## License

This project is licensed under the
[GNU Affero General Public License v3.0](LICENSE) (AGPL-3.0-only).

The base client it is built on (deveworld/ypt_client) is MIT licensed —
see NOTICE for the original copyright and terms.

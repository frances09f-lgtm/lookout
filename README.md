# Lookout (V1)

Your personal background agent. Tell Lookout what to watch; it keeps checking in
the background and notifies you when your condition is met. Not a chatbot.

## What V1 does (and honestly does not)

Works today:
- **Reminders** - "Remind me in 2 hours if this task hasn't been completed"
  fires a notification when due. Fully automatic.
- **Value watch** - "Tell me when this product becomes cheaper than ₹50,000"
  tracks the condition in the background. V1 has no web fetching, so you
  update the current value on the agent page; Lookout evaluates the condition
  on every check (every 15-30 min) and notifies when it crosses. Previous vs
  current value is tracked.
- Background checks run via Android WorkManager and survive app close and
  device reboot. Pause / Resume / Run now / Delete per agent. Full activity
  log per check ("Started check", "Fetched data", "Condition met/not met",
  "Notification sent", "Next check scheduled"). Local SQLite storage.
  Dark + light Material 3. No login, no analytics, no accounts.

Not in V1 (marked in the app, never faked):
- Webpage/website monitoring (V2) - the parser recognises these requests and
  says so instead of pretending.
- Unrestricted natural-language automation (V3).

## Project structure

```
lib/
  domain/        Agent model, ActivityEntry, deterministic goal parser
  data/          AgentRepository interface, in-memory (tests), sqflite (prod)
  services/      checker (check engine shared by worker + Run now),
                 notifications, background (WorkManager bridge)
  presentation/  Home / Create Agent / Agent Details / Activity screens,
                 theme (M3 dark+light)
```

## Architecture / bridge

- Local-first: all state in SQLite (sqflite). No server.
- Background execution: Flutter registers a periodic task with the
  `workmanager` plugin, whose Android side is native Kotlin WorkManager.
  Every cycle runs `lookoutCallbackDispatcher`, which opens the database,
  checks all due agents, posts notifications, and reschedules - headless.
  Failed cycles return `false` so WorkManager retries with backoff.
- The same `AgentChecker` powers background checks and the "Run now" button,
  so manual and scheduled behaviour are identical.

## Permissions

- `POST_NOTIFICATIONS` only (requested at runtime on Android 13+).
- No `INTERNET` permission in V1 - nothing in V1 uses the network.
- No boot receiver: WorkManager reschedules itself across reboots.

## Android limitations (inherent, not bugs)

- WorkManager's minimum periodic interval is 15 minutes, so check intervals
  start at 15 min. Android may also delay cycles under battery pressure
  (Doze). Exact per-second scheduling is not possible for periodic work.
- Some OEMs (Xiaomi/Oppo/Vivo) aggressively kill background work; keep
  battery optimisation unrestricted for Lookout for the most reliable timing.

## Setup & test

```
flutter pub get
flutter test      # 14 tests: parser, check engine, repository, UI smoke
flutter run       # debug build on a device/emulator
```

Release builds are signed with a persistent keystore (CI restores it from
repo secrets) and auto-increment versionCode/versionName from the CI run
number, so updates install in place.

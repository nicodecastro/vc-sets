# VC SETS

VC SETS (Statistics & Event Tracking System) helps the UPLB Volleyball Club run tournaments and record volleyball matches. Organizers set up teams and fixtures, while two scorers track the same match on separate devices. Afterward, they compare the rally logs, resolve differences, and finalize one record for standings and player statistics.

The app is built with Flutter for Windows, Android, and the web. Match data is stored on each device, so scoring does not depend on a live connection between the scorers.

## What it does

- Set up tournaments, teams, rosters, and match rules. Generate round-robin fixtures, pool play followed by a knockout bracket, or a knockout-only bracket. Optional third-place matches are supported.
- Score rallies on two devices. Each scorer records rally winners and player actions for an assigned team.
- Import the other scorer's log, compare rallies and scores, resolve discrepancies, and finalize the match.
- View standings and player totals from finalized matches. Export standings, player statistics, and R-5/substitution records as CSV, or generate a printable report.
- Export a full backup of tournament data and restore it later.

## Run the app

The repository includes Windows and Android Flutter targets and a web app with an installable PWA manifest. A GitHub Pages workflow builds and deploys the web version when configured for the repository.

**Web app:** [VC SETS](https://nicodecastro.github.io/vc-stats/). Open it once while connected; your browser's install option may then be available, depending on the browser and device.

To run from source, install Flutter and use these commands from `app/`:

```powershell
flutter pub get
flutter run -d windows
```

For the web version, run `flutter run -d chrome`. For Android, connect a device or start an emulator, check its ID with `flutter devices`, then run `flutter run -d <device-id>`.

## Match-day workflow

1. On the tournament device, create the tournament, teams, rosters, and fixture.
2. Export the fixture as a `.vcgame` package and import it on the second device.
3. Assign one team to each scorer and select the same first server on both devices.
4. Both scorers award each rally. Each records player actions for their assigned team.
5. Export the second scorer's completed `.vcgame` package and import it on the tournament device.
6. Compare the logs, resolve highlighted differences, and finalize the official match. Export a backup after match day.

## How it works

Flutter provides the Windows, Android, and web interfaces. Drift stores app data in a local SQLite file on native platforms and a browser SQLite database through WebAssembly on the web. The web build includes the SQLite WebAssembly file and Drift worker, so it does not fetch them from a runtime CDN.

Devices exchange `.vcgame` files instead of syncing through a server. Each package is JSON with a versioned manifest and a SHA-256 payload hash for integrity checking. The app records imported package IDs to prevent duplicate imports. During reconciliation, it compares rally winners and scores from both devices, lets the organizer choose corrections, and merges the player actions into an official log. Standings and player totals use finalized matches.

## Development

From `app/`:

```powershell
flutter pub get
flutter test
flutter run -d windows
flutter run -d chrome
```

## Data and backups

Tournament and match data stays in the device's local database until someone exports it. The GitHub Pages deployment serves the app files; it does not store match data. `.vcgame` packages and full backups are plain JSON and may contain player names and other roster information. Store and share exported files accordingly.

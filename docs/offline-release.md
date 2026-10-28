# Offline launch release checklist

The implementation targets Chrome/Edge on desktop, Android Chrome, and Safari installed to the iPhone/iPad home screen. Automated Chromium and WebKit checks are deployment gates; they do not replace physical-device checks. Do not announce Android or iOS offline launch as verified until the corresponding checks below have passed on the release candidate.

## Local automated verification — 2026-10-27

The Flutter 3.47.6 release build and all 75 Dart tests passed. All 12 browser checks passed on Windows using Playwright 1.62.1 with Chromium and WebKit. These include full browser-process restarts using a saved profile, offline scoring and exports, interrupted preparation and retry, rejected persistence requests, unavailable storage, unsupported service workers, failed updates, activation after every app window closes, and cache isolation. A separate cold-start check passed in the installed Microsoft Edge browser. The phone-sized readiness layout was also inspected.

## Physical-device checks — pending

Record the release commit, OS/browser versions, device, date, and result for each run. Real devices are not available in the development environment used for this change.

- [ ] Android Chrome: open the release online and wait for **Ready for offline use**. Install it, open the installed app online, and confirm readiness there.
- [ ] iPhone Safari: add to home screen, open the installed app online, and wait for readiness. Repeat on iPad.
- [ ] Create/import a tournament and roster, start a scorer log, and save a lineup on each device.
- [ ] Fully close the installed app and browser, enable airplane mode, and reopen from the home screen. Confirm the saved tournament and scorer log remain.
- [ ] Record a rally offline, close and reopen again, and confirm it persists. Open reports and export CSV plus a full backup locally. Cloud-only files may require a connection; use locally saved files when testing imports.
- [ ] Reconnect and deploy a prepared second release. Keep the old app open and confirm no reload interrupts scoring. Close every app/browser window for the site, then reopen and confirm the update and data both survive another offline launch.
- [ ] Interrupt first-time preparation. Confirm readiness is not displayed; reconnect and retry successfully.

## Expected limits

The initial download requires a connection and enough available storage for the full application. A new release temporarily requires room for both the old and new caches. A failed download or hash mismatch keeps the prior release active. Updates activate only after all controlled windows close; there is no forced update button.

Readiness confirms this release's cached files and successful database startup. Persistence requests are best effort. Clearing site data removes the database and offline files; restoring a backup does not restore the application cache. Installing the home-screen app may use storage separate from an existing browser session, so prepare and verify it in the app you will use on match day.

GitHub Pages continues to serve static files only. Match data remains in the existing device database; no server or synchronization service is introduced. Worker caches are scoped to the deployed repository path. Do not move that URL or database name as part of a routine app update.

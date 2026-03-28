# SK Mole

SK Mole is a native macOS maintenance toolkit inspired by Mole, CleanMyMac, AppCleaner, DaisyDisk, and iStat Menus. It is designed around a safety-first workflow: preview before action, protect system-critical paths, and move user-facing deletions to Trash instead of permanently removing files.

## Included modules

- Dashboard with live CPU, GPU activity, memory, disk, and network telemetry
- Cleanup center for caches, logs, browser leftovers, developer artifacts, and Trash
- App uninstaller that previews user-domain remnants before moving them to Trash
- Storage analyzer for category breakdowns and large-file discovery
- Optimize center for low-risk cache and system-service refresh actions
- Privileged helper architecture for carefully scoped admin-only maintenance tasks

## Safety boundaries

- System-critical folders are blocked from cleanup and uninstall actions
- Protected Apple apps are not removable
- Cleanup and uninstall actions only operate inside curated allow-lists
- Destructive actions use Finder Trash where possible
- The app exposes only low-risk service refresh tasks that do not require root
- Admin-only tasks are isolated behind a signed helper allow-list instead of arbitrary elevated shell execution

## GitHub-ready layout

- `Sources/` contains the main app, shared helper contract, and privileged helper target
- `Resources/` contains only source assets and bundle templates that can be reproduced locally
- `.github/workflows/ci.yml` runs build, tests, and app bundling on macOS
- `.gitignore` excludes `.build`, `dist`, generated icon outputs, and other machine-local artifacts

## Privileged helper

The helper is packaged as a launch daemon and is intentionally narrow:

- `flushDNSCache`
- `runPeriodicDaily`

See [`docs/PRIVILEGED_HELPER.md`](docs/PRIVILEGED_HELPER.md) for the design and signing notes.

## Build

For development:

```bash
swift run SKMoleApp
```

To package a standalone `.app` bundle:

```bash
./scripts/build-app.sh
```

The generated app bundle is created in `dist/SK Mole.app`.

To package a distributable `.dmg`:

```bash
./scripts/build-dmg.sh
```

The generated disk image is created in `dist/SK-Mole-1.0.0.dmg`.

For production helper registration, sign with a real Apple identity:

```bash
SKMOLE_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

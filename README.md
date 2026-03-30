# SK Mole

SK Mole is a native macOS maintenance toolkit inspired by Mole, CleanMyMac, AppCleaner, DaisyDisk, iStat Menus, and Cork. It is designed around a safety-first workflow: preview before action, protect system-critical paths, isolate admin-only work behind a helper, and keep destructive operations tightly scoped.

## Included modules

- Dashboard with live CPU, GPU activity, memory, disk, and network telemetry, plus history views and a smoother long-scroll layout
- Homebrew manager for packages, casks, `brew services`, maintenance, doctor follow-up, curated recommendations, and GitHub CLI workflows
- Network inspector for processes, remote hosts, connections, and interfaces
- Quarantine review tab for quarantined app bundles with explicit `xattr` actions
- Smart Care recommendations across cleanup, storage, permissions, and app health
- Cleanup center for caches, logs, browser leftovers, developer artifacts, installers, downloads, and Trash
- App uninstaller with remnant previews, reset flows, and Trash-app review
- Storage explorer with multi-volume drill-down, focus filters, and large-file actions
- Optimize center for low-risk cache, system-service, and helper-backed admin maintenance actions
- Menu bar companion for compact monitoring and quick actions

## Developer workflows

- Homebrew installation can be launched from SK Mole without Apple Events automation permission; the app now opens a temporary Terminal `.command` script instead of scripting Terminal directly
- GitHub CLI install/auth flows are surfaced in the Homebrew area, including auth-status refresh, PAT links, and repository listing for the signed-in account
- Homebrew doctor output can surface actionable unexpected-dylib follow-up directly in the UI
- Homebrew inventory loading is hardened so noisy or partial `brew` JSON output does not collapse the whole tab into a decode error

## Safety boundaries

- System-critical folders are blocked from cleanup and uninstall actions
- Protected Apple apps are not removable
- Cleanup, uninstall, quarantine, and developer-tool actions only operate inside curated allow-lists
- Cleanup removals are intentionally constrained to reviewed locations, while app removal uses Trash-first handling for user-domain remnants
- Quarantine review only removes `com.apple.quarantine`; it does not spoof signatures or bypass broader Gatekeeper trust decisions
- The app exposes only low-risk service refresh tasks directly; admin-only tasks are isolated behind a signed helper allow-list instead of arbitrary elevated shell execution

## Notes for testers

- The packaged app in `dist/` is ad-hoc signed in this workspace, so the main UI is testable but privileged-helper registration still requires a real Apple signing identity
- Quarantine actions use the system `xattr` tool directly from SK Mole and do not require Terminal automation permission
- Homebrew install/auth flows should now open Terminal normally without requiring Terminal Apple Events authorization
- The DMG includes both `SK Mole.app` and this `README.md` for distribution

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

The generated disk image is created in `dist/SK-Mole-1.0.0.dmg` and now includes both `SK Mole.app` and this `README.md`.

For production helper registration, sign with a real Apple identity:

```bash
SKMOLE_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

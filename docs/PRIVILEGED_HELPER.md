# Privileged Helper Design

SK Mole keeps its main app process unprivileged. Admin-only work is isolated into a separate launch daemon helper that exposes a very small XPC allow-list.

## Why this exists

- The main app should not run as root
- Admin-only maintenance tasks should be explicit and tightly scoped
- Packaging and signing should be reproducible for GitHub clones and CI builds

## Included admin-only tasks

- `flushDNSCache`
  - Runs `dscacheutil -flushcache`
  - Sends `HUP` to `mDNSResponder`
- `runPeriodicDaily`
  - Runs `periodic daily`

These are intentionally conservative. The helper does not accept arbitrary commands, paths, shell fragments, or file deletion requests.

## Bundle layout

The app packaging script installs the helper assets here:

- `Contents/Library/LaunchServices/com.siveesh.skmole.privilegedhelper`
- `Contents/Library/LaunchDaemons/com.siveesh.skmole.privilegedhelper.plist`

## Signing

`./scripts/build-app.sh` signs the helper binary first and the enclosing app bundle second.

- Default: ad-hoc signing for local smoke tests
- Production helper registration: set `SKMOLE_CODESIGN_IDENTITY` to a real Apple signing identity

Example:

```bash
SKMOLE_CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
```

Ad-hoc signing is enough to build and launch the app locally, but a privileged helper registration flow should use a real certificate and matching app/helper identity.

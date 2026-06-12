# Releasing NoNap

NoNap uses git tags to cut releases. Pushing a tag like `v1.0.0` triggers the
[release workflow](.github/workflows/release.yml), which builds `NoNap.dmg` and
`NoNap.zip` and publishes them as a GitHub Release with auto-generated notes.

## Cut a release

1. Bump the version in `Resources/Info.plist`:
   - `CFBundleShortVersionString` — the marketing version (e.g. `1.1`).
   - `CFBundleVersion` — the build number (e.g. `2`); bump on every release.

2. Commit the bump:
   ```bash
   git commit -am "Release v1.1.0"
   ```

3. Tag and push:
   ```bash
   git tag v1.1.0
   git push origin main --tags
   ```

4. GitHub Actions builds the app and attaches `NoNap.zip` to a new Release.
   Edit the release notes on GitHub if you want to add highlights.

## Build a release locally

```bash
./Scripts/make_dmg.sh        # produces NoNap.dmg
./Scripts/package_zip.sh     # produces NoNap.zip
```

## A note on signing

Releases are **ad-hoc signed**, not notarized — users must right-click → Open on
first launch (see the README). For warning-free distribution, add a
*Developer ID* signature + notarization (Apple Developer account, $99/yr) to
`Scripts/make_app.sh` before the zip step.

# xiren

Personal iPhone app for the ezVille (S&D 스마트홈) home network, focused on one-tap 공동현관 door opening. Built with Tuist, signed with fastlane match, and shipped to TestFlight only.

## Build

```bash
tuist generate --no-open   # creates Xiren.xcworkspace
```

Scheme: `XireniOS` (iPhone app + `XireniOSTests`).

Configurations get their own bundle IDs so they install side by side: Debug `app.xiren.debug.ios`, Development `app.xiren.dev.ios`, Production `app.xiren.ios`.

The version lives in `Project.swift` (`CFBundleShortVersionString`). The build number is not committed; pass it through `TUIST_BUILD_NUMBER`, which fastlane sets from TestFlight at release time.

## Release

"Release the next version" means: decide the version, write the release notes, trigger the **Release** workflow, and watch it.

The app ships to **TestFlight only** and is never submitted to the App Store, so there is no listing, no metadata and no screenshots - only Beta App Review.

### 1. Decide the version

- If the user gives an exact version (e.g. `0.2.0`), use it as-is.
- Otherwise look at the changes since the last release:
  ```bash
  git fetch --tags
  git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..origin/main --oneline
  ```
  - **minor** (`x.Y.0`): new features, UI changes, new behaviors
  - **patch** (`x.y.Z`): bug fixes, performance, refactors, dependency updates
- **Never bump major.** Only the owner does that.
- If there are no tags yet, the first release is the version already in `Project.swift`.
- Tags have no `v` prefix (`0.2.0`, not `v0.2.0`).

### 2. Write the release notes

Rewrite `fastlane/release_notes.txt`, commit it, and **push to `main`** before triggering; the workflow builds from `main`.

It becomes TestFlight's "What to Test", written for testers: what changed and what to try. Nothing user-facing? Say so: "Internal cleanup only. Nothing new to test, just check that a door still opens." Plain text, English, a few short lines, most important change first. No emoji, no markdown.

The GitHub Release notes are auto-generated from merged PRs, so don't write those.

### 3. Trigger and watch

```bash
gh workflow run release.yml -f version=X.Y.Z
sleep 5
gh run watch "$(gh run list --workflow release.yml --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
```

Report the result with the GitHub Release URL (`gh release view X.Y.Z --json url -q .url`).

### What the workflow does

1. Validates `x.y.z` and that the tag doesn't exist yet.
2. `fastlane bump version:X.Y.Z` sets the version in `Project.swift` and commits locally.
3. `fastlane ios beta` takes the next build number from TestFlight (latest + 1), passes it to `tuist generate` through `TUIST_BUILD_NUMBER`, signs with match, builds the `Production` configuration of the `XireniOS` scheme, uploads it to TestFlight, waits for processing, and submits it to the external **Beta Testers** group (Beta App Review).
4. Only after all of that succeeds: pushes the bump commit to `main`, tags `X.Y.Z`, and creates the GitHub Release (notes only; TestFlight builds aren't attached anywhere).

### If a release fails

Don't re-run the same version: a TestFlight build may already be uploaded. Find the cause from the run log (`gh run view <id> --log-failed`), fix it on `main`, and release the **next patch** version. Failed versions stay skipped.

### Required GitHub secrets

| Secret | Value |
| --- | --- |
| `MATCH_PASSWORD` | Passphrase for the `devxoul/xiren-match` repo |
| `MATCH_GITHUB_PAT` | GitHub PAT with read-only `Contents` access to `devxoul/xiren-match` |
| `APP_STORE_CONNECT_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect API issuer ID |
| `APP_STORE_CONNECT_API_KEY_P8_BASE64` | `base64` of the `.p8` key file |
| `APP_REVIEW_PHONE_NUMBER` | Phone number for the Beta App Review contact, e.g. `+82 10-0000-0000` |

To release from a Mac instead, set `MATCH_PASSWORD`, `APP_STORE_CONNECT_API_KEY_KEY_ID`, `APP_STORE_CONNECT_API_KEY_ISSUER_ID` and `APP_STORE_CONNECT_API_KEY_KEY_FILEPATH` in the environment and run `bundle exec fastlane ios beta`.

## Signing

Certificates and profiles live in the private `devxoul/xiren-match` repo, encrypted with `MATCH_PASSWORD`; the profile is `match AppStore app.xiren.ios`. CI runs match read-only through `setup_ci`. Creating or renewing them happens locally only.

This repo is public: never commit a `.p8` key, a `.env`, the match password or any other credential. They belong in GitHub secrets, the owner's keychain or `~/Downloads` - never in git.

## App Store Connect

One-time setup before the first release, none of which the API key can do:

- an app record for `app.xiren.ios`, which needs an Apple ID login and 2FA, since the App Store Connect API can't create apps:

  ```bash
  bundle exec fastlane produce --username devxoul@gmail.com --app_identifier app.xiren.ios --app_name Xiren --sku app.xiren.ios --language en-US --platform ios
  ```

- an external tester group named **Beta Testers**, with the testers invited

The bundle ID `app.xiren.ios` is already registered on the Developer portal.

## Safety

Never send actuating requests (`openDoor.ifttt`, `individualctrl*.ifttt` with `power`/`settemp`/`state`, gas valve, elevator) while developing or testing. The app ships with Dry Run on; keep tests offline.

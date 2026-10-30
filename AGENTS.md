# xiren

Personal iPhone app for the ezVille (S&D 스마트홈) home network, focused on one-tap 공동현관 door opening. Built with Tuist.

## Build

```bash
tuist generate --no-open   # creates Xiren.xcworkspace
```

Scheme: `XireniOS` (iPhone app + `XireniOSTests`).

Configurations get their own bundle IDs so they install side by side: Debug `app.xiren.debug.ios`, Development `app.xiren.dev.ios`, Production `app.xiren.ios`.

The version lives in `Project.swift` (`CFBundleShortVersionString`). The build number is not committed; pass it through `TUIST_BUILD_NUMBER`.

## Safety

Never send actuating requests (`openDoor.ifttt`, `individualctrl*.ifttt` with `power`/`settemp`/`state`, gas valve, elevator) while developing or testing. The app ships with Dry Run on; keep tests offline.

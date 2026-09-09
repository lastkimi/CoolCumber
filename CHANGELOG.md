# Changelog

## 1.2.0 Beta — 2026-08-20

- Rebuilt CoolCumber as a quiet, menu-bar-first macOS health monitor with a
  resizable native dashboard and explicit loading, stale, unsupported, and
  unavailable states.
- Added a typed telemetry model with units, provenance, bounded persistence,
  future-timestamp rejection, schema validation, and 83 unit tests.
- Added real local CPU, memory, thermal-pressure, storage, battery, Widget, and
  supported hardware readings without simulated fallback values.
- Replaced the legacy privileged service with a signed, caller-validated v2
  helper limited to bounded temperature and fan-speed reads.
- Removed process termination, process freezing, fan writes, battery writes,
  destructive cleaning, synthetic memory pressure, external AI telemetry, and
  in-app self-updating from the production source tree.
- Added Free/Pro entitlements: 24-hour history in Free; 30-day history, local
  trusted alerts, and spreadsheet-safe CSV export in Pro.
- Added a StoreKit 2 lifetime purchase and restore flow for the Mac App Store.
  The launch price is US$19.99; Direct purchasing remains fail-closed until a
  signed license service is deployed.
- Added English and Simplified Chinese UI, first-run guidance, accessibility
  improvements, light/dark appearances, and a real App Group-backed Widget.
- Added Debug/Beta/Release CI across Direct and Mac App Store channels, secret
  scanning, channel-boundary checks, signed-artifact validation, notarization
  recovery, and sealed-archive App Store upload gates.

Beta Preview access is temporary and free. Direct Beta builds expire no later
than 2026-09-30 and safely return to Free when the preview window ends.

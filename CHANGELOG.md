# Changelog

## 1.2.0 Build 4 — Limited Beta candidate — 2026-10-20

Build 4 is reserved for a small, free Beta. It is not the paid production
upload and must not be attached to the US$19.99 Pro App Store submission. After
the Beta and its feedback are complete, the paid release will use a unique
higher build number, currently planned as build 5.

- Removed the optional notch SmartBar surface and its externally inspired
  detection routine. That historical routine followed display-cutout ideas from
  [SuperIsland](https://github.com/shobhit99/SuperIsland); no SuperIsland code or
  asset remains in either current target. The menu bar remains the universal
  primary entry point on both 2019 Intel and Apple silicon Macs.
- Corrected Mac App Store documentation: Pro alerts are opt-in notifications
  for fresh serious or critical thermal pressure reported by macOS; the
  sandboxed edition does not offer a configurable CPU-temperature threshold.
- Recorded the actual build-3 validation boundary: no external TestFlight beta
  occurred, core-model and native-render checks passed, and the full macOS XCUI
  run was blocked by active system authentication.
- Require new visual evidence after every candidate UI change; legacy concept
  art and simulated telemetry remain prohibited.
- Renewed the bounded Beta Preview window for both channels in build 4 from
  2026-10-20 to 2026-12-04 UTC. Both channels fail closed to Free after that
  window, independently of TestFlight's distribution expiry. Beta access must
  not be represented as a purchase or permanent license.

## 1.2.0 Internal Beta implementation — 2026-08-20

This work was validated internally. Build 3 had no external TestFlight group or
tester, so it was not a completed public or limited external Beta and produced
no external Beta-user feedback.

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
  The planned launch price is US$19.99; Direct purchasing remains fail-closed
  until a signed license service is deployed.
- Added English and Simplified Chinese UI, first-run guidance, accessibility
  improvements, light/dark appearances, and a real App Group-backed Widget.
- Added Debug/Beta/Release CI across Direct and Mac App Store channels, secret
  scanning, channel-boundary checks, signed-artifact validation, notarization
  recovery, and sealed-archive App Store upload gates.

Beta Preview access is temporary and free. Direct Beta builds expire no later
than 2026-09-30 and safely return to Free when the preview window ends.

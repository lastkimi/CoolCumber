# CoolCumber

**English** | [中文](README_zh.md)

CoolCumber is a quiet, local-first health monitor for macOS 13 and later. It
shows what the Mac can actually report, marks stale or unsupported readings
explicitly, and never fills missing sensor data with invented values.

## What it does

- A lightweight menu bar summary and a resizable native macOS dashboard.
- Trusted CPU load, memory, thermal-pressure, storage, battery, and supported
  hardware readings with source and freshness information.
- A WidgetKit extension that reads the latest real snapshot through an App
  Group and clearly shows stale or unavailable data.
- Compact local history: 24 hours in Free, up to 30 days in Pro.
- Pro local health alerts based on fresh available readings, plus
  spreadsheet-safe CSV history export.
- English and Simplified Chinese UI, including a menu-bar-first experience for
  2019 Intel MacBook Pro models without a display notch.

CoolCumber does not automatically kill or freeze processes, manufacture memory
pressure, clean personal application data, change battery charging behavior, or
write fan settings. Unsupported controls are not sold as Pro features.

## Editions and pricing

The Mac App Store edition is sandboxed and never installs a privileged helper.
Some low-level temperature and fan sensors are therefore unavailable and are
shown as such. The Direct edition can offer an explicitly approved, signed
helper for supported read-only hardware monitoring.

Core live monitoring and 24-hour local history are free. CoolCumber Pro is a
one-time, non-consumable Mac App Store purchase launching at US$19.99. Pro adds
30-day local history, configurable local alerts, and CSV export. The first paid
launch is Mac App Store only; Direct checkout stays disabled until a signed
license service and public verification key are deployed. Beta Preview builds
temporarily unlock eligible Pro features without creating a purchase or
permanent license. Direct previews carry a fixed access window of no more than
45 days and fail closed to Free after it expires.

## Privacy and security

Telemetry and history remain on the Mac. CoolCumber contains no advertising or
third-party analytics and does not upload telemetry by default. See
[PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

Official Direct builds are signed with Developer ID and notarized by Apple.
Mac App Store builds are distributed by Apple. Do not install unsigned mirrors.
Release changes are recorded in [CHANGELOG.md](CHANGELOG.md).

## Build from source

Requirements: Xcode, Swift 5.9 or later, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
xcodegen generate
swift test --package-path Packages/ThermFlowCore
xcodebuild -project MacThermFlow.xcodeproj -scheme ThermFlowApp \
  -configuration Debug -destination 'platform=macOS' build
```

The repository keeps Direct and Mac App Store capabilities separate. Run the
checked-in release gates before producing distribution artifacts:

```bash
Scripts/ci-secret-scan.sh
Scripts/check-project-boundaries.rb project.yml 1.2.0 3
```

## License

Source code in this repository is available under the [MIT License](LICENSE).

# CoolCumber 1.2 — App Store Connect metadata

This file records release identities for the sandboxed Mac App Store product.
Version 1.2.0 build 4 is reserved for the free TestFlight Beta; it is not the
paid production upload. On 20 October 2026 the owner explicitly instructed a
direct production and US$19.99 Pro launch without waiting for external Beta
feedback. Build 5 is the formal Release candidate. Its archive, screenshots,
checksums and provider status must be recorded from that exact candidate;
this document alone is not evidence of public availability.

## App information

- App name: `CoolCumber - Thermal Monitor`
- Subtitle: `Trusted Mac Health Monitor`
- Bundle ID: `com.slmcamp.CoolCumber`
- SKU: `COOLCUMBER_001`
- Primary category: Utilities
- Version: `1.2.0`
- Limited free Beta build: `4`
- Formal production candidate build: `5` (provider status is recorded separately)
- Copyright: `© 2026 Hangzhou Inkblaze AI Technology Co., Ltd.`
- Beta price: Free; Beta access is temporary and creates no purchase
- Planned production price: Free with In-App Purchase
- Marketing URL: `https://github.com/lastkimi/CoolCumber`
- Support URL: `https://github.com/lastkimi/CoolCumber/issues`
- Privacy policy URL: `https://github.com/lastkimi/CoolCumber/blob/master/PRIVACY.md`
- Review contact: Peng Liu, `hi@slmcamp.com`, `+86 15700133031`

## In-App Purchase

- Reference name: `CoolCumber Pro Lifetime`
- Product ID: `com.slmcamp.CoolCumber.pro.lifetime`
- Type: Non-consumable
- Launch base price: US$19.99; StoreKit displays the localized storefront price
- Release boundary: purchase and restore are disabled in build-4 Beta; the IAP
  is planned for the later paid production build only
- Includes: up to 30 days of on-device history, opt-in local alerts based only
  on fresh serious or critical thermal pressure reported by macOS, and CSV
  history export
- Free remains usable with live monitoring and up to 24 hours of local history

## English metadata

Subtitle:

```text
Trusted Mac Health Monitor
```

Promotional text:

```text
See what your Mac can actually report. CoolCumber marks stale and unsupported readings clearly, keeps history on-device, and never invents sensor values.
```

Keywords:

```text
mac monitor,thermal pressure,cpu,memory,battery,menu bar,widget,history,health
```

Description:

```text
CoolCumber is a quiet, local-first Mac health monitor built around trustworthy data.

LIVE HEALTH OVERVIEW
• See CPU load, memory use, macOS thermal pressure, storage, and battery health.
• Every reading includes an explicit available, stale, unsupported, or temporarily unavailable state.
• No simulated temperatures and no fake “healthy” defaults.

MADE FOR THE MENU BAR
• Check the essentials without interrupting your work.
• Open a resizable native macOS dashboard when you need context.
• Works as a menu-bar-first product on Intel and Apple silicon Macs, including models without a display notch.

LOCAL HISTORY AND ALERTS
• Free includes up to 24 hours of compact on-device history.
• CoolCumber Pro adds up to 30 days of history, opt-in local alerts based only on fresh serious or critical thermal pressure reported by macOS, and CSV export.

PRIVATE BY DESIGN
• No advertising or third-party analytics.
• Monitoring data and history stay on your Mac.
• The Mac App Store edition is sandboxed and never installs a privileged helper.

This Mac App Store build does not provide CPU/GPU temperature or fan-speed readings. CoolCumber shows them as unsupported instead of estimating them; macOS thermal pressure remains available. Unsupported hardware controls are never sold as Pro features.
```

## Simplified Chinese metadata

Subtitle:

```text
可信的 Mac 健康监测
```

Promotional text:

```text
只展示 Mac 能够真实提供的数据：明确标记过期与不支持状态，本地保存历史，绝不虚构传感器数值。
```

Keywords:

```text
Mac监控,系统热压力,CPU,内存,电池,菜单栏,小组件,历史,健康
```

Description:

```text
CoolCumber 是一款安静、本地优先，并以数据可信为核心的 Mac 健康监测工具。

可信健康概览
• 查看 CPU 负载、内存占用、macOS 系统热压力、存储和电池健康。
• 每项数据都会明确显示为可用、已过期、不支持或暂时不可用。
• 不模拟温度，也不用虚假的“正常值”填补空白。

为菜单栏而生
• 无需打断工作即可查看关键状态。
• 需要更多信息时，打开可缩放的原生 macOS 主窗口。
• 兼顾 Intel 与 Apple 芯片 Mac，包括没有显示器刘海的机型。

本地历史与提醒
• Free 包含最长 24 小时的紧凑本地历史。
• CoolCumber Pro 增加最长 30 天历史、仅基于 macOS 新鲜“严重”或“危急”热压力读数的本地提醒，以及 CSV 导出。

隐私优先
• 不含广告或第三方分析。
• 监测数据和历史只保留在 Mac 本机。
• Mac App Store 版严格运行在沙盒中，绝不安装特权辅助组件。

此 Mac App Store 构建不提供 CPU/GPU 温度或风扇转速读数。CoolCumber 会将它们标记为“不支持”，而不是进行估算；macOS 系统热压力仍可用。不支持的硬件控制不会作为 Pro 功能销售。
```

## Privacy answers

- Data collection: No data collected
- Tracking: No
- Third-party advertising/analytics: No
- Network access in the Mac App Store candidate: No client entitlement
- Local notifications: Requested only after the user explicitly enables alerts
- Local history: 24 hours Free / 30 days Pro or Beta Preview, bounded and
  removable with the app

## External Beta status

No external TestFlight beta was conducted for build 3: the app had zero beta
groups and zero testers, so there is no external beta-user feedback to cite.
Build 4 was uploaded and separately submitted for TestFlight Beta review on
20 October 2026. The owner subsequently chose direct production launch; no
external testers, sessions or feedback are claimed. The historical limited
Beta plan below is not a prerequisite for production release.

### Proposed limited TestFlight Beta

Group: `CoolCumber 1.2 Limited Beta`

Public-link limit: `25` testers

Distribution: private invitations or an unlisted link shared directly with the
small test group; do not post the link publicly

English description:

```text
Help validate a quiet, local-first Mac health monitor. This preview focuses on truthful availability states, menu-bar monitoring, on-device history, local alerts, and CSV export. Beta access is free and temporary; it is not a purchase.
```

English What to Test:

```text
Please compare the menu-bar summary, dashboard, history, and Widget after several refreshes. Check that missing or old readings are visibly unavailable or stale, alerts only use fresh serious or critical thermal pressure reported by macOS, and CSV export opens safely in a spreadsheet. On Intel Macs, confirm that temperature and fan readings remain explicitly unsupported in the sandboxed App Store edition.
```

Simplified Chinese description:

```text
帮助验证一款安静、本地优先的 Mac 健康监测工具。本预览重点测试可信的可用状态、菜单栏监测、本地历史、本地提醒和 CSV 导出。Beta 权益免费且有期限，不代表购买。
```

Simplified Chinese What to Test:

```text
请在多次刷新后对比菜单栏、主窗口、历史和小组件；确认缺失或过期读数明确显示为不可用或已过期，提醒只使用 macOS 报告的新鲜“严重”或“危急”热压力，CSV 可安全地用表格软件打开。Intel Mac 用户请确认沙盒 App Store 版会把温度和风扇读数明确显示为“不支持”。
```

Build-4 Beta access temporarily unlocks eligible Pro features for evaluation.
It disables purchase and restore, creates no receipt or permanent entitlement,
and must not be attached to the paid App Store submission.

### Direct-launch decision and remaining release gates

The owner explicitly removed external-feedback, tester-count, session-count
and observation-duration prerequisites on 20 October 2026. Production need
not wait for the build-4 TestFlight review or an external test cohort.

- No unresolved P0 or P1 defect, including launch/signature failures, misleading
  sensor values, privacy regressions, history loss or incorrect paid access.
- Deterministic data/commerce tests, real visible-window checks and universal
  Intel/Apple-silicon builds must pass with source and result evidence.
- The exact Release candidate must be signed and validated; Direct must also
  be notarized. The paid build must not contain Beta access or StoreKit fixtures.
- Store metadata, real screenshots, non-consumable price, purchase/restore and
  first-IAP review association must be checked without fabricated transactions.
- Apple approval and account eligibility remain required for paid availability.

Local automation and StoreKit fixtures are internal validation, not external
testers, installations or revenue. No production purchase can be claimed until
one is observed; the owner decision does not waive platform requirements.

## Limited Beta review notes — build 4

```text
Version 1.2.0 build 4 is a small, free TestFlight Beta candidate, not the paid production upload. Beta Preview temporarily enables eligible history, alert and CSV features for testing; purchase and restore are disabled and no receipt or permanent license is created.

The optional screen-positioned SmartBar and all display-cutout geometry derived from the previously disclosed SuperIsland reference (https://github.com/shobhit99/SuperIsland) have been removed. Every supported Mac now uses the standard AppKit menu-bar status item and popover as the primary entry point.

CoolCumber intentionally shows unsupported or unavailable sensor readings as such. The Mac App Store binary is sandboxed, contains no privileged helper, and has no network-client entitlement.

To review: launch the app with no account, use the menu-bar cucumber to open CoolCumber, and inspect the source/time/status below each metric. CPU/GPU temperature and fan speed remain explicitly unsupported in this sandboxed edition. Open Activity for CPU, memory and storage use. Open History to verify temporary 30-day Beta access, the opt-in alert for fresh serious or critical thermal pressure reported by macOS, and CSV export. Open Pro to verify that Beta is identified as temporary evaluation access rather than a purchase.

Validation boundary: 103 deterministic ThermFlowCore tests passed. Build 3 had no external TestFlight group or testers; no external beta feedback is claimed. Build-4 external testing must be reported only after App Store Connect provides evidence that it occurred.
```

## Planned paid App Review notes — build 5 or later

This is a template, not a claim about an existing binary. Replace the build
number and validation evidence after the build bump, signed archive, and
fresh UI capture are complete.

```text
The first non-consumable IAP is CoolCumber Pro Lifetime (com.slmcamp.CoolCumber.pro.lifetime). Free includes live monitoring and 24-hour local history. Pro adds 30-day local history, opt-in local alerts for fresh serious or critical thermal pressure reported by macOS, and CSV export. No fan, SMC, process, file-cleaning, battery-control, or temperature-threshold capability is sold by this IAP.

To review the future paid build: open Settings > View lifetime Pro, verify the localized price returned by the production App Store storefront, and purchase or restore the product. Then open History to verify the 30-day label, thermal-pressure alert setting, and Export CSV action. The purchase state changes only after StoreKit returns a verified transaction.
```

## Required paid-release assets — pending build 5

- Three real English and three real Simplified Chinese screenshots captured
  from the visible, exact paid candidate: Overview, History, and Pro
- A fresh IAP review screenshot showing the production StoreKit storefront
  price, Restore, and all implemented benefits
- Public support URL and public HTTPS privacy-policy URL
- App Review contact details in App Store Connect

The old build-4 Debug purchase screenshots are local visual-QA drafts, not
canonical Beta assets and not paid build-5 release evidence. Do not commit or
upload them as the paid submission. After the exact paid candidate is committed,
capture fresh assets and validate them with explicit version, build, and source
commit arguments:

```bash
Scripts/validate-store-screenshots.sh AppStore_Screenshots \
  --expected-version 1.2.0 \
  --expected-build 5 \
  --expected-source-commit FULL_40_CHARACTER_CAPTURE_SOURCE_COMMIT
```

Do not reuse legacy concept images or a local StoreKit test-configuration price
as proof of the production storefront price.

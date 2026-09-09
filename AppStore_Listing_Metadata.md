# CoolCumber 1.2 — App Store Connect metadata

This file is the release source of truth. It intentionally describes only the
sandboxed Mac App Store product and the features present in the submitted
binary.

## App information

- App name: `CoolCumber - Thermal Monitor`
- Subtitle: `Trusted Mac Health Monitor`
- Bundle ID: `com.slmcamp.CoolCumber`
- SKU: `COOLCUMBER_001`
- Primary category: Utilities
- Version: `1.2.0`
- Build: `3`
- Copyright: `© 2026 Hangzhou Inkblaze AI Technology Co., Ltd.`
- Price: Free with In-App Purchase
- Marketing URL: `https://github.com/lastkimi/CoolCumber`
- Support URL: `https://github.com/lastkimi/CoolCumber/issues`
- Privacy policy URL: `https://github.com/lastkimi/CoolCumber/blob/master/PRIVACY.md`
- Review contact: Peng Liu, `hi@slmcamp.com`, `+86 15700133031`

## In-App Purchase

- Reference name: `CoolCumber Pro Lifetime`
- Product ID: `com.slmcamp.CoolCumber.pro.lifetime`
- Type: Non-consumable
- Launch base price: US$19.99; StoreKit displays the localized storefront price
- Includes: up to 30 days of on-device history, configurable local alerts based
  on fresh available readings, and CSV history export
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
mac monitor,thermal,cpu,memory,battery,menu bar,widget,history,temperature,health
```

Description:

```text
CoolCumber is a quiet, local-first Mac health monitor built around trustworthy data.

LIVE HEALTH OVERVIEW
• See CPU load, memory use, macOS thermal pressure, storage, battery health, and supported sensor readings.
• Every reading includes an explicit available, stale, unsupported, or temporarily unavailable state.
• No simulated temperatures and no fake “healthy” defaults.

MADE FOR THE MENU BAR
• Check the essentials without interrupting your work.
• Open a resizable native macOS dashboard when you need context.
• Works as a menu-bar-first product on Intel and Apple silicon Macs, including models without a display notch.

LOCAL HISTORY AND ALERTS
• Free includes up to 24 hours of compact on-device history.
• CoolCumber Pro adds up to 30 days of history, configurable local alerts based only on fresh verified readings, and CSV export.

PRIVATE BY DESIGN
• No advertising or third-party analytics.
• Monitoring data and history stay on your Mac.
• The Mac App Store edition is sandboxed and never installs a privileged helper.

Some low-level temperature and fan sensors are not exposed to sandboxed apps. CoolCumber shows them as unavailable instead of estimating them. Unsupported hardware controls are never sold as Pro features.
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
Mac监控,系统热压力,CPU,内存,电池,菜单栏,小组件,历史,温度,健康
```

Description:

```text
CoolCumber 是一款安静、本地优先，并以数据可信为核心的 Mac 健康监测工具。

可信健康概览
• 查看 CPU 负载、内存占用、macOS 系统热压力、存储、电池健康和受支持的传感器读数。
• 每项数据都会明确显示为可用、已过期、不支持或暂时不可用。
• 不模拟温度，也不用虚假的“正常值”填补空白。

为菜单栏而生
• 无需打断工作即可查看关键状态。
• 需要更多信息时，打开可缩放的原生 macOS 主窗口。
• 兼顾 Intel 与 Apple 芯片 Mac，包括没有显示器刘海的机型。

本地历史与提醒
• Free 包含最长 24 小时的紧凑本地历史。
• CoolCumber Pro 增加最长 30 天历史、仅基于新鲜可信读数的本地提醒，以及 CSV 导出。

隐私优先
• 不含广告或第三方分析。
• 监测数据和历史只保留在 Mac 本机。
• Mac App Store 版严格运行在沙盒中，绝不安装特权辅助组件。

沙盒 App 无法读取部分底层温度或风扇传感器。CoolCumber 会显示“不可用”，而不是进行估算；不支持的硬件控制不会作为 Pro 功能销售。
```

## Privacy answers

- Data collection: No data collected
- Tracking: No
- Third-party advertising/analytics: No
- Network access in the submitted Mac App Store binary: No client entitlement
- Local notifications: Requested only after the user explicitly enables alerts
- Local history: 24 hours Free / 30 days Pro, bounded and removable with the app

## Limited TestFlight Beta

Group: `CoolCumber 1.2 Limited Beta`

Public-link limit: `25` testers

English description:

```text
Help validate a quiet, local-first Mac health monitor. This preview focuses on truthful availability states, menu-bar monitoring, on-device history, local alerts, and CSV export. Beta access is free and temporary; it is not a purchase.
```

English What to Test:

```text
Please compare the menu-bar summary, dashboard, history, and Widget after several refreshes. Check that missing or old readings are visibly unavailable or stale, alerts only use fresh readings, and CSV export opens safely in a spreadsheet. On Intel Macs, please also report whether optional read-only sensor setup succeeds.
```

Simplified Chinese description:

```text
帮助验证一款安静、本地优先的 Mac 健康监测工具。本预览重点测试可信的可用状态、菜单栏监测、本地历史、本地提醒和 CSV 导出。Beta 权益免费且有期限，不代表购买。
```

Simplified Chinese What to Test:

```text
请在多次刷新后对比菜单栏、主窗口、历史和小组件；确认缺失或过期读数明确显示为不可用或已过期，提醒只使用新鲜读数，CSV 可安全地用表格软件打开。Intel Mac 用户也请反馈可选的只读传感器设置是否成功。
```

## Review notes

```text
CoolCumber intentionally shows unsupported or unavailable sensor readings as such. The Mac App Store binary is sandboxed, contains no privileged helper, and has no network-client entitlement.

The first non-consumable IAP is CoolCumber Pro Lifetime (com.slmcamp.CoolCumber.pro.lifetime). Free includes live monitoring and 24-hour local history. Pro adds 30-day local history, local threshold alerts, and CSV export. No fan, SMC, process, file-cleaning, or battery-control capability is sold by this IAP.

To review: open Settings > Pro, purchase or restore the product, then open History to verify the 30-day label, alert settings, and Export CSV action. The purchase state changes only after StoreKit returns a verified transaction.
```

## Required release assets

- Real English and Simplified Chinese screenshots captured from build 3
- A real IAP review screenshot showing the Pro paywall and implemented benefits
- Public support URL and public HTTPS privacy-policy URL
- App Review contact details in App Store Connect

Do not reuse the repository's legacy concept images as product screenshots.

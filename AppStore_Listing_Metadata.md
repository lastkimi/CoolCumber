# 🍏 CoolCumber - Mac App Store 上架提审全套资料与元数据 (Metadata)

---

## 1. 基础应用信息 (App Information)

- **应用名称 (App Name)**: CoolCumber
- **副标题 (Subtitle)**: 极简灵动岛温控与系统监控大师 (Dynamic Island Thermal & System Monitor)
- **主分类 (Primary Category)**: 工具 (Utilities)
- **次分类 (Secondary Category)**: 效率 (Productivity)
- **Bundle ID**: `com.slmcamp.CoolCumber`
- **SKU**: `COOLCUMBER_MAC_001`
- **版权声明 (Copyright)**: `© 2026 Hangzhou Inkblaze AI Technology Co., Ltd.`
- **价格分级**: 免费 / 包含应用内购买 (Free / IAP)

---

## 2. 关键词与搜索标签 (Keywords)

```text
system monitor,cpu temperature,fan speed,thermal,dynamic island,smart bar,hardware,istat,menubar,cleaner,battery health,系统监控,CPU温度,风扇控制,灵动岛,硬件监控
```

---

## 3. 描述文案 (App Descriptions)

### 🇨🇳 简体中文描述 (Simplified Chinese)

```text
CoolCumber 是专为 Apple Silicon (M1/M2/M3/M4) 与 Intel Mac 深度定制的下一代系统监控与硬件状态看板。拥有媲美 iOS 原生质感的 Dynamic Island (灵动岛 SmartBar) 与菜单栏常驻悬浮态，让您实时掌控 Mac 的每颗核心与功耗表现。

【核心亮点】
• 灵动岛 SmartBar：吸顶隐藏式设计，鼠标悬停即刻展开 CPU/GPU 实时负荷、温度与风扇读数。
• 全维度系统遥测：高频采集 CPU 单核/多核占用、Unified Memory 内存压力、网络上下行瞬时速率与磁盘读写吞吐。
• 电池健康智控：智能分析循环次数与充电健康度，提供硬件养护与寿命延长建议。
• 深度维护与瘦身：一键清理系统缓存、重建 Spotlight 索引与 DNS 刷新，保持 Mac 峰值运行效率。
• macOS Sonoma / Sequoia 原生 Widget 小组件：在桌面上随时掌握系统核心动态。

【隐私与沙盒合规】
CoolCumber App Store 版本 100% 遵循 Apple 安全沙盒规范，完全在用户态安全运行，无需安装特权内核扩展，全方位守护您的设备安全与数据隐私。
```

### 🇺🇸 英文描述 (English)

```text
CoolCumber is a next-generation system telemetry and thermal monitoring dashboard crafted exclusively for Apple Silicon (M1/M2/M3/M4) and Intel Macs. Featuring a sleek Dynamic Island (SmartBar) and lightweight menu bar interface, it keeps you in complete control of your Mac's performance.

【Key Features】
• Dynamic Island SmartBar: Seamlessly docked near the screen notch with fluid hover expansion for real-time CPU/GPU thermals and metrics.
• Comprehensive System Telemetry: High-precision real-time tracking for CPU usage, Unified Memory pressure, network throughput, and disk I/O.
• Battery Health Guardian: Battery cycle diagnostics and smart power management suggestions.
• System Optimization Suite: One-click cache sweeping, Spotlight re-indexing, and DNS flushing to maintain peak Mac responsiveness.
• macOS Sonoma & Sequoia Widgets: Keep essential performance statistics right on your desktop.

【App Store Sandbox Compliant】
This version strictly adheres to Apple's App Sandbox guidelines, running completely in user-space without privileged daemons for maximum security and peace of mind.
```

---

## 4. 链接与联系信息 (URLs & Support)

- **技术支持网站 (Support URL)**: `https://github.com/lastkimi/CoolCumber`
- **隐私政策网站 (Privacy Policy URL)**: `https://github.com/lastkimi/CoolCumber/blob/master/PRIVACY.md`
- **营销网站 (Marketing URL)**: `https://github.com/lastkimi/CoolCumber`

---

## 5. 一键上传与提审操作指南 (Submission Guide)

### 方案 A：通过 Xcode 一键上传 (推荐，最简便)
1. 双击打开工程生成的归档文件：
   ```bash
   open ./CoolCumber_AppStore.xcarchive
   ```
2. Xcode 会自动弹出 **Organizer (归档管理器)** 窗口，并选中刚生成的 `CoolCumber Lite`。
3. 点击右侧蓝色按钮 **「Distribute App」** -> 选择 **「App Store Connect」** -> **「Upload」**。
4. 勾选自动签名，点击 **「Upload」**，Xcode 将自动校验并分发至 App Store Connect 后台！

### 方案 B：通过 Transporter 应用上传
1. 打开 Mac 上的 **Transporter** 官方工具（可从 App Store 免费下载）。
2. 将已打包生成的 [`CoolCumber_Lite_AppStore.pkg`](file:///Users/brucelieu/Desktop/MacThermFlow/CoolCumber_Lite_AppStore.pkg) 拖入 Transporter 窗口。
3. 点击 **「交付 (Deliver)」** 即可完成上传。

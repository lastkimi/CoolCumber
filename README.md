# CoolCumber 🥒

**English** | [中文](README_zh.md)

**CoolCumber** is an intelligent, sleek, and AI-driven Mac cooling and system optimization tool. Born out of the necessity to keep your macOS running cool and efficient, it features a stunning 3D interactive interface, background process management, thermal monitoring, and deep junk cleanup capabilities.

---

## 🌟 Key Features

### 🌡️ Geek-Grade Thermal & Power Monitoring
- **Real-time Dashboard**: A stunning 3D UI that displays real-time CPU temperature, memory usage, and battery power.
- **Historical Trends**: Intuitive CPU thermal and load history graphs that accurately map temperature fluctuations in the 40°C to 95°C range, helping you understand your system's heat dissipation at a glance.

### 🛡️ Rogue App Killer
- **Silent Guardian**: Intelligently detects and analyzes background processes that consume excessive CPU and memory without your knowledge.
- **One-Click Freeze**: Instantly terminate stubborn resource-hogging background applications to cool down your system immediately.

### 🧹 Deep System Optimizer
- **Comprehensive Scan**: Deeply scans your macOS for application caches, temporary files, and useless log remnants.
- **One-Click Cleanup**: Free up valuable disk storage space and keep your system running light and fast.

### 🤖 Built by Agentic Studio
The core codebase of this project was primarily developed autonomously by Google Antigravity AI agents. From low-level system API integrations to highly customized 3D frontend animations, it demonstrates the phenomenal power of Agentic Coding in modern software engineering.

---

## 🚀 Quick Start Tutorial

### 1. Installation
1. Go to the [Releases page](https://github.com/lastkimi/CoolCumber/releases) and download the latest `CoolCumber.dmg`.
2. Double-click the downloaded `.dmg` file and drag `CoolCumber` into your **Applications** folder.
3. Open CoolCumber from Launchpad. On first launch, macOS may prompt you to grant necessary permissions (such as Full Disk Access or Accessibility permissions). Please allow these in System Preferences so the app can correctly read thermal sensors and clear system caches.

### 2. User Guide
- **Check Status**: Click the snowflake/fan icon in your Mac's menu bar to expand the beautiful floating dashboard and view real-time percentages and temperatures for CPU, RAM, and Battery.
- **Clean Junk**: Switch to the "System Optimizer" tab, click **Scan**, wait a few seconds for the analysis to complete, and then click **Clean** to free up space.
- **Manage Processes**: Switch to the "App Freezer" tab to monitor current high-load background applications. Terminate any rogue apps you don't need with a single click.
- **Language Toggle**: You can freely switch between English and Chinese in the Settings panel for a native localization experience.

---

## 🛠️ Build from Source

If you want to contribute or build this project yourself, you will need to install [XcodeGen](https://github.com/yonaskolb/XcodeGen) (or install via Homebrew: `brew install xcodegen`).

1. **Clone the repository**:
   ```bash
   git clone https://github.com/lastkimi/CoolCumber.git
   ```
2. **Navigate to the project directory**:
   ```bash
   cd CoolCumber
   ```
3. **Generate the Xcode project**:
   ```bash
   xcodegen generate
   ```
4. **Compile & Run**:
   Open the generated `.xcodeproj` file and build it using Xcode on your Mac.

---

## 📄 License
This project is licensed under the **MIT License**. You are free to use, modify, and distribute this software. See the [LICENSE](LICENSE) file for details.

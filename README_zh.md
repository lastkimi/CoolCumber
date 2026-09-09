# CoolCumber

[English](README.md) | **中文**

CoolCumber 是一款适用于 macOS 13 及以上版本的安静、本地优先 Mac 健康监测工具。它只展示系统能够真实提供的数据，明确标记过期或不支持的读数，绝不会用虚构数值填补传感器空白。

## 产品能力

- 轻量菜单栏摘要与可缩放的原生 macOS 主窗口。
- 展示可信的 CPU 负载、内存、系统热压力、存储、电池和受支持的硬件读数，并说明数据来源与新鲜度。
- WidgetKit 小组件通过 App Group 读取最新真实快照，明确显示过期或不可用状态。
- 紧凑本地历史：Free 保留 24 小时，Pro 最长保留 30 天。
- Pro 提供仅基于新鲜可用读数的本地健康提醒，以及防表格公式注入的 CSV 历史导出。
- 支持英文和简体中文；以菜单栏为主入口，兼顾没有刘海的 2019 Intel MacBook Pro。

CoolCumber 不会自动结束或冻结进程、制造内存压力、清理个人应用数据、修改电池充电行为或写入风扇设置；不支持的控制能力不会被包装为 Pro 功能销售。

## 版本与价格

Mac App Store 版严格运行在沙盒中，绝不安装特权辅助组件。因此部分底层温度或风扇传感器可能不可用，界面会如实显示。官网直装版可以在用户明确批准后，为受支持设备安装签名辅助组件，以提供只读硬件监测。

实时核心监测和 24 小时本地历史永久免费。CoolCumber Pro 首先以 Mac App Store 一次性非消耗型购买形式上线，基准价为 US$19.99（实际价格以当地 App Store 为准）。Pro 包含 30 天本地历史、可配置的本地提醒和 CSV 导出。首轮正式收费只走 Mac App Store；在签名授权服务和公开验签密钥部署前，官网版结账保持关闭。免费 Beta Preview 会临时开放符合条件的 Pro 能力，但不会生成购买记录或永久授权；Direct 预览版的固定有效期最长为 45 天，到期后自动回到 Free。

## 隐私与安全

遥测与历史保留在本机。CoolCumber 不含广告或第三方分析，默认不会上传系统遥测。详见 [PRIVACY.md](PRIVACY.md) 和 [SECURITY.md](SECURITY.md)。

官网正式版应由 Developer ID 签名并通过 Apple 公证；Mac App Store 版仅由 Apple 分发。请勿安装来源不明或未签名的镜像。
版本变更记录见 [CHANGELOG.md](CHANGELOG.md)。

## 从源码构建

需要 Xcode、Swift 5.9 或更高版本，以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
xcodegen generate
swift test --package-path Packages/ThermFlowCore
xcodebuild -project MacThermFlow.xcodeproj -scheme ThermFlowApp \
  -configuration Debug -destination 'platform=macOS' build
```

仓库严格分离官网直装版与 Mac App Store 版能力。制作发布产物前请运行内置门禁：

```bash
Scripts/ci-secret-scan.sh
Scripts/check-project-boundaries.rb project.yml 1.2.0 3
```

## 开源协议

本仓库源代码采用 [MIT License](LICENSE)。

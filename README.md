# MoneyFly

MoneyFly 是一款面向多设备使用的跨平台代理与 VPN 客户端，提供账号登录、订阅同步、节点连接、分应用代理、路由规则、流量统计和自动更新能力。项目基于 Flutter 构建，核心网络能力依托 sing-box / Hiddify Next Core 等开源生态。

> 请在遵守当地法律法规、网络服务条款和订阅服务规则的前提下使用本软件。

<p align="center">
  <a href="https://github.com/moneyfly004/cboard/releases/latest">
    <img src="https://img.shields.io/github/v/release/moneyfly004/cboard?style=flat-square&logo=github" alt="Latest Release">
  </a>
  <a href="https://github.com/moneyfly004/cboard/releases">
    <img src="https://img.shields.io/github/downloads/moneyfly004/cboard/total?style=flat-square&logo=github" alt="Downloads">
  </a>
  <a href="https://github.com/moneyfly004/cboard/actions/workflows/moneyfly-build.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/moneyfly004/cboard/moneyfly-build.yml?branch=main&style=flat-square&label=build" alt="Build Status">
  </a>
</p>

## 主要功能

- 账号体系：支持登录、注册、邮箱验证码、忘记密码与修改密码。
- 订阅同步：登录后可同步账号订阅，并在客户端生成可连接的订阅配置。
- 多设备使用：支持查看设备数量、在线设备、移动端/桌面端统计，并可管理设备备注和移除设备。
- 套餐与订单：支持查看套餐、创建订单、发起支付、查询订单状态和查看历史订单。
- 一键连接：主页展示连接状态、订阅到期时间、在线设备、剩余天数和流量信息。
- 模式切换：快速切换代理、系统代理、VPN/TUN 等连接模式。
- 节点管理：支持节点列表、当前节点展示、延迟测试、按名称/延迟/用量排序。
- 配置管理：支持订阅链接、二维码、剪贴板和本地配置导入，支持自动更新订阅。
- 路由规则：支持域名、IP/CIDR、端口、进程、应用包名、协议等规则条件。
- 分应用代理：Android 支持按应用选择代理、绕过或全局模式。
- DNS 与入站设置：支持远程 DNS、直连 DNS、Fake DNS、混合端口、TUN 参数等配置。
- 链式模式：支持主配置、额外安全层、解锁器、WARP、Psiphon 等组合模式。
- 统计与日志：显示实时上传/下载速度、总流量、连接信息，并支持查看与分享日志。
- 自动更新：客户端可检测 GitHub Releases 上的新版本，并提示用户更新。
- 桌面体验：Windows/macOS 支持托盘、窗口管理、开机自启和静默启动等常用桌面能力。

## 支持平台

| 平台 | 支持情况 |
| --- | --- |
| Android | APK / AAB |
| Windows 10/11 x64 | 安装包 / 便携版 |
| Windows 7 SP1 x64 | Legacy 安装包 / Legacy 便携版 |
| macOS | DMG / PKG |

Windows 7 Legacy 包会经过静态兼容性检查，但仍建议在真实 Windows 7 SP1 x64 环境中做运行验证。

## 下载

最新版本统一发布在 GitHub Releases：

<p>
  <a href="https://github.com/moneyfly004/cboard/releases/latest">
    <img src="https://img.shields.io/badge/GitHub_Releases-下载最新版-181717.svg?style=for-the-badge&logo=github" alt="GitHub Releases">
  </a>
</p>

### Android

- [MoneyFly-Android-universal.apk](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-Android-universal.apk)
- [MoneyFly-Android-arm64-v8a.apk](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-Android-arm64-v8a.apk)
- [MoneyFly-Android-armeabi-v7a.apk](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-Android-armeabi-v7a.apk)
- [MoneyFly-Android-x86_64.apk](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-Android-x86_64.apk)
- [MoneyFly-Android.aab](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-Android.aab)

### Windows

- [MoneyFly-Windows-x64-Setup.exe](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-Windows-x64-Setup.exe)
- [MoneyFly-Windows-x64-Portable.zip](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-Windows-x64-Portable.zip)
- [MoneyFly-Windows7-x64-Setup.exe](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-Windows7-x64-Setup.exe)
- [MoneyFly-Windows7-x64-Portable.zip](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-Windows7-x64-Portable.zip)

### macOS

- [MoneyFly-macOS-universal.dmg](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-macOS-universal.dmg)
- [MoneyFly-macOS-universal.pkg](https://github.com/moneyfly004/cboard/releases/latest/download/MoneyFly-macOS-universal.pkg)

## 版本与更新

MoneyFly 使用标准语义化版本号：

- 当前基础版本记录在 `pubspec.yaml`。
- 发布版本按 patch 递增，例如 `1.0.0` -> `1.0.1` -> `1.0.2`。
- GitHub Actions 构建时会解析最新正式 Release，生成下一个版本号和对应构建号。
- 安装包、Release 标题、更新检测信息会跟随发布版本变化。
- 旧版本客户端检测到 GitHub Releases 上有新版本时，会弹出更新提示。

## 使用说明

1. 安装对应平台的 MoneyFly 客户端。
2. 打开应用并登录账号；没有账号时可在客户端注册。
3. 登录后同步订阅，主页会显示订阅状态、到期信息和设备信息。
4. 点击连接按钮启动代理/VPN。
5. 需要调整连接方式时，使用主页的“模式切换”。
6. 需要精细控制流量时，可进入设置配置路由规则、DNS、分应用代理和链式模式。

## 配置能力

MoneyFly 支持常见订阅与配置格式，适用于多种代理协议和节点管理方式。配置可通过订阅链接、二维码、剪贴板或本地文件导入，并可根据订阅信息显示剩余流量、到期时间、配置名称、服务商页面和支持入口。

## 构建

推荐环境：

- Flutter `3.38.5`
- Dart `3.10.4`
- Java `17`
- Android SDK `36`
- Android NDK `28.2.13676358`

常用命令：

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart run slang
flutter test
flutter analyze --no-fatal-infos
```

平台构建示例：

```bash
flutter build apk --release
flutter build appbundle --release
flutter build windows --release
flutter build macos --release
```

## 自动构建与发布

仓库内的 `MoneyFly Build` 工作流会在推送到主分支或手动触发时运行：

- 校验 Flutter 源码、生成文件、测试和静态分析。
- 构建 Android APK/AAB。
- 构建 Windows 安装包、便携版和 Windows 7 Legacy 包。
- 构建 macOS DMG/PKG。
- 发布 GitHub Release，并上传校验文件。

如果需要发布带签名的生产安装包，请在仓库的 GitHub Secrets 中配置相应平台的签名信息。

## 隐私与安全

- README 不公开后台结构、接口路径、服务部署或内部鉴权细节。
- 账号、订阅、订单和设备信息只在客户端功能层面展示。
- 日志用于排查连接问题，分享日志前请自行确认是否包含敏感信息。
- 崩溃分析与诊断能力以客户端设置为准，可根据需要关闭。

## 鸣谢

MoneyFly 使用并受益于以下开源项目：

- [sing-box](https://github.com/SagerNet/sing-box)
- [Hiddify Next Core](https://github.com/hiddify/hiddify-next-core)
- [Flutter](https://flutter.dev/)
- [Riverpod](https://riverpod.dev/)
- [Drift](https://drift.simonbinder.eu/)
- [Dio](https://pub.dev/packages/dio)

更多依赖请查看 [pubspec.yaml](./pubspec.yaml)。

## 许可证

请以仓库中的许可证文件为准。

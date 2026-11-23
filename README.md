<p align="center">
  <img src="assets/icon.png" width="88" alt="DimWallpaper 图标" />
</p>

<h1 align="center">DimWallpaper</h1>

<p align="center">macOS 原生菜单栏工具：深色模式下自动压暗桌面壁纸，浅色模式保持原色，不改动系统壁纸文件。</p>

<p align="center">
  <a href="https://github.com/xxkingstuggle/dim-wallpaper/releases/latest"><img src="https://img.shields.io/github/v/release/xxkingstuggle/dim-wallpaper" alt="最新版本" /></a>
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple" alt="macOS 13 及以上" />
  <img src="https://img.shields.io/badge/Swift-AppKit-F05138?logo=swift&logoColor=white" alt="Swift + AppKit" />
  <img src="https://img.shields.io/badge/License-MIT-green.svg" alt="MIT License" />
</p>

<p align="center">
  <a href="https://github.com/xxkingstuggle/dim-wallpaper/releases/latest">下载 Release (v1.0.0)</a> ·
  <a href="https://myzjx.com/software/dim-wallpaper/">项目概览</a> ·
  <a href="https://myzjx.com/posts/dim-wallpaper-macos-desktop-overlay/">工程手记</a> ·
  <a href="https://github.com/xxkingstuggle/dim-wallpaper/issues">问题反馈</a>
</p>

原生 Swift + AppKit 编写，无第三方依赖，无常驻守护进程，仅驻留一个菜单栏图标。

## 原理

在每个显示器上铺一层**不可见交互的纯黑窗口**，窗口层级设为
`CGWindowLevelForKey(.desktopWindow)`——也就是壁纸之上、Finder 桌面图标和所有应用窗口之下。
调整这层窗口的 alpha 就等于给壁纸加一层灰膜：

- 应用窗口完全不受影响（不透明白窗实测：开关前后像素完全相同）
- 菜单栏和 Dock 是半透明材质，会透出背后的壁纸，所以壁纸变暗时它们看起来也会略暗一点——这是材质特性，不是被盖住
- 不需要修改壁纸文件，也不碰 `com.apple.desktop` / wallpaper 数据库
- 跟随系统外观变化（`NSApp.effectiveAppearance` KVO + `AppleInterfaceThemeChangedNotification`）
- 每个显示器一层窗口，`didChangeScreenParametersNotification` 时重建，分辨率变化自动跟随
- `collectionBehavior = [.canJoinAllSpaces, .stationary]`：切 Space、进全屏都保持覆盖

> 为什么不做「生成一张调暗的图再 setDesktopImageURL」：那会把用户的壁纸换成另一份文件，
> 系统设置里的壁纸条目会被改写，换壁纸后还得重新同步。叠加窗口方案完全不动系统状态。

## 用法

菜单栏图标：

| 图标 | 含义 |
|---|---|
| 🌙 | 深色模式，壁纸已调暗 |
| ☀️ | 浅色模式（或已关闭深色限制），保持原色 |
| 🚫 | 已暂停 |

菜单项：

- **启用壁纸调暗** — 总开关
- **仅在深色模式下生效** — 关掉后浅色模式也调暗
- **调暗强度** — 5%–80% 滑杆，实时生效
- **开机自动启动** — 由 `SMAppService` 管理，可在「系统设置 → 通用 → 登录项」里看到
- **退出 DimWallpaper**

设置用 `UserDefaults` 保存在 `~/Library/Preferences/local.zjx.DimWallpaper.plist`。

## 安装与构建

### 方式一：从 Releases 下载预编译包

1. 前往 [GitHub Releases (v1.0.0)](https://github.com/xxkingstuggle/dim-wallpaper/releases/tag/v1.0.0) 下载 `DimWallpaper-1.0.0-macOS.zip`（可对照 `SHA256SUMS.txt` 校验）。
2. 解压后将 `DimWallpaper.app` 移入 `~/Applications` 或 `/Applications` 并打开。

### 方式二：从源码构建

```bash
git clone https://github.com/xxkingstuggle/dim-wallpaper.git
cd dim-wallpaper
./build.sh
cp -R dist/DimWallpaper.app ~/Applications/
open ~/Applications/DimWallpaper.app
```

首次启动会自动注册登录项。如果系统提示需要确认，去
「系统设置 → 通用 → 登录项与扩展」允许 `DimWallpaper.app`。

## 诊断

```bash
~/Applications/DimWallpaper.app/Contents/MacOS/DimWallpaper --status
# enabled=true intensity=0.4 darkOnly=true loginItemStatus=1
# loginItemStatus: 0=notRegistered 1=enabled 2=requiresApproval 3=notFound
```

## 卸载

先在菜单里取消「开机自动启动」（登录项由 `SMAppService` 托管，直接删 App 会在登录项里留下失效条目），再退出应用、将 `~/Applications/DimWallpaper.app` 移入废纸篓，并清理偏好设置：

```bash
osascript -e 'quit app "DimWallpaper"'
defaults delete local.zjx.DimWallpaper
```

## 环境

- macOS 27.0.1 / Xcode 27 / Swift 6.4，arm64
- 最低支持 macOS 13（`SMAppService` 要求）

## 已验证（2026-10-24，macOS 27.0.1 / 单显示器）

截图逐像素采样，采样点在纯壁纸区域：

- 深色模式（强度 40%）：桌面亮度 0.929 → 0.557
- 浅色模式：保持 0.929
- 反复切换深浅色，叠加层 alpha 每次都正确跟随（0 ⇄ 0.40）
- 菜单栏、Dock、应用窗口的采样亮度在开关前后不变
- 开机启动项注册成功（`loginItemStatus=1`），Launch Services 已索引
- 重复 `open` 只保留一个实例
- 菜单可见、状态条目正常出现（开启前后对比截图确认）

未实测：多显示器（本机只有一块屏）、通知中心覆盖、休眠唤醒后重连外接屏。这些走的是同一套窗口层级与 `didChangeScreenParametersNotification` 路径，但按「没测就不写进已验证」处理。

## 开源许可

采用 [MIT License](LICENSE) 开源。

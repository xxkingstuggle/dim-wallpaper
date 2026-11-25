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

原生 Swift + AppKit + SwiftUI 编写，零第三方依赖，无常驻守护进程，仅驻留一个菜单栏图标。

## 原理

在每个显示器上铺一层**不可见交互的调光遮罩窗口**，窗口层级严格落在
`CGWindowLevelForKey(.desktopWindow) + 1`（位于壁纸之上、严格低于 `CGWindowLevelForKey(.desktopIconWindow)` 桌面图标层）：

- 应用窗口完全不受影响（不透明白窗实测：开关前后像素完全相同）
- 菜单栏和 Dock 是半透明材质，会透出背后的壁纸，所以壁纸变暗时它们看起来也会略暗一点——这是材质特性，不是被盖住
- 不需要修改壁纸文件，也不碰 `com.apple.desktop` / wallpaper 数据库
- 暂停或处于浅色待命时，淡出完成后自动 `orderOut` 卸载遮罩窗口，避免空闲占用 WindowServer 合成缓冲
- 监听系统外观变化、显示器热插拔、休眠唤醒与空间切换并做短窗防抖，支持多显示器逐屏独立豁免
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]` 并开启 `canHide = false`：切 Space 或隐藏应用时不丢失覆盖

> 为什么不做「生成一张调暗的图再 setDesktopImageURL」：那会把用户的壁纸换成另一份文件，
> 系统设置里的壁纸条目会被改写，换壁纸后还得重新同步。叠加窗口方案完全不动系统状态。

## 用法

菜单栏图标：

| 图标 | 含义 |
|---|---|
| 🌙 | 深色模式，壁纸已调暗 |
| ☀️ | 浅色模式（或已关闭深色限制），保持原色 |
| 🚫 | 已暂停 |

- **左键点击状态栏图标**：弹出原生毛玻璃控制中心，包含 16:10 实时桌面压暗微缩预览、5%–80% 连续滑杆、快捷场景预设（轻柔 25% / 专注 45% / 深夜 65% / 极暗 80%）、色温滤镜（中性黑 / 暖夜 / 深蓝夜）、深色模式联动、逐显示器独立开关、零权限全局切换快捷键（`⌥⌘D`，Carbon `RegisterEventHotKey`）及开机自启状态，完整适配浅/深色与「降低透明度」降级。
- **右键（或 Control + 左键）点击状态栏图标**：弹出极速菜单（一键开关、场景预设、登录项、`⌘Q` 退出）。

设置用 `UserDefaults` 保存在 `~/Library/Preferences/local.zjx.DimWallpaper.plist`。

## 安装与构建

### 方式一：从 Releases 下载预编译包

1. 前往 [GitHub Releases (v1.0.0)](https://github.com/xxkingstuggle/dim-wallpaper/releases/tag/v1.0.0) 下载 `DimWallpaper-1.0.0-macOS.zip`（可对照 `SHA256SUMS.txt` 校验）。
2. 解压后将 `DimWallpaper.app` 移入 `~/Applications` 或 `/Applications` 并打开。

### 方式二：从源码构建

```bash
git clone https://github.com/xxkingstuggle/dim-wallpaper.git
cd dim-wallpaper
swift test
./build.sh
cp -R dist/DimWallpaper.app ~/Applications/
open ~/Applications/DimWallpaper.app
```

首次启动会自动注册登录项。如果系统提示需要确认，去
「系统设置 → 通用 → 登录项与扩展」允许 `DimWallpaper.app`。

## 诊断

```bash
~/Applications/DimWallpaper.app/Contents/MacOS/DimWallpaper --status
# enabled=true intensity=0.4 darkOnly=true tint=neutral hotKeyEnabled=true displays=1 loginItemStatus=1
# loginItemStatus: 0=notRegistered 1=enabled 2=requiresApproval 3=notFound

# 输出完整 JSON（含在线显示器列表、色温、快捷键与隔离 suite 信息）
~/Applications/DimWallpaper.app/Contents/MacOS/DimWallpaper --status-json

# 隔离沙箱运行参数（不触碰日用偏好与登录项）
dist/DimWallpaper.app/Contents/MacOS/DimWallpaper \
  --defaults-suite local.zjx.DimWallpaper.sandbox \
  --no-login-item \
  --allow-multiple-instances
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

## 已验证（2026-11-25，`1.1.0` 分支隔离沙箱真机 / 双显示器）

在 `TYPEC`（`1920×1080 @2x`）+ `内建视网膜显示器`（`1470×956 @2x`）双屏环境下通过 `--defaults-suite` + `--no-login-item` + `--allow-multiple-instances` 隔离实测（未触碰日用实例与偏好）：

- `swift test` 核心纯逻辑单测 7/7 通过（`0.005s`）；`./build.sh` 生成 `dist/DimWallpaper.app`，`codesign --verify --deep --strict` 通过，`AppIcon_1024.png` 精确为 `1024×1024`
- `--status` 与 `--status-json` 正确输出隔离 suite、双屏元数据与色温/热键字段
- 激活态（`enabled=true, darkOnly=false, intensity=0.45`）：`CGWindowListCopyWindowInfo` 实测双屏各挂载 1 层遮罩，`kCGWindowLayer = -2147483622`（严格介于 `.desktopWindow = -2147483623` 与 `.desktopIconWindow = -2147483603` 之间），alpha `0.45`；连续 3 次 `ps` 采样空闲 **平均 CPU `0.00%`、平均 RSS `75.3 MB`**
- 逐屏独立豁免（豁免 `id=3` 外接屏）：WindowServer 在屏遮罩窗口精确缩减为 `1` 个（仅内建屏 `1470×956`）
- 暂停态（`enabled=false`）：`CGWindowListCopyWindowInfo(.optionOnScreenOnly)` 实测在屏桌面遮罩窗口为 `0`，确认 `orderOut` 释放 WindowServer 合成缓冲，新增崩溃日志为 `0`
- 毛玻璃控制中心离屏 2× 快照（`324×674@2x`，浅色与深色模式）目视验收通过，分层桌面预览、预设胶囊、色温分段、双屏开关与 `⌥⌘D` 键帽无裁切无重叠

未实测：通知中心覆盖、休眠唤醒后物理热插拔外接屏、真实键盘跨应用触发 `⌥⌘D` 全局热键、状态栏真实鼠标左右键手点及「降低透明度」系统开关实机切换。

## 开源许可

采用 [MIT License](LICENSE) 开源。

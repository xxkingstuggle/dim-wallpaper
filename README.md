# DimWallpaper

macOS 菜单栏小工具：深色模式下把桌面壁纸调暗，浅色模式下保持原色。

原生 Swift + AppKit，无第三方依赖，无后台守护进程，只有一个菜单栏图标。

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

## 构建与安装

```bash
cd ~/Developer/repos/dim-wallpaper
./build.sh
rm -rf ~/Applications/DimWallpaper.app
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

先在菜单里取消「开机自动启动」（登录项由 `SMAppService` 托管，直接删 app 会在登录项里留下失效条目），再：

```bash
osascript -e 'quit app "DimWallpaper"'
rm -rf ~/Applications/DimWallpaper.app
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

# DimWallpaper

macOS 菜单栏小工具：深色模式下把桌面壁纸调暗，浅色模式下保持原色。

原生 Swift + AppKit，无第三方依赖，无后台守护进程，只有一个菜单栏图标。

## 原理

在每个显示器上铺一层**不可见交互的纯黑窗口**，窗口层级设为
`CGWindowLevelForKey(.desktopWindow)`——也就是壁纸之上、Finder 桌面图标和所有应用窗口之下。
调整这层窗口的 alpha 就等于给壁纸加一层灰膜：

- 应用窗口、Dock、菜单栏、通知中心都不受影响
- 不需要修改壁纸文件，也不碰 `com.apple.desktop` / wallpaper 数据库
- 跟随系统外观变化（`NSApp.effectiveAppearance` KVO + `AppleInterfaceThemeChangedNotification`）
- 多显示器、分辨率变化、Spaces 切换都自动跟随

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

```bash
osascript -e 'quit app "DimWallpaper"'
rm -rf ~/Applications/DimWallpaper.app
defaults delete local.zjx.DimWallpaper
rm -rf ~/Library/LaunchAgents/local.zjx.DimWallpaper.plist 2>/dev/null
```

## 环境

- macOS 27.0.1 / Xcode 27 / Swift 6.4，arm64
- 最低支持 macOS 13（`SMAppService` 要求）

## 已验证

- 深色模式：壁纸采样亮度 0.929 → 0.557（强度 40%）
- 浅色模式：壁纸保持 0.929
- 反复深浅色切换：叠加层 alpha 正确跟随
- 菜单栏、Dock、应用窗口亮度不受影响
- 开机启动项注册成功（`loginItemStatus=1`）
- 重复启动只保留一个实例

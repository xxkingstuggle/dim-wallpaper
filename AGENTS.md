# 项目指引

## 项目定位
macOS 菜单栏工具：提供桌面层级「壁纸调暗」与前台高亮「专注遮罩（Focus Mode）」双层无边框穿透遮罩，全链路不修改硬件 Gamma/色表/亮度或壁纸文件，无需录屏或辅助功能权限。

## 如何运行
在 macOS 上执行 `swift test` 运行核心纯逻辑单测，执行 `./build.sh` 生成 `dist/DimWallpaper.app`；安装、诊断与隔离测试参数见 `README.md`。

## 技术栈
Swift 6、AppKit、SwiftUI、Carbon、ServiceManagement 和 macOS 系统工具；项目零第三方运行时依赖。

## 目录与约定
`Package.swift` 定义 SwiftPM 构建与单测；`Sources/DimWallpaperCore/` 为纯逻辑核心（含 `FocusModels.swift` 的双屏 CG→AppKit 坐标转换、无重叠区域分割与窗口 Z 序规划），`Sources/DimWallpaperApp/` 为菜单栏、双热键与毛玻璃控制中心宿主层，`Tests/DimWallpaperCoreTests/` 为核心单测；`Resources/` 保存 `Info.plist`，`Tools/` 生成图标，`dist/` 是打包产物。

## 安全红线
- 严禁调用任何修改硬件显示模式、Gamma、色表或亮度的 API（如 `CGSetDisplayTransfer*`、`CGConfigureDisplay*`），只允许只读屏幕/窗口查询与无边框鼠标穿透 `NSWindow`。
- 专注遮罩菜单栏/Dock 分条必须与主遮罩严格无重叠分割，且位于对应系统栏层级之上、下拉菜单层级之下；停用、豁免或息屏时 `orderOut` 并销毁释放。

## 当前状态与下一步
README.md 区分已验证行为和未验证场景。改窗口层级或显示器处理时，保留这一区分并按实际设备验证。

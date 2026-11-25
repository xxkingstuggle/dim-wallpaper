# 项目指引

## 项目定位
macOS 菜单栏工具，在深色模式下用桌面层级窗口调暗壁纸。

## 如何运行
在 macOS 上执行 `swift test` 运行核心纯逻辑单测，执行 `./build.sh` 生成 `dist/DimWallpaper.app`；安装、诊断与隔离测试参数见 `README.md`。

## 技术栈
Swift 6、AppKit、SwiftUI、Carbon、ServiceManagement 和 macOS 系统工具；项目零第三方运行时依赖。

## 目录与约定
`Package.swift` 定义 SwiftPM 构建与单测；`Sources/DimWallpaperCore/` 为纯逻辑核心，`Sources/DimWallpaperApp/` 为菜单栏与毛玻璃控制中心宿主层，`Tests/DimWallpaperCoreTests/` 为核心单测；`Resources/` 保存 `Info.plist`，`Tools/` 生成图标，`dist/` 是打包产物。

## 当前状态与下一步
README.md 区分已验证行为和未验证场景。改窗口层级或显示器处理时，保留这一区分并按实际设备验证。

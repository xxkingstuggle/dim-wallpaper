# 项目指引

## 项目定位
macOS 菜单栏工具，在深色模式下用桌面层级窗口调暗壁纸。

## 如何运行
在 macOS 上执行 ./build.sh；产物写入 dist/，安装、诊断与卸载说明见 README.md。

## 技术栈
Swift、AppKit、ServiceManagement 和 macOS 系统工具；项目没有第三方运行时依赖。

## 目录与约定
Sources/main.swift 是应用入口，Resources/ 保存 Info.plist，Tools/ 生成图标；dist/ 是构建产物。

## 当前状态与下一步
README.md 区分已验证行为和未验证场景。改窗口层级或显示器处理时，保留这一区分并按实际设备验证。

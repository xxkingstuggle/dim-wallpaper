import AppKit
import ServiceManagement

// MARK: - Preferences

private enum PrefKey {
    static let enabled = "enabled"
    static let intensity = "intensity"
    static let darkOnly = "darkOnly"
    static let didSetupLoginItem = "didSetupLoginItem"
}

// MARK: - Overlay

/// Draws one translucent black window per display at the desktop window level.
/// It sits above the wallpaper (and below Finder icons), so the wallpaper dims
/// while every app window, the Dock and the menu bar stay untouched.
final class OverlayController {
    static let shared = OverlayController()

    private(set) var enabled: Bool
    private(set) var intensity: Double
    private(set) var darkOnly: Bool

    /// Called whenever the effective dimming state changes (theme, toggles, slider).
    var onChange: (() -> Void)?

    private var windows: [CGDirectDisplayID: NSWindow] = [:]
    private var appearanceObserver: NSKeyValueObservation?
    private var pendingAppearanceUpdate = false
    private let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            PrefKey.enabled: true,
            PrefKey.intensity: 0.40,
            PrefKey.darkOnly: true,
        ])
        enabled = defaults.bool(forKey: PrefKey.enabled)
        intensity = defaults.double(forKey: PrefKey.intensity)
        darkOnly = defaults.bool(forKey: PrefKey.darkOnly)
    }

    var isDarkAppearance: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    var isDimming: Bool {
        enabled && intensity > 0.005 && (isDarkAppearance || !darkOnly)
    }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(themeChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
        appearanceObserver = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            self?.scheduleAppearanceUpdate()
        }
        rebuildWindows()
        update(animated: false)
    }

    // MARK: Settings

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: PrefKey.enabled)
        update(animated: true)
        onChange?()
    }

    func setIntensity(_ value: Double) {
        intensity = value
        UserDefaults.standard.set(value, forKey: PrefKey.intensity)
        update(animated: false)
        onChange?()
    }

    func setDarkOnly(_ value: Bool) {
        darkOnly = value
        UserDefaults.standard.set(value, forKey: PrefKey.darkOnly)
        update(animated: true)
        onChange?()
    }

    // MARK: Notifications

    @objc private func screenParametersChanged() {
        rebuildWindows()
        update(animated: false)
    }

    @objc private func themeChanged() {
        scheduleAppearanceUpdate()
    }

    private func scheduleAppearanceUpdate() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.scheduleAppearanceUpdate() }
            return
        }
        guard !pendingAppearanceUpdate else { return }
        pendingAppearanceUpdate = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingAppearanceUpdate = false
            self.update(animated: true)
            self.onChange?()
        }
    }

    // MARK: Windows

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    private func makeWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = desktopLevel
        window.backgroundColor = .black
        window.alphaValue = 0
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isMovable = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.setFrame(screen.frame, display: false)
        window.orderFrontRegardless()
        return window
    }

    private func rebuildWindows() {
        var seen = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = displayID(for: screen) else { continue }
            seen.insert(id)
            if let window = windows[id] {
                window.setFrame(screen.frame, display: false)
            } else {
                windows[id] = makeWindow(for: screen)
            }
        }
        let stale = windows.keys.filter { !seen.contains($0) }
        for id in stale {
            windows.removeValue(forKey: id)?.orderOut(nil)
        }
    }

    private func update(animated: Bool) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.update(animated: animated) }
            return
        }
        let target: CGFloat = isDimming ? CGFloat(intensity) : 0
        for window in windows.values {
            if target > 0 {
                window.orderFrontRegardless()
            }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    context.allowsImplicitAnimation = true
                    window.animator().alphaValue = target
                }
            } else {
                window.alphaValue = target
            }
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let overlay = OverlayController.shared
    private weak var intensityValueLabel: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let bundleID = Bundle.main.bundleIdentifier {
            let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !others.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        overlay.onChange = { [weak self] in self?.updateStatusIcon() }
        overlay.start()
        updateStatusIcon()
        setUpLoginItemOnFirstLaunch()
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status = NSMenuItem(title: statusText(), action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let enableItem = NSMenuItem(title: "启用壁纸调暗", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.target = self
        enableItem.state = overlay.enabled ? .on : .off
        menu.addItem(enableItem)

        let darkOnlyItem = NSMenuItem(title: "仅在深色模式下生效", action: #selector(toggleDarkOnly), keyEquivalent: "")
        darkOnlyItem.target = self
        darkOnlyItem.state = overlay.darkOnly ? .on : .off
        menu.addItem(darkOnlyItem)

        menu.addItem(makeIntensityItem())
        menu.addItem(.separator())

        let service = SMAppService.mainApp
        let loginTitle = service.status == .requiresApproval
            ? "允许在后台运行（需系统设置）…"
            : "开机自动启动"
        let loginItem = NSMenuItem(title: loginTitle, action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = service.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionItem = NSMenuItem(title: "DimWallpaper \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let quitItem = NSMenuItem(title: "退出 DimWallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)
    }

    private func makeIntensityItem() -> NSMenuItem {
        let item = NSMenuItem()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 250, height: 58))

        let title = NSTextField(labelWithString: "调暗强度")
        title.font = NSFont.systemFont(ofSize: 13)
        title.textColor = .labelColor
        title.frame = NSRect(x: 14, y: 34, width: 120, height: 18)
        container.addSubview(title)

        let value = NSTextField(labelWithString: "\(Int((overlay.intensity * 100).rounded()))%")
        value.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.textColor = .secondaryLabelColor
        value.alignment = .right
        value.frame = NSRect(x: 150, y: 34, width: 86, height: 18)
        container.addSubview(value)
        intensityValueLabel = value

        let slider = NSSlider(
            value: overlay.intensity,
            minValue: 0.05,
            maxValue: 0.80,
            target: self,
            action: #selector(intensityChanged(_:))
        )
        slider.controlSize = .small
        slider.isContinuous = true
        slider.frame = NSRect(x: 14, y: 8, width: 222, height: 20)
        container.addSubview(slider)

        item.view = container
        return item
    }

    private func statusText() -> String {
        let appearance = overlay.isDarkAppearance ? "深色" : "浅色"
        if !overlay.enabled {
            return "已暂停 · 壁纸正常显示"
        }
        if overlay.isDimming {
            return "\(appearance)模式 · 壁纸已调暗 \(Int((overlay.intensity * 100).rounded()))%"
        }
        return "\(appearance)模式 · 保持原色"
    }

    private func updateStatusIcon() {
        let symbolName: String
        if !overlay.enabled {
            symbolName = "circle.slash"
        } else if overlay.isDimming {
            symbolName = "moon.fill"
        } else {
            symbolName = "sun.max"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "壁纸调暗")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = "DimWallpaper · \(statusText())"
    }

    // MARK: Actions

    @objc private func toggleEnabled() {
        overlay.setEnabled(!overlay.enabled)
    }

    @objc private func toggleDarkOnly() {
        overlay.setDarkOnly(!overlay.darkOnly)
    }

    @objc private func intensityChanged(_ sender: NSSlider) {
        overlay.setIntensity(sender.doubleValue)
        intensityValueLabel?.stringValue = "\(Int((sender.doubleValue * 100).rounded()))%"
    }

    // MARK: Login item

    private func setUpLoginItemOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: PrefKey.didSetupLoginItem) else { return }
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            defaults.set(true, forKey: PrefKey.didSetupLoginItem)
        case .notRegistered, .notFound:
            // .notFound happens when Launch Services has not indexed the fresh
            // bundle yet; register once, and retry on the next launch if it fails.
            do {
                try service.register()
                if service.status == .enabled || service.status == .requiresApproval {
                    defaults.set(true, forKey: PrefKey.didSetupLoginItem)
                }
            } catch {
                NSLog("DimWallpaper: login item registration failed: \(error)")
            }
        case .requiresApproval:
            defaults.set(true, forKey: PrefKey.didSetupLoginItem)
        @unknown default:
            defaults.set(true, forKey: PrefKey.didSetupLoginItem)
        }
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            switch service.status {
            case .enabled:
                try service.unregister()
            case .requiresApproval:
                SMAppService.openSystemSettingsLoginItems()
            case .notRegistered, .notFound:
                try service.register()
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                }
            @unknown default:
                break
            }
        } catch {
            presentError("无法修改开机启动设置：\(error.localizedDescription)")
        }
    }

    private func presentError(_ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "DimWallpaper"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// MARK: - Entry point

if CommandLine.arguments.contains("--status") {
    UserDefaults.standard.register(defaults: [
        PrefKey.enabled: true,
        PrefKey.intensity: 0.40,
        PrefKey.darkOnly: true,
    ])
    let defaults = UserDefaults.standard
    print("enabled=\(defaults.bool(forKey: PrefKey.enabled)) intensity=\(defaults.double(forKey: PrefKey.intensity)) darkOnly=\(defaults.bool(forKey: PrefKey.darkOnly)) loginItemStatus=\(SMAppService.mainApp.status.rawValue)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

import AppKit
import SwiftUI
#if canImport(DimWallpaperCore)
import DimWallpaperCore
#endif

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSMenuDelegate {
    private let launchOptions: LaunchOptions
    private let controller: DimWallpaperController
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var lastStatusSymbolName: String?
    private var lastStatusToolTip: String?

    init(launchOptions: LaunchOptions) {
        self.launchOptions = launchOptions
        self.controller = DimWallpaperController(launchOptions: launchOptions)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if !launchOptions.allowMultipleInstances, let bundleID = Bundle.main.bundleIdentifier {
            let runningPeers = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            if !runningPeers.isEmpty {
                NSApp.terminate(nil)
                return
            }
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        statusItem = item

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
        let rootView = ControlCenterView(
            controller: controller,
            version: version,
            onQuit: { NSApp.terminate(nil) }
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = .preferredContentSize

        let panelPopover = NSPopover()
        panelPopover.behavior = .transient
        panelPopover.animates = false
        panelPopover.delegate = self
        panelPopover.contentViewController = hostingController
        popover = panelPopover

        controller.onStatusAppearanceChanged = { [weak self] in
            self?.updateStatusIcon()
        }
        controller.start()
        updateStatusIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        removePopoverMonitors()
        popover?.performClose(nil)
        controller.shutdown()
    }

    // MARK: - Status Item Routing

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isContextTrigger = event?.type == .rightMouseDown
            || event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) == true)

        if isContextTrigger {
            closePopover()
            showQuickMenu(anchoredTo: sender)
            return
        }
        togglePopover(anchoredTo: sender)
    }

    private func togglePopover(anchoredTo button: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            closePopover()
        } else {
            controller.recordFrontmostAppFast()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            installPopoverMonitors()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.controller.refreshLoginStatus()
                self.controller.refreshDisplaysIfChanged()
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        removePopoverMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverMonitors()
    }

    private func installPopoverMonitors() {
        removePopoverMonitors()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.closePopover()
                return nil
            }
            return event
        }
    }

    private func removePopoverMonitors() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
            localKeyMonitor = nil
        }
    }

    // MARK: - Right-Click Quick Menu

    private func showQuickMenu(anchoredTo button: NSStatusBarButton) {
        controller.recordFrontmostAppFast()
        let menu = buildQuickMenu()
        menu.delegate = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        DispatchQueue.main.async { [weak self] in
            self?.controller.refreshLoginStatus()
        }
    }

    private func buildQuickMenu() -> NSMenu {
        let menu = NSMenu()

        let summaryItem = NSMenuItem(title: controller.state.statusSummary, action: nil, keyEquivalent: "")
        summaryItem.isEnabled = false
        menu.addItem(summaryItem)
        menu.addItem(.separator())

        let enableItem = NSMenuItem(title: "启用壁纸调暗", action: #selector(toggleEnabledFromMenu), keyEquivalent: "")
        enableItem.target = self
        enableItem.state = controller.state.snapshot.enabled ? .on : .off
        menu.addItem(enableItem)

        let darkOnlyItem = NSMenuItem(title: "仅在深色模式下生效", action: #selector(toggleDarkOnlyFromMenu), keyEquivalent: "")
        darkOnlyItem.target = self
        darkOnlyItem.state = controller.state.snapshot.darkOnly ? .on : .off
        menu.addItem(darkOnlyItem)

        let presetSubmenu = NSMenu()
        for preset in DimmingPreset.allCases {
            let presetItem = NSMenuItem(
                title: "\(preset.title) · \(preset.percentage)%",
                action: #selector(selectPresetFromMenu(_:)),
                keyEquivalent: ""
            )
            presetItem.target = self
            presetItem.representedObject = preset.rawValue
            presetItem.state = controller.state.activePreset == preset ? .on : .off
            presetSubmenu.addItem(presetItem)
        }
        let presetMenuItem = NSMenuItem(title: "壁纸快捷预设", action: nil, keyEquivalent: "")
        presetMenuItem.submenu = presetSubmenu
        menu.addItem(presetMenuItem)

        menu.addItem(.separator())

        let focusEnableItem = NSMenuItem(title: "启用专注遮罩", action: #selector(toggleFocusEnabledFromMenu), keyEquivalent: "")
        focusEnableItem.target = self
        focusEnableItem.state = controller.state.snapshot.focusEnabled ? .on : .off
        menu.addItem(focusEnableItem)

        let systemBarsItem = NSMenuItem(
            title: "同时压暗菜单栏与 Dock",
            action: #selector(toggleSystemBarsFromMenu),
            keyEquivalent: ""
        )
        systemBarsItem.target = self
        if controller.state.snapshot.dimMenuBar && controller.state.snapshot.dimDock {
            systemBarsItem.state = .on
        } else if controller.state.snapshot.dimMenuBar || controller.state.snapshot.dimDock {
            systemBarsItem.state = .mixed
        } else {
            systemBarsItem.state = .off
        }
        menu.addItem(systemBarsItem)

        let scopeSubmenu = NSMenu()
        for scope in FocusScope.allCases {
            let scopeItem = NSMenuItem(
                title: scope.title,
                action: #selector(selectFocusScopeFromMenu(_:)),
                keyEquivalent: ""
            )
            scopeItem.target = self
            scopeItem.representedObject = scope.rawValue
            scopeItem.state = controller.state.snapshot.focusScope == scope ? .on : .off
            scopeSubmenu.addItem(scopeItem)
        }
        let scopeMenuItem = NSMenuItem(title: "聚焦范围", action: nil, keyEquivalent: "")
        scopeMenuItem.submenu = scopeSubmenu
        menu.addItem(scopeMenuItem)

        let multiDisplaySubmenu = NSMenu()
        for policy in FocusMultiDisplayPolicy.allCases {
            let policyItem = NSMenuItem(
                title: policy.title,
                action: #selector(selectFocusMultiDisplayPolicyFromMenu(_:)),
                keyEquivalent: ""
            )
            policyItem.target = self
            policyItem.representedObject = policy.rawValue
            policyItem.state = controller.state.snapshot.focusMultiDisplayPolicy == policy ? .on : .off
            multiDisplaySubmenu.addItem(policyItem)
        }
        let multiDisplayMenuItem = NSMenuItem(title: "多屏策略", action: nil, keyEquivalent: "")
        multiDisplayMenuItem.submenu = multiDisplaySubmenu
        menu.addItem(multiDisplayMenuItem)

        let fullscreenExemptItem = NSMenuItem(
            title: "全屏视频自动豁免",
            action: #selector(togglePauseFocusOnFullscreenFromMenu),
            keyEquivalent: ""
        )
        fullscreenExemptItem.target = self
        fullscreenExemptItem.state = controller.state.snapshot.pauseFocusOnFullscreen ? .on : .off
        menu.addItem(fullscreenExemptItem)

        let focusPresetSubmenu = NSMenu()
        for preset in FocusPreset.allCases {
            let item = NSMenuItem(
                title: "\(preset.title) · \(preset.percentage)%",
                action: #selector(selectFocusPresetFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.rawValue
            item.state = controller.state.activeFocusPreset == preset ? .on : .off
            focusPresetSubmenu.addItem(item)
        }
        let focusPresetMenuItem = NSMenuItem(title: "专注强度预设", action: nil, keyEquivalent: "")
        focusPresetMenuItem.submenu = focusPresetSubmenu
        menu.addItem(focusPresetMenuItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: controller.loginController.menuTitle, action: #selector(toggleLoginItemFromMenu), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = controller.loginStatus == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.0"
        let versionItem = NSMenuItem(title: "DimWallpaper \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        let websiteItem = NSMenuItem(title: "访问官网 myzjx.com", action: #selector(openWebsiteFromMenu), keyEquivalent: "")
        websiteItem.target = self
        menu.addItem(websiteItem)

        let quitItem = NSMenuItem(title: "退出 DimWallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        return menu
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem?.menu = nil
    }

    @objc private func toggleEnabledFromMenu() {
        controller.toggleEnabled()
    }

    @objc private func toggleDarkOnlyFromMenu() {
        controller.setDarkOnly(!controller.state.snapshot.darkOnly)
    }

    @objc private func selectPresetFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let preset = DimmingPreset(rawValue: rawValue) else { return }
        controller.applyPreset(preset)
    }

    @objc private func toggleFocusEnabledFromMenu() {
        controller.toggleFocusEnabled()
    }

    @objc private func toggleSystemBarsFromMenu() {
        controller.toggleDimSystemBarsTogether()
    }

    @objc private func selectFocusScopeFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let scope = FocusScope(rawValue: rawValue) else { return }
        controller.setFocusScope(scope)
    }

    @objc private func selectFocusMultiDisplayPolicyFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let policy = FocusMultiDisplayPolicy(rawValue: rawValue) else { return }
        controller.setFocusMultiDisplayPolicy(policy)
    }

    @objc private func togglePauseFocusOnFullscreenFromMenu() {
        controller.setPauseFocusOnFullscreen(!controller.state.snapshot.pauseFocusOnFullscreen)
    }

    @objc private func selectFocusPresetFromMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let preset = FocusPreset(rawValue: rawValue) else { return }
        controller.applyFocusPreset(preset)
    }

    @objc private func toggleLoginItemFromMenu() {
        controller.toggleLoginItem()
        if let errorMessage = controller.loginError {
            presentError(errorMessage)
        }
    }

    @objc private func openWebsiteFromMenu() {
        if let url = URL(string: "https://myzjx.com") {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let symbolName = controller.state.statusSymbolName
        if symbolName != lastStatusSymbolName {
            let image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "壁纸调暗"
            )
            image?.isTemplate = true
            button.image = image
            lastStatusSymbolName = symbolName
        }
        let nextToolTip = "DimWallpaper · \(controller.state.statusSummary)"
        if nextToolTip != lastStatusToolTip {
            button.toolTip = nextToolTip
            lastStatusToolTip = nextToolTip
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

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
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
        let rootView = ControlCenterView(
            controller: controller,
            version: version,
            onQuit: { NSApp.terminate(nil) }
        )
        let hostingController = NSHostingController(rootView: rootView)
        hostingController.sizingOptions = .preferredContentSize

        let panelPopover = NSPopover()
        panelPopover.behavior = .transient
        panelPopover.animates = true
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
        let isContextTrigger = event?.type == .rightMouseUp
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
            controller.refreshLoginStatus()
            controller.refreshDisplaysNow()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            installPopoverMonitors()
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
        controller.refreshLoginStatus()
        let menu = buildQuickMenu()
        menu.delegate = self
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
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
        let presetMenuItem = NSMenuItem(title: "快捷场景预设", action: nil, keyEquivalent: "")
        presetMenuItem.submenu = presetSubmenu
        menu.addItem(presetMenuItem)

        menu.addItem(.separator())

        let loginItem = NSMenuItem(title: controller.loginController.menuTitle, action: #selector(toggleLoginItemFromMenu), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = controller.loginStatus == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
        let versionItem = NSMenuItem(title: "DimWallpaper \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

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

    @objc private func toggleLoginItemFromMenu() {
        controller.toggleLoginItem()
        if let errorMessage = controller.loginError {
            presentError(errorMessage)
        }
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(
            systemSymbolName: controller.state.statusSymbolName,
            accessibilityDescription: "壁纸调暗"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = "DimWallpaper · \(controller.state.statusSummary)"
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

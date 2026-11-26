import AppKit
import ServiceManagement
#if canImport(DimWallpaperCore)
import DimWallpaperCore
#endif

@MainActor
final class LoginItemController {
    var status: SMAppService.Status {
        SMAppService.mainApp.status
    }

    var statusLabel: String {
        switch status {
        case .enabled: "开机自启 · 已开启"
        case .requiresApproval: "开机自启 · 需批准"
        case .notRegistered, .notFound: "开机自启 · 未开启"
        @unknown default: "开机自启"
        }
    }

    var compactStatusLabel: String {
        switch status {
        case .enabled: "自启 · 已开"
        case .requiresApproval: "自启 · 需批"
        case .notRegistered, .notFound: "开机自启"
        @unknown default: "开机自启"
        }
    }

    var menuTitle: String {
        switch status {
        case .requiresApproval: "允许在后台运行（打开系统设置）…"
        default: "开机自动启动"
        }
    }

    func setupOnFirstLaunchIfNeeded(store: PreferencesStore, disabled: Bool) {
        guard !disabled else { return }
        guard !store.didSetupLoginItem else { return }
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled, .requiresApproval:
            store.didSetupLoginItem = true
        case .notRegistered, .notFound:
            do {
                try service.register()
                if service.status == .enabled || service.status == .requiresApproval {
                    store.didSetupLoginItem = true
                }
            } catch {
                NSLog("DimWallpaper: login item registration failed: %@", error.localizedDescription)
            }
        @unknown default:
            store.didSetupLoginItem = true
        }
    }

    @discardableResult
    func toggle() -> String? {
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
            return nil
        } catch {
            return "无法修改开机启动设置：\(error.localizedDescription)"
        }
    }
}

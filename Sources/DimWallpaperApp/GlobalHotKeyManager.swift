import Carbon
import Foundation
#if canImport(DimWallpaperCore)
import DimWallpaperCore
#endif

private let hotKeyEventHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == GlobalHotKeyManager.signature,
          hotKeyID.id == GlobalHotKeyManager.identifier else {
        return OSStatus(eventNotHandledErr)
    }
    let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.handlePressed()
    }
    return noErr
}

@MainActor
final class GlobalHotKeyManager {
    nonisolated static let signature: OSType = 0x44494D57
    nonisolated static let identifier: UInt32 = 1

    var onPressed: (() -> Void)?
    private(set) var lastError: String?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func configure(enabled: Bool, binding: HotKeyBinding) {
        unregisterHotKeyOnly()
        lastError = nil

        guard enabled else { return }
        guard binding.isValid else {
            lastError = "快捷键配置无效，未启用全局热键。"
            return
        }

        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let userData = Unmanaged.passUnretained(self).toOpaque()
            let installStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                hotKeyEventHandler,
                1,
                &eventType,
                userData,
                &eventHandlerRef
            )
            guard installStatus == noErr else {
                lastError = "无法安装快捷键事件处理器（错误码 \(installStatus)）。"
                return
            }
        }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.identifier)
        var registeredRef: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredRef
        )
        if registerStatus == noErr, let registeredRef {
            hotKeyRef = registeredRef
            lastError = nil
        } else {
            hotKeyRef = nil
            lastError = "快捷键 \(binding.displayLabel) 已被其他应用占用（错误码 \(registerStatus)）。"
        }
    }

    func shutdown() {
        unregisterHotKeyOnly()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
        lastError = nil
    }

    fileprivate func handlePressed() {
        onPressed?()
    }

    private func unregisterHotKeyOnly() {
        if let currentRef = hotKeyRef {
            UnregisterEventHotKey(currentRef)
            hotKeyRef = nil
        }
    }
}

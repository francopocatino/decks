import Carbon
import Foundation

enum HotkeyOption: String, CaseIterable, Identifiable {
    case off, ctrlOptSpace, optCmdN, ctrlOptD, ctrlOptP, ctrlOptF

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: "Off"
        case .ctrlOptSpace: "⌃⌥ Space"
        case .optCmdN: "⌥⌘ N"
        case .ctrlOptD: "⌃⌥ D"
        case .ctrlOptP: "⌃⌥ P"
        case .ctrlOptF: "⌃⌥ F"
        }
    }

    var key: (code: UInt32, modifiers: UInt32)? {
        switch self {
        case .off: nil
        case .ctrlOptSpace: (UInt32(kVK_Space), UInt32(controlKey | optionKey))
        case .optCmdN: (UInt32(kVK_ANSI_N), UInt32(optionKey | cmdKey))
        case .ctrlOptD: (UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey))
        case .ctrlOptP: (UInt32(kVK_ANSI_P), UInt32(controlKey | optionKey))
        case .ctrlOptF: (UInt32(kVK_ANSI_F), UInt32(controlKey | optionKey))
        }
    }
}

// Carbon RegisterEventHotKey: system-wide, no accessibility prompt. Holds
// several hotkeys at once, keyed by id, dispatching by the fired EventHotKeyID.
@MainActor
@Observable
final class HotkeyManager {
    private static let signature = OSType(0x4443_4B53)

    private(set) var registrationFailed = false
    @ObservationIgnored private var registrations: [UInt32: (ref: EventHotKeyRef, action: () -> Void)] = [:]
    @ObservationIgnored private var handlerRef: EventHandlerRef?

    func apply(_ option: HotkeyOption, id: UInt32 = 1, action: @escaping () -> Void) {
        if let existing = registrations[id] {
            UnregisterEventHotKey(existing.ref)
            registrations[id] = nil
        }
        registrationFailed = false
        guard let key = option.key else { return }
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(key.code, key.modifiers, hotkeyID, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            registrations[id] = (ref, action)
        } else {
            registrationFailed = true
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let userData, let event else { return noErr }
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { manager.registrations[hotkeyID.id]?.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
    }
}

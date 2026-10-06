import Carbon.HIToolbox

/// Глобальные горячие клавиши через Carbon `RegisterEventHotKey`.
///
/// В отличие от мониторов `NSEvent`, такое сочетание перехватывается системой и не доходит
/// до активного приложения — ⌃⌥T не напечатает «†» в целевом окне. Отдельных разрешений
/// для этого не нужно.
@MainActor
final class HotkeyManager {
    enum Action: UInt32, CaseIterable {
        case start = 1
        case pause = 2
    }

    /// Сигнатура приложения для идентификаторов горячих клавиш: 'HTyp'.
    private static let signature: OSType = 0x4854_7970

    private var registered: [Action: EventHotKeyRef] = [:]
    private var handlers: [Action: @MainActor () -> Void] = [:]
    private var eventHandler: EventHandlerRef?

    init() {
        installEventHandler()
    }

    /// Регистрирует сочетание для действия, заменяя прежнее. `false` — сочетание занято.
    @discardableResult
    func register(_ hotkey: Hotkey, for action: Action, handler: @escaping @MainActor () -> Void) -> Bool {
        unregister(action)
        let id = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return false }
        registered[action] = ref
        handlers[action] = handler
        return true
    }

    func unregister(_ action: Action) {
        if let ref = registered.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
        }
        handlers[action] = nil
    }

    func unregisterAll() {
        Action.allCases.forEach(unregister)
    }

    fileprivate func handle(_ id: EventHotKeyID) {
        guard id.signature == Self.signature, let action = Action(rawValue: id.id) else { return }
        handlers[action]?()
    }

    private func installEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventCallback, 1, &eventType, context, &eventHandler)
    }
}

/// C-обработчик Carbon. Вызывается на главном потоке.
private func hotkeyEventCallback(_: EventHandlerCallRef?, event: EventRef?, context: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let context else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &id
    )
    guard status == noErr else { return status }
    let hotkeyID = id
    let manager = Unmanaged<HotkeyManager>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        manager.handle(hotkeyID)
    }
    return noErr
}

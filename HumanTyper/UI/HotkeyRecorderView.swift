import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Кнопка записи сочетания клавиш: нажать → ввести сочетание с ⌘/⌃/⌥. Esc — отмена.
struct HotkeyRecorderView: View {
    @Binding var hotkey: Hotkey
    let defaultValue: Hotkey
    var onRecordingChanged: (Bool) -> Void = { _ in }

    @StateObject private var recorder = HotkeyRecorder()

    var body: some View {
        HStack(spacing: 6) {
            Button {
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    recorder.start { hotkey = $0 }
                }
            } label: {
                Text(recorder.isRecording ? "Нажмите сочетание…" : hotkey.displayString)
                    .frame(minWidth: 120)
            }
            .help("Нажмите и введите новое сочетание с ⌘, ⌃ или ⌥. Esc — отмена.")

            if hotkey != defaultValue, !recorder.isRecording {
                Button {
                    hotkey = defaultValue
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .buttonStyle(.borderless)
                .help("Вернуть \(defaultValue.displayString)")
            }
        }
        .onChange(of: recorder.isRecording) { onRecordingChanged($0) }
        .onDisappear { recorder.stop() }
    }
}

/// Перехватывает следующее нажатие в окне приложения через локальный монитор `NSEvent`.
@MainActor
private final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    func start(onRecord: @escaping @MainActor (Hotkey) -> Void) {
        stop()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = UInt32(event.keyCode)
            let modifiers = event.modifierFlags
            MainActor.assumeIsolated {
                self?.record(keyCode: keyCode, modifiers: modifiers, onRecord: onRecord)
            }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func record(keyCode: UInt32, modifiers: NSEvent.ModifierFlags, onRecord: @MainActor (Hotkey) -> Void) {
        let hotkey = Hotkey(keyCode: keyCode, modifiers: modifiers)
        if keyCode == UInt32(kVK_Escape), !hotkey.isValidGlobalHotkey {
            stop()
            return
        }
        guard hotkey.isValidGlobalHotkey else {
            NSSound.beep()
            return
        }
        onRecord(hotkey)
        stop()
    }
}

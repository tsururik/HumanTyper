import AppKit
import SwiftUI

/// Значок в строке меню: показывает отсчёт и процент набора.
struct MenuBarLabel: View {
    @ObservedObject var controller: TypingController

    var body: some View {
        switch controller.phase {
        case .countdown(let secondsLeft, _):
            Label("\(secondsLeft)", systemImage: "timer")
                .labelStyle(.titleAndIcon)
        case .typing:
            Label(percent, systemImage: "keyboard.fill")
                .labelStyle(.titleAndIcon)
        case .paused:
            Label(percent, systemImage: "pause.circle")
                .labelStyle(.titleAndIcon)
        case .idle, .finished:
            Image(systemName: "keyboard")
        }
    }

    private var percent: String {
        "\(Int((controller.progress * 100).rounded(.down)))%"
    }
}

/// Меню в строке меню.
struct MenuBarContent: View {
    @EnvironmentObject private var controller: TypingController
    @EnvironmentObject private var permission: AccessibilityPermission
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(status)

        if !permission.isGranted {
            Button("Выдать доступ к Универсальному доступу…") {
                showMainWindow()
                permission.openSystemSettings()
            }
        }

        Divider()

        Button("Начать набор (\(controller.startHotkey.displayString))") { controller.start() }
            .disabled(!controller.canStart || !permission.isGranted)

        if case .paused = controller.phase {
            Button("Продолжить (\(controller.pauseHotkey.displayString))") { controller.resume() }
        } else {
            Button("Пауза (\(controller.pauseHotkey.displayString))") { controller.pause() }
                .disabled(controller.phase != .typing)
        }

        Button("Остановить (Esc)") { controller.stop() }
            .disabled(!controller.isSessionActive)

        Divider()

        Button("Вставить текст из буфера") {
            if let string = NSPasteboard.general.string(forType: .string) {
                controller.text = string
            }
        }
        .disabled(controller.isSessionActive)

        Button("Открыть окно HumanTyper…") { showMainWindow() }

        Divider()

        Button("Выйти из HumanTyper") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var status: String {
        switch controller.phase {
        case .idle, .finished:
            controller.text.isEmpty
                ? "Текст не задан"
                : "Готов: \(Formatting.characters(controller.text.count))"
        case .countdown(let secondsLeft, _):
            "Старт через \(secondsLeft)…"
        case .typing:
            if let left = controller.breakSecondsLeft {
                "Перерыв — ещё \(Int(left.rounded(.up))) с"
            } else {
                "Набор: \(controller.typedCount)/\(controller.totalCount), осталось ≈ \(Formatting.clock(controller.remainingTime))"
            }
        case .paused:
            "Пауза: \(controller.typedCount)/\(controller.totalCount)"
        }
    }

    private func showMainWindow() {
        openWindow(id: HumanTyperApp.mainWindowID)
        NSApp.activate(ignoringOtherApps: true)
    }
}

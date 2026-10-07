import AppKit
import SwiftUI

/// Левая часть окна: текст для набора, прогресс и кнопки управления.
struct EditorPanel: View {
    @EnvironmentObject private var controller: TypingController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            editor
            SessionStatusView()
            controls
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Текст для набора").font(.headline)
            Spacer()
            Text(Formatting.characters(controller.text.count))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button {
                if let string = NSPasteboard.general.string(forType: .string) {
                    controller.text = string
                }
            } label: {
                Label("Вставить из буфера", systemImage: "doc.on.clipboard")
            }
            Button {
                controller.text = ""
            } label: {
                Label("Очистить", systemImage: "trash")
            }
            .disabled(controller.text.isEmpty)
        }
        .disabled(controller.isSessionActive)
    }

    private var editor: some View {
        TextEditor(text: $controller.text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)))
            .overlay(alignment: .topLeading) {
                if controller.text.isEmpty {
                    Text("Вставьте сюда текст — кириллица, латиница, эмодзи, переводы строк…")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .disabled(controller.isSessionActive)
            .frame(minHeight: 220)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button {
                controller.start()
            } label: {
                Label("Старт", systemImage: "play.fill").frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!controller.canStart)

            switch controller.phase {
            case .paused:
                Button {
                    controller.resume()
                } label: {
                    Label("Продолжить", systemImage: "playpause.fill")
                }
            default:
                Button {
                    controller.pause()
                } label: {
                    Label("Пауза", systemImage: "pause.fill")
                }
                .disabled(controller.phase != .typing)
            }

            Button(role: .destructive) {
                controller.stop()
            } label: {
                Label("Стоп", systemImage: "stop.fill")
            }
            .disabled(!controller.isSessionActive)

            Spacer()

            Text("\(controller.startHotkey.displayString) — старт · \(controller.pauseHotkey.displayString) — пауза · Esc — стоп")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .controlSize(.large)
    }
}

/// Прогресс, обратный отсчёт и сообщения.
struct SessionStatusView: View {
    @EnvironmentObject private var controller: TypingController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch controller.phase {
            case .idle, .finished:
                if let notice = controller.notice {
                    Label(notice, systemImage: controller.phase == .finished ? "checkmark.circle.fill" : "info.circle")
                        .foregroundStyle(controller.phase == .finished ? .green : .secondary)
                } else {
                    Label("Нажмите «Старт» и за \(TypingController.countdownSeconds) секунды поставьте курсор в нужное поле. Или поставьте курсор сразу и нажмите \(controller.startHotkey.displayString).",
                          systemImage: "keyboard")
                        .foregroundStyle(.secondary)
                }

            case .countdown(let secondsLeft):
                HStack(spacing: 14) {
                    Text("\(secondsLeft)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.accentColor)
                    Text("Переключитесь в окно и поставьте курсор в поле ввода — набор привяжется к нему.")
                        .foregroundStyle(.secondary)
                }

            case .typing:
                progress
                if let left = controller.breakSecondsLeft {
                    Label("Перерыв — ещё \(Int(left.rounded(.up))) с", systemImage: "cup.and.saucer")
                        .foregroundStyle(.secondary)
                }

            case .paused(.user):
                progress
                Label("Пауза. Нажмите \(controller.pauseHotkey.displayString) в том же окне, чтобы продолжить.",
                      systemImage: "pause.circle.fill")
                    .foregroundStyle(.orange)

            case .paused(.focusLost):
                progress
                Label(controller.notice ?? "Набор на паузе.", systemImage: "lock.circle.fill")
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
    }

    @ViewBuilder
    private var progress: some View {
        if controller.totalCount > 0 {
            ProgressView(value: controller.progress)
            HStack {
                Text("Набрано \(controller.typedCount) из \(controller.totalCount)")
                Spacer()
                if let target = controller.targetDescription {
                    Label(target, systemImage: "lock.fill")
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help("Набор привязан к этому окну и печатает только в него")
                }
                Text("Осталось ≈ \(Formatting.clock(controller.remainingTime))")
            }
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
    }
}

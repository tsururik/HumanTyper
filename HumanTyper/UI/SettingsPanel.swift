import SwiftUI

/// Настройки набора. Все значения хранятся в UserDefaults через `@AppStorage`.
struct SettingsPanel: View {
    @EnvironmentObject private var controller: TypingController

    @AppStorage(SettingsKey.wordsPerMinute) private var wordsPerMinute = AppDefaults.wordsPerMinute
    @AppStorage(SettingsKey.typoPercent) private var typoPercent = AppDefaults.typoPercent
    @AppStorage(SettingsKey.naturalRhythm) private var naturalRhythm = AppDefaults.naturalRhythm
    @AppStorage(SettingsKey.breaksEnabled) private var breaksEnabled = AppDefaults.breaksEnabled
    @AppStorage(SettingsKey.breakEveryMin) private var breakEveryMin = AppDefaults.breakEveryMin
    @AppStorage(SettingsKey.breakEveryMax) private var breakEveryMax = AppDefaults.breakEveryMax
    @AppStorage(SettingsKey.breakForMin) private var breakForMin = AppDefaults.breakForMin
    @AppStorage(SettingsKey.breakForMax) private var breakForMax = AppDefaults.breakForMax
    @AppStorage(SettingsKey.theme) private var theme: AppTheme = .system
    @AppStorage(SettingsKey.hideWindowOnStart) private var hideWindowOnStart = AppDefaults.hideWindowOnStart
    @AppStorage(SettingsKey.startHotkey) private var startHotkey: Hotkey = .defaultStart
    @AppStorage(SettingsKey.pauseHotkey) private var pauseHotkey: Hotkey = .defaultPause

    var body: some View {
        Form {
            typingSections
                .disabled(controller.isSessionActive)

            Section("Управление") {
                LabeledContent("Старт") {
                    HotkeyRecorderView(hotkey: $startHotkey, defaultValue: .defaultStart, onRecordingChanged: recordingChanged)
                }
                LabeledContent("Пауза / продолжить") {
                    HotkeyRecorderView(hotkey: $pauseHotkey, defaultValue: .defaultPause, onRecordingChanged: recordingChanged)
                }
                LabeledContent("Экстренная остановка") {
                    Text("Esc").monospaced()
                }
                if let warning = controller.hotkeyWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
                Toggle("Скрывать HumanTyper на время отсчёта", isOn: $hideWindowOnStart)
                caption("Фокус вернётся в приложение, где вы работали до этого. Если активное приложение сменится во время набора, он встанет на паузу.")
            }

            Section("Оформление") {
                Picker("Тема", selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .onChange(of: theme) { $0.apply() }
        .onChange(of: startHotkey) { _ in controller.reloadHotkeys() }
        .onChange(of: pauseHotkey) { _ in controller.reloadHotkeys() }
    }

    @ViewBuilder
    private var typingSections: some View {
        Section("Скорость") {
            LabeledContent("Скорость набора") {
                Text("\(Int(wordsPerMinute)) WPM").monospacedDigit()
            }
            Slider(value: $wordsPerMinute, in: AppDefaults.wordsPerMinuteRange, step: 5) {
                EmptyView()
            } minimumValueLabel: {
                Text("30")
            } maximumValueLabel: {
                Text("150")
            }
            caption("≈ \(Int(wordsPerMinute * 5)) знаков в минуту, задержка между символами меняется случайно в пределах ±40%.")
        }

        Section("Опечатки") {
            LabeledContent("Частота опечаток") {
                Text(typoPercent.formatted(.number.precision(.fractionLength(0...1))) + "%").monospacedDigit()
            }
            Slider(value: $typoPercent, in: AppDefaults.typoPercentRange, step: 0.5) {
                EmptyView()
            } minimumValueLabel: {
                Text("0")
            } maximumValueLabel: {
                Text("20")
            }
            caption("Промах по соседней клавише (QWERTY или ЙЦУКЕН), пауза, Backspace и правильный символ. Примерно каждая пятая ошибка замечается через 1–3 символа.")
        }

        Section("Ритм") {
            Toggle("Естественный ритм", isOn: $naturalRhythm)
            caption("Паузы после пробела (50–150 мс), запятой (0,2–0,5 с), точки (0,4–1,2 с) и абзаца (1–3 с). Заглавные буквы и спецсимволы набираются медленнее.")
        }

        Section("Перерывы") {
            Toggle("Делать перерывы", isOn: $breaksEnabled)
            Group {
                SecondsRangeRow(title: "Каждые", lower: $breakEveryMin, upper: $breakEveryMax, bounds: AppDefaults.breakEveryRange)
                SecondsRangeRow(title: "Пауза на", lower: $breakForMin, upper: $breakForMax, bounds: AppDefaults.breakForRange)
            }
            .disabled(!breaksEnabled)
        }
    }

    private func recordingChanged(_ isRecording: Bool) {
        if isRecording {
            controller.suspendHotkeys()
        } else {
            controller.reloadHotkeys()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Строка «от … до … с» с полями и степперами.
private struct SecondsRangeRow: View {
    let title: String
    @Binding var lower: Int
    @Binding var upper: Int
    let bounds: ClosedRange<Int>

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                SecondsField(value: $lower, bounds: bounds)
                Text("–")
                SecondsField(value: $upper, bounds: bounds)
                Text("с").foregroundStyle(.secondary)
            }
        }
        .onChange(of: lower) { if $0 > upper { upper = $0 } }
        .onChange(of: upper) { if $0 < lower { lower = $0 } }
    }
}

private struct SecondsField: View {
    @Binding var value: Int
    let bounds: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 2) {
            TextField("", value: clamped, format: .number.grouping(.never))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 52)
            Stepper("", value: $value, in: bounds)
                .labelsHidden()
        }
    }

    private var clamped: Binding<Int> {
        Binding(
            get: { value },
            set: { value = min(max($0, bounds.lowerBound), bounds.upperBound) }
        )
    }
}

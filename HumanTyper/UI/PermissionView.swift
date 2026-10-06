import SwiftUI

/// Экран, который показывается, пока нет доступа к Универсальному доступу.
struct PermissionView: View {
    @EnvironmentObject private var permission: AccessibilityPermission

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "hand.raised.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Нужен доступ к «Универсальному доступу»")
                .font(.title2.bold())

            Text("HumanTyper набирает текст, отправляя нажатия клавиш в другие приложения, и следит за клавишей Esc для экстренной остановки. macOS разрешает это только программам из списка «Универсальный доступ».")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520)

            VStack(alignment: .leading, spacing: 10) {
                step(1, "Нажмите «Открыть Системные настройки».")
                step(2, "В разделе «Конфиденциальность и безопасность → Универсальный доступ» включите переключатель у HumanTyper. Если приложения нет в списке — нажмите «+» и выберите HumanTyper.app.")
                step(3, "Вернитесь сюда — окно обновится само, перезапуск не нужен.")
            }
            .frame(maxWidth: 520, alignment: .leading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))

            HStack(spacing: 12) {
                Button("Открыть Системные настройки") { permission.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Показать системный запрос") { permission.request() }
                    .controlSize(.large)
            }

            Label("Проверяю доступ каждую секунду…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.callout.bold())
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

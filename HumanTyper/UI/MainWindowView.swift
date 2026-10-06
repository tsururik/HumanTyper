import SwiftUI

/// Главное окно: без доступа — экран разрешений, с доступом — текст слева, настройки справа.
struct MainWindowView: View {
    @EnvironmentObject private var permission: AccessibilityPermission

    var body: some View {
        Group {
            if permission.isGranted {
                HStack(spacing: 0) {
                    EditorPanel()
                        .frame(minWidth: 480, maxWidth: .infinity)
                    Divider()
                    SettingsPanel()
                        .frame(width: 360)
                }
            } else {
                PermissionView()
            }
        }
        .frame(minWidth: 880, minHeight: 600)
    }
}

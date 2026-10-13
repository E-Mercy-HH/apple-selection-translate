import ApplicationServices
import AppKit
import SwiftUI

@MainActor
private final class AccessibilityState: ObservableObject {
    @Published var isGranted = AXIsProcessTrusted()
}

@MainActor
struct SettingsView: View {
    let onRequestAccessibility: () -> Void
    let onCheckAccessibility: () -> Void

    @StateObject private var accessibility = AccessibilityState()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("自动划词翻译")
                        .font(.title2.bold())
                    Text("鼠标选中英文或中文后，使用 macOS 系统翻译在附近显示译文。")
                        .foregroundStyle(.secondary)
                }

                GroupBox("辅助功能权限") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(accessibility.isGranted ? "已授权，可以读取选中的文字" : "尚未授权，无法读取其他应用的选区",
                              systemImage: accessibility.isGranted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        HStack {
                            Button("请求授权") {
                                onRequestAccessibility()
                            }
                            Button("重新检查并开始") {
                                onCheckAccessibility()
                                accessibility.isGranted = AXIsProcessTrusted()
                            }
                            Button("打开系统设置") {
                                guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
                                NSWorkspace.shared.open(url)
                            }
                            Button("定位当前应用") {
                                NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                            }
                        }
                        Text("授权后返回此窗口会自动重新检查。若系统设置显示已开启但这里仍未授权，请移除旧条目，再把当前应用重新加入并开启。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }

                LanguageSetupView()

                Text("本工具不连接第三方翻译服务、不记录历史、不自动复制或替换文字。系统语言包由 macOS 管理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 560, height: 480)
        .onAppear { accessibility.isGranted = AXIsProcessTrusted() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            onCheckAccessibility()
            accessibility.isGranted = AXIsProcessTrusted()
        }
    }
}

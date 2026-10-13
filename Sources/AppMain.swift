import ApplicationServices
import AppKit
import SwiftUI

@MainActor
private enum AppRuntime {
    static var delegate: AppCoordinator?
}

@MainActor
final class AppCoordinator: NSObject, NSApplicationDelegate {
    private let monitor = SelectionMonitor()
    private let translator = SystemTranslator()
    private let popup = PopupController()

    private var statusItem: NSStatusItem?
    private var enabledMenuItem: NSMenuItem?
    private var settingsWindow: NSWindow?
    private var currentTranslation: Task<Void, Never>?
    private var requestNumber: UInt64 = 0
    private var sourceApplicationPID: pid_t?
    private var isEnabled = true
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()

        monitor.onSelection = { [weak self] selection in
            self?.translate(selection)
        }
        popup.onDismiss = { [weak self] in
            self?.cancelTranslation()
        }

        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceNotifications.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            Task { @MainActor [weak self] in
                guard let self, let sourceApplicationPID = self.sourceApplicationPID else { return }
                if activatedPID != sourceApplicationPID {
                    self.dismissForContextChange()
                }
            }
        })
        workspaceObservers.append(workspaceNotifications.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.dismissForContextChange()
            }
        })

        refreshMonitoring()
        if !AXIsProcessTrusted() {
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        let workspaceNotifications = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            workspaceNotifications.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        monitor.stop()
        cancelTranslation()
        popup.hide(notify: false)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "character.bubble.fill", accessibilityDescription: "自动划词翻译")
        if item.button?.image == nil {
            item.button?.title = "译"
        }

        let menu = NSMenu()
        let enabled = NSMenuItem(title: "自动划词翻译", action: #selector(toggleEnabled(_:)), keyEquivalent: "")
        enabled.target = self
        enabled.state = .on
        menu.addItem(enabled)
        enabledMenuItem = enabled

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置与语言包…", action: #selector(openSettings(_:)), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)

        let checkPermission = NSMenuItem(title: "重新检查辅助功能权限", action: #selector(checkPermission(_:)), keyEquivalent: "")
        checkPermission.target = self
        menu.addItem(checkPermission)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func refreshMonitoring() {
        if isEnabled && AXIsProcessTrusted() {
            monitor.start()
        } else {
            monitor.stop()
            cancelTranslation()
            popup.hide(notify: false)
        }
        enabledMenuItem?.state = isEnabled ? .on : .off
    }

    private func translate(_ selection: CapturedSelection) {
        guard isEnabled,
              AXIsProcessTrusted(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == selection.applicationPID else { return }

        cancelTranslation()
        requestNumber &+= 1
        let thisRequest = requestNumber
        sourceApplicationPID = selection.applicationPID
        popup.showLoading(near: selection.cursorLocation)

        currentTranslation = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.requestNumber == thisRequest {
                    self.currentTranslation = nil
                }
            }
            do {
                let result = try await translator.translate(selection.text)
                guard !Task.isCancelled,
                      self.requestNumber == thisRequest,
                      self.popup.isVisible else { return }
                guard self.sourceApplicationPID == selection.applicationPID,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == selection.applicationPID else {
                    self.dismissForContextChange()
                    return
                }
                self.popup.showResult(result)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      self.requestNumber == thisRequest,
                      self.popup.isVisible else { return }
                guard self.sourceApplicationPID == selection.applicationPID,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == selection.applicationPID else {
                    self.dismissForContextChange()
                    return
                }
                self.popup.showError(error.localizedDescription)
            }
        }
    }

    private func cancelTranslation() {
        requestNumber &+= 1
        currentTranslation?.cancel()
        currentTranslation = nil
        sourceApplicationPID = nil
        translator.cancel()
    }

    private func dismissForContextChange() {
        guard sourceApplicationPID != nil else { return }
        cancelTranslation()
        popup.hide(notify: false)
    }

    private func showSettings() {
        cancelTranslation()
        popup.hide(notify: false)

        if settingsWindow == nil {
            let view = SettingsView(
                onRequestAccessibility: { [weak self] in self?.requestAccessibility() },
                onCheckAccessibility: { [weak self] in self?.refreshMonitoring() }
            )
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
                                  styleMask: [.titled, .closable, .miniaturizable],
                                  backing: .buffered,
                                  defer: false)
            window.title = "自动划词翻译设置"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func requestAccessibility() {
        let options: NSDictionary = [
            "AXTrustedCheckOptionPrompt": true
        ]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        isEnabled.toggle()
        refreshMonitoring()
        if isEnabled && !AXIsProcessTrusted() {
            showSettings()
        }
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        showSettings()
    }

    @objc private func checkPermission(_ sender: NSMenuItem) {
        refreshMonitoring()
        if !AXIsProcessTrusted() {
            showSettings()
        }
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}

@main
enum AppMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppCoordinator()
        AppRuntime.delegate = delegate
        app.delegate = delegate
        app.run()
    }
}

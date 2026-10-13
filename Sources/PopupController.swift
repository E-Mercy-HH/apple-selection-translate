import AppKit
import SwiftUI

@MainActor
private final class PopupContent: ObservableObject {
    @Published var result = ""
    @Published var error: String?
    @Published var isLoading = true
    @Published var layout = PopupLayout.initial
}

private struct PopupLayout {
    static let padding: CGFloat = 16
    static let spacing: CGFloat = 10
    static let headerHeight: CGFloat = 24
    static let footerHeight: CGFloat = 14
    static let margin: CGFloat = 8
    static let initial = PopupLayout(width: 290, bodyHeight: 24, scrolls: false)

    let width: CGFloat
    let bodyHeight: CGFloat
    let scrolls: Bool

    var bodyWidth: CGFloat { max(1, width - 2 * Self.padding) }
    var height: CGFloat {
        2 * Self.padding + Self.headerHeight + 2 * Self.spacing + bodyHeight + Self.footerHeight
    }
    var size: NSSize { NSSize(width: width, height: height) }

    static func loading(in visibleFrame: NSRect) -> PopupLayout {
        let width = min(290, max(1, visibleFrame.width - 2 * margin))
        let bodyHeight = min(24, availableBodyHeight(in: visibleFrame))
        return PopupLayout(width: width, bodyHeight: bodyHeight, scrolls: false)
    }

    static func text(_ value: String, in visibleFrame: NSRect) -> PopupLayout {
        let maximumWidth = min(420, max(1, visibleFrame.width - 2 * margin))
        let minimumWidth = min(240, maximumWidth)
        let maximumBodyWidth = max(1, maximumWidth - 2 * padding)
        let measuredWidth = measure(value, constrainedTo: maximumBodyWidth).width
        let width = min(maximumWidth, max(minimumWidth, ceil(measuredWidth) + 2 * padding + 8))
        let bodyWidth = max(1, width - 2 * padding)

        let measuredHeight = measure(value, constrainedTo: bodyWidth).height
        let font = NSFont.preferredFont(forTextStyle: .body)
        let fontLineHeight = ceil(font.ascender - font.descender + font.leading)
        let lineCount = max(1, ceil(measuredHeight / max(1, fontLineHeight)))
        let trailingLineHeight = value.hasSuffix("\n") ? fontLineHeight : 0
        let requiredHeight = max(fontLineHeight + 4,
                                 ceil(measuredHeight + trailingLineHeight + 4 + lineCount))
        let maximumBodyHeight = min(280, visibleFrame.height * 0.42,
                                    availableBodyHeight(in: visibleFrame))
        return PopupLayout(width: width,
                           bodyHeight: min(requiredHeight, maximumBodyHeight),
                           scrolls: requiredHeight > maximumBodyHeight)
    }

    private static func availableBodyHeight(in visibleFrame: NSRect) -> CGFloat {
        max(1, visibleFrame.height - 2 * margin -
            (2 * padding + headerHeight + 2 * spacing + footerHeight))
    }

    private static func measure(_ value: String, constrainedTo width: CGFloat) -> NSRect {
        (value as NSString).boundingRect(
            with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.preferredFont(forTextStyle: .body)]
        )
    }
}

private struct TranslationPopup: View {
    @ObservedObject var content: PopupContent
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: PopupLayout.spacing) {
            HStack {
                Label("系统翻译", systemImage: "character.bubble")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭翻译")
            }
            .frame(width: content.layout.bodyWidth, height: PopupLayout.headerHeight)

            if content.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在使用 Mac 上的翻译模型…")
                        .foregroundStyle(.secondary)
                }
                .frame(width: content.layout.bodyWidth,
                       height: content.layout.bodyHeight,
                       alignment: .topLeading)
            } else {
                messageView
            }

            Text("不会修改原文")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: content.layout.bodyWidth,
                       height: PopupLayout.footerHeight,
                       alignment: .leading)
        }
        .padding(PopupLayout.padding)
        .frame(width: content.layout.width, height: content.layout.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.quaternary, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var messageView: some View {
        let message = content.error ?? content.result
        let color: Color = content.error == nil ? .primary : .red

        if content.layout.scrolls {
            ScrollView(.vertical) {
                Text(message)
                    .font(.body)
                    .foregroundStyle(color)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: content.layout.bodyWidth, height: content.layout.bodyHeight)
        } else {
            Text(message)
                .font(.body)
                .foregroundStyle(color)
                .textSelection(.enabled)
                .frame(width: content.layout.bodyWidth,
                       height: content.layout.bodyHeight,
                       alignment: .topLeading)
        }
    }
}

@MainActor
final class PopupController {
    var onDismiss: (() -> Void)?

    private let content = PopupContent()
    private var panel: NSPanel?
    private var outsideClickMonitor: Any?
    private var escapeMonitor: Any?
    private var presentationNumber: UInt64 = 0
    private var anchor: NSPoint?

    var isVisible: Bool { panel?.isVisible ?? false }

    func showLoading(near point: NSPoint) {
        hide(notify: false)
        presentationNumber &+= 1
        let thisPresentation = presentationNumber
        content.result = ""
        content.error = nil
        content.isLoading = true
        anchor = point

        let visibleFrame = visibleFrame(near: point)
        let layout = PopupLayout.loading(in: visibleFrame)
        content.layout = layout
        let panel = NSPanel(contentRect: NSRect(origin: popupOrigin(near: point,
                                                                   size: layout.size,
                                                                   in: visibleFrame),
                                            size: layout.size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: TranslationPopup(content: content) { [weak self] in
            self?.hide()
        })

        self.panel = panel
        panel.orderFrontRegardless()
        installDismissMonitors(for: thisPresentation)
    }

    func showResult(_ value: String) {
        guard isVisible else { return }
        content.result = String(decoding: value.utf16.prefix(10_000), as: UTF16.self)
        content.error = nil
        content.isLoading = false
        resizeForText(content.result)
    }

    func showError(_ message: String) {
        guard isVisible else { return }
        content.error = String(decoding: message.utf16.prefix(10_000), as: UTF16.self)
        content.isLoading = false
        resizeForText(content.error ?? "")
    }

    func hide(notify: Bool = true) {
        presentationNumber &+= 1
        removeDismissMonitors()
        let wasVisible = isVisible
        panel?.orderOut(nil)
        panel = nil
        anchor = nil
        content.result = ""
        content.error = nil
        content.isLoading = false
        if notify && wasVisible {
            onDismiss?()
        }
    }

    private func resizeForText(_ value: String) {
        guard let panel, let anchor else { return }
        let visibleFrame = visibleFrame(near: anchor)
        let layout = PopupLayout.text(value, in: visibleFrame)
        content.layout = layout
        panel.setFrame(NSRect(origin: popupOrigin(near: anchor,
                                                 size: layout.size,
                                                 in: visibleFrame),
                              size: layout.size),
                       display: true,
                       animate: false)
    }

    private func visibleFrame(near point: NSPoint) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        return screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func popupOrigin(near point: NSPoint, size: NSSize, in frame: NSRect) -> NSPoint {
        let margin = PopupLayout.margin
        let x = min(max(point.x + 12, frame.minX + margin), frame.maxX - size.width - margin)
        let below = point.y - size.height - 12
        let preferredY = below >= frame.minY + margin ? below : point.y + 12
        let y = min(max(preferredY, frame.minY + margin), frame.maxY - size.height - margin)
        return NSPoint(x: x, y: y)
    }

    private func installDismissMonitors(for expectedPresentation: UInt64) {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.presentationNumber == expectedPresentation else { return }
                self?.hide()
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor [weak self] in
                guard self?.presentationNumber == expectedPresentation else { return }
                self?.hide()
            }
            return nil
        }
    }

    private func removeDismissMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        outsideClickMonitor = nil
        escapeMonitor = nil
    }
}

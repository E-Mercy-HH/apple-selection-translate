import AppKit
import ApplicationServices

struct CapturedSelection {
    let text: String
    let applicationPID: pid_t
    let cursorLocation: NSPoint
}

private enum MousePhase: Sendable {
    case down
    case dragged
    case up
}

private struct MouseSample: Sendable {
    let phase: MousePhase
    let timestamp: TimeInterval
    let clickCount: Int
    let shiftHeld: Bool
}

@MainActor
final class SelectionMonitor {
    var onSelection: ((CapturedSelection) -> Void)?

    private struct LastEmission {
        let textHash: Int
        let textLength: Int
        let applicationPID: pid_t
        let focusedElement: AXUIElement
        let selectedRange: SelectedRange?
    }

    private struct SelectedRange: Equatable {
        let location: Int
        let length: Int
    }

    private enum AXStringAttribute {
        case value(String)
        case absent
        case invalid
    }

    private struct MouseGesture {
        let applicationPID: pid_t
        let startedAt: TimeInterval
        let clickCount: Int
        let shiftHeld: Bool
        var sawDragEvent = false

        mutating func record(_ sample: MouseSample) {
            if sample.phase == .dragged {
                sawDragEvent = true
            }
        }
    }

    private let ownPID = NSRunningApplication.current.processIdentifier
    private var eventMonitor: Any?
    private var monitorEpoch: UInt64 = 0
    private var mouseGesture: MouseGesture?
    private var pendingCapture: Task<Void, Never>?
    private var generation: UInt64 = 0
    private var lastEmission: LastEmission?

    func start() {
        guard eventMonitor == nil else { return }

        monitorEpoch &+= 1
        let epoch = monitorEpoch
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            let phase: MousePhase
            switch event.type {
            case .leftMouseDown: phase = .down
            case .leftMouseDragged: phase = .dragged
            case .leftMouseUp: phase = .up
            default: return
            }
            let sample = MouseSample(phase: phase,
                                     timestamp: event.timestamp,
                                     clickCount: event.clickCount,
                                     shiftHeld: event.modifierFlags.contains(.shift))
            // Preserve the down/drag/up order; independent MainActor tasks can overtake.
            DispatchQueue.main.async { [weak self] in
                self?.handleMouseEvent(sample, monitorEpoch: epoch)
            }
        }
    }

    func stop() {
        monitorEpoch &+= 1
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = nil
        mouseGesture = nil
        generation &+= 1
        pendingCapture?.cancel()
        pendingCapture = nil
        lastEmission = nil
    }

    private func handleMouseEvent(_ sample: MouseSample, monitorEpoch epoch: UInt64) {
        // A queued event handler from an earlier monitor must not act after a restart.
        guard eventMonitor != nil, monitorEpoch == epoch else { return }

        switch sample.phase {
        case .down:
            // A later click invalidates an earlier selection capture, even if this
            // click does not become a qualifying selection gesture.
            generation &+= 1
            pendingCapture?.cancel()
            pendingCapture = nil
            guard let applicationPID = frontmostExternalPID() else {
                mouseGesture = nil
                return
            }
            mouseGesture = MouseGesture(applicationPID: applicationPID,
                                        startedAt: sample.timestamp,
                                        clickCount: sample.clickCount,
                                        shiftHeld: sample.shiftHeld)

        case .dragged:
            guard var gesture = mouseGesture,
                  frontmostExternalPID() == gesture.applicationPID else {
                mouseGesture = nil
                return
            }
            guard sample.timestamp >= gesture.startedAt else { return }
            gesture.record(sample)
            mouseGesture = gesture

        case .up:
            guard let gesture = mouseGesture else { return }
            mouseGesture = nil
            guard frontmostExternalPID() == gesture.applicationPID,
                  sample.timestamp >= gesture.startedAt,
                  sample.timestamp - gesture.startedAt <= 30 else { return }

            let isMultiClick = gesture.clickCount >= 2 && sample.clickCount >= 2
            guard gesture.sawDragEvent || isMultiClick || gesture.shiftHeld else { return }
            scheduleCapture(from: gesture.applicationPID, monitorEpoch: epoch)
        }
    }

    private func frontmostExternalPID() -> pid_t? {
        guard let applicationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              applicationPID != ownPID else { return nil }
        return applicationPID
    }

    private func scheduleCapture(from applicationPID: pid_t, monitorEpoch epoch: UInt64) {
        guard eventMonitor != nil,
              monitorEpoch == epoch,
              frontmostExternalPID() == applicationPID else { return }

        generation &+= 1
        pendingCapture?.cancel()
        pendingCapture = nil

        let cursorLocation = NSEvent.mouseLocation
        let currentGeneration = generation

        pendingCapture = Task { @MainActor [weak self] in
            defer {
                if let self, self.generation == currentGeneration {
                    self.pendingCapture = nil
                }
            }

            do {
                try await Task.sleep(nanoseconds: 80_000_000)
            } catch {
                return
            }

            guard let self,
                  !Task.isCancelled,
                  self.eventMonitor != nil,
                  self.monitorEpoch == epoch,
                  self.generation == currentGeneration else { return }

            self.captureSelection(from: applicationPID, at: cursorLocation)
        }
    }

    private func captureSelection(from applicationPID: pid_t, at cursorLocation: NSPoint) {
        guard AXIsProcessTrusted(),
              applicationPID != ownPID,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == applicationPID,
              let focusedElement = focusedElement() else {
            return
        }

        AXUIElementSetMessagingTimeout(focusedElement, 0.5)
        var focusedPID: pid_t = 0
        guard AXUIElementGetPid(focusedElement, &focusedPID) == .success,
              focusedPID == applicationPID,
              isSafeTextElement(focusedElement),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == applicationPID else { return }

        let selectedRange = selectedTextRange(of: focusedElement)
        // A provider that exposes a range can reject an oversized selection
        // before asking it to materialize the selected text.
        if let selectedRange,
           selectedRange.length == 0 || selectedRange.length > 10_000 { return }

        guard let text = boundedSelectedText(of: focusedElement),
              !text.isEmpty,
              text.count <= 5_000,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == applicationPID else {
            return
        }

        let textHash = text.hashValue
        let textLength = text.count
        if let previous = lastEmission,
           previous.applicationPID == applicationPID,
           CFEqual(previous.focusedElement, focusedElement),
           previous.textHash == textHash,
           previous.textLength == textLength {
            // Without a changed AX range, the same bytes may be a retained
            // selection exposed after an unrelated gesture. Suppress it.
            if selectedRange == nil || previous.selectedRange == nil ||
                selectedRange == previous.selectedRange {
                return
            }
        }

        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == applicationPID else {
            return
        }

        lastEmission = LastEmission(textHash: textHash,
                                    textLength: textLength,
                                    applicationPID: applicationPID,
                                    focusedElement: focusedElement,
                                    selectedRange: selectedRange)
        onSelection?(CapturedSelection(text: text,
                                       applicationPID: applicationPID,
                                       cursorLocation: cursorLocation))
    }

    private func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.5)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func isSafeTextElement(_ element: AXUIElement) -> Bool {
        guard case let .value(role) = stringAttribute(kAXRoleAttribute as CFString, of: element),
              role != "AXSecureTextField" else { return false }

        switch stringAttribute(kAXSubroleAttribute as CFString, of: element) {
        case .value(let subrole):
            return subrole != "AXSecureTextField"
        case .absent:
            return true
        case .invalid:
            return false
        }
    }

    private func boundedSelectedText(of element: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedTextAttribute as CFString,
                                            &value) == .success,
              let value,
              CFGetTypeID(value) == CFStringGetTypeID(),
              CFStringGetLength((value as! CFString)) <= 10_000,
              let text = value as? String,
              text.utf8.count <= 20_000 else { return nil }
        return text
    }

    private func selectedTextRange(of element: AXUIElement) -> SelectedRange? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element,
                                            kAXSelectedTextRangeAttribute as CFString,
                                            &value) == .success,
              let value,
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axValue, .cfRange, &range),
              range.location >= 0,
              range.length >= 0 else { return nil }
        return SelectedRange(location: range.location, length: range.length)
    }

    private func stringAttribute(_ attribute: CFString, of element: AXUIElement) -> AXStringAttribute {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)

        if error == .noValue || error == .attributeUnsupported {
            return .absent
        }
        guard error == .success,
              let value,
              CFGetTypeID(value) == CFStringGetTypeID(),
              CFStringGetLength((value as! CFString)) <= 128,
              let text = value as? String else { return .invalid }
        return .value(text)
    }
}

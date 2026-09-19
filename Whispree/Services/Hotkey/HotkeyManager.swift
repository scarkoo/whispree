import AppKit
import Combine
import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording", default: .init(.r, modifiers: [.control, .shift]))
    static let quickFix = Self("quickFix", default: .init(.d, modifiers: [.control, .shift]))
}

@MainActor
final class HotkeyManager: ObservableObject {
    var onRecordingToggle: ((Bool) -> Void)?
    var onCancel: (() -> Void)?
    var onQuickFix: (() -> Void)?

    private let appState: AppState
    let eventTapService = EventTapHotkeyService.shared
    private var eventTap: EventTapHotkeyService { eventTapService }
    private var isKeyDown = false
    private var escMonitorLocal: Any?
    private var accessibilityCancellable: AnyCancellable?
    private var stateCancellable = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        eventTap.start()
        setupHotkeys()
        setupEscCancel()

        accessibilityCancellable = PermissionManager.shared.$accessibility
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard status == .granted else { return }
                self?.eventTap.start()
            }
    }

    private func setupHotkeys() {
        eventTap.clearBindings()
        switch appState.settings.recordingMode {
        case .pushToTalk: setupPushToTalk()
        case .toggle: setupToggleMode()
        }
        setupQuickFixHotkey()
    }

    func updateMode(_ mode: RecordingMode) {
        appState.settings.recordingMode = mode
        setupHotkeys()
    }

    func reloadHotkeys() { setupHotkeys() }

    private func setupPushToTalk() {
        let shortcut = appState.settings.toggleRecordingShortcut
        eventTap.register(
            whispreeShortcut: shortcut,
            keyDown: { [weak self] in
                guard let self, !isKeyDown else { return }
                isKeyDown = true
                onRecordingToggle?(true)
            },
            keyUp: { [weak self] in
                guard let self, isKeyDown else { return }
                isKeyDown = false
                onRecordingToggle?(false)
            }
        )
    }

    private func setupToggleMode() {
        let shortcut = appState.settings.toggleRecordingShortcut
        eventTap.register(
            whispreeShortcut: shortcut,
            keyDown: { [weak self] in
                guard let self else { return }
                onRecordingToggle?(!appState.isRecording)
            }
        )
    }

    private func setupQuickFixHotkey() {
        eventTap.register(
            whispreeShortcut: appState.settings.quickFixShortcut,
            keyDown: { [weak self] in self?.onQuickFix?() }
        )
    }

    private func setupEscCancel() {
        escMonitorLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self else { return event }
            if appState.isRecording || appState.transcriptionState != .idle {
                onCancel?()
                return nil
            }
            return event
        }

        eventTap.onEscPressed = { [weak self] in self?.onCancel?() }

        appState.$transcriptionState
            .combineLatest(appState.$isRecording, appState.$dictationQueueSnapshot)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state, isRecording, snapshot in
                guard let self else { return }
                let visibleProcessing = (state == .transcribing || state == .correcting)
                    && snapshot.foregroundJobSequence != nil
                eventTap.isSelectionActive = false
                eventTap.isPipelineActive = isRecording || visibleProcessing || state == .inserting
            }
            .store(in: &stateCancellable)
    }

    deinit {
        if let escMonitorLocal { NSEvent.removeMonitor(escMonitorLocal) }
    }
}

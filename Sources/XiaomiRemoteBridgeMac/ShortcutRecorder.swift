import Foundation

final class ShortcutRecorder {
    private(set) var isRecording = false
    private(set) var preview = ""

    var onPreviewChange: ((String) -> Void)?
    var onComplete: ((KeyChord) -> Void)?
    var onCancel: (() -> Void)?

    private var currentModifiers = Set<KeyModifier>()
    private var capturedModifiers = Set<KeyModifier>()
    private var capturedKey: ShortcutKey?
    private var primaryKeyIsDown = false

    func start() {
        reset()
        isRecording = true
        publishPreview()
    }

    func stop() {
        reset()
    }

    func cancel() {
        guard isRecording else { return }
        reset()
        onCancel?()
    }

    func handleFlagsChanged(
        _ modifiers: Set<KeyModifier>,
        isSynthetic: Bool = false
    ) {
        guard isRecording, !isSynthetic else { return }
        currentModifiers = modifiers

        if capturedKey == nil, modifiers.count > capturedModifiers.count {
            capturedModifiers = modifiers
        }
        publishPreview()
        finishIfReleased()
    }

    func handleKeyDown(
        _ key: ShortcutKey,
        modifiers: Set<KeyModifier>,
        isRepeat: Bool = false,
        isSynthetic: Bool = false
    ) {
        guard isRecording, !isSynthetic, !isRepeat else { return }
        if key.keyCode == 53 {
            cancel()
            return
        }
        guard capturedKey == nil else { return }

        currentModifiers = modifiers
        capturedModifiers = modifiers
        capturedKey = key
        primaryKeyIsDown = true
        publishPreview()
    }

    func handleKeyUp(
        _ key: ShortcutKey,
        modifiers: Set<KeyModifier>,
        isSynthetic: Bool = false
    ) {
        guard isRecording, !isSynthetic, capturedKey?.keyCode == key.keyCode else {
            return
        }
        currentModifiers = modifiers
        primaryKeyIsDown = false
        publishPreview()
        finishIfReleased()
    }

    private func finishIfReleased() {
        guard
            isRecording,
            !primaryKeyIsDown,
            currentModifiers.isEmpty,
            let chord = KeyChord(modifiers: capturedModifiers, key: capturedKey)
        else {
            return
        }

        reset()
        onComplete?(chord)
    }

    private func publishPreview() {
        if let chord = KeyChord(
            modifiers: capturedModifiers.isEmpty ? currentModifiers : capturedModifiers,
            key: capturedKey
        ) {
            preview = chord.displayName
        } else {
            preview = "请按下快捷键"
        }
        onPreviewChange?(preview)
    }

    private func reset() {
        isRecording = false
        preview = ""
        currentModifiers.removeAll()
        capturedModifiers.removeAll()
        capturedKey = nil
        primaryKeyIsDown = false
    }
}

import AppKit
import SwiftUI

private enum ShortcutCaptureTarget: Hashable {
    case button(RemoteButton)
    case combination(RemoteButtonChord)
}

@MainActor
private final class ShortcutCaptureModel: ObservableObject {
    @Published private(set) var recordingTarget: ShortcutCaptureTarget?
    @Published private(set) var preview = ""

    private let recorder = ShortcutRecorder()
    private let eventTap = ShortcutCaptureEventTap()
    private var completion: ((KeyChord) -> Void)?

    init() {
        recorder.onPreviewChange = { [weak self] preview in
            self?.preview = preview
        }
        recorder.onComplete = { [weak self] chord in
            self?.finish(with: chord)
        }
        recorder.onCancel = { [weak self] in
            self?.finish(with: nil)
        }
    }

    deinit {
        eventTap.stop()
    }

    func begin(
        for target: ShortcutCaptureTarget,
        onComplete: @escaping (KeyChord) -> Void
    ) {
        cancel()
        completion = onComplete
        recordingTarget = target
        guard eventTap.start(handler: { [weak self] type, event in
            self?.handle(type: type, event: event)
        }) else {
            finish(with: nil)
            return
        }
        recorder.start()
    }

    func cancel() {
        guard recordingTarget != nil || eventTap.isRunning else { return }
        recorder.stop()
        finish(with: nil)
    }

    private func finish(with chord: KeyChord?) {
        let callback = completion
        completion = nil
        eventTap.stop()
        recorder.stop()
        recordingTarget = nil
        preview = ""
        if let chord {
            callback?(chord)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) {
        let modifiers = Self.modifiers(from: event.flags)
        switch type {
        case .flagsChanged:
            recorder.handleFlagsChanged(modifiers)
        case .keyDown:
            recorder.handleKeyDown(
                Self.shortcutKey(from: event),
                modifiers: modifiers,
                isRepeat: event.getIntegerValueField(
                    .keyboardEventAutorepeat
                ) != 0
            )
        case .keyUp:
            recorder.handleKeyUp(
                Self.shortcutKey(from: event),
                modifiers: modifiers
            )
        default:
            break
        }
    }

    private static func modifiers(
        from flags: CGEventFlags
    ) -> Set<KeyModifier> {
        var result = Set<KeyModifier>()
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        return result
    }

    private static func shortcutKey(from event: CGEvent) -> ShortcutKey {
        let keyCode = UInt16(
            event.getIntegerValueField(.keyboardEventKeycode)
        )
        let labels: [UInt16: String] = [
            36: "Return",
            48: "Tab",
            49: "Space",
            51: "Delete",
            53: "Escape",
            76: "Enter",
            96: "F5",
            103: "F11",
            109: "F10",
            115: "Home",
            116: "Page Up",
            117: "Forward Delete",
            119: "End",
            121: "Page Down",
            123: "Left Arrow",
            124: "Right Arrow",
            125: "Down Arrow",
            126: "Up Arrow",
        ]
        let label = labels[keyCode]
            ?? NSEvent(cgEvent: event)?
                .charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
            ?? ""
        return ShortcutKey(keyCode: keyCode, displayName: label)
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var model: ShortcutBridgeAppModel
    @ObservedObject private var settings: ShortcutBridgeSettings
    @ObservedObject private var launchAtLogin: LaunchAtLoginManager
    @StateObject private var capture = ShortcutCaptureModel()
    @State private var combinationFirst = RemoteButton.menu
    @State private var combinationSecond = RemoteButton.up

    init(model: ShortcutBridgeAppModel) {
        self.model = model
        settings = model.settings
        launchAtLogin = model.launchAtLoginManager
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                mappingSection
                Divider()
                combinationSection
                Divider()
                permissionsSection
                Divider()
                applicationSection
            }
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onDisappear {
            capture.cancel()
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            remoteImage

            VStack(alignment: .leading, spacing: 7) {
                Text("遥控快捷桥")
                    .font(.system(size: 26, weight: .semibold))

                HStack(spacing: 7) {
                    Circle()
                        .fill(model.isConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(model.hidStatus)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 16)

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("重新连接 RC003")
        }
        .padding(.bottom, 18)
    }

    @ViewBuilder
    private var remoteImage: some View {
        if
            let url = Bundle.main.url(
                forResource: "RC003-remote-photo",
                withExtension: "png"
            ),
            let image = NSImage(contentsOf: url)
        {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 46, height: 92)
        } else {
            Image(systemName: "appletvremote.gen1")
                .font(.system(size: 42))
                .frame(width: 46, height: 92)
        }
    }

    private var mappingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("按键映射")
                .font(.headline)
                .padding(.vertical, 15)

            ForEach(RemoteButton.allCases) { button in
                VStack(spacing: 0) {
                    mappingRow(button)
                        .padding(.vertical, 8)
                    if button != RemoteButton.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    private func mappingRow(_ button: RemoteButton) -> some View {
        let target = ShortcutCaptureTarget.button(button)
        let isRecording = capture.recordingTarget == target
        let binding = settings.binding(for: button)

        return HStack(spacing: 12) {
            Text(button.shortLabel)
                .font(.system(size: 13, weight: button == .microphone ? .semibold : .regular))
                .frame(width: 64, alignment: .leading)

            Text(isRecording ? capture.preview : binding.displayName)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isRecording ? .accentColor : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            modifierMenu(for: button)

            Button {
                if isRecording {
                    capture.cancel()
                } else {
                    capture.begin(for: target) { chord in
                        model.setBinding(.chord(chord), for: button)
                    }
                }
            } label: {
                Label(
                    isRecording ? "取消" : "重新录制",
                    systemImage: isRecording ? "xmark.circle" : "record.circle"
                )
            }
            .frame(width: 112)

            Button {
                capture.cancel()
                model.setBinding(.disabled, for: button)
            } label: {
                Image(systemName: "trash")
            }
            .help("清除 \(button.displayName) 映射")
            .disabled(binding == .disabled && !isRecording)
        }
        .frame(minHeight: 30)
    }

    private func modifierMenu(for button: RemoteButton) -> some View {
        modifierMenu {
            model.setBinding($0, for: button)
        }
    }

    private func modifierMenu(
        onSelect: @escaping (ShortcutBinding) -> Void
    ) -> some View {
        Menu {
            modifierButton("Control", modifier: .control, onSelect: onSelect)
            modifierButton("Option", modifier: .option, onSelect: onSelect)
            modifierButton("Shift", modifier: .shift, onSelect: onSelect)
            modifierButton("Command", modifier: .command, onSelect: onSelect)
        } label: {
            Image(systemName: "keyboard")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("设为可保持的修饰键")
    }

    private func modifierButton(
        _ title: String,
        modifier: KeyModifier,
        onSelect: @escaping (ShortcutBinding) -> Void
    ) -> some View {
        Button(title) {
            capture.cancel()
            guard let chord = KeyChord(modifiers: [modifier], key: nil) else {
                return
            }
            onSelect(.chord(chord))
        }
    }

    private var combinationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("组合按键")
                    .font(.headline)
                Spacer()
                remoteButtonPicker(
                    selection: $combinationFirst,
                    excluding: combinationSecond
                )
                Text("+")
                    .foregroundColor(.secondary)
                remoteButtonPicker(
                    selection: $combinationSecond,
                    excluding: combinationFirst
                )
                Button {
                    guard let chord = RemoteButtonChord(
                        buttons: [combinationFirst, combinationSecond]
                    ) else {
                        return
                    }
                    model.setCombinationBinding(.disabled, for: chord)
                } label: {
                    Image(systemName: "plus")
                }
                .help("添加遥控器组合按键")
                .disabled(
                    combinationFirst == combinationSecond ||
                        pendingCombinationAlreadyExists
                )
            }
            .padding(.vertical, 15)

            if settings.combinationBindings.isEmpty {
                Text("未设置组合按键")
                    .foregroundColor(.secondary)
                    .padding(.bottom, 12)
            } else {
                ForEach(sortedCombinationChords) { chord in
                    VStack(spacing: 0) {
                        combinationRow(chord)
                            .padding(.vertical, 8)
                        if chord.id != sortedCombinationChords.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func remoteButtonPicker(
        selection: Binding<RemoteButton>,
        excluding excluded: RemoteButton
    ) -> some View {
        Picker("", selection: selection) {
            ForEach(RemoteButton.allCases.filter { $0 != excluded }) { button in
                Text(button.shortLabel).tag(button)
            }
        }
        .labelsHidden()
        .frame(width: 92)
    }

    private func combinationRow(_ chord: RemoteButtonChord) -> some View {
        let target = ShortcutCaptureTarget.combination(chord)
        let isRecording = capture.recordingTarget == target
        let binding = settings.combinationBinding(for: chord) ?? .disabled

        return HStack(spacing: 12) {
            Text(chord.displayName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 120, alignment: .leading)

            Text(isRecording ? capture.preview : binding.displayName)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(isRecording ? .accentColor : .primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            modifierMenu {
                model.setCombinationBinding($0, for: chord)
            }

            Button {
                if isRecording {
                    capture.cancel()
                } else {
                    capture.begin(for: target) { output in
                        model.setCombinationBinding(
                            .chord(output),
                            for: chord
                        )
                    }
                }
            } label: {
                Label(
                    isRecording ? "取消" : "录制输出",
                    systemImage: isRecording
                        ? "xmark.circle"
                        : "record.circle"
                )
            }
            .frame(width: 112)

            Button {
                capture.cancel()
                model.removeCombination(chord)
            } label: {
                Image(systemName: "trash")
            }
            .help("删除 \(chord.displayName) 组合")
        }
        .frame(minHeight: 30)
    }

    private var sortedCombinationChords: [RemoteButtonChord] {
        settings.combinationBindings.keys.sorted { $0.id < $1.id }
    }

    private var pendingCombinationAlreadyExists: Bool {
        guard let chord = RemoteButtonChord(
            buttons: [combinationFirst, combinationSecond]
        ) else {
            return false
        }
        return settings.combinationBindings[chord] != nil
    }

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("系统权限")
                .font(.headline)

            permissionRow(
                title: "输入监控",
                granted: model.inputMonitoringGranted
            ) {
                model.requestInputMonitoringPermission()
            }

            permissionRow(
                title: "辅助功能",
                granted: model.accessibilityGranted
            ) {
                model.requestAccessibilityPermission()
            }
        }
        .padding(.vertical, 16)
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(granted ? .green : .orange)
            Text(title)
            Spacer()
            Text(granted ? "已允许" : "需要允许")
                .foregroundColor(.secondary)
            Button("打开设置", action: action)
                .disabled(granted)
        }
    }

    private var applicationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用")
                .font(.headline)

            Toggle(
                "登录时自动启动",
                isOn: Binding(
                    get: { settings.launchAtLoginEnabled },
                    set: { model.setLaunchAtLoginEnabled($0) }
                )
            )

            HStack {
                Text(launchAtLogin.statusText)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                Spacer()
                if launchAtLogin.requiresApproval {
                    Button("打开登录项设置") {
                        model.openLoginItemsSettings()
                    }
                }
            }

            HStack {
                Button {
                    model.restoreDefaultBindings()
                } label: {
                    Label("恢复默认映射", systemImage: "arrow.uturn.backward")
                }

                Button {
                    model.openLogFolder()
                } label: {
                    Label("显示日志", systemImage: "doc.text.magnifyingglass")
                }

                Spacer()
                Text("版本 \(model.versionText)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 16)
    }
}

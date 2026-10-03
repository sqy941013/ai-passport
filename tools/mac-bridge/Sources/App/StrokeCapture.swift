import AppKit
import FoloVibeCore
import SwiftUI

/// Records whatever key the user presses for a gesture, including a modifier
/// on its own — Right Option and Fn are what several dictation apps listen
/// for, and they never arrive as an ordinary key press.
struct StrokeCaptureSheet: View {
    let title: String
    let onCapture: (KeyStroke) -> Void
    /// Owned, not merely observed. The sheet is a value type: every re-render
    /// by the parent runs this initialiser again, and a draft built here as a
    /// plain stored property would be a fresh object each time. It then read as
    /// a panel that forgot what you just pressed — the key you had recorded
    /// reverted a moment after it appeared, and so did the style, because both
    /// live on the same draft. A StateObject is created once and kept across
    /// those re-renders.
    @StateObject private var draft: StrokeDraft
    @Environment(\.dismiss) private var dismiss

    init(title: String, current: KeyStroke? = nil, onCapture: @escaping (KeyStroke) -> Void) {
        self.title = title
        self.onCapture = onCapture
        // Opening on an existing binding shows it, so changing only how it is
        // sent does not mean recording the key again.
        _draft = StateObject(wrappedValue: StrokeDraft(current))
    }

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.headline)
            Text(draft.stroke == nil ? "按下想要绑定的按键" : "再按一次可以改")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(draft.stroke?.label ?? "…")
                .font(.system(size: 26, weight: .medium))
                .frame(maxWidth: .infinity, minHeight: 68)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            Picker("", selection: $draft.style) {
                ForEach(KeyStroke.Style.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("有的软件要连按两下才唤起，有的要按住不放")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Only a modifier pressed on its own has the choice. An ordinary key
            // is delivered one way and there is nothing to pick.
            if draft.stroke?.isModifierOnly == true {
                HStack {
                    Text("发送方式")
                        .font(.caption)
                    Spacer()
                    Picker("", selection: $draft.delivery) {
                        ForEach(KeyStroke.Delivery.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                Text("有的软件只认状态变化，有的只认按键；都不行就换另一种")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            StrokeRecorder { draft.stroke = $0 }
                .frame(height: 0)

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    if var s = draft.stroke {
                        s.style = draft.style
                        s.delivery = draft.delivery
                        onCapture(s)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft.stroke == nil)
            }
        }
        .padding(22)
        .frame(width: 340)
    }
}

/// Picks what one gesture does.
///
/// This was a `Menu` on the end of each row, with the shortcut presets one
/// submenu deep and the device's own name another level below that — three
/// levels of popover from a row the width of a sentence. On top of that,
/// `Menu` on this macOS version drops everything in its label but the first
/// view, which is why the action name used to disappear from every row.
///
/// A sheet is the honest shape for this: everything on one flat list, the
/// preset groups are headings rather than nested menus, and the row it came
/// from can be laid out as a real row.
struct ActionPickerSheet: View {
    let key: ButtonKey
    let gesture: ButtonGesture
    let current: ButtonAction
    let currentStroke: KeyStroke?
    let currentLabel: String?
    let onPick: (ButtonAction) -> Void
    let onPreset: (KeyPreset) -> Void
    let onRecord: () -> Void
    let onRename: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(key.title) · \(gesture.title)")
                    .font(.headline)
                Text(now)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    section("动作") {
                        row("无", detail: "这一格不发送任何东西", marked: current == .none) {
                            pick(.none)
                        }
                        row("语音输入", detail: "同时开始录音", marked: current == .voice) {
                            pick(.voice)
                        }
                        row("全选并删除", detail: nil, marked: current == .clear) {
                            pick(.clear)
                        }
                        row("交给另一台 Mac", detail: nil, marked: current == .handoff) {
                            pick(.handoff)
                        }
                    }

                    ForEach(KeyPreset.Group.allCases, id: \.self) { group in
                        section(group.rawValue) {
                            ForEach(KeyPreset.grouped(group)) { preset in
                                let markedHere = current == .key
                                    && currentStroke.flatMap { KeyPreset.matching($0)?.id == preset.id } == true
                                row(preset.title, detail: preset.shortcutNote, marked: markedHere) {
                                    onPreset(preset)
                                    dismiss()
                                }
                            }
                        }
                    }

                    section("其他") {
                        row("自定义按键…", detail: "录一段你实际会按的组合键", marked: false) {
                            onRecord()
                            dismiss()
                        }
                        row("改设备屏幕名称…", detail: currentLabel ?? "设备屏幕上显示的名字", marked: false) {
                            onRename()
                            dismiss()
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .frame(height: 380)

            Divider()

            HStack {
                Spacer()
                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .frame(width: 420)
    }

    /// What this binding does right now, in one line.
    private var now: String {
        guard current != .none else { return "未绑定" }
        if let label = currentLabel { return "\(current.title) · 设备上显示「\(label)」" }
        if current.needsStroke, let s = currentStroke { return "\(current.title) · \(s.display)" }
        return current.title
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 3)
            content()
            Divider().padding(.vertical, 6)
        }
    }

    private func row(_ title: String, detail: String?, marked: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout)
                        .foregroundStyle(marked ? Color.accentColor : .primary)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 10)
                if marked {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pick(_ action: ButtonAction) {
        onPick(action)
        dismiss()
    }
}

/// Renames what a gesture prints on the device screen.
///
/// It used to be a text field sitting in every binding row, nine of them, each
/// showing the action's own name as placeholder. That is a name most people
/// never change, and paying a field for it in every row is what made the grid
/// unreadable — so it is now somewhere you go to deliberately.
struct StrokeLabelSheet: View {
    let title: String
    let placeholder: String
    let onSave: (String?) -> Void

    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, placeholder: String, current: String?,
         onSave: @escaping (String?) -> Void) {
        self.title = title
        self.placeholder = placeholder
        self.onSave = onSave
        _text = State(initialValue: current ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text("设备屏幕上显示的名字，留空则用默认名称。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { commit() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(trimmed.isEmpty ? nil : trimmed)
        dismiss()
    }
}

/// Holds what has been pressed so far. A plain @State would be reset by the
/// recorder view rebuilding on every keystroke.
private final class StrokeDraft: ObservableObject {
    @Published var stroke: KeyStroke?
    @Published var style: KeyStroke.Style
    @Published var delivery: KeyStroke.Delivery

    init(_ current: KeyStroke?) {
        stroke = current
        style = current?.style ?? .tap
        delivery = current?.delivery ?? .both
    }
}

private struct StrokeRecorder: NSViewRepresentable {
    let onCapture: (KeyStroke) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onCapture = onCapture
        return v
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onCapture = onCapture
    }
}

final class RecorderView: NSView {
    var onCapture: ((KeyStroke) -> Void)?
    /// The physical modifier keys down at this moment. The flags cannot say
    /// which side a modifier was on, and an app offering "left Option" as its
    /// hotkey can, so the side is kept and replayed with the key.
    private var heldModifiers: [UInt16] = []

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        let mods = UInt64(event.modifierFlags.rawValue) & KeyStroke.modifierMask
        let name = Self.keyName(for: event)
        onCapture?(KeyStroke(
            keyCode: event.keyCode,
            modifiers: mods,
            label: KeyStroke.label(keyCode: event.keyCode, modifiers: mods, keyName: name),
            modifierKeyCodes: heldModifiers))
    }

    /// Pressing a modifier alone arrives here, not in keyDown. Recorded on the
    /// release so holding one down does not fire repeatedly.
    override func flagsChanged(with event: NSEvent) {
        guard KeyStroke.modifierKeyCodes.contains(event.keyCode) else { return }
        let stillDown = UInt64(event.modifierFlags.rawValue) & Self.flagMask(event.keyCode) != 0
        heldModifiers.removeAll { $0 == event.keyCode }
        if stillDown {
            heldModifiers.append(event.keyCode)
            return
        }
        let name = Self.modifierNames[event.keyCode] ?? "修饰键"
        onCapture?(KeyStroke(keyCode: event.keyCode, modifiers: 0, label: name))
    }

    private static func flagMask(_ keyCode: UInt16) -> UInt64 {
        switch keyCode {
        case 0x37, 0x36: return UInt64(NSEvent.ModifierFlags.command.rawValue)
        case 0x38, 0x3C: return UInt64(NSEvent.ModifierFlags.shift.rawValue)
        case 0x3A, 0x3D: return UInt64(NSEvent.ModifierFlags.option.rawValue)
        case 0x3B, 0x3E: return UInt64(NSEvent.ModifierFlags.control.rawValue)
        case 0x3F: return UInt64(NSEvent.ModifierFlags.function.rawValue)
        default: return 0
        }
    }

    private static let modifierNames: [UInt16: String] = [
        0x37: "⌘ 左", 0x36: "⌘ 右",
        0x38: "⇧ 左", 0x3C: "⇧ 右",
        0x3A: "⌥ 左", 0x3D: "⌥ 右",
        0x3B: "⌃ 左", 0x3E: "⌃ 右",
        0x3F: "Fn",
    ]

    /// Prefers the unmodified character so ⌘C reads as "C" rather than the
    /// control character the modifier produces.
    private static func keyName(for event: NSEvent) -> String {
        if let special = specialNames[event.keyCode] { return special }
        let raw = event.charactersIgnoringModifiers ?? ""
        return raw.isEmpty ? "键\(event.keyCode)" : raw.uppercased()
    }

    private static let specialNames: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "空格", 51: "⌫", 53: "esc",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17",
        0x4F: "F18", 0x50: "F19",
    ]
}

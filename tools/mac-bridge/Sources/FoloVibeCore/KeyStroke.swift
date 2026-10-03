import Foundation

/// An arbitrary keyboard shortcut: a virtual key plus its modifiers. Lets a
/// gesture drive anything the Mac can receive, not just the actions this app
/// knows about.
public struct KeyStroke: Codable, Equatable, Hashable {
    public var keyCode: UInt16
    /// Raw CGEventFlags, masked to the four modifiers a user can press.
    public var modifiers: UInt64
    /// What to show in the UI and on the device, e.g. "⌘C".
    public var label: String
    /// How the key is delivered. Which one an application wants is not
    /// something this app can detect: some dictation tools start on a double
    /// press, others on a held key.
    public enum Style: String, Codable, CaseIterable, Equatable {
        case tap
        case double
        case hold

        public var title: String {
            switch self {
            case .tap: return "按一下"
            case .double: return "连按两下"
            case .hold: return "按住不放"
            }
        }
    }

    public var style: Style
    /// Volume, play/pause and the like are not ordinary keys; they travel as
    /// system media events and need their own posting path.
    public var isMedia: Bool

    /// How the modifiers in a shortcut are delivered.
    ///
    /// There are two ways to send Option+Space and only one of them is the
    /// shortcut most apps expect. Normally the modifier is a flag carried
    /// along on the key event, which is cheap and is all an app needs if it
    /// reads that flag. Some apps instead watch for the modifier going down
    /// and wait for the key afterwards; to those, a shortcut whose modifier
    /// was never pressed does not exist. Nothing here can tell which an app
    /// wants, so the choice is the user's and defaults to covering both.
    public enum Delivery: String, Codable, CaseIterable, Equatable {
        case state
        case keystroke
        case both

        public var title: String {
            switch self {
            case .state: return "先按修饰键"
            case .keystroke: return "修饰键只做标记"
            case .both: return "两种都发"
            }
        }

        /// Whether the modifier keys are pressed and released around the key.
        public var sendsState: Bool { self != .keystroke }
        /// Whether the key event carries the modifiers as flags.
        public var sendsInline: Bool { self != .state }
    }

    public var delivery: Delivery

    /// The physical modifier keys held when this stroke was recorded.
    ///
    /// The flags cannot say which side a modifier was on: left and right
    /// Option raise the same bit. An app that offers "left Option" as its
    /// hotkey can tell them apart, so the recorded key codes travel with the
    /// stroke and the press comes back as the same one.
    public var modifierKeyCodes: [UInt16]

    public init(keyCode: UInt16, modifiers: UInt64, label: String,
                style: Style = .tap, isMedia: Bool = false,
                delivery: Delivery = .both, modifierKeyCodes: [UInt16] = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.label = label
        self.style = style
        self.isMedia = isMedia
        self.delivery = delivery
        self.modifierKeyCodes = modifierKeyCodes
    }

    /// The modifier keys a press has to raise for this stroke.
    ///
    /// A stroke that is nothing but a modifier raises its own key. A stroke
    /// that combines modifiers with a real key raises whichever were held when
    /// it was recorded, or the left-hand key for each modifier the flags name
    /// when nothing was recorded.
    public var modifierKeys: [UInt16] {
        if isModifierOnly { return [keyCode] }
        if !modifierKeyCodes.isEmpty { return modifierKeyCodes }
        var keys: [UInt16] = []
        if modifiers & KeyStroke.command != 0 { keys.append(0x37) }
        if modifiers & KeyStroke.shift != 0 { keys.append(0x38) }
        if modifiers & KeyStroke.option != 0 { keys.append(0x3A) }
        if modifiers & KeyStroke.control != 0 { keys.append(0x3B) }
        return keys
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, modifiers, label, style, isMedia, taps, delivery, modifierKeyCodes
    }

    /// Strokes written before styles existed were single or double presses.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        modifiers = try c.decode(UInt64.self, forKey: .modifiers)
        label = try c.decode(String.self, forKey: .label)
        isMedia = try c.decodeIfPresent(Bool.self, forKey: .isMedia) ?? false
        delivery = try c.decodeIfPresent(Delivery.self, forKey: .delivery) ?? .both
        modifierKeyCodes = try c.decodeIfPresent([UInt16].self, forKey: .modifierKeyCodes) ?? []
        if let s = try c.decodeIfPresent(Style.self, forKey: .style) {
            style = s
        } else {
            style = (try c.decodeIfPresent(Int.self, forKey: .taps) ?? 1) > 1 ? .double : .tap
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(modifiers, forKey: .modifiers)
        try c.encode(label, forKey: .label)
        try c.encode(style, forKey: .style)
        try c.encode(isMedia, forKey: .isMedia)
        try c.encode(delivery, forKey: .delivery)
        try c.encode(modifierKeyCodes, forKey: .modifierKeyCodes)
    }

    /// Return on its own, the key that sends a message. Option+Return breaks a
    /// line instead, so it does not count.
    public var isReturn: Bool { !isMedia && keyCode == 0x24 && modifiers == 0 }

    /// True when the shortcut is a modifier key by itself, like Right Option.
    /// Those have to be held and released rather than typed.
    public var isModifierOnly: Bool { Self.modifierKeyCodes.contains(keyCode) }

    /// Enough for a listener to time the press, and still short enough to
    /// feel like a tap.
    public static let modifierTapMilliseconds: UInt32 = 90
    public static let doublePressHoldMilliseconds: UInt32 = 45
    public static let doublePressGapMilliseconds: UInt32 = 140
    public static let holdMillisecondsHeld: UInt32 = 800

    /// How long the key stays down, in milliseconds.
    ///
    /// An ordinary key can be pressed and released in the same instant, which
    /// is what a tap is. A modifier pressed on its own cannot: it goes out as
    /// a change of modifier state, and dictation apps that watch Fn or Option
    /// time the press rather than merely note it. Posted back to back with no
    /// gap, the event is dropped before it reaches them and the keystroke
    /// leaves the machine having done nothing. So a lone modifier always keeps
    /// a floor, while everything else is left exactly as it was.
    public var holdMilliseconds: UInt32 {
        switch style {
        case .tap: return isModifierOnly ? Self.modifierTapMilliseconds : 0
        case .double: return Self.doublePressHoldMilliseconds
        case .hold: return Self.holdMillisecondsHeld
        }
    }

    /// Whether the two presses of a double press read as two. A gap that is
    /// not comfortably longer than the press itself collapses into one.
    public static var doublePressIsDistinct: Bool {
        doublePressGapMilliseconds > doublePressHoldMilliseconds
    }

    /// Virtual key codes of the keys that only ever act as modifiers.
    public static let modifierKeyCodes: Set<UInt16> = [
        0x37, 0x36,  // command, right command
        0x38, 0x3C,  // shift, right shift
        0x3A, 0x3D,  // option, right option
        0x3B, 0x3E,  // control, right control
        0x3F,        // fn
    ]

    /// Label plus how it is sent, for a list where both matter.
    public var display: String {
        switch style {
        case .tap: return label
        case .double: return "\(label) ×2"
        case .hold: return "\(label) 按住"
        }
    }

    /// Only these four are worth carrying; the rest of CGEventFlags describes
    /// event state rather than something a person held down.
    public static let command: UInt64 = 1 << 20
    public static let shift: UInt64 = 1 << 17
    public static let option: UInt64 = 1 << 19
    public static let control: UInt64 = 1 << 18
    public static let modifierMask: UInt64 = command | shift | option | control

    /// Builds the conventional symbol order: ⌃⌥⇧⌘ then the key.
    public static func label(keyCode: UInt16, modifiers: UInt64, keyName: String) -> String {
        var s = ""
        if modifiers & control != 0 { s += "⌃" }
        if modifiers & option != 0 { s += "⌥" }
        if modifiers & shift != 0 { s += "⇧" }
        if modifiers & command != 0 { s += "⌘" }
        return s + keyName
    }
}

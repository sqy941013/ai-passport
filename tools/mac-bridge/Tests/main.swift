import FoloVibeCore
import Foundation

var failed = 0

func expect(_ cond: Bool, _ name: String) {
    if cond {
        print("OK  \(name)")
    } else {
        print("FAIL \(name)")
        failed += 1
    }
}

do {
    let pcm = IMAADPCM.decode(Data([0x04, 0x0C]), predictor: 0, stepIndex: 0)
    expect(Array(pcm.prefix(3)) == [7, 8, -1], "ADPCM reference vector")
    expect(IMAADPCM.peak([12, -40, 7]) == 40, "ADPCM peak")
}

do {
    var bytes = [UInt8](repeating: 0, count: 166)
    bytes[0] = 0x34
    bytes[1] = 0x12
    bytes[2] = 0xFE
    bytes[3] = 0xFF
    bytes[4] = 7
    bytes[6] = 0xA5
    let pkt = AudioPacket.parse(Data(bytes))
    expect(pkt?.seq == 0x1234, "packet seq")
    expect(pkt?.predictor == -2, "packet predictor")
    expect(pkt?.eos == false, "packet not eos")
    expect(AudioPacket.parse(Data([9, 0, 0, 0, 0, 1]))?.eos == true, "eos packet")
    expect(AudioPacket.parse(Data([1, 2, 3, 4, 5])) == nil, "reject short")
}

do {
    expect(BridgeSettings.default.powerMode == .standard, "default standard power mode")
    // codes must stay consecutive.
    expect(VibeProtocol.powerModeEco == VibeProtocol.powerModeStandard + 1, "eco follows standard")
    expect(VibeProtocol.powerModeUltra == VibeProtocol.powerModeStandard + 2, "ultra follows eco")
    expect(BridgePowerMode.allCases.count == 3, "three power modes")
    expect(BridgePowerMode.ultra.title == "超级省电", "ultra title")
}

do {
    // A setup written when the app knew about particular input methods keeps
    // working: the keys that lived in settings move onto the gestures that
    // were sending them, double press and all. Without this an upgrade would
    // leave every button silent until each one was recorded again.
    let legacy = Data(#"""
    {"talkKey":"F13","doubaoKey":"Right Option","talkTap":"single","doubaoTap":"double",
     "buttons":{"bindings":{"0.0":"doubao","2.0":"typelessDictate","1.0":"enter"}}}
    """#.utf8)
    let old = try? JSONDecoder().decode(BridgeSettings.self, from: legacy)
    expect(old?.buttons.action(.up, .click) == .voice, "Doubao binding becomes voice input")
    expect(old?.buttons.stroke(.up, .click)?.keyCode == 0x3D, "and keeps Right Option")
    expect(old?.buttons.stroke(.up, .click)?.style == .double, "and its double press")
    expect(old?.buttons.stroke(.down, .click)?.keyCode == 0x69, "dictation keeps F13")
    expect(old?.buttons.stroke(.down, .click)?.style == .tap, "as a single press")
    // Return used to be an action of its own; it is the same key, now carried
    // by the gesture, so the binding keeps working without being re-made.
    expect(old?.buttons.action(.mid, .click) == .key, "Return becomes a sent key")
    expect(old?.buttons.stroke(.mid, .click)?.keyCode == 0x24, "carrying Return itself")
    expect(old?.buttons.label(.mid, .click) == "发送", "and naming the key on screen")

    // The retired keys are read once and never written back.
    let saved = try? JSONEncoder().encode(old ?? .default)
    let text = String(decoding: saved ?? Data(), as: UTF8.self)
    expect(!text.contains("talkKey") && !text.contains("doubaoTap"),
        "retired settings are not written again")
}

do {
    // Cue volume defaults to the loudness the cues always had, and an older
    // settings file without it lands there too rather than on silence.
    expect(BridgeSettings.default.cueVolume == 2, "cue volume defaults to medium")
    let older = try? JSONDecoder().decode(BridgeSettings.self, from: Data("{}".utf8))
    expect(older?.cueVolume == 2, "missing volume reads as medium, not silent")
    expect(VibeProtocol.volumeLevels.count == 5, "five volume levels, matching the firmware")
}

do {
    // Only a bare Return earns the "sent" sound: Option+Return breaks a line.
    expect(KeyPreset.find("return")?.stroke.isReturn == true, "Return is a send")
    expect(KeyPreset.find("newline")?.stroke.isReturn == false, "Option+Return is not")
    expect(KeyPreset.find("copy")?.stroke.isReturn == false, "nor is anything else")
}

do {
    // A key with no name of its own is still named on the device: the preset
    // it matches, else the key itself, never a bare "custom".
    var map = ButtonMap()
    map.set(.mid, .click, .key)
    map.setStroke(.mid, .click, KeyStroke(keyCode: 0x24, modifiers: 0, label: "↩"))
    expect(map.screenName(.mid, .click) == "发送", "Return is named after its preset")
    map.setStroke(.mid, .click, KeyStroke(keyCode: 0x23, modifiers: KeyStroke.command | KeyStroke.shift, label: "⇧⌘P"))
    expect(map.screenName(.mid, .click) == "⇧⌘P", "an unknown key is named by itself")
    map.setLabel(.mid, .click, "命令")
    expect(map.screenName(.mid, .click) == "命令", "the user's own name wins")
    expect(ButtonMap().screenName(.up, .click) == nil, "nothing bound, nothing named")
}

do {
    // Presets are just named strokes, so picking one fills the same field the
    // recorder would — and names the key on the device at the same time.
    var map = ButtonMap()
    map.bind(.up, .double, preset: "copy")
    expect(map.action(.up, .double) == .key, "a preset is a sent key")
    expect(map.stroke(.up, .double)?.modifiers == KeyStroke.command, "copy carries Command")
    expect(map.label(.up, .double) == "复制", "and labels the key on the device")
    expect(KeyPreset.find("playPause")?.stroke.isMedia == true,
        "media keys are marked, since they do not travel as key events")
    expect(KeyPreset.all.count == Set(KeyPreset.all.map(\.id)).count, "preset ids are unique")
    expect(KeyPreset.Group.allCases.allSatisfy { !KeyPreset.grouped($0).isEmpty },
        "every group has something in it")

    // How a key is sent survives a save, and an older stroke reads as a tap.
    var s = KeyStroke(keyCode: 8, modifiers: 0, label: "C", style: .hold)
    let round = try? JSONDecoder().decode(KeyStroke.self, from: JSONEncoder().encode(s))
    expect(round?.style == .hold, "hold survives a round trip")
    let older = Data(#"{"keyCode":8,"modifiers":0,"label":"C","taps":2}"#.utf8)
    expect((try? JSONDecoder().decode(KeyStroke.self, from: older))?.style == .double,
        "a stroke written before styles reads as a double press")
    s.style = .tap
    expect(s.display == "C" , "a plain tap shows just the key")
}

do {
    // A screen label is trimmed, and blank means "use the built-in name".
    var map = ButtonMap.default
    map.setLabel(.up, .click, "  讯飞 ")
    expect(map.label(.up, .click) == "讯飞", "label is trimmed")
    map.setLabel(.up, .click, "   ")
    expect(map.label(.up, .click) == nil, "blank label falls back to the default")
    map.setLabel(.down, .long, "问问")
    let round = try? JSONDecoder().decode(ButtonMap.self, from: JSONEncoder().encode(map))
    expect(round?.label(.down, .long) == "问问", "label round trips")
    // Wire slots follow the firmware's gesture index: button * 3 + gesture.
    expect(ButtonMap.wireSlot(.mid, .double) == 4, "wire slot matches firmware")
    // Configurations written before labels existed still decode.
    let legacy = Data(#"{"bindings":{"0.0":"doubao"}}"#.utf8)
    let old = try? JSONDecoder().decode(ButtonMap.self, from: legacy)
    expect(old?.action(.up, .click) == .voice && old?.label(.up, .click) == nil,
           "legacy button map has no labels")
}

do {
    // Handing a device to another Mac never arms the microphone, and its wire
    // code must not collide with anything the firmware already knows.
    expect(ButtonAction.handoff.code == 10, "handoff wire code")
    expect(!ButtonAction.handoff.isRecording, "handoff does not record")
    expect(Set(ButtonAction.allCases.map(\.code)).count == ButtonAction.allCases.count,
           "every action has its own wire code")
}

do {
    expect(ButtonAction.key.code == 9, "send-key wire code")
    expect(!ButtonAction.key.isRecording, "sending a key does not record")
    expect(KeyStroke.label(keyCode: 8, modifiers: KeyStroke.command, keyName: "C") == "⌘C",
        "label puts the symbol before the key")
    expect(KeyStroke.label(keyCode: 8,
        modifiers: KeyStroke.command | KeyStroke.shift | KeyStroke.option | KeyStroke.control,
        keyName: "C") == "⌃⌥⇧⌘C", "modifiers use the conventional order")

    var map = ButtonMap.default
    map.set(.down, .double, .key)
    map.setStroke(.down, .double, KeyStroke(keyCode: 8, modifiers: KeyStroke.command, label: "⌘C"))
    expect(map.stroke(.down, .double)?.label == "⌘C", "stroke stored per slot")
    expect(map.stroke(.up, .click) == nil, "other slots keep no stroke")

    // Configurations written before custom keys existed must still decode.
    let legacy = Data("""
    {"bindings":{"1.0":"enter"}}
    """.utf8)
    let decoded = try? JSONDecoder().decode(ButtonMap.self, from: legacy)
    expect(decoded?.action(.mid, .click) == .key, "legacy config still decodes")
    expect(decoded?.stroke(.mid, .click)?.keyCode == 0x24, "and gains the key it used to mean")

    let round = try? JSONDecoder().decode(
        ButtonMap.self, from: JSONEncoder().encode(map))
    expect(round?.stroke(.down, .double)?.keyCode == 8, "stroke round trips")
}

do {
    let h = VibeProtocol.otaHeader(length: 1216672)
    expect(h.count == 6, "OTA header is six bytes")
    expect(h[0] == 0x46 && h[1] == 0x57, "OTA header magic")
    let len = UInt32(h[2]) | (UInt32(h[3]) << 8) | (UInt32(h[4]) << 16) | (UInt32(h[5]) << 24)
    expect(len == 1216672, "OTA header carries the length little-endian")
}

do {
    let line = LogLine.parse("01:02:03.456 [蓝牙] 已连接 FoloVibe-4C11")
    expect(line.time == "01:02:03.456", "log time")
    expect(line.category == "蓝牙", "log category")
    expect(line.message == "已连接 FoloVibe-4C11", "log message")
    expect(LogLine.parse("裸行没有分类").category.isEmpty, "bare log line")
}

do {
    // A modifier pressed on its own is posted as a modifier-state change, and
    // a dictation app listening on Fn or Option times the press rather than
    // merely noting it. Released in the same instant it went down, the event
    // never reached them — the tap left the machine and did nothing. A lone
    // modifier therefore keeps a floor that an ordinary key does not need.
    let optionTap = KeyStroke(keyCode: 0x3A, modifiers: 0, label: "⌥ 左", style: .tap)
    expect(optionTap.isModifierOnly, "option on its own is a modifier")
    expect(
        optionTap.holdMilliseconds >= 50,
        "a tapped modifier is held long enough for a listener to time it")
    expect(
        optionTap.holdMilliseconds <= 200,
        "a tapped modifier is still short enough to feel like a tap")

    let fnTap = KeyStroke(keyCode: 0x3F, modifiers: 0, label: "fn", style: .tap)
    expect(fnTap.holdMilliseconds == optionTap.holdMilliseconds, "every lone modifier gets the same floor")

    // Nothing else moves. ⌘C and ⌥↩ already reach their apps with no hold,
    // and padding every shortcut would change working bindings for no reason.
    let copy = KeyStroke(keyCode: 0x08, modifiers: KeyStroke.command, label: "⌘C", style: .tap)
    expect(!copy.isModifierOnly, "⌘C is not a lone modifier")
    expect(copy.holdMilliseconds == 0, "an ordinary tap is not padded")
    let newline = KeyStroke(keyCode: 0x24, modifiers: KeyStroke.option, label: "⌥↩", style: .tap)
    expect(newline.holdMilliseconds == 0, "option as a prefix is not padded")
    let f13 = KeyStroke(keyCode: 0x69, modifiers: 0, label: "F13", style: .tap)
    expect(f13.holdMilliseconds == 0, "a function key tap is not padded")

    // The other two styles keep the timings their comments describe.
    expect(optionTap.style == .tap, "tap style is a single press")
    let optionHold = KeyStroke(keyCode: 0x3A, modifiers: 0, label: "⌥ 左", style: .hold)
    expect(optionHold.holdMilliseconds >= 500, "a held modifier is held long enough to read as deliberate")
    expect(optionHold.holdMilliseconds > optionTap.holdMilliseconds, "hold outlasts tap")
    let optionDouble = KeyStroke(keyCode: 0x3A, modifiers: 0, label: "⌥ 左", style: .double)
    expect(optionDouble.holdMilliseconds > 0, "a double press presses")
    expect(KeyStroke.doublePressIsDistinct, "the gap between two presses outlasts a press")

    // Media keys keep their own path, but the timing still comes from here.
    let volume = KeyStroke(keyCode: 0x48, modifiers: 0, label: "🔊", style: .tap, isMedia: true)
    expect(volume.isMedia && !volume.isModifierOnly, "volume is media, not a modifier")
    expect(volume.holdMilliseconds == 0, "a media tap is not padded")
}

do {
    // A modifier that only rides along on a key event was never pressed. An
    // app that watches for the modifier going down and waits for the key
    // afterwards never sees that shortcut at all, which is how a dictation app
    // could ignore an Option+Space the log said it sent. So the modifiers are
    // raised as their own state changes too, and every mode sends at least
    // one half rather than nothing.
    expect(KeyStroke.Delivery.allCases.count == 3, "three delivery modes")
    expect(KeyStroke.Delivery.both.sendsState && KeyStroke.Delivery.both.sendsInline,
        "both sends both halves")
    expect(KeyStroke.Delivery.state.sendsState, "state presses the modifiers")
    expect(!KeyStroke.Delivery.state.sendsInline, "state sends no flag-bearing key")
    expect(KeyStroke.Delivery.keystroke.sendsInline, "keystroke sends the flag-bearing key")
    expect(!KeyStroke.Delivery.keystroke.sendsState, "keystroke presses nothing")
    for d in KeyStroke.Delivery.allCases {
        expect(d.sendsState || d.sendsInline, "\(d.rawValue) sends something")
    }

    // The side of a modifier has to survive, because the flags cannot carry it
    // and an app asking for "left Option" can tell.
    let optionSpace = KeyStroke(keyCode: 0x31, modifiers: KeyStroke.option, label: "⌥空格",
                                modifierKeyCodes: [0x3A])
    expect(optionSpace.modifierKeys == [0x3A], "recorded left option is replayed as left")
    let rightOptionSpace = KeyStroke(keyCode: 0x31, modifiers: KeyStroke.option, label: "⌥空格",
                                     modifierKeyCodes: [0x3D])
    expect(rightOptionSpace.modifierKeys == [0x3D], "recorded right option stays right")
    expect(optionSpace.modifierKeys != rightOptionSpace.modifierKeys,
        "left and right are not the same key")

    // A shortcut recorded before the side was kept still names its modifiers,
    // assuming the left, rather than sending none.
    let noSides = KeyStroke(keyCode: 0x31, modifiers: KeyStroke.option, label: "⌥空格")
    expect(noSides.modifierKeys == [0x3A], "an unrecorded side falls back to left")
    let cmdShift = KeyStroke(keyCode: 0x08, modifiers: KeyStroke.command | KeyStroke.shift,
                             label: "⌘⇧C")
    expect(cmdShift.modifierKeys == [0x37, 0x38], "each named modifier is raised")
    let bare = KeyStroke(keyCode: 0x08, modifiers: 0, label: "C")
    expect(bare.modifierKeys.isEmpty, "a key with no modifier raises none")

    // A lone modifier raises its own key, and nothing else.
    let option = KeyStroke(keyCode: 0x3A, modifiers: 0, label: "⌥ 左", style: .tap)
    expect(option.modifierKeys == [0x3A], "a lone modifier raises itself")
    expect(option.holdMilliseconds >= 50, "and is still held long enough to be timed")

    // A binding saved before this choice existed has to keep working.
    let legacy = Data(#"{"keyCode":49,"modifiers":0,"label":"⌥空格","style":"tap"}"#.utf8)
    let old = try? JSONDecoder().decode(KeyStroke.self, from: legacy)
    expect(old?.delivery == .both, "a binding without delivery covers both")
    expect(old?.modifierKeyCodes.isEmpty == true, "and without recorded sides")

    let stored = KeyStroke(keyCode: 0x31, modifiers: KeyStroke.option, label: "⌥空格",
                           style: .hold, delivery: .state, modifierKeyCodes: [0x3A])
    let back = try? JSONDecoder().decode(KeyStroke.self, from: JSONEncoder().encode(stored))
    expect(back == stored, "delivery and sides round trip")
    expect(back?.modifierKeys == [0x3A], "and the side survives the round trip")
}

if failed == 0 {
    print("ALL PASSED")
    exit(0)
}
print("\(failed) FAILED")
exit(1)

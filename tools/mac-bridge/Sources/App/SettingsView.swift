import FoloVibeCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SettingsStore
    @ObservedObject var updater: Updater
    @ObservedObject var installer: VirtualMicInstaller

    let page: AppTab

    init(model: AppModel, page: AppTab) {
        self.model = model
        self.page = page
        self.store = model.settings
        self.updater = model.updater
        self.installer = model.micInstaller
    }

    var body: some View {
        Group {
            switch page {
            case .keys: keysPage
            case .devices: devicesPage
            case .general: generalPage
            }
        }
        .sheet(item: $model.actionTarget) { slot in
            let action = store.current.buttons.action(slot.key, slot.gesture)
            ActionPickerSheet(
                key: slot.key,
                gesture: slot.gesture,
                current: action,
                currentStroke: store.current.buttons.stroke(slot.key, slot.gesture),
                currentLabel: store.current.buttons.label(slot.key, slot.gesture),
                onPick: { bind(slot.key, slot.gesture, $0) },
                onPreset: { store.current.buttons.bind(slot.key, slot.gesture, preset: $0.id) },
                onRecord: { afterSheetDismiss { openRecorder(slot) } },
                onRename: { afterSheetDismiss { model.labelTarget = slot } })
        }
        .sheet(item: $model.strokeTarget) { slot in
            StrokeCaptureSheet(
                title: slot.title,
                current: store.current.buttons.stroke(slot.key, slot.gesture)
            ) { stroke in
                store.current.buttons.setStroke(slot.key, slot.gesture, stroke)
            }
        }
        .sheet(item: $model.labelTarget) { slot in
            let action = store.current.buttons.action(slot.key, slot.gesture)
            StrokeLabelSheet(
                title: "设备屏幕名称 · \(slot.title)",
                placeholder: placeholder(slot.key, slot.gesture, action),
                current: store.current.buttons.label(slot.key, slot.gesture)
            ) { label in
                store.current.buttons.setLabel(slot.key, slot.gesture, label)
            }
        }
    }

    /// The three buttons, each with its three gestures. The setup guide only
    /// appears here while something still needs doing.
    private var keysPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !model.setupComplete { SetupGuideView(model: model) }

                SurfaceCard("按键绑定", subtitle: "点任意一行，改这一格的动作、快捷键和设备上显示的名字") {
                    VStack(spacing: 14) {
                        ForEach(Array(ButtonKey.allCases.enumerated()), id: \.element) { index, key in
                            if index > 0 { Divider() }
                            keyGroup(key)
                        }
                    }
                }

                HStack {
                    Spacer()
                    Button("恢复默认按键") { store.current.buttons = .default }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            .padding(12)
        }
    }

    /// One physical button and its three gestures, kept together because that
    /// is how they are used: you press a button, then choose how.
    ///
    /// These used to be a 3x3 matrix, one button per row and one gesture per
    /// column. It was compact but unreadable — each cell was about a hundred
    /// points wide, so the action name, the one thing you actually scan for,
    /// had to be set in caption2 and scaled down further to fit. Three
    /// gestures across a row of a three-column window leaves no room to write
    /// anything down. A row per binding has the whole width, so nothing needs
    /// shrinking.
    private func keyGroup(_ key: ButtonKey) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(key.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            ForEach(ButtonGesture.allCases, id: \.self) { gesture in
                bindingRow(key, gesture)
            }
        }
    }

    /// One binding on one line: what the gesture does is the headline, the
    /// shortcut it sends sits at the far right as a reference, and a name set
    /// for the device's own screen goes underneath. Clicking the row opens the
    /// sheet that changes all three.
    private func bindingRow(_ key: ButtonKey, _ gesture: ButtonGesture) -> some View {
        let action = store.current.buttons.action(key, gesture)
        let fired = model.firedSlot == GestureSlot(key: key, gesture: gesture)
        let custom = store.current.buttons.label(key, gesture)
        let stroke = store.current.buttons.stroke(key, gesture)

        return Button {
            model.actionTarget = GestureSlot(key: key, gesture: gesture)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(gesture.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(menuTitle(key, gesture))
                        .font(.callout.weight(fired ? .semibold : .regular))
                        .foregroundStyle(action == .none ? .secondary : .primary)
                        .lineLimit(1)
                    if let custom {
                        Text("设备上显示「\(custom)」")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                keyCap(action, stroke: stroke)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                fired ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        fired ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.07),
                        lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(key.title) · \(gesture.title)：\(menuTitle(key, gesture))")
        .animation(.easeOut(duration: 0.25), value: model.firedSlot)
    }

    /// The shortcut at the far right of a row, for reference.
    ///
    /// A binding that sends no key shows a dash, because there is nothing to
    /// show. A binding that needs one but has none says so instead: the dash
    /// would look the same, and the difference between "this does not send a
    /// key" and "this sends a key you have not recorded yet" is the difference
    /// between a working button and one that does nothing when pressed.
    private func keyCap(_ action: ButtonAction, stroke: KeyStroke?) -> some View {
        Group {
            if let s = stroke, action.needsStroke {
                Text(s.display)
                    .foregroundStyle(.secondary)
            } else if action.needsStroke {
                Text("未设置快捷键")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
        .font(.system(.callout, design: .monospaced).weight(.medium))
        .lineLimit(1)
    }

    private var devicesPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SurfaceCard("连接设备", subtitle: "空闲的自动连上；别的 Mac 在用的，点「使用」切过来") {
                    VStack(spacing: 15) {
                        deviceList
                        Divider()
                        SettingRow("音频输出", subtitle: "语音软件也选它") {
                            HStack(spacing: 8) {
                                Picker("输出设备", selection: outputBinding) {
                                    ForEach(audioDeviceOptions, id: \.self) { Text($0).tag($0) }
                                }
                                .labelsHidden()
                                .frame(width: 170)
                                Button { model.refreshChecks() } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .help("刷新音频设备列表")
                            }
                        }
                        virtualMicHelp
                    }
                }

                SurfaceCard("提示音", subtitle: "开机、连接、说话、发送、断开、休眠时设备发出的声音") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: volumeBinding) {
                            ForEach(0..<VibeProtocol.volumeLevels.count, id: \.self) { level in
                                Text(VibeProtocol.volumeLevels[level]).tag(level)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        HStack {
                            Text("改完会用新音量响一声")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("试听") {
                                model.ble.setVolume(store.current.cueVolume, preview: true)
                            }
                            .disabled(store.current.cueVolume == 0 || !model.bleSnap.subscribed)
                        }
                    }
                }

                SurfaceCard("设备功耗模式", subtitle: "根据你是否长时间闲置，切换设备的耗电策略") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("", selection: powerModeBinding) {
                            ForEach(BridgePowerMode.allCases, id: \.self) { mode in
                                Label(mode.title, systemImage: mode.symbol).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(store.current.powerMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SurfaceCard("设备固件", subtitle: "程序先升级，再用它把配套固件推给设备") {
                    VStack(alignment: .leading, spacing: 10) {
                        // Firmware follows the app: upgrade the Mac side first,
                        // then let it push the matching image to the device.
                        HStack(spacing: 10) {
                            Text(firmwareSummary)
                                .font(.callout.weight(.medium))
                            Spacer()
                            if model.otaRunning {
                                ProgressView(value: model.otaProgress).frame(width: 120)
                                Text("\(Int(model.otaProgress * 100))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            } else if model.firmwareUpdateAvailable {
                                Button { model.upgradeFirmware() } label: {
                                    Label("升级固件", systemImage: "cpu")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!model.bleSnap.subscribed)
                            }
                        }
                        if !model.otaNote.isEmpty {
                            Text(model.otaNote)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if model.firmwareUpdateAvailable && !model.bleSnap.subscribed {
                            Text("设备未连接，连上后才能升级固件")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
                SurfaceCard("高级", subtitle: "一般不用动；排查连接或音频问题时再看") {
                    DisclosureGroup("展开") {
                        VStack(alignment: .leading, spacing: 8) {
                            SettingRow("设备名前缀", subtitle: "填完整名字可只连某一台") {
                                TextField("FoloVibe", text: prefixBinding)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                            }
                            Toggle("设备断开后自动重连", isOn: autoReconnect)
                            Divider()
                            InfoRow(label: "音频包", value: "\(model.bleSnap.packets)")
                            InfoRow(label: "丢包", value: "\(model.bleSnap.lost)")
                            InfoRow(label: "MTU", value: "\(model.bleSnap.mtu)")
                            InfoRow(label: "最近一包", value: model.bleSnap.lastPacketHex.isEmpty ? "—" : model.bleSnap.lastPacketHex)
                            HStack(spacing: 10) {
                                Button("播放测试音") { model.playAudioTest() }
                                Button(model.mic.isArmed ? "取消录音测试" : "录一段回放") { model.toggleMicTest() }
                                Button("重新连接") { model.ble.reconnect() }
                            }
                            Text(model.audioTestNote).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }
                    .font(.callout)
                }
            }
            .padding(12)
        }
    }

    private var generalPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SurfaceCard("程序更新", subtitle: "从 GitHub 获取最新版本") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            Text("当前版本 \(model.updater.currentVersion)")
                                .font(.callout.weight(.medium))
                            Spacer()
                            Button { model.updater.check() } label: {
                                Label("检查更新", systemImage: "arrow.clockwise")
                            }
                            .disabled(model.updater.busy)
                            if model.updater.updateAvailable {
                                Button { model.updater.installUpdate() } label: {
                                    Label("升级并重启", systemImage: "arrow.down.circle.fill")
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(model.updater.busy)
                            }
                        }
                        if !model.updater.status.hasPrefix("已是最新") {
                            Text(model.updater.status)
                                .font(.caption)
                                .foregroundStyle(model.updater.updateAvailable ? .orange : .secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                SurfaceCard("启动与权限", subtitle: "这些选项只影响本程序") {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: loginBinding) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("开机启动").font(.callout.weight(.medium))
                                Text("登录 macOS 后自动启动 Bridge").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Toggle(isOn: hidden) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("启动后只留菜单栏").font(.callout.weight(.medium))
                                Text("适合日常使用，仍可从菜单栏重新打开窗口").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        HStack(spacing: 10) {
                            Button("打开辅助功能") { Permissions.openAccessibility(); KeyTap.promptTrust() }
                            Button("打开蓝牙设置") { Permissions.openBluetooth() }
                            Button("再次检查") { model.refreshChecks() }
                        }
                    }
                }

                SurfaceCard("运行日志", subtitle: "出问题时看这里") {
                    DisclosureGroup("展开日志") {
                        LogView(model: model).frame(height: 260)
                    }
                    .font(.callout)
                }
            }
            .padding(12)
        }
    }

    /// What the menu shows now: the preset's name when it is one, otherwise
    /// the action.
    private func menuTitle(_ key: ButtonKey, _ gesture: ButtonGesture) -> String {
        let action = store.current.buttons.action(key, gesture)
        guard action == .key else { return action.title }
        if let stroke = store.current.buttons.stroke(key, gesture),
            let preset = KeyPreset.matching(stroke)
        {
            return preset.title
        }
        return "自定义按键"
    }

    /// Shows what the device will print when the name is left empty.
    private func placeholder(_ key: ButtonKey, _ gesture: ButtonGesture,
                             _ action: ButtonAction) -> String {
        guard action == .key, let s = store.current.buttons.stroke(key, gesture) else {
            return action.deviceTitle
        }
        return KeyPreset.matching(s)?.short ?? s.label
    }

    private func bind(_ key: ButtonKey, _ gesture: ButtonGesture, _ action: ButtonAction) {
        store.current.buttons.set(key, gesture, action)
        if !action.needsStroke { store.current.buttons.setStroke(key, gesture, nil) }
        store.current.buttons.setLabel(key, gesture, nil)
    }

    /// Sets the binding to send a shortcut and opens the recorder for it.
    private func openRecorder(_ slot: GestureSlot) {
        bind(slot.key, slot.gesture, .key)
        model.strokeTarget = slot
    }

    /// Hands a follow-up sheet over to a sheet that is still closing. Setting
    /// the next item while this one is on its way out makes SwiftUI drop it.
    private func afterSheetDismiss(_ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    @ViewBuilder
    private var deviceList: some View {
        let devices = model.bleSnap.devices
        if devices.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在寻找附近的 Passport…").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(spacing: 10) {
                ForEach(devices, id: \.id) { d in
                    HStack(spacing: 12) {
                        Image(systemName: d.ready ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(d.ready ? .green : .secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.name).font(.callout.weight(.medium))
                            Text(deviceDetail(d)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if d.ready {
                            Text("使用中").font(.caption).foregroundStyle(.green)
                        } else if d.connected {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("使用") { model.useDevice(d) }
                                .buttonStyle(.bordered)
                                .help(d.busyElsewhere
                                    ? "它正在另一台 Mac 上使用，点这里会切换到本机"
                                    : "连接这台设备")
                        }
                    }
                }
            }
        }
    }

    private func deviceDetail(_ d: BLEClient.Device) -> String {
        var parts: [String] = []
        if d.ready {
            parts.append("已连接本机")
        } else if d.connected {
            parts.append("连接中")
        } else if d.busyElsewhere {
            parts.append("另一台 Mac 在用")
        } else {
            parts.append("空闲")
        }
        if let b = d.battery { parts.append(d.charging ? "电量 \(b)% 充电中" : "电量 \(b)%") }
        if let rssi = d.rssi { parts.append("信号 \(rssi)") }
        if !d.firmwareVersion.isEmpty { parts.append(d.firmwareVersion) }
        return parts.joined(separator: " · ")
    }

    private func actionBinding(_ key: ButtonKey, _ gesture: ButtonGesture) -> Binding<ButtonAction> {
        Binding(
            get: { store.current.buttons.action(key, gesture) },
            set: { store.current.buttons.set(key, gesture, $0) })
    }

    private var prefixBinding: Binding<String> {
        Binding(get: { store.current.devicePrefix }, set: { store.current.devicePrefix = $0 })
    }

    private var outputBinding: Binding<String> {
        Binding(get: { store.current.outputDevice }, set: { store.current.outputDevice = $0 })
    }

    private var audioDeviceOptions: [String] {
        var names = model.audioDeviceNames
        if !names.contains(store.current.outputDevice) {
            names.insert(store.current.outputDevice, at: 0)
        }
        return names
    }

    private var autoReconnect: Binding<Bool> {
        Binding(get: { store.current.autoReconnect }, set: { store.current.autoReconnect = $0 })
    }

    /// What to do when the chosen audio device is missing. With no virtual
    /// microphone on the Mac at all, the only sensible thing is to install one.
    @ViewBuilder
    private var virtualMicHelp: some View {
        let loopbacks = AudioOutput.loopbackDeviceNames()
        if loopbacks.isEmpty || installer.busy || !installer.status.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if loopbacks.isEmpty && !installer.busy {
                    Label("这台 Mac 还没有虚拟麦克风，设备的声音没地方去",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    if loopbacks.isEmpty || installer.busy {
                        Button {
                            model.installVirtualMic()
                        } label: {
                            Label("一键安装虚拟麦克风", systemImage: "arrow.down.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(installer.busy)
                    }
                    if installer.busy { ProgressView().controlSize(.small) }
                }
                if !installer.status.isEmpty {
                    Text(installer.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else if !model.audioOK {
            HStack(spacing: 8) {
                Label("找不到这个设备", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("改用 \(loopbacks[0])") {
                    store.current.outputDevice = loopbacks[0]
                }
                .controlSize(.small)
            }
        }
    }

    /// Read from the devices themselves: the version arrives before a device
    /// counts as ready, so a summary kept elsewhere could miss it.
    private var firmwareSummary: String {
        let versions = model.bleSnap.devices.filter(\.ready).map {
            "\($0.name)  \($0.firmwareVersion.isEmpty ? "读取中" : $0.firmwareVersion)"
        }
        return versions.isEmpty ? "没有已连接的设备" : versions.joined(separator: "\n")
    }

    private var volumeBinding: Binding<Int> {
        Binding(get: { store.current.cueVolume }, set: { store.current.cueVolume = $0 })
    }

    private var powerModeBinding: Binding<BridgePowerMode> {
        Binding(get: { store.current.powerMode }, set: { store.current.powerMode = $0 })
    }

    private var hidden: Binding<Bool> {
        Binding(get: { store.current.startHidden }, set: { store.current.startHidden = $0 })
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { model.loginOn },
            set: {
                LoginItem.set($0)
                store.current.launchAtLogin = $0
            })
    }
}

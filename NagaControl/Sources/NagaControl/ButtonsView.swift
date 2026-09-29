import AppKit
import NagaKit
import SwiftUI

struct ButtonInfo: Identifiable, Hashable {
    let id: UInt8
    let name: String
}

enum ButtonCatalog {
    static func groups(plate: SidePlate) -> [(String, [ButtonInfo])] {
        let side: [ButtonInfo]
        switch plate {
        case .two:
            side = [ButtonInfo(id: ButtonID.side4, name: String(localized: "Rear side button")),
                    ButtonInfo(id: ButtonID.side5, name: String(localized: "Front side button"))]
        case .seven:
            side = ButtonID.plate7.enumerated().map { ButtonInfo(id: $1, name: String(localized: "Side \($0 + 1)")) }
        case .twelve:
            side = ButtonID.plate12.enumerated().map { ButtonInfo(id: $1, name: String(localized: "Side \($0 + 1)")) }
        }
        return [
            (String(localized: "Main"), [
                ButtonInfo(id: ButtonID.left, name: String(localized: "Left button")),
                ButtonInfo(id: ButtonID.right, name: String(localized: "Right button")),
                ButtonInfo(id: ButtonID.middle, name: String(localized: "Wheel click")),
            ]),
            (String(localized: "Wheel"), [
                ButtonInfo(id: ButtonID.wheelUp, name: String(localized: "Scroll up")),
                ButtonInfo(id: ButtonID.wheelDown, name: String(localized: "Scroll down")),
                ButtonInfo(id: ButtonID.tiltLeft, name: String(localized: "Tilt left")),
                ButtonInfo(id: ButtonID.tiltRight, name: String(localized: "Tilt right")),
            ]),
            (String(localized: "Top"), [
                ButtonInfo(id: ButtonID.dpiUp, name: String(localized: "DPI + button")),
                ButtonInfo(id: ButtonID.dpiDown, name: String(localized: "DPI − button")),
            ]),
            (String(localized: "Side panel (\(plate.title))"), side),
            (String(localized: "Other"), [ButtonInfo(id: ButtonID.extra, name: String(localized: "Button 0x0E"))]),
        ]
    }
}

extension ButtonAction {
    static let browserBack = ButtonAction.keyboard(modifiers: HIDKeys.modCmd, key: 0x2F)
    static let browserForward = ButtonAction.keyboard(modifiers: HIDKeys.modCmd, key: 0x30)

    func title(for button: UInt8, layer: Layer) -> String {
        if self == .factoryDefault(button: button, layer: layer), case .raw = self { return String(localized: "Factory function") }
        switch self {
        case .disabled: return String(localized: "Disabled")
        case .mouse(let b):
            switch b {
            case 1: return String(localized: "Left click")
            case 2: return String(localized: "Right click")
            case 3: return String(localized: "Middle click")
            case 4: return String(localized: "Mouse button 4 (back)")
            case 5: return String(localized: "Mouse button 5 (forward)")
            case 9: return String(localized: "Scroll up")
            case 10: return String(localized: "Scroll down")
            default: return String(localized: "Mouse button \(Int(b))")
            }
        case .keyboard(let m, let k):
            let keys = HIDKeys.describe(modifiers: m, key: k)
            switch (m, k) {
            case (HIDKeys.modCmd, 0x2F): return String(localized: "Browser back (\(keys))")
            case (HIDKeys.modCmd, 0x30): return String(localized: "Browser forward (\(keys))")
            case (HIDKeys.modCmd, 0x06): return String(localized: "Copy (\(keys))")
            case (HIDKeys.modCmd, 0x19): return String(localized: "Paste (\(keys))")
            case (HIDKeys.modCmd, 0x1B): return String(localized: "Cut (\(keys))")
            case (HIDKeys.modCmd, 0x17): return String(localized: "New tab (\(keys))")
            case (HIDKeys.modCmd, 0x1A): return String(localized: "Close tab (\(keys))")
            case (0, 0x2A): return String(localized: "Delete (\(keys))")
            case (HIDKeys.modCtrl, 0x52): return "Mission Control (\(keys))"
            default: return keys
            }
        case .dpi(let d): return d == 1 ? "DPI +" : d == 2 ? "DPI −" : "DPI (\(d))"
        case .raw(let t, let p):
            return String(localized: "Code") + String(format: " %02X: ", t) + p.map { String(format: "%02X", $0) }.joined(separator: " ")
        }
    }
}

struct ButtonsView: View {
    @EnvironmentObject var store: DeviceStore
    @AppStorage("sidePlate") private var plateRaw = SidePlate.two.rawValue
    @State private var layer: Layer = .normal
    @State private var selected: UInt8? = ButtonID.tiltLeft

    private var plate: SidePlate { SidePlate(rawValue: plateRaw) ?? .two }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Layer", selection: $layer) {
                        Text("Normal").tag(Layer.normal)
                        Text("Hypershift").tag(Layer.hypershift)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Hypershift is a second layer of bindings, active while the Hypershift button is held")
                    Picker("Side panel", selection: $plateRaw) {
                        ForEach(SidePlate.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .help("Which side panel is installed")
                }
                .padding(12)
                Divider()
                List(selection: $selected) {
                    ForEach(ButtonCatalog.groups(plate: plate), id: \.0) { group, buttons in
                        SwiftUI.Section(group) {
                            ForEach(buttons) { b in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(b.name)
                                    Text(store.action(b.id, layer)?.title(for: b.id, layer: layer) ?? "—")
                                        .font(.caption)
                                        .foregroundStyle(subtitleColor(b.id))
                                }
                                .padding(.vertical, 2)
                                .tag(b.id)
                            }
                        }
                    }
                }
            }
            .frame(width: 270)

            Divider()

            Group {
                if let id = selected, let info = ButtonCatalog.groups(plate: plate).flatMap(\.1).first(where: { $0.id == id }) {
                    ActionEditor(button: info, layer: layer)
                } else {
                    ContentUnavailableView("Select a button", systemImage: "cursorarrow.click")
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Changed bindings are highlighted, except on the selected row where accent-on-accent is unreadable.
    private func subtitleColor(_ id: UInt8) -> Color {
        if id == selected { return .white.opacity(0.85) }
        return isFactory(id) ? .secondary : .accentColor
    }

    private func isFactory(_ id: UInt8) -> Bool {
        store.action(id, layer) == ButtonAction.factoryDefault(button: id, layer: layer)
    }
}

struct ActionEditor: View {
    @EnvironmentObject var store: DeviceStore
    let button: ButtonInfo
    let layer: Layer

    private var current: ButtonAction? { store.action(button.id, layer) }
    private var factory: ButtonAction { .factoryDefault(button: button.id, layer: layer) }

    private let presets: [(LocalizedStringKey, String, [(LocalizedStringKey, ButtonAction)])] = [
        ("Browser", "globe", [
            ("Back  ⌘[", .browserBack), ("Forward  ⌘]", .browserForward),
            ("Mouse button 4", .mouse(4)), ("Mouse button 5", .mouse(5)),
        ]),
        ("Mouse", "computermouse", [
            ("Left click", .mouse(1)), ("Right click", .mouse(2)), ("Middle click", .mouse(3)),
            ("Scroll ↑", .mouse(9)), ("Scroll ↓", .mouse(10)),
        ]),
        ("System", "macwindow", [
            ("Mission Control  ⌃↑", .keyboard(modifiers: HIDKeys.modCtrl, key: 0x52)),
            ("Space left  ⌃←", .keyboard(modifiers: HIDKeys.modCtrl, key: 0x50)),
            ("Space right  ⌃→", .keyboard(modifiers: HIDKeys.modCtrl, key: 0x4F)),
            ("Copy  ⌘C", .keyboard(modifiers: HIDKeys.modCmd, key: 0x06)),
            ("Paste  ⌘V", .keyboard(modifiers: HIDKeys.modCmd, key: 0x19)),
            ("Cut  ⌘X", .keyboard(modifiers: HIDKeys.modCmd, key: 0x1B)),
            ("Delete  ⌫", .keyboard(modifiers: 0, key: 0x2A)),
            ("New tab  ⌘T", .keyboard(modifiers: HIDKeys.modCmd, key: 0x17)),
            ("Close tab  ⌘W", .keyboard(modifiers: HIDKeys.modCmd, key: 0x1A)),
        ]),
        ("DPI", "speedometer", [("DPI +", .dpi(1)), ("DPI −", .dpi(2))]),
    ]

    var body: some View {
        Form {
            SwiftUI.Section {
                LabeledContent("Current") {
                    Text(current?.title(for: button.id, layer: layer) ?? "—").fontWeight(.semibold)
                }
                LabeledContent("Factory") {
                    Text(factory.title(for: button.id, layer: layer)).foregroundStyle(.secondary)
                }
            } header: {
                Text(button.name).font(.title2.bold()).foregroundStyle(.primary)
                    + Text(verbatim: layer == .hypershift ? "  · Hypershift" : "").foregroundStyle(.secondary)
            }

            ForEach(presets, id: \.1) { title, icon, items in
                SwiftUI.Section {
                    FlowLayout(spacing: 8) {
                        ForEach(items, id: \.1) { label, action in
                            Button(label) { store.setAction(action, button: button.id, layer: layer) }
                                .buttonStyle(PresetButtonStyle(active: current == action))
                        }
                    }
                } header: { Label(title, systemImage: icon) }
            }

            SwiftUI.Section("Custom shortcut") {
                KeyRecorder { mods, key in
                    store.setAction(.keyboard(modifiers: mods, key: key), button: button.id, layer: layer)
                }
            }

            SwiftUI.Section {
                HStack {
                    Button("Restore factory") { store.setAction(factory, button: button.id, layer: layer) }
                        .disabled(current == factory)
                    Button("Disable button", role: .destructive) { store.setAction(.disabled, button: button.id, layer: layer) }
                        .disabled(current == .disabled || button.id == ButtonID.left)
                }
            } footer: {
                if button.id == ButtonID.left {
                    Text("The left button can’t be disabled — you could end up without a click.").font(.caption)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct PresetButtonStyle: ButtonStyle {
    var active: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(active ? Color.accentColor : Color.secondary.opacity(configuration.isPressed ? 0.3 : 0.12),
                        in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(active ? Color.white : Color.primary)
    }
}

/// Records one keyboard shortcut from the next key press.
struct KeyRecorder: View {
    var onRecord: (UInt8, UInt8) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hint: String?

    var body: some View {
        HStack {
            Button(recording ? LocalizedStringKey("Press a shortcut…") : "Record shortcut") {
                recording ? stop() : start()
            }
            .buttonStyle(.borderedProminent)
            .tint(recording ? .orange : .accentColor)
            if recording { Button("Cancel") { stop() } }
            if let hint { Text(hint).foregroundStyle(.secondary).font(.caption) }
        }
        .onDisappear { stop() }
    }

    private func start() {
        hint = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let key = HIDKeys.key(virtualKeyCode: event.keyCode) else {
                hint = String(localized: "This key isn’t supported")
                return nil
            }
            let f = event.modifierFlags
            var mods: UInt8 = 0
            if f.contains(.control) { mods |= HIDKeys.modCtrl }
            if f.contains(.shift) { mods |= HIDKeys.modShift }
            if f.contains(.option) { mods |= HIDKeys.modAlt }
            if f.contains(.command) { mods |= HIDKeys.modCmd }
            onRecord(mods, key.hid)
            let keys = HIDKeys.describe(modifiers: mods, key: key.hid)
            hint = String(localized: "Assigned: \(keys)")
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

/// Simple wrapping layout for preset chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Without a proposed width, wrap to the widest chip so the ideal size never
        // becomes one endless row that pushes the window wider than it is.
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? widest
        let size = arrange(width: width, subviews: subviews).size
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(width: bounds.width, subviews: subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        var points: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowH = max(rowH, size.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: maxX, height: y + rowH), points)
    }
}

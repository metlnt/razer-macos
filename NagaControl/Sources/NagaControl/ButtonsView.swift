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
            side = [ButtonInfo(id: ButtonID.side4, name: "Боковая задняя"),
                    ButtonInfo(id: ButtonID.side5, name: "Боковая передняя")]
        case .seven:
            side = ButtonID.plate7.enumerated().map { ButtonInfo(id: $1, name: "Боковая \($0 + 1)") }
        case .twelve:
            side = ButtonID.plate12.enumerated().map { ButtonInfo(id: $1, name: "Боковая \($0 + 1)") }
        }
        return [
            ("Основные", [
                ButtonInfo(id: ButtonID.left, name: "Левая кнопка"),
                ButtonInfo(id: ButtonID.right, name: "Правая кнопка"),
                ButtonInfo(id: ButtonID.middle, name: "Нажатие колеса"),
            ]),
            ("Колесо", [
                ButtonInfo(id: ButtonID.wheelUp, name: "Прокрутка вверх"),
                ButtonInfo(id: ButtonID.wheelDown, name: "Прокрутка вниз"),
                ButtonInfo(id: ButtonID.tiltLeft, name: "Наклон влево"),
                ButtonInfo(id: ButtonID.tiltRight, name: "Наклон вправо"),
            ]),
            ("Верхние", [
                ButtonInfo(id: ButtonID.dpiUp, name: "Кнопка DPI +"),
                ButtonInfo(id: ButtonID.dpiDown, name: "Кнопка DPI −"),
            ]),
            ("Боковая панель (\(plate.title))", side),
            ("Прочее", [ButtonInfo(id: ButtonID.extra, name: "Кнопка 0x0E")]),
        ]
    }
}

extension ButtonAction {
    static let browserBack = ButtonAction.keyboard(modifiers: HIDKeys.modCmd, key: 0x2F)
    static let browserForward = ButtonAction.keyboard(modifiers: HIDKeys.modCmd, key: 0x30)

    func title(for button: UInt8, layer: Layer) -> String {
        if self == .factoryDefault(button: button, layer: layer), case .raw = self { return "Заводская функция" }
        switch self {
        case .disabled: return "Отключено"
        case .mouse(let b):
            return [1: "Левый клик", 2: "Правый клик", 3: "Средний клик", 4: "Кнопка мыши 4 (назад)",
                    5: "Кнопка мыши 5 (вперёд)", 9: "Прокрутка вверх", 10: "Прокрутка вниз"][Int(b)] ?? "Кнопка мыши \(b)"
        case .keyboard(let m, let k):
            let keys = HIDKeys.describe(modifiers: m, key: k)
            if self == .browserBack { return "Назад в браузере (\(keys))" }
            if self == .browserForward { return "Вперёд в браузере (\(keys))" }
            return keys
        case .dpi(let d): return d == 1 ? "DPI +" : d == 2 ? "DPI −" : "DPI (\(d))"
        case .raw(let t, let p):
            return String(format: "Код %02X: ", t) + p.map { String(format: "%02X", $0) }.joined(separator: " ")
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
                    Picker("Слой", selection: $layer) {
                        Text("Обычный").tag(Layer.normal)
                        Text("Hypershift").tag(Layer.hypershift)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Hypershift — второй слой назначений, пока зажата кнопка Hypershift")
                    Picker("Боковая панель", selection: $plateRaw) {
                        ForEach(SidePlate.allCases) { Text($0.title).tag($0.rawValue) }
                    }
                    .help("Какая боковая панель установлена")
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
                                        .foregroundStyle(isFactory(b.id) ? Color.secondary : Color.accentColor)
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
                    ContentUnavailableView("Выберите кнопку", systemImage: "cursorarrow.click")
                }
            }
            .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
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

    private let presets: [(String, String, [(String, ButtonAction)])] = [
        ("Браузер", "globe", [
            ("Назад  ⌘[", .browserBack), ("Вперёд  ⌘]", .browserForward),
            ("Кнопка мыши 4", .mouse(4)), ("Кнопка мыши 5", .mouse(5)),
        ]),
        ("Мышь", "computermouse", [
            ("Левый клик", .mouse(1)), ("Правый клик", .mouse(2)), ("Средний клик", .mouse(3)),
            ("Прокрутка ↑", .mouse(9)), ("Прокрутка ↓", .mouse(10)),
        ]),
        ("Система", "macwindow", [
            ("Mission Control  ⌃↑", .keyboard(modifiers: HIDKeys.modCtrl, key: 0x52)),
            ("Стол слева  ⌃←", .keyboard(modifiers: HIDKeys.modCtrl, key: 0x50)),
            ("Стол справа  ⌃→", .keyboard(modifiers: HIDKeys.modCtrl, key: 0x4F)),
            ("Копировать  ⌘C", .keyboard(modifiers: HIDKeys.modCmd, key: 0x06)),
            ("Вставить  ⌘V", .keyboard(modifiers: HIDKeys.modCmd, key: 0x19)),
            ("Новая вкладка  ⌘T", .keyboard(modifiers: HIDKeys.modCmd, key: 0x17)),
            ("Закрыть вкладку  ⌘W", .keyboard(modifiers: HIDKeys.modCmd, key: 0x1A)),
        ]),
        ("DPI", "speedometer", [("DPI +", .dpi(1)), ("DPI −", .dpi(2))]),
    ]

    var body: some View {
        Form {
            SwiftUI.Section {
                LabeledContent("Сейчас") {
                    Text(current?.title(for: button.id, layer: layer) ?? "—").fontWeight(.semibold)
                }
                LabeledContent("Заводское") {
                    Text(factory.title(for: button.id, layer: layer)).foregroundStyle(.secondary)
                }
            } header: {
                Text(button.name).font(.title2.bold()).foregroundStyle(.primary)
                    + Text(layer == .hypershift ? "  · Hypershift" : "").foregroundStyle(.secondary)
            }

            ForEach(presets, id: \.0) { title, icon, items in
                SwiftUI.Section {
                    FlowLayout(spacing: 8) {
                        ForEach(items, id: \.0) { label, action in
                            Button(label) { store.setAction(action, button: button.id, layer: layer) }
                                .buttonStyle(PresetButtonStyle(active: current == action))
                        }
                    }
                } header: { Label(title, systemImage: icon) }
            }

            SwiftUI.Section("Своё сочетание клавиш") {
                KeyRecorder { mods, key in
                    store.setAction(.keyboard(modifiers: mods, key: key), button: button.id, layer: layer)
                }
            }

            SwiftUI.Section {
                HStack {
                    Button("Вернуть заводское") { store.setAction(factory, button: button.id, layer: layer) }
                        .disabled(current == factory)
                    Button("Отключить кнопку", role: .destructive) { store.setAction(.disabled, button: button.id, layer: layer) }
                        .disabled(current == .disabled || button.id == ButtonID.left)
                }
            } footer: {
                if button.id == ButtonID.left {
                    Text("Левую кнопку отключить нельзя — иначе можно остаться без клика.").font(.caption)
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
            Button(recording ? "Нажмите сочетание…" : "Записать сочетание") {
                recording ? stop() : start()
            }
            .buttonStyle(.borderedProminent)
            .tint(recording ? .orange : .accentColor)
            if recording { Button("Отмена") { stop() } }
            if let hint { Text(hint).foregroundStyle(.secondary).font(.caption) }
        }
        .onDisappear { stop() }
    }

    private func start() {
        hint = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let key = HIDKeys.key(virtualKeyCode: event.keyCode) else {
                hint = "Эта клавиша не поддерживается"
                return nil
            }
            let f = event.modifierFlags
            var mods: UInt8 = 0
            if f.contains(.control) { mods |= HIDKeys.modCtrl }
            if f.contains(.shift) { mods |= HIDKeys.modShift }
            if f.contains(.option) { mods |= HIDKeys.modAlt }
            if f.contains(.command) { mods |= HIDKeys.modCmd }
            onRecord(mods, key.hid)
            hint = "Назначено: " + HIDKeys.describe(modifiers: mods, key: key.hid)
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

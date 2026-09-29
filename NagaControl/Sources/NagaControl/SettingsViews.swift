import AppKit
import NagaKit
import SwiftUI

// MARK: - DPI & polling

struct PerformanceView: View {
    @EnvironmentObject var store: DeviceStore
    @State private var splitXY = false

    var body: some View {
        Form {
            SwiftUI.Section {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: store.currentDPI.map { $0.x == $0.y ? "\($0.x)" : "\($0.x)×\($0.y)" } ?? "—")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("DPI").font(.title3).foregroundStyle(.secondary)
                    Spacer()
                    Text("Stage \(store.dpi.active) of \(store.dpi.stages.count)").foregroundStyle(.secondary)
                }
                .animation(.snappy, value: store.currentDPI)
            } header: {
                Text("Now")
            }

            SwiftUI.Section("Polling rate") {
                Picker("Polling rate", selection: Binding(get: { store.polling }, set: { store.setPolling($0) })) {
                    ForEach(PollingRate.allCases) { Text("\($0.hz) Hz").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            SwiftUI.Section {
                ForEach(store.dpi.stages.indices, id: \.self) { i in
                    DPIStageRow(index: i, splitXY: splitXY)
                }
                HStack {
                    Button("Add stage", systemImage: "plus") {
                        var d = store.dpi
                        d.stages.append(d.stages.last ?? DPIStage(x: 1600, y: 1600))
                        store.setDPI(d)
                    }
                    .disabled(store.dpi.stages.count >= 5)
                    Button("Remove last", systemImage: "minus") {
                        var d = store.dpi
                        d.stages.removeLast()
                        d.active = min(d.active, d.stages.count)
                        store.setDPI(d)
                    }
                    .disabled(store.dpi.stages.count <= 1)
                    Spacer()
                    Toggle("Separate X/Y", isOn: $splitXY)
                }
            } header: {
                Text("DPI stages")
            } footer: {
                Text("The DPI ± buttons cycle through the stages. The selected stage applies immediately.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

struct DPIStageRow: View {
    @EnvironmentObject var store: DeviceStore
    let index: Int
    let splitXY: Bool

    var body: some View {
        let stage = store.dpi.stages[index]
        let isActive = store.dpi.active == index + 1
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    var d = store.dpi
                    d.active = index + 1
                    store.setDPI(d)
                } label: {
                    Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Make active")
                Text("Stage \(index + 1)").fontWeight(isActive ? .semibold : .regular)
                Spacer()
                Text(verbatim: splitXY ? "\(stage.x) × \(stage.y)" : "\(stage.x) DPI").monospacedDigit().foregroundStyle(.secondary)
            }
            axisSlider("X", value: stage.x) { v in update { $0.x = v; if !splitXY { $0.y = v } } }
            if splitXY {
                axisSlider("Y", value: stage.y) { v in update { $0.y = v } }
            }
        }
        .padding(.vertical, 4)
    }

    private func axisSlider(_ label: String, value: UInt16, set: @escaping (UInt16) -> Void) -> some View {
        HStack {
            if splitXY { Text(label).frame(width: 14).foregroundStyle(.secondary) }
            Slider(value: Binding(get: { Double(value) }, set: { set(UInt16(($0 / 50).rounded() * 50)) }),
                   in: Double(DPIStages.range.lowerBound)...Double(DPIStages.range.upperBound))
            TextField("", value: Binding(get: { Int(value) }, set: {
                set(UInt16(min(max($0, DPIStages.range.lowerBound), DPIStages.range.upperBound)))
            }), format: .number.grouping(.never))
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
        }
    }

    private func update(_ change: (inout DPIStage) -> Void) {
        var d = store.dpi
        change(&d.stages[index])
        store.setDPI(d)
    }
}

// MARK: - Lighting

enum EffectKind: String, CaseIterable, Identifiable {
    case off, staticColor, breathing, breathingDual, breathingRandom, spectrum, reactive
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return String(localized: "Off")
        case .staticColor: return String(localized: "Static color")
        case .breathing: return String(localized: "Breathing")
        case .breathingDual: return String(localized: "Breathing, 2 colors")
        case .breathingRandom: return String(localized: "Breathing, random")
        case .spectrum: return String(localized: "Spectrum")
        case .reactive: return String(localized: "Reactive")
        }
    }

    init(_ e: LightEffect) {
        switch e {
        case .off, .unknown: self = .off
        case .staticColor: self = .staticColor
        case .breathing: self = .breathing
        case .breathingDual: self = .breathingDual
        case .breathingRandom: self = .breathingRandom
        case .spectrum: self = .spectrum
        case .reactive: self = .reactive
        }
    }
}

extension LightEffect {
    var colors: (RGB, RGB) {
        switch self {
        case .staticColor(let c), .breathing(let c), .reactive(let c, _): return (c, RGB(0, 0, 255))
        case .breathingDual(let a, let b): return (a, b)
        default: return (.green, RGB(0, 0, 255))
        }
    }

    var speed: UInt8 { if case .reactive(_, let s) = self { return s } else { return 2 } }

    static func make(_ kind: EffectKind, _ c1: RGB, _ c2: RGB, speed: UInt8) -> LightEffect {
        switch kind {
        case .off: return .off
        case .staticColor: return .staticColor(c1)
        case .breathing: return .breathing(c1)
        case .breathingDual: return .breathingDual(c1, c2)
        case .breathingRandom: return .breathingRandom
        case .spectrum: return .spectrum
        case .reactive: return .reactive(c1, speed: speed)
        }
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255) }
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(UInt8((ns.redComponent * 255).rounded()), UInt8((ns.greenComponent * 255).rounded()),
                  UInt8((ns.blueComponent * 255).rounded()))
    }
}

struct LightingView: View {
    @EnvironmentObject var store: DeviceStore
    @AppStorage("syncZones") private var sync = true

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle("Same for all zones", isOn: $sync)
            }
            if sync {
                ZoneEditor(title: String(localized: "All zones"), state: store.zones[.logo] ?? ZoneState()) { store.setAllZones($0) }
            } else {
                ForEach(LEDZone.allCases) { z in
                    ZoneEditor(title: z.title, state: store.zones[z] ?? ZoneState()) { store.setZone(z, $0) }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ZoneEditor: View {
    let title: String
    let state: ZoneState
    let onChange: (ZoneState) -> Void

    var body: some View {
        let kind = EffectKind(state.effect)
        let (c1, c2) = state.effect.colors
        SwiftUI.Section(title) {
            Picker("Effect", selection: Binding(get: { kind }, set: { apply($0, c1, c2, state.effect.speed) })) {
                ForEach(EffectKind.allCases) { Text($0.title).tag($0) }
            }
            if [.staticColor, .breathing, .breathingDual, .reactive].contains(kind) {
                ColorPicker(kind == .breathingDual ? LocalizedStringKey("Color 1") : "Color",
                            selection: Binding(get: { c1.color }, set: { apply(kind, RGB($0), c2, state.effect.speed) }),
                            supportsOpacity: false)
            }
            if kind == .breathingDual {
                ColorPicker("Color 2", selection: Binding(get: { c2.color }, set: { apply(kind, c1, RGB($0), state.effect.speed) }),
                            supportsOpacity: false)
            }
            if kind == .reactive {
                Picker("Duration", selection: Binding(get: { state.effect.speed }, set: { apply(kind, c1, c2, $0) })) {
                    Text("Short").tag(UInt8(1)); Text("Medium").tag(UInt8(2))
                    Text("Long").tag(UInt8(3)); Text("Very long").tag(UInt8(4))
                }
            }
            if kind != .off {
                LabeledContent("Brightness") {
                    HStack {
                        Slider(value: Binding(get: { state.brightness }, set: {
                            var s = state; s.brightness = $0; onChange(s)
                        }), in: 0...255)
                        Text(verbatim: "\(Int(state.brightness / 2.55))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func apply(_ kind: EffectKind, _ c1: RGB, _ c2: RGB, _ speed: UInt8) {
        var s = state
        s.effect = .make(kind, c1, c2, speed: speed)
        if kind != .off, s.brightness == 0 { s.brightness = 255 }
        onChange(s)
    }
}

// MARK: - Device

struct DeviceView: View {
    @EnvironmentObject var store: DeviceStore

    var body: some View {
        Form {
            SwiftUI.Section("Device") {
                LabeledContent("Model", value: "Razer Naga Trinity (RZ01-0241)")
                LabeledContent("USB", value: "1532:0067")
                LabeledContent("Firmware", value: store.info?.firmware ?? "—")
                LabeledContent("Serial number", value: store.info?.serial ?? "—")
            }
            SwiftUI.Section {
                Button("Reload settings from mouse") { Task { await store.reload() } }
                Button("Reset all buttons to factory defaults", role: .destructive) { store.resetAllButtons() }
            } footer: {
                Text("All changes apply immediately and are stored in the mouse — they keep working without this app.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

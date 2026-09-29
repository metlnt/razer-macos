import AppKit
import NagaKit
import SwiftUI

struct ZoneState: Equatable {
    var effect: LightEffect = .off
    var brightness: Double = 255
}

struct MappingKey: Hashable {
    var button: UInt8
    var layer: Layer
}

enum SidePlate: Int, CaseIterable, Identifiable {
    case two = 2, seven = 7, twelve = 12
    var id: Int { rawValue }
    var title: String { String(localized: "\(rawValue) buttons") }
}

@MainActor
final class DeviceStore: ObservableObject {
    enum Status: Equatable { case searching, loading, ready, error(String) }

    @Published var status: Status = .searching
    @Published var info: DeviceInfo?
    @Published var polling: PollingRate = .hz1000
    @Published var dpi = DPIStages(active: 1, stages: [DPIStage(x: 1600, y: 1600)])
    @Published var zones: [LEDZone: ZoneState] = [:]
    @Published var mappings: [MappingKey: ButtonAction] = [:]
    @Published var toast: String?
    /// DPI actually in use right now (follows the mouse's DPI buttons).
    @Published var currentDPI: DPIStage?
    @Published var animation = AnimationSettings.load() {
        didSet { animationChanged(from: oldValue) }
    }

    static let shared = DeviceStore()

    private var device: NagaTrinity?
    private let monitor = DeviceMonitor()
    private let queue = DispatchQueue(label: "naga.hid")
    private var pending: [String: Task<Void, Never>] = [:]
    private var watcher: Task<Void, Never>?
    private var animationTimer: Timer?
    private var renderer = AnimationRenderer(settings: AnimationSettings())
    private let cpu = CPUMonitor()
    private var lastCPUSample = Date.distantPast
    private var frameInFlight = false
    private let animationStart = Date()

    private init() {
        monitor.onChange = { [weak self] in self?.connect() }
        connect()
    }

    /// Polls the live DPI so changes made with the mouse's buttons show up.
    private func startWatching() {
        watcher?.cancel()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, self.status == .ready, self.pending["dpi"] == nil else { continue }
                guard let (dpi, active) = try? await self.io({ d in (try d.currentDPI(), try d.dpiStages().active) })
                else { continue }
                if self.pending["dpi"] != nil { continue }
                if self.currentDPI != dpi { self.currentDPI = dpi }
                if self.dpi.active != active, self.dpi.stages.indices.contains(active - 1) { self.dpi.active = active }
            }
        }
    }

    // MARK: Connection

    func connect() {
        guard monitor.isConnected else {
            stopAnimationTimer()
            device = nil
            currentDPI = nil
            status = .searching
            return
        }
        do {
            device = try NagaTrinity()
            Task { await reload() }
            startWatching()
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Runs HID I/O off the main thread, serialized.
    private func io<T>(_ body: @escaping (NagaTrinity) throws -> T) async throws -> T {
        guard let device else { throw RazerError.io(String(localized: "mouse not connected")) }
        return try await withCheckedThrowingContinuation { cont in
            queue.async { cont.resume(with: Result { try body(device) }) }
        }
    }

    func reload() async {
        status = .loading
        do {
            let snap = try await io { d -> (DeviceInfo, PollingRate, DPIStages, [LEDZone: ZoneState], [MappingKey: ButtonAction], DPIStage) in
                var zones: [LEDZone: ZoneState] = [:]
                for z in LEDZone.allCases {
                    zones[z] = ZoneState(effect: try d.effect(z), brightness: Double(try d.brightness(z)))
                }
                var maps: [MappingKey: ButtonAction] = [:]
                for b in try d.buttonIDs() {
                    for l in Layer.allCases { maps[MappingKey(button: b, layer: l)] = try d.action(button: b, layer: l) }
                }
                return (try d.info(), try d.pollingRate(), try d.dpiStages(), zones, maps, try d.currentDPI())
            }
            (info, polling, dpi, zones, mappings, currentDPI) = snap
            status = .ready
            if animation.enabled { startAnimation() }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Writes to both live and saved storage so the change is immediate and survives replugging.
    private func write(_ key: String, debounce: Bool = false, _ body: @escaping (NagaTrinity) throws -> Void) {
        pending[key]?.cancel()
        pending[key] = Task {
            if debounce {
                try? await Task.sleep(for: .milliseconds(120))
                if Task.isCancelled { return }
            }
            do { try await io(body) } catch { show(error.localizedDescription) }
            if !Task.isCancelled { pending[key] = nil }
        }
    }

    func show(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == message { toast = nil }
        }
    }

    // MARK: Performance

    func setPolling(_ rate: PollingRate) {
        polling = rate
        write("polling") { try $0.setPollingRate(rate) }
    }

    func setDPI(_ stages: DPIStages) {
        dpi = stages
        let active = stages.stages[stages.active - 1]
        currentDPI = active
        write("dpi", debounce: true) { d in
            try d.setDPIStages(stages, store: NagaTrinity.savedStore)
            try d.setDPI(active, store: NagaTrinity.liveStore)
        }
    }

    func selectStage(_ index: Int) {
        var d = dpi
        d.active = index + 1
        setDPI(d)
    }

    // MARK: Lighting

    func setZone(_ zone: LEDZone, _ state: ZoneState) {
        let old = zones[zone]
        zones[zone] = state
        if old?.effect != state.effect {
            write("fx\(zone.rawValue)", debounce: true) { d in
                for s in [NagaTrinity.liveStore, NagaTrinity.savedStore] { try d.setEffect(state.effect, zone: zone, store: s) }
            }
        }
        if old?.brightness != state.brightness {
            let v = UInt8(state.brightness.rounded())
            write("br\(zone.rawValue)", debounce: true) { d in
                for s in [NagaTrinity.liveStore, NagaTrinity.savedStore] { try d.setBrightness(v, zone: zone, store: s) }
            }
        }
    }

    func setAllZones(_ state: ZoneState) {
        for z in LEDZone.allCases { setZone(z, state) }
    }

    // MARK: Software animations

    private func animationChanged(from old: AnimationSettings) {
        animation.save()
        renderer.settings = animation
        guard status == .ready else { return }
        if animation.enabled && !old.enabled {
            startAnimation()
        } else if !animation.enabled && old.enabled {
            stopAnimation()
        }
    }

    private func startAnimation() {
        renderer.settings = animation
        write("anim-start") { try $0.enableCustomFrame() }
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderFrame() }
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func stopAnimationTimer() {
        animationTimer?.invalidate()
        animationTimer = nil
    }

    /// Stops streaming and puts the mouse's own effects back.
    private func stopAnimation() {
        stopAnimationTimer()
        let zones = self.zones
        write("anim-stop") { d in
            for (z, st) in zones {
                try d.setEffect(st.effect, zone: z, store: NagaTrinity.liveStore)
                try d.setBrightness(UInt8(st.brightness.rounded()), zone: z, store: NagaTrinity.liveStore)
            }
        }
    }

    /// Called on quit: restores the mouse's own effects before the process exits.
    func restoreLightingSync() {
        guard animation.enabled, let device else { return }
        stopAnimationTimer()
        let zones = self.zones
        queue.sync {
            for (z, st) in zones {
                try? device.setEffect(st.effect, zone: z, store: NagaTrinity.liveStore)
                try? device.setBrightness(UInt8(st.brightness.rounded()), zone: z, store: NagaTrinity.liveStore)
            }
        }
    }

    private func renderFrame() {
        guard let device, !frameInFlight else { return }  // drop frames instead of queueing them
        if animation.kind == .cpu, Date().timeIntervalSince(lastCPUSample) > 0.5 {
            renderer.cpuLoad = cpu.sample()
            lastCPUSample = Date()
        }
        let colors = renderer.frame(at: Date().timeIntervalSince(animationStart), zones: NagaTrinity.frameZones.count)
        frameInFlight = true
        queue.async { [weak self] in
            try? device.setCustomFrame(colors)
            DispatchQueue.main.async { self?.frameInFlight = false }
        }
    }

    // MARK: Buttons

    func action(_ button: UInt8, _ layer: Layer) -> ButtonAction? {
        mappings[MappingKey(button: button, layer: layer)]
    }

    func setAction(_ action: ButtonAction, button: UInt8, layer: Layer) {
        mappings[MappingKey(button: button, layer: layer)] = action
        write("btn\(button)-\(layer.rawValue)") { d in
            for p: UInt8 in [0, 1] { try d.setAction(action, button: button, layer: layer, profile: p) }
        }
    }

    func resetAllButtons() {
        for key in mappings.keys {
            setAction(ButtonAction.factoryDefault(button: key.button, layer: key.layer), button: key.button, layer: key.layer)
        }
        show(String(localized: "All buttons restored to factory defaults"))
    }
}

import Foundation

// MARK: - Models

public struct RGB: Equatable, Hashable, Codable {
    public var r, g, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
    public static let green = RGB(0, 255, 0)
}

public enum LEDZone: UInt8, CaseIterable, Identifiable {
    case scrollWheel = 0x01, logo = 0x04, sidePanel = 0x11
    public var id: UInt8 { rawValue }
    public var title: String {
        switch self {
        case .scrollWheel: return String(localized: "Scroll wheel")
        case .logo: return String(localized: "Logo")
        case .sidePanel: return String(localized: "Side panel")
        }
    }
}

public enum LightEffect: Equatable {
    case off
    case staticColor(RGB)
    case breathingRandom
    case breathing(RGB)
    case breathingDual(RGB, RGB)
    case spectrum
    case reactive(RGB, speed: UInt8)   // speed 1 (fast) ... 4 (slow)
    case unknown([UInt8])

    /// (data size, args) for command 0F:02.
    func encode(store: UInt8, zone: LEDZone) -> (UInt8, [UInt8]) {
        let h: [UInt8] = [store, zone.rawValue]
        switch self {
        case .off: return (6, h + [0x00, 0, 0, 0])
        case .spectrum: return (6, h + [0x03, 0, 0, 0])
        case .breathingRandom: return (6, h + [0x02, 0, 0, 0])
        case .staticColor(let c): return (9, h + [0x01, 0, 0, 1, c.r, c.g, c.b])
        case .breathing(let c): return (9, h + [0x02, 1, 0, 1, c.r, c.g, c.b])
        case .breathingDual(let a, let b): return (12, h + [0x02, 2, 0, 2, a.r, a.g, a.b, b.r, b.g, b.b])
        case .reactive(let c, let s): return (9, h + [0x05, 0, s, 1, c.r, c.g, c.b])
        case .unknown(let raw): return (UInt8(raw.count + 2), h + raw)
        }
    }

    /// Decodes the response of 0F:82 (args start with store, zone).
    static func decode(_ a: [UInt8]) -> LightEffect {
        func rgb(_ i: Int) -> RGB { RGB(a[i], a[i + 1], a[i + 2]) }
        switch a[2] {
        case 0x00: return .off
        case 0x01: return .staticColor(rgb(6))
        case 0x02:
            switch a[3] {
            case 1: return .breathing(rgb(6))
            case 2: return .breathingDual(rgb(6), rgb(9))
            default: return .breathingRandom
            }
        case 0x03: return .spectrum
        case 0x05: return .reactive(rgb(6), speed: max(1, a[4]))
        default: return .unknown(Array(a[2..<12]))
        }
    }
}

public enum PollingRate: UInt8, CaseIterable, Identifiable {
    case hz125 = 0x08, hz500 = 0x02, hz1000 = 0x01
    public var id: UInt8 { rawValue }
    public var hz: Int { [0x08: 125, 0x02: 500, 0x01: 1000][rawValue]! }
}

public struct DPIStage: Equatable, Hashable {
    public var x: UInt16, y: UInt16
    public init(x: UInt16, y: UInt16) { self.x = x; self.y = y }
}

public struct DPIStages: Equatable {
    public var active: Int          // 1-based
    public var stages: [DPIStage]   // 1...5
    public init(active: Int, stages: [DPIStage]) { self.active = active; self.stages = stages }
    public static let range: ClosedRange<Int> = 100...16000
}

/// Button identifiers from command 02:84.
public enum ButtonID {
    public static let left: UInt8 = 0x01, right: UInt8 = 0x02, middle: UInt8 = 0x03
    public static let side4: UInt8 = 0x04, side5: UInt8 = 0x05
    public static let wheelUp: UInt8 = 0x09, wheelDown: UInt8 = 0x0A
    public static let dpiUp: UInt8 = 0x0B, dpiDown: UInt8 = 0x0C, extra: UInt8 = 0x0E
    public static let tiltLeft: UInt8 = 0x34, tiltRight: UInt8 = 0x35
    public static let plate12: [UInt8] = Array(0x40...0x4B)
    public static let plate7: [UInt8] = Array(0x50...0x56)
}

public enum Layer: UInt8, CaseIterable, Identifiable {
    case normal = 0, hypershift = 1
    public var id: UInt8 { rawValue }
}

public enum ButtonAction: Equatable, Hashable {
    case disabled
    case mouse(UInt8)                            // 1 L, 2 R, 3 M, 4 back, 5 forward, 9/0A wheel
    case keyboard(modifiers: UInt8, key: UInt8)  // HID modifier bits + HID usage
    case dpi(UInt8)                              // 1 stage up, 2 stage down
    case raw(type: UInt8, params: [UInt8])

    var encoded: [UInt8] {
        switch self {
        case .disabled: return [0x00, 0x00]
        case .mouse(let b): return [0x01, 0x01, b]
        case .keyboard(let m, let k): return [0x02, 0x02, m, k]
        case .dpi(let d): return [0x06, 0x01, d]
        case .raw(let t, let p): return [t, UInt8(p.count)] + p
        }
    }

    static func decode(type t: UInt8, params p: [UInt8]) -> ButtonAction {
        switch (t, p.count) {
        case (0x00, _): return .disabled
        case (0x01, 1): return .mouse(p[0])
        case (0x02, 2): return .keyboard(modifiers: p[0], key: p[1])
        case (0x06, 1): return .dpi(p[0])
        default: return .raw(type: t, params: p)
        }
    }

    /// Factory mapping, captured from this mouse before any changes.
    public static func factoryDefault(button b: UInt8, layer: Layer) -> ButtonAction {
        switch b {
        case 0x01...0x05, 0x09, 0x0A: return .mouse(b)
        case ButtonID.tiltLeft: return .raw(type: 0x0E, params: [0x09, 0x00, 0x8E])
        case ButtonID.tiltRight: return .raw(type: 0x0E, params: [0x0A, 0x00, 0x8E])
        case ButtonID.dpiUp: return .dpi(1)
        case ButtonID.dpiDown: return .dpi(2)
        case ButtonID.extra: return layer == .normal ? .raw(type: 0x07, params: [0x01]) : .disabled
        default:
            // side buttons type 1,2,...,9,0,-,=
            let keys: [UInt8] = [0x1E, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x2D, 0x2E]
            if let i = ButtonID.plate12.firstIndex(of: b) { return .keyboard(modifiers: 0, key: keys[i]) }
            if let i = ButtonID.plate7.firstIndex(of: b) { return .keyboard(modifiers: 0, key: keys[i]) }
            return .disabled
        }
    }
}

public struct DeviceInfo: Equatable {
    public var firmware: String
    public var serial: String
}

// MARK: - Device

/// Razer Naga Trinity (RZ01-0241, USB 1532:0067) protocol.
///
/// Storage: 0 = live (RAM), 1 = saved on the mouse. Button profiles: 0 = live, 1...5 = onboard.
public final class NagaTrinity {
    public static let reportLength = 90
    static let transactionID: UInt8 = 0x1F

    public static let liveStore: UInt8 = 0
    public static let savedStore: UInt8 = 1

    private let hid: USBTransport

    public init() throws {
        hid = try USBTransport()
    }

    static func buildReport(_ cls: UInt8, _ id: UInt8, size: UInt8, args: [UInt8]) -> [UInt8] {
        var r = [UInt8](repeating: 0, count: reportLength)
        r[1] = transactionID
        r[5] = size
        r[6] = cls
        r[7] = id
        for (i, a) in args.prefix(80).enumerated() { r[8 + i] = a }
        r[88] = r[2..<88].reduce(0, ^)
        return r
    }

    /// Sends a command and returns the 80 argument bytes of the response.
    @discardableResult
    public func request(_ cls: UInt8, _ id: UInt8, size: UInt8, _ args: [UInt8] = []) throws -> [UInt8] {
        try hid.setFeature(Self.buildReport(cls, id, size: size, args: args))
        for _ in 0..<15 {
            usleep(4000)
            let resp = try hid.getFeature(length: Self.reportLength)
            guard resp.count >= Self.reportLength else { continue }
            if resp[0] == 0x01 || resp[6] != cls || resp[7] != id { continue }  // busy / stale
            guard resp[0] == 0x02 else { throw RazerError.status(resp[0], cls: cls, id: id) }
            return Array(resp[8..<88])
        }
        throw RazerError.noResponse(cls: cls, id: id)
    }

    // MARK: Info

    public func info() throws -> DeviceInfo {
        let fw = try request(0x00, 0x81, size: 2)
        let sn = try request(0x00, 0x82, size: 0x16)
        let serial = String(decoding: sn.prefix(22).prefix { $0 != 0 }, as: UTF8.self)
        return DeviceInfo(firmware: "\(fw[0]).\(fw[1])", serial: serial)
    }

    // MARK: Performance

    public func pollingRate() throws -> PollingRate {
        PollingRate(rawValue: try request(0x00, 0x85, size: 1)[0]) ?? .hz1000
    }

    public func setPollingRate(_ rate: PollingRate) throws {
        try request(0x00, 0x05, size: 1, [rate.rawValue])
    }

    public func dpiStages(store: UInt8 = savedStore) throws -> DPIStages {
        let a = try request(0x04, 0x86, size: 0x26, [store])
        let count = Int(min(a[2], 5))
        let stages = (0..<count).map { i -> DPIStage in
            let o = 3 + i * 7
            return DPIStage(x: UInt16(a[o + 1]) << 8 | UInt16(a[o + 2]), y: UInt16(a[o + 3]) << 8 | UInt16(a[o + 4]))
        }
        return DPIStages(active: Int(a[1]), stages: stages)
    }

    public func setDPIStages(_ s: DPIStages, store: UInt8) throws {
        var args: [UInt8] = [store, UInt8(s.active), UInt8(s.stages.count)]
        for (i, st) in s.stages.enumerated() {
            args += [UInt8(i + 1), UInt8(st.x >> 8), UInt8(st.x & 0xFF), UInt8(st.y >> 8), UInt8(st.y & 0xFF), 0, 0]
        }
        try request(0x04, 0x06, size: 0x26, args)
    }

    public func currentDPI(store: UInt8 = liveStore) throws -> DPIStage {
        let a = try request(0x04, 0x85, size: 7, [store])
        return DPIStage(x: UInt16(a[1]) << 8 | UInt16(a[2]), y: UInt16(a[3]) << 8 | UInt16(a[4]))
    }

    public func setDPI(_ st: DPIStage, store: UInt8) throws {
        try request(0x04, 0x05, size: 7, [store, UInt8(st.x >> 8), UInt8(st.x & 0xFF), UInt8(st.y >> 8), UInt8(st.y & 0xFF), 0, 0])
    }

    // MARK: Lighting

    public func effect(_ zone: LEDZone, store: UInt8 = liveStore) throws -> LightEffect {
        LightEffect.decode(try request(0x0F, 0x82, size: 0x0C, [store, zone.rawValue]))
    }

    public func setEffect(_ e: LightEffect, zone: LEDZone, store: UInt8) throws {
        let (size, args) = e.encode(store: store, zone: zone)
        try request(0x0F, 0x02, size: size, args)
    }

    public func brightness(_ zone: LEDZone, store: UInt8 = liveStore) throws -> UInt8 {
        try request(0x0F, 0x84, size: 3, [store, zone.rawValue])[2]
    }

    public func setBrightness(_ v: UInt8, zone: LEDZone, store: UInt8) throws {
        try request(0x0F, 0x04, size: 3, [store, zone.rawValue, v])
    }

    /// Host-driven lighting: one color per zone in frame column order (wheel, logo, side panel).
    /// Call `enableCustomFrame()` once, then stream frames.
    public static let frameZones: [LEDZone] = [.scrollWheel, .logo, .sidePanel]

    public func setCustomFrame(_ colors: [RGB]) throws {
        let cols = colors.prefix(Self.frameZones.count)
        var args: [UInt8] = [0, 0, 0, 0, UInt8(cols.count - 1)]
        for c in cols { args += [c.r, c.g, c.b] }
        try request(0x0F, 0x03, size: UInt8(args.count), args)
    }

    public func enableCustomFrame() throws {
        try request(0x0F, 0x02, size: 0x0C, [Self.liveStore, 0x00, 0x08])
    }

    // MARK: Buttons

    public func buttonIDs() throws -> [UInt8] {
        let a = try request(0x02, 0x84, size: 0x50, [0x01])
        return Array(a[1..<(1 + Int(min(a[0], 79)))])
    }

    public func action(button: UInt8, layer: Layer, profile: UInt8 = 0) throws -> ButtonAction {
        let a = try request(0x02, 0x8C, size: 0x0A, [profile, button, layer.rawValue])
        let len = Int(min(a[4], 5))
        return ButtonAction.decode(type: a[3], params: Array(a[5..<(5 + len)]))
    }

    public func setAction(_ action: ButtonAction, button: UInt8, layer: Layer, profile: UInt8) throws {
        try request(0x02, 0x0C, size: 0x0A, [profile, button, layer.rawValue] + action.encoded)
    }
}

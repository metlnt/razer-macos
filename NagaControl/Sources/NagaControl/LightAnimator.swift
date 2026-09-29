import Darwin
import Foundation
import NagaKit

/// Software lighting effects rendered by the app and streamed to the mouse as custom frames.
enum AnimationKind: String, CaseIterable, Identifiable, Codable {
    case breathing, colorCycle, rainbow, wave, strobe, heartbeat, fire, cpu
    var id: String { rawValue }

    var title: String {
        switch self {
        case .breathing: return String(localized: "Breathing")
        case .colorCycle: return String(localized: "Color cycle")
        case .rainbow: return String(localized: "Rainbow")
        case .wave: return String(localized: "Wave")
        case .strobe: return String(localized: "Strobe")
        case .heartbeat: return String(localized: "Heartbeat")
        case .fire: return String(localized: "Fire")
        case .cpu: return String(localized: "CPU load")
        }
    }

    var usesPalette: Bool { self != .rainbow }
}

struct AnimationSettings: Codable, Equatable {
    var enabled = false
    var kind: AnimationKind = .breathing
    var speed: Double = 1          // 0.25 ... 4 (×)
    var brightness: Double = 1     // 0 ... 1
    var palette: [RGB] = [RGB(0x00, 0x57, 0xB7), RGB(0xFF, 0xD7, 0x00)]

    static let maxColors = 8

    static func load() -> AnimationSettings {
        guard let data = UserDefaults.standard.data(forKey: "animation"),
              let s = try? JSONDecoder().decode(AnimationSettings.self, from: data) else { return AnimationSettings() }
        return s
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: "animation") }
    }
}

struct PalettePreset: Identifiable {
    let name: String
    let colors: [RGB]
    var id: String { name }

    static let all: [PalettePreset] = [
        PalettePreset(name: "Ukraine", colors: [RGB(0x00, 0x57, 0xB7), RGB(0xFF, 0xD7, 0x00)]),
        PalettePreset(name: "Razer", colors: [RGB(0x44, 0xD6, 0x2C), RGB(0x00, 0x40, 0x00)]),
        PalettePreset(name: "Sunset", colors: [RGB(0xFF, 0x3C, 0x00), RGB(0xFF, 0x00, 0x6E), RGB(0x8A, 0x00, 0xFF)]),
        PalettePreset(name: "Ocean", colors: [RGB(0x00, 0x2B, 0xFF), RGB(0x00, 0xC8, 0xFF), RGB(0x00, 0xFF, 0x9C)]),
        PalettePreset(name: "Neon", colors: [RGB(0xFF, 0x00, 0xE6), RGB(0x00, 0xF0, 0xFF), RGB(0xB4, 0xFF, 0x00)]),
        PalettePreset(name: "Police", colors: [RGB(0xFF, 0x00, 0x00), RGB(0x00, 0x30, 0xFF)]),
        PalettePreset(name: "Status", colors: [RGB(0x00, 0xFF, 0x40), RGB(0xFF, 0xC0, 0x00), RGB(0xFF, 0x00, 0x00)]),
    ]
}

/// Pure frame renderer: time → one color per zone.
struct AnimationRenderer {
    var settings: AnimationSettings
    var cpuLoad: Double = 0
    private var flicker = [Double](repeating: 0.8, count: 3)

    init(settings: AnimationSettings) { self.settings = settings }

    mutating func frame(at t: Double, zones: Int) -> [RGB] {
        let s = settings
        let p = s.palette.isEmpty ? [RGB(255, 255, 255)] : s.palette
        let v = t * s.speed
        var out: [RGB] = []
        for z in 0..<zones {
            let c: (Double, Double, Double)
            switch s.kind {
            case .breathing:
                let period = 3.0
                let cycle = v / period
                let level = (1 - cos(2 * .pi * cycle.truncatingRemainder(dividingBy: 1))) / 2
                c = scale(p[Int(cycle) % p.count], level * level)
            case .colorCycle:
                c = blend(p, v / 2)
            case .rainbow:
                c = hsv((v * 0.15 + Double(z) * 0.18).truncatingRemainder(dividingBy: 1))
            case .wave:
                c = blend(p, v / 2 + Double(z) * 0.5)
            case .strobe:
                let f = v * 3
                let on = f.truncatingRemainder(dividingBy: 1) < 0.35
                c = on ? scale(p[Int(f) % p.count], 1) : (0, 0, 0)
            case .heartbeat:
                let beat = v / 1.2
                let x = beat.truncatingRemainder(dividingBy: 1)
                let level = max(exp(-x * 18), 0.7 * exp(-max(0, x - 0.22) * 18) * (x >= 0.22 ? 1 : 0))
                c = scale(p[Int(beat) % p.count], level)
            case .fire:
                flicker[z % 3] += (Double.random(in: 0.35...1) - flicker[z % 3]) * min(1, 0.25 * s.speed)
                let f = flicker[z % 3]
                let base = p.count > 1 ? lerp(p[0], p[1], 1 - f) : scale(p[0], 1)
                c = (base.0 * f, base.1 * f, base.2 * f)
            case .cpu:
                let base = blend(p, cpuLoad * Double(max(p.count - 1, 0)), wrap: false)
                let pulse = 0.75 + 0.25 * sin(2 * .pi * t * (0.3 + cpuLoad * 2.5) * s.speed)
                c = (base.0 * pulse, base.1 * pulse, base.2 * pulse)
            }
            out.append(RGB(byte(c.0 * s.brightness), byte(c.1 * s.brightness), byte(c.2 * s.brightness)))
        }
        return out
    }

    private func byte(_ x: Double) -> UInt8 { UInt8(max(0, min(255, x.rounded()))) }
    private func scale(_ c: RGB, _ k: Double) -> (Double, Double, Double) { (Double(c.r) * k, Double(c.g) * k, Double(c.b) * k) }

    private func lerp(_ a: RGB, _ b: RGB, _ k: Double) -> (Double, Double, Double) {
        (Double(a.r) + (Double(b.r) - Double(a.r)) * k,
         Double(a.g) + (Double(b.g) - Double(a.g)) * k,
         Double(a.b) + (Double(b.b) - Double(a.b)) * k)
    }

    /// Smoothly walks through the palette; `pos` is measured in colors.
    private func blend(_ p: [RGB], _ pos: Double, wrap: Bool = true) -> (Double, Double, Double) {
        guard p.count > 1 else { return scale(p[0], 1) }
        if !wrap {
            let x = min(max(pos, 0), Double(p.count - 1))
            let i = min(Int(x), p.count - 2)
            return lerp(p[i], p[i + 1], x - Double(i))
        }
        let x = pos.truncatingRemainder(dividingBy: Double(p.count))
        let i = Int(x)
        let k = x - Double(i)
        return lerp(p[i], p[(i + 1) % p.count], k * k * (3 - 2 * k))
    }

    private func hsv(_ h: Double) -> (Double, Double, Double) {
        let x = h * 6
        let f = x - floor(x)
        switch Int(x) % 6 {
        case 0: return (255, 255 * f, 0)
        case 1: return (255 * (1 - f), 255, 0)
        case 2: return (0, 255, 255 * f)
        case 3: return (0, 255 * (1 - f), 255)
        case 4: return (255 * f, 0, 255)
        default: return (255, 0, 255 * (1 - f))
        }
    }
}

/// Samples total CPU usage between calls.
final class CPUMonitor {
    private var last: (busy: UInt64, total: UInt64)?

    func sample() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let t = info.cpu_ticks
        let busy = UInt64(t.0) + UInt64(t.1) + UInt64(t.3)   // user + system + nice
        let total = busy + UInt64(t.2)                        // + idle
        defer { last = (busy, total) }
        guard let last, total > last.total else { return 0 }
        return Double(busy - last.busy) / Double(total - last.total)
    }
}

import AppKit
import NagaKit
import SwiftUI

@main
struct NagaControlApp: App {
    @StateObject private var store = DeviceStore()

    init() {
        // Allows running the bare executable (swift run) as a regular windowed app.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async { NSApplication.shared.activate(ignoringOtherApps: true) }
    }

    var body: some Scene {
        WindowGroup("Naga Control") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowResizability(.contentMinSize)

    }
}

enum Section: String, CaseIterable, Identifiable {
    case buttons, performance, lighting, device
    var id: String { rawValue }
    var title: String {
        switch self {
        case .buttons: return "Кнопки"
        case .performance: return "DPI и опрос"
        case .lighting: return "Подсветка"
        case .device: return "Устройство"
        }
    }
    var icon: String {
        switch self {
        case .buttons: return "computermouse"
        case .performance: return "speedometer"
        case .lighting: return "lightbulb"
        case .device: return "info.circle"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var store: DeviceStore
    @State private var section: Section? = .buttons

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $section) { s in
                Label(s.title, systemImage: s.icon).tag(s)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
            .safeAreaInset(edge: .bottom) { StatusBadge().padding(12) }
        } detail: {
            Group {
                switch store.status {
                case .searching:
                    ContentUnavailableView("Мышь не найдена", systemImage: "cable.connector",
                                           description: Text("Подключите Razer Naga Trinity по USB."))
                case .loading where store.info == nil:
                    ProgressView("Читаю настройки мыши…")
                case .error(let msg) where store.info == nil:
                    ContentUnavailableView {
                        Label("Ошибка связи", systemImage: "exclamationmark.triangle")
                    } description: { Text(msg) } actions: {
                        Button("Повторить") { store.connect() }
                    }
                default:
                    switch section ?? .buttons {
                    case .buttons: ButtonsView()
                    case .performance: PerformanceView()
                    case .lighting: LightingView()
                    case .device: DeviceView()
                    }
                }
            }
            .navigationTitle((section ?? .buttons).title)
        }
        .overlay(alignment: .bottom) {
            if let toast = store.toast {
                Text(toast)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toast)
    }
}

struct StatusBadge: View {
    @EnvironmentObject var store: DeviceStore

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text("Naga Trinity").font(.caption.weight(.semibold))
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var color: Color {
        switch store.status {
        case .ready: return .green
        case .loading: return .yellow
        case .searching: return .gray
        case .error: return .red
        }
    }

    private var label: String {
        switch store.status {
        case .ready: return "Подключена"
        case .loading: return "Чтение…"
        case .searching: return "Не подключена"
        case .error: return "Ошибка"
        }
    }
}

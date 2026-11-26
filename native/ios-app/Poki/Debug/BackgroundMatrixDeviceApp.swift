#if POKI_STRIPPED_MATRIX_LAB
import SwiftUI

#if DEBUG && POKI_BACKGROUND_MATRIX_DEVICE
@main
struct BackgroundMatrixDeviceApp: App {
    var body: some Scene {
        WindowGroup { BackgroundMatrixDeviceView() }
    }
}

private struct BackgroundMatrixDeviceView: View {
    @State private var enabled = false
    @State private var safetyPassed = false
    @State private var locked = false
    @State private var ranAutomatic = false
    @State private var run: BackgroundMatrixProbe?
    @State private var status: LocalizedStringKey = "Ready for the safety check"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable this Lab trial", isOn: $enabled)
                        .disabled(locked || run != nil)
                    Button(safetyPassed ? "Start fixture trials" : "Start safety check") {
                        guard enabled, !locked, run == nil else { return }
                        begin(automated: false, safety: !safetyPassed)
                    }
                    .disabled(!enabled || locked || run != nil)
                    Button("Stop", role: .destructive) {
                        run?.cancel(local: true)
                        status = "Lab is stopping"
                    }
                    .disabled(run == nil)
                } footer: {
                    Text(status)
                }
            }
            .navigationTitle("Poki Lab")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active, !ranAutomatic, UserDefaults.standard.bool(forKey: "pokiDeviceMatrixAuto"),
               let value = UserDefaults.standard.string(forKey: "pokiDeviceMatrixLane"),
               ["safety", "controls"].contains(value) {
                ranAutomatic = true
                begin(automated: true, safety: value == "safety")
            }
        }
    }

    private func begin(automated: Bool, safety: Bool) {
        guard run == nil, !locked else { return }
        run = BackgroundMatrixProbe.startLocal(safety: safety, automated: automated) { passed in
            run = nil
            enabled = false
            if passed && safety && !automated {
                safetyPassed = true
                status = "Safety check passed"
            } else {
                locked = true
                status = passed ? "Fixture trials finished" : "Lab stopped. Do not retry"
            }
        }
        status = run != nil ? "Lab trial running" : "Lab could not start"
    }
}
#else
@main
struct DisabledBackgroundMatrixDeviceApp: App {
    var body: some Scene {
        WindowGroup { Text("Poki Lab").accessibilityIdentifier("lab-disabled") }
    }
}
#endif
#endif

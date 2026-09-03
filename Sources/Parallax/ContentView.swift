import ParallaxCore
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    private let models = [
        ("mug", "Tasse", "Henkel rechts — von der Seite ein anderes Profil"),
        ("bust", "Büste", "Kopf mit Nase und Augen. Blick von der Seite zeigt das Ohr"),
        ("car", "Auto", "Karosserie, Räder, Kanzel. Bug ragt nach vorn"),
        ("import", "Import", "OBJ, STL, DAE, USD, USDZ, SCN, PLY"),
    ]

    var body: some View {
        ZStack {
            ParallaxTheme.bg
            HologramView(controller: model.hologram)
                .ignoresSafeArea()
            gazeReticle
            VStack {
                header
                Spacer()
                HStack(alignment: .bottom) {
                    trackingPanel
                    Spacer()
                    VStack(alignment: .trailing, spacing: 12) {
                        modelPanel
                        telemetry
                    }
                }
            }
            .padding(24)
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var gazeReticle: some View {
        GeometryReader { geo in
            let x = geo.size.width * CGFloat(0.5 + model.eye.x / 0.28 * 0.42)
            let y = geo.size.height * CGFloat(0.5 - model.eye.y / 0.18 * 0.38)
            Circle()
                .stroke(ParallaxTheme.live.opacity(0.8), lineWidth: 1.2)
                .frame(width: 28, height: 28)
                .overlay(Circle().fill(ParallaxTheme.live).frame(width: 5, height: 5))
                .position(
                    x: min(geo.size.width - 40, max(40, x)),
                    y: min(geo.size.height - 40, max(40, y))
                )
                .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("SPATIAL DISPLAY")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(ParallaxTheme.muted)
                Text("Parallax")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.6)
                    .foregroundStyle(ParallaxTheme.fg)
                Text("Holografisches 3-D auf dem 2-D-Bildschirm. Die Kamera liest deine Augen — das Modell bleibt, du schaust um es herum. Kein Hand-Tracking.")
                    .font(.system(size: 13))
                    .foregroundStyle(ParallaxTheme.muted)
                    .frame(maxWidth: 320, alignment: .leading)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(model.live ? ParallaxTheme.live : ParallaxTheme.muted)
                    .frame(width: 6, height: 6)
                Text(model.live ? "TRACKING LIVE" : model.searching ? "SUCHE GESICHT" : model.mode == "mouse" ? "MAUS-PARALLAX" : "DEMO-ORBIT")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ParallaxTheme.fg)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ParallaxTheme.surface.opacity(0.85), in: Capsule())
            .overlay(Capsule().stroke(ParallaxTheme.fg.opacity(0.12)))
        }
    }

    private var trackingPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("EYE TRACKING")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(ParallaxTheme.muted)
                Spacer()
                Text(model.live ? "IRIS LOCK" : model.searching ? "SUCHE" : "IDLE")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(model.live ? ParallaxTheme.live : ParallaxTheme.muted)
            }
            EyeTrackingOverlay(
                preview: model.camera.preview,
                left: model.eyes?.left,
                right: model.eyes?.right,
                face: model.eyes?.face,
                tracking: model.live
            )
            .frame(height: 168)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                mono("X \(fmt(model.eye.x)) m")
                mono("Y \(fmt(model.eye.y)) m")
                mono("Z \(fmt(model.eye.z)) m")
                mono(model.eyes.map { $0.ipd > 0 ? String(format: "IPD %.3f", $0.ipd) : "IPD —" } ?? "IPD —")
            }

            if let err = model.camera.errorMessage {
                Text(err).font(.system(size: 12)).foregroundStyle(ParallaxTheme.danger)
            }

            HStack(spacing: 8) {
                Button(model.cameraActive ? "Kamera stoppen" : "Kamera starten") {
                    if model.cameraActive { model.stopCamera() } else { model.startCamera() }
                }
                .buttonStyle(PrimaryButtonStyle(filled: !model.cameraActive))
                Button("Demo") { model.stopCamera() }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
            }
        }
        .padding(12)
        .frame(width: 340)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ParallaxTheme.fg.opacity(0.12)))
    }

    private var modelPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MODELL")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(ParallaxTheme.muted)
            ForEach(models, id: \.0) { item in
                Button {
                    model.setModel(item.0)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.1)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(model.modelId == item.0 ? ParallaxTheme.bg : ParallaxTheme.fg)
                        Text(item.0 == "import" && model.importName != nil ? model.importName! : item.2)
                            .font(.system(size: 11))
                            .foregroundStyle(model.modelId == item.0 ? ParallaxTheme.bg.opacity(0.7) : ParallaxTheme.muted)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        model.modelId == item.0 ? ParallaxTheme.silver : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
            }
            Button("Datei wählen") { model.pickImport() }
                .buttonStyle(PrimaryButtonStyle(filled: false))
            if let err = model.importError {
                Text(err).font(.system(size: 11)).foregroundStyle(ParallaxTheme.danger)
            }

            Text("GRÖSSE")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(ParallaxTheme.muted)
                .padding(.top, 6)
            Slider(
                value: Binding(get: { Double(model.modelScale) }, set: { model.setScale(Float($0)) }),
                in: 0.4...2.4
            )
            Text(String(format: "%.2f×", model.modelScale))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ParallaxTheme.muted)

            Text("EMPFINDLICHKEIT")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(ParallaxTheme.muted)
                .padding(.top, 6)
            Slider(
                value: Binding(get: { Double(model.sensitivity) }, set: { model.sensitivity = Float($0) }),
                in: 0.6...1.8
            )
            Text(String(format: "%.2f×", model.sensitivity))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ParallaxTheme.muted)
        }
        .padding(12)
        .frame(width: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ParallaxTheme.fg.opacity(0.12)))
    }

    private var telemetry: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TELEMETRIE")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(ParallaxTheme.muted)
            row("FPS", "\(model.fps)")
            row("Modus", model.mode)
            row("Links", coord(model.eyes?.left))
            row("Rechts", coord(model.eyes?.right))
            row("Lock", model.live ? "ja" : "nein")
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ParallaxTheme.fg.opacity(0.12)))
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(ParallaxTheme.muted)
            Spacer()
            Text(v).foregroundStyle(ParallaxTheme.fg)
        }
        .font(.system(size: 11, design: .monospaced))
    }

    private func mono(_ t: String) -> some View {
        Text(t).font(.system(size: 11, design: .monospaced)).foregroundStyle(ParallaxTheme.muted)
    }

    private func coord(_ p: CGPoint?) -> String {
        guard let p else { return "—" }
        return String(format: "%.0f/%.0f", p.x * 100, p.y * 100)
    }

    private func fmt(_ n: Float) -> String {
        let sign = n < 0 ? "−" : "+"
        return sign + String(format: "%.3f", abs(n))
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .foregroundStyle(filled ? ParallaxTheme.bg : ParallaxTheme.fg)
            .background(filled ? ParallaxTheme.silver : ParallaxTheme.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(ParallaxTheme.fg.opacity(filled ? 0 : 0.12)))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

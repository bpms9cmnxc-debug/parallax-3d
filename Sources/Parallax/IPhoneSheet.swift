import AppKit
import ParallaxCore
import SwiftUI

struct IPhoneSheet: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("IPHONE LIDAR + KAMERA")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(ParallaxTheme.muted)
            Text(model.iphone.connected ? "Verbunden" : "Nicht verbunden")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(model.iphone.connected ? ParallaxTheme.live : ParallaxTheme.fg)

            statusBlock

            VStack(alignment: .leading, spacing: 8) {
                Text("So hängt das iPhone am Mac")
                    .font(.system(size: 14, weight: .medium))
                Text("1. iPhone 12 Pro oder neuer (LiDAR auf der Rückseite).\n2. iPhone oben auf den Monitor, Display vom dir weg — wie eine Webcam.\n3. Rückkamera und LiDAR zeigen auf dein Gesicht.\n4. Gleiches WLAN, oder iPhone nah am Mac (Peer-to-Peer).\n5. Auf dem iPhone „Parallax Track“ starten, „Senden an den Mac“.\n6. Lokalnetz erlauben, wenn iOS fragt.")
                    .font(.system(size: 13))
                    .foregroundStyle(ParallaxTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                row("Mac", model.iphone.hostName)
                row("Adresse", "\(model.iphone.ipAddress):\(TrackerPacket.port)")
                row("Bonjour", TrackerPacket.bonjourType)
                if let p = model.iphone.latest {
                    row("LiDAR Z", String(format: "%.0f cm", p.z * 100))
                    row("Quelle", p.source)
                    row("Qualität", String(format: "%.0f %%", p.quality * 100))
                }
            }
            .padding(12)
            .background(ParallaxTheme.bg.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            Text("Parallax Track liegt im Release als ParallaxTrack-iOS.zip. In Xcode öffnen (Personal Team), aufs iPhone. Ohne LiDAR: TrueDepth-Frontkamera in der iPhone-App.")
                .font(.system(size: 12))
                .foregroundStyle(ParallaxTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            cameraPicker

            HStack(spacing: 8) {
                Button("Mitte setzen") { model.zeroIPhone() }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                    .disabled(!model.iphone.connected)
                Button("Listener neu") { model.iphone.start() }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                Spacer()
                Button("Schließen") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle(filled: true))
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(ParallaxTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ParallaxTheme.fg.opacity(0.12)))
        .onAppear { model.refreshCameras() }
    }

    private var statusBlock: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(model.iphone.connected ? ParallaxTheme.live : ParallaxTheme.muted)
                .frame(width: 10, height: 10)
            Text(model.iphone.status)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(ParallaxTheme.fg)
            Spacer()
        }
        .padding(10)
        .background(ParallaxTheme.bg.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    private var cameraPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MAC-KAMERA")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(ParallaxTheme.muted)
            Text("Continuity: iPhone in der Nähe als Kamera (ohne LiDAR). Für echten Abstand die App Parallax Track.")
                .font(.system(size: 12))
                .foregroundStyle(ParallaxTheme.muted)
            if !model.cameras.isEmpty {
                Picker("Kamera", selection: Binding(
                    get: { model.cameraID },
                    set: { model.setCamera($0) }
                )) {
                    ForEach(model.cameras, id: \.id) { d in
                        Text(d.name).tag(d.id)
                    }
                }
                .labelsHidden()
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(ParallaxTheme.muted)
            Spacer()
            Text(v).foregroundStyle(ParallaxTheme.fg)
        }
        .font(.system(size: 12, design: .monospaced))
    }
}

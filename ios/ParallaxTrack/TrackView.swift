import ARKit
import SceneKit
import SwiftUI

struct TrackView: View {
    @StateObject private var session = TrackerSession()

    var body: some View {
        ZStack {
            CameraBackdrop(session: session.ar)
                .ignoresSafeArea()
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                Text("PARALLAX TRACK")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(.white.opacity(0.6))
                Text("iPhone → Mac")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Zwei Modi: LiDAR-Rückseite (iPhone wie eine Webcam oben auf den Mac) oder TrueDepth-Frontkamera (Display zu dir). Abstand in Metern an Parallax 3D.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))

                Picker("Sensor", selection: $session.mode) {
                    ForEach(CaptureMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: session.mode) { _, _ in
                    if session.running { session.start() }
                }

                HStack {
                    Circle()
                        .fill(session.sending ? Color(red: 0.37, green: 0.92, blue: 0.83) : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(session.status)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    row("Abstand", String(format: "%.0f cm", session.z * 100))
                    row("X", String(format: "%+.3f m", session.x))
                    row("Y", String(format: "%+.3f m", session.y))
                    row("LiDAR", session.hasLidar ? "ja" : "nein")
                    row("TrueDepth", session.hasTrueDepth ? "ja" : "nein")
                    row("Qualität", String(format: "%.0f %%", session.quality * 100))
                }
                .padding(12)
                .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))

                TextField("Mac-IP (optional, z. B. 192.168.1.12)", text: $session.manualHost)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.numbersAndPunctuation)
                    .padding(10)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)

                Button(session.running ? "Stoppen" : "Senden an den Mac") {
                    session.running ? session.stop() : session.start()
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color(red: 0.77, green: 0.80, blue: 0.84), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color(red: 0.03, green: 0.03, blue: 0.04))
                .font(.system(size: 16, weight: .semibold))

                Spacer()
            }
            .padding(22)
        }
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(v).foregroundStyle(.white)
        }
        .font(.system(size: 13, design: .monospaced))
    }
}

struct CameraBackdrop: UIViewRepresentable {
    let session: ARSession
    func makeUIView(context: Context) -> ARSCNView {
        let v = ARSCNView()
        v.session = session
        v.scene = SCNScene()
        v.automaticallyUpdatesLighting = false
        return v
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {
        uiView.session = session
    }
}

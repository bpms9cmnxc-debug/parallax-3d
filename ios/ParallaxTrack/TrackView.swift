import SwiftUI

struct TrackView: View {
    @StateObject private var session = TrackerSession()

    var body: some View {
        ZStack {
            Color(red: 0.027, green: 0.031, blue: 0.039).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16) {
                Text("PARALLAX TRACK")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.62))
                Text("iPhone LiDAR")
                    .font(.system(size: 28, weight: .semibold))
                Text("Rückkamera auf dich, iPhone oben an den Mac. LiDAR misst den Abstand, das Gesicht liefert X/Y. Nur Eye-Tracking, keine Hände.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.62))

                HStack {
                    Circle()
                        .fill(session.sending ? Color(red: 0.37, green: 0.92, blue: 0.83) : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(session.status)
                        .font(.system(size: 13, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 6) {
                    row("Abstand", String(format: "%.0f cm", session.z * 100))
                    row("X", String(format: "%+.3f m", session.x))
                    row("Y", String(format: "%+.3f m", session.y))
                    row("LiDAR", session.hasLidar ? "ja" : "nein — TrueDepth/Schätzung")
                    row("Qualität", String(format: "%.0f %%", session.quality * 100))
                }
                .padding(12)
                .background(Color(red: 0.07, green: 0.08, blue: 0.10), in: RoundedRectangle(cornerRadius: 12))

                Button(session.running ? "Stoppen" : "Senden an den Mac") {
                    session.running ? session.stop() : session.start()
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(red: 0.77, green: 0.80, blue: 0.84), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color(red: 0.03, green: 0.03, blue: 0.04))

                Spacer()
            }
            .padding(24)
        }
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).foregroundStyle(Color(red: 0.55, green: 0.58, blue: 0.62))
            Spacer()
            Text(v)
        }
        .font(.system(size: 13, design: .monospaced))
    }
}

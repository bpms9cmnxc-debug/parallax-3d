import AppKit
import CoreGraphics
import ParallaxCore
import SwiftUI

struct CalibrationWizard: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var draft = Calibration()
    @State private var hint = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("KALIBRIERUNG")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundStyle(ParallaxTheme.muted)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(ParallaxTheme.fg)
            Text(bodyText)
                .font(.system(size: 13))
                .foregroundStyle(ParallaxTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if step == 1 {
                HStack {
                    Text(String(format: "Bildschirm  %.0f × %.0f cm", draft.screenW * 100, draft.screenH * 100))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(ParallaxTheme.fg)
                    Spacer()
                }
            }

            if !hint.isEmpty {
                Text(hint).font(.system(size: 12)).foregroundStyle(ParallaxTheme.danger)
            }

            HStack(spacing: 8) {
                Button("Abbrechen") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle(filled: false))
                Spacer()
                if step > 0 {
                    Button("Zurück") { step -= 1; hint = "" }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                }
                Button(primaryTitle) { advance() }
                    .buttonStyle(PrimaryButtonStyle(filled: true))
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(ParallaxTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(ParallaxTheme.fg.opacity(0.12)))
        .onAppear {
            let m = ScreenMeasure.fallbackScreen()
            draft.screenW = m.w
            draft.screenH = m.h
            draft.iphoneOffsetY = m.h * 0.5 + 0.04
            draft.depth = model.hologramDepth
        }
    }

    private var title: String {
        switch step {
        case 0: return "Fenster = Bildschirm"
        case 1: return "Mitte"
        case 2: return "Linke Kante"
        case 3: return "Rechte Kante"
        case 4: return "iPhone LiDAR"
        default: return "Fertig"
        }
    }

    private var bodyText: String {
        switch step {
        case 0:
            return "Das Display ist ein Fenster. Damit Umschauen echt wirkt, muss die virtuelle Scheibe dieselbe Größe haben wie dein Monitor — und deine Augen müssen in echten Metern davor sitzen."
        case 1:
            return "Setz dich gerade hin, Blick auf die Bildschirmmitte, etwa eine Armlänge Abstand. Kamera an. Dann „Mitte speichern“."
        case 2:
            return "Schieb den Kopf seitlich, bis er ungefähr über der linken Displaykante sitzt — als würdest du um den linken Rahmen schauen. Dann speichern."
        case 3:
            return "Dasselbe rechts: Kopf über der rechten Kante, speichern. Daraus wird die echte Geometrie (links = −halbe Breite)."
        case 4:
            return "Optional: iPhone 12 Pro oder neuer oben an den Mac, Rückkamera + LiDAR auf dich. App „Parallax Track“ starten (im Repo unter ios/). LiDAR misst den Abstand in Zentimetern — dann fühlt sich Vor- und Zurücklehnen richtig an. Ohne iPhone reicht die Webcam."
        default:
            return "Kalibrierung liegt. 3D-Stärke bei 1,0 ist physikalisch; höher = theatralischer. Hologramm-Tiefe schiebt das Modell hinter die Scheibe, damit du wirklich um es herumschaust."
        }
    }

    private var primaryTitle: String {
        switch step {
        case 0: return "Weiter"
        case 1: return "Mitte speichern"
        case 2: return "Links speichern"
        case 3: return "Rechts speichern"
        case 4: return model.iphone.connected ? "LiDAR übernehmen" : "Ohne iPhone weiter"
        default: return "Fertig"
        }
    }

    private func advance() {
        hint = ""
        switch step {
        case 0:
            step = 1
        case 1, 2, 3:
            guard let s = model.faceSample() else {
                hint = "Kein Gesicht — Kamera starten und ins Bild setzen."
                return
            }
            if step == 1 {
                draft.centerNX = s.nx
                draft.centerNY = s.ny
                draft.ipdAtCenter = s.ipd
                draft.zAtCenter = OffAxis.clampedDistance(ipdNorm: s.ipd)
            } else if step == 2 {
                draft.leftNX = s.nx
            } else {
                draft.rightNX = s.nx
                if abs(draft.rightNX - draft.leftNX) < 0.08 {
                    hint = "Links und rechts sind zu nah. Etwas weiter zur Kante."
                    return
                }
            }
            step += 1
        case 4:
            draft.completed = true
            model.applyCalibration(draft)
            step = 5
        default:
            dismiss()
        }
    }
}

extension ScreenMeasure {
    static func fallbackScreen() -> (w: Float, h: Float) {
        guard let screen = NSScreen.main else { return (0.30, 0.19) }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let id: CGDirectDisplayID
        if let num = screen.deviceDescription[key] as? NSNumber {
            id = CGDirectDisplayID(num.uint32Value)
        } else {
            id = CGMainDisplayID()
        }
        let mm = CGDisplayScreenSize(id)
        guard mm.width > 40 else { return (0.30, 0.19) }
        return (Float(mm.width / 1000), Float(mm.height / 1000))
    }
}

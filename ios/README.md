# Parallax Track (iPhone)

LiDAR + Kamera als Abstandssensor für **Parallax 3D** auf dem Mac.

## Gerät

- iPhone **12 Pro / 13 Pro / 14 Pro / 15 Pro / 16 Pro** (LiDAR auf der Rückseite)
- Ohne LiDAR: Abstand aus der Gesichtsgröße, ungenauer

## Setup

1. iPhone **oben an den Mac** (Continuity-Halter oder anlehnen), **Rückkamera auf dich**
2. Mac: Parallax 3D starten, **Kalibrieren** durchlaufen
3. Dieses Projekt in Xcode öffnen:
   - File → New → Project → iOS App, Name `Parallax Track`, Bundle `dev.parallax.track`
   - Dateien aus diesem Ordner ersetzen (`ParallaxTrackApp.swift`, `TrackView.swift`, `TrackerSession.swift`)
   - Info: Kamera + lokales Netz (Plist in diesem Ordner)
4. Signing: dein Personal Team, aufs iPhone
5. App starten — Status **„Verbunden mit dem Mac“**
6. Kopf bewegen. Telemetrie auf dem Mac zeigt Quelle **LiDAR** und Abstand in cm

Gleiches WLAN (oder USB + Netzwerk-Sharing). Firewall: Parallax darf lokal empfangen.

Kein Hand-Tracking. Helios bleibt unberührt.

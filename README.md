# Parallax 3D

Live, brillenloses holografisches 3-D auf einem normalen Bildschirm. Die FaceTime-Kamera liest deine **Augen** (Iris L/R). Off-Axis-Frustum plus Blick-Orbit: das Modell bleibt in der Scheibe, du siehst Henkel, Ohr, Seite.

Kein Headset. Keine Brille. **Kein Hand-Tracking. Kein Browser, kein HTML.**

Optisch inspiriert von der räumlichen Kamera-Idee hinter [Helios](https://github.com/bpms9cmnxc-debug/Helios) — Helios selbst wird **nicht** verändert, nicht geforkt und nicht mitgeliefert.

## Download

**Nur die DMG-Datei laden, nicht Source code (zip):**

[Parallax-3D.dmg](https://github.com/bpms9cmnxc-debug/parallax-3d/releases/latest/download/Parallax-3D.dmg)

1. `Parallax-3D.dmg` doppelklicken
2. Parallax nach **Programme** ziehen
3. Erster Start: **Rechtsklick → Öffnen** (Gatekeeper, Ad-hoc-Signatur)
4. Kamera erlauben
5. **Kalibrieren** (oben rechts): Mitte, dann Kopf an die linke und rechte Displaykante
6. Kopf langsam nach links / rechts — du schaust *um* das Modell, das Zentrum bleibt
7. Optional: iPhone Pro mit LiDAR, App `ios/ParallaxTrack`, Rückkamera auf dich
8. Unten links: Iris-Marker **L** / **R**

macOS 14–27, Apple Silicon.

## Was du siehst

- Hohle Tasse mit Henkel und Löffel, Büste mit Nase, Auto mit Rädern — von der Seite ein anderes Profil
- Objekt sitzt in der Glasscheibe: Zentrum bleibt, Volumen macht es dicker
- Raum dahinter (Fensterrahmen, Bild, Lampe) weicht mit dem Blick zurück
- Live-Kamera mit Iris-Lock. FaceTime-Spiegelung: L bleibt visuell links
- Kalibrierung: Bildschirmgröße in Metern
- iPhone LiDAR (Pro, Rückkamera) über lokales Netz (`ios/ParallaxTrack`)

## iPhone LiDAR

Siehe [ios/README.md](ios/README.md). Continuity-Kamera allein liefert kein LiDAR an den Mac.

## Technik

- **Vision** `VNDetectFaceLandmarksRequest` — Pupillen / Augen, nicht Hände
- **SceneKit** Off-Axis-Projektion + Look-around-Orbit (Zentrum bleibt)
- FaceTime-Buffer gespiegelt (`isVideoMirrored`)
- Import über NSOpenPanel + ModelIO (lokal)
- Kamera und Dateien bleiben auf dem Gerät

```
swift test
bash packaging/make-dmg.sh
```

GitHub Actions (`macos-26`) legt bei Push auf `main` die DMG als Release ab.

## Lizenz

MIT

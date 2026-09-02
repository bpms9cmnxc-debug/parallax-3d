# Parallax 3D

Live, brillenloses holografisches 3-D auf einem normalen Bildschirm. Die FaceTime-Kamera liest deine **Augen** (Iris L/R). Die Szene nutzt ein Off-Axis-Frustum: das Modell dreht sich nicht mit — du schaust *um es herum*, wie bei Spatial-Displays (Sony Spatial Reality, ASUS Spatial Vision).

Kein Headset. Keine Brille. **Kein Hand-Tracking.**

Optisch inspiriert von der räumlichen Kamera-Idee hinter [Helios](https://github.com/bpms9cmnxc-debug/Helios) — Helios selbst wird **nicht** verändert, nicht geforkt und nicht mitgeliefert.

## Download

**Nur die DMG-Datei laden, nicht Source code (zip):**

[Parallax-3D.dmg](https://github.com/bpms9cmnxc-debug/parallax-3d/releases/latest/download/Parallax-3D.dmg)

1. `Parallax-3D.dmg` doppelklicken
2. Parallax nach **Programme** ziehen
3. Erster Start: **Rechtsklick → Öffnen** (Gatekeeper, Ad-hoc-Signatur)
4. Kamera erlauben
5. Kopf langsam nach links / rechts / vor / zurück bewegen
6. Unten links siehst du, wo das Eye-Tracking lockt (Marker **L** / **R**)

macOS 14–27, Apple Silicon.

## Was du siehst

- Echtes 3-D-Modell in einem räumlichen **Gitter**. Von der Seite sieht es anders aus als von vorn.
- Objekte vor der Scheibe (z > 0) treten heraus, der Raum dahinter weicht zurück.
- Live-Kamera mit Iris-Lock und Blickwinkel in Metern (X/Y/Z).
- Modelle: Orrery, Relikt, Vessel.

## Technik

- **Vision** `VNDetectFaceLandmarksRequest` — Pupillen / Augen, nicht Hände
- **SceneKit** Off-Axis-Projektion (sheared frustum)
- Kamera lokal, nichts wird hochgeladen

```
swift test
bash packaging/make-dmg.sh
```

GitHub Actions (`macos-26`, Xcode 26/27) legt bei Push auf `main` die DMG als Release ab.

## Browser-Demo

`web/` ist dieselbe Projektion mit MediaPipe Face Landmarker, zum Ausprobieren ohne Build.

## Lizenz

MIT

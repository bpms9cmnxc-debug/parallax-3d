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
5. **Kalibrieren** (oben rechts): Mitte, dann Kopf an die linke und rechte Displaykante
6. Kopf langsam nach links / rechts / vor / zurück — du schaust *um* das Modell
7. Optional: iPhone Pro mit LiDAR, App `ios/ParallaxTrack`, Rückkamera auf dich
8. Unten links: Iris-Marker **L** / **R**. Größe, 3D-Stärke, Abstand, Hologramm-Tiefe rechts

macOS 14–27, Apple Silicon.

## Was du siehst

- Erkennbare, selbstleuchtende 3-D-Objekte (Tasse, Büste, Auto) vor einem dünnen Fensterrahmen — nicht hinter einem Drahtkäfig.
- Objekte vor der Scheibe (z > 0) treten heraus, der Raum dahinter weicht zurück.
- Live-Kamera mit Iris-Lock und Blickwinkel in Metern (X/Y/Z). FaceTime-Spiegelung: L bleibt visuell links, Blick nach rechts schaut von rechts um das Modell.
- Modelle: Tasse, Büste, Auto, plus Import auf dem Mac (OBJ, STL, DAE, USD, USDZ, SCN, PLY).
- Kalibrierung: Bildschirmgröße in Metern, Blick von den Displaykanten = echte Geometrie
- iPhone LiDAR (Pro, Rückkamera) als Abstandssensor über lokales Netz (`ios/ParallaxTrack`)
- Hologramm sitzt in der Scheibe; der Volumen-Schieber schiebt es hinter das Glas, ohne die Geometrie in Z zu strecken.

## iPhone LiDAR

Siehe [ios/README.md](ios/README.md). Continuity-Kamera allein liefert kein LiDAR an den Mac — deshalb eine kleine Companion-App, die `ARFrame.sceneDepth` am Gesicht sampelt und die Pose an den Mac schickt.

## Technik

- **Vision** `VNDetectFaceLandmarksRequest` — Pupillen / Augen, nicht Hände
- **SceneKit** Off-Axis-Projektion (sheared frustum), Simulation auf dem Render-Callback
- FaceTime-Buffer gespiegelt (`isVideoMirrored`) — Look-around-X und Overlay passen dazu
- Import über NSOpenPanel + ModelIO (lokal). GLB/GLTF/FBX sind auf dem Mac nicht unterstützt.
- Kamera und Dateien bleiben auf dem Gerät

```
swift test
bash packaging/make-dmg.sh
```

GitHub Actions (`macos-26`, Xcode 26/27) legt bei Push auf `main` die DMG als Release ab.

## Browser-Demo

`web/` ist dieselbe Off-Axis-Projektion mit MediaPipe Face Landmarker, zum Ausprobieren ohne Build. Die Web-Demo hat **keinen** Datei-Import; Formate wie GLB/FBX stehen dort nicht zur Verfügung.

## 1.4.2

- Flackern: Bildschirmmaß wird gecacht, Projektion nur bei echter Augenbewegung, Simulation auf dem SceneKit-Vsync statt einem zweiten 60-Hz-Timer.
- 3-D-Gefühl: Modelle werden nicht mehr in Z gestreckt. Volumen verschiebt das Objekt durch die Scheibe. Lateral-Gain höher, damit Kopfbewegung um die Seiten führt.
- Auto: Radachsen zeigen quer zur Fahrtrichtung (Z), nicht längs (X).
- Licht folgt dem Blickwinkel.

## Lizenz

MIT

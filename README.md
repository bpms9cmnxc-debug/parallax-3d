# Parallax 3D

Live, brillenloses holografisches 3-D auf einem normalen Bildschirm. FaceTime-Augen **oder iPhone LiDAR / TrueDepth**. Das Diorama hat drei Tiefenebenen: Flasche vor der Scheibe, Tasse in der Scheibe, Bücher dahinter.

Kein Headset. **Kein Hand-Tracking. Kein HTML.**

Helios wird nicht verändert.

## Download

- [Parallax-3D.dmg](https://github.com/bpms9cmnxc-debug/parallax-3d/releases/latest/download/Parallax-3D.dmg) — Mac
- [ParallaxTrack-iOS.zip](https://github.com/bpms9cmnxc-debug/parallax-3d/releases/latest/download/ParallaxTrack-iOS.zip) — iPhone

1. DMG: App nach Programme, Rechtsklick → Öffnen, Kamera erlauben
2. Oben rechts **iPhone LiDAR** — IP, Port, Continuity-Kamera
3. iPhone: Zip in Xcode öffnen, Personal Team, aufs Gerät. Lokalnetz erlauben
4. LiDAR-Rückseite (Pro, Display vom dir weg, oben auf den Mac) oder TrueDepth-Front
5. Mac: **Mitte setzen**. Kopf bewegen — die Flasche gleitet anders als die Bücher

macOS 14–27, Apple Silicon.

## iPhone

Siehe [ios/README.md](ios/README.md). Continuity-Kamera allein liefert kein LiDAR — deshalb Parallax Track.

## Technik

- Vision (Mac) oder ARKit LiDAR / TrueDepth (iPhone)
- SceneKit Off-Axis-Frustum, Objekt bleibt in der Scheibe
- Bonjour `_parallax._tcp` Port 47331, AWDL Peer-to-Peer
- Import OBJ/STL/DAE/USD/USDZ/SCN/PLY

```
swift test
bash packaging/make-dmg.sh
```

## Lizenz

MIT

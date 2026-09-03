# Parallax Track (iPhone)

LiDAR-Rückkamera **oder** TrueDepth-Frontkamera als Abstandssensor für **Parallax 3D** auf dem Mac.

## Download

Im gleichen Release wie die Mac-DMG: **ParallaxTrack-iOS.zip**

Oder dieses Repo: `ios/ParallaxTrack.xcodeproj` in Xcode öffnen.

## Gerät

- **LiDAR Rückseite:** iPhone 12 Pro / 13 Pro / 14 Pro / 15 Pro / 16 Pro  
  iPhone **oben auf den Mac, Display von dir weg**, Rückkamera auf dein Gesicht (wie eine Webcam).
- **TrueDepth Front:** jedes iPhone mit Face ID  
  Display **zu dir**. Einfacher, Abstand etwas grober als LiDAR.

## Setup

1. Mac: Parallax 3D starten → Button **iPhone LiDAR** (oben rechts). Dort stehen IP und Port.
2. Xcode: `ParallaxTrack.xcodeproj` öffnen, Signing = dein Personal Team, aufs iPhone.
3. App starten. Lokalnetz **erlauben**.
4. Modus wählen (LiDAR oder TrueDepth), **Senden an den Mac**.
5. Status **„Verbunden mit dem Mac“**. Auf dem Mac: „LiDAR live“ oder „iPhone-Kamera live“.
6. Einmal **Mitte setzen** (Mac-Dialog), während du gerade sitzt.

Bonjour findet den Mac automatisch. Falls nicht: Mac-IP aus dem Dialog ins Feld auf dem iPhone (z. B. `192.168.1.12`).

Gleiches WLAN oder nah beieinander (AWDL/Peer-to-Peer). Firewall: Parallax darf lokal empfangen.

Kein Hand-Tracking. Helios bleibt unberührt.

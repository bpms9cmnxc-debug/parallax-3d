#!/bin/bash
# Native Parallax.app + UDZO DMG. Run on macOS 14–27 (GitHub Actions macos-26).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift test --disable-xctest || swift test

swift build -c release --arch arm64 --product Parallax
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Parallax"
test -x "$BIN"

STAGE="$(mktemp -d /tmp/parallax-app.XXXXXX)"
APP="$STAGE/Parallax.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Parallax"
chmod +x "$APP/Contents/MacOS/Parallax"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"

if [[ -f "$ROOT/macos/AppIcon.icns" ]]; then
  cp "$ROOT/macos/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
elif [[ -f "$ROOT/macos/AppIcon.png" ]]; then
  if command -v sips >/dev/null && command -v iconutil >/dev/null; then
    ICONSET="$(mktemp -d /tmp/parallax-icon.XXXXXX)"
    mkdir -p "$ICONSET/AppIcon.iconset"
    for s in 16 32 128 256 512; do
      sips -z $s $s "$ROOT/macos/AppIcon.png" --out "$ICONSET/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
      d=$((s * 2))
      sips -z $d $d "$ROOT/macos/AppIcon.png" --out "$ICONSET/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
  else
    cp "$ROOT/macos/AppIcon.png" "$APP/Contents/Resources/AppIcon.png"
  fi
fi

codesign --force --sign - \
  --deep \
  --options runtime \
  --timestamp=none \
  --entitlements "$ROOT/macos/Parallax.entitlements" \
  "$APP"

cat > "$STAGE/Liesmich.txt" <<'TXT'
Parallax 3D
===========

1. Parallax.app nach Programme ziehen
2. Beim ersten Start: Rechtsklick → Öffnen (Gatekeeper)
3. Kamera erlauben
4. Kopf bewegen — das Modell bleibt in der Scheibe, du siehst die Seite
5. Unten links: Live-Kamera mit Iris-Markern L / R

macOS 14 bis macOS 27. Apple Silicon.
Kein Hand-Tracking. Nur Eye-Tracking über die FaceTime-Kamera.
Native Swift/SceneKit. Kein HTML.
Helios wurde nicht verändert.
TXT
ln -s /Applications "$STAGE/Applications"

OUT="${1:-$ROOT/Parallax-3D.dmg}"
rm -f "$OUT"
hdiutil create \
  -volname "Parallax 3D" \
  -srcfolder "$STAGE" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  "$OUT"
rm -rf "$STAGE"
test -f "$OUT"
file "$OUT"
ls -lh "$OUT"
echo "Wrote $OUT"

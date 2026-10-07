#!/bin/zsh
# docs/icon/app-icon.svg → Resources/AppIcon.icns (렌더링에 Chrome 사용)
set -e
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP=$(mktemp -d)
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=1024,1024 \
  --default-background-color=00000000 --screenshot="$TMP/1024.png" "file://$PWD/docs/icon/app-icon.svg" >/dev/null 2>&1
SET="$TMP/AppIcon.iconset"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/1024.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/1024.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
mkdir -p Resources
iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$TMP/1024.png" docs/icon/app-icon.png
echo "Resources/AppIcon.icns 생성"

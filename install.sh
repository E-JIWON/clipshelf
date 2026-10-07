#!/bin/zsh
# 릴리즈 빌드 → Shelf.app 번들 → /Applications 설치
set -e
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64
APP=/Applications/Shelf.app
pkill -x Shelf 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/apple/Products/Release/Shelf "$APP/Contents/MacOS/Shelf"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Shelf</string>
  <key>CFBundleDisplayName</key><string>선반</string>
  <key>CFBundleIdentifier</key><string>com.bongchil.shelf</string>
  <key>CFBundleExecutable</key><string>Shelf</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"

# 예전 방식(LaunchAgent) 정리. 로그인 실행은 이제 메뉴바 > "로그인 시 실행"
AGENT=~/Library/LaunchAgents/com.bongchil.shelf.plist
if [ -f "$AGENT" ]; then launchctl bootout gui/$UID "$AGENT" 2>/dev/null || true; rm -f "$AGENT"; fi

open "$APP"
echo "설치 완료: $APP"

#!/bin/zsh
# 릴리즈 빌드 → ClipShelf.app 번들 → /Applications 설치
set -e
cd "$(dirname "$0")"
swift build -c release --arch arm64 --arch x86_64
APP=/Applications/ClipShelf.app
pkill -x ClipShelf 2>/dev/null || true; pkill -x Shelf 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/apple/Products/Release/ClipShelf "$APP/Contents/MacOS/ClipShelf"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>ClipShelf</string>
  <key>CFBundleDisplayName</key><string>ClipShelf</string>
  <key>CFBundleIdentifier</key><string>com.bongchil.clipshelf</string>
  <key>CFBundleExecutable</key><string>ClipShelf</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"

# 예전 이름(Shelf)으로 설치된 흔적 정리
rm -rf /Applications/Shelf.app
[ -d ~/Library/Caches/Shelf ] && [ ! -d ~/Library/Caches/ClipShelf ] && mv ~/Library/Caches/Shelf ~/Library/Caches/ClipShelf
# 예전 방식(LaunchAgent) 정리. 로그인 실행은 이제 메뉴바 > "로그인 시 실행"
AGENT=~/Library/LaunchAgents/com.bongchil.shelf.plist
if [ -f "$AGENT" ]; then launchctl bootout gui/$UID "$AGENT" 2>/dev/null || true; rm -f "$AGENT"; fi

open "$APP"
echo "설치 완료: $APP"

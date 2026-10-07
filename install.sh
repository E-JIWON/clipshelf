#!/bin/zsh
# 릴리즈 빌드 → Shelf.app 번들 → /Applications 설치 → 로그인 시 자동 실행
set -e
cd "$(dirname "$0")"
swift build -c release
APP=/Applications/Shelf.app
pkill -x Shelf 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Shelf "$APP/Contents/MacOS/Shelf"
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

# 로그인 시 실행 (시스템 설정 > 일반 > 로그인 항목에 "백그라운드 항목"으로 보임)
AGENT=~/Library/LaunchAgents/com.bongchil.shelf.plist
mkdir -p ~/Library/LaunchAgents
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.bongchil.shelf</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/Shelf</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST
launchctl bootout gui/$UID "$AGENT" 2>/dev/null || true
launchctl bootstrap gui/$UID "$AGENT"
echo "설치 완료: $APP (로그인 시 자동 실행)"

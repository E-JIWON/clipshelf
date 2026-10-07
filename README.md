# Shelf (선반)

macOS 화면 가장자리에 붙어 있는 임시 보관 선반. 캡처 썸네일·텍스트·파일을 끌어다 놓거나 ⌘V로 올려두고, 필요할 때 끌어서 꺼내 쓴다. [Yoink](https://eternalstorms.at/yoink/mac)의 핵심만 남긴 무료 버전.

<img src="docs/screenshot.png" width="160" alt="선반 패널">

## 동작

- **넣기**: 패널로 드래그 앤 드롭, 또는 패널 클릭 후 ⌘V. 메뉴바 아이콘에서도 "클립보드에서 추가".
- **꺼내기**: 카드를 다른 앱으로 드래그. 이미지는 파일 URL + 이미지 데이터, 텍스트는 문자열로 전달.
- **미리보기/편집**: 카드 클릭. 이미지는 Quick Look, 텍스트는 바로 편집(자동 저장).
- **숨김**: 평소엔 8px 탭만 남기고 가장자리로 들어가 있다가, 탭에 마우스를 대거나 어디서든 드래그가 시작되면 펼쳐진다.
- **위치**: 패널을 끌어다 놓으면 가까운 좌/우 가장자리에 스냅되고 기억된다. 우하단 핀을 켜면 위치 잠금 + 항상 열림.

## 구조

```
Sources/Shelf/
  ShelfApp.swift        SwiftUI App 진입점 (MenuBarExtra), AppDelegate
  ShelfPanel.swift      패널 생명주기: 숨김/펼침, 가장자리 스냅, 외부 드래그 감지, 미리보기 팝오버
  Store.swift           데이터 = 캐시 폴더. 파일 하나가 아이템 하나 (.txt는 텍스트)
  Views/
    ShelfView.swift     패널 본체, 드롭 타깃, 토스트, 핀
    Card.swift          아이템 카드 (썸네일/텍스트/파일)
    DragHandle.swift    AppKit 드래그 세션 + 호버/클릭 (SwiftUI onDrag가 file-url을 못 실어서)
    TextEditView.swift  텍스트 편집 팝오버
Tests/ShelfTests/       Store 단위 테스트
install.sh              릴리즈 빌드 → .app 번들 → /Applications → 로그인 시 자동 실행
```

설계상 선택:
- 서버·DB·설정 파일 없음. 저장소는 `~/Library/Caches/Shelf/` 폴더 그 자체. 파일명이 생성 시각이라 정렬에 메타데이터가 필요 없다.
- 폴더를 `DispatchSource`로 감시해서 바깥에서 파일이 바뀌어도 목록이 맞춰진다.
- 외부 드래그 감지는 Yoink 방식: 드래그 페이스트보드의 `changeCount` 변화를 글로벌 마우스 모니터에서 확인.

## 개발

```bash
swift run            # 개발 실행
swift test           # Store 테스트
./install.sh         # 설치 + 로그인 항목 등록
kill -USR1 $(pgrep -x Shelf)   # 패널을 ~/Library/Caches/Shelf-snapshot.png 로 저장 (UI 점검용)
```

요구사항: macOS 14+, Xcode 15+.

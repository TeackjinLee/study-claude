# 웹 실행 확인

Godot 4.7.2 기준. PC 브라우저용이다. 별도 멀티 이동 연습장 실행은 `docs/21_전용서버_브라우저_이동동기화.md`를 참고한다.

## 다시 빌드하고 실행

프로젝트 폴더에서:

```sh
godot --headless --path . --import
godot --headless --path . --export-release Web output/web/index.html
python3 tools/serve_web.py
```

브라우저에서 http://localhost:8060 을 연다. 서버 종료는 Ctrl+C.
파일을 더블클릭하는 file:// 방식은 지원하지 않는다.
일상 실행은 릴리스 빌드를 사용한다. 오류 추적이 필요할 때만 `--export-debug`를 사용한다.

## 템플릿

공식 4.7.2 export_templates.tpz 안의 templates/web_debug.zip과
web_release.zip을 output/web_templates/에 두었다. Web 프리셋이 이 경로를 사용한다.
엔진 버전을 바꾸면 같은 버전 템플릿으로 함께 교체한다.
공식 다운로드: https://github.com/godotengine/godot-builds/releases/tag/4.7.2-stable

## 웹 전용 설정

- Compatibility 렌더러와 Stream 오디오를 웹에서만 사용한다.
- 웹은 viewport stretch로 내부 해상도를 1280×720에 고정한다. Retina 화면에서 픽셀 수가 4배로 늘지 않는다.
- `http://localhost:8060/?perf=1`로 열면 5초 준비 후 10초마다 브라우저 콘솔에 WEB_PERF 측정값을 남긴다. 일반 주소에서는 측정하지 않는다.
- Noto Sans KR 글꼴을 웹 기본 글꼴로 포함한다. 라이선스: assets/fonts/OFL.txt.
- 효과음 합성 코드가 Thread를 사용하므로 스레드 지원을 켰다.
- 게임에서 직접 읽는 assets/data JSON을 포함한다.
- 제작 원본 output, 문서 docs, 테스트 tests, 제작 도구 tools는 내보내기에서 제외한다.

## 배포 서버 요건

현재 서버는 로컬 확인용이며 외부에는 공개되지 않는다.
외부 배포 시 HTTPS 및 아래 응답 헤더를 설정한다.

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

.wasm MIME은 application/wasm이어야 한다. 실제 배포는 정적 웹 서버를 사용한다.

웹은 30FPS 표시·60틱 물리를 사용하고 카메라 배율을 1.35배로 올려 한 번에 그리는 도시 범위를 줄인다.
이는 웹 전용 설정이며 데스크톱의 배율과 프레임 목표에는 적용하지 않는다.
웹 빌드는 약 162MiB(압축 전)이므로 배포 시 압축과 리소스 경량화가 필요하다.

## 확인 범위

내장 Chromium 브라우저에서 타이틀, 새 게임 진입, W 이동에 따른 화면 이동 확인.
첫 빌드에서 Emscripten 메인 스레드 blocking 경고를 관찰했다.
소리 청취, 저장 재접속, Safari/Firefox, 모바일, 장시간 성능은 별도 검증 대상이다.

## 2026-10-21 웹 성능 측정

내장 Chromium, Retina, 시작 도시 장면에서 측정했다. 다른 장면·기기에서는 달라진다.

- 초기 디버그/Retina: 평균 55.82ms, 약 18FPS, draw calls 3869.
- 릴리스/1280×720 고정: 평균 49.25ms, 약 20FPS, draw calls 3841.
- 릴리스/1280×720/웹 카메라 1.35배/30FPS 목표: 평균 34.37ms, 약 29FPS, p95 39.31ms, draw calls 2735.
- 이동 입력 후 화면 이동을 확인했다. 60FPS 달성이나 장시간 무끊김은 확인하지 않았다.
- 추가 개선은 건물의 그리기 호출 병합/캐시 작업이 필요하다.

데스크톱 Compatibility perf_probe 16초 확인(별도 브라우저 렌더링 정지 후):
- 변경 전: 주행 16.67ms/끊김 2회, 폭발 16.67ms/끊김 0회.
- 변경 후: 주행 16.67ms/끊김 2회, 폭발 16.66ms/끊김 0회.
- 회귀 테스트 17종 중 15종 PASS. traffic/police는 각 300초 제한에 걸려 완료하지 못했다.
- 초기 샌드박스 실행에서 저장 권한 때문에 실패했던 title 테스트는 사용자 데이터 쓰기 허용 후 PASS.

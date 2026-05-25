# 1. Claude Code 설치부터 실전 팁까지

## 1.설치

### Mac
``` bash
  curl -fsSL https://claude.ai/install.sh | bash
```

### Window
``` bash
  irm https://claude.ai/install.ps1 | iex
```

## 2.실전팁
### plan mode(수정 불가) -> accept edits on(수정 가능)

## 3. 초기화
``` bash
/init
```

## 5.토큰 관리
``` bash
/context
```
- 토큰을 볼수있는 command
- context가 많으면 환각을 일으키기 쉬움
- context가 가득차면 성능이 저하되고 비용이 급증하기 때문에, 아래 두 명령어를 적절히 활용하는 것이 안정적인 작업 품질과 비용 효율을 유지하는 힉심

``` bash
/clear
```
- context를 완전히 초기화하여 새 작업을 꺠끗한 상태에서 시작
  
``` bash
/compact
```
- 현재 대화 내용을 요약해 컨텍스트 윈도우 사용량을 줄여줌

### 6.세션관리
- 각터미널을 열고 작업할시 관리 명령어

``` bash
/claude --continue
```
- 방금 끝낸 Session을 불러옴

``` bash
/claude --resume
```
- 내가 내린 명령들의 history를 보여주고 거기로 들어갈 수 있음.

``` bash
/rename #명칭#
```
- 내가 나중에 찾을 history의 명칭 지정

### 7. 그 외 (whisper flow)

- git과 연동
- 터미널 알림연동
- Whisper Flow (음성입력)











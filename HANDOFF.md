# 작업 인계 (2026-10-27 기준)

다른 컴퓨터(노트북)에서 이어서 작업하기 위한 메모입니다. 맨 아래 "이어서 줄 프롬프트"를 Claude Code 에 그대로 붙여 넣으면 됩니다.

## 노트북 준비

1. 저장소 받기

```bash
git clone https://github.com/GomdorE/poketmon-red.git pokered-godot
```

2. 원본 소스 두 폴더를 저장소 폴더 **옆에** 둡니다(같은 상위 폴더 안).
   - `pokered-master` : 원작 디스어셈블리. `git clone https://github.com/pret/pokered.git pokered-master` 로 받으면 됩니다.
   - `pokered-korean` : 한글 포크. 인터넷에 없으므로 이 컴퓨터(`X:\joy2is90\pokered-master\pokered-korean`)에서 압축해 옮겨야 합니다.
   - 게임 실행만 하려면 이 두 폴더가 없어도 됩니다(`assets/` 가 저장소에 들어 있음). 하지만 원작 asm 을 읽어 포팅하는 작업과 `tools/export_data.py` 실행에는 둘 다 필요합니다.

```
상위폴더/
  pokered-godot/     <- 이 저장소
  pokered-master/    <- pret/pokered
  pokered-korean/    <- 한글 포크 (직접 복사)
```

   - pret/pokered 클론에는 빌드된 그래픽(.2bpp/.1bpp)이 없어서 `tools/export_data.py` 가 돌지 않습니다.
     RGBDS 1.0.4(https://github.com/gbdev/rgbds/releases/tag/v1.0.4 의 rgbds-win64.zip)를 받아
     `python tools/build_pokered_gfx.py <rgbgfx.exe 경로>` 를 실행하면 Makefile 규칙대로 만들어 줍니다(make·C 컴파일러 불필요).
3. Godot 4.7.2 콘솔판을 받아 두고, 아래 명령의 Godot 경로를 노트북 경로로 바꿔 씁니다.
   클래스 캐시 갱신: `Godot_v4.7.2-stable_win64_console.exe --headless --editor --quit --path .`

## 지금까지 된 것

- 1~3챕터: 오프닝 ~ 상록숲 ~ 회색시티 ~ 웅 체육관, 원작 배틀 엔진(기술 효과 68종, 트레이너 AI), 트레이너 시선 엔진.
- 오버월드 엔진: 턱 뛰어내리기, 높낮이 타일 충돌, 벌레퇴치스프레이, 필드 기술(플래시·순간이동·구멍파기·풀베기·공중날기·파도타기·괴력), 동굴탈출로프, 자전거, 낚싯대 3종, 맵 텍스트 포인터 표.
- 4챕터(Codex 작업 병합): 3번도로, 달맞이산(화석 선택), 4번도로, 블루시티(라이벌, 로켓단 TM28, 이슬 체육관, 자전거 가게, 배지 집), 24·25번도로, 빌의 집.
  검증: `python tools/chapter4_smoke.py --full` → 33개 모두 PASS.
- 병합 뒤 정리: 달맞이산 화석 구역 배틀 금지(BIT_NO_BATTLES), 블루시티 체육관 동상·빌의 PC 를 숨겨진 사물 엔진에서 처리.

## 하던 일 (멈춘 지점)

**게임 내 교환(블루시티 교환 집: 슈륙챙이 ↔ 루주라 "롤라")** 포팅 완료.

- `scripts/game/trade_anim.gd`(교환 영상), `scripts/game/in_game_trade.gd`(교환 대화), `cerulean_scripts.gd` 연결, 세이브의 `completed_trades`.
- 스모크: `trade_lola`, `trade_no`, `trade_wrong_mon` 추가 → `GODOT=<콘솔판 경로> python tools/chapter4_smoke.py --full` 36개 PASS.
  (스모크 스크립트는 이제 Godot 경로를 환경 변수 `GODOT` 로 받습니다.)
- 확인할 것: 교환 정보 상자의 라벨("──№." / "OT/" / "IDNo.")은 지금 영어 원작 그대로입니다. `pokered-korean` 의
  `engine/movie/trade2.asm` 의 Trade_MonInfoText 와 비교해 한글판이 다르면 맞춥니다(어버이 "트레이너" 가 상자 폭을 넘는지도).

## 그다음

- 4챕터 exe: `--export-release "Windows Desktop" dist/PokemonRed-Godot-Chapter4.exe` (exe 는 100 MB 가 넘어 저장소에 넣지 않음).
- 5챕터: 9·10번도로(돌산터널 앞까지), 5·6번도로·지하통로, 갈색시티(마티스·상선 S.S.안느) 순서로 진행. 필드 기술 중 알낳기(필드)만 남음.
- 게임 전체가 끝나면: 실행 파일 용량 최적화(축소 export 템플릿, PCK 분리), 저장소 정리(assets 제외 등).

## 작업 규칙 (사용자 결정)

- 모든 스타일·타이밍·텍스트·효과음은 원작과 똑같이, 엔진만 바꾼다. 손으로 만든 그래픽·임의 UI 금지.
- 한글 8×16 글꼴이 테두리나 다른 글자를 덮으면 "깨진 것" 으로 보고 한글일 때만 배치를 고친다(README 의 "원작과 다른 점" 참고).
- git 커밋 메시지는 제목·본문 모두 한글. 저장소는 공개 상태로 두고 정리는 마지막에.
- Codex 와 나눠서 하지 않고 Claude 혼자 진행.
- 테스트 키 이름은 소문자(`--keys=every:20:a`). 창 모드는 프레임 타이밍이 headless 와 다르니 스크린샷은 넉넉히.
- 자주 쓰는 테스트 인자: `--stage=map:맵,x,y --party=종:레벨 --sim=UUDDA|... --event=... --script=맵:번호 --give=도구:수 --badges=N --teach=기술 --visited=도시 --repel=N --trace-scripts --trace-battle --fast --quit-after=N`, 창 모드 `--shot=.tmp/xx/s%d.png --shot-every=N`.

## 이어서 줄 프롬프트

```text
pokered-godot (포켓몬 레드 Godot 재구현) 작업을 이어서 하자. 먼저 HANDOFF.md 와 README.md 를 읽어.
게임 내 교환은 끝났어. HANDOFF.md 의 "확인할 것"(한글판 교환 정보 상자) 을 보고,
4챕터 exe 가 없으면 빌드한 다음 5챕터로 넘어가. 원작과 똑같이, 혼자 진행하고, 커밋은 한글로.
```

# 작업 인계 (2026-10-27 밤 기준)

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

3. Godot 4.7.2 콘솔판을 받아 두고, 아래 명령의 Godot 경로를 노트북 경로로 바꿔 씁니다.
   클래스 캐시 갱신: `Godot_v4.7.2-stable_win64_console.exe --headless --editor --quit --path .`

## 지금까지 된 것

- 1~3챕터: 오프닝 ~ 상록숲 ~ 회색시티 ~ 웅 체육관, 원작 배틀 엔진(기술 효과 68종, 트레이너 AI), 트레이너 시선 엔진.
- 오버월드 엔진: 턱 뛰어내리기, 높낮이 타일 충돌, 벌레퇴치스프레이, 필드 기술(플래시·순간이동·구멍파기·풀베기·공중날기·파도타기·괴력), 동굴탈출로프, 자전거, 낚싯대 3종, 맵 텍스트 포인터 표.
- 4챕터(Codex 작업 병합): 3번도로, 달맞이산(화석 선택), 4번도로, 블루시티(라이벌, 로켓단 TM28, 이슬 체육관, 자전거 가게, 배지 집), 24·25번도로, 빌의 집.
  검증: `python tools/chapter4_smoke.py --full` → 33개 모두 PASS.
- 병합 뒤 정리: 달맞이산 화석 구역 배틀 금지(BIT_NO_BATTLES), 블루시티 체육관 동상·빌의 PC 를 숨겨진 사물 엔진에서 처리.

## 하던 일 (멈춘 지점)

**게임 내 교환(블루시티 교환 집: 쥬레곤 ↔ 롤라)** 을 포팅하던 중입니다.

- 끝난 것: 교환 표·교환 화면 그래픽/타일맵 내보내기(`assets/data/trade.json`, `trade_gfx`, `cable_ball`, `trade_bubble`), `PartyMon.ot_name / ot_id`(교환받은 포켓몬의 어버이), 능력치 화면 표시.
- 초안만 있는 것: `tools/_wip_patch_anim_trade.py` — BattleAnim 을 배틀 밖에서 쓰는 `play_trade()` 와 교환용 특수 효과(TradeHidePokemon / TradeShakePokeball / TradeJumpPokeball). 아직 적용하지 않았습니다. 경로를 확인하고 실행한 뒤 이 파일은 지웁니다.
- 남은 것:
  1. `scripts/game/trade_anim.gd` : `engine/movie/trade.asm` 의 InternalClockTradeAnim 포팅
     (게임보이 그림·케이블 스크롤, 공이 케이블로 들어가는 연출, 아이콘+원 OAM 이동, 텍스트 상자 밀어내기, 창(window) 레이어와 SCX 사용).
     원작의 자동 BG 전송 대상은 교환 중 $9C00 이므로, 우리 렌더러에서는 "글자는 bg 에, 오른쪽으로 미는 상자는 win 에" 로 옮기면 됩니다.
  2. `scripts/game/in_game_trade.gd` : `engine/events/in_game_trades.asm` 의 DoInGameTradeDialogue
     (교환 제안/거절/다른 포켓몬/고마워/교환 뒤 대사, 파티 메뉴 선택, 케이블 연결 대사, 받은 포켓몬 = 준 포켓몬 레벨·별명·어버이 "트레이너"·무작위 ID, 교환 완료 플래그 세이브).
  3. `cerulean_scripts.gd` 에 `TEXT_CERULEANTRADEHOUSE_GAMBLER` → 교환(롤라) 연결.
  4. 창 모드 스크린샷으로 교환 화면 확인 → 커밋(한글) → push → 4챕터 exe 빌드.

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
하던 일은 블루시티 교환 집의 게임 내 교환 포팅이야. HANDOFF.md 의 "하던 일" 순서대로
tools/_wip_patch_anim_trade.py 적용 → engine/movie/trade.asm 포팅(trade_anim.gd) → in_game_trades.asm 포팅(in_game_trade.gd)
→ 블루시티 교환 집 연결 → 창 모드 스크린샷 확인 → 한글 커밋·push → 4챕터 exe 빌드까지 해 줘.
그다음 5챕터로 넘어가. 원작과 똑같이, 혼자 진행하고, 커밋은 한글로.
```

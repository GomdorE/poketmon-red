# 작업 인계 (2026-10-31 기준)

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
- 게임 내 교환(블루시티 롤라, 지하통로 스폿, 갈색시티 덕스)과 교환 영상.
- 5챕터: 9·10번도로, 5·6번도로·게이트·지하통로·육아집, 갈색시티·체육관·부두(상선 출항 연출)·상선 S.S.안느 전체(라이벌·선장 비밀기술01).
- 6챕터: 11번도로·게이트, 디그다의 굴, 2번도로 동쪽, 돌산터널(어둠), 보라타운·포켓몬타워 1F/2F.
- 7챕터: 7·8번도로·게이트·지하통로(동서), 무지개시티(백화점·엘리베이터·자판기·맨션·증서·식당·체육관), 게임코너(슬롯머신·코인·경품), 로켓단 아지트(화살표 타일·비주기·리프트키).
- 8챕터: 포켓몬타워 3F~7F(유령 배틀·정화 구역·마라의 유령·후지 구출), 12번도로(게이트·슈퍼낚싯대·잠만보·포켓몬피리).
- 9챕터: 노랑시티 전체(집들·사천왕 도장·노랑체육관 순간이동 패드·초련), 실프컴퍼니 1F~11F(카드키 문·라이벌·라프라스·마스터볼·비주기·엘리베이터).
- 10챕터: 13~18번도로·게이트(자전거 검사·경험치나눔이·교환), 자전거 도로(강제 자전거·내리막), 16번도로 잠만보·비전머신02.
- 11챕터: 연분홍시티(원장 비전머신04·좋은낚싯대·독수 체육관), 사파리존(게이트·걸음 수·게임 종료·4구역·비전머신03), 사파리 배틀(볼·미끼·돌·도망).

## 하던 일 (멈춘 지점)

**11챕터 포팅 완료** (2026-11-01): 연분홍시티(센터·상점·원장 집·좋은낚싯대 집·빌 할아버지 집·회의실·독수 체육관), 사파리존(게이트·동서남북 구역·쉼터·비밀의 집),
사파리 게임(¥500·볼 30개·502걸음·게임 종료 워프)과 사파리 배틀.

- 코드: `scripts/game/map_scripts_chapter11.gd`. 엔진: `GameState.safari_balls/safari_steps`(저장), `Overworld._safari_zone_game_over()`·`_print_safari_zone_steps()`,
  `Battle.is_safari`(`_safari_battle`·`_safari_menu`·`_throw_bait_or_rock`·`_enemy_ran`, `actual_catch_rate`), LAB 타일셋, 벤치 남자는 표의 방향(왼쪽)만 봄.
  테스트 인자 `--safari=볼:걸음`, `--battle-map=맵`.
- 회귀는 작업 트리를 건드리지 않게 스크래치 폴더의 스냅샷 복사본(`dist`·`.tmp`·`.git` 제외, 약 10 MB)에서 돌림.
- 스모크: `GODOT=<콘솔판 경로> python tools/chapter11_smoke.py --full`. 4~10챕터 스모크도 PASS 해야 함(여러 Godot 를 동시에 돌리면 8챕터 유령 케이스가 흔들림).
- 아직 없는 것: 19·20번수로·쌍둥이섬(연분홍시티 남쪽 연결 막힘), 홍련섬.

## 그다음

- 11챕터 exe 는 만들어 둠(`dist/PokemonRed-Godot-Chapter11.exe`, 커밋 안 함). 다시 만들려면 `--export-release "Windows Desktop" dist/PokemonRed-Godot-Chapter11.exe`.
- 12챕터 후보: 19·20번수로(파도타기 트레이너)·쌍둥이섬(B1F~B4F 괴력 바위·해류·프리져, `force_bike_surf` 의 해류 강제 파도타기), 21번수로, 홍련섬(포켓몬 저택 1F~B1F 스위치·연구소 화석 복원·강연 체육관 퀴즈 문).
- 아직 없는 것: 알낳기(필드), 교환 포켓몬 말 안 듣기, 통신 배틀, 학습장치.
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
11챕터(연분홍시티·사파리존)는 끝났고 11챕터 exe 도 있어.
HANDOFF.md 의 "그다음" 순서대로 12챕터(19·20번수로·쌍둥이섬 → 홍련섬)로 넘어가.
원작과 똑같이, 혼자 진행하고, 커밋은 한글로. 구역마다 스모크(tools/chapter12_smoke.py 를 같은 방식으로) PASS 뒤 커밋.
```

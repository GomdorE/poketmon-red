# 작업 인계 (2026-10-28 기준)

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

## 하던 일 (멈춘 지점)

**6챕터 포팅 완료** (2026-10-28): 11번도로·게이트(오박사 조수 아이템파인더, 테리 교환) → 디그다의 굴 → 2번도로 동쪽(마르셀 교환, 조수 플래시)
→ 돌산터널(어둠 + 플래시) → 보라타운(센터·숍·탑골 집·후지 노인의 집·이름평가사·포켓몬타워 1F·2F 라이벌).

- 코드: `scripts/game/map_scripts_chapter6.gd`. 엔진: `GBScreen.pal_offset`/`Overworld.set_map_pal_offset`(어둠), 아이템파인더(bag.gd),
  테스트 인자 `--owned=N`(도감 N종 소유), `--trade-mon`(첫 포켓몬을 교환 포켓몬으로).
- 스모크: `GODOT=<콘솔판 경로> python tools/chapter6_smoke.py --full`. 4·5챕터 스모크도 PASS 해야 함.
- 아직 없는 것: 포켓몬타워 3F~7F(유령 배틀 = 실프스코프, 채널러, 마라의 유령, 후지 구출), 12번도로(잠만보·포켓몬피리 사용), 8번도로, 노랑시티 전체.

## 그다음

- 6챕터 exe: `--export-release "Windows Desktop" dist/PokemonRed-Godot-Chapter6.exe` (아직 안 만듦).
- 7챕터 후보: 7·8번도로와 지하통로(동서), 무지개시티(백화점·게임코너·로켓단 아지트(실프스코프)·민화 체육관·맨션), 그 뒤 포켓몬타워 3F~7F(유령 배틀)·12번도로(잠만보).
- 아직 없는 것: 알낳기(필드), 배틀의 유령(실프스코프)·교환 포켓몬 말 안 듣기·포켓몬피리·사파리존·통신 배틀·학습장치.
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
6챕터(11번도로 → 디그다의 굴 → 2번도로 동쪽 → 돌산터널 → 보라타운·타워 2F)는 끝났어. 6챕터 exe 가 없으면 빌드하고,
HANDOFF.md 의 "그다음" 순서대로 7챕터(7·8번도로·지하통로 → 무지개시티)로 넘어가.
원작과 똑같이, 혼자 진행하고, 커밋은 한글로. 구역마다 스모크(tools/chapter7_smoke.py 를 같은 방식으로) PASS 뒤 커밋.
```

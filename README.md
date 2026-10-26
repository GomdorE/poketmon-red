# 포켓몬 레드 Godot 재구현 — 1~3챕터

Game Boy ROM을 에뮬레이션하는 것이 아니라, `pokered` 디스어셈블리(원본 데이터)를 그대로 읽어
Godot 4에서 다시 구현한 프로젝트입니다. 화면은 160×144 게임보이 타일 화면 그대로이며,
모든 타일·글꼴·텍스트·맵·스탯은 `tools/export_data.py` 가 원본에서 뽑아낸 데이터입니다.
직접 그린 그래픽이나 손으로 쓴 대사는 없습니다 (한글은 `pokered-korean` 포크의 8×16 폰트와 번역 텍스트).

## 구현 범위 (1챕터)

1. 저작권 화면 → 게임프리크 별똥별 → 팬텀 vs 니드리노 오프닝 (원작 OAM 좌표·타이밍 그대로)
2. 타이틀 (로고 바운스, 버전 글자 슬라이드, 포켓몬 교체 스크롤, 공 튀기기) → 새로 시작 / 설정 메뉴
3. 오박사 소개 — 픽 페이드/슬라이드, 니드리노 좌우반전, 이름 선택 상자, 알파벳 이름 입력 화면, 축소 연출
4. 오버월드 — 내 방(2층) → 1층(엄마·TV) → 태초마을(NPC 랜덤 이동, 표지판, 꽃·물 타일 애니메이션, 1번도로 경계 표시)
   → 북쪽 출구에서 오박사 등장(`!` 말풍선) → 오박사 따라 연구소 입장 컷신
5. 오박사 연구소 — 라이벌 대화, 몬스터볼 조사 → 도감 페이지 → 예/아니오 → 스타팅 획득 → 라이벌이 남은 볼 선택
   → 나가려 하면 라이벌의 도전
6. 라이벌 배틀 — 화면 번쩍임 + 나선 전환, 실루엣 슬라이드 인, 트레이너 픽 퇴장, 포켓몬 등장(공→3×3→5×5→원본),
   HUD/HP바, 싸운다·포켓몬·도구·도망 메뉴, 기술 메뉴(타입/PP 상자), 1세대 데미지 공식(급소·STAB·상성·랜덤),
   능력치 변화, 경험치·레벨업(능력치 상자), 승리 텍스트·상금 / 패배 시 라이벌 대사
7. 배틀 후 라이벌 퇴장까지. 이후에는 태초마을을 자유롭게 돌아다닐 수 있습니다 (1번도로 진입 불가).
8. 음악·효과음·울음소리 — 원작 사운드 엔진(`audio/engine_1.asm`, 배틀 효과음·HP 경고음이 있는 bank 2 변형 포함)을
   GDScript로 포팅하고, 게임보이 APU(펄스 2채널·파형·노이즈, 엔벨로프·스윕·프레임 시퀀서)를 소프트웨어로 합성합니다.
   `tools/export_audio.py` 가 `audio/sfx`, `audio/music`, 헤더, 울음소리·기술 효과음 테이블, 파형, 음표 주파수를
   그대로 뽑아내고(`assets/data/audio.json`), 엔진은 그 명령 스트림을 원작 의미대로 해석합니다 — 템포·음 길이의
   분수 누적, 비브라토, 피치 슬라이드(원작의 borrow 버그 포함), 듀티 패턴, 효과음 우선순위, 울음소리의 주파수·템포 보정,
   맵 음악 페이드아웃(`FadeOutAudio`), 라이벌 테마의 대체 시작(`Music_RivalAlternateStart`), 텍스트 명령 효과음 등.
   재생 시점도 원작 호출 위치를 따릅니다(메뉴 A/B·텍스트 넘김 소리, 벽 충돌, 문 출입, Start 메뉴, 배틀 시작·공격·피격·기절·레벨업·승리).

9. 원작 설정 화면 — 타이틀 메뉴와 Start 메뉴의 "설정"에서 `DisplayOptionMenu` 그대로: 문자 속도(빠름/보통/느림 = 글자당 1/3/5프레임),
   전투 애니메이션 켬/끔(끄면 기술 연출 대신 30프레임 대기), 전투 방식 교체/유지(1챕터에서는 효과 없음). 커서 좌표·▷ 표시·토글 동작 동일.
10. 상단 메뉴 바(원작에 없는 기능) — 게임(일시정지·처음부터 다시 시작·종료), 속도(1×~8×, 0.5 단위), 화면(배율·전체화면·팔레트), 소리(음소거·볼륨),
    설정(설정 화면 열기·기본 키 복원). 전투 중에도 마우스로 열 수 있고 메뉴가 열린 동안 게임은 멈춥니다.
11. 엔진 설정 오버레이(원작에 없는 기능, Esc 또는 메뉴 바 > 설정) — 창 배율 ×2~×8, 전체화면, 팔레트(회색/초록), 볼륨·음소거, 키 재배정(키보드·패드), 게임 종료.
    게임보이 화면 위에 네이티브 해상도 Godot UI 로 그리며, 열려 있는 동안 게임은 일시정지됩니다.
    저장 위치: `%APPDATA%\Godot\app_userdata\포켓몬 레드 Godot\settings.cfg` (원작 옵션 byte 도 여기 저장).

12. 슈퍼 게임보이 색감 — 기본 팔레트이며 메뉴 바 > 화면 > 팔레트(또는 P 키 순환)에서 회색·초록으로 바꿀 수 있음. 레드에 내장된 SGB 데이터를 그대로 씁니다:
    `data/sgb/sgb_palettes.asm` 의 37개 팔레트, `engine/gfx/palettes.asm` 의 팔레트 명령(지역별 OVERWORLD, 종족별·HP 바 색의 BATTLE,
    POKEDEX, TITLE_SCREEN, NIDORINO/GAME_FREAK INTRO, GENERIC)과 ATTR_BLK 화면 영역 패킷, 그리고 `gfx/sgb/red_border` 의 SGB 보더(액자).
    `tools/export_sgb.py` → `assets/data/sgb.json`, `assets/gb/sgb_border.png`. 셰이더가 셀마다 4개 팔레트 중 하나를 고릅니다.

13. 세이브 — Start 메뉴 "리포트"(원작 SaveMenu: 플레이어·배지·도감·시간 정보 상자 → "리포트를 작성하시겠습니까?" 예/아니오 →
    다른 게임의 파일이 있으면 덮어쓰기 확인 → "저장 중..." 120프레임 → "리포트를 작성했다!" + 저장 효과음)과
    타이틀 메뉴 "이어하기"(저장 파일이 있을 때만, 정보 상자 30프레임 뒤 A 로 시작 / B 로 취소). 플레이 시간은 원작 TrackPlayTime 방식(60프레임 = 1초).
    파일은 `%APPDATA%\Godot\app_userdata\포켓몬 레드 Godot\save.json` 하나(원작 SRAM 처럼 하나만).

## 구현 범위 (2챕터: 1번도로 ~ 상록시티 ~ 22번도로)

14. 맵 연결 — 태초마을↔1번도로↔상록시티↔2번도로/22번도로 (`connection` 매크로 의미 그대로 네 방향 경계 블록 렌더링과 경계 넘기).
    상록시티의 포켓몬센터·프렌들리숍·학교·별명집·체육관(잠김), 2번도로 남쪽, 22번도로, 상록숲 입구 게이트.
15. 야생 포켓몬 — `TryDoWildEncounter`: 서 있는 블록의 오른쪽 아래 타일이 풀 타일일 때 맵의 조우율(`data/wild/grass_water.asm`)과 10슬롯 확률표,
    맵 진입 뒤 3걸음 조우 없음. 야생 배틀: 울음소리 → "야생 ○○ 나타났다!" → 교체·도망(원작 도망 공식, 시도 횟수 +30)·
    몬스터볼(`ItemUseBall` 포획 공식·흔들림 횟수·실패 대사 4종, 새 도감 등록 → 도감 페이지, 별명 입력 화면, 파티 6마리면 박스) · 승리 음악.
16. 상태이상·기술 효과 — 독·화상(턴마다 최대HP/16, 독은 오버월드에서 4걸음마다 1 + 화면 번쩍임 + 효과음, 전멸 시 눈앞이 깜깜)·마비(스피드 1/4, 25% 행동 불가)·
    잠듦·얼음·풀죽음·씨뿌리기, 능력 변화(상대가 쓰는 능력 하락 기술 25% 빗나감 포함), 2~5회/2회 연속 공격, 전광석화 우선권.
17. 트레이너 다수 포켓몬 — 상대의 다음 포켓몬(전투 방식 "교체"일 때 "레드도 포켓몬을 교체하겠습니까?"), 내 포켓몬 교체(RetreatMon 대사·축소 연출),
    기절 후 "다음 포켓몬을 내보내겠습니까?"(야생), 참가한 포켓몬끼리 경험치 분배(트레이너 1.5배), 레벨업 기술 습득(4개면 잊을 기술 선택 "1, 2 and... Poof!"),
    배틀 후 진화(`EvolveMon`: 땡 소리 → 사파리존 음악 → 흑백 교차 애니메이션, B로 취소), 전멸 시 소지금 절반·마지막 포켓몬센터(없으면 태초마을)로.
18. 오박사의 소포 — 프렌들리숍 점원이 맡긴 소포 전달 → 라이벌 등장 → 도감 획득 → 라이벌 퇴장 → 22번도로 라이벌 배틀(구구 L9 + 스타팅 L8) →
    오박사의 몬스터볼 5개, 도감 평가. 블루의 집 누나에게 타운맵, 상록시티 할아버지의 포획 시범(OLD MAN 이 뿔충이를 잡는 스크립트 배틀).
19. 포켓몬센터(간호순이 대화·회복 기계 연출·효과음) / 프렌들리숍(구입·판매·수량·소지금 상자, 원작 리스트 메뉴).
20. Start 메뉴 — 도감(목록·DATA·CRY·AREA), 포켓몬(파티 메뉴: 아이콘 애니메이션·HP바·상태 / 능력치 화면 2페이지 / 교체), 도구(가방·사용·버리기·타운맵·기술머신 가르치기),
    트레이너 카드(이름·소지금·시간·배지).
21. 배틀 애니메이션 엔진 — `engine/battle/animations.asm` 의 해석기를 그대로 포팅했습니다(`scripts/game/battle_anim.gd`, 데이터는 `tools/export_battle_anims.py` →
    `assets/data/battle_anims.json`): 기술별 명령 스트림(서브 애니메이션·특수 효과·효과음), 서브 애니메이션의 프레임 블록·기준 좌표·변환(상대 턴 좌우/상하 반전·역순),
    프레임 블록 모드, 애니메이션별 특수 효과(화면 번쩍임·울음소리 음표 복사·볼 던지기/흔들기/퐁 효과음), 특수 효과 39종(팔레트 변경, 화면 흔들림, 픽 이동/슬라이드/깜빡임/
    찌그러짐, 공 발사·소용돌이, 물방울·잎·꽃잎 떨어짐, 물결 화면, 상대 HUD 흔들림 등)과 피격 연출 6종(세로/가로 흔들림·상대 깜빡임). 몬스터볼 던지기·흔들림·퐁,
    독/화상·잠듦·혼란 연출, 상태이상 부여 시 HUD 흔들림도 같은 엔진으로 돌아갑니다. SGB 에서는 원작처럼 애니메이션 스프라이트가 흑백 2단계($f0 팔레트)로 나옵니다.
22. 능력치 경험치(stat exp) — 쓰러뜨린 포켓몬의 종족값이 참가 포켓몬에 쌓이고(참가 수로 나눔, 최대 65535) 레벨업·진화 때 `CalcStat` 의 √(stat exp)/4 항으로 반영됩니다.
23. 포켓몬센터 PC — 누군가의/빌의 PC(맡기기·찾기·놓아주기·박스 변경, 12박스×20마리), 내 PC(도구 맡기기·찾기·버리기), 오박사의 PC(도감 평가), 로그오프;
    내 방 PC, 책장·포스터·메모·칠판 등 숨겨진 사물(`data/events/hidden_events.asm`).

## 구현 범위 (3챕터: 상록숲 ~ 2번도로 북쪽 ~ 회색시티 ~ 웅)

24. 트레이너 시선 엔진 — `home/trainers.asm`·`engine/overworld/trainer_sight.asm` 포팅(`scripts/game/trainer_engine.gd`).
    맵 스크립트의 트레이너 헤더(`def_trainers` / `trainer 이벤트, 시야, 대사...`)를 `tools/export_data.py` 가 `maps.json` 의 `trainer_headers` 로 뽑습니다.
    화면 좌표·바이트 차이 계산 그대로(맨 윗줄 트레이너는 시야 계산이 어긋나는 원작 버릇 포함), 느낌표 → 만남 음악(남/여/악당 목록) → 플레이어 앞까지 걸어옴 → 대사 → 배틀,
    직접 말을 건 경우(TalkToTrainer)도 같은 흐름. 이긴 트레이너는 플래그가 서고 그 뒤로 플레이어 쪽을 봅니다(SetEnemyTrainerToStayAndFaceAnyDirection).
    전멸했을 때는 원작처럼 맵 스크립트가 한 번 더 돌아 트레이너 상태가 초기화됩니다. 트레이너만 있는 맵은 따로 코드 없이 같은 스크립트 표로 동작합니다.
25. 상록숲(벌레잡이소년 3명, 아이템, 숨겨진 아이템), 북쪽 게이트, 2번도로 북쪽, 회색시티(박물관 안내 아저씨·체육관 안내 소년이 플레이어를 데려가는 스크립트,
    웅을 이기기 전 동쪽 출구 막기), 박물관 1F/2F(50원 입장권, 화석 그림 팝업, 호박 받기), 회색시티 포켓몬센터(푸린 노래), 프렌들리숍, 니드런 집, 이야기 집.
26. 회색체육관 — 소년트레이너, 웅(체육관 관장 음악·승리 음악, 회색배지·기술머신34 참기, 배지 뒤 22번도로 라이벌 숨김·체육관 안내 소년 숨김),
    체육관 안내원 예/아니오, 체육관 동상.
27. 배틀 엔진 — `engine/battle/core.asm`·`effects.asm` 을 그대로 따릅니다: 배틀 중 능력치(보정 전/후)·랭크 1~13·상태 플래그·다턴 카운터·사슬묶기·참기·대타,
    원작 데미지 공식(255 넘는 능력치 축소, 급소율 높은 기술, 기충전 버그), 화상·마비 페널티와 배지 능력치 보정 시점, 기술 효과 68종 전부(혼란·사슬묶기·조이기류·
    난동·2턴 기술·파괴광선 반동·분노·흰안개·리플렉터/빛의장막·대타출동·변신·흉내내기·손가락흔들기·따라하기·카운터·일격필살·반동·흡수·자폭·고양이돈받기·흑안개·회복·
    순간이동/날려버리기 등), 트레이너 AI(기술 선택 보정 1~3단계, 클래스별 도구·교체), 체육관 관장 고유 기술(롱스톤의 참기), 관장 배틀·승리 음악,
    배틀 끝 대사 앞의 트레이너 이름("웅: ..."), 상금 = 마지막 포켓몬 레벨 × 기본금. 기술 선택에서 SELECT 두 번으로 기술 순서 바꾸기(SwapMovesInMenu).
    포켓몬이 처음 가지는 기술은 원작 WriteMonMoves 대로 마지막에 배운 네 개입니다.
28. 워프 판정 — `ExtraWarpCheck`(밖 타일셋은 플레이어 앞 매트 타일, 실내는 맵 끝을 볼 때)와 충돌 워프, `CheckIfInOutsideMap`(OVERWORLD/PLATEAU 타일셋)로 LAST_MAP 갱신.
29. 숨겨진 아이템(`HiddenItems`: 한 번만, 효과음 뒤 버튼 대기 없음, 가방 가득 처리), 박물관 화석(`DisplayMonFrontSpriteInBox`).

### 원작과 다른 점 (의도적 단순화)
- 저장 파일은 JSON 이며 체크섬·손상 검사는 없습니다. 타이틀의 Up+B+Select 파일 삭제는 없습니다(파일을 지우면 됩니다).
- SGB 속성은 화면 8×8 셀 단위라 스크롤 중 셀에 걸친 타일은 타일 왼쪽 위 기준 셀의 팔레트를 씁니다(1챕터에서 영역이 나뉘는 화면은 스크롤하지 않음).
- 원작 옵션(wOptions)은 세이브 파일이 아니라 settings.cfg 에 저장됩니다. Start 메뉴의 리포트·설정·닫기 이외 항목은 아직 동작하지 않습니다.
- 사운드 하드웨어는 에뮬레이터가 아니라 근사 모델입니다(채널 혼합·DAC 오프셋 단순화, 32768Hz 출력).
  엔진 자체는 원작 코드 대응이며 `--audio-test` 로 음 길이·주파수를 수치 검증했습니다.
- 배틀 중 교체·도구 메뉴의 흰색 페이드는 원작 GBPalWhiteOut 대로 한 프레임입니다.
- 한글 포크의 8×16 글꼴은 윗 반쪽을 한 줄 위에 그리므로(한글 ROM 도 같아서 0행 글자가 잘리고 라벨이 겹침) 한글일 때만 배치를 손본 곳이 있습니다:
  배틀 기술 메뉴의 "타입/" 상자는 한 줄에 "타입 /노말"; 상대 포켓몬 HUD(이름·레벨·HP바)는 한 줄 아래; 파티 메뉴는 이름이 두 줄을 차지하고 HP바가 오른쪽(x11)으로
  옮겨지며 HP 숫자는 생략(능력치 화면에서 확인); 능력치 화면 1페이지의 타입1·타입2·번호·어버이 라벨은 값과 같은 줄에(값은 오른쪽 정렬), 능력치 상자 라벨은 한 줄 아래,
  2페이지의 경험치/다음레벨은 2·5행에 두고 다음 레벨 줄은 7행; 타운맵·서식지 머리글은 1행. 영어는 모두 원작 좌표 그대로입니다.
- 필드 기술(풀베기 등)은 아직 없습니다. 2번도로 동쪽(풀베기 필요: 디그다굴 입구·교환 집·게이트)은 들어갈 수 없습니다.
- 배틀: 유령(실프스코프)·교환 포켓몬 말 안 듣기·포켓몬피리·사파리존·통신 배틀·학습장치는 아직 없습니다. 방어 0 으로 나누는 경우(원작은 멈춤)는 막아 두었습니다.
- 아직 내보내지 않은 맵으로 이어지는 연결(회색시티 동쪽 → 3번도로)은 벽처럼 막힙니다(4챕터에서 열림).
- 배틀 기술 목록(배틀의 기술 선택, 기술 잊기)은 한글일 때 2×2 칸으로 놓습니다(이름 줄 14·16행). 원작·한글 ROM 은 한 줄 간격이라 8×16 글자가 서로 덮입니다.
- 텍스트 상자·메뉴 아래에 선 NPC 는 원작 규칙(CheckSpriteAvailability: 맵 타일이 아닌 타일 위면 숨김)대로 보이지 않습니다.
- 연구소 입장 컷신 동안 입력을 막아 두었습니다(원작은 약 50프레임 동안 이동 가능).

## 조작

기본 키 (Esc 설정 화면에서 바꿀 수 있음):

| 키 | 게임보이 |
|---|---|
| Z 또는 Space | A |
| X | B |
| Enter | Start |
| Shift | Select |
| 방향키 | 십자키 |
| P | 팔레트 순환 (회색 → 초록 → SGB 컬러) |
| F | 배속 토글 (1× ↔ 메뉴에서 고른 배속, 기본 8×) |
| Esc | 엔진 설정 (배율·전체화면·팔레트·볼륨·키 설정·종료) |

## 구조

```
tools/export_data.py      ../pokered-master, ../pokered-korean → assets/gb/*.png, assets/data/*.json
tools/export_audio.py     ../pokered-master/audio → assets/data/audio.json (음악·효과음 명령, 헤더, 울음소리, 파형)
tools/audio_check.py       --audio-test 로 만든 WAV 의 프레임별 음높이·길이 분석
tools/export_sgb.py        ../pokered-master/data/sgb, gfx/sgb → assets/data/sgb.json, assets/gb/sgb_border.png
tools/export_battle_anims.py  data/moves/animations.asm, data/battle_anims/* → assets/data/battle_anims.json
scripts/game/battle_anim.gd   배틀 애니메이션 해석기(PlayAnimation/서브 애니메이션/특수 효과/피격 연출/볼 던지기)
scripts/gb/sgb.gd          SGB 팔레트 명령(RunPaletteCommand) 포팅 (autoload SGB)
tools/pathfind.py          맵 위 최단 경로 (테스트 입력 작성용)
scripts/gb/gb.gd           프레임 클록(59.7275Hz)·조이패드·팔레트 (autoload GB); 매 프레임 Sound.vblank() 호출
scripts/gb/apu.gd          게임보이 APU 모델 (레지스터 $FF10-$FF3F 그대로 기록)
scripts/gb/sound.gd        pokered 사운드 엔진 포팅 + home/audio.asm 의 PlayMusic/PlaySound/PlayDefaultMusic/페이드 (autoload Sound)
scripts/engine/settings.gd         엔진 설정 + 원작 wOptions 저장/적용, 키 바인딩 (autoload Settings)
scripts/engine/settings_overlay.gd Esc 설정 오버레이 UI
scripts/engine/menu_bar.gd         상단 메뉴 바 (게임·화면·소리·설정)
scripts/game/option_menu.gd        원작 OPTION 화면 (DisplayOptionMenu)
scripts/game/save_game.gd          세이브 파일(user://save.json), SaveMenu, 이어하기 정보 상자
scenes/main.tscn           SubViewport(160×144) 안의 GBScreen 을 정수 배율로 창에 띄움; 오버레이는 창 해상도로 그림
scripts/gb/screen.gd       BG/윈도우 맵, OAM, 스크롤, 팔레트 레지스터를 그리는 타일 렌더러 + 셰이더
scripts/gb/text.gd         문자표·PlaceString·텍스트 명령 처리기(한글 8×16 포함)
scripts/gb/menu.gd         텍스트 상자·커서 메뉴·예/아니오
scripts/game/trainer_engine.gd   트레이너 시선·대화·배틀 시작/종료 (home/trainers.asm)
scripts/game/map_scripts_pewter.gd  3챕터 회색시티·박물관·센터 등 맵 스크립트 (회색체육관은 map_scripts.gd)
scripts/game/*.gd          splash, intro, title, oak_speech, naming, overworld, map_scripts, pokedex_page, battle, party_mon,
                           pokecenter, pokemart, party_menu, status_screen, bag, item_use, pokedex_menu, town_map, dex_rating, mon_hud
scripts/gb/list_menu.gd    DisplayListMenuID(가방·상점 목록)·수량 선택
```

데이터를 다시 뽑으려면 (Pillow 필요):

```powershell
python tools\export_data.py
python tools\export_audio.py
python tools\export_sgb.py
python tools\export_battle_anims.py
```

## 실행

```powershell
X:\joy2is90\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64.exe --path X:\joy2is90\pokered-master\pokered-godot
```

디버그 인자(`--` 뒤에):

- `--stage=splash|intro|title|oak|overworld|lab|battle` 해당 단계부터 시작, `--stage=map:MAP,x,y` 그 맵에서 시작(연구소 이후 이벤트 완료 상태)
- 테스트 상태: `--party=종:레벨[:상태[:추가경험치[:HP]]],...`, `--give=도구:수,...`, `--event=이벤트,...`, `--script=맵:번호`
- 배틀 테스트: `--stage=battle --wild=종:레벨` / `--trainer=클래스:팀번호` / `--old-man`, `--trace-battle` 로 메뉴·대사 로그, `--keys=every:N:키[:시작프레임]` 주기 입력
- `--shot=경로\s_%d.png --shot-every=60` 주기적 스크린샷, `--quit-after=N` N프레임 후 종료, `--fast` 8배속 시작
- `--keys=프레임:키[:유지프레임],...` 키 입력 스크립트 (a,b,start,select,up,down,left,right)
- `--sim=RUUU|DDLL|...` 오버월드 테스트 걷기(한 글자 = 한 칸, A = A 버튼, `|` = 다음 맵)
- `--overlay-shot=경로.png` 설정 오버레이를 열어 창 전체를 저장, `--window-shot=경로.png` 창 전체만 저장(창 모드)
- `--palette=gray|dmg|sgb` 이번 실행의 팔레트(설정 파일은 바꾸지 않음)
- `--no-audio` 소리 출력 끄기(엔진은 그대로 돌아 타이밍은 같음; headless 에서는 자동)
- `--audio-out=경로.wav --audio-test=music|sfx|cry:이름:프레임수[:솔로채널]` 사운드 엔진을 오프라인으로 렌더링해 WAV 저장
  (예: `--audio-test=music:MUSIC_PALLET_TOWN:400:1`, `--audio-test=sfx:SFX_PRESS_AB:40`, `--audio-test=cry:BULBASAUR:120`),
  결과는 `python tools\audio_check.py 경로.wav` 로 프레임 단위 음높이·길이를 확인

예) 1챕터 전체 자동 진행:

```powershell
Godot_v4.7.2-stable_win64_console.exe --path . -- --stage=overworld "--sim=RUUUUURRR|DDDDDDLLLLD|DRRRRUUUURU|RADDD" --fast --keys=100:a,145:a,...
```

## Windows EXE

```powershell
X:\joy2is90\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe --headless --path X:\joy2is90\pokered-master\pokered-godot --export-release "Windows Desktop" X:\joy2is90\pokered-master\pokered-godot\dist\PokemonRed-Godot-Chapter3.exe
```

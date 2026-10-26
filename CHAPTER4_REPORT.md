# 4챕터 포팅 결과

작업 폴더: `X:\joy2is90\pokered-master\pokered-godot-codex`  
작업 브랜치: `코덱스-4챕터`  
다른 worktree와 원본 ASM은 수정하지 않았다. push/merge는 실행하지 않았다.

## 옮긴 맵과 스크립트

원본 `scripts/<Map>.asm`, `data/maps/objects/<Map>.asm`, 영문·한글 `text/<Map>.asm`을 대조했다.
17개 맵, 일반 트레이너 헤더 37개를 내보냈다. 트레이너만 있는 맵은 기존 TrainerEngine을 그대로 사용한다.

| 맵 | 처리 |
|---|---|
| ROUTE_3 | 원본 맵·일반 대사·8개 트레이너 헤더 |
| MT_MOON_POKECENTER | 간호순, 잉어킹 500원 판매, 거절·돈 부족·박스 가득 참·구입 완료 분기, 별명/박스 전송 |
| MT_MOON_1F | 원본 맵·7개 트레이너·아이템·주뱃 주의 표지판 |
| MT_MOON_B1F | 사다리/층간 워프, 동굴 데이터 |
| MT_MOON_B2F | 4개 로켓단 헤더, 괴짜 좌표 트리거/배틀, 두 화석 선택·가방 부족, 상대 화석 회수 이동 상태표 |
| ROUTE_4 | 원본 맵·트레이너·표지판·아이템, 블루시티 연결 |
| CERULEAN_CITY | 양쪽 다리 좌표의 라이벌 접근/승패/퇴장, 로켓단 배틀/TM28 반환/가방 부족 재시도/퇴장, 경비원·야도란 랜덤 대사 |
| CERULEAN_GYM | 일반 트레이너 2명, 이슬·블루배지·TM11·가방 부족 재수령, 안내원·동상 |
| CERULEAN_POKECENTER | 간호순과 원본 일반 대사 |
| CERULEAN_MART | 원본 상품 목록과 기존 상점 엔진 연결 |
| CERULEAN_TRADE_HOUSE | 맵·할머니 대사. NPC 교환은 아래 필요한 API 참고 |
| CERULEAN_TRASHED_HOUSE | TM28 소지 여부에 따른 집주인 대사, 소녀·구멍 대사·워프 |
| CERULEAN_BADGE_HOUSE | 원본 SHIP 타일셋, 배지 8종 목록·설명·취소 |
| BIKE_SHOP | 교환권 교환/가방 부족/교환 후 대사, 백만 원 자전거 메뉴·취소·구입 불가 분기 |
| ROUTE_24 | 6개 트레이너 헤더, 금구슬 지급/가방 부족 시 뒤로 이동, 로켓단전과 후속 대사 |
| ROUTE_25 | 9개 트레이너 헤더, 이수재 방문 전후 오브젝트 토글 |
| BILLS_HOUSE | 포켓몬 상태 대화·기계 진입, PC 전송기 효과음/대기, 사람으로 복귀하는 이동, 배표/가방 부족, 재방문 포켓몬 목록 |

코드 위치:

- `scripts/game/map_scripts_mtmoon.gd`: 장 연결, 달맞이산·잉어킹·화석, 이벤트 배틀 공통 호출.
- `scripts/game/cerulean_scripts.gd`: 블루시티·체육관·건물.
- `scripts/game/cerulean_cape.gd`: 24·25번도로와 이수재의 집.
- `tools/export_data.py`: 허용된 딕셔너리 항목만 추가. 함수 본문은 기존 버전과 AST 비교하여 동일함을 확인.
- `assets/data/`와 `assets/gb/tileset_{cavern,club,interior,ship}.png`: 원본에서 생성한 데이터/이미지.

`overworld.gd`, `map_scripts.gd`, `battle.gd`, `trainer_engine.gd`, 사운드 엔진은 수정하지 않았다.

## 검증 명령과 결과

Godot 실행 파일:

```powershell
$godot = 'X:\joy2is90\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'
```

기본 검사:

```powershell
python tools/export_data.py
& $godot --headless --editor --quit --path . --log-file .tmp/chapter4/import.engine.log
python -X utf8 tools/chapter4_audit.py
python -X utf8 tools/chapter4_smoke.py
git diff --check
```

- 임포트/스크립트 파싱 통과.
- 17개 맵 존재, 한글 정적 대사 라벨, exporter 함수 무수정 검사 통과.
- 기본 자동 검사 **23개 통과**: 17개 맵 로드, 3번도로 트레이너 시야, 동굴 사다리 워프, 화석 가방 부족/거절, 이슬 TM 재수령, 4번도로→블루시티 연결.
- 실행 로그/결과 JSON: `.tmp/chapter4/*.log`, `.tmp/chapter4/smoke_results.json`.

실제 이벤트/배틀 시나리오:

각 명령에는 `--trace-scripts --trace-battle --fast`를 붙여 실행했다. 입력은 `--keys=every:20:a`이며, 상자/메뉴가 열렸을 때도 게임의 실제 조이패드 경로를 거친다.

| 시나리오 | `--` 뒤의 핵심 인자 | 확인한 결과 |
|---|---|---|
| 갑각화석 | `--stage=map:MT_MOON_B2F,12,7 --event=EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD --sim=UA --quit-after=700` | `FOSSIL_SELECTED DOME_FOSSIL`, 상태 4→5→0 |
| 조개화석 | `--stage=map:MT_MOON_B2F,13,7 --event=EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD --sim=UA --quit-after=700` | `FOSSIL_SELECTED HELIX_FOSSIL`, 상태 4→5→0 |
| 잉어킹 | `--stage=map:MT_MOON_POKECENTER,10,7 --sim=UA --party=BLASTOISE:60 --quit-after=700` | `MAGIKARP_PURCHASE money=2500 party=2 box=0` |
| 자전거 | `--stage=map:BIKE_SHOP,6,3 --give=BIKE_VOUCHER:1 --sim=UA --quit-after=700` | `BIKE_EXCHANGED voucher=0 bicycle=1` |
| 괴짜 | `--stage=map:MT_MOON_B2F,13,8 --party=BLASTOISE:60 --quit-after=4300` | 승리 후 상태 3→0 |
| 이슬 | `--stage=map:CERULEAN_GYM,4,3 --sim=UA --event=EVENT_BEAT_CERULEAN_GYM_TRAINER_0,EVENT_BEAT_CERULEAN_GYM_TRAINER_1 --party=BLASTOISE:60 --quit-after=5000` | `MISTY_VICTORY badges=2 tm11=1` |
| 금구슬 다리 | `--stage=map:ROUTE_24,10,15 --party=BLASTOISE:60 --quit-after=5000` | 금구슬 1개, 로켓단 2마리 격파, 상태 3→0 |
| 라이벌 | `--stage=map:CERULEAN_CITY,20,6 --party=BLASTOISE:60 --quit-after=8000` | 상대 4마리 격파, 라이벌 퇴장, 상태 2→3→0 |
| TM28 도둑 | `--stage=map:CERULEAN_CITY,30,9 --party=BLASTOISE:60 --quit-after=4300` | `CERULEAN_TM28 item=1 rocket_hidden=true`, 상태 4→0 |
| 이수재 | `--stage=map:BILLS_HOUSE,6,6 --sim=UALLLLLUDUDUDUDUARRRUA --party=BLASTOISE:60 --quit-after=2200` | `CELL_SEPARATOR_USED`, `BILL_RESTORED`, `SS_TICKET_RECEIVED qty=1` |

`python tools/chapter4_smoke.py --full`은 위 시나리오까지 포함한 33개 검사를 재실행한다. 기본 23개와 별도 이벤트 실행을 구분해 기록했다.

창모드 검사는 `--headless` 없이 다음과 같이 실행했다:

```powershell
& $godot --path . --log-file .tmp/chapter4/visual.engine.log -- --stage=map:MT_MOON_B2F,12,7 --event=EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD --sim=UA --party=BLASTOISE:60 --keys=every:40:a --shot=.tmp/chapter4/visual/fossil_%d.png --shot-every=60 --fast --quit-after=360
```

같은 방식으로 자전거 가게와 배지 설명집도 확인했다. `.tmp/chapter4/visual/`에 전체 화면 캡처를 남겼으며, 대표 화면은 `reports/chapter4/fossil.png`, `bike_shop.png`, `badges.png`로 커밋했다. 화석 이름과 획득 대사, 자전거 메뉴, 배지 목록의 한글 윗반쪽이 테두리나 다른 글자를 덮지 않는 것을 확인했다.

## 원작과 다른 점 / 필요한 API

아래 부분은 요청한 수정 경계를 지키기 위해 공통 엔진을 고치지 않았다. **4챕터의 모든 동작이 완전히 원작과 동일하다고 주장하지 않는다.**

1. **야생 전투 금지 플래그**: `MtMoonB2F_Script`의 `BIT_NO_BATTLES` 공유 상태와 `_try_wild_encounter()`의 검사 API가 없다. 괴짜 격파 후 좌표 `x=11..14, y=5..8`에서 야생 전투를 막는 원작 조건이 미연결이다. 화석 선택·보상·이동 상태표는 동작한다. 임의로 조우 쿨다운을 덮어쓰는 대체 구현은 하지 않았다.
2. **NPC 교환**: 블루시티 교환집의 `TRADE_FOR_LOLA`(슈륙챙이→루주라)는 `DoInGameTradeDialogue`/`InternalClockTradeAnim` API가 없고, PartyMon에 원작 OT/교환 개체 정보도 없다. 해당 교환 NPC의 교환 기능은 미구현이다. 대사를 임의로 쓰거나 교환 완료 플래그만 세우지 않았다.
3. **이슬 승리 사운드의 원작 버그**: 원작은 잘못된 음악 뱅크 때문에 배지 효과음 대신 `SFX_BALL_POOF`의 두 번째 채널이 난다. 기존 사운드 엔진은 `SFX_Get_Key_Item_1`이 bank 2에 없으면 bank 1로 fallback한다. 텍스트/호출 위치는 원본대로지만 이 잘못된 뱅크/부분 채널 효과음까지 재현하려면 사운드 엔진 지원이 필요하다. 로그에 관련 경고가 나온다.
4. **기존 종료 정리 문제**: 자동 실행 종료 시 `ObjectDB instances were leaked`와 `resources still in use at exit` 경고/오류가 남는다. 스크립트 파싱·게임 진행 중 예외와 구분했다. 전역 수명/코어 정리 코드는 수정하지 않았다.
5. **한국어 메뉴 배치**: 허용된 예외에 따라 8×16 한글 메뉴만 두 행 간격으로 배치한다. 영문 메뉴는 원작 한 행 간격을 유지한다. 새 그래픽/임의 대사는 만들지 않았다.
6. **맵 로컬 숨김 이벤트 연결**: 현재 HiddenEvents에는 이수재 PC와 블루체육관 동상 처리가 없다. 원본 좌표와 위쪽 바라보기 조건을 map-local 대사 이벤트로 연결했다. 공통 엔진 파일을 건드리지 않고 PC 이벤트·동상 대사를 실행한다.
7. **Claude 담당 엔진 기능**: 턱 뛰어내리기, 필드 기술, 자전거 타기, 낚시, 벌레퇴치스프레이는 이 브랜치에서 수정하지 않았다. 자전거 가게는 도구 지급까지만 담당한다. 5·9번도로는 다음 범위로 내보내지 않았으며 연결이 막히는 기존 정책을 따른다.
8. **타일셋 애니메이션과 통신 기능**: 기존 `_tick_tile_animation()`/`_tile_value()`는 OVERWORLD/DOJO에 한정되어 있어 원본 CAVERN/SHIP의 `TILEANIM_WATER` 일반화가 필요하다. 포켓몬센터 통신 접수원은 앞 챕터와 같은 안내문 연결이며 실제 통신/교환 엔진은 없다. 이 두 공통 엔진은 수정 범위 밖이다.

이 결과는 CLI 시작 지점을 이용한 맵/이벤트별 검증이다. 1챕터부터 4챕터 끝까지 한 저장 파일로 연속 플레이한 완주 검사는 아니다. 사용자 `save.json`을 지우거나 저장하는 입력은 실행하지 않았다.

## 커밋

- `0afb7df` 4챕터 맵과 타일셋 원본 데이터를 추가
- `268953f` 달맞이산 화석 선택과 잉어킹 판매 이벤트를 포팅
- `e69470e` 블루시티 라이벌과 로켓단 및 이슬 이벤트를 포팅
- `336250f` 금구슬 다리와 이수재 구출 및 배표 이벤트를 포팅
- `07179ea` 4챕터 타일셋과 대사 이름 및 숨김 이벤트 조건을 보완
- 이후 보완·검증 커밋은 `git log main..코덱스-4챕터 --oneline`으로 확인한다.

이 브랜치의 변경 파일은 4챕터 스크립트, exporter 딕셔너리, 생성 assets, 검사 도구와 이 보고서뿐이다. 병합은 사용자가 진행한다.

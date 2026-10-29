"""Run chapter-seven map/event checks without loading or writing user saves.
GODOT=<Godot console exe> python tools/chapter7_smoke.py [--full]"""
from pathlib import Path
import json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
GODOT=Path(os.environ['GODOT'])  # Godot_v4.7.2-stable_win64_console.exe
OUT=ROOT/'.tmp/chapter7';OUT.mkdir(parents=True,exist_ok=True)
maps=json.loads((ROOT/'assets/data/maps.json').read_text(encoding='utf8'))
chapter=['ROUTE_7','ROUTE_7_GATE','UNDERGROUND_PATH_ROUTE_7','UNDERGROUND_PATH_WEST_EAST','UNDERGROUND_PATH_ROUTE_8','ROUTE_8_GATE','ROUTE_8',
 'CELADON_CITY','CELADON_MART_1F','CELADON_MART_2F','CELADON_MART_3F','CELADON_MART_4F','CELADON_MART_5F','CELADON_MART_ELEVATOR','CELADON_MART_ROOF',
 'CELADON_MANSION_1F','CELADON_MANSION_2F','CELADON_MANSION_3F','CELADON_MANSION_ROOF','CELADON_MANSION_ROOF_HOUSE','CELADON_POKECENTER','CELADON_GYM',
 'CELADON_DINER','CELADON_CHIEF_HOUSE','CELADON_HOTEL','GAME_CORNER','GAME_CORNER_PRIZE_ROOM','ROCKET_HIDEOUT_B1F','ROCKET_HIDEOUT_B2F','ROCKET_HIDEOUT_B3F','ROCKET_HIDEOUT_B4F','ROCKET_HIDEOUT_ELEVATOR']
cases=[]
for mid in chapter:
 cases.append(('load_'+mid,[f'--stage=map:{mid},1,1','--quit-after=8'],f'MAP_LOAD {mid} '))
cases += [
 # Routes 7/8, the Saffron gates, the Underground Path
 ('route7_gate_enter',['--stage=map:ROUTE_7,10,10','--sim=RR','--quit-after=200'],'MAP_LOAD ROUTE_7_GATE (0,4)'),
 ('gate_exit_route7',['--stage=map:ROUTE_7_GATE,1,3','--sim=LL','--last-map=ROUTE_7','--quit-after=200'],'MAP_LOAD ROUTE_7 (11,10)'),
 ('route7_gate_thirsty',['--stage=map:ROUTE_7_GATE,3,4','--quit-after=400'],'TEXT_ID TEXT_ROUTE7GATE_GUARD_GEE_IM_THIRSTY'),
 ('route7_gate_walked_back',['--stage=map:ROUTE_7_GATE,3,4','--quit-after=400'],'MAPSCRIPT ROUTE_7_GATE -> 0'),
 ('route7_gate_drink',['--stage=map:ROUTE_7_GATE,3,4','--give=LEMONADE:1','--quit-after=400'],'GUARD_DRINK item=LEMONADE'),
 ('route7_gate_guard',['--stage=map:ROUTE_7_GATE,3,2','--sim=UA','--event=GAVE_SAFFRON_GUARDS_DRINK','--quit-after=300'],'TEXT_ID TEXT_ROUTE7GATE_GUARD'),
 ('route8_gate_thirsty',['--stage=map:ROUTE_8_GATE,2,3','--quit-after=400'],'TEXT_ID TEXT_ROUTE8GATE_GUARD_GEE_IM_THIRSTY'),
 ('route8_gate_drink',['--stage=map:ROUTE_8_GATE,2,3','--give=FRESH_WATER:1','--quit-after=400'],'GUARD_DRINK item=FRESH_WATER'),
 ('route8_gate_enter',['--stage=map:ROUTE_8,9,10','--sim=LL','--quit-after=200'],'MAP_LOAD ROUTE_8_GATE (5,4)'),
 ('route7_underground_enter',['--stage=map:ROUTE_7,5,12','--sim=D','--quit-after=200'],'MAP_LOAD UNDERGROUND_PATH_ROUTE_7 (3,7)'),
 ('underground7_exit',['--stage=map:UNDERGROUND_PATH_ROUTE_7,3,6','--sim=DD','--quit-after=200'],'MAP_LOAD ROUTE_7 (5,13)'),
 ('underground7_down',['--stage=map:UNDERGROUND_PATH_ROUTE_7,4,3','--sim=D','--quit-after=200'],'MAP_LOAD UNDERGROUND_PATH_WEST_EAST (2,5)'),
 ('underground_east_up',['--stage=map:UNDERGROUND_PATH_WEST_EAST,47,3','--sim=U','--quit-after=200'],'MAP_LOAD UNDERGROUND_PATH_ROUTE_8 (4,4)'),
 ('underground8_exit',['--stage=map:UNDERGROUND_PATH_ROUTE_8,3,6','--sim=DD','--quit-after=200'],'MAP_LOAD ROUTE_8 (13,3)'),
 ('route8_trainer_sight',['--stage=map:ROUTE_8,13,6','--party=BLASTOISE:60','--quit-after=600'],'TRAINER_SEES'),
 ('celadon_route7',['--stage=map:CELADON_CITY,49,10','--sim=R','--quit-after=150'],'MAP_LOAD ROUTE_7'),
 # Celadon City
 ('celadon_tm41',['--stage=map:CELADON_CITY,22,17','--sim=UA','--quit-after=600'],'GOT_TM41'),
 ('celadon_tm41_again',['--stage=map:CELADON_CITY,22,17','--sim=UA','--event=EVENT_GOT_TM41','--quit-after=400'],'TEXT_ID TEXT_CELADONCITY_GRAMPS3'),
 ('celadon_poliwrath',['--stage=map:CELADON_CITY,30,13','--sim=UA','--quit-after=400'],'TEXT_ID TEXT_CELADONCITY_POLIWRATH'),
 ('celadon_mart_door',['--stage=map:CELADON_CITY,8,14','--sim=U','--quit-after=200'],'MAP_LOAD CELADON_MART_1F (2,7)'),
 ('celadon_gym_door',['--stage=map:CELADON_CITY,12,28','--sim=U','--quit-after=200'],'MAP_LOAD CELADON_GYM (4,17)'),
 ('celadon_nurse',['--stage=map:CELADON_POKECENTER,3,3','--party=PIDGEY:9:PSN','--sim=UA','--quit-after=900'],'POKECENTER_HEALED'),
 # the department store
 ('mart1f_elevator_door',['--stage=map:CELADON_MART_1F,1,2','--sim=U','--quit-after=200'],'ELEVATOR_WARPS -> CELADON_MART_1F warp=5'),
 ('mart2f_clerk1',['--stage=map:CELADON_MART_2F,5,5','--sim=UA','--keys=every:25:b:60','--quit-after=500'],'TEXT_ID TEXT_CELADONMART2F_CLERK1'),
 ('mart3f_tm18',['--stage=map:CELADON_MART_3F,16,3','--sim=DA','--quit-after=600'],'GOT_TM18'),
 ('mart3f_snes',['--stage=map:CELADON_MART_3F,5,5','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_CELADONMART3F_SNES2'),
 ('mart4f_clerk',['--stage=map:CELADON_MART_4F,5,5','--sim=DA','--keys=every:25:b:60','--quit-after=500'],'TEXT_ID TEXT_CELADONMART4F_CLERK'),
 ('elevator_menu',['--stage=map:CELADON_MART_ELEVATOR,3,1','--sim=UA','--quit-after=600'],'ELEVATOR_WARPS -> CELADON_MART_1F warp=5'),
 ('elevator_shake',['--stage=map:CELADON_MART_ELEVATOR,3,1','--sim=UA','--quit-after=1200'],'ELEVATOR_SHAKE_DONE'),
 ('elevator_exit',['--stage=map:CELADON_MART_ELEVATOR,2,2','--sim=DD','--quit-after=200'],'MAP_LOAD CELADON_MART_1F (1,1)'),
 ('vending_water',['--stage=map:CELADON_MART_ROOF,10,2','--sim=UA','--quit-after=900'],'VENDING item=FRESH_WATER money=2800'),
 ('vending_cancel',['--stage=map:CELADON_MART_ROOF,10,2','--sim=UA','--keys=every:25:b:60','--quit-after=500'],'TEXT_ID TEXT_CELADONMARTROOF_VENDING_MACHINE1'),
 ('roof_girl_thirsty',['--stage=map:CELADON_MART_ROOF,4,5','--sim=RA','--quit-after=400'],'TEXT_ID TEXT_CELADONMARTROOF_LITTLE_GIRL'),
 ('roof_girl_soda',['--stage=map:CELADON_MART_ROOF,4,5','--sim=RA','--give=SODA_POP:1','--quit-after=1200'],'ROOF_GIRL drink=SODA_POP tm=TM48'),
 # the mansion, the diner
 ('mansion_meowth',['--stage=map:CELADON_MANSION_1F,0,6','--sim=UA','--quit-after=400'],'TEXT_ID TEXT_CELADONMANSION1F_MEOWTH'),
 ('game_designer',['--stage=map:CELADON_MANSION_3F,2,4','--sim=UA','--quit-after=400'],'TEXT_ID TEXT_CELADONMANSION3F_GAME_DESIGNER'),
 ('game_designer_diploma',['--stage=map:CELADON_MANSION_3F,2,4','--sim=UA','--owned=150','--quit-after=900'],'DIPLOMA shown'),
 ('eevee_gift',['--stage=map:CELADON_MANSION_ROOF_HOUSE,3,3','--sim=RA','--quit-after=600'],'EEVEE_GIFT party=2'),
 ('diner_coin_case',['--stage=map:CELADON_DINER,1,1','--sim=LA','--quit-after=600'],'GOT_COIN_CASE'),
 # the Game Corner
 ('gamecorner_hideout_wall',['--stage=map:GAME_CORNER,17,5','--sim=U','--quit-after=120'],'debug walk: blocked U at (17,5)'),
 ('gamecorner_poster',['--stage=map:GAME_CORNER,9,5','--sim=UA','--quit-after=600'],'FOUND_ROCKET_HIDEOUT'),
 ('gamecorner_stairs',['--stage=map:GAME_CORNER,17,5','--sim=UU','--event=EVENT_FOUND_ROCKET_HIDEOUT','--quit-after=300'],'MAP_LOAD ROCKET_HIDEOUT_B1F (21,2)'),
 ('gamecorner_buy_coins',['--stage=map:GAME_CORNER,5,7','--sim=UA','--give=COIN_CASE:1','--quit-after=900'],'BOUGHT_COINS coins=50 money=2000'),
 ('gamecorner_no_coin_case',['--stage=map:GAME_CORNER,5,7','--sim=UA','--quit-after=900'],'TEXT_ID TEXT_GAMECORNER_CLERK1'),
 ('gamecorner_guru_coins',['--stage=map:GAME_CORNER,4,11','--sim=RA','--give=COIN_CASE:1','--quit-after=600'],'GOT_COINS 10 coins=10'),
 ('gamecorner_gentleman_coins',['--stage=map:GAME_CORNER,16,13','--sim=RA','--give=COIN_CASE:1','--quit-after=600'],'GOT_COINS 20 coins=20'),
 ('gamecorner_hidden_coins',['--stage=map:GAME_CORNER,1,8','--sim=RLA','--give=COIN_CASE:1','--trace-pc','--quit-after=400'],'HiddenCoins 10 coins=10'),
 ('gamecorner_hidden_coins_40',['--stage=map:GAME_CORNER,9,7','--sim=RA','--give=COIN_CASE:1','--trace-pc','--quit-after=400'],'HiddenCoins 20 coins=20'),
 ('slots_out_of_order',['--stage=map:GAME_CORNER,5,12','--sim=RA','--trace-pc','--quit-after=400'],'HIDDEN_EVENT frame=3 StartSlotMachine SLOTS_OUTOFORDER'),
 ('slots_need_coin_case',['--stage=map:GAME_CORNER,2,11','--sim=LA','--trace-pc','--keys=every:25:b:60','--quit-after=400'],'HIDDEN_EVENT frame=3 StartSlotMachine ANY_FACING'),
 ('slots_play',['--stage=map:GAME_CORNER,2,11','--sim=LA','--give=COIN_CASE:1','--coins=5','--keys=every:20:a,every:700:b:650','--quit-after=6000'],'SLOTS end coins='),
 ('coin_case_use',['--stage=map:GAME_CORNER,2,11','--give=COIN_CASE:1','--coins=123','--keys=every:1000:start:10,every:1000:down:25,every:1000:a:40,every:1000:down:55,every:1000:a:70,every:1000:a:85','--quit-after=300'],'COIN_CASE coins=123'),
 ('prize_need_case',['--stage=map:GAME_CORNER_PRIZE_ROOM,2,3','--sim=UA','--quit-after=400'],'TEXT_ID TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_1'),
 ('prize_abra',['--stage=map:GAME_CORNER_PRIZE_ROOM,2,3','--sim=UA','--give=COIN_CASE:1','--coins=200','--quit-after=1500'],'PRIZE ABRA coins=20'),
 ('prize_tm_no_coins',['--stage=map:GAME_CORNER_PRIZE_ROOM,6,3','--sim=UA','--give=COIN_CASE:1','--coins=200','--quit-after=1500'],'TEXT_ID TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_3'),
 # the Rocket Hideout
 ('hideout_b1f_door_closed',['--stage=map:ROCKET_HIDEOUT_B1F,25,15','--sim=D','--quit-after=120'],'debug walk: blocked D at (25,15)'),
 ('hideout_b1f_door_open',['--stage=map:ROCKET_HIDEOUT_B1F,25,15','--sim=D','--event=EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4','--quit-after=120'],'debug walk: D from (25,15)'),
 ('hideout_b1f_stairs',['--stage=map:ROCKET_HIDEOUT_B1F,23,3','--sim=U','--quit-after=300'],'MAP_LOAD ROCKET_HIDEOUT_B2F'),
 ('hideout_b1f_elevator',['--stage=map:ROCKET_HIDEOUT_B1F,24,18','--sim=DD','--quit-after=300'],'MAP_LOAD ROCKET_HIDEOUT_ELEVATOR'),
 ('hideout_elevator_no_key',['--stage=map:ROCKET_HIDEOUT_ELEVATOR,1,2','--sim=UA','--quit-after=400'],'TEXT_ID TEXT_ROCKETHIDEOUTELEVATOR'),
 ('hideout_elevator_key',['--stage=map:ROCKET_HIDEOUT_ELEVATOR,1,2','--sim=UA','--give=LIFT_KEY:1','--quit-after=1200'],'ELEVATOR_WARPS -> ROCKET_HIDEOUT_B1F warp=4'),
 ('hideout_b2f_arrow',['--stage=map:ROCKET_HIDEOUT_B2F,4,9','--quit-after=400'],'ARROW_TILE done at (2,9)'),
 ('hideout_b2f_arrow_turns',['--stage=map:ROCKET_HIDEOUT_B2F,4,15','--quit-after=900'],'ARROW_TILE done at (8,11)'),
 ('hideout_b3f_arrow',['--stage=map:ROCKET_HIDEOUT_B3F,10,19','--quit-after=1200'],'ARROW_TILE done at (18,15)'),
 ('hideout_b4f_door_closed',['--stage=map:ROCKET_HIDEOUT_B4F,25,10','--sim=D','--quit-after=120'],'debug walk: blocked D at (25,10)'),
 ('hideout_b4f_door_open',['--stage=map:ROCKET_HIDEOUT_B4F,25,10','--sim=D','--event=EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0,EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_1','--quit-after=120'],'debug walk: D from (25,10)'),
 ('hideout_b4f_lift_key',['--stage=map:ROCKET_HIDEOUT_B4F,11,3','--sim=UA','--event=EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_2','--quit-after=400'],'LIFT_KEY_DROPPED'),
 ('hideout_giovanni_talk',['--stage=map:ROCKET_HIDEOUT_B4F,25,4','--sim=UA','--event=EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI','--quit-after=400'],'TEXT_ID TEXT_ROCKETHIDEOUTB4F_GIOVANNI'),
]
if '--full' in sys.argv:
 cases += [
  ('erika_full',['--stage=map:CELADON_GYM,4,4','--sim=UA','--party=CHARIZARD:80','--teach=FIRE_BLAST,FIRE_BLAST,FIRE_BLAST,FIRE_BLAST','--quit-after=8000'],'ERIKA_VICTORY'),
  ('celadon_gym_lass_full',['--stage=map:CELADON_GYM,2,12','--sim=UA','--party=BLASTOISE:60','--quit-after=4000'],'MAPSCRIPT CELADON_GYM -> 0'),
  ('giovanni_full',['--stage=map:ROCKET_HIDEOUT_B4F,25,4','--sim=UA','--party=CHARIZARD:80','--teach=FIRE_BLAST,FIRE_BLAST,FIRE_BLAST,FIRE_BLAST','--quit-after=8000'],'GIOVANNI_BEATEN'),
  ('gamecorner_rocket_full',['--stage=map:GAME_CORNER,9,7','--sim=UA','--party=CHARIZARD:80','--quit-after=6000'],'GAMECORNER_ROCKET_GONE'),
  ('hideout_b1f_rocket_full',['--stage=map:ROCKET_HIDEOUT_B1F,26,10','--sim=UA','--party=CHARIZARD:80','--quit-after=5000'],'MAPSCRIPT ROCKET_HIDEOUT_B1F -> 0'),
  ('route8_gambler_full',['--stage=map:ROUTE_8,13,6','--party=BLASTOISE:60','--quit-after=4000'],'MAPSCRIPT ROUTE_8 -> 0'),
 ]
results=[]
failed=[]
for name,args,marker in cases:
 command=[str(GODOT),'--headless','--path','.', '--log-file',str(OUT/(name+'.engine.log')), '--',*args,'--trace-scripts','--trace-battle','--fast']
 if not any(a.startswith('--keys=')for a in args):command.append('--keys=every:20:a')
 p=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,encoding='utf8',errors='replace',timeout=120)
 (OUT/(name+'.log')).write_text(p.stdout,encoding='utf8')
 ok=p.returncode==0 and 'SCRIPT ERROR' not in p.stdout and 'missing text label' not in p.stdout and marker in p.stdout
 if not ok and '--no-stop' in sys.argv:   # development: list every failure instead of stopping
  failed.append(name);print('FAIL '+name,flush=True);continue
 assert p.returncode==0 and 'SCRIPT ERROR' not in p.stdout and 'missing text label' not in p.stdout,(name,p.stdout)
 assert marker in p.stdout,(name,marker,p.stdout)
 results.append({'test':name,'pass':True,'command':command})
 print('PASS '+name,flush=True)
if failed:
 print('FAILED: '+', '.join(failed));sys.exit(1)
(OUT/'smoke_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
print(f'PASS {len(results)} chapter-seven smoke cases')

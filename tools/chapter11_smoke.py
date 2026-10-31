"""Run chapter-eleven map/event checks without loading or writing user saves.
GODOT=<Godot console exe> python tools/chapter11_smoke.py [--full] [--no-stop]"""
from pathlib import Path
import json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
GODOT=Path(os.environ['GODOT'])  # Godot_v4.7.2-stable_win64_console.exe
OUT=ROOT/'.tmp/chapter11';OUT.mkdir(parents=True,exist_ok=True)
maps=json.loads((ROOT/'assets/data/maps.json').read_text(encoding='utf8'))
chapter=['FUCHSIA_CITY','FUCHSIA_MART','FUCHSIA_BILLS_GRANDPAS_HOUSE','FUCHSIA_POKECENTER','WARDENS_HOUSE','SAFARI_ZONE_GATE','FUCHSIA_GYM',
 'FUCHSIA_MEETING_ROOM','FUCHSIA_GOOD_ROD_HOUSE','SAFARI_ZONE_EAST','SAFARI_ZONE_NORTH','SAFARI_ZONE_WEST','SAFARI_ZONE_CENTER',
 'SAFARI_ZONE_CENTER_REST_HOUSE','SAFARI_ZONE_SECRET_HOUSE','SAFARI_ZONE_WEST_REST_HOUSE','SAFARI_ZONE_EAST_REST_HOUSE','SAFARI_ZONE_NORTH_REST_HOUSE']
STRONG=['--party=CHARIZARD:80','--teach=FIRE_BLAST,FIRE_BLAST,FIRE_BLAST,FIRE_BLAST']
LONG=['--party=CHARIZARD:80','--teach=SLASH,SLASH,SLASH,SLASH']   # 80 PP for the long fights
SAFARI_BATTLE=['--stage=battle','--battle-map=SAFARI_ZONE_CENTER']
cases=[]
for mid in chapter:
 cases.append(('load_'+mid,[f'--stage=map:{mid},1,1','--quit-after=8'],f'MAP_LOAD {mid} '))
cases += [
 # Fuchsia City
 ('route15_to_fuchsia',['--stage=map:ROUTE_15,0,8','--sim=L','--quit-after=150'],'MAP_LOAD FUCHSIA_CITY'),
 ('route18_to_fuchsia',['--stage=map:ROUTE_18,49,8','--sim=R','--quit-after=150'],'MAP_LOAD FUCHSIA_CITY'),
 ('fuchsia_safari_door',['--stage=map:FUCHSIA_CITY,18,4','--sim=U','--quit-after=200'],'MAP_LOAD SAFARI_ZONE_GATE'),
 ('fuchsia_gym_door',['--stage=map:FUCHSIA_CITY,5,28','--sim=U','--quit-after=200'],'MAP_LOAD FUCHSIA_GYM (4,17)'),
 ('fuchsia_warden_door',['--stage=map:FUCHSIA_CITY,27,28','--sim=U','--quit-after=200'],'MAP_LOAD WARDENS_HOUSE'),
 ('fuchsia_chansey_sign',['--stage=map:FUCHSIA_CITY,33,8','--sim=UA','--quit-after=900'],'TEXT_ID TEXT_FUCHSIACITY_CHANSEY_SIGN'),
 ('fuchsia_fossil_sign',['--stage=map:FUCHSIA_CITY,7,8','--sim=UA','--quit-after=500'],'TEXT_ID TEXT_FUCHSIACITY_FOSSIL_SIGN'),
 ('fuchsia_nurse',['--stage=map:FUCHSIA_POKECENTER,3,3','--party=PIDGEY:9:PSN','--sim=UA','--quit-after=900'],'POKECENTER_HEALED'),
 ('fuchsia_bench_guy',['--stage=map:FUCHSIA_POKECENTER,1,4','--sim=LA','--trace-pc','--quit-after=400'],'PrintBenchGuyText'),
 ('fuchsia_mart_clerk',['--stage=map:FUCHSIA_MART,1,5','--sim=LA','--keys=every:25:b:60','--quit-after=500'],'TEXT_ID TEXT_FUCHSIAMART_CLERK'),
 ('good_rod',['--stage=map:FUCHSIA_GOOD_ROD_HOUSE,5,4','--sim=UA','--quit-after=700'],'GOT_GOOD_ROD'),
 ('warden_gibberish',['--stage=map:WARDENS_HOUSE,3,3','--sim=LA','--quit-after=600'],'TEXT_ID TEXT_WARDENSHOUSE_WARDEN'),
 ('warden_hm04',['--stage=map:WARDENS_HOUSE,3,3','--sim=LA','--give=GOLD_TEETH:1','--quit-after=900'],'GOT_HM04'),
 ('warden_bookshelf',['--stage=map:WARDENS_HOUSE,2,4','--sim=DA','--quit-after=300'],'debug walk'),
 # the gym
 ('koga_talk',['--stage=map:FUCHSIA_GYM,4,11','--sim=UA','--quit-after=400'],'TEXT_ID TEXT_FUCHSIAGYM_KOGA'),
 ('fuchsia_gym_statue',['--stage=map:FUCHSIA_GYM,3,16','--sim=UA','--trace-pc','--quit-after=300'],'GymStatues'),
 # the Safari Zone gate
 ('safari_join',['--stage=map:SAFARI_ZONE_GATE,4,3','--sim=U','--quit-after=900'],'SAFARI_ENTERED money=2500'),
 ('safari_join_walk_right',['--stage=map:SAFARI_ZONE_GATE,3,3','--sim=U','--quit-after=900'],'SAFARI_ENTERED money=2500'),
 ('safari_join_enters_zone',['--stage=map:SAFARI_ZONE_GATE,4,3','--sim=U','--quit-after=900'],'MAP_LOAD SAFARI_ZONE_CENTER'),
 ('safari_refuse',['--stage=map:SAFARI_ZONE_GATE,4,3','--sim=U','--keys=every:20:b','--quit-after=900'],'MAPSCRIPT SAFARI_ZONE_GATE -> 4'),
 ('safari_leaving_early',['--stage=map:SAFARI_ZONE_CENTER,14,24','--sim=DD','--safari=20:300','--script=SAFARI_ZONE_GATE:5','--quit-after=900'],'SAFARI_LEFT early'),
 ('safari_steps_game_over',['--stage=map:SAFARI_ZONE_CENTER,14,24','--sim=U','--safari=20:0','--quit-after=1200'],'SAFARI_GAME_OVER balls=20 steps=0'),
 ('safari_game_over_seen_out',['--stage=map:SAFARI_ZONE_CENTER,14,24','--sim=U','--safari=20:0','--quit-after=1500'],'SAFARI_LEFT game_over'),
 ('safari_balls_game_over',['--stage=map:SAFARI_ZONE_CENTER,14,23','--safari=0:300','--quit-after=1200'],'SAFARI_GAME_OVER balls=0'),
 ('safari_step_counts',['--stage=map:SAFARI_ZONE_CENTER,14,24','--sim=U','--safari=20:1','--quit-after=300'],'debug walk: U from (14,24)'),
 ('safari_secret_house_hm03',['--stage=map:SAFARI_ZONE_SECRET_HOUSE,3,4','--sim=UA','--quit-after=600'],'GOT_HM03'),
 ('safari_gold_teeth',['--stage=map:SAFARI_ZONE_WEST,19,8','--sim=UA','--quit-after=400'],'GOT_ITEM GOLD_TEETH'),
 # Safari battles
 ('safari_battle_menu',[*SAFARI_BATTLE,'--wild=CHANSEY:20','--safari=30:500','--battle-seed=3','--quit-after=600'],'BATTLE_MENU frame='),
 ('safari_battle_ball_used',[*SAFARI_BATTLE,'--wild=CHANSEY:20','--safari=30:500','--battle-seed=3','--quit-after=900'],'safari balls=29'),
 ('safari_battle_catch',[*SAFARI_BATTLE,'--wild=NIDORAN_M:22','--safari=30:500','--battle-seed=1','--quit-after=4000'],'BATTLE_CAUGHT NIDORAN_M ball=SAFARI_BALL'),
 ('safari_battle_bait',[*SAFARI_BATTLE,'--wild=CHANSEY:20','--safari=30:500','--battle-seed=3','--keys=every:1000:right:425,every:20:a','--quit-after=900'],'SAFARI_BAIT catch_rate=15'),
 ('safari_battle_rock',[*SAFARI_BATTLE,'--wild=CHANSEY:20','--safari=30:500','--battle-seed=3','--keys=every:1000:down:425,every:20:a','--quit-after=900'],'SAFARI_ROCK catch_rate=60'),
 ('safari_battle_run',[*SAFARI_BATTLE,'--wild=CHANSEY:20','--safari=30:500','--battle-seed=3','--keys=every:1000:down:425,every:1000:right:430,every:20:a','--quit-after=900'],'BATTLE_DONE result=ran'),
 ('safari_battle_out_of_balls',[*SAFARI_BATTLE,'--wild=CHANSEY:20','--safari=1:500','--battle-seed=3','--quit-after=1500'],'_OutOfSafariBallsText'),
]
if '--full' in sys.argv:
 cases += [
  ('koga_full',['--stage=map:FUCHSIA_GYM,4,11','--sim=UA',*LONG,'--quit-after=9000'],'KOGA_VICTORY'),
 ]
results=[]
failed=[]
for name,args,marker in cases:
 command=[str(GODOT),'--headless','--path','.', '--log-file',str(OUT/(name+'.engine.log')), '--',*args,'--trace-scripts','--trace-battle','--fast']
 if not any(a.startswith('--keys=')for a in args):command.append('--keys=every:20:a')
 p=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,encoding='utf8',errors='replace',timeout=120)
 (OUT/(name+'.log')).write_text(p.stdout,encoding='utf8')
 ok=p.returncode==0 and 'SCRIPT ERROR' not in p.stdout and 'missing text label' not in p.stdout and marker in p.stdout
 if not ok and '--no-stop' in sys.argv:
  failed.append(name);print('FAIL '+name,flush=True);continue
 assert p.returncode==0 and 'SCRIPT ERROR' not in p.stdout and 'missing text label' not in p.stdout,(name,p.stdout)
 assert marker in p.stdout,(name,marker,p.stdout)
 results.append({'test':name,'pass':True,'command':command})
 print('PASS '+name,flush=True)
if failed:
 print('FAILED: '+', '.join(failed));sys.exit(1)
(OUT/'smoke_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
print(f'PASS {len(results)} chapter-eleven smoke cases')

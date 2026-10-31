"""Run chapter-ten map/event checks without loading or writing user saves.
GODOT=<Godot console exe> python tools/chapter10_smoke.py [--full] [--no-stop]"""
from pathlib import Path
import json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
GODOT=Path(os.environ['GODOT'])  # Godot_v4.7.2-stable_win64_console.exe
OUT=ROOT/'.tmp/chapter10';OUT.mkdir(parents=True,exist_ok=True)
maps=json.loads((ROOT/'assets/data/maps.json').read_text(encoding='utf8'))
chapter=['ROUTE_13','ROUTE_14','ROUTE_15','ROUTE_15_GATE_1F','ROUTE_15_GATE_2F','ROUTE_16','ROUTE_16_GATE_1F','ROUTE_16_GATE_2F',
 'ROUTE_16_FLY_HOUSE','ROUTE_17','ROUTE_18','ROUTE_18_GATE_1F','ROUTE_18_GATE_2F']
STRONG=['--party=CHARIZARD:80','--teach=FIRE_BLAST,FIRE_BLAST,FIRE_BLAST,FIRE_BLAST']
FLUTE_KEYS='--keys=every:1000:start:10,every:1000:down:25,every:1000:a:40,every:1000:down:55,every:1000:a:70,every:1000:a:85'
cases=[]
for mid in chapter:
 cases.append(('load_'+mid,[f'--stage=map:{mid},1,1','--quit-after=8'],f'MAP_LOAD {mid} '))
cases += [
 # Routes 12-15
 ('route12_to_13',['--stage=map:ROUTE_12,10,107','--sim=D','--repel=99','--quit-after=200'],'MAP_LOAD ROUTE_13'),
 ('route13_trainer_sight',['--stage=map:ROUTE_13,29,10','--sim=LL','--quit-after=600'],'TRAINER_SEES'),
 ('route13_sign',['--stage=map:ROUTE_13,31,12','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_ROUTE13_SIGN'),
 ('route13_hidden_pp_up',['--stage=map:ROUTE_13,1,13','--sim=DA','--trace-pc','--quit-after=300'],'HiddenItems PP_UP'),
 ('route15_tm_rage',['--stage=map:ROUTE_15,18,6','--sim=UA','--quit-after=400'],'GOT_ITEM TM20'),
 ('route15_gate_enter',['--stage=map:ROUTE_15,15,8','--sim=LL','--quit-after=200'],'MAP_LOAD ROUTE_15_GATE_1F'),
 ('route15_gate_up',['--stage=map:ROUTE_15_GATE_1F,6,7','--sim=D','--quit-after=200'],'MAP_LOAD ROUTE_15_GATE_2F'),
 ('route15_aide_not_enough',['--stage=map:ROUTE_15_GATE_2F,4,3','--sim=UA','--quit-after=900'],'OAKS_AIDE not_enough EXP_ALL'),
 ('route15_aide_exp_all',['--stage=map:ROUTE_15_GATE_2F,4,3','--sim=UA','--owned=50','--quit-after=900'],'OAKS_AIDE got EXP_ALL'),
 ('route15_binoculars_articuno',['--stage=map:ROUTE_15_GATE_2F,1,3','--sim=UA','--trace-pc','--quit-after=600'],'Route15GateLeftBinoculars'),
 # Route 16, the Cycling Road gates
 ('route16_snorlax_talk',['--stage=map:ROUTE_16,25,10','--sim=RA','--quit-after=300'],'TEXT_ID TEXT_ROUTE16_SNORLAX'),
 ('route16_flute_snorlax',['--stage=map:ROUTE_16,25,10','--give=POKE_FLUTE:1',FLUTE_KEYS,'--quit-after=1200'],'TEXT_ID TEXT_ROUTE16_SNORLAX_WOKE_UP'),
 ('route16_flute_far',['--stage=map:ROUTE_16,24,10','--give=POKE_FLUTE:1',FLUTE_KEYS,'--quit-after=400'],'POKE_FLUTE effect=false'),
 ('route16_fly_house_hm02',['--stage=map:ROUTE_16_FLY_HOUSE,3,3','--sim=LA','--quit-after=600'],'GOT_HM02'),
 ('route16_fly_house_door',['--stage=map:ROUTE_16,7,6','--sim=U','--quit-after=200'],'MAP_LOAD ROUTE_16_FLY_HOUSE'),
 ('gate16_no_bike_stop',['--stage=map:ROUTE_16_GATE_1F,5,8','--sim=L','--quit-after=600'],'GATE_STOP ROUTE_16_GATE_1F idx=2'),
 ('gate16_no_bike_pushed',['--stage=map:ROUTE_16_GATE_1F,5,8','--sim=L','--quit-after=800'],'GATE_PUSHED ROUTE_16_GATE_1F (5,7)'),
 ('gate16_guard_text',['--stage=map:ROUTE_16_GATE_1F,5,8','--sim=L','--quit-after=600'],'TEXT_ID TEXT_ROUTE16GATE1F_GUARD '),
 ('gate16_bike_passes',['--stage=map:ROUTE_16_GATE_1F,5,8','--sim=LLLLLL','--give=BICYCLE:1','--last-map=ROUTE_16','--quit-after=400'],'MAP_LOAD ROUTE_16 (17,10)'),
 ('gate16_forced_bike',['--stage=map:ROUTE_16_GATE_1F,5,8','--sim=LLLLLL','--give=BICYCLE:1','--last-map=ROUTE_16','--quit-after=400'],'FORCED_BIKE ROUTE_16 (17,10)'),
 ('gate16_upstairs',['--stage=map:ROUTE_16_GATE_1F,6,11','--sim=D','--quit-after=200'],'MAP_LOAD ROUTE_16_GATE_2F'),
 ('gate16_2f_binoculars',['--stage=map:ROUTE_16_GATE_2F,1,3','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_ROUTE16GATE2F_LEFT_BINOCULARS'),
 ('gate18_no_bike_stop',['--stage=map:ROUTE_18_GATE_1F,5,4','--sim=L','--quit-after=600'],'GATE_STOP ROUTE_18_GATE_1F idx=2'),
 ('gate18_trade',['--stage=map:ROUTE_18_GATE_2F,4,3','--sim=UA','--seed=1','--keys=every:25:b:60','--quit-after=600'],'TEXT_ID TEXT_ROUTE18GATE2F_YOUNGSTER'),
 # the Cycling Road
 ('cycling_road_downhill',['--stage=map:ROUTE_17,10,136','--quit-after=300'],'MAP_LOAD ROUTE_18'),
 ('route17_trainer_sight',['--stage=map:ROUTE_17,5,31','--quit-after=600'],'TRAINER_SEES'),
 ('route17_sign',['--stage=map:ROUTE_17,9,52','--sim=UA','--keys=every:20:a:5','--quit-after=300'],'TEXT_ID TEXT_ROUTE17_NOTICE_SIGN1'),
 ('route18_gate_enter',['--stage=map:ROUTE_18,32,8','--sim=RR','--quit-after=200'],'MAP_LOAD ROUTE_18_GATE_1F'),
 ('route18_forced_bike',['--stage=map:ROUTE_18_GATE_1F,1,4','--sim=LL','--give=BICYCLE:1','--last-map=ROUTE_18','--quit-after=400'],'FORCED_BIKE ROUTE_18 (33,8)'),
 ('forced_bike_cant_get_off',['--stage=map:ROUTE_18_GATE_1F,1,4','--sim=LL','--give=BICYCLE:1','--last-map=ROUTE_18','--keys=every:1000:start:120,every:1000:down:135,every:1000:a:150,every:1000:down:165,every:1000:a:180,every:1000:a:195','--quit-after=600'],'BICYCLE cannot_get_off'),
]
if '--full' in sys.argv:
 cases += [
  ('snorlax16_full',['--stage=map:ROUTE_16,25,10','--give=POKE_FLUTE:1',*STRONG,FLUTE_KEYS.replace('every:1000:a:85','every:1000:a:85,every:20:a:300'),'--quit-after=8000'],'SNORLAX_DONE result=won'),
  ('route17_trainer_full',['--stage=map:ROUTE_17,5,31',*STRONG,'--quit-after=6000'],'MAPSCRIPT ROUTE_17 -> 0'),
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
print(f'PASS {len(results)} chapter-ten smoke cases')

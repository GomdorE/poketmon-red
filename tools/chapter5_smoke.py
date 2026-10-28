"""Run chapter-five map/event checks without loading or writing user saves.
GODOT=<Godot console exe> python tools/chapter5_smoke.py [--full]"""
from pathlib import Path
import json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
GODOT=Path(os.environ['GODOT'])  # Godot_v4.7.2-stable_win64_console.exe
OUT=ROOT/'.tmp/chapter5';OUT.mkdir(parents=True,exist_ok=True)
maps=json.loads((ROOT/'assets/data/maps.json').read_text(encoding='utf8'))
chapter=['ROUTE_9','ROUTE_10','ROCK_TUNNEL_POKECENTER','ROUTE_5','ROUTE_5_GATE','UNDERGROUND_PATH_ROUTE_5','DAYCARE','UNDERGROUND_PATH_NORTH_SOUTH','UNDERGROUND_PATH_ROUTE_6','ROUTE_6_GATE','ROUTE_6']
cases=[]
for mid in chapter:
 cases.append(('load_'+mid,[f'--stage=map:{mid},1,1','--quit-after=8'],f'MAP_LOAD {mid} '))
cases += [
 # Cerulean City east exit -> Route 9 (the connection opens now that Route 9 is exported)
 ('cerulean_route9',['--stage=map:CERULEAN_CITY,39,17','--sim=R','--quit-after=150'],'MAP_LOAD ROUTE_9'),
 ('route9_route10',['--stage=map:ROUTE_9,59,9','--sim=R','--quit-after=150'],'MAP_LOAD ROUTE_10'),
 ('route10_pokecenter',['--stage=map:ROUTE_10,11,20','--sim=U','--quit-after=200'],'MAP_LOAD ROCK_TUNNEL_POKECENTER'),
 # the Rock Tunnel entrance leads to a map a later chapter exports: no crash, no warp
 ('route10_tunnel_inert',['--stage=map:ROUTE_10,8,18','--sim=UU','--quit-after=200'],'WARP_UNEXPORTED ROUTE_10 -> ROCK_TUNNEL_1F'),
 ('route9_trainer_sight',['--stage=map:ROUTE_9,22,4','--party=BLASTOISE:60','--quit-after=600'],'TRAINER_SEES'),
 ('route9_sign',['--stage=map:ROUTE_9,25,8','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_ROUTE9_SIGN'),
 ('route10_powerplant_sign',['--stage=map:ROUTE_10,5,42','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_ROUTE10_POWERPLANT_SIGN'),
 ('rocktunnel_nurse',['--stage=map:ROCK_TUNNEL_POKECENTER,3,3','--party=PIDGEY:9:PSN','--sim=UA','--quit-after=900'],'POKECENTER_HEALED'),
 # Routes 5/6: the gates, the Underground Path and the Daycare
 ('cerulean_route5',['--stage=map:CERULEAN_CITY,19,35','--sim=D','--quit-after=150'],'MAP_LOAD ROUTE_5'),
 ('route5_gate_thirsty',['--stage=map:ROUTE_5_GATE,3,1','--sim=DD','--quit-after=600'],'TEXT_ID TEXT_ROUTE5GATE_GUARD_GEE_IM_THIRSTY'),
 ('route5_gate_drink',['--stage=map:ROUTE_5_GATE,3,1','--sim=DD','--give=SODA_POP:1','--quit-after=900'],'GUARD_DRINK item=SODA_POP'),
 ('route6_gate_thirsty',['--stage=map:ROUTE_6_GATE,3,4','--sim=UU','--quit-after=600'],'TEXT_ID TEXT_ROUTE6GATE_GUARD_GEE_IM_THIRSTY'),
 ('underground_to_route6',['--stage=map:UNDERGROUND_PATH_NORTH_SOUTH,2,40','--sim=D|DDDD','--quit-after=600'],'MAP_LOAD ROUTE_6 (17,13)'),
 ('underground_to_route5',['--stage=map:UNDERGROUND_PATH_NORTH_SOUTH,5,5','--sim=U|LDDDD','--quit-after=600'],'MAP_LOAD ROUTE_5 (17,27)'),
 ('underground_hidden',['--stage=map:UNDERGROUND_PATH_NORTH_SOUTH,3,6','--sim=UA','--trace-pc','--quit-after=300'],'HiddenItems FULL_RESTORE'),
 ('daycare_deposit_withdraw',['--stage=map:DAYCARE,3,3','--party=PIDGEY:9,RATTATA:5','--sim=LA','--quit-after=2500'],'DAYCARE_WITHDRAW RATTATA'),
 ('daycare_hm_refused',['--stage=map:DAYCARE,3,3','--party=BULBASAUR:12,RATTATA:5','--teach=CUT','--sim=LA','--quit-after=800'],'DAYCARE_HM_REFUSED BULBASAUR'),
 ('trade_spot',['--stage=map:UNDERGROUND_PATH_ROUTE_5,3,3','--party=NIDORAN_M:10,PIDGEY:9','--sim=LA','--keys=every:25:a:60','--quit-after=3200'],'IN_GAME_TRADE_TEXT _Thanks3Text'),
 ('route9_hidden_ether',['--stage=map:ROUTE_9,14,8','--sim=UA','--trace-pc','--quit-after=300'],'HiddenItems ETHER'),
]
if '--full' in sys.argv:
 cases += [
  ('route9_hiker_full',['--stage=map:ROUTE_9,45,16','--sim=UA','--party=BLASTOISE:60','--quit-after=4000'],'MAPSCRIPT ROUTE_9 -> 0'),
  ('route6_trainer_full',['--stage=map:ROUTE_6,1,15','--sim=LA','--party=BLASTOISE:60','--quit-after=4000'],'MAPSCRIPT ROUTE_6 -> 0'),
  ('route10_pokemaniac_full',['--stage=map:ROUTE_10,9,44','--sim=RA','--party=BLASTOISE:60','--quit-after=4000'],'MAPSCRIPT ROUTE_10 -> 0'),
 ]
results=[]
for name,args,marker in cases:
 command=[str(GODOT),'--headless','--path','.', '--log-file',str(OUT/(name+'.engine.log')), '--',*args,'--trace-scripts','--trace-battle','--fast']
 if not any(a.startswith('--keys=')for a in args):command.append('--keys=every:20:a')
 p=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,encoding='utf8',errors='replace',timeout=120)
 (OUT/(name+'.log')).write_text(p.stdout,encoding='utf8')
 assert p.returncode==0 and 'SCRIPT ERROR' not in p.stdout and 'missing text label' not in p.stdout,(name,p.stdout)
 assert marker in p.stdout,(name,marker,p.stdout)
 results.append({'test':name,'pass':True,'command':command})
 print('PASS '+name,flush=True)
(OUT/'smoke_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
print(f'PASS {len(results)} chapter-five smoke cases')

"""Run chapter-six map/event checks without loading or writing user saves.
GODOT=<Godot console exe> python tools/chapter6_smoke.py [--full]"""
from pathlib import Path
import json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
GODOT=Path(os.environ['GODOT'])  # Godot_v4.7.2-stable_win64_console.exe
OUT=ROOT/'.tmp/chapter6';OUT.mkdir(parents=True,exist_ok=True)
maps=json.loads((ROOT/'assets/data/maps.json').read_text(encoding='utf8'))
chapter=['ROUTE_11','ROUTE_11_GATE_1F','ROUTE_11_GATE_2F','DIGLETTS_CAVE_ROUTE_11','DIGLETTS_CAVE','DIGLETTS_CAVE_ROUTE_2','ROUTE_2_TRADE_HOUSE','ROUTE_2_GATE','ROCK_TUNNEL_1F','ROCK_TUNNEL_B1F','LAVENDER_TOWN','LAVENDER_POKECENTER','LAVENDER_MART','NAME_RATERS_HOUSE','LAVENDER_CUBONE_HOUSE','MR_FUJIS_HOUSE','POKEMON_TOWER_1F','POKEMON_TOWER_2F']
cases=[]
for mid in chapter:
 cases.append(('load_'+mid,[f'--stage=map:{mid},1,1','--quit-after=8'],f'MAP_LOAD {mid} '))
cases += [
 ('vermilion_route11',['--stage=map:VERMILION_CITY,39,12','--sim=R','--quit-after=150'],'MAP_LOAD ROUTE_11'),
 ('route11_gate',['--stage=map:ROUTE_11,48,8','--sim=RR','--quit-after=200'],'MAP_LOAD ROUTE_11_GATE_1F'),
 ('gate_upstairs',['--stage=map:ROUTE_11_GATE_1F,6,7','--sim=D','--quit-after=200'],'MAP_LOAD ROUTE_11_GATE_2F'),
 ('route11_trainer_sight',['--stage=map:ROUTE_11,11,5','--party=BLASTOISE:60','--quit-after=600'],'TRAINER_SEES'),
 ('aide_not_enough',['--stage=map:ROUTE_11_GATE_2F,3,6','--sim=LA','--quit-after=900'],'OAKS_AIDE not_enough ITEMFINDER'),
 ('aide_itemfinder',['--stage=map:ROUTE_11_GATE_2F,3,6','--sim=LA','--owned=30','--quit-after=1200'],'OAKS_AIDE got ITEMFINDER owned=30'),
 ('aide_refuse',['--stage=map:ROUTE_2_GATE,2,4','--sim=LA','--keys=every:25:b:60','--quit-after=600'],'OAKS_AIDE refused HM05'),
 ('aide_flash',['--stage=map:ROUTE_2_GATE,2,4','--sim=LA','--owned=10','--quit-after=1200'],'OAKS_AIDE got HM05 owned=10'),
 ('binoculars',['--stage=map:ROUTE_11_GATE_2F,6,3','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_ROUTE11GATE2F_RIGHT_BINOCULARS'),
 ('route11_cave_entrance',['--stage=map:ROUTE_11,4,6','--sim=UU','--quit-after=200'],'MAP_LOAD DIGLETTS_CAVE_ROUTE_11'),
 ('cave_ladder_route11',['--stage=map:DIGLETTS_CAVE,37,30','--sim=D','--quit-after=200'],'MAP_LOAD DIGLETTS_CAVE_ROUTE_11 (4,4)'),
 ('cave_ladder_route2',['--stage=map:DIGLETTS_CAVE,5,6','--sim=U','--quit-after=200'],'MAP_LOAD DIGLETTS_CAVE_ROUTE_2 (4,4)'),
 ('cave_exit_route2',['--stage=map:DIGLETTS_CAVE_ROUTE_2,2,6','--sim=DD','--quit-after=200'],'MAP_LOAD ROUTE_2 (12,9)'),
 ('cave_exit_route11',['--stage=map:DIGLETTS_CAVE_ROUTE_11,2,6','--sim=DD','--quit-after=200'],'MAP_LOAD ROUTE_11 (4,5)'),
 ('trade_marcel',['--stage=map:ROUTE_2_TRADE_HOUSE,4,2','--party=ABRA:10,PIDGEY:9','--sim=UA','--keys=every:25:a:60','--quit-after=3200'],'IN_GAME_TRADE_TEXT _Thanks1Text'),
 # Rock Tunnel and Lavender Town
 ('tunnel_enter_dark',['--stage=map:ROUTE_10,8,18','--sim=UU','--quit-after=300'],'MAP_PAL_OFFSET 6 map=ROUTE_10'),
 ('tunnel_enter_load',['--stage=map:ROUTE_10,8,18','--sim=UU','--quit-after=300'],'MAP_LOAD ROCK_TUNNEL_1F (15,3)'),
 ('tunnel_exit_light',['--stage=map:ROCK_TUNNEL_1F,15,4','--sim=U','--last-map=ROUTE_10','--quit-after=300'],'MAP_PAL_OFFSET 0 map=ROCK_TUNNEL_1F'),
 ('tunnel_exit_route10',['--stage=map:ROCK_TUNNEL_1F,15,4','--sim=U','--last-map=ROUTE_10','--quit-after=300'],'MAP_LOAD ROUTE_10 (8,17)'),
 ('tunnel_ladder_b1f',['--stage=map:ROCK_TUNNEL_1F,37,2','--sim=D','--quit-after=300'],'MAP_LOAD ROCK_TUNNEL_B1F (33,25)'),
 ('tunnel_ladder_1f',['--stage=map:ROCK_TUNNEL_B1F,33,24','--sim=D','--quit-after=300'],'MAP_LOAD ROCK_TUNNEL_1F (37,3)'),
 ('tunnel_trainer_sight',['--stage=map:ROCK_TUNNEL_1F,7,8','--party=BLASTOISE:60','--quit-after=600'],'TRAINER_SEES'),
 ('route10_lavender',['--stage=map:ROUTE_10,7,71','--sim=D','--quit-after=150'],'MAP_LOAD LAVENDER_TOWN'),
 ('lavender_nurse',['--stage=map:LAVENDER_POKECENTER,3,3','--party=PIDGEY:9:PSN','--sim=UA','--quit-after=900'],'POKECENTER_HEALED'),
 ('cubone_house',['--stage=map:LAVENDER_CUBONE_HOUSE,3,4','--sim=LA','--quit-after=400'],'TEXT_ID TEXT_LAVENDERCUBONEHOUSE_BRUNETTE_GIRL'),
 ('fuji_house_girl',['--stage=map:MR_FUJIS_HOUSE,6,2','--sim=DA','--quit-after=400'],'TEXT_ID TEXT_MRFUJISHOUSE_LITTLE_GIRL'),
 ('fuji_flute',['--stage=map:MR_FUJIS_HOUSE,3,2','--sim=UA','--event=EVENT_RESCUED_MR_FUJI,SHOW_MR_FUJIS_HOUSE_4','--quit-after=1200'],'POKE_FLUTE_RECEIVED'),
 ('name_rater_cancel',['--stage=map:NAME_RATERS_HOUSE,4,3','--sim=RA','--keys=every:25:b:60','--quit-after=600'],'NAME_RATER cancel'),
 ('name_rater_not_mine',['--stage=map:NAME_RATERS_HOUSE,4,3','--party=POLIWHIRL:20','--sim=RA','--trade-mon','--quit-after=1200'],'NAME_RATER not_mine'),
 ('tower_2f_channeler',['--stage=map:POKEMON_TOWER_2F,4,7','--sim=LA','--quit-after=400'],'TEXT_ID TEXT_POKEMONTOWER2F_CHANNELER'),
 ('route11_hidden_rope',['--stage=map:ROUTE_11,48,6','--sim=UA','--trace-pc','--quit-after=300'],'HiddenItems ESCAPE_ROPE'),
]
if '--full' in sys.argv:
 cases += [
  ('tower_rival_full',['--stage=map:POKEMON_TOWER_2F,15,6','--sim=U','--party=BLASTOISE:60','--quit-after=8000'],'TOWER_RIVAL_DONE'),
  ('tunnel_hiker_full',['--stage=map:ROCK_TUNNEL_1F,7,8','--party=BLASTOISE:60','--quit-after=4000'],'MAPSCRIPT ROCK_TUNNEL_1F -> 0'),
  ('route11_gambler_full',['--stage=map:ROUTE_11,10,15','--sim=UA','--party=BLASTOISE:60','--quit-after=4000'],'MAPSCRIPT ROUTE_11 -> 0'),
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
print(f'PASS {len(results)} chapter-six smoke cases')

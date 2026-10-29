"""Run chapter-eight map/event checks without loading or writing user saves.
GODOT=<Godot console exe> python tools/chapter8_smoke.py [--full] [--no-stop]"""
from pathlib import Path
import json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
GODOT=Path(os.environ['GODOT'])  # Godot_v4.7.2-stable_win64_console.exe
OUT=ROOT/'.tmp/chapter8';OUT.mkdir(parents=True,exist_ok=True)
maps=json.loads((ROOT/'assets/data/maps.json').read_text(encoding='utf8'))
chapter=['POKEMON_TOWER_3F','POKEMON_TOWER_4F','POKEMON_TOWER_5F','POKEMON_TOWER_6F','POKEMON_TOWER_7F','ROUTE_12','ROUTE_12_GATE_1F','ROUTE_12_GATE_2F','ROUTE_12_SUPER_ROD_HOUSE']
cases=[]
for mid in chapter:
 cases.append(('load_'+mid,[f'--stage=map:{mid},1,1','--quit-after=8'],f'MAP_LOAD {mid} '))
FLUTE_KEYS='--keys=every:1000:start:10,every:1000:down:25,every:1000:a:40,every:1000:down:55,every:1000:a:70,every:1000:a:85'
cases += [
 # Pokémon Tower
 ('tower2f_up',['--stage=map:POKEMON_TOWER_2F,4,9','--sim=L','--quit-after=200'],'MAP_LOAD POKEMON_TOWER_3F'),
 ('tower5f_purified',['--stage=map:POKEMON_TOWER_5F,10,11','--sim=UU','--party=PIDGEY:9:PSN','--repel=50','--quit-after=600'],'PURIFIED_ZONE'),
 ('tower5f_purified_text',['--stage=map:POKEMON_TOWER_5F,10,11','--sim=UU','--repel=50','--quit-after=600'],'TEXT_ID TEXT_POKEMONTOWER5F_PURIFIEDZONE'),
 ('tower6f_begone',['--stage=map:POKEMON_TOWER_6F,10,17','--sim=U','--quit-after=400'],'TEXT_ID TEXT_POKEMONTOWER6F_BEGONE'),
 ('tower6f_ghost_unidentified',['--stage=map:POKEMON_TOWER_6F,10,17','--sim=U','--quit-after=1500'],'BATTLE_TEXT frame=',),
 ('tower6f_ghost_cant_id',['--stage=map:POKEMON_TOWER_6F,10,17','--sim=U','--quit-after=1500'],'_GhostCantBeIDdText'),
 ('tower6f_ghost_scared',['--stage=map:POKEMON_TOWER_6F,10,17','--sim=U','--quit-after=3000'],'_ScaredText'),
 ('tower6f_ghost_get_out',['--stage=map:POKEMON_TOWER_6F,10,17','--sim=U','--quit-after=3000'],'_GetOutText'),
 ('tower6f_marowak_unveiled',['--stage=map:POKEMON_TOWER_6F,10,17','--sim=U','--give=SILPH_SCOPE:1','--quit-after=2500'],'_UnveiledGhostText'),
 ('tower6f_beaten_no_ghost',['--stage=map:POKEMON_TOWER_6F,10,17','--sim=U','--event=EVENT_BEAT_GHOST_MAROWAK','--quit-after=300'],'debug walk: U from (10,17)'),
 ('tower7f_fuji',['--stage=map:POKEMON_TOWER_7F,10,4','--sim=UA','--quit-after=900'],'FUJI_RESCUED'),
 ('tower7f_fuji_warp',['--stage=map:POKEMON_TOWER_7F,10,4','--sim=UA','--quit-after=900'],'MAP_LOAD MR_FUJIS_HOUSE (3,7)'),
 # Route 12
 ('lavender_route12',['--stage=map:LAVENDER_TOWN,9,17','--sim=D','--quit-after=200'],'MAP_LOAD ROUTE_12'),
 ('route12_gate_enter',['--stage=map:ROUTE_12,10,14','--sim=DD','--quit-after=200'],'MAP_LOAD ROUTE_12_GATE_1F'),
 ('route12_gate_upstairs',['--stage=map:ROUTE_12_GATE_1F,8,5','--sim=DD','--quit-after=200'],'MAP_LOAD ROUTE_12_GATE_2F'),
 ('route12_gate_tm39',['--stage=map:ROUTE_12_GATE_2F,4,4','--sim=LA','--quit-after=600'],'GOT_TM39'),
 ('route12_snorlax_talk',['--stage=map:ROUTE_12,10,63','--sim=UA','--quit-after=400'],'TEXT_ID TEXT_ROUTE12_SNORLAX'),
 ('route12_flute_no_effect',['--stage=map:ROUTE_12,10,65','--give=POKE_FLUTE:1',FLUTE_KEYS,'--quit-after=400'],'POKE_FLUTE effect=false'),
 ('route12_flute_snorlax',['--stage=map:ROUTE_12,10,63','--give=POKE_FLUTE:1',FLUTE_KEYS,'--quit-after=1200'],'TEXT_ID TEXT_ROUTE12_SNORLAX_WOKE_UP'),
 ('route12_super_rod',['--stage=map:ROUTE_12_SUPER_ROD_HOUSE,2,5','--sim=UA','--quit-after=600'],'GOT_SUPER_ROD'),
 ('route12_super_rod_again',['--stage=map:ROUTE_12_SUPER_ROD_HOUSE,2,5','--sim=UA','--event=GOT_SUPER_ROD','--quit-after=400'],'TEXT_ID TEXT_ROUTE12SUPERRODHOUSE_FISHING_GURU'),
]
if '--full' in sys.argv:
 cases += [
  ('marowak_full',['--stage=map:POKEMON_TOWER_6F,10,17','--sim=U','--give=SILPH_SCOPE:1','--party=CHARIZARD:80','--teach=FIRE_BLAST,FIRE_BLAST,FIRE_BLAST,FIRE_BLAST','--quit-after=8000'],'MAROWAK_DEPARTED'),
  ('tower7f_rocket_full',['--stage=map:POKEMON_TOWER_7F,9,12','--sim=UA','--party=CHARIZARD:80','--teach=FIRE_BLAST,FIRE_BLAST,FIRE_BLAST,FIRE_BLAST','--quit-after=6000'],'ROCKET_LEFT'),
  ('snorlax_full',['--stage=map:ROUTE_12,10,63','--give=POKE_FLUTE:1','--party=CHARIZARD:80','--teach=FIRE_BLAST,FIRE_BLAST,FIRE_BLAST,FIRE_BLAST',FLUTE_KEYS.replace('every:1000:a:85','every:1000:a:85,every:20:a:300'),'--quit-after=8000'],'SNORLAX_DONE result=won'),
  ('tower3f_channeler_full',['--stage=map:POKEMON_TOWER_3F,1,1','--party=CHARIZARD:80','--teach=FIRE_BLAST,FIRE_BLAST,FIRE_BLAST,FIRE_BLAST','--quit-after=8'],'MAP_LOAD POKEMON_TOWER_3F'),
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
print(f'PASS {len(results)} chapter-eight smoke cases')

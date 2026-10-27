"""Run chapter-four map/transaction boundaries without loading or writing user saves."""
from pathlib import Path
import json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
GODOT=Path(os.environ['GODOT'])  # Godot_v4.7.2-stable_win64_console.exe
OUT=ROOT/'.tmp/chapter4';OUT.mkdir(parents=True,exist_ok=True)
maps=json.loads((ROOT/'assets/data/maps.json').read_text(encoding='utf8'))
chapter=['ROUTE_3','MT_MOON_POKECENTER','MT_MOON_1F','MT_MOON_B1F','MT_MOON_B2F','ROUTE_4','CERULEAN_CITY','CERULEAN_GYM','CERULEAN_MART','CERULEAN_POKECENTER','CERULEAN_TRADE_HOUSE','CERULEAN_TRASHED_HOUSE','CERULEAN_BADGE_HOUSE','BIKE_SHOP','ROUTE_24','ROUTE_25','BILLS_HOUSE']
cases=[]
for mid in chapter:
 cases.append(('load_'+mid,[f'--stage=map:{mid},1,1','--quit-after=8'],f'MAP_LOAD {mid} '))
fullbag='ANTIDOTE,PARLYZ_HEAL,BURN_HEAL,ICE_HEAL,AWAKENING,FULL_HEAL,FULL_RESTORE,MAX_POTION,HYPER_POTION,SUPER_POTION,POKE_BALL,GREAT_BALL,ULTRA_BALL,MASTER_BALL,ESCAPE_ROPE,REPEL,MAX_REPEL,SUPER_REPEL,ETHER'
cases += [
 ('route3_trainer',['--stage=map:ROUTE_3,14,7','--party=BLASTOISE:60','--quit-after=600'],'TRAINER_SEES'),
 ('cave_ladder',['--stage=map:MT_MOON_1F,5,6','--sim=U','--party=BLASTOISE:60','--quit-after=250'],'MAP_LOAD MT_MOON_B1F'),
 ('fossil_full_bag',['--stage=map:MT_MOON_B2F,12,7','--sim=UA','--event=EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD','--give='+','.join(i+':1'for i in fullbag.split(',')),'--quit-after=600'],'FOSSIL_REJECTED bag_full'),
 ('fossil_no',['--stage=map:MT_MOON_B2F,12,7','--sim=UA','--event=EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD','--keys=every:20:b','--quit-after=600'],'FOSSIL_DECLINED'),
 ('misty_tm_retry',['--stage=map:CERULEAN_GYM,4,3','--sim=UA','--event=EVENT_BEAT_MISTY,EVENT_BEAT_CERULEAN_GYM_TRAINER_0,EVENT_BEAT_CERULEAN_GYM_TRAINER_1','--quit-after=1000'],'MISTY_VICTORY badges=2 tm11=1'),
 ('trade_lola',['--stage=map:CERULEAN_TRADE_HOUSE,1,4','--party=POLIWHIRL:20,PIDGEY:9','--sim=UUA','--keys=every:25:a:60','--quit-after=3200'],'IN_GAME_TRADE_TEXT _Thanks2Text'),
 ('trade_no',['--stage=map:CERULEAN_TRADE_HOUSE,1,4','--party=POLIWHIRL:20','--sim=UUA','--keys=every:25:b:60','--quit-after=500'],'IN_GAME_TRADE_TEXT _NoTrade2Text'),
 ('trade_wrong_mon',['--stage=map:CERULEAN_TRADE_HOUSE,1,4','--party=PIDGEY:9,POLIWHIRL:20','--sim=UUA','--keys=every:25:a:60','--quit-after=700'],'IN_GAME_TRADE_TEXT _WrongMon2Text'),
 ('route4_cerulean',['--stage=map:ROUTE_4,89,10','--sim=R','--quit-after=150'],'MAP_LOAD CERULEAN_CITY'),
]
if '--full' in sys.argv:
 cases += [
  ('fossil_dome',['--stage=map:MT_MOON_B2F,12,7','--sim=UA','--event=EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD','--quit-after=700'],'FOSSIL_SELECTED DOME_FOSSIL'),
  ('fossil_helix',['--stage=map:MT_MOON_B2F,13,7','--sim=UA','--event=EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD','--quit-after=700'],'FOSSIL_SELECTED HELIX_FOSSIL'),
  ('magikarp',['--stage=map:MT_MOON_POKECENTER,10,7','--sim=UA','--party=BLASTOISE:60','--quit-after=700'],'MAGIKARP_PURCHASE money=2500'),
  ('bike_voucher',['--stage=map:BIKE_SHOP,6,3','--give=BIKE_VOUCHER:1','--sim=UA','--quit-after=700'],'BIKE_EXCHANGED voucher=0 bicycle=1'),
  ('nerd_full',['--stage=map:MT_MOON_B2F,13,8','--party=BLASTOISE:60','--quit-after=4300'],'MAPSCRIPT MT_MOON_B2F -> 0'),
  ('misty_full',['--stage=map:CERULEAN_GYM,4,3','--sim=UA','--party=BLASTOISE:60','--event=EVENT_BEAT_CERULEAN_GYM_TRAINER_0,EVENT_BEAT_CERULEAN_GYM_TRAINER_1','--quit-after=5000'],'MISTY_VICTORY badges=2 tm11=1'),
  ('bridge_full',['--stage=map:ROUTE_24,10,15','--party=BLASTOISE:60','--quit-after=5000'],'MAPSCRIPT ROUTE_24 -> 0'),
  ('rival_full',['--stage=map:CERULEAN_CITY,20,6','--party=BLASTOISE:60','--quit-after=8000'],'MAPSCRIPT CERULEAN_CITY -> 3'),
  ('rocket_full',['--stage=map:CERULEAN_CITY,30,9','--party=BLASTOISE:60','--quit-after=4300'],'CERULEAN_TM28 item=1 rocket_hidden=true'),
  ('bill_full',['--stage=map:BILLS_HOUSE,6,6','--sim=UALLLLLUDUDUDUDUARRRUA','--party=BLASTOISE:60','--quit-after=2200'],'SS_TICKET_RECEIVED qty=1'),
 ]
results=[]
for name,args,marker in cases:
 command=[str(GODOT),'--headless','--path','.', '--log-file',str(OUT/(name+'.engine.log')), '--',*args,'--trace-scripts','--trace-battle','--fast']
 if not any(a.startswith('--keys=')for a in args):command.append('--keys=every:20:a')
 p=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,encoding='utf8',errors='replace',timeout=90)
 (OUT/(name+'.log')).write_text(p.stdout,encoding='utf8')
 assert p.returncode==0 and 'SCRIPT ERROR' not in p.stdout and 'missing text label' not in p.stdout,(name,p.stdout)
 if marker=='__NO_FOSSIL__':assert 'FOSSIL_SELECTED'not in p.stdout,(name,p.stdout)
 else:assert marker in p.stdout,(name,marker,p.stdout)
 results.append({'test':name,'pass':True,'command':command,'shutdown_resource_warning':'resources still in use at exit'in p.stdout})
 print('PASS '+name,flush=True)
(OUT/'smoke_results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
print(f'PASS {len(results)} chapter-four smoke cases')

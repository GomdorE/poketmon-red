"""Run chapter-nine map/event checks without loading or writing user saves.
GODOT=<Godot console exe> python tools/chapter9_smoke.py [--full] [--no-stop]"""
from pathlib import Path
import json,os,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
GODOT=Path(os.environ['GODOT'])  # Godot_v4.7.2-stable_win64_console.exe
OUT=ROOT/'.tmp/chapter9';OUT.mkdir(parents=True,exist_ok=True)
maps=json.loads((ROOT/'assets/data/maps.json').read_text(encoding='utf8'))
chapter=['SAFFRON_CITY','SAFFRON_POKECENTER','SAFFRON_MART','SAFFRON_PIDGEY_HOUSE','MR_PSYCHICS_HOUSE','COPYCATS_HOUSE_1F','COPYCATS_HOUSE_2F',
 'FIGHTING_DOJO','SAFFRON_GYM','SILPH_CO_1F','SILPH_CO_2F','SILPH_CO_3F','SILPH_CO_4F','SILPH_CO_5F','SILPH_CO_6F','SILPH_CO_7F','SILPH_CO_8F',
 'SILPH_CO_9F','SILPH_CO_10F','SILPH_CO_11F','SILPH_CO_ELEVATOR']
STRONG=['--party=CHARIZARD:80','--teach=FIRE_BLAST,FIRE_BLAST,FIRE_BLAST,FIRE_BLAST']
LONG=['--party=CHARIZARD:80','--teach=SLASH,SLASH,SLASH,SLASH']   # 80 PP for the long fights
BEATEN='--event=EVENT_BEAT_SILPH_CO_GIOVANNI'
cases=[]
for mid in chapter:
 cases.append(('load_'+mid,[f'--stage=map:{mid},1,1','--quit-after=8'],f'MAP_LOAD {mid} '))
cases += [
 # Saffron City
 ('saffron_from_route7',['--stage=map:ROUTE_7,19,9','--sim=R','--quit-after=150'],'MAP_LOAD SAFFRON_CITY'),
 ('saffron_to_route8',['--stage=map:SAFFRON_CITY,39,17','--sim=R','--quit-after=150'],'MAP_LOAD ROUTE_8'),
 ('saffron_rocket1',['--stage=map:SAFFRON_CITY,7,7','--sim=UA','--quit-after=400'],'TEXT_ID TEXT_SAFFRONCITY_ROCKET1'),
 ('saffron_rocket_blocks_door',['--stage=map:SAFFRON_CITY,7,7','--sim=UU','--quit-after=200'],'debug walk: blocked U at (7,7)'),
 ('saffron_copycat_door',['--stage=map:SAFFRON_CITY,7,6','--sim=U','--event=HIDE_SAFFRON_CITY_0','--quit-after=200'],'MAP_LOAD COPYCATS_HOUSE_1F'),
 ('saffron_silph_door_blocked',['--stage=map:SAFFRON_CITY,18,23','--sim=UU','--quit-after=200'],'debug walk: blocked U at (18,23)'),
 ('saffron_silph_door',['--stage=map:SAFFRON_CITY,18,22','--sim=U','--event=HIDE_SAFFRON_CITY_13,SHOW_SAFFRON_CITY_14','--quit-after=200'],'MAP_LOAD SILPH_CO_1F'),
 ('saffron_silph_sign',['--stage=map:SAFFRON_CITY,15,22','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_SAFFRONCITY_SILPH_CO_SIGN'),
 ('saffron_gym_door',['--stage=map:SAFFRON_CITY,34,4','--sim=U','--event=HIDE_SAFFRON_CITY_2','--quit-after=200'],'MAP_LOAD SAFFRON_GYM (8,17)'),
 ('saffron_dojo_door',['--stage=map:SAFFRON_CITY,26,4','--sim=U','--quit-after=200'],'MAP_LOAD FIGHTING_DOJO (4,11)'),
 ('saffron_after_silph',['--stage=map:SAFFRON_CITY,7,7','--sim=UU',BEATEN+',HIDE_SAFFRON_CITY_0,SHOW_SAFFRON_CITY_7','--quit-after=200'],'MAP_LOAD COPYCATS_HOUSE_1F'),
 ('saffron_nurse',['--stage=map:SAFFRON_POKECENTER,3,3','--party=PIDGEY:9:PSN','--sim=UA','--quit-after=900'],'POKECENTER_HEALED'),
 ('saffron_bench_guy',['--stage=map:SAFFRON_POKECENTER,0,5','--sim=UA','--trace-pc','--quit-after=300'],'HIDDEN_EVENT'),
 ('saffron_mart_clerk',['--stage=map:SAFFRON_MART,1,5','--sim=LA','--keys=every:25:b:60','--quit-after=500'],'TEXT_ID TEXT_SAFFRONMART_CLERK'),
 ('pidgey_house_paper',['--stage=map:SAFFRON_PIDGEY_HOUSE,3,4','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_SAFFRONPIDGEYHOUSE_PAPER'),
 ('mr_psychic_tm29',['--stage=map:MR_PSYCHICS_HOUSE,4,3','--sim=RA','--quit-after=600'],'GOT_TM29'),
 ('mr_psychic_again',['--stage=map:MR_PSYCHICS_HOUSE,4,3','--sim=RA','--event=EVENT_GOT_TM29','--quit-after=400'],'TEXT_ID TEXT_MRPSYCHICSHOUSE_MR_PSYCHIC'),
 ('copycat_stairs',['--stage=map:COPYCATS_HOUSE_1F,7,2','--sim=U','--quit-after=200'],'MAP_LOAD COPYCATS_HOUSE_2F'),
 ('copycat_snes',['--stage=map:COPYCATS_HOUSE_2F,3,6','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_COPYCATSHOUSE2F_SNES'),
 ('copycat_pc',['--stage=map:COPYCATS_HOUSE_2F,0,2','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_COPYCATSHOUSE2F_PC'),
 ('copycat_nugget',['--stage=map:COPYCATS_HOUSE_2F,1,2','--sim=UA','--trace-pc','--quit-after=300'],'HIDDEN_EVENT'),
 # the Fighting Dojo
 ('dojo_sign',['--stage=map:FIGHTING_DOJO,4,1','--sim=UA','--trace-pc','--quit-after=300'],'PrintFightingDojoText2'),
 ('dojo_trainer_sight',['--stage=map:FIGHTING_DOJO,4,4','--quit-after=600'],'TRAINER_SEES'),
 ('dojo_master_meet',['--stage=map:FIGHTING_DOJO,4,3','--event=EVENT_BEAT_FIGHTING_DOJO_TRAINER_0,EVENT_BEAT_FIGHTING_DOJO_TRAINER_1,EVENT_BEAT_FIGHTING_DOJO_TRAINER_2,EVENT_BEAT_FIGHTING_DOJO_TRAINER_3','--quit-after=400'],'TEXT_ID TEXT_FIGHTINGDOJO_KARATE_MASTER'),
 ('dojo_master_offer',['--stage=map:FIGHTING_DOJO,4,3','--sim=RA','--event=EVENT_BEAT_KARATE_MASTER,EVENT_BEAT_FIGHTING_DOJO_TRAINER_0,EVENT_BEAT_FIGHTING_DOJO_TRAINER_1,EVENT_BEAT_FIGHTING_DOJO_TRAINER_2,EVENT_BEAT_FIGHTING_DOJO_TRAINER_3','--quit-after=400'],'TEXT_ID TEXT_FIGHTINGDOJO_KARATE_MASTER'),
 ('dojo_hitmonlee',['--stage=map:FIGHTING_DOJO,4,2','--sim=UA','--event=EVENT_BEAT_KARATE_MASTER,EVENT_BEAT_FIGHTING_DOJO_TRAINER_0,EVENT_BEAT_FIGHTING_DOJO_TRAINER_1,EVENT_BEAT_FIGHTING_DOJO_TRAINER_2,EVENT_BEAT_FIGHTING_DOJO_TRAINER_3','--quit-after=1500'],'DOJO_GIFT HITMONLEE party=2'),
 ('dojo_greedy',['--stage=map:FIGHTING_DOJO,5,2','--sim=UA','--event=EVENT_GOT_HITMONLEE,EVENT_DEFEATED_FIGHTING_DOJO,HIDE_FIGHTING_DOJO_5','--quit-after=400'],'TEXT_ID TEXT_FIGHTINGDOJO_HITMONCHAN_POKE_BALL'),
 # Sabrina's gym
 ('gym_warp_pad',['--stage=map:SAFFRON_GYM,1,4','--sim=U','--quit-after=200'],'MAP_LOAD SAFFRON_GYM (15,5)'),
 ('gym_guide',['--stage=map:SAFFRON_GYM,10,16','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_SAFFRONGYM_GYM_GUIDE'),
 ('gym_statue',['--stage=map:SAFFRON_GYM,9,16','--sim=UA','--trace-pc','--quit-after=300'],'GymStatues'),
 ('gym_trainer_sight',['--stage=map:SAFFRON_GYM,17,3','--quit-after=600'],'TRAINER_SEES'),
 ('gym_sabrina_talk',['--stage=map:SAFFRON_GYM,9,9','--sim=UA','--quit-after=400'],'TEXT_ID TEXT_SAFFRONGYM_SABRINA'),
 ('gym_sabrina_after',['--stage=map:SAFFRON_GYM,9,9','--sim=UA','--event=EVENT_BEAT_SABRINA,EVENT_GOT_TM46','--quit-after=400'],'TEXT_ID TEXT_SAFFRONGYM_SABRINA'),
 # Silph Co.
 ('silph1f_stairs',['--stage=map:SILPH_CO_1F,26,1','--sim=U','--quit-after=200'],'MAP_LOAD SILPH_CO_2F'),
 ('silph1f_elevator_door',['--stage=map:SILPH_CO_1F,20,1','--sim=U','--quit-after=200'],'ELEVATOR_WARPS -> SILPH_CO_1F warp=3'),
 ('silph1f_receptionist',['--stage=map:SILPH_CO_1F,4,3','--sim=UA',BEATEN,'--quit-after=400'],'TEXT_ID TEXT_SILPHCO1F_LINK_RECEPTIONIST'),
 ('silph_elevator_menu',['--stage=map:SILPH_CO_ELEVATOR,3,1','--sim=UA','--quit-after=600'],'ELEVATOR_WARPS -> SILPH_CO_1F warp=2'),
 ('silph_elevator_shake',['--stage=map:SILPH_CO_ELEVATOR,3,1','--sim=UA','--quit-after=1200'],'ELEVATOR_SHAKE_DONE'),
 ('silph2f_tm36',['--stage=map:SILPH_CO_2F,10,2','--sim=UA','--quit-after=600'],'GOT_TM36'),
 ('silph2f_trainer_sight',['--stage=map:SILPH_CO_2F,5,14','--quit-after=600'],'TRAINER_SEES'),
 ('silph2f_door_no_key',['--stage=map:SILPH_CO_2F,4,6','--sim=UA','--quit-after=400'],'CARD_KEY_MISSING SILPH_CO_2F'),
 ('silph2f_door_key',['--stage=map:SILPH_CO_2F,4,6','--sim=UA','--give=CARD_KEY:1','--quit-after=600'],'CARD_KEY_DOOR_UNLOCKED SILPH_CO_2F 1'),
 ('silph2f_door_walk_through',['--stage=map:SILPH_CO_2F,4,6','--sim=UAUU','--give=CARD_KEY:1','--quit-after=800'],'debug walk: U from (4,4)'),
 ('silph2f_door_unlocked',['--stage=map:SILPH_CO_2F,4,6','--sim=UUU','--event=EVENT_SILPH_CO_2_UNLOCKED_DOOR1','--quit-after=400'],'debug walk: U from (4,4)'),
 ('silph3f_pad',['--stage=map:SILPH_CO_3F,23,12','--sim=U','--quit-after=200'],'MAP_LOAD SILPH_CO_3F (27,15)'),
 ('silph3f_worker',['--stage=map:SILPH_CO_3F,24,9','--sim=UA','--quit-after=300'],'TEXT_ID TEXT_SILPHCO3F_SILPH_WORKER_M'),
 ('silph5f_card_key_ball',['--stage=map:SILPH_CO_5F,21,15','--sim=DA','--quit-after=600'],'GOT_ITEM CARD_KEY'),
 ('silph5f_hidden_elixer',['--stage=map:SILPH_CO_5F,12,4','--sim=UA','--trace-pc','--quit-after=300'],'HiddenItems ELIXER'),
 ('silph7f_lapras',['--stage=map:SILPH_CO_7F,1,6','--sim=UA','--quit-after=900'],'GOT_LAPRAS party=2'),
 ('silph7f_rival_meet',['--stage=map:SILPH_CO_7F,3,2','--quit-after=600'],'SILPH_RIVAL idx=1'),
 ('silph7f_rival_meet_low',['--stage=map:SILPH_CO_7F,3,3','--quit-after=600'],'SILPH_RIVAL idx=2'),
 ('silph9f_nurse',['--stage=map:SILPH_CO_9F,3,15','--party=PIDGEY:9:PSN','--sim=UA','--quit-after=600'],'SILPH_NURSE_HEALED'),
 ('silph11f_door_no_key',['--stage=map:SILPH_CO_11F,6,14','--sim=UA','--quit-after=400'],'CARD_KEY_MISSING SILPH_CO_11F'),
 ('silph11f_door_key',['--stage=map:SILPH_CO_11F,6,14','--sim=UA','--give=CARD_KEY:1','--quit-after=600'],'CARD_KEY_DOOR_UNLOCKED SILPH_CO_11F 1'),
 ('silph3f_door_key_side',['--stage=map:SILPH_CO_3F,10,9','--sim=LA','--give=CARD_KEY:1','--quit-after=600'],'CARD_KEY_USED SILPH_CO_3F block=(4,4)'),
 ('silph11f_president',['--stage=map:SILPH_CO_11F,7,6','--sim=UA','--quit-after=600'],'GOT_MASTER_BALL'),
 ('silph11f_giovanni_meet',['--stage=map:SILPH_CO_11F,6,13','--quit-after=600'],'SILPH_GIOVANNI idx=1'),
 ('silph11f_giovanni_meet2',['--stage=map:SILPH_CO_11F,7,12','--quit-after=600'],'SILPH_GIOVANNI idx=2'),
 ('silph11f_pc',['--stage=map:SILPH_CO_11F,10,13','--sim=UA','--trace-pc','--quit-after=300'],'OpenPokemonCenterPC'),
]
if '--full' in sys.argv:
 cases += [
  ('dojo_master_full',['--stage=map:FIGHTING_DOJO,4,3','--event=EVENT_BEAT_FIGHTING_DOJO_TRAINER_0,EVENT_BEAT_FIGHTING_DOJO_TRAINER_1,EVENT_BEAT_FIGHTING_DOJO_TRAINER_2,EVENT_BEAT_FIGHTING_DOJO_TRAINER_3',*STRONG,'--quit-after=6000'],'KARATE_MASTER_BEATEN'),
  ('sabrina_full',['--stage=map:SAFFRON_GYM,9,9','--sim=UA',*LONG,'--quit-after=9000'],'SABRINA_VICTORY'),
  ('silph7f_rival_full',['--stage=map:SILPH_CO_7F,3,3',*LONG,'--quit-after=9000'],'SILPH_RIVAL_LEFT'),
  ('silph11f_giovanni_full',['--stage=map:SILPH_CO_11F,6,13',*STRONG,'--quit-after=9000'],'SILPH_GIOVANNI_BEATEN'),
  ('copycat_tm31',['--stage=map:COPYCATS_HOUSE_2F,4,4','--sim=UA','--seed=1','--give=POKE_DOLL:1','--quit-after=900'],'GOT_TM31'),
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
print(f'PASS {len(results)} chapter-nine smoke cases')

"""Audit chapter-four exported maps, source labels and the exporter's edit boundary."""
import ast,json,re,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
maps=json.loads((ROOT/'assets/data/maps.json').read_text(encoding='utf8'))
texts=json.loads((ROOT/'assets/data/text_ko.json').read_text(encoding='utf8'))
required=['ROUTE_3','MT_MOON_POKECENTER','MT_MOON_1F','MT_MOON_B1F','MT_MOON_B2F','ROUTE_4','CERULEAN_CITY','CERULEAN_GYM','CERULEAN_MART','CERULEAN_POKECENTER','CERULEAN_TRADE_HOUSE','CERULEAN_TRASHED_HOUSE','CERULEAN_BADGE_HOUSE','BIKE_SHOP','ROUTE_24','ROUTE_25','BILLS_HOUSE']
assert all(k in maps for k in required)
missing=[]
for file in [ROOT/'scripts/game/map_scripts_mtmoon.gd',*sorted((ROOT/'scripts/game').glob('cerulean_*.gd'))]:
 for label in re.findall(r'"(_[A-Za-z0-9]+)"',file.read_text(encoding='utf8')):
  if label.endswith('Text') and label not in texts:missing.append((file.name,label))
assert not missing,missing
current=ast.parse((ROOT/'tools/export_data.py').read_text(encoding='utf8'))
original=ast.parse(subprocess.check_output(['git','show','0afb7df^:tools/export_data.py'],cwd=ROOT).decode('utf8'))
functions=lambda module:{n.name:ast.dump(n)for n in module.body if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef))}
assert functions(current)==functions(original),'Exporter functions must remain untouched'
result={'maps':len(required),'trainer_headers':{m:len(maps[m].get('trainer_headers',[]))for m in required},'exact_korean_text_labels':'PASS','exporter_function_boundary':'PASS','fossil_area_no_battles_api':'missing shared BIT_NO_BATTLES flag','in_game_trade_api':'missing DoInGameTradeDialogue and trade animation','unexported_next_chapter_connections':['ROUTE_5','ROUTE_9']}
print(json.dumps(result,ensure_ascii=False,indent=2))

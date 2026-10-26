## Save-file style state shared between stages (wPlayerName, party, events...).
class_name GameState
extends RefCounted

var player_name := "레드"
var rival_name := "그린"
var events := {}          # EVENT_* -> true
var starter := ""         # PLAYER starter species key
var rival_starter := ""
var party: Array = []     # Array of PartyMon
var items: Array = [{"item": "POTION", "qty": 1}]  # AddItemToInventory in OakSpeech
var money := 3000
var cur_map := "REDS_HOUSE_2F"
var x := 3
var y := 6
var facing := 0           # 0 down, 4 up, 8 left, 12 right (SPRITE_FACING_*)
var last_map := "PALLET_TOWN"
var pokedex_seen := {}
var pokedex_owned := {}
var map_scripts := {}     # map -> current script index
var badges := 0             # wObtainedBadges (bit 0 = Boulder Badge)
var beat_gym_flags := 0     # wBeatGymFlags
var repel_steps := 0        # wRepelRemainingSteps
var town_visited: Array = []   # wTownVisitedFlag (city map ids, for Fly)
var player_id := 0        # wPlayerID: random per new game, identifies the save file
var boxes: Array = []     # sBox1..sBox12: 12 boxes of PartyMon (MONS_PER_BOX = 20 each)
var current_box := 0      # wCurrentBoxNum
var pc_items: Array = []  # wNumBoxItems: the player's PC item storage [{item, qty}]
## wBoxMons: the current box (an alias into `boxes`)
var box: Array:
	get:
		return boxes[current_box]
	set(v):
		boxes[current_box] = v
var last_blackout_map := "PALLET_TOWN"   # wLastBlackoutMap: where a blackout returns the player
var step_counter := 0     # wStepCounter: poison damage every fourth step
var encounter_cooldown := 0   # wNumberOfNoRandomBattleStepsLeft (not saved)


func _init() -> void:
	player_id = randi() & 0xFFFF
	for i in 12:
		boxes.append([])


func to_dict() -> Dictionary:
	var mons: Array = []
	for m in party:
		mons.append(m.to_dict())
	var boxed: Array = []
	for b in boxes:
		var one: Array = []
		for m in b:
			one.append(m.to_dict())
		boxed.append(one)
	return {
		"player_name": player_name, "rival_name": rival_name, "player_id": player_id, "events": events,
		"starter": starter, "rival_starter": rival_starter, "party": mons, "items": items, "money": money,
		"cur_map": cur_map, "x": x, "y": y, "facing": facing, "last_map": last_map,
		"pokedex_seen": pokedex_seen, "pokedex_owned": pokedex_owned, "map_scripts": map_scripts, "badges": badges, "beat_gym_flags": beat_gym_flags, "repel_steps": repel_steps, "town_visited": town_visited,
		"boxes": boxed, "current_box": current_box, "pc_items": pc_items,
		"last_blackout_map": last_blackout_map, "step_counter": step_counter,
	}


func from_dict(d: Dictionary) -> void:
	player_name = str(d.get("player_name", player_name))
	rival_name = str(d.get("rival_name", rival_name))
	player_id = int(d.get("player_id", player_id))
	events = d.get("events", {})
	starter = str(d.get("starter", ""))
	rival_starter = str(d.get("rival_starter", ""))
	party = []
	for md in d.get("party", []):
		party.append(PartyMon.from_dict(md))
	items = d.get("items", items)
	money = int(d.get("money", money))
	cur_map = str(d.get("cur_map", cur_map))
	x = int(d.get("x", x))
	y = int(d.get("y", y))
	facing = int(d.get("facing", facing))
	last_map = str(d.get("last_map", last_map))
	pokedex_seen = d.get("pokedex_seen", {})
	pokedex_owned = d.get("pokedex_owned", {})
	map_scripts = d.get("map_scripts", {})
	badges = int(d.get("badges", 0))
	beat_gym_flags = int(d.get("beat_gym_flags", 0))
	repel_steps = int(d.get("repel_steps", 0))
	town_visited = d.get("town_visited", [])
	boxes = []
	for i in 12:
		boxes.append([])
	current_box = clampi(int(d.get("current_box", 0)), 0, 11)
	if d.has("boxes"):
		var saved_boxes: Array = d["boxes"]
		for i in mini(12, saved_boxes.size()):
			for md in saved_boxes[i]:
				boxes[i].append(PartyMon.from_dict(md))
	else:
		# older saves: a single box
		for md in d.get("box", []):
			boxes[current_box].append(PartyMon.from_dict(md))
	pc_items = d.get("pc_items", [])
	last_blackout_map = str(d.get("last_blackout_map", last_blackout_map))
	step_counter = int(d.get("step_counter", 0))


const BAG_SIZE := 20


## AddItemToInventory: stacks up to 99, at most 20 kinds. Returns false when the bag is full.
func give_item(item: String, qty: int = 1) -> bool:
	for it in items:
		if it.item == item and it.qty + qty <= 99:
			it.qty += qty
			return true
	if items.size() >= BAG_SIZE:
		return false
	items.append({"item": item, "qty": qty})
	return true


func remove_item(item: String, qty: int = 1) -> void:
	for i in items.size():
		if items[i].item == item:
			items[i].qty -= qty
			if items[i].qty <= 0:
				items.remove_at(i)
			return


func item_count(item: String) -> int:
	for it in items:
		if it.item == item:
			return it.qty
	return 0


func set_event(name: String) -> void:
	events[name] = true


func has_event(name: String) -> bool:
	return events.get(name, false)

## Test harness for the Start-menu screens (party menu, status screen, bag,
## Pokédex list, town map). Run with scenes/.. replaced by this scene:
##   Godot --path . tests/menus_test.tscn -- --test=party --keys=120:a,... --shots=100:out1.png,300:out2.png --quit-after=600
extends Node2D

var test := "party"
var shots := {}      # frame -> path
var quit_after := 900


func _ready() -> void:
	GB.screen = $Screen/View/GBScreen
	GB.set_palette_name(GB.palette_name)
	RenderingServer.set_default_clear_color(Color.BLACK)
	$Screen.scale = Vector2(4, 4)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--test="):
			test = arg.get_slice("=", 1)
		elif arg.begins_with("--keys="):
			GB.load_key_script(arg.get_slice("=", 1))
		elif arg.begins_with("--shots="):
			for part in arg.get_slice("=", 1).split(","):
				shots[int(part.get_slice(":", 0))] = part.get_slice(":", 1)
		elif arg.begins_with("--quit-after="):
			quit_after = int(arg.get_slice("=", 1))
		elif arg.begins_with("--palette="):
			Settings.palette = arg.get_slice("=", 1)
			Settings.apply_all()
		elif arg.begins_with("--lang="):
			GameData.lang = arg.get_slice("=", 1)
	_shot_loop()
	_run()


func _shot_loop() -> void:
	while true:
		await GB.frame
		if shots.has(GB.frame_count):
			await GB.screenshot(shots[GB.frame_count])
			print("SHOT ", GB.frame_count, " ", shots[GB.frame_count])
		if GB.frame_count >= quit_after:
			print("QUIT_AFTER_FRAMES")
			get_tree().quit()
			return


static func _arg(name: String, default: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(name + "="):
			return arg.get_slice("=", 1)
	return default


func _state() -> GameState:
	var state := GameState.new()
	state.player_name = "레드" if GameData.lang == "ko" else "RED"
	state.cur_map = "VIRIDIAN_CITY"
	state.x = 23
	state.y = 26
	state.last_map = "PALLET_TOWN"
	var a := PartyMon.create("BULBASAUR", 7)
	var b := PartyMon.create("PIDGEY", 4)
	b.hp = 5
	var c := PartyMon.create("RATTATA", 3)
	c.status = PartyMon.PSN
	c.hp = 2
	var d := PartyMon.create("CATERPIE", 3)
	d.hp = 0
	var e := PartyMon.create("NIDORAN_M", 5)
	e.status = 3   # asleep
	state.party = [a, b, c, d, e]
	state.items = [{"item": "POTION", "qty": 3}, {"item": "ANTIDOTE", "qty": 1}, {"item": "POKE_BALL", "qty": 5},
		{"item": "TOWN_MAP", "qty": 1}, {"item": "OAKS_PARCEL", "qty": 1}, {"item": "AWAKENING", "qty": 2}]
	for sp in ["BULBASAUR", "PIDGEY", "RATTATA", "CATERPIE", "NIDORAN_M", "WEEDLE", "SPEAROW", "CHARMANDER", "IVYSAUR"]:
		state.pokedex_seen[sp] = true
	for sp in ["BULBASAUR", "PIDGEY", "RATTATA", "CATERPIE", "NIDORAN_M"]:
		state.pokedex_owned[sp] = true
	state.set_event("EVENT_GOT_POKEDEX")
	return state


## Stand-in for the Overworld: the map id and a redraw that paints a checker pattern.
class FakeOverworld:
	var map_id := "VIRIDIAN_CITY"
	var state: GameState
	func reload_map_view() -> void:
		var S: GBScreen = GB.screen
		S.clear_sprites()
		for y in 18:
			for x in 20:
				S.set_bg(x, y, S.tile("tileset_overworld", 0x0A if (x + y) % 2 == 0 else 0x0B))


func _run() -> void:
	var state := _state()
	var ow := FakeOverworld.new()
	ow.state = state
	ow.reload_map_view()
	GB.screen.normal_pals()
	await GB.frames(10)
	match test:
		"party":
			var r := await PartyMenu.show(state, "normal")
			print("PARTY_RESULT ", r)
		"startmenu":
			await PartyMenu.start_menu_pokemon(state, ow)
			print("STARTMENU_DONE party=", [state.party[0].nickname, state.party[1].nickname])
		"status":
			await StatusScreen.show(state, 0)
			print("STATUS_DONE")
		"card":
			GB.play_time_hours = 3
			GB.play_time_minutes = 7
			state.badges = int(_arg("--badges", "0"))
			await TrainerCard.show(state)
			print("CARD_DONE")
		"tm":
			state.items = [{"item": "TM06", "qty": 2}, {"item": "TM42", "qty": 1}, {"item": "HM01", "qty": 1}]
			var close_tm := await Bag.show(state, ow)
			print("TM_DONE close=", close_tm, " items=", state.items, " moves=", state.party[0].moves)
		"bag":
			var close := await Bag.show(state, ow)
			print("BAG_DONE close=", close, " items=", state.items, " hp=", state.party[1].hp, " st=", state.party[2].status)
		"dex":
			await PokedexMenu.show(state)
			print("DEX_DONE")
		"map":
			await TownMap.show(state, ow)
			print("MAP_DONE")
		"nest":
			await TownMap.show_nest(state, "PIDGEY")
			print("NEST_DONE")
		"nest_none":
			await TownMap.show_nest(state, "MEW")
			print("NEST_NONE_DONE")
		"medicine":
			var r1 := ItemUse.apply_medicine(state.party[1], "POTION")
			var r2 := ItemUse.apply_medicine(state.party[0], "POTION")
			var r3 := ItemUse.apply_medicine(state.party[2], "ANTIDOTE")
			var r4 := ItemUse.apply_medicine(state.party[3], "POTION")
			var r5 := ItemUse.apply_medicine(state.party[4], "ANTIDOTE")
			var r6 := ItemUse.apply_medicine(state.party[4], "AWAKENING")
			print("MEDICINE ", r1, " ", r2, " ", r3, " ", r4, " ", r5, " ", r6)
	ow.reload_map_view()
	GB.screen.normal_pals()
	await GB.frames(30)
	print("TEST_DONE")
	get_tree().quit()

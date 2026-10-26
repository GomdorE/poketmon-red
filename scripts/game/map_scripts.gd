## Map scripts and text handlers for the first chapter
## (scripts/PalletTown.asm, RedsHouse1F.asm, RedsHouse2F.asm, OaksLab.asm, BluesHouse.asm).
class_name MapScripts
extends RefCounted

var ow: Overworld
var state: GameState
var oak_walked_to_player := false
var route22_coord_index := 0
var rival_starter_temp := ""
var rival_ball_index := -1
var rival_steps := 0
var old_man_saved_npc := Vector2i(-1, -1)   # wSavedNPCMovementDirections2Index (Oak's request scene)
var trainers: TrainerEngine                 # home/trainers.asm
var pewter: PewterScripts                   # chapter 3: Pewter City and its buildings
var mtmoon: MtMoonScripts                   # chapter 4: Route 3, Mt. Moon, Route 4


func _init(o: Overworld) -> void:
	ow = o
	state = o.state
	trainers = TrainerEngine.new(self)
	pewter = PewterScripts.new(self)
	mtmoon = MtMoonScripts.new(self)


func _script_index() -> int:
	return state.map_scripts.get(ow.map_id, 0)


func _set_script(i: int) -> void:
	state.map_scripts[ow.map_id] = i
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("MAPSCRIPT %s -> %d (frame %d)" % [ow.map_id, i, GB.frame_count])


# --- per-frame map scripts ----------------------------------------------------------

func run_map_script() -> void:
	match ow.map_id:
		"PALLET_TOWN":
			ow.no_auto_text_box = false
			await _pallet_town()
		"REDS_HOUSE_2F":
			ow.no_auto_text_box = false
			if _script_index() == 0:
				ow.player.facing = Overworld.FACE_UP
				_set_script(1)
		"REDS_HOUSE_1F":
			ow.no_auto_text_box = false
		"BLUES_HOUSE":
			ow.no_auto_text_box = false
			_blues_house()
		"OAKS_LAB":
			ow.no_auto_text_box = true
			await _oaks_lab()
		"VIRIDIAN_CITY":
			ow.no_auto_text_box = false
			await _viridian_city()
		"VIRIDIAN_MART":
			ow.no_auto_text_box = false
			await _viridian_mart()
		"ROUTE_22":
			ow.no_auto_text_box = false
			await _route22()
		"PEWTER_GYM":
			ow.no_auto_text_box = false
			await _pewter_gym()
		_:
			# Route1, Route2, Pokecenter, school, nickname house, gym, gates: EnableAutoTextBoxDrawing
			ow.no_auto_text_box = false
			await pewter.run_map_script()
			await mtmoon.run_map_script()
			# a map whose script table is only the trainer engine (most routes)
			if not ow.map.get("trainer_headers", []).is_empty():
				await trainer_map_script()


## PewterGym_Script: the trainer engine plus PewterGymBrockPostBattle (script 3).
func _pewter_gym() -> void:
	match _script_index():
		0: await trainers.check_fighting_map_trainers()
		1: await trainers.display_enemy_trainer_text_and_start_battle()
		2: trainers.end_trainer_battle()
		3:
			# PewterGymBrockPostBattle
			if not ow.last_battle_won:
				_pewter_gym_reset_scripts()
				return
			ow.joy_ignore = GB.CTRL_PAD
			await _pewter_gym_receive_tm34()


## PewterGymResetScripts.
func _pewter_gym_reset_scripts() -> void:
	ow.joy_ignore = 0
	_set_script(0)


## PewterGymScriptReceiveTM34 (+ .gymVictory).
func _pewter_gym_receive_tm34() -> void:
	await ow.display_text_id("TEXT_PEWTERGYM_BROCK_WAIT_TAKE_THIS", -1)
	await _pewter_gym_give_tm34()
	_pewter_gym_reset_scripts()


## The part of PewterGymScriptReceiveTM34 after the first text (also reached from
## Brock's own text when the bag was full the first time).
func _pewter_gym_give_tm34() -> void:
	state.set_event("EVENT_BEAT_BROCK")
	if state.give_item("TM34", 1):
		await ow.display_text_id("TEXT_PEWTERGYM_RECEIVED_TM34", -1)
		state.set_event("EVENT_GOT_TM34")
	else:
		await ow.display_text_id("TEXT_PEWTERGYM_TM34_NO_ROOM", -1)
	# .gymVictory
	state.badges |= 1          # BIT_BOULDERBADGE in wObtainedBadges
	state.beat_gym_flags |= 1  # and in wBeatGymFlags
	_hide_remote_object("PEWTER_CITY", 4)   # TOGGLE_GYM_GUY
	_hide_remote_object("ROUTE_22", 0)      # TOGGLE_ROUTE_22_RIVAL_1
	state.events.erase("EVENT_1ST_ROUTE22_RIVAL_BATTLE")
	state.events.erase("EVENT_ROUTE22_RIVAL_WANTS_BATTLE")
	state.set_event("EVENT_BEAT_PEWTER_GYM_TRAINER_0")   # deactivate the gym trainers
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("GYM_VICTORY badges=%d tm34=%d money=%d" % [state.badges, state.item_count("TM34"), state.money])


## PewterGymBrockText.
func _pewter_gym_brock_text(npc_index: int) -> void:
	if state.has_event("EVENT_BEAT_BROCK"):
		if state.has_event("EVENT_GOT_TM34"):
			await ow.print_text("_PewterGymBrockPostBattleAdviceText")
		else:
			# the TM didn't fit in the bag last time
			await ow.display_text_id("TEXT_PEWTERGYM_BROCK_WAIT_TAKE_THIS", -1)
			await _pewter_gym_give_tm34()
			_pewter_gym_reset_scripts()
			ow.do_not_wait_after_text = true   # DisableWaitingAfterTextDisplay
		return
	await ow.print_text("_PewterGymBrockPreBattleText")
	# SaveEndBattleTextPointers, EngageMapTrainer (PlayTrainerMusic runs while
	# wGymLeaderNo is still 0: the male trainer theme starts), InitBattleEnemyParameters
	trainers.header = {}
	trainers._engage_map_trainer(npc_index + 1)
	ow.battle_request = {
		"trainer": trainers.engaged_class, "team": trainers.engaged_set, "gym_leader": 1,
		"win_text": "PewterGymBrockReceivedBoulderBadgeText", "lose_text": "PewterGymBrockReceivedBoulderBadgeText",
	}
	_set_script(3)   # SCRIPT_PEWTERGYM_BROCK_POST_BATTLE


## PewterGymGuideText.
func _pewter_gym_guide_text() -> void:
	if state.beat_gym_flags & 1:
		await ow.print_text("_PewterGymGuidePostBattleText")
		return
	await ow.print_text("_PewterGymGuidePreAdviceText")
	if await Menu.yes_no():
		await ow.print_text("_PewterGymGuideBeginAdviceText")
	else:
		await ow.print_text("_PewterGymGuideFreeServiceText")
	await ow.print_text("_PewterGymGuideAdviceText")


## The script table of a map with only trainers: CheckFightingMapTrainers,
## DisplayEnemyTrainerTextAndStartBattle, EndTrainerBattle.
func trainer_map_script() -> void:
	match _script_index():
		0: await trainers.check_fighting_map_trainers()
		1: await trainers.display_enemy_trainer_text_and_start_battle()
		2: trainers.end_trainer_battle()


## ViridianCity_Script
func _viridian_city() -> void:
	match _script_index():
		0:
			# ViridianCityCheckGymOpenScript: the gym stays locked without all other badges
			if not state.has_event("EVENT_VIRIDIAN_GYM_OPEN") and ow.player.x == 32 and ow.player.y == 8:
				await ow.display_text_id("TEXT_VIRIDIANCITY_GYM_LOCKED", -1)
				_viridian_move_player_down()
				_set_script(3)
				return
			# ViridianCityCheckGotPokedexScript: the sleepy old man blocks the way north
			if not state.has_event("EVENT_GOT_POKEDEX") and ow.player.x == 19 and ow.player.y == 9:
				await ow.display_text_id("TEXT_VIRIDIANCITY_OLD_MAN_SLEEPY", -1)
				_set_script(3)
		1:
			# ViridianCityOldManStartCatchTrainingScript: the position of sprite 3 (the
			# wandering youngster, object 2) is saved around the battle, then the old
			# man's Weedle demonstration (BATTLE_TYPE_OLD_MAN, WEEDLE L5)
			old_man_saved_npc = Vector2i(ow.npcs[2].x, ow.npcs[2].y)
			ow.battle_request = {"type": "old_man", "species": "WEEDLE", "level": 5}
			_set_script(2)
		2:
			# ViridianCityOldManEndCatchTrainingScript
			if old_man_saved_npc.x >= 0:
				ow.set_npc_position(2, old_man_saved_npc.x, old_man_saved_npc.y)
				old_man_saved_npc = Vector2i(-1, -1)
			await GB.delay3()
			ow.joy_ignore = 0
			await ow.display_text_id("TEXT_VIRIDIANCITY_OLD_MAN_YOU_NEED_TO_WEAKEN_THE_TARGET", -1)
			ow.joy_ignore = 0
			_set_script(0)
		3:
			if ow.sim_queue.size() > 0:
				return
			await GB.delay3()
			_set_script(0)


## ViridianCityMovePlayerDownScript
func _viridian_move_player_down() -> void:
	ow.player.facing = Overworld.FACE_DOWN
	ow.simulate([GB.DOWN])


## ViridianMart_Script: the clerk asks the player to deliver Oak's parcel on the first visit.
func _viridian_mart() -> void:
	match _script_index():
		0:
			await ow.display_text_id("TEXT_VIRIDIANMART_CLERK_YOU_CAME_FROM_PALLET_TOWN", -1)
			# RLE list PAD_LEFT 1, PAD_UP 2, played from the end
			ow.simulate([GB.UP, GB.UP, GB.LEFT])
			_set_script(1)
		1:
			if ow.sim_queue.size() > 0:
				return
			await GB.delay3()
			await ow.display_text_id("TEXT_VIRIDIANMART_CLERK_PARCEL_QUEST", -1)
			state.give_item("OAKS_PARCEL", 1)
			state.set_event("EVENT_GOT_OAKS_PARCEL")
			_set_script(2)


## Route22_Script: the first rival battle on the way to the league gate.
func _route22() -> void:
	match _script_index():
		0:
			if not state.has_event("EVENT_ROUTE22_RIVAL_WANTS_BATTLE"):
				return
			if ow.player.x != 29 or (ow.player.y != 4 and ow.player.y != 5):
				return
			# wCoordIndex is 1-based: 1 = (29, 4), 2 = (29, 5)
			route22_coord_index = 1 if ow.player.y == 4 else 2
			ow.joy_ignore = GB.CTRL_PAD
			ow.player.facing = Overworld.FACE_LEFT
			if not state.has_event("EVENT_1ST_ROUTE22_RIVAL_BATTLE"):
				return
			# Route22FirstRivalBattleScript
			await ow.emotion_bubble(1, "shock")
			Sound.play_music("MUSIC_MEET_RIVAL")
			# Route22MoveRivalRightScript: all four steps from the upper coordinate, three otherwise
			var moves: Array = [Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT]
			if route22_coord_index == 1:
				moves.append(Overworld.NPC_RIGHT)
			ow.move_sprite(0, moves)
			ow.set_npc_facing(0, Overworld.FACE_RIGHT)
			await GB.frames(6)
			_set_script(1)
		1:
			if ow.npc_moving(0):
				return
			if route22_coord_index == 1:
				ow.player.facing = Overworld.FACE_DOWN
				ow.set_npc_facing(0, Overworld.FACE_UP)
			else:
				ow.set_npc_facing(0, Overworld.FACE_RIGHT)
			await GB.frames(6)
			ow.joy_ignore = 0
			await ow.display_text_id("TEXT_ROUTE22_RIVAL1", 0)
			# .StarterTable: rival trainer numbers 4 (SQUIRTLE), 5 (BULBASAUR), 6 (CHARMANDER)
			var team: int = {"SQUIRTLE": 4, "BULBASAUR": 5, "CHARMANDER": 6}[state.rival_starter]
			ow.battle_request = {
				"trainer": "RIVAL1", "team": team, "name": state.rival_name,
				"win_text": "_Route22Rival1DefeatedText", "lose_text": "_Route22Rival1VictoryText",
			}
			_set_script(2)
		2:
			# Route22Rival1AfterBattleScript
			if not ow.last_battle_won:
				ow.joy_ignore = 0
				_set_script(0)
				return
			# the map reload after the battle put the rival back on his object square;
			# he stood next to the player (Route22MoveRivalRightScript)
			ow.set_npc_position(0, 29 if route22_coord_index == 1 else 28, 5)
			if ow.player.facing == Overworld.FACE_DOWN:
				ow.set_npc_facing(0, Overworld.FACE_UP)
			else:
				ow.set_npc_facing(0, Overworld.FACE_RIGHT)
			await GB.frames(6)
			ow.joy_ignore = GB.CTRL_PAD
			state.set_event("EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE")
			await ow.display_text_id("TEXT_ROUTE22_RIVAL1", 0)
			Sound.stop_all_music()
			Sound.rival_alternate_start()
			if route22_coord_index == 1:
				ow.move_sprite(0, [Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN])
			else:
				ow.move_sprite(0, [Overworld.NPC_UP, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN])
			_set_script(3)
		3:
			if ow.npc_moving(0):
				return
			ow.joy_ignore = 0
			ow.hide_object(0)
			state.set_event("HIDE_ROUTE_22_0")
			await Sound.play_default_music()
			state.events.erase("EVENT_1ST_ROUTE22_RIVAL_BATTLE")
			state.events.erase("EVENT_ROUTE22_RIVAL_WANTS_BATTLE")
			_set_script(0)


func _pallet_town() -> void:
	# PalletTown_Script header
	if state.has_event("EVENT_GOT_POKEBALLS_FROM_OAK"):
		state.set_event("EVENT_PALLET_AFTER_GETTING_POKEBALLS")
	match _script_index():
		0:
			if state.has_event("EVENT_FOLLOWED_OAK_INTO_LAB"):
				return
			if ow.player.y != 1:
				return
			ow.player.facing = Overworld.FACE_DOWN
			Sound.stop_all_sound()
			Sound.play_music("MUSIC_MEET_PROF_OAK")
			ow.joy_ignore = GB.SELECT | GB.START | GB.CTRL_PAD
			state.set_event("EVENT_OAK_APPEARED_IN_PALLET")
			_set_script(1)
		1:
			oak_walked_to_player = false
			await ow.display_text_id("TEXT_PALLETTOWN_OAK", -1)
			ow.joy_ignore = GB.BUTTONS | GB.CTRL_PAD
			ow.show_object(0)
			_set_script(2)
		2:
			ow.set_npc_facing(0, Overworld.FACE_UP)
			await GB.delay3()
			var path := ow.find_path_to_player(0, 1)
			ow.move_sprite(0, path)
			ow.joy_ignore = GB.BUTTONS | GB.CTRL_PAD
			_set_script(3)
		3:
			if ow.npc_moving(0):
				return
			ow.player.facing = Overworld.FACE_DOWN
			oak_walked_to_player = true
			ow.joy_ignore = GB.SELECT | GB.START | GB.CTRL_PAD
			await ow.display_text_id("TEXT_PALLETTOWN_OAK", -1)
			ow.joy_ignore = GB.BUTTONS | GB.CTRL_PAD
			ow.follow_script = {"fn": 0, "steps": 0}
			_set_script(4)
		4:
			if ow.follow_script.is_empty():
				_set_script(5)
				return
			_pallet_follow_script()
		5:
			# PalletTownDaisyScript (stays current): once the Town Map was received and
			# Blue's house entered, Daisy moves from her chair (BLUES_HOUSE object 0) to
			# walking about (object 1)
			if not state.has_event("EVENT_DAISY_WALKING") \
					and state.has_event("EVENT_GOT_TOWN_MAP") and state.has_event("EVENT_ENTERED_BLUES_HOUSE"):
				state.set_event("EVENT_DAISY_WALKING")
				_hide_remote_object("BLUES_HOUSE", 0)
				_show_remote_object("BLUES_HOUSE", 1)
				return
			if state.has_event("EVENT_GOT_POKEBALLS_FROM_OAK"):
				state.set_event("EVENT_PALLET_AFTER_GETTING_POKEBALLS_2")


## BluesHouse_Script: entering the house is remembered for Daisy's Pallet Town script.
func _blues_house() -> void:
	if _script_index() == 0:
		state.set_event("EVENT_ENTERED_BLUES_HOUSE")
		_set_script(1)


## ShowObject / HideObject for an object of another map (the same event convention
## Overworld.show_object / hide_object use, applied when that map loads).
func _show_remote_object(map: String, index: int) -> void:
	state.set_event("SHOW_%s_%d" % [map, index])
	state.events.erase("HIDE_%s_%d" % [map, index])


func _hide_remote_object(map: String, index: int) -> void:
	state.set_event("HIDE_%s_%d" % [map, index])
	state.events.erase("SHOW_%s_%d" % [map, index])


## PalletMovementScript_* (engine/overworld/auto_movement.asm): Oak and the
## player walk to the lab, the player one step behind.
func _pallet_follow_script() -> void:
	var fs := ow.follow_script
	match fs.fn:
		0:
			var steps: int = ow.player.x - 10
			fs.steps = steps
			if steps > 0:
				var moves: Array = []
				for i in steps:
					moves.append(Overworld.NPC_LEFT)
				ow.move_sprite(0, moves)
				fs.fn = 1
			else:
				fs.fn = 3
			Sound.no_map_music = true   # the Oak music keeps playing into the lab
			ow.joy_ignore = GB.SELECT | GB.START | GB.CTRL_PAD
		1:
			if ow.npc_moving(0):
				return
			var presses: Array = []
			for i in fs.steps:
				presses.append(GB.LEFT)
			ow.simulate(presses)
			fs.fn = 2
		2:
			if ow.sim_queue.size() > 0:
				return
			fs.fn = 3
		3:
			# RLEList_PlayerWalkToLab is consumed from the end: DOWN 6, LEFT 1, DOWN 5, RIGHT 3, UP 2
			var presses: Array = []
			for i in 6: presses.append(GB.DOWN)
			presses.append(GB.LEFT)
			for i in 5: presses.append(GB.DOWN)
			for i in 3: presses.append(GB.RIGHT)
			for i in 2: presses.append(GB.UP)
			ow.simulate(presses)
			var oak: Array = []
			for i in 5: oak.append(Overworld.NPC_DOWN)
			oak.append(Overworld.NPC_LEFT)
			for i in 5: oak.append(Overworld.NPC_DOWN)
			for i in 3: oak.append(Overworld.NPC_RIGHT)
			oak.append(Overworld.NPC_UP)
			ow.start_scripted_npc(0, oak)
			fs.fn = 4
		4:
			if ow.sim_queue.size() > 0:
				return
			ow.follow_script = {}


func _oaks_lab() -> void:
	match _script_index():
		0:
			if not state.has_event("EVENT_OAK_APPEARED_IN_PALLET"):
				return
			ow.joy_ignore = GB.BUTTONS | GB.CTRL_PAD
			ow.show_object(7)
			_set_script(1)
		1:
			ow.move_sprite(7, [Overworld.NPC_UP, Overworld.NPC_UP, Overworld.NPC_UP])
			_set_script(2)
		2:
			if ow.npc_moving(7):
				return
			ow.hide_object(7)
			ow.show_object(4)
			_set_script(3)
		3:
			await GB.delay3()
			var presses: Array = []
			for i in 8:
				presses.append(GB.UP)
			ow.simulate(presses)
			ow.set_npc_facing(0, Overworld.FACE_DOWN)
			ow.set_npc_facing(4, Overworld.FACE_DOWN)
			_set_script(4)
		4:
			if ow.sim_queue.size() > 0:
				return
			state.set_event("EVENT_FOLLOWED_OAK_INTO_LAB")
			state.set_event("EVENT_FOLLOWED_OAK_INTO_LAB_2")
			ow.set_npc_facing(0, Overworld.FACE_UP)
			Sound.no_map_music = false
			await Sound.play_default_music()
			_set_script(5)
		5:
			ow.joy_ignore = GB.SELECT | GB.START | GB.CTRL_PAD
			await ow.display_text_id("TEXT_OAKSLAB_RIVAL_FED_UP_WITH_WAITING", -1)
			await GB.delay3()
			await ow.display_text_id("TEXT_OAKSLAB_OAK_CHOOSE_MON", -1)
			await GB.delay3()
			await ow.display_text_id("TEXT_OAKSLAB_RIVAL_WHAT_ABOUT_ME", -1)
			await GB.delay3()
			await ow.display_text_id("TEXT_OAKSLAB_OAK_BE_PATIENT", -1)
			state.set_event("EVENT_OAK_ASKED_TO_CHOOSE_MON")
			ow.joy_ignore = 0
			_set_script(6)
		6:
			# the player may not leave before choosing
			if ow.player.y != 6:
				return
			ow.set_npc_facing(4, Overworld.FACE_DOWN)
			ow.set_npc_facing(0, Overworld.FACE_DOWN)
			await ow.display_text_id("TEXT_OAKSLAB_OAK_DONT_GO_AWAY_YET", -1)
			ow.simulate([GB.UP])
			ow.player.facing = Overworld.FACE_UP
			_set_script(7)
		7:
			if ow.sim_queue.size() > 0:
				return
			await GB.delay3()
			_set_script(6)
		8:
			# OaksLabChoseStarterScript: the rival walks to the remaining ball
			var moves: Array = []
			match state.starter:
				"CHARMANDER":
					if ow.player.y == 4:
						moves = [Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_UP]
					else:
						moves = [Overworld.NPC_DOWN, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT]
				"SQUIRTLE":
					if ow.player.y == 4:
						moves = [Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_UP]
					else:
						moves = [Overworld.NPC_DOWN, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT]
				_:
					if ow.player.x == 9:
						var rival: Dictionary = ow.npcs[0]
						rival.x = 9
						rival.y = 8
						rival.px = (Overworld.BORDER + 9 * 2) * 8
						rival.py = (Overworld.BORDER + 8 * 2) * 8
						moves = [Overworld.NPC_RIGHT]
					else:
						moves = [Overworld.NPC_DOWN, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT]
			ow.move_sprite(0, moves)
			_set_script(9)
		9:
			if ow.npc_moving(0):
				return
			ow.joy_ignore = GB.SELECT | GB.START | GB.CTRL_PAD
			ow.set_npc_facing(0, Overworld.FACE_UP)
			await ow.display_text_id("TEXT_OAKSLAB_RIVAL_ILL_TAKE_THIS_ONE", -1)
			ow.hide_object(rival_ball_index)
			await GB.delay3()
			state.rival_starter = rival_starter_temp
			Text.ram["wNameBuffer"] = GameData.mon_name(state.rival_starter)
			ow.set_npc_facing(0, Overworld.FACE_UP)
			await ow.display_text_id("TEXT_OAKSLAB_RIVAL_RECEIVED_MON", -1)
			state.set_event("EVENT_GOT_STARTER")
			ow.joy_ignore = 0
			_set_script(10)
		10:
			if ow.player.y != 6:
				return
			ow.set_npc_facing(0, Overworld.FACE_DOWN)
			ow.player.facing = Overworld.FACE_UP
			Sound.play_music("MUSIC_MEET_RIVAL")
			await ow.display_text_id("TEXT_OAKSLAB_RIVAL_ILL_TAKE_YOU_ON", -1)
			var path := ow.find_path_to_player(0, 1)
			ow.move_sprite(0, path)
			_set_script(11)
		11:
			if ow.npc_moving(0):
				return
			ow.joy_ignore = 0
			ow.player.facing = Overworld.FACE_UP
			ow.battle_request = {
				"trainer": "RIVAL1", "name": state.rival_name,
				"party": [{"species": state.rival_starter, "level": 5}],
				"win_text": "_OaksLabRivalIPickedTheWrongPokemonText",
				"lose_text": "_OaksLabRivalAmIGreatOrWhatText",
			}
			_set_script(12)
		12:
			# OaksLabRivalEndBattleScript (runs after the battle)
			ow.joy_ignore = GB.CTRL_PAD
			ow.player.facing = Overworld.FACE_UP
			ow.set_npc_facing(0, Overworld.FACE_DOWN)
			Battle.heal_party(state)
			state.set_event("EVENT_BATTLED_RIVAL_IN_OAKS_LAB")
			_set_script(13)
		13:
			await GB.frames(20)
			await ow.display_text_id("TEXT_OAKSLAB_RIVAL_SMELL_YOU_LATER", -1)
			Sound.rival_alternate_start()
			var rival: Dictionary = ow.npcs[0]
			rival.change_facing = Overworld.FACE_RIGHT if ow.player.x == 4 else Overworld.FACE_LEFT
			ow.move_sprite(0, [Overworld.NPC_CHANGE_FACING, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN])
			_set_script(14)
		14:
			if ow.npc_moving(0):
				# keep the player facing the rival as he walks away
				var rival: Dictionary = ow.npcs[0]
				var steps_done: int = rival.move_idx - 1
				if steps_done < 5:
					ow.player.facing = Overworld.FACE_RIGHT if ow.player.x == 4 else Overworld.FACE_LEFT
				else:
					ow.player.facing = Overworld.FACE_DOWN
				return
			ow.hide_object(0)
			ow.joy_ignore = 0
			await Sound.play_default_music()
			_set_script(18)
		15:
			# OaksLabRivalArrivesAtOaksRequestScript
			ow.no_auto_text_box = false
			Sound.stop_all_music()
			Sound.rival_alternate_start()
			await ow.display_text_id("TEXT_OAKSLAB_RIVAL_GRAMPS", -1)
			# OaksLabCalcRivalMovementScript: the rival appears below the player in
			# the column left of Oak (x = 4) and walks up to his usual square (4, 3)
			if ow.player.y == 3:
				rival_steps = 4
			elif ow.player.y == 1:
				rival_steps = 2
			else:
				rival_steps = 3
			ow.set_npc_position(0, 4, 3 + rival_steps)
			ow.show_object(0)
			var ups: Array = []
			for i in rival_steps:
				ups.append(Overworld.NPC_UP)
			ow.move_sprite(0, ups)
			_set_script(16)
		16:
			# OaksLabOakGivesPokedexScript
			if ow.npc_moving(0):
				return
			ow.no_auto_text_box = false
			await Sound.play_default_music()
			ow.joy_ignore = GB.SELECT | GB.START | GB.CTRL_PAD
			await _rival_face_up_oak_face_down()
			await ow.display_text_id("TEXT_OAKSLAB_RIVAL_WHAT_DID_YOU_CALL_ME_FOR", -1)
			await GB.frame
			await _rival_face_up_oak_face_down()
			await ow.display_text_id("TEXT_OAKSLAB_OAK_I_HAVE_A_REQUEST", -1)
			await GB.frame
			await _rival_face_up_oak_face_down()
			await ow.display_text_id("TEXT_OAKSLAB_OAK_MY_INVENTION_POKEDEX", -1)
			await GB.frame
			await ow.display_text_id("TEXT_OAKSLAB_OAK_GOT_POKEDEX", -1)
			await GB.delay3()
			ow.hide_object(5)   # TOGGLE_POKEDEX_1
			ow.hide_object(6)   # TOGGLE_POKEDEX_2
			await _rival_face_up_oak_face_down()
			await ow.display_text_id("TEXT_OAKSLAB_OAK_THAT_WAS_MY_DREAM", -1)
			ow.set_npc_facing(0, Overworld.FACE_RIGHT)
			await GB.frames(6)
			await GB.delay3()
			await ow.display_text_id("TEXT_OAKSLAB_RIVAL_LEAVE_IT_ALL_TO_ME", -1)
			state.set_event("EVENT_GOT_POKEDEX")
			state.set_event("EVENT_OAK_GOT_PARCEL")
			_hide_remote_object("VIRIDIAN_CITY", 4)   # TOGGLE_LYING_OLD_MAN
			_show_remote_object("VIRIDIAN_CITY", 6)   # TOGGLE_OLD_MAN
			Sound.stop_all_music()
			Sound.rival_alternate_start()
			var downs: Array = []
			for i in rival_steps:
				downs.append(Overworld.NPC_DOWN)
			ow.move_sprite(0, downs)
			_set_script(17)
		17:
			# OaksLabRivalLeavesWithPokedexScript
			if ow.npc_moving(0):
				return
			await Sound.play_default_music()
			ow.hide_object(0)
			state.set_event("EVENT_1ST_ROUTE22_RIVAL_BATTLE")
			state.events.erase("EVENT_2ND_ROUTE22_RIVAL_BATTLE")
			state.set_event("EVENT_ROUTE22_RIVAL_WANTS_BATTLE")
			_show_remote_object("ROUTE_22", 0)   # TOGGLE_ROUTE_22_RIVAL_1
			state.map_scripts["PALLET_TOWN"] = 5   # SCRIPT_PALLETTOWN_DAISY
			ow.joy_ignore = 0
			_set_script(18)
		_:
			pass


## OaksLabRivalFaceUpOakFaceDownScript (SetSpriteFacingDirectionAndDelay waits 6 frames).
func _rival_face_up_oak_face_down() -> void:
	ow.set_npc_facing(0, Overworld.FACE_UP)
	ow.npcs[0].keep_facing = true
	await GB.frames(6)
	# OAKSLAB_OAK2 (object 7) is the hidden Oak after the entrance scene; the Oak on
	# screen is object 4, which always faces down
	ow.set_npc_facing(4, Overworld.FACE_DOWN)
	ow.npcs[4].keep_facing = true
	await GB.frames(6)


# --- text handlers -------------------------------------------------------------------

func text(text_id: String, npc_index: int) -> void:
	if await trainers.handle_text(npc_index):
		return
	if await pewter.text(text_id, npc_index):
		return
	if await mtmoon.text(text_id, npc_index):
		return
	match text_id:
		# Pallet Town
		"TEXT_PALLETTOWN_OAK":
			if not oak_walked_to_player:
				ow.do_not_wait_after_text = true
				await ow.print_text("_PalletTownOakHeyWaitDontGoOutText")
				await GB.frames(10)
				await ow.emotion_bubble(0, "shock")
				ow.player.facing = Overworld.FACE_DOWN
			else:
				await ow.print_text("_PalletTownOakItsUnsafeText")
		"TEXT_PALLETTOWN_GIRL": await _far("_PalletTownGirlText")
		"TEXT_PALLETTOWN_FISHER": await _far("_PalletTownFisherText")
		"TEXT_PALLETTOWN_OAKSLAB_SIGN": await _far("_PalletTownOaksLabSignText")
		"TEXT_PALLETTOWN_SIGN": await _far("_PalletTownSignText")
		"TEXT_PALLETTOWN_PLAYERSHOUSE_SIGN": await _far("_PalletTownPlayersHouseSignText")
		"TEXT_PALLETTOWN_RIVALSHOUSE_SIGN": await _far("_PalletTownRivalsHouseSignText")
		# Red's house
		"TEXT_REDSHOUSE1F_MOM":
			if state.has_event("EVENT_GOT_STARTER"):
				await ow.print_text("_RedsHouse1FMomYouShouldRestText")
				await Intro.fade_out_to_white()
				Battle.heal_party(state)
				await GB.frames(60)
				await Intro.fade_in_from_white()
				await ow.print_text("_RedsHouse1FMomLookingGreatText")
			else:
				await ow.print_text("_RedsHouse1FMomWakeUpText")
		"TEXT_REDSHOUSE1F_TV":
			if ow.player.facing == Overworld.FACE_UP:
				await ow.print_text("_RedsHouse1FTVStandByMeMovieText")
			else:
				await ow.print_text("_RedsHouse1FTVWrongSideText")
		# Blue's house
		"TEXT_BLUESHOUSE_DAISY_SITTING":
			# BluesHouseDaisySittingText
			if state.has_event("EVENT_GOT_TOWN_MAP"):
				await ow.print_text("_BluesHouseDaisyUseMapText")
			elif state.has_event("EVENT_GOT_POKEDEX"):
				await ow.print_text("_BluesHouseDaisyOfferMapText")
				if state.give_item("TOWN_MAP", 1):
					ow.hide_object(2)   # TOGGLE_TOWN_MAP
					Text.ram["wStringBuffer"] = GameData.item_name("TOWN_MAP")
					await ow.print_text("_GotMapText")
					await Sound.text_sound("sound_get_key_item")
					state.set_event("EVENT_GOT_TOWN_MAP")
				else:
					await ow.print_text("_BluesHouseDaisyBagFullText")
			else:
				await ow.print_text("_BluesHouseDaisyRivalAtLabText")
		"TEXT_BLUESHOUSE_DAISY_WALKING": await _far("_BluesHouseDaisyWalkingText")
		"TEXT_BLUESHOUSE_TOWN_MAP": await _far("_BluesHouseTownMapText")
		# Oak's Lab
		"TEXT_OAKSLAB_RIVAL":
			if not state.has_event("EVENT_FOLLOWED_OAK_INTO_LAB_2"):
				await ow.print_text("_OaksLabRivalGrampsIsntAroundText")
			elif not state.has_event("EVENT_GOT_STARTER"):
				await ow.print_text("_OaksLabRivalGoAheadAndChooseText")
			else:
				await ow.print_text("_OaksLabRivalMyPokemonLooksStrongerText")
		"TEXT_OAKSLAB_CHARMANDER_POKE_BALL":
			await _poke_ball("CHARMANDER", 1, "SQUIRTLE", 2)
		"TEXT_OAKSLAB_SQUIRTLE_POKE_BALL":
			await _poke_ball("SQUIRTLE", 2, "BULBASAUR", 3)
		"TEXT_OAKSLAB_BULBASAUR_POKE_BALL":
			await _poke_ball("BULBASAUR", 3, "CHARMANDER", 1)
		"TEXT_OAKSLAB_OAK1": await _oak1_text()
		"TEXT_OAKSLAB_OAK_GOT_POKEDEX":
			await ow.print_text("_OaksLabOakGotPokedexText")
			await Sound.text_sound("sound_get_key_item")
		"TEXT_OAKSLAB_POKEDEX1", "TEXT_OAKSLAB_POKEDEX2": await ow.print_text("_OaksLabPokedexText")
		"TEXT_OAKSLAB_OAK2": await _far("_OaksLabOak2Text")
		"TEXT_OAKSLAB_GIRL": await ow.print_text("_OaksLabGirlText")
		"TEXT_OAKSLAB_SCIENTIST1", "TEXT_OAKSLAB_SCIENTIST2": await ow.print_text("_OaksLabScientistText")
		"TEXT_OAKSLAB_OAK_DONT_GO_AWAY_YET": await ow.print_text("_OaksLabOakDontGoAwayYetText")
		"TEXT_OAKSLAB_RIVAL_ILL_TAKE_THIS_ONE": await ow.print_text("_OaksLabRivalIllTakeThisOneText")
		"TEXT_OAKSLAB_RIVAL_RECEIVED_MON":
			await ow.print_text("_OaksLabRivalReceivedMonText")
			await Sound.text_sound("sound_get_key_item")
		"TEXT_OAKSLAB_RIVAL_ILL_TAKE_YOU_ON": await ow.print_text("_OaksLabRivalIllTakeYouOnText")
		"TEXT_OAKSLAB_RIVAL_SMELL_YOU_LATER": await ow.print_text("_OaksLabRivalSmellYouLaterText")
		"TEXT_OAKSLAB_RIVAL_FED_UP_WITH_WAITING": await ow.print_text("_OaksLabRivalFedUpWithWaitingText")
		"TEXT_OAKSLAB_OAK_CHOOSE_MON": await ow.print_text("_OaksLabOakChooseMonText")
		"TEXT_OAKSLAB_RIVAL_WHAT_ABOUT_ME": await ow.print_text("_OaksLabRivalWhatAboutMeText")
		"TEXT_OAKSLAB_OAK_BE_PATIENT": await ow.print_text("_OaksLabOakBePatientText")
		# Route 1
		"TEXT_ROUTE1_YOUNGSTER1":
			if state.has_event("EVENT_GOT_POTION_SAMPLE"):
				await ow.print_text("_Route1Youngster1AlsoGotPokeballsText")
			else:
				state.set_event("EVENT_GOT_POTION_SAMPLE")
				await ow.print_text("_Route1Youngster1MartSampleText")
				if state.give_item("POTION", 1):
					Text.ram["wStringBuffer"] = GameData.item_name("POTION")
					await ow.print_text("_Route1Youngster1GotPotionText")
					await Sound.text_sound("sound_get_item_1")
				else:
					await ow.print_text("_Route1Youngster1NoRoomText")
		# Viridian City
		"TEXT_VIRIDIANCITY_GAMBLER1": await ow.print_text("_ViridianCityGambler1GymAlwaysClosedText")
		"TEXT_VIRIDIANCITY_YOUNGSTER2":
			await ow.print_text("_ViridianCityYoungster2YouWantToKnowAboutText")
			if await Menu.yes_no():
				await ow.print_text("ViridianCityYoungster2CaterpieAndWeedleDescriptionText")
			else:
				await ow.print_text("ViridianCityYoungster2OkThenText")
		"TEXT_VIRIDIANCITY_GIRL":
			await ow.print_text("_ViridianCityGirlWhenIGoShopText" if state.has_event("EVENT_GOT_POKEDEX") else "_ViridianCityGirlHasntHadHisCoffeeYetText")
		"TEXT_VIRIDIANCITY_OLD_MAN_SLEEPY":
			await ow.print_text("_ViridianCityOldManSleepyPrivatePropertyText")
			_viridian_move_player_down()
			_set_script(3)
		"TEXT_VIRIDIANCITY_FISHER":
			if state.has_event("EVENT_GOT_TM42"):
				await ow.print_text("_ViridianCityFisherTM42ExplanationText")
			else:
				await ow.print_text("ViridianCityFisherYouCanHaveThisText")
				if state.give_item("TM42", 1):
					await ow.print_text("_ViridianCityFisherReceivedTM42Text")
					await Sound.text_sound("sound_get_item_2")
					state.set_event("EVENT_GOT_TM42")
				else:
					await ow.print_text("_ViridianCityFisherTM42NoRoomText")
		"TEXT_VIRIDIANCITY_OLD_MAN":
			await ow.print_text("_ViridianCityOldManHadMyCoffeeNowText")
			await GB.frames(2)
			if await Menu.yes_no():
				await ow.print_text("_ViridianCityOldManTimeIsMoneyText")
			else:
				await ow.print_text("_ViridianCityOldManKnowHowToCatchPokemonText")
				_set_script(1)
		"TEXT_VIRIDIANCITY_MART_SIGN": await _far("_MartSignText")
		"TEXT_VIRIDIANCITY_POKECENTER_SIGN": await _far("_PokeCenterSignText")
		# Viridian buildings
		"TEXT_VIRIDIANPOKECENTER_NURSE": await Pokecenter.nurse(ow, npc_index)
		"TEXT_VIRIDIANPOKECENTER_LINK_RECEPTIONIST": await ow.print_text("_CableClubNPCWelcomeText")
		"TEXT_VIRIDIANNICKNAMEHOUSE_SPEAROW":
			await ow.print_text("_ViridianNicknameHouseSpearowText")
			Sound.play_cry("SPEAROW")
			await Sound.wait_for_sfx()
		"TEXT_VIRIDIANMART_CLERK":
			if state.has_event("EVENT_OAK_GOT_PARCEL"):
				await Pokemart.dialogue(ow, "VIRIDIAN_MART")
			else:
				await ow.print_text("_ViridianMartClerkSayHiToOakText")
		"TEXT_VIRIDIANMART_CLERK_YOU_CAME_FROM_PALLET_TOWN": await ow.print_text("_ViridianMartClerkYouCameFromPalletTownText")
		"TEXT_VIRIDIANMART_CLERK_PARCEL_QUEST":
			await ow.print_text("_ViridianMartClerkParcelQuestText")
			await Sound.text_sound("sound_get_key_item")
		# Pewter Gym
		"TEXT_PEWTERGYM_BROCK": await _pewter_gym_brock_text(npc_index)
		"TEXT_PEWTERGYM_GYM_GUIDE": await _pewter_gym_guide_text()
		"TEXT_PEWTERGYM_RECEIVED_TM34": await Text.print_text_no_box("PewterGymReceivedTM34Text")
		# Route 22
		"TEXT_ROUTE22_RIVAL1":
			await ow.print_text("_Route22RivalAfterBattleText1" if state.has_event("EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE") else "_Route22RivalBeforeBattleText1")
		_:
			var label := GameData.text_label_for(text_id)
			await _far(label if label != "" else text_id)


## OaksLabOak1Text.
func _oak1_text() -> void:
	if state.has_event("EVENT_PALLET_AFTER_GETTING_POKEBALLS") \
			or (state.pokedex_owned.size() >= 2 and state.has_event("EVENT_GOT_POKEDEX")):
		await ow.print_text("_OaksLabOak1HowIsYourPokedexComingText")
		ow.do_not_wait_after_text = true
		await DexRating.display(state)
		return
	if state.item_count("POKE_BALL") > 0:
		await ow.print_text("_OaksLabOak1ComeSeeMeSometimesText")
		return
	if state.has_event("EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE"):
		if state.has_event("EVENT_GOT_POKEBALLS_FROM_OAK"):
			await ow.print_text("_OaksLabOak1ComeSeeMeSometimesText")
			return
		state.set_event("EVENT_GOT_POKEBALLS_FROM_OAK")
		state.give_item("POKE_BALL", 5)
		await ow.print_text("_OaksLabOak1ReceivedPokeballsText")
		await Sound.text_sound("sound_get_key_item")
		await Text.run_commands(GameData.text("_OaksLabGivePokeballsExplanationText"))
		return
	if state.has_event("EVENT_GOT_POKEDEX"):
		await ow.print_text("_OaksLabOak1PokemonAroundTheWorldText")
		return
	if state.has_event("EVENT_BATTLED_RIVAL_IN_OAKS_LAB"):
		if state.item_count("OAKS_PARCEL") > 0:
			await ow.print_text("_OaksLabOak1DeliverParcelText")
			await Sound.text_sound("sound_get_key_item")
			await Text.run_commands(GameData.text("_OaksLabOak1ParcelThanksText"))
			state.remove_item("OAKS_PARCEL", 1)   # OaksLabScript_RemoveParcel
			_set_script(15)   # SCRIPT_OAKSLAB_RIVAL_ARRIVES_AT_OAKS_REQUEST
		else:
			await ow.print_text("_OaksLabOak1RaiseYourYoungPokemonText")
		return
	if state.has_event("EVENT_GOT_STARTER_FLAG"):
		await ow.print_text("_OaksLabOak1YourPokemonCanFightText")
	else:
		await ow.print_text("_OaksLabOak1WhichPokemonDoYouWantText")


## A text entry that is just `text_far` + `text_end` in a map with auto text boxes.
func _far(label: String) -> void:
	if ow.no_auto_text_box:
		Menu.message_box()
		await GB.delay3()
	await Text.print_text_no_box(label)


## OaksLabCharmander/Squirtle/BulbasaurPokeBallText.
func _poke_ball(species: String, ball_index: int, rival_species: String, rival_ball: int) -> void:
	rival_starter_temp = rival_species
	rival_ball_index = rival_ball
	if state.has_event("EVENT_GOT_STARTER"):
		ow.set_npc_facing(4, Overworld.FACE_DOWN)
		ow.npcs[4].keep_facing = true
		await ow.print_text("_OaksLabLastMonText")
		return
	if not state.has_event("EVENT_OAK_ASKED_TO_CHOOSE_MON"):
		await ow.print_text("_OaksLabThoseArePokeBallsText")
		return
	ow.set_npc_facing(4, Overworld.FACE_DOWN)
	ow.set_npc_facing(0, Overworld.FACE_RIGHT)
	ow.npcs[4].keep_facing = true
	ow.npcs[0].keep_facing = true
	Text.no_delay = true
	await PokedexPage.new().show(species)
	SGB.run("DEFAULT")
	Text.no_delay = false
	ow.reload_map_view()
	await GB.frames(10)
	var label := "_OaksLabYouWant%sText" % species.capitalize()
	await ow.print_text(label)
	ow.do_not_wait_after_text = true
	var yes := await Menu.yes_no()
	if not yes:
		return
	state.starter = species
	Text.ram["wNameBuffer"] = GameData.mon_name(species)
	ow.hide_object(ball_index)
	ow.do_not_wait_after_text = true
	await ow.print_text("_OaksLabMonEnergeticText")
	await ow.print_text("_OaksLabReceivedMonText")
	await Sound.text_sound("sound_get_key_item")
	state.party.append(PartyMon.create(species, 5))
	state.set_event("EVENT_GOT_STARTER_FLAG")
	ow.joy_ignore = GB.SELECT | GB.START | GB.CTRL_PAD
	_set_script(8)

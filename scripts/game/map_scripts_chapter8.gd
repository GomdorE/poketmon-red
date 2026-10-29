## Chapter 8 map scripts and text handlers: Pokémon Tower 3F-7F (scripts/PokemonTower3F.asm ...
## PokemonTower7F.asm: the channelers, the purified zone, the ghost of Cubone's mother, the
## Rockets and Mr. Fuji) and Route 12 with its gate and the Super Rod house (Route12.asm,
## Route12Gate1F.asm, Route12Gate2F.asm, Route12SuperRodHouse.asm). The ghost battles
## themselves are in Battle (IsGhostBattle, MarowakAnim).
class_name Chapter8Scripts
extends RefCounted

const PURIFIED_ZONE := [Vector2i(10, 8), Vector2i(11, 8), Vector2i(10, 9), Vector2i(11, 9)]
const MAROWAK_SPOT := Vector2i(10, 16)   # PokemonTower6FMarowakCoords
## PokemonTower7FNPCCoordMovementTable: per Rocket (object index), the player's position ->
## the Rocket's way out (R right, D down, L left)
const ROCKET_EXITS := {
	0: {Vector2i(9, 12): "RDDDDDL", Vector2i(10, 11): "DRDDDD", Vector2i(11, 11): "DDDDD", Vector2i(12, 11): "DDDDD"},
	1: {Vector2i(12, 10): "LDDDDDD", Vector2i(11, 9): "DDDLDD", Vector2i(10, 9): "DDDDD", Vector2i(9, 9): "DDDDD"},
	2: {Vector2i(9, 8): "RDDDDDD", Vector2i(10, 7): "DDDDD", Vector2i(11, 7): "DDDDD", Vector2i(12, 7): "DDDDD"},
}
const GOT_SUPER_ROD := "GOT_SUPER_ROD"   # wStatusFlags1 BIT_GOT_SUPER_ROD, kept with the events

var ms: MapScripts
var ow: Overworld
var state: GameState
var entered_map := ""
var rocket_leaving := -1   # wSpriteIndex: the 7F Rocket walking out


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state


## The per-frame map script (see MtMoonScripts.run_map_script for the contract).
func run_map_script() -> bool:
	var _entered := entered_map != ow.map_id
	entered_map = ow.map_id
	match ow.map_id:
		"POKEMON_TOWER_3F", "POKEMON_TOWER_4F":
			await _trainer_scripts()
		"POKEMON_TOWER_5F":
			if ms._script_index() == 0:
				await _purified_zone()
			else:
				await _trainer_scripts()
		"POKEMON_TOWER_6F":
			match ms._script_index():
				0: await _tower_6f_default()
				3: _tower_6f_player_moving()
				4: await _marowak_battle_script()
				_: await _trainer_scripts()
		"POKEMON_TOWER_7F":
			match ms._script_index():
				2: await _tower_7f_end_battle()
				3: _tower_7f_hide_npc()
				4: await _warp_to_mr_fujis_house()
				_: await _trainer_scripts()
		"ROUTE_12":
			match ms._script_index():
				0: await _route12_default()
				3: await _snorlax_post_battle()
				_: await _trainer_scripts()
		"ROUTE_12_GATE_2F":
			ow.no_auto_text_box = true   # DisableAutoTextBoxDrawing
		_:
			return false
	return true


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		"TEXT_POKEMONTOWER6F_MAROWAK_DEPARTED":
			# PokemonTower6FMarowakDepartedText: the ghost's cry between the two texts
			await ow.print_text("_PokemonTower6FGhostWasCubonesMotherText")
			Sound.play_cry("MAROWAK")
			await Sound.wait_for_sfx()
			await GB.frames(30)
			await ow.print_text("_PokemonTower6FSoulWasCalmedText")
		"TEXT_POKEMONTOWER7F_MR_FUJI": await _mr_fuji()
		"TEXT_ROUTE12GATE2F_BRUNETTE_GIRL": await _gate_girl_tm39()
		"TEXT_ROUTE12GATE2F_LEFT_BINOCULARS": await ms.ch6._print_if_facing_up("_Route12Gate2FLeftBinocularsText")
		"TEXT_ROUTE12GATE2F_RIGHT_BINOCULARS": await ms.ch6._print_if_facing_up("_Route12Gate2FRightBinocularsText")
		"TEXT_ROUTE12SUPERRODHOUSE_FISHING_GURU": await _super_rod()
		_:
			return false
	return true


## CheckFightingMapTrainers / DisplayEnemyTrainerTextAndStartBattle / EndTrainerBattle.
func _trainer_scripts() -> void:
	match ms._script_index():
		0: await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()


# --- Pokémon Tower 5F ---------------------------------------------------------------------

## PokemonTower5FDefaultScript: the purified zone heals the party once per visit (no wild
## battles inside), with a white fade and a text; stepping out arms it again.
func _purified_zone() -> void:
	if Vector2i(ow.player.x, ow.player.y) in PURIFIED_ZONE:
		if state.has_event("EVENT_IN_PURIFIED_ZONE"):
			return
		state.set_event("EVENT_IN_PURIFIED_ZONE")
		ow.joy_ignore = GB.CTRL_PAD
		ow.no_battles = true
		Battle.heal_party(state)
		await Intro.fade_out_to_white()
		await GB.delay3()
		await GB.delay3()
		await Intro.fade_in_from_white()
		await ow.display_text_id("TEXT_POKEMONTOWER5F_PURIFIEDZONE", -1)
		ow.joy_ignore = 0
		trace("PURIFIED_ZONE")
		return
	ow.no_battles = false
	state.events.erase("EVENT_IN_PURIFIED_ZONE")
	await ms.trainers.check_fighting_map_trainers()


# --- Pokémon Tower 6F ---------------------------------------------------------------------

## PokemonTower6FDefaultScript: on the ghost's tile "Be gone..." and the battle with the
## restless soul (a level 30 MAROWAK).
func _tower_6f_default() -> void:
	if state.has_event("EVENT_BEAT_GHOST_MAROWAK") or Vector2i(ow.player.x, ow.player.y) != MAROWAK_SPOT:
		await ms.trainers.check_fighting_map_trainers()
		return
	await ow.display_text_id("TEXT_POKEMONTOWER6F_BEGONE", -1)
	ow.battle_request = {"wild": true, "species": "MAROWAK", "level": 30, "restless_soul": true}
	ms._set_script(4)
	trace("MAROWAK_BATTLE")


## PokemonTower6FMarowakBattleScript: a win calms the soul; running away walks the player
## one step to the right.
func _marowak_battle_script() -> void:
	if ow.last_battle_result in ["lost", "blackout"]:
		ow.joy_ignore = 0   # PokemonTower6FSetDefaultScript
		ms._set_script(0)
		return
	ow.joy_ignore = GB.CTRL_PAD
	if ow.last_battle_result == "won":
		state.set_event("EVENT_BEAT_GHOST_MAROWAK")
		await ow.display_text_id("TEXT_POKEMONTOWER6F_MAROWAK_DEPARTED", -1)
		ow.joy_ignore = 0
		ms._set_script(0)
		trace("MAROWAK_DEPARTED")
		return
	ow.simulate([GB.RIGHT])
	ms._set_script(3)


## PokemonTower6FPlayerMovingScript.
func _tower_6f_player_moving() -> void:
	if not ow.sim_queue.is_empty():
		return
	ms._set_script(0)


# --- Pokémon Tower 7F ---------------------------------------------------------------------

## PokemonTower7FEndBattleScript: a beaten Rocket says his line and walks out (the way
## depends on where the player stands), then disappears.
func _tower_7f_end_battle() -> void:
	ms.trainers.seen_by_trainer = false
	if not ow.last_battle_won:
		ow.joy_ignore = 0   # PokemonTower7FSetDefaultScript
		ms._set_script(0)
		return
	var h: Dictionary = ms.trainers.header
	ms.trainers.end_trainer_battle()
	ow.joy_ignore = GB.CTRL_PAD
	var idx := int(h.get("sprite", 1)) - 1
	await ow.display_text_id(str(ow.npcs[idx].text), idx)
	# PokemonTower7FRocketLeaveMovementScript
	var exits: Dictionary = ROCKET_EXITS.get(idx, {})
	var key := Vector2i(ow.player.x, ow.player.y)
	if exits.has(key):
		var moves: Array = []
		for ch in str(exits[key]):
			moves.append({"R": Overworld.NPC_RIGHT, "D": Overworld.NPC_DOWN, "L": Overworld.NPC_LEFT, "U": Overworld.NPC_UP}[ch])
		ow.move_sprite(idx, moves)
	rocket_leaving = idx
	ms._set_script(3)


## PokemonTower7FHideNPCScript.
func _tower_7f_hide_npc() -> void:
	if rocket_leaving >= 0 and ow.npc_moving(rocket_leaving):
		return
	if rocket_leaving >= 0:
		ow.hide_object(rocket_leaving)
	ow.joy_ignore = 0
	rocket_leaving = -1
	ms._set_script(0)
	trace("ROCKET_LEFT")


## PokemonTower7FMrFujiText: Mr. Fuji is rescued (he appears at home, Saffron's Rockets
## change) and the next frame warps the player to his house.
func _mr_fuji() -> void:
	await ow.print_text("_PokemonTower7FMrFujiRescueText")
	state.set_event("EVENT_RESCUED_MR_FUJI")
	state.set_event("EVENT_RESCUED_MR_FUJI_2")
	_show("MR_FUJIS_HOUSE", 4, true)    # TOGGLE_MR_FUJIS_HOUSE_MR_FUJI
	_show("SAFFRON_CITY", 4, false)     # TOGGLE_SAFFRON_CITY_E (Rocket 5)
	_show("SAFFRON_CITY", 5, true)      # TOGGLE_SAFFRON_CITY_F (Rocket 6)
	ms._set_script(4)


## ShowObject / HideObject on a map that is not loaded (the events the map reads on load).
func _show(map: String, index: int, shown: bool) -> void:
	state.set_event("%s_%s_%d" % ["SHOW" if shown else "HIDE", map, index])
	state.events.erase("%s_%s_%d" % ["HIDE" if shown else "SHOW", map, index])


## PokemonTower7FWarpToMrFujiHouseScript: Mr. Fuji vanishes and the player warps to the
## second door of his house, facing up (BIT_WARP_FROM_CUR_SCRIPT).
func _warp_to_mr_fujis_house() -> void:
	ow.joy_ignore = GB.BUTTONS | GB.CTRL_PAD
	ow.hide_object(3)   # TOGGLE_POKEMON_TOWER_7F_MR_FUJI
	ow.player.facing = Overworld.FACE_UP
	state.last_map = "LAVENDER_TOWN"
	ms._set_script(0)
	trace("FUJI_RESCUED")
	await ow.warp_to("MR_FUJIS_HOUSE", 1)
	ow.joy_ignore = 0


# --- Route 12 ------------------------------------------------------------------------------

## Route12DefaultScript: the POKé FLUTE flag (ItemUsePokeFlute) wakes SNORLAX for a level
## 30 wild battle; the sleeping sprite goes away.
func _route12_default() -> void:
	if state.has_event("EVENT_BEAT_ROUTE12_SNORLAX") or not state.has_event("EVENT_FIGHT_ROUTE12_SNORLAX"):
		await ms.trainers.check_fighting_map_trainers()
		return
	state.events.erase("EVENT_FIGHT_ROUTE12_SNORLAX")
	await ow.display_text_id("TEXT_ROUTE12_SNORLAX_WOKE_UP", -1)
	ow.battle_request = {"wild": true, "species": "SNORLAX", "level": 30}
	ow.hide_object(0)   # TOGGLE_ROUTE_12_SNORLAX
	ms._set_script(3)
	trace("SNORLAX_BATTLE")


## Route12SnorlaxPostBattleScript: "SNORLAX calmed down" unless it was caught or the player
## ran (wBattleResult 2); either way it is gone.
func _snorlax_post_battle() -> void:
	if ow.last_battle_result in ["lost", "blackout"]:
		ow.joy_ignore = 0   # Route12ResetScripts
		ms._set_script(0)
		return
	if ow.last_battle_result == "won":
		await ow.display_text_id("TEXT_ROUTE12_SNORLAX_CALMED_DOWN", -1)
	state.set_event("EVENT_BEAT_ROUTE12_SNORLAX")
	await GB.delay3()
	ms._set_script(0)
	trace("SNORLAX_DONE result=%s" % ow.last_battle_result)


## Route12Gate2FBrunetteGirlText: TM39 (SWIFT) once.
func _gate_girl_tm39() -> void:
	if state.has_event("EVENT_GOT_TM39"):
		await ow.print_text("_Route12Gate2FBrunetteGirlTM39ExplanationText")
		return
	await ow.print_text("_Route12Gate2FBrunetteGirlYouCanHaveThisText")
	if state.give_item("TM39", 1):
		Text.ram["wStringBuffer"] = GameData.item_name("TM39")
		await ow.print_text("_Route12Gate2FBrunetteGirlReceivedTM39Text")
		await Sound.text_sound("sound_get_item_1")
		state.set_event("EVENT_GOT_TM39")
		trace("GOT_TM39")
	else:
		await ow.print_text("_Route12Gate2FBrunetteGirlTM39NoRoomText")


## Route12SuperRodHouseFishingGuruText: the SUPER ROD once (wStatusFlags1 BIT_GOT_SUPER_ROD).
func _super_rod() -> void:
	if state.has_event(GOT_SUPER_ROD):
		await ow.print_text("_Route12SuperRodHouseFishingGuruTryFishingText")
		return
	await ow.print_text("_Route12SuperRodHouseFishingGuruDoYouLikeToFishText")
	if not await Menu.yes_no():
		await ow.print_text("_Route12SuperRodHouseFishingGuruThatsDisappointingText")
		return
	if not state.give_item("SUPER_ROD", 1):
		await ow.print_text("_Route12SuperRodHouseFishingGuruNoRoomText")
		return
	state.set_event(GOT_SUPER_ROD)
	Text.ram["wStringBuffer"] = GameData.item_name("SUPER_ROD")
	await ow.print_text("_Route12SuperRodHouseFishingGuruReceivedSuperRodText")
	await Sound.text_sound("sound_get_item_1")
	trace("GOT_SUPER_ROD")


func trace(message: String) -> void:
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("CHAPTER8 %s frame=%d" % [message, GB.frame_count])

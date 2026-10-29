## The Rocket Hideout under the Game Corner (scripts/RocketHideoutB1F.asm ... B4F.asm,
## RocketHideoutElevator.asm): the doors that open once their guards are beaten, the arrow
## tiles of B2F/B3F that spin the player along (home/map_objects.asm DecodeArrowMovementRLE,
## engine/overworld/spinners.asm), Giovanni and the SILPH SCOPE, the LIFT KEY elevator.
class_name RocketHideoutScripts
extends RefCounted

const ELEVATOR_FLOORS := ["FLOOR_B1F", "FLOOR_B2F", "FLOOR_B4F"]
## RocketHideoutElevatorWarpMaps (destination warp 0-based, map)
const ELEVATOR_WARPS := [[4, "ROCKET_HIDEOUT_B1F"], [4, "ROCKET_HIDEOUT_B2F"], [2, "ROCKET_HIDEOUT_B4F"]]

## RocketHideout2ArrowTilePlayerMovement: (x, y) -> [[direction, steps] ...]; the lists are
## read from the end, so the player walks the last entry first.
const B2F_ARROWS := {
	Vector2i(4, 9): [["L", 2]], Vector2i(4, 11): [["R", 4]], Vector2i(4, 15): [["U", 4], ["R", 4]],
	Vector2i(4, 16): [["U", 4], ["R", 4], ["U", 1]], Vector2i(4, 19): [["L", 2]], Vector2i(4, 22): [["L", 2], ["U", 3]],
	Vector2i(5, 14): [["D", 2], ["R", 4]], Vector2i(6, 22): [["U", 2]], Vector2i(6, 24): [["U", 4]],
	Vector2i(8, 9): [["L", 6]], Vector2i(8, 12): [["U", 1]], Vector2i(8, 15): [["U", 4]], Vector2i(8, 19): [["L", 6]],
	Vector2i(8, 23): [["L", 6], ["U", 4]], Vector2i(9, 14): [["D", 2]], Vector2i(9, 22): [["D", 2]],
	Vector2i(10, 9): [["L", 8]], Vector2i(10, 10): [["L", 8], ["U", 1]], Vector2i(10, 15): [["L", 8], ["U", 6]],
	Vector2i(10, 17): [["U", 2], ["R", 4]], Vector2i(10, 19): [["U", 2], ["R", 4], ["U", 2]], Vector2i(10, 25): [["R", 4]],
	Vector2i(11, 14): [["D", 2], ["R", 4], ["D", 2]], Vector2i(11, 16): [["D", 2], ["R", 4]], Vector2i(11, 18): [["D", 2]],
	Vector2i(12, 9): [["L", 10]], Vector2i(12, 11): [["L", 10], ["U", 2]], Vector2i(12, 13): [["L", 10], ["U", 4]],
	Vector2i(12, 17): [["U", 2], ["R", 2]], Vector2i(13, 10): [["R", 1], ["D", 2]], Vector2i(13, 12): [["R", 1]],
	Vector2i(13, 16): [["D", 2], ["R", 2]], Vector2i(13, 18): [["D", 2], ["L", 2]],
	Vector2i(13, 19): [["U", 2], ["R", 4], ["U", 2], ["L", 3]], Vector2i(13, 22): [["D", 2], ["L", 4]],
	Vector2i(13, 23): [["L", 6], ["U", 4], ["L", 5]], Vector2i(14, 17): [["U", 2]], Vector2i(15, 16): [["D", 2]],
	Vector2i(16, 14): [["U", 1]], Vector2i(16, 16): [["U", 3]], Vector2i(16, 18): [["U", 5]],
	Vector2i(17, 10): [["R", 1], ["D", 2], ["L", 4]], Vector2i(17, 11): [["L", 10], ["U", 2], ["L", 5]],
}
## RocketHideout3ArrowTilePlayerMovement
const B3F_ARROWS := {
	Vector2i(10, 13): [["R", 4]], Vector2i(10, 19): [["R", 4], ["U", 4], ["R", 4]], Vector2i(11, 18): [["D", 4], ["R", 4]],
	Vector2i(12, 11): [["L", 2]], Vector2i(12, 17): [["R", 4], ["U", 2], ["R", 2]], Vector2i(12, 20): [["R", 4], ["U", 2], ["R", 2], ["U", 3]],
	Vector2i(13, 16): [["R", 4]], Vector2i(14, 11): [["R", 2]], Vector2i(14, 15): [["R", 4]], Vector2i(14, 17): [["R", 4], ["U", 2]],
	Vector2i(14, 19): [["R", 4], ["U", 4]], Vector2i(15, 16): [["R", 2]], Vector2i(15, 18): [["D", 4]], Vector2i(16, 13): [["U", 2]],
	Vector2i(17, 12): [["D", 4]], Vector2i(18, 16): [["U", 1]],
}

var chapter: Chapter7Scripts
var ms: MapScripts
var ow: Overworld
var state: GameState
var elevator := Elevator.new()
var b1f_reload := false   # BIT_CUR_MAP_LOADED_1 (the door callbacks)
var b4f_reload := false


func _init(c: Chapter7Scripts) -> void:
	chapter = c
	ms = c.ms
	ow = c.ow
	state = c.state


func run_map_script(entered: bool) -> bool:
	match ow.map_id:
		"ROCKET_HIDEOUT_B1F":
			if entered or b1f_reload:
				b1f_reload = false
				_b1f_door()
			await _trainer_scripts()
		"ROCKET_HIDEOUT_B2F":
			await _arrow_floor(B2F_ARROWS)
		"ROCKET_HIDEOUT_B3F":
			await _arrow_floor(B3F_ARROWS)
		"ROCKET_HIDEOUT_B4F":
			if entered or b4f_reload:
				b4f_reload = false
				_b4f_door()
			if ms._script_index() == 3:
				await _beat_giovanni()
			else:
				await _trainer_scripts()
		"ROCKET_HIDEOUT_ELEVATOR":
			await elevator.run_map_script(ow, entered, true)
		_:
			return false
	return true


func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		"TEXT_ROCKETHIDEOUTB4F_GIOVANNI":
			if state.has_event("EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI"):
				await ow.print_text("_RocketHideoutB4FGiovanniHopeWeMeetAgainText")
			else:
				await ow.print_text("_RocketHideoutB4FGiovanniImpressedYouGotHereText")
				chapter.event_battle(npc_index, 3, "_RocketHideoutB4FGiovanniWhatCannotBeText")
		"TEXT_ROCKETHIDEOUTELEVATOR":
			if state.item_count("LIFT_KEY") > 0:
				await elevator.floor_menu(ow, ELEVATOR_FLOORS, ELEVATOR_WARPS)
			else:
				await ow.print_text("_RocketHideoutElevatorAppearsToNeedKeyText")
				await Text.wait_scroll_button()
			ow.do_not_wait_after_text = true
		_:
			return false
	return true


## A trainer text with its own after-battle script, checked before TrainerEngine.handle_text:
## RocketHideoutB4FRocket3AfterBattleText, where the beaten Rocket drops the LIFT KEY once.
func trainer_text(text_id: String, _npc_index: int) -> bool:
	if text_id != "TEXT_ROCKETHIDEOUTB4F_ROCKET3" or not state.has_event("EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_2"):
		return false
	await ow.print_text("_RocketHideoutB4FRocket3AfterBattleText")
	if not state.has_event("EVENT_ROCKET_DROPPED_LIFT_KEY"):
		state.set_event("EVENT_ROCKET_DROPPED_LIFT_KEY")
		ow.show_object(8)   # TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_5
		chapter.trace("LIFT_KEY_DROPPED")
	return true


## CheckFightingMapTrainers / DisplayEnemyTrainerTextAndStartBattle / EndTrainerBattle.
func _trainer_scripts() -> void:
	match ms._script_index():
		0: await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()


## RocketHideoutB1FDoorCallbackScript: the door at block (12, 8) opens once the fifth Rocket
## is beaten; the "entered" event is only tested, so the door sound plays on every visit.
func _b1f_door() -> void:
	var block := 0x54   # door
	if state.has_event("EVENT_ENTERED_ROCKET_HIDEOUT"):
		block = 0x0e    # floor
	elif state.has_event("EVENT_BEAT_ROCKET_HIDEOUT_1_TRAINER_4"):
		Sound.play_sfx("SFX_GO_INSIDE")
		block = 0x0e
	_replace_block(12, 8, block)


## RocketHideoutB4FDoorCallbackScript: the door at block (12, 5) opens once both Rockets
## beside it are beaten.
func _b4f_door() -> void:
	var block := 0x2d   # door
	if state.has_event("EVENT_ROCKET_HIDEOUT_4_DOOR_UNLOCKED"):
		block = 0x0e
	elif state.has_event("EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0") and state.has_event("EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_1"):
		Sound.play_sfx("SFX_GO_INSIDE")
		state.set_event("EVENT_ROCKET_HIDEOUT_4_DOOR_UNLOCKED")
		block = 0x0e
	_replace_block(12, 5, block)


func _replace_block(bx: int, by: int, block: int) -> void:
	ow.cut_blocks[Vector2i(bx, by)] = block
	ow._put_block(bx, by, block, ow.tileset)


## RocketHideoutB2FDefaultScript / B3F and the *PlayerSpinningScript: standing on an arrow
## tile starts the simulated walk (BIT_SPINNING, SFX_ARROW_TILES, every key ignored); the
## spin ends when the simulated presses run out.
func _arrow_floor(arrows: Dictionary) -> void:
	match ms._script_index():
		0:
			var key := Vector2i(ow.player.x, ow.player.y)
			if not arrows.has(key):
				await ms.trainers.check_fighting_map_trainers()
				return
			var presses: Array = []
			var entries: Array = arrows[key]
			for i in range(entries.size() - 1, -1, -1):
				var dir: int = {"U": GB.UP, "D": GB.DOWN, "L": GB.LEFT, "R": GB.RIGHT}[entries[i][0]]
				for n in int(entries[i][1]):
					presses.append(dir)
			ow.start_spinning()
			ow.simulate(presses)   # StartSimulatingJoypadStates
			Sound.play_sfx("SFX_ARROW_TILES")
			ms._set_script(3)
			chapter.trace("ARROW_TILE at (%d,%d) steps=%d" % [key.x, key.y, presses.size()])
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()
		3:
			if not ow.sim_queue.is_empty():
				return
			ow.joy_ignore = 0
			ow.spinning = false
			ms._set_script(0)
			chapter.trace("ARROW_TILE done at (%d,%d)" % [ow.player.x, ow.player.y])


## RocketHideoutB4FBeatGiovanniScript: Giovanni's last words, then (in the dark) he is gone
## and the SILPH SCOPE lies where he stood.
func _beat_giovanni() -> void:
	if not ow.last_battle_won:
		ow.joy_ignore = 0   # RocketHideoutB4FSetDefaultScript
		ms._set_script(0)
		return
	ow.joy_ignore = GB.CTRL_PAD
	state.set_event("EVENT_BEAT_ROCKET_HIDEOUT_GIOVANNI")
	await ow.display_text_id("TEXT_ROCKETHIDEOUTB4F_GIOVANNI_HOPE_WE_MEET_AGAIN", -1)
	await Intro.fade_out_to_black()
	ow.hide_object(0)   # TOGGLE_ROCKET_HIDEOUT_B4F_GIOVANNI
	ow.show_object(7)   # TOGGLE_ROCKET_HIDEOUT_B4F_ITEM_4 (the SILPH SCOPE)
	ow._render()
	await Intro.fade_in_from_black()
	ow.joy_ignore = 0
	b4f_reload = true
	ms._set_script(0)
	chapter.trace("GIOVANNI_BEATEN")

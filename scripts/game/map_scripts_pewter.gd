## Chapter 3 map scripts and text handlers: Viridian Forest north gate, Pewter City
## and its buildings (scripts/PewterCity.asm, Museum1F.asm, Museum2F.asm, PewterMart.asm,
## PewterPokecenter.asm, PewterNidoranHouse.asm, PewterSpeechHouse.asm,
## ViridianForestNorthGate.asm). Pewter Gym lives in map_scripts.gd (trainer engine).
## Texts that are only `text_far` + `text_end` fall through to MapScripts' generic
## label lookup (Museum2F, the speech house, the north gate, signs, ...).
class_name PewterScripts
extends RefCounted

const PEWTERCITY_SUPER_NERD1 := 2   # object index (sprite 3, TOGGLE_MUSEUM_GUY)
const PEWTERCITY_YOUNGSTER := 4     # object index (sprite 5, TOGGLE_GYM_GUY)
const PEWTERPOKECENTER_JIGGLYPUFF := 2
const NPC_MOVEMENT_MUSEUM_GUY := 2  # wNPCMovementScriptPointerTableNum
const NPC_MOVEMENT_GYM_GUY := 3

# PewterCityPlayerLeavingEastCoords (dbmapcoord x, y)
const LEAVING_EAST_COORDS := [Vector2i(35, 17), Vector2i(36, 17), Vector2i(37, 18), Vector2i(37, 19)]

var ms: MapScripts
var ow: Overworld
var state: GameState
var npc_movement := 0        # wNPCMovementScriptPointerTableNum
var npc_movement_fn := 0     # wNPCMovementScriptFunctionNum
var saved_sprite_pos := Vector2i(-1, -1)   # GetSpritePosition2 / SetSpritePosition2


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state


## The per-frame map script of the chapter 3 maps (called for maps map_scripts.gd
## does not handle itself).
func run_map_script() -> void:
	match ow.map_id:
		"PEWTER_CITY":
			await _pewter_city()
		"MUSEUM_1F":
			# Museum1F_Script: no auto text box, wDoNotWaitForButtonPressAfterDisplayingText = 0
			ow.no_auto_text_box = true
			ow.do_not_wait_after_text = false
			await _museum_1f()
		"PEWTER_MART":
			ow.no_auto_text_box = true
		_:
			pass


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		# Pewter City
		"TEXT_PEWTERCITY_SUPER_NERD1": await _super_nerd1_text()
		"TEXT_PEWTERCITY_SUPER_NERD2":
			await ow.print_text("_PewterCitySuperNerd2DoYouKnowWhatImDoingText")
			if await Menu.yes_no():
				await ow.print_text("_PewterCitySuperNerd2ThatsRightText")
			else:
				await ow.print_text("_PewterCitySuperNerd2ImSprayingRepelText")
		"TEXT_PEWTERCITY_YOUNGSTER":
			await ow.print_text("_PewterCityYoungsterYoureATrainerFollowMeText")
			_start_npc_movement_script(NPC_MOVEMENT_GYM_GUY, PEWTERCITY_YOUNGSTER)
			_set_pewter_script(4)   # SCRIPT_PEWTERCITY_YOUNGSTER_SHOWS_PLAYER_GYM
		"TEXT_PEWTERCITY_MART_SIGN": await ms._far("_MartSignText")
		"TEXT_PEWTERCITY_POKECENTER_SIGN": await ms._far("_PokeCenterSignText")
		# Museum 1F
		"TEXT_MUSEUM1F_SCIENTIST1": await _museum_scientist1_text()
		"TEXT_MUSEUM1F_SCIENTIST2": await _museum_scientist2_text()
		# Pewter Mart
		"TEXT_PEWTERMART_CLERK": await Pokemart.dialogue(ow, "PEWTER_MART")
		# Pewter Pokémon Center
		"TEXT_PEWTERPOKECENTER_NURSE": await Pokecenter.nurse(ow, npc_index)
		"TEXT_PEWTERPOKECENTER_LINK_RECEPTIONIST": await ow.print_text("_CableClubNPCWelcomeText")
		"TEXT_PEWTERPOKECENTER_JIGGLYPUFF": await _jigglypuff_text()
		# Pewter Nidoran house
		"TEXT_PEWTERNIDORANHOUSE_NIDORAN":
			await ms._far("_PewterNidoranHouseNidoranText")
			Sound.play_cry("NIDORAN_M")
			await Sound.wait_for_sfx()
		_:
			return false
	return true


# --- Pewter City --------------------------------------------------------------------

func _pewter_script() -> int:
	return state.map_scripts.get("PEWTER_CITY", 0)


func _set_pewter_script(i: int) -> void:
	state.map_scripts["PEWTER_CITY"] = i
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("MAPSCRIPT PEWTER_CITY -> %d (frame %d) player=(%d,%d)" % [i, GB.frame_count, ow.player.x, ow.player.y])


## PewterCity_Script (RunMapScript runs RunNPCMovementScript first).
func _pewter_city() -> void:
	ow.no_auto_text_box = false
	_run_npc_movement_script()
	match _pewter_script():
		0:
			# PewterCityDefaultScript

			state.map_scripts["MUSEUM_1F"] = 0
			state.events.erase("EVENT_BOUGHT_MUSEUM_TICKET")
			# PewterCityCheckPlayerLeavingEastScript
			if state.has_event("EVENT_BEAT_BROCK"):
				return
			if not Vector2i(ow.player.x, ow.player.y) in LEAVING_EAST_COORDS:
				return
			ow.joy_ignore = GB.CTRL_PAD
			# TEXT_PEWTERCITY_YOUNGSTER is also sprite 5's text: the youngster faces the player
			await ow.display_text_id("TEXT_PEWTERCITY_YOUNGSTER", PEWTERCITY_YOUNGSTER)
		1:
			# PewterCitySuperNerd1ShowsPlayerMuseumScript
			if npc_movement != 0:
				return
			await _set_facing_and_delay(PEWTERCITY_SUPER_NERD1, Overworld.FACE_UP)
			await Sound.play_default_music()
			await ow.display_text_id("TEXT_PEWTERCITY_SUPER_NERD1_ITS_RIGHT_HERE", -1)
			# SetSpritePosition1: screen ($30, $3c) = one block left of the player, map (13, 8)
			_set_sprite_position1(PEWTERCITY_SUPER_NERD1, 13, 8, -16)
			ow.move_sprite(PEWTERCITY_SUPER_NERD1, [Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_DOWN])
			_set_pewter_script(2)
		2:
			# PewterCityHideSuperNerd1Script
			if ow.npc_moving(PEWTERCITY_SUPER_NERD1):
				return
			ow.hide_object(PEWTERCITY_SUPER_NERD1)
			_set_pewter_script(3)
		3:
			# PewterCityResetSuperNerd1Script
			_set_sprite_position2(PEWTERCITY_SUPER_NERD1)
			ow.show_object(PEWTERCITY_SUPER_NERD1)
			ow.joy_ignore = 0
			_set_pewter_script(0)
		4:
			# PewterCityYoungsterShowsPlayerGymScript
			if npc_movement != 0:
				return
			await _set_facing_and_delay(PEWTERCITY_YOUNGSTER, Overworld.FACE_LEFT)
			await Sound.play_default_music()
			await ow.display_text_id("TEXT_PEWTERCITY_YOUNGSTER_GO_TAKE_ON_BROCK", -1)
			# SetSpritePosition1: map (12, 18) but screen X $40 instead of $50 (the original
			# bug): the youngster is drawn over the player while he walks off
			_set_sprite_position1(PEWTERCITY_YOUNGSTER, 12, 18, 0)
			ow.move_sprite(PEWTERCITY_YOUNGSTER, [Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT])
			_set_pewter_script(5)
		5:
			# PewterCityHideYoungsterScript
			if ow.npc_moving(PEWTERCITY_YOUNGSTER):
				return
			ow.hide_object(PEWTERCITY_YOUNGSTER)
			_set_pewter_script(6)
		6:
			# PewterCityResetYoungsterScript
			_set_sprite_position2(PEWTERCITY_YOUNGSTER)
			ow.show_object(PEWTERCITY_YOUNGSTER)
			ow.joy_ignore = 0
			_set_pewter_script(0)


## PewterCitySuperNerd1Text.
func _super_nerd1_text() -> void:
	await ow.print_text("_PewterCitySuperNerd1DidYouCheckOutMuseumText")
	if await Menu.yes_no():
		await ow.print_text("_PewterCitySuperNerd1WerentThoseFossilsAmazingText")
		return
	await ow.print_text("_PewterCitySuperNerd1YouHaveToGoText")
	_start_npc_movement_script(NPC_MOVEMENT_MUSEUM_GUY, PEWTERCITY_SUPER_NERD1)
	_set_pewter_script(1)   # SCRIPT_PEWTERCITY_SUPER_NERD1_SHOWS_PLAYER_MUSEUM


## SetSpriteFacingDirectionAndDelay + SetSpriteImageIndexAfterSettingFacingDirection.
func _set_facing_and_delay(index: int, facing: int) -> void:
	ow.set_npc_facing(index, facing)
	ow.npcs[index].anim = 0
	await GB.frames(6)


## SetSpritePosition1 with the map coordinates and a screen X relative to the player
## (the screen Y is the player's row).
func _set_sprite_position1(index: int, x: int, y: int, screen_dx: int) -> void:
	ow.set_npc_position(index, x, y)
	var n: Dictionary = ow.npcs[index]
	n.px = ow.player.px + screen_dx
	n.py = ow.player.py


## SetSpritePosition2: back to the position saved by GetSpritePosition2.
func _set_sprite_position2(index: int) -> void:
	if saved_sprite_pos.x >= 0:
		ow.set_npc_position(index, saved_sprite_pos.x, saved_sprite_pos.y)
		saved_sprite_pos = Vector2i(-1, -1)


## The text handler's part: wNPCMovementScriptPointerTableNum / FunctionNum and
## GetSpritePosition2 of the guide.
func _start_npc_movement_script(table: int, index: int) -> void:
	npc_movement = table
	npc_movement_fn = 0
	var n: Dictionary = ow.npcs[index]
	saved_sprite_pos = Vector2i(n.x, n.y)
	# IsPlayerCharacterBeingControlledByGame is true from now on
	ow.follow_script = {"fn": 99, "pewter": table}


## RunNPCMovementScript: PewterMuseumGuyMovementScriptPointerTable /
## PewterGymGuyMovementScriptPointerTable (engine/overworld/auto_movement.asm).
func _run_npc_movement_script() -> void:
	if npc_movement == 0:
		return
	match npc_movement_fn:
		0:
			if npc_movement == NPC_MOVEMENT_MUSEUM_GUY:
				_walk_with_guide(PEWTERCITY_SUPER_NERD1,
					[[0, 1], [GB.UP, 3], [GB.LEFT, 13], [GB.UP, 6]],
					[[Overworld.NPC_UP, 6], [Overworld.NPC_LEFT, 13], [Overworld.NPC_UP, 3], [Overworld.NPC_LEFT, 1]],
					_museum_guy_prefix())
			else:
				_walk_with_guide(PEWTERCITY_YOUNGSTER,
					[[0, 1], [GB.RIGHT, 2], [GB.DOWN, 5], [GB.LEFT, 11], [GB.UP, 5], [GB.LEFT, 15]],
					[[Overworld.NPC_DOWN, 2], [Overworld.NPC_LEFT, 15], [Overworld.NPC_UP, 5], [Overworld.NPC_LEFT, 11], [Overworld.NPC_DOWN, 5], [Overworld.NPC_RIGHT, 3]],
					_gym_guy_prefix())
			npc_movement_fn = 1
		1:
			# PewterMovementScript_Done
			if ow.sim_queue.size() > 0:
				return
			# EndNPCMovementScript
			npc_movement = 0
			npc_movement_fn = 0
			ow.follow_script = {}


## PewterMovementScript_WalkToMuseum / _WalkToGym: MUSIC_MUSEUM_GUY, the player's
## simulated joypad list (RLE, consumed from its end; PewterGuys overwrites the first
## consumed entry with the approach moves for the player's square, which are consumed
## from their end too) and the guide's DoScriptedNPCMovement list.
func _walk_with_guide(index: int, player_rle: Array, npc_rle: Array, prefix: Array) -> void:
	Sound.play_new_sound("MUSIC_MUSEUM_GUY")
	var entries: Array = []
	for e in player_rle:
		for i in int(e[1]):
			entries.append(int(e[0]))
	entries.pop_back()   # PewterGuys: `dec a` overwrites the last byte before $ff
	var presses: Array = []
	for i in range(prefix.size() - 1, -1, -1):
		presses.append(prefix[i])
	for i in range(entries.size() - 1, -1, -1):
		presses.append(entries[i])
	ow.simulate(presses)
	# InitScriptedNPCMovement takes the first frame (the guide moves from the next one)
	var moves: Array = [-1]
	for e in npc_rle:
		for i in int(e[1]):
			moves.append(int(e[0]))
	ow.start_scripted_npc(index, moves)
	ow.follow_script = {"fn": 99, "pewter": npc_movement}
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("PEWTER_GUIDE walk from (%d,%d) presses=%d npc=%d" % [ow.player.x, ow.player.y, presses.size(), moves.size() - 1])


## PewterMuseumGuyCoords: below, above, left and right of the museum guy.
func _museum_guy_prefix() -> Array:
	match Vector2i(ow.player.x, ow.player.y):
		Vector2i(27, 18): return [GB.UP, GB.UP]
		Vector2i(27, 16): return [GB.RIGHT, GB.LEFT]
		Vector2i(26, 17): return [GB.UP, GB.RIGHT]
		Vector2i(28, 17): return [GB.UP, GB.LEFT]
	return []


## PewterGymGuyCoords: the squares that trigger the gym guy ($00 is a pause).
func _gym_guy_prefix() -> Array:
	match Vector2i(ow.player.x, ow.player.y):
		Vector2i(34, 16): return [GB.LEFT, GB.DOWN, GB.DOWN, GB.RIGHT]
		Vector2i(35, 17): return [GB.LEFT, GB.DOWN, GB.RIGHT, GB.LEFT]
		Vector2i(37, 18): return [GB.LEFT, GB.LEFT, GB.LEFT, 0, 0, 0, 0, 0, 0, 0, 0]
		Vector2i(37, 19): return [GB.LEFT, GB.LEFT, GB.UP, GB.LEFT]
		Vector2i(36, 17): return [GB.LEFT, GB.DOWN, GB.LEFT, 0, 0, 0, 0, 0, 0, 0, 0]
	return []


# --- Museum 1F -----------------------------------------------------------------------

## Museum1F_Script: walking past the ticket counter (y 4, x 9 or 10) calls the scientist.
func _museum_1f() -> void:
	if ms._script_index() != 0:
		return   # Museum1FNoopScript
	if ow.player.y != 4 or (ow.player.x != 9 and ow.player.x != 10):
		return
	await ow.display_text_id("TEXT_MUSEUM1F_SCIENTIST1", 0)


## Museum1FScientist1Text: the ticket counter (or the amber talk from behind it).
func _museum_scientist1_text() -> void:
	var x := ow.player.x
	var y := ow.player.y
	if (y == 4 and x == 13) or (y == 3 and x == 12):
		# .behind_counter
		await ow.print_text("_Museum1FScientist1DoYouKnowWhatAmberIsText")
		if await Menu.yes_no():
			await ow.print_text("_Museum1FScientist1TheresALabSomewhereText")
		else:
			await ow.print_text("_Museum1FScientist1AmberIsFossilizedTreeSapText")
		return
	if y != 4:
		# .not_behind_counter
		if state.has_event("EVENT_BOUGHT_MUSEUM_TICKET"):
			await ow.print_text("_Museum1FScientist1TakePlentyOfTimeText")
		else:
			await ow.print_text("_Museum1FScientist1GoToOtherSideText")
		return
	# .check_ticket
	if state.has_event("EVENT_BOUGHT_MUSEUM_TICKET"):
		await ow.print_text("_Museum1FScientist1TakePlentyOfTimeText")
		return
	# .no_ticket: MONEY_BOX, the 50¥ question
	Pokemart._money_box(state)
	await ow.print_text("_Museum1FScientist1WouldYouLikeToComeInText")
	if await Menu.yes_no():
		if state.money >= 50:
			await ow.print_text("_Museum1FScientist1ThankYouText")
			state.set_event("EVENT_BOUGHT_MUSEUM_TICKET")
			state.money -= 50
			Pokemart._money_box(state)
			await Sound.play_sfx_wait_for_current("SFX_PURCHASE")
			await Sound.wait_for_sfx()
			ms._set_script(1)   # SCRIPT_MUSEUM1F_NOOP
			return
		await ow.print_text("_Museum1FScientist1DontHaveEnoughMoneyText")
	# .deny_entry: step back down
	await ow.print_text("_Museum1FScientist1ComeAgainText")
	ow.simulate([GB.DOWN])


## Museum1FScientist2Text: the Old Amber.
func _museum_scientist2_text() -> void:
	if state.has_event("EVENT_GOT_OLD_AMBER"):
		await ow.print_text("_Museum1FScientist2GetTheOldAmberCheckText")
		return
	await ow.print_text("_Museum1FScientist2TakeThisToAPokemonLabText")
	if state.give_item("OLD_AMBER", 1):
		state.set_event("EVENT_GOT_OLD_AMBER")
		ow.hide_object(4)   # TOGGLE_OLD_AMBER
		await ow.print_text("_Museum1FScientist2ReceivedOldAmberText")
		await Sound.text_sound("sound_get_item_1")
	else:
		await ow.print_text("_Museum1FScientist2YouDontHaveSpaceText")


# --- Pewter Pokémon Center -------------------------------------------------------------

## PewterPokecenterJigglypuffText: Jigglypuff sings and spins (its image index cycles
## down, left, up, right every 24 frames until the song ends).
func _jigglypuff_text() -> void:
	ow.do_not_wait_after_text = true
	await ow.print_text("_PewterPokecenterJigglypuffText")
	Sound.stop_all_sound()   # SFX_STOP_ALL_MUSIC
	await GB.frames(32)
	var dirs: Array = [Overworld.FACE_DOWN, Overworld.FACE_LEFT, Overworld.FACE_UP, Overworld.FACE_RIGHT]
	var n: Dictionary = ow.npcs[PEWTERPOKECENTER_JIGGLYPUFF]
	var k: int = maxi(0, dirs.find(int(n.facing)))
	Sound.play_music("MUSIC_JIGGLYPUFF_SONG")
	while true:
		n.facing = dirs[k]
		_draw_npc(n)
		k = (k + 1) % 4
		await GB.frames(24)
		if Sound.ch_id[Sound.CHAN1] == 0 and Sound.ch_id[Sound.CHAN1 + 1] == 0:
			break
	await GB.frames(48)
	await Sound.play_default_music()


## The NPC's OAM entries only (the text box stays on screen).
func _draw_npc(n: Dictionary) -> void:
	var vx: int = ow.player.px - 64
	var vy: int = ow.player.py - 64
	var fr := Overworld._frame_for(int(n.facing), 0, int(n.frames))
	Overworld.draw_sprite_frame(GB.screen, 4 + 4 * int(n.index), str(n.sprite), int(fr[0]), int(n.px) - vx, int(n.py) - vy - 4, bool(fr[1]))

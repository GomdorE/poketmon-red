## Chapter 5: Vermilion City and its buildings (scripts/VermilionCity.asm, VermilionDock.asm,
## VermilionGym.asm + engine/events/hidden_events/vermilion_gym_trash.asm, PokemonFanClub.asm,
## VermilionOldRodHouse.asm, VermilionPidgeyHouse.asm, VermilionTradeHouse.asm,
## VermilionMart.asm, VermilionPokecenter.asm).
class_name VermilionScripts
extends RefCounted

var chapter: Chapter5Scripts
var ms: MapScripts
var ow: Overworld
var state: GameState

var first_lock_can := 0      # wFirstLockTrashCanIndex (WRAM: rolled when the city loads)
var second_lock_can := 0     # wSecondLockTrashCanIndex
var gym_door_dirty := false  # the gym's wCurrentMapScriptFlags BIT_CUR_MAP_LOADED_2

const GOT_OLD_ROD := "GOT_OLD_ROD"   # wStatusFlags1 BIT_GOT_OLD_ROD, kept with the events
## GymTrashCans: [mask for the random number, the four cans that may hold the second lock]
const GYM_TRASH_CANS := [
	[2, 1, 3, 0, 0], [3, 0, 2, 4, 0], [2, 1, 5, 0, 0], [3, 0, 4, 6, 0], [4, 1, 3, 5, 7],
	[3, 2, 4, 8, 0], [3, 3, 7, 9, 0], [4, 4, 6, 8, 10], [3, 5, 7, 11, 0], [3, 6, 10, 12, 0],
	[4, 7, 9, 11, 13], [3, 8, 10, 14, 0], [2, 9, 13, 0, 0], [3, 10, 12, 14, 0], [2, 11, 13, 0, 0],
]
const WATER_TILE := 0x14


func _init(c: Chapter5Scripts) -> void:
	chapter = c
	ms = c.ms
	ow = c.ow
	state = c.state


func run_map_script(entered: bool) -> bool:
	match ow.map_id:
		"VERMILION_CITY":
			if entered:
				# VermilionCityLeftSSAnneCallbackScript (BIT_CUR_MAP_LOADED_2)
				if state.has_event("EVENT_SS_ANNE_LEFT") and not state.has_event("EVENT_WALKED_PAST_GUARD_AFTER_SS_ANNE_LEFT"):
					state.set_event("EVENT_WALKED_PAST_GUARD_AFTER_SS_ANNE_LEFT")
					ms._set_script(2)
				# .setFirstLockTrashCanIndex (BIT_CUR_MAP_LOADED_1): Random & $e
				first_lock_can = ow.rng.randi_range(0, 255) & 0xE
			await _city()
			return true
		"VERMILION_DOCK":
			await _dock()
			return true
		"VERMILION_GYM":
			if entered:
				Text.ram["wGymCityName"] = "갈색시티" if GameData.lang == "ko" else "VERMILION CITY"
				Text.ram["wGymLeaderName"] = "마티스" if GameData.lang == "ko" else "LT.SURGE"
				gym_door_dirty = true
			if gym_door_dirty:
				gym_door_dirty = false
				_set_gym_door_tile()
			await _gym()
			return true
	return false


func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		# Vermilion City
		"TEXT_VERMILIONCITY_BEAUTY", "TEXT_VERMILIONCITY_GAMBLER1":
			await ow.print_text("_VermilionCityGambler1SSAnneDepartedText" if state.has_event("EVENT_SS_ANNE_LEFT") else "_VermilionCityGambler1DidYouSeeText")
		"TEXT_VERMILIONCITY_SAILOR1": await _sailor1()
		"TEXT_VERMILIONCITY_MACHOP":
			Sound.play_cry("MACHOP")
			await Sound.wait_for_sfx()
			await ow.print_text("_VermilionCityMachopStompingTheLandFlatText")
		"TEXT_VERMILIONCITY_MART_SIGN": await ms._far("_MartSignText")
		"TEXT_VERMILIONCITY_POKECENTER_SIGN": await ms._far("_PokeCenterSignText")
		# Pokémon Center, mart, trade house, Pidgey house
		"TEXT_VERMILIONPOKECENTER_NURSE": await Pokecenter.nurse(ow, npc_index)
		"TEXT_VERMILIONPOKECENTER_LINK_RECEPTIONIST": await ow.print_text("_CableClubNPCWelcomeText")
		"TEXT_VERMILIONMART_CLERK": await Pokemart.dialogue(ow, "VERMILION_MART")
		"TEXT_VERMILIONTRADEHOUSE_LITTLE_GIRL": await InGameTrade.dialogue(ow, state, InGameTrade.TRADE_FOR_DUX)
		"TEXT_VERMILIONPIDGEYHOUSE_PIDGEY":
			# the cry alone (the text box stays empty)
			Sound.play_cry("PIDGEY")
			await Sound.wait_for_sfx()
		"TEXT_VERMILIONOLDRODHOUSE_FISHING_GURU": await _old_rod()
		# Pokémon Fan Club
		"TEXT_POKEMONFANCLUB_PIKACHU_FAN": await _fan("PIKACHU_FAN", "SEEL_FAN", "_PokemonFanClubPikachuFan")
		"TEXT_POKEMONFANCLUB_SEEL_FAN": await _fan("SEEL_FAN", "PIKACHU_FAN", "_PokemonFanClubSeelFan")
		"TEXT_POKEMONFANCLUB_PIKACHU", "TEXT_POKEMONFANCLUB_SEEL":
			var species := "PIKACHU" if text_id.ends_with("PIKACHU") else "SEEL"
			await ow.print_text("_PokemonFanClub%sText" % species.capitalize())
			Sound.play_cry(species)
			await Sound.wait_for_sfx()
		"TEXT_POKEMONFANCLUB_CHAIRMAN": await _chairman()
		# Vermilion Gym
		"TEXT_VERMILIONGYM_LT_SURGE": await _surge_text(npc_index)
		"TEXT_VERMILIONGYM_LT_SURGE_THUNDER_BADGE_INFO": await ms._far("_VermilionGymLTSurgeThunderBadgeInfoText")
		"TEXT_VERMILIONGYM_LT_SURGE_RECEIVED_TM24":
			await ms._far("_VermilionGymLTSurgeReceivedTM24Text")
			await Sound.text_sound("sound_get_key_item")
			await ms._far("_TM24ExplanationText")
		"TEXT_VERMILIONGYM_LT_SURGE_TM24_NO_ROOM": await ms._far("_VermilionGymLTSurgeTM24NoRoomText")
		"TEXT_VERMILIONGYM_GYM_GUIDE":
			await ow.print_text("_VermilionGymGymGuideBeatLTSurgeText" if state.beat_gym_flags & 4 else "_VermilionGymGymGuideChampInMakingText")
		_:
			return false
	return true


# --- Vermilion City -------------------------------------------------------------------

## VermilionCity_ScriptPointers.
func _city() -> void:
	match ms._script_index():
		0:
			# VermilionCityDefaultScript: facing down on the tile above the dock sailor
			if ow.player.facing != Overworld.FACE_DOWN or ow.player.x != 18 or ow.player.y != 30:
				return
			await ow.display_text_id("TEXT_VERMILIONCITY_SAILOR1", 2)
			if not state.has_event("EVENT_SS_ANNE_LEFT") and state.item_count("S_S_TICKET") > 0:
				return
			ow.simulate([GB.UP])
			ms._set_script(1)
		1:
			# VermilionCityPlayerMovingUp1Script
			if not ow.sim_queue.is_empty():
				return
			await GB.frames(10)
			ms._set_script(0)
		2:
			# VermilionCityPlayerExitShipScript: two steps up past the sailor
			ow.simulate([GB.UP, GB.UP])
			ms._set_script(3)
		3:
			# VermilionCityPlayerMovingUp2Script
			if not ow.sim_queue.is_empty():
				return
			ow.joy_ignore = 0
			ms._set_script(0)
		4:
			# VermilionCityPlayerAllowedToPassScript
			if ow.player.x == 18 and ow.player.y == 30:
				return
			ms._set_script(0)


## VermilionCitySailor1Text.
func _sailor1() -> void:
	if state.has_event("EVENT_SS_ANNE_LEFT"):
		await ow.print_text("_VermilionCitySailor1ShipSetSailText")
		return
	var pos := Vector2i(ow.player.x, ow.player.y)
	if ow.player.facing == Overworld.FACE_RIGHT or pos in [Vector2i(19, 29), Vector2i(19, 31)]:
		await ow.print_text("_VermilionCitySailor1WelcomeToSSAnneText")
		return
	await ow.print_text("_VermilionCitySailor1DoYouHaveATicketText")
	if state.item_count("S_S_TICKET") == 0:
		await ow.print_text("_VermilionCitySailor1YouNeedATicketText")
		return
	await ow.print_text("_VermilionCitySailor1FlashedTicketText")
	ms._set_script(4)   # SCRIPT_VERMILIONCITY_PLAYER_ALLOWED_TO_PASS
	chapter.trace("SS_ANNE_TICKET_OK")


# --- Vermilion Dock -------------------------------------------------------------------

## VermilionDock_Script.
func _dock() -> void:
	if state.has_event("EVENT_STARTED_WALKING_OUT_OF_DOCK"):
		if state.has_event("EVENT_WALKED_OUT_OF_DOCK") or not ow.sim_queue.is_empty():
			return
		ow.joy_ignore = 0
		state.set_event("EVENT_WALKED_OUT_OF_DOCK")
		return
	if not state.has_event("EVENT_GOT_HM01") or ow.dest_warp_id != 1:
		return
	if not state.has_event("EVENT_SS_ANNE_LEFT"):
		await _ss_anne_leaves()
		return
	state.set_event("EVENT_STARTED_WALKING_OUT_OF_DOCK")
	await GB.delay3()
	ow.simulate([GB.UP, GB.UP, GB.UP])
	ow.joy_ignore = 0xFF


## VermilionDockSSAnneLeavesScript: the ship (BG rows 10-15) scrolls off to the left
## 128 pixels in 8 column steps while the smoke puff at its funnel drifts right; the
## newly uncovered columns are water (ScheduleEastColumnRedraw from the water-filled
## wTileMap rows), then the ship's rows become water for good and the ship's warp is gone.
func _ss_anne_leaves() -> void:
	var S: GBScreen = GB.screen
	state.set_event("EVENT_SS_ANNE_LEFT")
	ow.joy_ignore = 0xFF
	Sound.stop_all_music()
	Sound.play_music("MUSIC_SURFING")
	chapter.trace("SS_ANNE_LEAVES")
	# LoadSmokeTileFourTimes: OAM tiles $fc-$ff are the smoke tile; the player stands still
	var smoke: int = S.tile("boulder_smoke", 0)
	await GB.frames(120)
	# CopyScreenTileBufferToVRAM (vBGMap1), the water fill of wTileMap rows 10-15 and its
	# transfer: three frames
	await GB.delay3()
	var drift := 0
	S.obp1 = GBScreen.pal_byte(0x00)   # rOBP1 = 0: the smoke is white
	var smoke_x := 88                  # wSSAnneSmokeX (OAM coordinates)
	var puff_x := 0
	await Sound.play_sfx_wait_for_current("SFX_SS_ANNE_HORN")
	ow.update_sprites = false          # wUpdateSpritesEnabled = $ff
	var d := 0
	for e in 8:
		# .shift_columns_up: VermilionDock_EmitSmokePuff (always OAM block 1 = sprites 4-7)
		smoke_x = (smoke_x - 16) & 0xFF
		drift += 1
		puff_x = smoke_x
		_draw_puff(S, puff_x, smoke)
		for b in 16:
			# VermilionDock_AnimSmokePuffDriftRight: the puff moves two pixels right
			puff_x = (puff_x + 2) & 0xFF
			_draw_puff(S, puff_x, smoke)
			for c in 8:
				_render_ship_rows(S, d)   # VermilionDock_SyncScrollWithLY
				await GB.frame
			d += 1
	# rWY/hWY = 0: the window shows the screen copy (the ship's rows water) while
	# VermilionDock_EraseSSAnne fills BG map 0; then the horn, 120 frames, hWY = $90
	S.row_scx = PackedInt32Array()
	_erase_ss_anne()
	ow._render()
	Sound.play_sfx("SFX_SS_ANNE_HORN")
	await GB.frames(120)
	ow.update_sprites = true
	for k in 4:
		S.set_sprite(4 + k, -16, -16, GBScreen.BLANK)
	# dec [wNumberOfWarps]: the gangway warp onto the ship is gone until the map reloads
	ow.map = ow.map.duplicate()
	ow.map["warps"] = ow.map["warps"].slice(0, ow.map["warps"].size() - 1)


## WriteOAMBlock 1 with VermilionDockOAMBlock: four smoke tiles at OAM (x, 100), OBP1.
func _draw_puff(S: GBScreen, x: int, smoke: int) -> void:
	var sx := x - 8
	var sy := 100 - 16
	S.set_sprite(4, sx, sy, smoke, 1)
	S.set_sprite(5, sx + 8, sy, smoke, 1)
	S.set_sprite(6, sx, sy + 8, smoke, 1)
	S.set_sprite(7, sx + 8, sy + 8, smoke, 1)


## One frame of the departure: the map view, then screen rows 10-15 shifted left by `d`
## pixels (SCX = d between LY 80 and 128) with water in the columns the shift uncovers.
func _render_ship_rows(S: GBScreen, d: int) -> void:
	ow._render()
	var k := d >> 3
	var tx0 := (ow.player.px - 64) >> 3
	var ty0 := (ow.player.py - 64) >> 3
	var water: int = ow._tile_value(WATER_TILE)
	for j in range(10, 16):
		var gy := ty0 + j
		for i in 21:
			var c := i + k
			var v: int = water
			if c < 20:
				var gx := tx0 + c
				v = GBScreen.BLANK
				if gx >= 0 and gy >= 0 and gx < ow.grid_w and gy < ow.grid_h:
					v = ow._tile_value(ow.grid_ids[gy * ow.grid_w + gx])
			S.bg[(j & 31) * GBScreen.MAP_W + (i & 31)] = v
	var rows := PackedInt32Array()
	rows.resize(18)
	for j in 18:
		rows[j] = (d & 7) if (j >= 10 and j <= 15) else 0
	S.row_scx = rows


## VermilionDock_EraseSSAnne: the ship's rows of the map view become water.
func _erase_ss_anne() -> void:
	var ty0 := (ow.player.py - 64) >> 3
	for j in range(10, 16):
		var gy := ty0 + j
		if gy < 0 or gy >= ow.grid_h:
			continue
		for gx in ow.grid_w:
			ow.grid_ids[gy * ow.grid_w + gx] = WATER_TILE


# --- Vermilion Gym --------------------------------------------------------------------

## VermilionGymSetDoorTile: the double door at block (2, 2) until the second lock opens.
func _set_gym_door_tile() -> void:
	var block := 0x24   # double door
	if state.has_event("EVENT_2ND_LOCK_OPENED"):
		Sound.play_sfx("SFX_GO_INSIDE")
		block = 0x05    # clear floor
	ow.cut_blocks[Vector2i(2, 2)] = block
	ow._put_block(2, 2, block, ow.tileset)


## VermilionGym_ScriptPointers.
func _gym() -> void:
	match ms._script_index():
		0: await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()
		3:
			# VermilionGymLTSurgeAfterBattleScript
			if not ow.last_battle_won:
				_gym_reset_scripts()
				return
			ow.joy_ignore = GB.CTRL_PAD
			await _surge_receive_tm24()
			_gym_reset_scripts()


## VermilionGymResetScripts.
func _gym_reset_scripts() -> void:
	ow.joy_ignore = 0
	ms._set_script(0)


## VermilionGymLTSurgeReceiveTM24Script (+ .gym_victory).
func _surge_receive_tm24() -> void:
	await ow.display_text_id("TEXT_VERMILIONGYM_LT_SURGE_THUNDER_BADGE_INFO", -1)
	state.set_event("EVENT_BEAT_LT_SURGE")
	if state.give_item("TM24", 1):
		await ow.display_text_id("TEXT_VERMILIONGYM_LT_SURGE_RECEIVED_TM24", -1)
		state.set_event("EVENT_GOT_TM24")
	else:
		await ow.display_text_id("TEXT_VERMILIONGYM_LT_SURGE_TM24_NO_ROOM", -1)
	state.badges |= 4          # BIT_THUNDERBADGE
	state.beat_gym_flags |= 4
	for i in 3:                # deactivate the gym trainers
		state.set_event("EVENT_BEAT_VERMILION_GYM_TRAINER_%d" % i)
	chapter.trace("SURGE_VICTORY badges=%d tm24=%d" % [state.badges, state.item_count("TM24")])


## VermilionGymLTSurgeText.
func _surge_text(npc_index: int) -> void:
	if state.has_event("EVENT_BEAT_LT_SURGE"):
		if state.has_event("EVENT_GOT_TM24"):
			await ow.print_text("_VermilionGymLTSurgePostBattleAdviceText")
		else:
			# the TM didn't fit in the bag last time
			await _surge_receive_tm24()
			_gym_reset_scripts()
			ow.do_not_wait_after_text = true   # DisableWaitingAfterTextDisplay
		return
	await ow.print_text("_VermilionGymLTSurgePreBattleText")
	chapter.event_battle(npc_index, 3, "VermilionGymLTSurgeReceivedThunderBadgeText", "", 3)


## GymTrashScript (hidden event `can` = wGymTrashCanIndex).
func gym_trash(can: int) -> void:
	if state.has_event("EVENT_2ND_LOCK_OPENED"):
		await _trash_text("_VermilionGymTrashText", "")
		return
	if not state.has_event("EVENT_1ST_LOCK_OPENED"):
		if can != first_lock_can:
			await _trash_text("_VermilionGymTrashText", "")
			return
		# .openFirstLock: the next can is one of the entry's candidates, picked with the
		# random number's high nibble masked; the original bug makes it can 0 when the
		# mask and the number share no bit (the index -1 reads a zero padding byte)
		state.set_event("EVENT_1ST_LOCK_OPENED")
		var entry: Array = GYM_TRASH_CANS[can]
		var r := ow.rng.randi_range(0, 255)
		r = ((r << 4) | (r >> 4)) & 0xFF
		var v := (int(entry[0]) & r) - 1
		second_lock_can = (int(entry[1 + v]) & 0xF) if v >= 0 else 0
		chapter.trace("GYM_TRASH first=%d second=%d" % [can, second_lock_can])
		await _trash_text("_VermilionGymTrashSuccessText1", "SFX_SWITCH")
		return
	if can == second_lock_can:
		# .openSecondLock
		state.set_event("EVENT_2ND_LOCK_OPENED")
		gym_door_dirty = true
		chapter.trace("GYM_TRASH opened")
		await _trash_text("_VermilionGymTrashSuccessText3", "SFX_GO_INSIDE")
		return
	# the cans are reset
	state.events.erase("EVENT_1ST_LOCK_OPENED")
	first_lock_can = ow.rng.randi_range(0, 255) & 0xE
	chapter.trace("GYM_TRASH reset first=%d" % first_lock_can)
	await _trash_text("_VermilionGymTrashFailText", "SFX_DENIED")


## PrintPredefTextID of a trash can text, with the sound the text_asm plays after it.
func _trash_text(label: String, sfx: String) -> void:
	ow.in_text = true
	Menu.message_box()
	await GB.delay3()
	await Text.print_text_no_box(label)
	if sfx != "":
		await Sound.wait_for_sfx()
		Sound.play_sfx(sfx)
		await Sound.wait_for_sfx()
	await Text.wait_scroll_button(false)
	await Text.hold_text_display_open()
	ow.in_text = false
	ow._render()


# --- Pokémon Fan Club, old rod house --------------------------------------------------

## PokemonFanClubPikachuFanText / SeelFanText: the fans boast in turns.
func _fan(mine: String, other: String, prefix: String) -> void:
	if state.has_event("EVENT_%s_BOAST" % mine):
		await ow.print_text(prefix + "BetterText")
		state.events.erase("EVENT_%s_BOAST" % mine)
	else:
		await ow.print_text(prefix + "NormalText")
		state.set_event("EVENT_%s_BOAST" % other)


## PokemonFanClubChairmanText.
func _chairman() -> void:
	# PokemonFanClub_CheckBikeInBag
	if state.has_event("EVENT_GOT_BIKE_VOUCHER") or state.item_count("BICYCLE") > 0 or state.item_count("BIKE_VOUCHER") > 0:
		await ow.print_text("_PokemonFanClubChairFinalText")
		return
	await ow.print_text("_PokemonFanClubChairmanIntroText")
	if not await Menu.yes_no():
		await ow.print_text("_PokemonFanClubNoStoryText")
		return
	await ow.print_text("_PokemonFanClubChairmanStoryText")
	if state.give_item("BIKE_VOUCHER", 1):
		Text.ram["wStringBuffer"] = GameData.item_name("BIKE_VOUCHER")
		await ow.print_text("_PokemonFanClubReceivedBikeVoucherText")
		await Sound.text_sound("sound_get_key_item")
		await ow.print_text("_PokemonFanClubExplainBikeVoucherText")
		state.set_event("EVENT_GOT_BIKE_VOUCHER")
		chapter.trace("BIKE_VOUCHER_RECEIVED")
	else:
		await ow.print_text("_PokemonFanClubBagFullText")


## VermilionOldRodHouseFishingGuruText.
func _old_rod() -> void:
	if state.has_event(GOT_OLD_ROD):
		await ow.print_text("_VermilionOldRodHouseFishingGuruHowAreTheFishBitingText")
		return
	await ow.print_text("_VermilionOldRodHouseFishingGuruDoYouLikeToFishText")
	if not await Menu.yes_no():
		await ow.print_text("_VermilionOldRodHouseFishingGuruThatsSoDisappointingText")
		return
	if not state.give_item("OLD_ROD", 1):
		await ow.print_text("_VermilionOldRodHouseFishingGuruNoRoomText")
		return
	state.set_event(GOT_OLD_ROD)
	Text.ram["wStringBuffer"] = GameData.item_name("OLD_ROD")
	await ow.print_text("_VermilionOldRodHouseFishingGuruTakeThisText")
	await Sound.text_sound("sound_get_item_1")
	await ow.print_text("_VermilionOldRodHouseFishingGuruFishingIsAWayOfLifeText")
	chapter.trace("OLD_ROD_RECEIVED")

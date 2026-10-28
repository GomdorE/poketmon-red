## Chapter 6 map scripts and text handlers: Route 11 and its gate (scripts/Route11.asm,
## Route11Gate1F.asm, Route11Gate2F.asm), Diglett's Cave (DiglettsCaveRoute11.asm,
## DiglettsCave.asm, DiglettsCaveRoute2.asm), the east end of Route 2 (Route2TradeHouse.asm,
## Route2Gate.asm), Rock Tunnel (trainers only; the darkness is in Overworld) and Lavender
## Town (LavenderTown.asm, LavenderMart.asm, LavenderCuboneHouse.asm, MrFujisHouse.asm,
## NameRatersHouse.asm, PokemonTower1F.asm, PokemonTower2F.asm).
## Maps with only trainer headers need no code here (TrainerEngine handles them).
class_name Chapter6Scripts
extends RefCounted

var ms: MapScripts
var ow: Overworld
var state: GameState
var entered_map := ""


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state


## The per-frame map script (see MtMoonScripts.run_map_script for the contract).
func run_map_script() -> bool:
	var _entered := entered_map != ow.map_id
	entered_map = ow.map_id
	match ow.map_id:
		"ROUTE_11_GATE_2F":
			ow.no_auto_text_box = true   # DisableAutoTextBoxDrawing
			return true
		"DIGLETTS_CAVE_ROUTE_11":
			state.last_map = "ROUTE_11"   # the LAST_MAP warps lead back to Route 11
			return true
		"DIGLETTS_CAVE_ROUTE_2":
			state.last_map = "ROUTE_2"
			return true
		"POKEMON_TOWER_2F":
			await _tower_2f()
			return true
		_:
			return false


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		# Route 11 gate, Route 2 east
		"TEXT_ROUTE11GATE2F_YOUNGSTER": await InGameTrade.dialogue(ow, state, InGameTrade.TRADE_FOR_TERRY)
		"TEXT_ROUTE11GATE2F_OAKS_AIDE":
			await _oaks_aide(30, "ITEMFINDER", "EVENT_GOT_ITEMFINDER", "_Route11Gate2FOaksAideItemfinderDescriptionText")
		"TEXT_ROUTE11GATE2F_LEFT_BINOCULARS":
			await _print_if_facing_up("_Route11Gate2FLeftBinocularsNoSnorlaxText" if state.has_event("EVENT_BEAT_ROUTE12_SNORLAX") else "_Route11Gate2FLeftBinocularsSnorlaxText")
		"TEXT_ROUTE11GATE2F_RIGHT_BINOCULARS": await _print_if_facing_up("_Route11Gate2FRightBinocularsText")
		"TEXT_ROUTE2TRADEHOUSE_GAMEBOY_KID": await InGameTrade.dialogue(ow, state, InGameTrade.TRADE_FOR_MARCEL)
		"TEXT_ROUTE2GATE_OAKS_AIDE":
			await _oaks_aide(10, "HM05", "EVENT_GOT_HM05", "_Route2GateOaksAideFlashExplanationText")
		# Lavender Town
		"TEXT_LAVENDERTOWN_LITTLE_GIRL":
			await ow.print_text("_LavenderTownLittleGirlDoYouBelieveInGhostsText")
			await ow.print_text("_LavenderTownLittleGirlSoThereAreBelieversText" if await Menu.yes_no() else "_LavenderTownLittleGirlHaHaGuessNotText")
		"TEXT_LAVENDERTOWN_MART_SIGN": await ms._far("_MartSignText")
		"TEXT_LAVENDERTOWN_POKECENTER_SIGN": await ms._far("_PokeCenterSignText")
		"TEXT_LAVENDERPOKECENTER_NURSE": await Pokecenter.nurse(ow, npc_index)
		"TEXT_LAVENDERPOKECENTER_LINK_RECEPTIONIST": await ow.print_text("_CableClubNPCWelcomeText")
		"TEXT_LAVENDERMART_CLERK": await Pokemart.dialogue(ow, "LAVENDER_MART")
		"TEXT_LAVENDERMART_COOLTRAINER_M":
			await ow.print_text("_LavenderMartCooltrainerMNuggetText" if state.has_event("EVENT_RESCUED_MR_FUJI") else "_LavenderMartCooltrainerMReviveText")
		"TEXT_LAVENDERCUBONEHOUSE_CUBONE": Sound.play_cry("CUBONE")
		"TEXT_LAVENDERCUBONEHOUSE_BRUNETTE_GIRL":
			await ow.print_text("_LavenderCuboneHouseBrunetteGirlGhostIsGoneText" if state.has_event("EVENT_RESCUED_MR_FUJI") else "_LavenderCuboneHouseBrunetteGirlPoorCubonesMotherText")
		"TEXT_MRFUJISHOUSE_SUPER_NERD":
			await ow.print_text("_MrFujisHouseSuperNerdMrFujiHadBeenPrayingText" if state.has_event("EVENT_RESCUED_MR_FUJI") else "_MrFujisHouseSuperNerdMrFujiIsntHereText")
		"TEXT_MRFUJISHOUSE_LITTLE_GIRL":
			await ow.print_text("_MrFujisHouseLittleGirlPokemonAreNiceToHugText" if state.has_event("EVENT_RESCUED_MR_FUJI") else "_MrFujisHouseLittleGirlThisIsMrFujisHouseText")
		"TEXT_MRFUJISHOUSE_PSYDUCK": Sound.play_cry("PSYDUCK")
		"TEXT_MRFUJISHOUSE_NIDORINO": Sound.play_cry("NIDORINO")
		"TEXT_MRFUJISHOUSE_MR_FUJI": await _mr_fuji()
		"TEXT_NAMERATERSHOUSE_NAME_RATER": await _name_rater()
		"TEXT_POKEMONTOWER2F_RIVAL": await _tower_rival_text()
		_:
			return false
	return true


## GateUpstairsScript_PrintIfFacingUp: the text only when facing up, otherwise nothing
## (and no button wait).
func _print_if_facing_up(label: String) -> void:
	if ow.player.facing == Overworld.FACE_UP:
		await ow.print_text(label)
	else:
		ow.do_not_wait_after_text = true


## OaksAideScript (engine/events/oaks_aide.asm): the aide's item for `requirement` kinds of
## Pokémon owned; the description text follows when the item is (or already was) received.
func _oaks_aide(requirement: int, item: String, event: String, description: String) -> void:
	if not state.has_event(event):
		Text.ram["hOaksAideRequirement"] = str(requirement)
		Text.ram["wOaksAideRewardItemName"] = GameData.item_name(item)
		await ow.print_text("_OaksAideHiText")
		if not await Menu.yes_no():
			await ow.print_text("_OaksAideComeBackText")
			trace("OAKS_AIDE refused %s" % item)
			return
		var owned := 0
		for sp in state.pokedex_owned:
			if state.pokedex_owned[sp]:
				owned += 1
		Text.ram["hOaksAideNumMonsOwned"] = str(owned)
		if owned < requirement:
			await ow.print_text("_OaksAideUhOhText")
			trace("OAKS_AIDE not_enough %s owned=%d" % [item, owned])
			return
		await ow.print_text("_OaksAideHereYouGoText")
		if not state.give_item(item, 1):
			await ow.print_text("_OaksAideNoRoomText")
			trace("OAKS_AIDE bag_full %s" % item)
			return
		await ow.print_text("_OaksAideGotItemText")
		await Sound.text_sound("sound_get_item_1")
		state.set_event(event)
		trace("OAKS_AIDE got %s owned=%d" % [item, owned])
	await ow.print_text(description)


# --- Lavender Town ---------------------------------------------------------------------

## MrFujisHouseMrFujiText: the Poké Flute (Mr. Fuji is only home once rescued).
func _mr_fuji() -> void:
	if state.has_event("EVENT_GOT_POKE_FLUTE"):
		await ow.print_text("_MrFujisHouseMrFujiHasMyFluteHelpedYouText")
		return
	await ow.print_text("_MrFujisHouseMrFujiIThinkThisMayHelpYourQuestText")
	if not state.give_item("POKE_FLUTE", 1):
		await ow.print_text("_MrFujisHouseMrFujiPokeFluteNoRoomText")
		return
	Text.ram["wStringBuffer"] = GameData.item_name("POKE_FLUTE")
	await ow.print_text("_MrFujisHouseMrFujiReceivedPokeFluteText")
	await Sound.text_sound("sound_get_key_item")
	await ow.print_text("_MrFujisHouseMrFujiPokeFluteExplanationText")
	state.set_event("EVENT_GOT_POKE_FLUTE")
	trace("POKE_FLUTE_RECEIVED")


## NameRatersHouseNameRaterText: rename one of the player's own Pokémon.
func _name_rater() -> void:
	var saved: PackedInt32Array = GB.screen.snapshot_bg()   # SaveScreenTilesToBuffer2
	await ow.print_text("_NameRatersHouseNameRaterWantMeToRateText")
	if not await Menu.yes_no():
		await _come_any_time()
		return
	await ow.print_text("_NameRatersHouseNameRaterWhichPokemonText")
	ow.update_sprites = false
	var idx := await PartyMenu.show(state, "normal")
	await InGameTrade._restore_screen(ow, saved)
	if idx < 0:
		await _come_any_time()
		return
	var m: PartyMon = state.party[idx]
	Text.ram["wNameBuffer"] = m.nickname
	# NameRatersHouseCheckMonOTScript: only the player's own Pokémon
	if m.ot_name != "" or m.ot_id >= 0:
		trace("NAME_RATER not_mine")
		await ow.print_text("_NameRatersHouseNameRaterATrulyImpeccableNameText")
		return
	await ow.print_text("_NameRatersHouseNameRaterGiveItANiceNameText")
	if not await Menu.yes_no():
		await _come_any_time()
		return
	await ow.print_text("_NameRatersHouseNameRaterWhatShouldWeNameItText")
	# DisplayNameRaterScreen
	ow.update_sprites = false
	var name: String = await NamingScreen.new().run(NamingScreen.Kind.MON, m.species)
	await InGameTrade._restore_screen(ow, saved)
	if name == "":
		await _come_any_time()
		return
	m.nickname = name
	trace("NAME_RATER renamed %s" % name)
	await ow.print_text("_NameRatersHouseNameRaterPokemonHasBeenRenamedText")


func _come_any_time() -> void:
	trace("NAME_RATER cancel")
	await ow.print_text("_NameRatersHouseNameRaterComeAnyTimeYouLikeText")


# --- Pokémon Tower 2F: the rival --------------------------------------------------------

## PokemonTower2F_ScriptPointers.
func _tower_2f() -> void:
	match ms._script_index():
		0:
			# PokemonTower2FDefaultScript (the coordinate list's end byte is $0F, not $FF:
			# the two real entries are kept, the code bytes after them never match)
			if state.has_event("EVENT_BEAT_POKEMON_TOWER_RIVAL"):
				return
			var pos := Vector2i(ow.player.x, ow.player.y)
			if not pos in [Vector2i(15, 5), Vector2i(14, 6)]:
				return
			Sound.stop_all_music()
			Sound.play_music("MUSIC_MEET_RIVAL")
			state.events.erase("EVENT_POKEMON_TOWER_RIVAL_ON_LEFT")
			if pos == Vector2i(15, 5):
				# the rival is on the left side and the player is on the right side
				state.set_event("EVENT_POKEMON_TOWER_RIVAL_ON_LEFT")
				ow.player.facing = Overworld.FACE_LEFT
				ow.set_npc_facing(0, Overworld.FACE_RIGHT)
			else:
				ow.player.facing = Overworld.FACE_UP
				ow.set_npc_facing(0, Overworld.FACE_DOWN)
			await GB.delay3()
			await ow.display_text_id("TEXT_POKEMONTOWER2F_RIVAL", 0)
		1:
			# PokemonTower2FDefeatedRivalScript
			if not ow.last_battle_won:
				_tower_reset()
				return
			ow.joy_ignore = GB.CTRL_PAD
			state.set_event("EVENT_BEAT_POKEMON_TOWER_RIVAL")
			await ow.display_text_id("TEXT_POKEMONTOWER2F_RIVAL", 0)
			var moves: Array
			if state.has_event("EVENT_POKEMON_TOWER_RIVAL_ON_LEFT"):
				moves = [Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT,
					Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_DOWN, Overworld.NPC_DOWN]
			else:
				moves = [Overworld.NPC_RIGHT, Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_RIGHT,
					Overworld.NPC_DOWN, Overworld.NPC_DOWN, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT]
			ow.move_sprite(0, moves)
			Sound.stop_all_music()
			Sound.rival_alternate_start()
			ms._set_script(2)
		2:
			# PokemonTower2FRivalExitsScript
			if ow.npc_moving(0):
				return
			ow.hide_object(0)   # TOGGLE_POKEMON_TOWER_2F_RIVAL
			ow.joy_ignore = 0
			await Sound.play_default_music()
			ms._set_script(0)
			trace("TOWER_RIVAL_DONE")


## PokemonTower2FResetRivalEncounter.
func _tower_reset() -> void:
	ow.joy_ignore = 0
	ms._set_script(0)


## PokemonTower2FRivalText.
func _tower_rival_text() -> void:
	if state.has_event("EVENT_BEAT_POKEMON_TOWER_RIVAL"):
		await ow.print_text("_PokemonTower2FRivalHowsYourDexText")
		return
	await ow.print_text("_PokemonTower2FRivalWhatBringsYouHereText")
	var team: int = {"SQUIRTLE": 4, "BULBASAUR": 5, "CHARMANDER": 6}.get(state.rival_starter, 6)
	ow.battle_request = {"trainer": "RIVAL2", "team": team, "name": state.rival_name,
		"win_text": "_PokemonTower2FRivalDefeatedText", "lose_text": "_PokemonTower2FRivalVictoryText"}
	ms._set_script(1)


func trace(message: String) -> void:
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("CHAPTER6 %s frame=%d" % [message, GB.frame_count])

## Pokémon Center nurse dialogue and the healing machine animation
## (engine/events/pokecenter.asm, engine/overworld/healing_machine.asm).
class_name Pokecenter
extends RefCounted


## DisplayPokemonCenterDialogue_. `nurse` is the nurse's NPC index.
static func nurse(ow: Overworld, nurse_index: int) -> void:
	var S: GBScreen = GB.screen
	var state: GameState = ow.state
	var saved := S.snapshot_bg()
	await Text.print_text("_PokemonCenterWelcomeText")
	if not state.has_event("USED_POKECENTER"):
		state.set_event("USED_POKECENTER")
		await Text.run_commands([["text_pause", ""]])
		await Text.run_commands(GameData.text("_ShallWeHealYourPokemonText"))
	# YesNoChoicePokeCenter: HEAL/CANCEL box at (11, 6)
	var yes := await Menu.yes_no(11, 6, true)
	if yes:
		S.restore_bg(saved)
		await Text.print_text("_NeedYourPokemonText")
		ow.set_npc_facing(nurse_index, Overworld.FACE_UP)
		ow.npcs[nurse_index].keep_facing = true
		ow.reload_map_view()
		await GB.delay3()
		Battle.heal_party(state)
		state.last_blackout_map = state.last_map   # SetLastBlackoutMap
		await _animate_healing_machine(S, state.party.size())
		Sound.restart_map_music()
		await Text.print_text("_PokemonFightingFitText")
		ow.set_npc_facing(nurse_index, Overworld.FACE_DOWN)
		ow.reload_map_view()
		await GB.frames(20)
	else:
		S.restore_bg(saved)
	await Text.run_commands([["text_pause", ""]])
	await Text.run_commands(GameData.text("_PokemonCenterFarewellText"))


## AnimateHealingMachine: the monitor sprite, one ball per party member with the
## machine sound, then the "healed" jingle while the balls flash.
static func _animate_healing_machine(S: GBScreen, party_count: int) -> void:
	var saved_obp1 := S.obp1
	S.obp1 = GBScreen.pal_byte(0xE0)
	var base := 33
	# dbsprite x_tile, y_tile, x_off, y_off -> screen x = x_tile*8 + x_off, y = y_tile*8 + y_off
	var oam := [
		[6 * 8 + 4, 4 * 8 + 4, 0, false],
		[6 * 8, 5 * 8 + 3, 1, false], [7 * 8, 5 * 8 + 3, 1, true],
		[6 * 8, 6 * 8, 1, false], [7 * 8, 6 * 8, 1, true],
		[6 * 8, 6 * 8 + 5, 1, false], [7 * 8, 6 * 8 + 5, 1, true],
	]
	var e: Array = oam[0]
	S.set_sprite(base, e[0], e[1], S.tile("heal_machine", e[2]), 1, e[3])
	Sound.fade_out_then(4)
	while Sound.fade_out_control != 0:
		await GB.frame
	for i in party_count:
		var b: Array = oam[1 + i]
		S.set_sprite(base + 1 + i, b[0], b[1], S.tile("heal_machine", b[2]), 1, b[3])
		Sound.play_sfx("SFX_HEALING_MACHINE")
		await GB.frames(30)
	Sound.play_new_sound_in_own_bank("MUSIC_PKMN_HEALED")
	# FlashSprite8Times: OBP1 ^= $28 every 10 frames
	var obp := 0xE0
	for k in 8:
		obp ^= 0x28
		S.obp1 = GBScreen.pal_byte(obp)
		await GB.frames(10)
	while Sound.channel1_is("MUSIC_PKMN_HEALED"):
		await GB.frame
	await GB.frames(32)
	S.obp1 = saved_obp1
	for i in 7:
		S.set_sprite(base + i, -16, -16, GBScreen.BLANK)

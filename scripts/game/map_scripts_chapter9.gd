## Chapter 9 map scripts and text handlers: Saffron City and its buildings
## (scripts/SaffronCity.asm, SaffronPokecenter.asm, SaffronMart.asm, SaffronPidgeyHouse.asm,
## MrPsychicsHouse.asm, CopycatsHouse1F.asm, CopycatsHouse2F.asm), the Fighting Dojo
## (FightingDojo.asm), Sabrina's gym (SaffronGym.asm) and Silph Co. (SilphCoScripts).
class_name Chapter9Scripts
extends RefCounted

const KARATE_MASTER := 0   # FIGHTINGDOJO_KARATE_MASTER

var ms: MapScripts
var ow: Overworld
var state: GameState
var silph: SilphCoScripts
var saved_coord_index := 0   # wSavedCoordIndex: 1 when the Karate Master was met from (4,3)


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state
	silph = SilphCoScripts.new(self)


## The per-frame map script (see MtMoonScripts.run_map_script for the contract).
func run_map_script() -> bool:
	match ow.map_id:
		"SAFFRON_CITY", "SAFFRON_POKECENTER", "SAFFRON_MART", "SAFFRON_PIDGEY_HOUSE", "MR_PSYCHICS_HOUSE", \
				"COPYCATS_HOUSE_1F", "COPYCATS_HOUSE_2F":
			pass   # EnableAutoTextBoxDrawing only
		"FIGHTING_DOJO":
			await _dojo()
		"SAFFRON_GYM":
			await _gym()
		_:
			return await silph.run_map_script()
	return true


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		# Saffron City
		"TEXT_SAFFRONCITY_MART_SIGN": await ms._far("_MartSignText")
		"TEXT_SAFFRONCITY_POKECENTER_SIGN": await ms._far("_PokeCenterSignText")
		"TEXT_SAFFRONPOKECENTER_NURSE": await Pokecenter.nurse(ow, npc_index)
		"TEXT_SAFFRONPOKECENTER_LINK_RECEPTIONIST": await ow.print_text("_CableClubNPCWelcomeText")
		"TEXT_SAFFRONMART_CLERK": await Pokemart.dialogue(ow, "SAFFRON_MART")
		"TEXT_SAFFRONPIDGEYHOUSE_PIDGEY": await _text_and_cry("_SaffronPidgeyHousePidgeyText", "PIDGEY")
		"TEXT_COPYCATSHOUSE1F_CHANSEY": await _text_and_cry("_CopycatsHouse1FChanseyText", "CHANSEY")
		"TEXT_COPYCATSHOUSE2F_COPYCAT": await _copycat()
		"TEXT_COPYCATSHOUSE2F_PC":
			# CopycatsHouse2FPCText: her secrets only facing up
			await ow.print_text("_CopycatsHouse2FPCMySecretsText" if ow.player.facing == Overworld.FACE_UP else "_CopycatsHouse2FPCCantSeeText")
		"TEXT_MRPSYCHICSHOUSE_MR_PSYCHIC": await _mr_psychic()
		# the Fighting Dojo
		"TEXT_FIGHTINGDOJO_KARATE_MASTER": await _karate_master_text(npc_index)
		"TEXT_FIGHTINGDOJO_KARATE_MASTER_I_WILL_GIVE_YOU_A_POKEMON":
			await ow.print_text("_FightingDojoKarateMasterIWillGiveYouAPokemonText")
		"TEXT_FIGHTINGDOJO_HITMONLEE_POKE_BALL": await _dojo_gift("HITMONLEE", 5, "EVENT_GOT_HITMONLEE")
		"TEXT_FIGHTINGDOJO_HITMONCHAN_POKE_BALL": await _dojo_gift("HITMONCHAN", 6, "EVENT_GOT_HITMONCHAN")
		# Sabrina's gym
		"TEXT_SAFFRONGYM_SABRINA": await _sabrina_text(npc_index)
		"TEXT_SAFFRONGYM_GYM_GUIDE":
			await ow.print_text("_SaffronGymGuideBeatSabrinaText" if state.has_event("EVENT_BEAT_SABRINA") else "_SaffronGymGuideChampInMakingText")
		_:
			return await silph.text(text_id, npc_index)
	return true


## EngageMapTrainer / SaveEndBattleTextPointers for non-header event opponents
## (the same as MtMoonScripts.event_battle).
func event_battle(npc_index: int, post: int, win: String, lose: String = "", gym: int = 0) -> void:
	ms.trainers.header = {}
	ms.trainers._engage_map_trainer(npc_index + 1)
	ow.battle_request = {"trainer": ms.trainers.engaged_class, "team": ms.trainers.engaged_set,
		"win_text": win, "lose_text": lose if lose != "" else win}
	if gym > 0:
		ow.battle_request["gym_leader"] = gym
	ms._set_script(post)


## A text followed by the Pokémon's cry (text_asm PlayCry).
func _text_and_cry(label: String, species: String) -> void:
	await ow.print_text(label)
	Sound.play_cry(species)
	await Sound.wait_for_sfx()


# --- Saffron City's houses -------------------------------------------------------------------

## CopycatsHouse2FCopycatText: TM31 (MIMIC) for a POKé DOLL, once; the first text does not
## wait for a button (wDoNotWaitForButtonPressAfterDisplayingText).
func _copycat() -> void:
	if state.has_event("EVENT_GOT_TM31"):
		await ow.print_text("_CopycatsHouse2FCopycatTM31Explanation2Text")
		return
	ow.do_not_wait_after_text = true
	await ow.print_text("_CopycatsHouse2FCopycatDoYouLikePokemonText")
	if state.item_count("POKE_DOLL") == 0:
		return
	await ow.print_text("_CopycatsHouse2FCopycatTM31PreReceiveText")
	if state.give_item("TM31", 1):
		Text.ram["wStringBuffer"] = GameData.item_name("TM31")
		await ow.print_text("_CopycatsHouse2FCopycatReceivedTM31Text")
		await Sound.text_sound("sound_get_item_1")
		await ow.print_text("_CopycatsHouse2FCopycatTM31Explanation1Text")
		await Text.wait_scroll_button()   # text_waitbutton
		state.remove_item("POKE_DOLL", 1)   # RemoveItemByID
		state.set_event("EVENT_GOT_TM31")
		trace("GOT_TM31 dolls=%d" % state.item_count("POKE_DOLL"))
	else:
		await ow.print_text("_CopycatsHouse2FCopycatTM31NoRoomText")
		await Text.wait_scroll_button()


## MrPsychicsHouseMrPsychicText: TM29 (PSYCHIC) once.
func _mr_psychic() -> void:
	if state.has_event("EVENT_GOT_TM29"):
		await ow.print_text("_MrPsychicsHouseMrPsychicTM29ExplanationText")
		return
	await ow.print_text("_MrPsychicsHouseMrPsychicYouWantedThisText")
	if state.give_item("TM29", 1):
		Text.ram["wStringBuffer"] = GameData.item_name("TM29")
		await ow.print_text("_MrPsychicsHouseMrPsychicReceivedTM29Text")
		await Sound.text_sound("sound_get_item_1")
		state.set_event("EVENT_GOT_TM29")
		trace("GOT_TM29")
	else:
		await ow.print_text("_MrPsychicsHouseMrPsychicTM29NoRoomText")


# --- the Fighting Dojo -----------------------------------------------------------------------

## FightingDojo_Script.
func _dojo() -> void:
	match ms._script_index():
		0: await _dojo_default()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()
		3: await _karate_master_post_battle()


## FightingDojoDefaultScript: while the dojo stands, the trainers' sight; on (4,3) left of
## the Karate Master he turns to the player and speaks (then the battle).
func _dojo_default() -> void:
	if state.has_event("EVENT_DEFEATED_FIGHTING_DOJO"):
		return
	await ms.trainers.check_fighting_map_trainers()
	if ms._script_index() != 0:   # wTrainerHeaderFlagBit: a trainer saw the player
		return
	if state.has_event("EVENT_BEAT_KARATE_MASTER"):
		return
	saved_coord_index = 0
	if ow.player.y != 3 or ow.player.x != 4:
		return
	saved_coord_index = 1
	ow.player.facing = Overworld.FACE_RIGHT
	ow.set_npc_facing(KARATE_MASTER, Overworld.FACE_LEFT)
	await GB.delay3()
	await ow.display_text_id("TEXT_FIGHTINGDOJO_KARATE_MASTER", KARATE_MASTER)


## FightingDojoKarateMasterText.
func _karate_master_text(npc_index: int) -> void:
	if state.has_event("EVENT_DEFEATED_FIGHTING_DOJO"):
		await ow.print_text("_FightingDojoKarateMasterStayAndTrainWithUsText")
		return
	if state.has_event("EVENT_BEAT_KARATE_MASTER"):
		await ow.print_text("_FightingDojoKarateMasterIWillGiveYouAPokemonText")
		return
	await ow.print_text("_FightingDojoKarateMasterText")
	event_battle(npc_index, 3, "_FightingDojoKarateMasterDefeatedText")


## FightingDojoKarateMasterPostBattleScript: the dojo's trainers stand down and the master
## offers a Pokémon.
func _karate_master_post_battle() -> void:
	if not ow.last_battle_won:
		ow.joy_ignore = 0   # FightingDojoResetScripts
		ms._set_script(0)
		return
	if saved_coord_index != 0:
		ow.player.facing = Overworld.FACE_RIGHT
		ow.set_npc_facing(KARATE_MASTER, Overworld.FACE_LEFT)
		await GB.delay3()
	ow.joy_ignore = GB.CTRL_PAD
	state.set_event("EVENT_BEAT_KARATE_MASTER")   # SetEventRange ... EVENT_BEAT_FIGHTING_DOJO_TRAINER_3
	for i in 4:
		state.set_event("EVENT_BEAT_FIGHTING_DOJO_TRAINER_%d" % i)
	await ow.display_text_id("TEXT_FIGHTINGDOJO_KARATE_MASTER_I_WILL_GIVE_YOU_A_POKEMON", -1)
	ow.joy_ignore = 0
	ms._set_script(0)
	trace("KARATE_MASTER_BEATEN")


## FightingDojoHitmonleePokeBallText / FightingDojoHitmonchanPokeBallText: the Pokédex page,
## "take it?", the level 30 Pokémon; the other ball is then refused.
func _dojo_gift(species: String, object_index: int, event: String) -> void:
	if state.has_event("EVENT_GOT_HITMONLEE") or state.has_event("EVENT_GOT_HITMONCHAN"):
		await ow.print_text("_FightingDojoBetterNotGetGreedyText")
		return
	Text.no_delay = true
	await PokedexPage.new().show(species)   # DisplayPokedex, then back to the map
	SGB.run("DEFAULT")
	Text.no_delay = false
	ow.reload_map_view()
	await ow.print_text("_FightingDojo%sPokeBallText" % species.capitalize())
	if not await Menu.yes_no():
		return
	if not await GivePokemon.give(ow, species, 30):
		return
	ow.hide_object(object_index)   # TOGGLE_FIGHTING_DOJO_GIFT_1 / _2
	state.set_event(event)
	state.set_event("EVENT_DEFEATED_FIGHTING_DOJO")
	trace("DOJO_GIFT %s party=%d" % [species, state.party.size()])


# --- Sabrina's gym ---------------------------------------------------------------------------

## SaffronGym_Script (the warp pads are ordinary warps of the FACILITY tileset).
func _gym() -> void:
	match ms._script_index():
		0: await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()
		3:
			# SaffronGymSabrinaPostBattle
			if not ow.last_battle_won:
				_gym_reset_scripts()
				return
			ow.joy_ignore = GB.CTRL_PAD
			await _sabrina_receive_tm46()
			_gym_reset_scripts()


## SaffronGymResetScripts.
func _gym_reset_scripts() -> void:
	ow.joy_ignore = 0
	ms._set_script(0)


## SaffronGymSabrinaReceiveTM46Script (+ .gymVictory): the badge info, TM46 (PSYWAVE), the
## MARSHBADGE and the gym trainers deactivated.
func _sabrina_receive_tm46() -> void:
	await ow.display_text_id("TEXT_SAFFRONGYM_SABRINA_MARSH_BADGE_INFO", -1)
	state.set_event("EVENT_BEAT_SABRINA")
	if state.give_item("TM46", 1):
		Text.ram["wStringBuffer"] = GameData.item_name("TM46")
		await ow.display_text_id("TEXT_SAFFRONGYM_SABRINA_RECEIVED_TM46", -1)
		state.set_event("EVENT_GOT_TM46")
	else:
		await ow.display_text_id("TEXT_SAFFRONGYM_SABRINA_TM46_NO_ROOM", -1)
	state.badges |= 1 << 5         # BIT_MARSHBADGE
	state.beat_gym_flags |= 1 << 5
	for i in 7:                    # deactivate the gym trainers
		state.set_event("EVENT_BEAT_SAFFRON_GYM_TRAINER_%d" % i)
	trace("SABRINA_VICTORY badges=%d tm46=%d" % [state.badges, state.item_count("TM46")])


## SaffronGymSabrinaText.
func _sabrina_text(npc_index: int) -> void:
	if state.has_event("EVENT_BEAT_SABRINA"):
		if state.has_event("EVENT_GOT_TM46"):
			await ow.print_text("_SaffronGymSabrinaPostBattleAdviceText")
		else:
			# the TM didn't fit in the bag last time
			await _sabrina_receive_tm46()
			_gym_reset_scripts()
			ow.do_not_wait_after_text = true   # DisableWaitingAfterTextDisplay
		return
	await ow.print_text("_SaffronGymSabrinaText")
	event_battle(npc_index, 3, "_SaffronGymSabrinaReceivedMarshBadgeText", "", 6)


func trace(message: String) -> void:
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("CHAPTER9 %s frame=%d" % [message, GB.frame_count])

## Chapter 4 map scripts and text handlers: Route 3, the Mt. Moon Pokémon Center,
## Mt. Moon 1F/B1F/B2F and Route 4 (scripts/Route3.asm, MtMoonPokecenter.asm,
## MtMoon1F.asm, MtMoonB1F.asm, MtMoonB2F.asm, Route4.asm) and on to Cerulean City.
## Maps with only trainer headers need no code here (TrainerEngine handles them).
class_name MtMoonScripts
extends RefCounted

var ms: MapScripts
var ow: Overworld
var state: GameState
var cerulean: CeruleanScripts
var cape: CeruleanCapeScripts
var entered_map := ""


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state
	cerulean = CeruleanScripts.new(self)
	cape = CeruleanCapeScripts.new(self)


## The per-frame map script of the chapter 4 maps (called for maps map_scripts.gd
## does not handle itself). Return true when the map has its own script table (a gym:
## call ms.trainers.check_fighting_map_trainers() etc. yourself); false lets MapScripts
## run the generic trainer table for maps with trainer headers.
func run_map_script() -> bool:
	var entered := entered_map != ow.map_id
	entered_map = ow.map_id
	match ow.map_id:
		"MT_MOON_B2F":
			await _mtmoon_b2f()
			return true
		"CERULEAN_CITY", "CERULEAN_GYM", "CERULEAN_BADGE_HOUSE":
			return await cerulean.run_map_script(entered)
		"ROUTE_24", "ROUTE_25", "BILLS_HOUSE":
			return await cape.run_map_script(entered)
		_:
			return false


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		"TEXT_MTMOONPOKECENTER_NURSE": await Pokecenter.nurse(ow, npc_index)
		"TEXT_MTMOONPOKECENTER_LINK_RECEPTIONIST": await ow.print_text("_CableClubNPCWelcomeText")
		"TEXT_MTMOONPOKECENTER_MAGIKARP_SALESMAN": await _magikarp_salesman()
		"TEXT_MTMOONB2F_SUPER_NERD": await _super_nerd(npc_index)
		"TEXT_MTMOONB2F_DOME_FOSSIL": await _fossil(true)
		"TEXT_MTMOONB2F_HELIX_FOSSIL": await _fossil(false)
		"TEXT_MTMOONB2F_SUPER_NERD_THEN_THIS_IS_MINE":
			await ms._far("_MtMoonB2FSuperNerdThenThisIsMineText")
			await Sound.text_sound("sound_get_key_item")
		"TEXT_ROUTE4_POKECENTER_SIGN": await ms._far("_PokeCenterSignText")
		"TEXT_MTMOON1F_BEWARE_ZUBAT_SIGN": await ms._far("_MtMoon1FBewareZubatSign")
		_:
			if await cerulean.text(text_id, npc_index):
				return true
			return await cape.text(text_id, npc_index)
	return true


## EngageMapTrainer / SaveEndBattleTextPointers for non-header event opponents.
func event_battle(npc_index: int, post: int, win: String, lose: String = "", gym: int = 0) -> void:
	ms.trainers.header = {}
	ms.trainers._engage_map_trainer(npc_index + 1)
	ow.battle_request = {"trainer": ms.trainers.engaged_class, "team": ms.trainers.engaged_set,
		"win_text": win, "lose_text": lose if lose != "" else win}
	if gym > 0:
		ow.battle_request["gym_leader"] = gym
	ms._set_script(post)


func reset_script() -> void:
	ow.joy_ignore = 0
	ms._set_script(0)


## home/give.asm + engine/events/give_pokemon.asm; used by this map's vendor.
func _magikarp_salesman() -> void:
	if state.has_event("EVENT_BOUGHT_MAGIKARP"):
		await ow.print_text("_MtMoonPokecenterMagikarpSalesmanNoRefundsText")
		return
	await ow.print_text("_MtMoonPokecenterMagikarpSalesmanIGotADealText")
	Pokemart._money_box(state)
	if not await Menu.yes_no():
		await ow.print_text("_MtMoonPokecenterMagikarpSalesmanNoText")
		return
	if state.money < 500:
		await ow.print_text("_MtMoonPokecenterMagikarpSalesmanNoMoneyText")
		return
	if state.party.size() >= 6 and state.box.size() >= 20:
		await ow.print_text("_BoxIsFullText")
		return
	var mon := PartyMon.create("MAGIKARP", 5)
	state.pokedex_owned["MAGIKARP"] = true
	state.pokedex_seen["MAGIKARP"] = true
	Text.ram["wNameBuffer"] = GameData.mon_name("MAGIKARP")
	await ow.print_text("_GotMonText")
	await Sound.text_sound("sound_get_item_1")
	if state.party.size() < 6:
		state.party.append(mon)
		ow.do_not_wait_after_text = true
		await ow.print_text("_DoYouWantToNicknameText")
		if await Menu.yes_no():
			var name: String = await NamingScreen.new().run(NamingScreen.Kind.MON, "MAGIKARP")
			if name != "":
				mon.nickname = name
			ow.reload_map_view()
	else:
		state.box.push_front(mon)
		Text.ram["wBoxMonNicks"] = mon.nickname
		Text.ram["wStringBuffer"] = str(state.current_box + 1)
		await ow.print_text("_SentToBoxText")
	state.money -= 500
	Pokemart._money_box(state)
	state.set_event("EVENT_BOUGHT_MAGIKARP")
	trace("MAGIKARP_PURCHASE money=%d party=%d box=%d" % [state.money, state.party.size(), state.box.size()])


func _mtmoon_b2f() -> void:
	match ms._script_index():
		0:
			if not state.has_event("EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD") and ow.player.x == 13 and ow.player.y == 8:
				await ow.display_text_id("TEXT_MTMOONB2F_SUPER_NERD", 0)
			elif not _got_fossil():
				await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()
		3:
			if ow.last_battle_won:
				await GB.delay3()
				state.set_event("EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD")
			reset_script()
		4:
			var pos := Vector2i(ow.player.x, ow.player.y)
			var moves: Array = []
			if pos in [Vector2i(12, 7), Vector2i(11, 6), Vector2i(12, 5)]:
				moves = [Overworld.NPC_RIGHT, Overworld.NPC_UP]
			elif pos in [Vector2i(13, 7), Vector2i(14, 6), Vector2i(14, 5)]:
				moves = [Overworld.NPC_UP]
			if moves.is_empty():
				await ms.trainers.check_fighting_map_trainers()
			else:
				ow.move_sprite(0, moves)
				ms._set_script(5)
		5:
			if ow.npc_moving(0):
				return
			ow.joy_ignore = GB.CTRL_PAD
			await ow.display_text_id("TEXT_MTMOONB2F_SUPER_NERD_THEN_THIS_IS_MINE", -1)
			ow.hide_object(6 if state.has_event("EVENT_GOT_DOME_FOSSIL") else 5)
			reset_script()


func _got_fossil() -> bool:
	return state.has_event("EVENT_GOT_DOME_FOSSIL") or state.has_event("EVENT_GOT_HELIX_FOSSIL")


func _super_nerd(npc_index: int) -> void:
	if not state.has_event("EVENT_BEAT_MT_MOON_EXIT_SUPER_NERD"):
		await ow.print_text("_MtMoonB2FSuperNerdTheyreBothMineText")
		event_battle(npc_index, 3, "MtMoonB2FSuperNerdOkIllShareText")
	else:
		await ow.print_text("_MtMoonB2FSuperNerdTheresAPokemonLabText" if _got_fossil() else "_MtMoonB2fSuperNerdEachTakeOneText")


func _fossil(dome: bool) -> void:
	ow.do_not_wait_after_text = true
	await ow.print_text("_MtMoonB2FDomeFossilYouWantText" if dome else "_MtMoonB2FHelixFossilYouWantText")
	if not await Menu.yes_no():
		trace("FOSSIL_DECLINED")
		return
	if not state.give_item("DOME_FOSSIL" if dome else "HELIX_FOSSIL", 1):
		await ow.print_text("_MtMoonB2FYouHaveNoRoomText")
		await Text.wait_scroll_button(false)
		trace("FOSSIL_REJECTED bag_full")
		return
	Text.ram["wStringBuffer"] = GameData.item_name("DOME_FOSSIL" if dome else "HELIX_FOSSIL")
	await ow.print_text("_MtMoonB2FReceivedFossilText")
	await Sound.text_sound("sound_get_key_item")
	await Text.wait_scroll_button(false)
	ow.hide_object(5 if dome else 6)
	state.set_event("EVENT_GOT_DOME_FOSSIL" if dome else "EVENT_GOT_HELIX_FOSSIL")
	ms._set_script(4)
	trace("FOSSIL_SELECTED %s" % ("DOME_FOSSIL" if dome else "HELIX_FOSSIL"))


func trace(message: String) -> void:
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("CHAPTER4 %s frame=%d" % [message, GB.frame_count])

## Chapter 5: Routes 5 and 6, the Saffron City gates on them, the Underground Path
## entrances and the Daycare (scripts/Route5Gate.asm, Route6Gate.asm,
## UndergroundPathRoute5.asm, UndergroundPathRoute6.asm, Daycare.asm).
## Route 5/6 themselves and the tunnel only need the generic trainer/sign handling.
class_name Route56Scripts
extends RefCounted

var chapter: Chapter5Scripts
var ms: MapScripts
var ow: Overworld
var state: GameState

## GuardDrinksList (data/items/guard_drink_items.asm)
const GUARD_DRINKS := ["FRESH_WATER", "SODA_POP", "LEMONADE"]
## wStatusFlags1 BIT_GAVE_SAFFRON_GUARDS_DRINK, kept with the events
const GAVE_DRINK := "GAVE_SAFFRON_GUARDS_DRINK"


func _init(c: Chapter5Scripts) -> void:
	chapter = c
	ms = c.ms
	ow = c.ow
	state = c.state


func run_map_script(_entered: bool) -> bool:
	match ow.map_id:
		"ROUTE_5_GATE":
			await _gate(5)
		"ROUTE_6_GATE":
			await _gate(6)
		"UNDERGROUND_PATH_ROUTE_5":
			# UndergroundPathRoute5_Script: wLastMap = ROUTE_5 (the LAST_MAP warps lead back
			# to Route 5 even after walking the tunnel from Route 6)
			state.last_map = "ROUTE_5"
		"UNDERGROUND_PATH_ROUTE_6":
			state.last_map = "ROUTE_6"
	return true


func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		"TEXT_ROUTE5GATE_GUARD", "TEXT_ROUTE6GATE_GUARD": await _guard_text()
		"TEXT_ROUTE5GATE_GUARD_GEE_IM_THIRSTY", "TEXT_ROUTE6GATE_GUARD_GEE_IM_THIRSTY":
			await ow.print_text("_SaffronGateGuardGeeImThirstyText")
		"TEXT_ROUTE5GATE_GUARD_GIVE_DRINK", "TEXT_ROUTE6GATE_GUARD_GIVE_DRINK": await _give_drink_text()
		"TEXT_UNDERGROUNDPATHROUTE5_LITTLE_GIRL": await InGameTrade.dialogue(ow, state, InGameTrade.TRADE_FOR_SPOT)
		"TEXT_DAYCARE_GENTLEMAN": await _daycare()
		_:
			return false
	return true


# --- Saffron gates --------------------------------------------------------------------

## Route5GateDefaultScript / Route6GateDefaultScript and the *PlayerMovingScript.
func _gate(route: int) -> void:
	match ms._script_index():
		0:
			if state.has_event(GAVE_DRINK):
				return
			var coords: Array = [Vector2i(3, 3), Vector2i(4, 3)] if route == 5 else [Vector2i(3, 2), Vector2i(4, 2)]
			if not Vector2i(ow.player.x, ow.player.y) in coords:
				return
			ow.player.facing = Overworld.FACE_LEFT if route == 5 else Overworld.FACE_RIGHT
			var drink := _remove_guard_drink()
			if drink == "":
				await ow.display_text_id("TEXT_ROUTE%dGATE_GUARD_GEE_IM_THIRSTY" % route, -1)
				# Route5GateMovePlayerUpScript / Route6GateMovePlayerDownScript
				ow.simulate([GB.UP if route == 5 else GB.DOWN])
				ms._set_script(1)
			else:
				chapter.trace("GUARD_DRINK item=%s" % drink)
				if route == 6:
					state.set_event(GAVE_DRINK)
				await ow.display_text_id("TEXT_ROUTE%dGATE_GUARD_GIVE_DRINK" % route, -1)
				state.set_event(GAVE_DRINK)
		1:
			if not ow.sim_queue.is_empty():
				return
			await GB.delay3()
			ow.joy_ignore = 0
			ms._set_script(0)


## RemoveGuardDrink: the first drink of the list in the bag is removed; "" when none.
func _remove_guard_drink() -> String:
	for item in GUARD_DRINKS:
		if state.item_count(item) > 0:
			state.remove_item(item, 1)
			return item
	return ""


## SaffronGateGuardText (shared by both gates: it always simulates PAD_UP and sets
## wRoute5GateCurScript, like the original).
func _guard_text() -> void:
	if state.has_event(GAVE_DRINK):
		await ow.print_text("_SaffronGateGuardThanksForTheDrinkText")
		return
	var drink := _remove_guard_drink()
	if drink == "":
		await ow.print_text("_SaffronGateGuardGeeImThirstyText")
		ow.simulate([GB.UP])
		state.map_scripts["ROUTE_5_GATE"] = 1
		return
	chapter.trace("GUARD_DRINK item=%s" % drink)
	await _give_drink_text()
	state.set_event(GAVE_DRINK)


## SaffronGateGuardGiveDrinkText: two texts around the key item sound.
func _give_drink_text() -> void:
	await ow.print_text("_SaffronGateGuardImParchedText")
	await Sound.text_sound("sound_get_key_item")
	await ow.print_text("_SaffronGateGuardYouCanGoOnThroughText")


# --- Daycare --------------------------------------------------------------------------

## DaycareGentlemanText.
func _daycare() -> void:
	var saved: PackedInt32Array = GB.screen.snapshot_bg()   # SaveScreenTilesToBuffer2
	if state.daycare_mon == null:
		await ow.print_text("_DaycareGentlemanIntroText")
		if not await Menu.yes_no():
			await _come_again()
			return
		if state.party.size() == 1:
			await ow.print_text("_DaycareGentlemanOnlyHaveOneMonText")
			return
		await ow.print_text("_DaycareGentlemanWhichMonText")
		ow.update_sprites = false
		var idx := await PartyMenu.show(state, "normal")
		await InGameTrade._restore_screen(ow, saved)
		if idx < 0:
			await _all_right_then()
			return
		var m: PartyMon = state.party[idx]
		if m.knows_hm_move():
			chapter.trace("DAYCARE_HM_REFUSED %s" % m.species)
			await ow.print_text("_DaycareGentlemanCantAcceptMonWithHMText")
			return
		Text.ram["wNameBuffer"] = m.nickname
		await ow.print_text("_DaycareGentlemanWillLookAfterMonText")
		# MoveMon PARTY_TO_DAYCARE + RemovePokemon
		state.daycare_mon = m
		state.daycare_level = m.level
		state.party.remove_at(idx)
		Sound.play_cry(m.species)
		await Sound.wait_for_sfx()
		chapter.trace("DAYCARE_DEPOSIT %s level=%d party=%d" % [m.species, m.level, state.party.size()])
		await ow.print_text("_DaycareGentlemanComeSeeMeInAWhileText")
		return
	# .daycareInUse
	var m: PartyMon = state.daycare_mon
	var growth: String = GameData.pokemon[m.species]["growth"]
	Text.ram["wNameBuffer"] = m.nickname
	Text.ram["wDayCareMonName"] = m.nickname
	var d := PartyMon.level_for_exp(growth, m.exp)
	if d >= 100:
		d = 100
		m.exp = PartyMon.exp_for_level(growth, 100)
	var start := state.daycare_level   # wDayCareStartLevel
	state.daycare_level = d
	var grown := 0
	if start == d:
		await ow.print_text("_DaycareGentlemanMonNeedsMoreTimeText")
	else:
		grown = d - start
		Text.ram["wDayCareNumLevelsGrown"] = str(grown)
		await ow.print_text("_DaycareGentlemanMonHasGrownText")
	if state.party.size() >= 6:
		await ow.print_text("_DaycareGentlemanNoRoomForMonText")
		state.daycare_level = start
		return
	var cost := 100 * (grown + 1)   # wDayCarePerLevelCost added (levels grown + 1) times
	Text.ram["wDayCareTotalCost"] = str(cost)
	await ow.print_text("_DaycareGentlemanOweMoneyText")
	Pokemart._money_box(state)
	if not await Menu.yes_no():
		await _all_right_then()
		state.daycare_level = start
		return
	if state.money < cost:
		await ow.print_text("_DaycareGentlemanNotEnoughMoneyText")
		state.daycare_level = start
		return
	state.money -= cost
	Sound.play_sfx("SFX_PURCHASE")
	await Sound.wait_for_sfx()
	Pokemart._money_box(state)
	await ow.print_text("_DaycareGentlemanHeresYourMonText")
	# MoveMon DAYCARE_TO_PARTY: level from experience, stats, moves learned meanwhile, full HP
	m.level = d
	m.learn_daycare_moves(start)
	m.recalc_stats()
	m.hp = m.max_hp
	state.party.append(m)
	state.daycare_mon = null
	state.daycare_level = 0
	Sound.play_cry(m.species)
	await Sound.wait_for_sfx()
	chapter.trace("DAYCARE_WITHDRAW %s level=%d grown=%d cost=%d money=%d" % [m.species, m.level, grown, cost, state.money])
	await ow.print_text("_DaycareGentlemanGotMonBackText")


## .AllRightThenText falls through into .ComeAgainText.
func _all_right_then() -> void:
	await ow.print_text("_DaycareGentlemanAllRightThenText")
	await Text.run_commands(GameData.text("_DaycareGentlemanComeAgainText"))


func _come_again() -> void:
	await ow.print_text("_DaycareGentlemanComeAgainText")

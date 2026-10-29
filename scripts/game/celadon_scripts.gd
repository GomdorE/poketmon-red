## Celadon City (scripts/CeladonCity.asm) and its buildings: the department store
## (CeladonMart1F..5F.asm, CeladonMartElevator.asm, CeladonMartRoof.asm), the Celadon
## Mansion (CeladonMansion1F/2F/3F/Roof/RoofHouse.asm), the Pokémon Center, the diner
## (CeladonDiner.asm), the chief's house, the hotel and the gym (CeladonGym.asm).
## The Game Corner and the Rocket Hideout have their own files.
class_name CeladonScripts
extends RefCounted

const ROOF_DRINKS := ["FRESH_WATER", "SODA_POP", "LEMONADE"]   # CeladonMartRoofDrinkList
## the drink -> (TM, got-it event, texts) of CeladonMartRoofScript_GiveDrinkToGirl
const ROOF_TMS := {
	"FRESH_WATER": ["TM13", "EVENT_GOT_TM13", "_CeladonMartRoofLittleGirlYayFreshWaterText", "_CeladonMartRoofLittleGirlReceivedTM13Text", "_CeladonMartRoofLittleGirlTM13ExplanationText"],
	"SODA_POP": ["TM48", "EVENT_GOT_TM48", "_CeladonMartRoofLittleGirlYaySodaPopText", "_CeladonMartRoofLittleGirlReceivedTM48Text", "_CeladonMartRoofLittleGirlTM48ExplanationText"],
	"LEMONADE": ["TM49", "EVENT_GOT_TM49", "_CeladonMartRoofLittleGirlYayLemonadeText", "_CeladonMartRoofLittleGirlReceivedTM49Text", "_CeladonMartRoofLittleGirlTM49ExplanationText"],
}
## CeladonMartElevatorFloors / CeladonMartElevatorWarpMaps (destination warp 0-based, map)
const MART_FLOORS := ["FLOOR_1F", "FLOOR_2F", "FLOOR_3F", "FLOOR_4F", "FLOOR_5F"]
const MART_WARPS := [[5, "CELADON_MART_1F"], [2, "CELADON_MART_2F"], [2, "CELADON_MART_3F"], [2, "CELADON_MART_4F"], [2, "CELADON_MART_5F"]]

var chapter: Chapter7Scripts
var ms: MapScripts
var ow: Overworld
var state: GameState
var elevator := Elevator.new()


func _init(c: Chapter7Scripts) -> void:
	chapter = c
	ms = c.ms
	ow = c.ow
	state = c.state


func run_map_script(entered: bool) -> bool:
	match ow.map_id:
		"CELADON_MART_ELEVATOR":
			await elevator.run_map_script(ow, entered)
		"CELADON_GYM":
			await _gym()
		_:
			return false
	return true


func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		# Celadon City
		"TEXT_CELADONCITY_GRAMPS3": await _gramps3()
		"TEXT_CELADONCITY_POLIWRATH":
			await ow.print_text("_CeladonCityPoliwrathText")
			Sound.play_cry("POLIWRATH")
			await Sound.wait_for_sfx()
		"TEXT_CELADONCITY_POKECENTER_SIGN": await ms._far("_PokeCenterSignText")
		# the department store
		"TEXT_CELADONMART2F_CLERK1": await Pokemart.dialogue(ow, "CELADON_MART_2F_CLERK1")
		"TEXT_CELADONMART2F_CLERK2": await Pokemart.dialogue(ow, "CELADON_MART_2F_CLERK2")
		"TEXT_CELADONMART3F_CLERK": await _mart_3f_clerk()
		"TEXT_CELADONMART3F_SNES1", "TEXT_CELADONMART3F_SNES2", "TEXT_CELADONMART3F_SNES3", "TEXT_CELADONMART3F_SNES4":
			await ow.print_text("_CeladonMart3FSNESText")
		"TEXT_CELADONMART3F_POKEMON_POSTER1", "TEXT_CELADONMART3F_POKEMON_POSTER2", "TEXT_CELADONMART3F_POKEMON_POSTER3":
			await ow.print_text("_CeladonMart3FPokemonPosterText")
		"TEXT_CELADONMART4F_CLERK": await Pokemart.dialogue(ow, "CELADON_MART_4F")
		"TEXT_CELADONMART5F_CLERK1": await Pokemart.dialogue(ow, "CELADON_MART_5F_CLERK1")
		"TEXT_CELADONMART5F_CLERK2": await Pokemart.dialogue(ow, "CELADON_MART_5F_CLERK2")
		"TEXT_CELADONMARTELEVATOR":
			await elevator.floor_menu(ow, MART_FLOORS, MART_WARPS)
			ow.do_not_wait_after_text = true
		"TEXT_CELADONMARTROOF_LITTLE_GIRL": await _roof_girl()
		"TEXT_CELADONMARTROOF_VENDING_MACHINE1", "TEXT_CELADONMARTROOF_VENDING_MACHINE2", "TEXT_CELADONMARTROOF_VENDING_MACHINE3":
			await VendingMachine.menu(ow)
		# the Celadon Mansion
		"TEXT_CELADONMANSION1F_MEOWTH": await _cry("MEOWTH")
		"TEXT_CELADONMANSION1F_CLEFAIRY": await _cry("CLEFAIRY")
		"TEXT_CELADONMANSION1F_NIDORANF": await _cry("NIDORAN_F")
		"TEXT_CELADONMANSION3F_GAME_DESIGNER": await _game_designer()
		"TEXT_CELADONMANSION_ROOF_HOUSE_EEVEE_POKEBALL":
			if await GivePokemon.give(ow, "EEVEE", 25):
				ow.hide_object(1)   # TOGGLE_CELADON_MANSION_EEVEE_GIFT
				state.set_event("HIDE_CELADON_MANSION_ROOF_HOUSE_1")
				chapter.trace("EEVEE_GIFT party=%d box=%d" % [state.party.size(), state.box.size()])
		# the Pokémon Center, the diner, the gym
		"TEXT_CELADONPOKECENTER_NURSE": await Pokecenter.nurse(ow, npc_index)
		"TEXT_CELADONPOKECENTER_LINK_RECEPTIONIST": await ow.print_text("_CableClubNPCWelcomeText")
		"TEXT_CELADONDINER_GYM_GUIDE": await _diner_gym_guide()
		"TEXT_CELADONGYM_ERIKA": await _erika_text(npc_index)
		"TEXT_CELADONGYM_RAINBOWBADGE_INFO": await ms._far("_CeladonGymRainbowBadgeInfoText")
		"TEXT_CELADONGYM_RECEIVED_TM21":
			await ow.print_text("_CeladonGymReceivedTM21Text")
			await Sound.text_sound("sound_get_item_1")
		"TEXT_CELADONGYM_TM21_NO_ROOM": await ms._far("_CeladonGymTM21NoRoomText")
		_:
			return false
	return true


## A text handler that is only PlayCry (the text box stays empty).
func _cry(species: String) -> void:
	Sound.play_cry(species)
	await Sound.wait_for_sfx()


# --- Celadon City -----------------------------------------------------------------------

## CeladonCityGramps3Text: TM41 (SOFTBOILED) once.
func _gramps3() -> void:
	if state.has_event("EVENT_GOT_TM41"):
		await ow.print_text("_CeladonCityGramps3TM41ExplanationText")
		return
	await ow.print_text("_CeladonCityGramps3Text")
	if state.give_item("TM41", 1):
		Text.ram["wStringBuffer"] = GameData.item_name("TM41")
		await ow.print_text("_CeladonCityGramps3ReceivedTM41Text")
		await Sound.text_sound("sound_get_item_1")
		state.set_event("EVENT_GOT_TM41")
		chapter.trace("GOT_TM41")
	else:
		await ow.print_text("_CeladonCityGramps3TM41NoRoomText")


# --- the department store -----------------------------------------------------------------

## CeladonMart3FClerkText: TM18 (COUNTER) once.
func _mart_3f_clerk() -> void:
	if state.has_event("EVENT_GOT_TM18"):
		await ow.print_text("_CeladonMart3FClerkTM18ExplanationText")
		return
	await ow.print_text("_CeladonMart3FClerkTM18PreReceiveText")
	if state.give_item("TM18", 1):
		state.set_event("EVENT_GOT_TM18")
		Text.ram["wStringBuffer"] = GameData.item_name("TM18")
		await ow.print_text("_CeladonMart3FClerkReceivedTM18Text")
		await Sound.text_sound("sound_get_item_1")
		chapter.trace("GOT_TM18")
	else:
		await ow.print_text("_CeladonMart3FClerkTM18NoRoomText")


## CeladonMartRoofLittleGirlText: with a drink in the bag, "Give her a drink?" then the
## drink menu; without one she is thirsty.
func _roof_girl() -> void:
	var drinks: Array = []   # CeladonMartRoofScript_GetDrinksInBag
	for d in ROOF_DRINKS:
		if state.item_count(d) > 0:
			drinks.append(d)
	if drinks.is_empty():
		await ow.print_text("_CeladonMartRoofLittleGirlImThirstyText")
		return
	ow.do_not_wait_after_text = true
	await ow.print_text("_CeladonMartRoofLittleGirlGiveHerADrinkText")
	if not await Menu.yes_no():
		return
	await _give_drink_to_girl(drinks)


## CeladonMartRoofScript_GiveDrinkToGirl: the drinks of the bag in a box at (0,0), two rows
## each; FRESH WATER -> TM13, SODA POP -> TM48, LEMONADE -> TM49, each once.
func _give_drink_to_girl(drinks: Array) -> void:
	Text.no_delay = true
	await ow.print_text("_CeladonMartRoofLittleGirlGiveHerWhichDrinkText")
	Menu.draw_box(0, 0, 12, drinks.size() * 2)
	for i in drinks.size():   # CeladonMartRoofScript_PrintDrinksInBag
		Text.place_string(2, 2 + i * 2, GameData.item_name(drinks[i]))
	Text.no_delay = false
	var keys := await Menu.handle_input(1, 2, drinks.size(), GB.A | GB.B)
	Menu.erase_cursor()
	if keys & GB.B:
		return
	var drink: String = drinks[Menu.current]
	var entry: Array = ROOF_TMS[drink]
	if state.has_event(entry[1]):
		await _roof_text("_CeladonMartRoofLittleGirlImNotThirstyText")
		return
	await _roof_text(entry[2])
	state.remove_item(drink, 1)   # RemoveItemByID
	if not state.give_item(entry[0], 1):
		await _roof_text("_CeladonMartRoofLittleGirlNoRoomText")
		return
	Text.ram["wStringBuffer"] = GameData.item_name(entry[0])
	# ReceivedTM text: the TM name, the item sound, the explanation, then the button
	await ow.print_text(entry[3])
	await Sound.text_sound("sound_get_item_1")
	await Text.run_commands(GameData.text(entry[4]))
	await Text.wait_scroll_button()
	state.set_event(entry[1])
	chapter.trace("ROOF_GIRL drink=%s tm=%s" % [drink, entry[0]])


## The roof girl's texts end with text_waitbutton.
func _roof_text(label: String) -> void:
	await ow.print_text(label)
	await Text.wait_scroll_button()


# --- the Celadon Mansion ---------------------------------------------------------------

## CeladonMansion3FGameDesignerText: with 150 kinds owned (Mew does not count) the
## diploma follows the text.
func _game_designer() -> void:
	var owned := 0
	for sp in state.pokedex_owned:
		if state.pokedex_owned[sp]:
			owned += 1
	if owned < 150:
		await ow.print_text("_CeladonMansion3FGameDesignerText")
		return
	await ow.print_text("_CeladonMansion3FGameDesignerCompletedDexText")
	await Text._prompt()
	await Diploma.show(ow)
	ow.reload_map_view()
	ow.do_not_wait_after_text = true


# --- the diner --------------------------------------------------------------------------

## CeladonDinerGymGuideText: the COIN CASE once.
func _diner_gym_guide() -> void:
	if state.has_event("EVENT_GOT_COIN_CASE"):
		await ow.print_text("_CeladonDinerGymGuideWinItBackText")
		return
	await ow.print_text("_CeladonDinerGymGuideImFlatOutBustedText")
	if state.give_item("COIN_CASE", 1):
		state.set_event("EVENT_GOT_COIN_CASE")
		Text.ram["wStringBuffer"] = GameData.item_name("COIN_CASE")
		await ow.print_text("_CeladonDinerGymGuideReceivedCoinCaseText")
		await Sound.text_sound("sound_get_key_item")
		chapter.trace("GOT_COIN_CASE")
	else:
		await ow.print_text("_CeladonDinerGymGuideCoinCaseNoRoomText")


# --- the gym ------------------------------------------------------------------------------

## CeladonGym_ScriptPointers.
func _gym() -> void:
	match ms._script_index():
		0: await ms.trainers.check_fighting_map_trainers()
		1: await ms.trainers.display_enemy_trainer_text_and_start_battle()
		2: ms.trainers.end_trainer_battle()
		3:
			# CeladonGymErikaPostBattleScript
			if not ow.last_battle_won:
				_gym_reset_scripts()
				return
			ow.joy_ignore = GB.CTRL_PAD
			await _erika_receive_tm21()
			_gym_reset_scripts()


## CeladonGymResetScripts.
func _gym_reset_scripts() -> void:
	ow.joy_ignore = 0
	ms._set_script(0)


## CeladonGymReceiveTM21 (+ .gymVictory): the badge info, TM21 (MEGA DRAIN), the
## RAINBOWBADGE and the gym trainers deactivated.
func _erika_receive_tm21() -> void:
	await ow.display_text_id("TEXT_CELADONGYM_RAINBOWBADGE_INFO", -1)
	state.set_event("EVENT_BEAT_ERIKA")
	if state.give_item("TM21", 1):
		Text.ram["wStringBuffer"] = GameData.item_name("TM21")
		await ow.display_text_id("TEXT_CELADONGYM_RECEIVED_TM21", -1)
		state.set_event("EVENT_GOT_TM21")
	else:
		await ow.display_text_id("TEXT_CELADONGYM_TM21_NO_ROOM", -1)
	state.badges |= 8          # BIT_RAINBOWBADGE
	state.beat_gym_flags |= 8
	for i in 7:                # deactivate the gym trainers
		state.set_event("EVENT_BEAT_CELADON_GYM_TRAINER_%d" % i)
	chapter.trace("ERIKA_VICTORY badges=%d tm21=%d" % [state.badges, state.item_count("TM21")])


## CeladonGymErikaText.
func _erika_text(npc_index: int) -> void:
	if state.has_event("EVENT_BEAT_ERIKA"):
		if state.has_event("EVENT_GOT_TM21"):
			await ow.print_text("_CeladonGymErikaPostBattleAdviceText")
		else:
			# the TM didn't fit in the bag last time
			await _erika_receive_tm21()
			_gym_reset_scripts()
			ow.do_not_wait_after_text = true   # DisableWaitingAfterTextDisplay
		return
	await ow.print_text("_CeladonGymErikaPreBattleText")
	chapter.event_battle(npc_index, 3, "_CeladonGymErikaReceivedRainbowBadgeText", "", 4)

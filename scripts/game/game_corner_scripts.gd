## The Celadon Game Corner (scripts/GameCorner.asm, engine/slots/game_corner_slots.asm,
## game_corner_slots2.asm) and the prize room (scripts/GameCornerPrizeRoom.asm,
## engine/events/prize_menu.asm, data/events/prizes.asm, prize_mon_levels.asm).
## The slot machine game itself is SlotMachine.
class_name GameCornerScripts
extends RefCounted

const ROCKET := 10   # GAMECORNER_ROCKET, the Rocket in front of the poster
## PrizeDifferentMenuPtrs: the three prize windows (prize, coins); the third one is TMs
## (TM23 DRAGON RAGE, TM15 HYPER BEAM, TM50 SUBSTITUTE)
const PRIZES := [
	[["ABRA", 180], ["CLEFAIRY", 500], ["NIDORINA", 1200]],
	[["DRATINI", 2800], ["SCYTHER", 5500], ["PORYGON", 9999]],
	[["TM23", 3300], ["TM15", 5500], ["TM50", 7700]],
]
const PRIZE_MON_LEVELS := {"ABRA": 9, "CLEFAIRY": 8, "NIDORINA": 17, "DRATINI": 18, "SCYTHER": 25, "PORYGON": 26}

var chapter: Chapter7Scripts
var ms: MapScripts
var ow: Overworld
var state: GameState
var lucky_slot := 0          # wLuckySlotHiddenEventIndex
var reload_flags := false    # BIT_CUR_MAP_LOADED_1/2 set again when the Rocket leaves


func _init(c: Chapter7Scripts) -> void:
	chapter = c
	ms = c.ms
	ow = c.ow
	state = c.state


func run_map_script(entered: bool) -> bool:
	match ow.map_id:
		"GAME_CORNER":
			if entered or reload_flags:
				reload_flags = false
				_select_lucky_slot_machine()
				_set_rocket_hideout_door_tile()
			match ms._script_index():
				1: await _rocket_battle_script()
				2: _rocket_exit_script()
		_:
			return false
	return true


func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		"TEXT_GAMECORNER_CLERK1": await _clerk1()
		"TEXT_GAMECORNER_FISHING_GURU":
			await _coin_giver("EVENT_GOT_10_COINS", 10, "_GameCornerFishingGuruWantToPlayText", "_GameCornerFishingGuruReceived10CoinsText",
				"_GameCornerFishingGuruDontNeedMyCoinsText", "_GameCornerFishingGuruWinsComeAndGoText", true)
		"TEXT_GAMECORNER_GYM_GUIDE":
			await ow.print_text("_GameCornerGymGuideTheyOfferRarePokemonText" if state.has_event("EVENT_BEAT_ERIKA") else "_GameCornerGymGuideChampInMakingText")
		"TEXT_GAMECORNER_CLERK2":
			await _coin_giver("EVENT_GOT_20_COINS_2", 20, "_GameCornerClerk2WantSomeCoinsText", "_GameCornerClerk2Received20CoinsText",
				"_GameCornerClerk2YouHaveLotsOfCoinsText", "_GameCornerClerk2INeedMoreCoinsText")
		"TEXT_GAMECORNER_GENTLEMAN":
			await _coin_giver("EVENT_GOT_20_COINS", 20, "_GameCornerGentlemanThrowingMeOffText", "_GameCornerGentlemanReceived20CoinsText",
				"_GameCornerGentlemanYouGotYourOwnCoinsText", "_GameCornerGentlemanCloselyWatchTheReelsText", false, true)
		"TEXT_GAMECORNER_ROCKET":
			await ow.print_text("_GameCornerRocketImGuardingThisPosterText")
			chapter.event_battle(npc_index, 1, "_GameCornerRocketBattleEndText")
		"TEXT_GAMECORNER_POSTER": await _poster()
		"TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_1": await _prize_menu(0)
		"TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_2": await _prize_menu(1)
		"TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_3": await _prize_menu(2)
		_:
			return false
	return true


# --- the Game Corner map -------------------------------------------------------------

## GameCornerSelectLuckySlotMachine: hRandomAdd / 8 (at least 1) picks the machine whose
## 7/BAR chance is a little better (the hidden event with index lucky - 1).
func _select_lucky_slot_machine() -> void:
	var r := ow.rng.randi_range(0, 255)
	if r < 7:
		r = 8
	lucky_slot = r >> 3
	chapter.trace("LUCKY_SLOT %d" % lucky_slot)


## GameCornerSetRocketHideoutDoorTile: block (8, 2) is a wall ($2a) until the poster's
## switch was found; the map data has the stairs ($43).
func _set_rocket_hideout_door_tile() -> void:
	if state.has_event("EVENT_FOUND_ROCKET_HIDEOUT"):
		return
	_replace_block(8, 2, 0x2a)


func _replace_block(bx: int, by: int, block: int) -> void:
	ow.cut_blocks[Vector2i(bx, by)] = block
	ow._put_block(bx, by, block, ow.tileset)


## GameCornerRocketBattleScript: after the battle the Rocket speaks and walks off to the
## right (around the player when they stand in his way).
func _rocket_battle_script() -> void:
	if not ow.last_battle_won:
		ow.joy_ignore = 0   # GameCornerReenterMapAfterPlayerLoss
		ms._set_script(0)
		return
	ow.joy_ignore = GB.CTRL_PAD
	await ow.display_text_id("TEXT_GAMECORNER_ROCKET_AFTER_BATTLE", -1)
	var moves: Array = [Overworld.NPC_DOWN, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_UP,
		Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT]
	if ow.player.y == 6 or ow.player.x == 8:
		moves = [Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT, Overworld.NPC_RIGHT]
	ow.move_sprite(ROCKET, moves)
	ms._set_script(2)


## GameCornerRocketExitScript.
func _rocket_exit_script() -> void:
	if ow.npc_moving(ROCKET):
		return
	ow.joy_ignore = 0
	ow.hide_object(ROCKET)   # TOGGLE_GAME_CORNER_ROCKET
	reload_flags = true
	ms._set_script(0)
	chapter.trace("GAMECORNER_ROCKET_GONE")


## GameCornerPosterText: the switch behind the poster opens the stairs to the hideout.
func _poster() -> void:
	ow.do_not_wait_after_text = true
	await ow.print_text("_GameCornerPosterSwitchBehindPosterText")
	Sound.play_sfx("SFX_SWITCH")
	await Sound.wait_for_sfx()
	Sound.play_sfx("SFX_GO_INSIDE")
	await Sound.wait_for_sfx()
	state.set_event("EVENT_FOUND_ROCKET_HIDEOUT")
	_replace_block(8, 2, 0x43)
	chapter.trace("FOUND_ROCKET_HIDEOUT")


## GameCornerClerk1Text: 50 coins for ¥1000 (a COIN CASE with room for them is needed).
func _clerk1() -> void:
	_draw_coin_box()
	await ow.print_text("_GameCornerClerk1DoYouNeedSomeGameCoinsText")
	var label := "_GameCornerClerk1PleaseComePlaySometimeText"
	if await Menu.yes_no():
		if state.item_count("COIN_CASE") == 0:
			label = "_GameCornerClerk1DontHaveCoinCaseText"
		elif state.coins >= 9990:   # Has9990Coins
			label = "_GameCornerClerk1CoinCaseIsFullText"
		elif state.money < 1000:
			label = "_GameCornerClerk1CantAffordTheCoinsText"
		else:
			state.money -= 1000
			state.coins = mini(state.coins + 50, 9999)
			_draw_coin_box()
			label = "_GameCornerClerk1ThanksHereAre50CoinsText"
			chapter.trace("BOUGHT_COINS coins=%d money=%d" % [state.coins, state.money])
	await ow.print_text(label)


## The customers who hand out coins once (GameCornerFishingGuruText, Clerk2Text,
## GentlemanText). The gentleman's coin case only counts as full at exactly 9990 coins
## (the original tests the wrong flag).
func _coin_giver(event: String, amount: int, ask: String, received: String, full: String, again: String, no_wait: bool = false, exact_full: bool = false) -> void:
	if state.has_event(event):
		await ow.print_text(again)
		return
	await ow.print_text(ask)
	if state.item_count("COIN_CASE") == 0:
		await ow.print_text("_GameCornerOopsForgotCoinCaseText")
		return
	if (state.coins == 9990) if exact_full else (state.coins >= 9990):
		await ow.print_text(full)
		return
	state.coins = mini(state.coins + amount, 9999)
	state.set_event(event)
	if no_wait:
		ow.do_not_wait_after_text = true
	await ow.print_text(received)
	await Sound.text_sound("sound_get_item_1")
	chapter.trace("GOT_COINS %d coins=%d" % [amount, state.coins])


## GameCornerDrawCoinBox: MONEY and COIN in a box at (11, 0). The Korean labels are two
## rows tall, so the Korean box gets one more row (COIN under the money, not over it).
func _draw_coin_box() -> void:
	var ko := GameData.lang == "ko"
	Text.no_delay = true
	if ko:
		Menu.draw_box(11, 0, 7, 6)
		Text.clear_area(12, 1, 7, 6)
		Text.place_string(12, 2, "소지금")
		ListMenu.place_money(12, 3, state.money)
		Text.place_string(12, 5, "코인")
		Text.place_string(15, 6, "%4d" % state.coins)
	else:
		Menu.draw_box(11, 0, 7, 5)
		Text.clear_area(12, 1, 7, 4)
		Text.place_string(12, 2, "MONEY")
		ListMenu.place_money(12, 3, state.money)
		Text.place_string(12, 4, "COIN")
		Text.place_string(15, 5, "%4d" % state.coins)
	Text.no_delay = false


# --- the slot machines ------------------------------------------------------------------

## StartSlotMachine (a hidden event on every machine): the broken ones have a text; the
## others need the player facing left or right, a COIN CASE and some coins
## (AbleToPlaySlotsCheck). The lucky machine's 7/BAR mode chance is 250 instead of 253.
func start_slot_machine(arg: String, hidden_index: int) -> void:
	match arg:
		"SLOTS_OUTOFORDER":
			await ow._show_overworld_text("_GameCornerOutOfOrderText", true)
			return
		"SLOTS_OUTTOLUNCH":
			await ow._show_overworld_text("_GameCornerOutToLunchText", true)
			return
		"SLOTS_SOMEONESKEYS":
			await ow._show_overworld_text("_GameCornerSomeonesKeysText", true)
			return
	if ow.player.facing & 8 == 0:
		return
	if state.item_count("COIN_CASE") == 0:
		await ow._show_overworld_text("_GameCornerCoinCaseText", true)
		return
	if state.coins == 0:
		await ow._show_overworld_text("_GameCornerNoCoinsText", true)
		return
	var chance := 250 if hidden_index + 1 == lucky_slot else 253
	chapter.trace("SLOTS start index=%d lucky=%d chance=%d coins=%d" % [hidden_index, lucky_slot, chance, state.coins])
	await SlotMachine.new().play(ow, chance)
	chapter.trace("SLOTS end coins=%d" % state.coins)


# --- the prize room ---------------------------------------------------------------------

## CeladonPrizeMenu: the coin box, the three prizes with their prices and NO THANKS.
func _prize_menu(which: int) -> void:
	if state.item_count("COIN_CASE") == 0:
		await ow.print_text("_RequireCoinCaseText")
		await Text.wait_scroll_button()
		return
	Text.no_delay = true
	await ow.print_text("_ExchangeCoinsForPrizesText")
	_print_prize_price()
	Menu.draw_box(0, 2, 16, 8)
	var ko := GameData.lang == "ko"
	var prizes: Array = PRIZES[which]
	for i in 3:
		var prize: String = prizes[i][0]
		Text.place_string(2, 4 + i * 2, GameData.item_name(prize) if which == 2 else GameData.mon_name(prize))
		Text.place_string(13, 5 + i * 2, "%4d" % int(prizes[i][1]))
	Text.place_string(2, 10, "괜찮습니다" if ko else "NO THANKS")
	await ow.print_text("_WhichPrizeText")
	var keys := await Menu.handle_input(1, 4, 4, GB.A | GB.B)
	Menu.erase_cursor()
	if not (keys & GB.B) and Menu.current != 3:
		await _handle_prize_choice(which, Menu.current)
	Text.no_delay = false


## PrintPrizePrice: the COIN box at (11, 0) with the player's coins.
func _print_prize_price() -> void:
	Menu.draw_box(11, 0, 7, 1)
	Text.place_string(12, 0, "코인" if GameData.lang == "ko" else "COIN")
	Text.place_string(13, 1, "%6d" % state.coins)


## HandlePrizeChoice: "So, you want X?", the coins check, the item or the Pokémon.
func _handle_prize_choice(which: int, index: int) -> void:
	var prize: String = PRIZES[which][index][0]
	var price: int = PRIZES[which][index][1]
	Text.ram["wNameBuffer"] = GameData.item_name(prize) if which == 2 else GameData.mon_name(prize)
	await ow.print_text("_SoYouWantPrizeText")
	if not await Menu.yes_no():
		await ow.print_text("_OhFineThenText")
		await Text.wait_scroll_button()
		return
	if state.coins < price:
		await ow.print_text("_SorryNeedMoreCoinsText")
		await Text.wait_scroll_button()
		return
	if which == 2:
		if not state.give_item(prize, 1):
			await ow.print_text("_OopsYouDontHaveEnoughRoomText")
			await Text.wait_scroll_button()
			return
	else:
		var party_before := state.party.size()
		var received := await GivePokemon.give(ow, prize, int(PRIZE_MON_LEVELS[prize]))
		if state.party.size() == party_before:   # not added to the party: wait after the message
			await Text.wait_scroll_button()
		if not received:
			return
	state.coins -= price
	_print_prize_price()
	chapter.trace("PRIZE %s coins=%d" % [prize, state.coins])

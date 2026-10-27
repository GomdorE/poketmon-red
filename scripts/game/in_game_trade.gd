## In-game trades (engine/events/in_game_trades.asm DoInGameTradeDialogue): the offer,
## YES/NO, the party menu, the trade movie and the received mon.
class_name InGameTrade
extends RefCounted

## constants/script_constants.asm TRADE_FOR_* (index into TradeMons)
const TRADE_FOR_TERRY := 0
const TRADE_FOR_MARCEL := 1
const TRADE_FOR_SAILOR := 3
const TRADE_FOR_DUX := 4
const TRADE_FOR_MARC := 5
const TRADE_FOR_LOLA := 6
const TRADE_FOR_DORIS := 7
const TRADE_FOR_CRINKLES := 8
const TRADE_FOR_SPOT := 9
## InGameTrade_CheckForTradeEvo: received species that evolve by trading (none of TradeMons)
const TRADE_EVO_SPECIES := ["KADABRA", "MACHOKE", "GRAVELER", "HAUNTER"]
## InGameTrade_TrainerString: the received mon's OT and the movie's other trainer
const TRAINER_STRING := "<TRAINER>"


## DoInGameTradeDialogue for wWhichTrade = `which`.
static func dialogue(ow: Overworld, state: GameState, which: int) -> void:
	var S: GBScreen = GB.screen
	var saved := S.snapshot_bg()   # SaveScreenTilesToBuffer2
	var t: Dictionary = GameData.trade["trades"][which]
	var give := str(t["give"])
	var receive := str(t["get"])
	var dialog_set := int(t["dialog"]) + 1   # TradeTextPointers1-3
	Text.ram["wInGameTradeGiveMonName"] = GameData.mon_name(give)
	Text.ram["wInGameTradeReceiveMonName"] = GameData.mon_name(receive)
	if state.completed_trades & (1 << which):
		_trace("_AfterTrade%dText" % dialog_set)
		await Text.print_text("_AfterTrade%dText" % dialog_set)
		return
	await Text.print_text("_WannaTrade%dText" % dialog_set)
	var result := "NoTrade"
	if await Menu.yes_no():
		result = await _do_trade(ow, state, which, saved)
		if result == "Thanks":
			await Text.print_text("_TradedForText")
			await Text.run_commands([["sound", "sound_get_key_item"], ["text_pause", ""]])
	_trace("_%s%dText" % [result, dialog_set])
	await Text.print_text("_%s%dText" % [result, dialog_set])


static func _trace(label: String) -> void:
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("IN_GAME_TRADE_TEXT " + label)


## InGameTrade_DoTrade: returns the text to print next ("NoTrade", "WrongMon", "Thanks").
static func _do_trade(ow: Overworld, state: GameState, which: int, saved: PackedInt32Array) -> String:
	var t: Dictionary = GameData.trade["trades"][which]
	var give := str(t["give"])
	var receive := str(t["get"])
	ow.update_sprites = false
	var idx := await PartyMenu.show(state, "normal")
	await _restore_screen(ow, saved)
	if idx < 0:
		return "NoTrade"
	var m: PartyMon = state.party[idx]
	if m.species != give:
		return "WrongMon"
	var level := m.level   # wCurEnemyLevel
	state.completed_trades |= 1 << which
	await Text.print_text("_ConnectCableText")
	# InGameTrade_PrepareTradeData
	var movie := TradeAnim.new()
	movie.player_species = give
	movie.enemy_species = receive
	movie.player_ot = state.player_name if m.ot_name == "" else m.ot_name
	movie.player_ot_id = state.player_id if m.ot_id < 0 else m.ot_id
	movie.enemy_ot = TRAINER_STRING
	movie.enemy_name = TRAINER_STRING
	movie.player_name = state.player_name
	movie.enemy_ot_id = ow.rng.randi_range(0, 0xFFFF)   # Random: hRandomAdd, hRandomSub
	ow.update_sprites = false   # LoadTradingGFXAndMonNames: wUpdateSpritesEnabled = $ff
	await movie.play()
	# RemovePokemon, AddPartyMon (no naming), InGameTrade_CopyDataToReceivedMon
	state.party.remove_at(idx)
	var got := PartyMon.create(receive, level)
	got.nickname = str(t["nick_ko"] if GameData.lang == "ko" else t["nick_en"])
	got.ot_name = TRAINER_STRING
	got.ot_id = movie.enemy_ot_id
	state.party.append(got)
	state.pokedex_seen[receive] = true
	state.pokedex_owned[receive] = true
	assert(not receive in TRADE_EVO_SPECIES, "InGameTrade_CheckForTradeEvo is not ported")
	await movie.clear_screen()
	await _restore_screen(ow, saved)
	# RedrawMapView: the map under the restored screen is already the current view
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("IN_GAME_TRADE %d %s -> %s nick=%s ot_id=%d" % [which, give, receive, got.nickname, got.ot_id])
	return "Thanks"


## InGameTrade_RestoreScreen: white out, the saved screen and sprites back, LoadGBPal, 10 frames.
static func _restore_screen(ow: Overworld, saved: PackedInt32Array) -> void:
	var S: GBScreen = GB.screen
	S.white_out()
	await GB.delay3()
	# RestoreScreenTilesAndReloadTilePatterns: ClearSprites, sprites on, the default palette, Delay3
	S.clear_sprites()
	ow.update_sprites = true
	S.swap_maps = false
	S.win_on = false
	S.wx = 7
	S.wy = 144
	ow._render()
	S.restore_bg(saved)
	SGB.run("DEFAULT")
	await GB.delay3()
	# ReloadTilesetTilePatterns, LoadScreenTilesFromBuffer2, Delay3, LoadGBPal
	await GB.delay3()
	S.normal_pals()
	await GB.frames(10)

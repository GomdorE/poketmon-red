## The trade movie (engine/movie/trade.asm InternalClockTradeAnim, trade2.asm): the
## player's Game Boy on the left, used by in-game trades.
##
## VRAM model during the movie: `S.bg` is the BG map at $9C00 (where the auto BG
## transfer of wTileMap goes, and what the text engine writes), `S.win` is $9800.
## LCDC with BG $9C00 / window $9800 draws them as they are; LCDC_DEFAULT
## (BG $9800 / window $9C00) swaps them (`S.swap_maps`). While hAutoBGTransferEnabled
## is off, wTileMap is kept apart in `tm` and `S.bg` keeps what VRAM held.
class_name TradeAnim
extends RefCounted

const GFX_BASE := 0x31          # vChars2 tile of TradingAnimationGraphics (game_boy + link_cable)
const CABLE_BALL_BASE := 0x7C   # vSprites tile of TradingAnimationGraphics2
const LOAD_MON_PARTY_SPRITE_GFX_FRAMES := 30   # 28 CopyVideoData calls of 4 or 8 tiles
const OAM_XFLIP := 0x20
const OAM_YFLIP := 0x40
## Trade_CircleOAMBlocks: [bubble tiles UL, UR, LL, LR], flips, upper-left x, y
const CIRCLE_BLOCKS := [
	[[0, 1, 2, 3], 0, 8, 8],
	[[1, 0, 3, 2], OAM_XFLIP, 24, 8],
	[[2, 3, 0, 1], OAM_YFLIP, 8, 24],
	[[3, 2, 1, 0], OAM_XFLIP | OAM_YFLIP, 24, 24],
]

var S: GBScreen
var player_species := ""     # wTradedPlayerMonSpecies
var enemy_species := ""      # wTradedEnemyMonSpecies
var player_ot := ""          # wTradedPlayerMonOT
var player_ot_id := 0        # wTradedPlayerMonOTID
var enemy_ot := ""           # wTradedEnemyMonOT
var enemy_ot_id := 0         # wTradedEnemyMonOTID
var player_name := ""        # wPlayerName
var enemy_name := ""         # wLinkEnemyTrainerName
var auto := true             # hAutoBGTransferEnabled (on from the dialogue before the movie)
var tm := PackedInt32Array() # wTileMap while the transfer is off
var moving_right := false    # wTradedMonMovingRight
var base_x := 0              # wBaseCoordX
var base_y := 0              # wBaseCoordY
var oam: Array = []          # the 20 circled-mon entries: {y, x, sheet, tile, alt, pal, flags}
var D: Dictionary


func _init() -> void:
	S = GB.screen
	D = GameData.trade


## InternalClockTradeAnim + TradeAnimCommon (InternalClockTradeFuncSequence).
func play() -> void:
	var saved_scx := S.scx
	var saved_scy := S.scy
	S.scx = 0
	S.scy = 0
	await _load_trading_gfx_and_mon_names()
	await _show_player_mon()
	await _draw_open_end_of_link_cable()
	await _animate_ball_entering_link_cable()
	await _anim_left_to_right()
	await GB.frames(100)
	await _show_cleared_window()
	await _print_went_to_text()
	await _print_for_sends_text()
	await _print_farewell_text()
	await _anim_right_to_left()
	await _show_cleared_window()
	await _draw_open_end_of_link_cable()
	await _show_enemy_mon()
	await GB.frames(100)
	_cleanup()
	S.scx = saved_scx
	S.scy = saved_scy


# --- wTileMap and the auto BG transfer --------------------------------------------

func _set_auto(on: bool) -> void:
	if on == auto:
		return
	if on:
		_transfer()
	else:
		tm = S.bg.duplicate()
	auto = on


## The auto BG transfer of the 20x18 wTileMap into the top-left of $9C00.
func _transfer() -> void:
	for y in 18:
		for x in 20:
			S.bg[y * GBScreen.MAP_W + x] = tm[y * GBScreen.MAP_W + x]


## Run a wTileMap drawing step: straight into S.bg while the transfer is on, else into `tm`.
func _tm(draw: Callable) -> void:
	if auto:
		draw.call()
		return
	var shown := S.bg
	S.bg = tm
	draw.call()
	tm = S.bg
	S.bg = shown


func _tile_map() -> PackedInt32Array:
	return S.bg if auto else tm


## ClearScreenArea on wTileMap (ClearMonPicFromTileMap from TradeHidePokemon).
func clear_area(x: int, y: int, w: int, h: int) -> void:
	_tm(func(): Text.clear_area(x, y, w, h))


## ClearScreen: blank wTileMap, Delay3.
func clear_screen() -> void:
	_clear_tile_map()
	await GB.delay3()


## Trade_ClearTileMap
func _clear_tile_map() -> void:
	clear_area(0, 0, 20, 18)


## Trade_CopyTileMapToVRAM: one Delay3 with the auto BG transfer on.
func _copy_tile_map_to_vram() -> void:
	_set_auto(true)
	await GB.delay3()
	_set_auto(false)


## CopyScreenTileBufferToVRAM to vBGMap0 ($9800 = S.win), six rows per frame.
func _copy_screen_to_bg_map0() -> void:
	var src := _tile_map()
	for third in 3:
		for y in range(third * 6, third * 6 + 6):
			for x in 20:
				S.win[y * GBScreen.MAP_W + x] = src[y * GBScreen.MAP_W + x]
		await GB.frame


## Trade_CopyCableTilesOffScreen: rows 4-5 of wTileMap go to $9C00 row 4 from column
## `col` (wrapping) through RedrawRowOrColumn in the next V-blank, then 10 frames.
func _copy_cable_tiles_off_screen(col: int) -> void:
	var src := _tile_map().duplicate()
	await GB.frame
	for half in 2:
		var y := 4 + half
		for i in 20:
			S.bg[y * GBScreen.MAP_W + ((col + i) & 31)] = src[y * GBScreen.MAP_W + i]
	await GB.frames(9)


## A TradingAnimationGraphics tile by its vChars2 tile id.
func _gfx(id: int) -> int:
	return S.tile("trade_gfx", id - GFX_BASE)


## CopyTileIDsFromList_ZeroBaseTileID
func _tile_ids(x: int, y: int, ids: Array, w: int, h: int) -> void:
	for j in h:
		for i in w:
			S.set_bg(x + i, y + j, _gfx(int(ids[j * w + i])))


## PlaceString with the HP bar / status tiles at $62-$7f (LoadHpBarAndStatusTilePatterns
## runs before the movie): "─", "№" and "<ID>" come from there.
func _place(x: int, y: int, s: String) -> void:
	StatusScreen._place(x, y, s)


# --- trade functions ---------------------------------------------------------------

## LoadTradingGFXAndMonNames
func _load_trading_gfx_and_mon_names() -> void:
	_clear_tile_map()
	# DisableLCD .. EnableLCD: the graphics are sheets; both BG maps are blanked
	S.clear_bg(Text.code_tile(Text.SPACE))
	S.clear_win(Text.code_tile(Text.SPACE))
	S.clear_sprites()
	Text.no_delay = true   # BIT_NO_TEXT_DELAY
	S.obp0 = GBScreen.pal_byte(0xF0 if S.sgb_on else 0xE4)
	_set_auto(false)
	Text.ram["wStringBuffer"] = GameData.mon_name(player_species)
	Text.ram["wNameBuffer"] = GameData.mon_name(enemy_species)
	Text.ram["wLinkEnemyTrainerName"] = enemy_name


## Trade_ShowPlayerMon
func _show_player_mon() -> void:
	# LCDC: window on ($9800), BG $9C00
	S.swap_maps = false
	S.win_on = true
	S.wy = 0x50
	S.wx = 0x86
	S.scx = 0x86
	_set_auto(false)
	_tm(func():
		Menu.draw_box(4, 0, 10, 6)
		_print_mon_info(0, player_species, Text.ram["wStringBuffer"], player_ot, player_ot_id))
	await _copy_screen_to_bg_map0()
	await clear_screen()
	await _load_mon_sprite(player_species)
	var a := 0x7E
	while true:
		await GB.frame
		S.wx = a
		S.scx = a
		a -= 2
		if a == 0:
			break
	await GB.frames(80)
	await BattleAnim.play_trade("TRADE_BALL_POOF_ANIM", self)
	await BattleAnim.play_trade("TRADE_BALL_DROP_ANIM", self)   # clears the mon pic
	Sound.play_cry(player_species)
	await Sound.wait_for_sfx()
	_set_auto(false)


## Trade_PrintPlayerMonInfoText / Trade_PrintEnemyMonInfoText at row `y`.
func _print_mon_info(y: int, species: String, mon_name: String, ot: String, ot_id: int) -> void:
	var ko := GameData.lang == "ko"
	if ko:
		# the Korean ROM's Trade_MonInfoText; its OT name at x 8 covers the "/" of "어버이/"
		# (8x16 glyphs), so the name goes one tile to the right
		_place(5, y, "──№<DOT><NEXT><NEXT>어버이/<NEXT>번호/")
	else:
		_place(5, y, "──№<DOT><NEXT><NEXT>OT/<NEXT><ID>№<DOT>")
	Text.place_string(9, y, "%03d" % int(GameData.pokemon[species]["dex"]))
	Text.place_string(5, y + 2, mon_name)
	Text.place_string(9 if ko else 8, y + 4, ot)
	Text.place_string(8, y + 6, "%05d" % ot_id)


## Trade_LoadMonSprite: the palette, the auto transfer toggled, the flipped front pic at (7, 2).
func _load_mon_sprite(species: String) -> void:
	SGB.run("POKEMON_WHOLE_SCREEN", {"species": species})
	_set_auto(not auto)
	_tm(func(): Title.draw_mon_pic(S, species, 7, 2, true))
	await GB.frames(10)


## Trade_DrawOpenEndOfLinkCable
func _draw_open_end_of_link_cable() -> void:
	_clear_tile_map()
	await _copy_screen_to_bg_map0()
	SGB.run("GENERIC")
	# pointless in the original: blank tiles over blank tiles
	await _copy_cable_tiles_off_screen(12)
	S.scx = 0xA0
	await GB.frame
	# LCDC: window off, BG $9C00
	S.swap_maps = false
	S.win_on = false
	_tm(func(): _tile_ids(6, 2, D["link_cable_tilemap"], 12, 3))
	await _copy_tile_map_to_vram()
	Sound.play_sfx("SFX_HEAL_HP")
	# twenty "add 4" with no frame in between
	S.scx = (S.scx + 20 * 4) & 0xFF


## Trade_AnimateBallEnteringLinkCable
func _animate_ball_entering_link_cable() -> void:
	await BattleAnim.play_trade("TRADE_BALL_SHAKE_ANIM", self)
	await GB.frames(10)
	S.obp0 = GBScreen.pal_byte(0xE4)
	var bulge := 0
	var x := 0x60
	var y := 0x20
	while true:
		# Trade_BallInsideLinkCableOAMBlock, then every entry gets tile $7e / $7f
		bulge ^= 1
		var v := S.tile("cable_ball", 0x7E + bulge - CABLE_BALL_BASE)
		S.set_sprite(0, x - 8, y - 16, v)
		S.set_sprite(1, x, y - 16, v, 0, true)
		S.set_sprite(2, x - 8, y - 8, v, 0, false, true)
		S.set_sprite(3, x, y - 8, v, 0, true, true)
		await GB.delay3()
		x += 4
		if x >= 0xA0:
			break
		Sound.play_sfx("SFX_TINK")
	S.clear_sprites()
	_set_auto(true)
	await clear_screen()
	await _copy_screen_to_bg_map0()
	await GB.delay3()
	_set_auto(false)


## Trade_ShowEnemyMon
func _show_enemy_mon() -> void:
	await BattleAnim.play_trade("TRADE_BALL_TILT_ANIM", self)
	await _show_cleared_window()
	_tm(func():
		Menu.draw_box(4, 10, 10, 6)
		_print_mon_info(10, enemy_species, Text.ram["wNameBuffer"], enemy_ot, enemy_ot_id))
	await _copy_tile_map_to_vram()
	_set_auto(true)
	await _load_mon_sprite(enemy_species)   # turns the transfer off: the pic shows after the poof
	await BattleAnim.play_trade("TRADE_BALL_POOF_ANIM", self)
	_set_auto(true)
	Sound.play_cry(enemy_species)
	await Sound.wait_for_sfx()
	await GB.frames(100)
	clear_area(4, 10, 12, 8)
	await Text.print_text("_TradeTakeCareText")
	await GB.frames(80)


## Trade_AnimLeftToRight: the mon moves from the left Game Boy to the right one.
func _anim_left_to_right() -> void:
	await _init_game_boy_transfer_gfx()
	moving_right = true
	S.obp0 = GBScreen.pal_byte(0xE4)
	base_x = 0x54
	base_y = 0x1C
	_write_circled_mon_oam(player_species)
	await _draw_left_game_boy()
	await _copy_tile_map_to_vram()
	_draw_cable_across_screen()
	await _copy_cable_tiles_off_screen(12)
	await _move_horizontal(6)
	_set_auto(true)
	_draw_cable_across_screen()
	await _move_horizontal(4)
	await _draw_right_game_boy()
	await _move_horizontal(6)
	_set_auto(false)
	await _move_vertical()
	S.clear_sprites()


## Trade_AnimRightToLeft: the mon moves from the right Game Boy to the left one.
func _anim_right_to_left() -> void:
	await _init_game_boy_transfer_gfx()
	moving_right = false
	base_x = 0x64
	base_y = 0x44
	_write_circled_mon_oam(enemy_species)
	await _draw_right_game_boy()
	await _copy_tile_map_to_vram()
	_draw_cable_across_screen()
	await _copy_cable_tiles_off_screen(20)
	await _move_vertical()
	await _move_horizontal(6)
	_set_auto(true)
	_draw_cable_across_screen()
	await _move_horizontal(4)
	await _draw_left_game_boy()
	await _move_horizontal(6)
	_set_auto(false)
	S.clear_sprites()


## Trade_InitGameboyTransferGfx
func _init_game_boy_transfer_gfx() -> void:
	_set_auto(true)
	await clear_screen()
	_set_auto(false)
	# Trade_LoadMonPartySpriteGfx: OBP1 %11010000, the icon tiles over 30 V-blanks
	S.obp1 = GBScreen.pal_byte(0xD0)
	await GB.frames(LOAD_MON_PARTY_SPRITE_GFX_FRAMES)
	await GB.frame
	# LCDC: window on ($9800), BG $9C00
	S.swap_maps = false
	S.win_on = true
	S.scx = 0
	S.wy = 0x90


## Trade_DrawLeftGameboy
func _draw_left_game_boy() -> void:
	_tm(func():
		Text.clear_area(0, 0, 20, 18)
		S.set_bg(11, 4, _gfx(0x5D))
		for i in 8:
			S.set_bg(12 + i, 4, _gfx(0x5E))
		_tile_ids(5, 3, D["game_boy_tilemap"], 6, 8)
		Menu.draw_box(4, 12, 7, 2)
		Text.place_string(5, 14, player_name))
	await GB.frame


## Trade_DrawRightGameboy
func _draw_right_game_boy() -> void:
	_tm(func():
		Text.clear_area(0, 0, 20, 18)
		for i in 14:
			S.set_bg(i, 4, _gfx(0x5E))
		S.set_bg(14, 4, _gfx(0x5F))
		for j in 4:
			S.set_bg(14, 5 + j, _gfx(0x61))
		S.set_bg(14, 9, _gfx(0x60))
		S.set_bg(13, 9, _gfx(0x5D))
		_tile_ids(7, 8, D["game_boy_tilemap"], 6, 8)
		Menu.draw_box(6, 0, 7, 2)
		Text.place_string(7, 2, enemy_name))
	await GB.frame


## Trade_DrawCableAcrossScreen
func _draw_cable_across_screen() -> void:
	_tm(func():
		Text.clear_area(0, 0, 20, 18)
		for i in 20:
			S.set_bg(i, 4, _gfx(0x5E)))


## Trade_AnimMonMoveHorizontal: `b` times, scroll 16 pixels (8 frames of 2) then
## Trade_AnimCircledMon.
func _move_horizontal(b: int) -> void:
	for k in b:
		for d in 8:
			S.scx = (S.scx + (2 if moving_right else -2)) & 0xFF
			await GB.frame
		_anim_circled_mon()


## Trade_AnimMonMoveVertical: the sprite itself moves over the cable's vertical segment.
func _move_vertical() -> void:
	if moving_right:
		await _move_sprite(4, 0)
		await _move_sprite(0, 10)
	else:
		await _move_sprite(0, -10)
		await _move_sprite(-4, 0)


func _move_sprite(dx: int, dy: int) -> void:
	base_x = dx
	base_y = dy
	for k in 4:
		_add_offsets_to_oam_coords()
		_anim_circled_mon()
		await GB.frames(8)


## Trade_AnimCircledMon: the link cable flashes (rBGP xor $3c) and the 20 entries
## switch to the other icon frame (tile xor ICONOFFSET).
func _anim_circled_mon() -> void:
	var b := S.bgp[0] | (S.bgp[1] << 2) | (S.bgp[2] << 4) | (S.bgp[3] << 6)
	S.bgp = GBScreen.pal_byte(b ^ 0x3C)
	for e in oam:
		e.alt = not e.alt
	_flush_oam()


## Trade_WriteCircledMonOAM: WriteMonPartySpriteOAMBySpecies (OAM 0-3 at Y 16, X 16),
## Trade_WriteCircleOAMBlock (OAM 4-19), then Trade_AddOffsetsToOAMCoords.
func _write_circled_mon_oam(species: String) -> void:
	oam = []
	var icon: Dictionary = PartyMenu.ICONS.get(GameData.pokemon[species].get("icon", "ICON_MON"), PartyMenu.ICONS["ICON_MON"])
	if icon.has("asym"):
		var a: Array = icon["asym"]
		for k in 4:
			oam.append({"y": 16 + (k / 2) * 8, "x": 16 + (k % 2) * 8, "rest": [a[0], int(a[1 + k])],
				"alt_tile": [a[0], int(a[1 + k])], "alt": false, "pal": 0, "flags": 0})
	else:
		var r: Array = icon["rest"]
		var t: Array = icon["alt"]
		for k in 4:
			var row := k / 2
			oam.append({"y": 16 + row * 8, "x": 16 + (k % 2) * 8, "rest": [r[0], int(r[1 + row])],
				"alt_tile": [t[0], int(t[1 + row])], "alt": false, "pal": 0, "flags": OAM_XFLIP if k % 2 else 0})
	for blk in CIRCLE_BLOCKS:
		var tiles: Array = blk[0]
		for k in 4:
			var tile := int(tiles[k])
			oam.append({"y": int(blk[3]) + (k / 2) * 8, "x": int(blk[2]) + (k % 2) * 8,
				"rest": ["trade_bubble", tile], "alt_tile": ["trade_bubble", tile + 4], "alt": false,
				"pal": 1, "flags": int(blk[1])})
	_add_offsets_to_oam_coords()


## Trade_AddOffsetsToOAMCoords: wBaseCoordY / wBaseCoordX added to all 20 entries.
func _add_offsets_to_oam_coords() -> void:
	for e in oam:
		e.y = (e.y + base_y) & 0xFF
		e.x = (e.x + base_x) & 0xFF
	_flush_oam()


func _flush_oam() -> void:
	for i in oam.size():
		var e: Dictionary = oam[i]
		var t: Array = e.alt_tile if e.alt else e.rest
		S.set_sprite(i, e.x - 8, e.y - 16, S.tile(str(t[0]), int(t[1])), e.pal,
			(e.flags & OAM_XFLIP) != 0, (e.flags & OAM_YFLIP) != 0)


## Trade_ShowClearedWindow: the window ($9C00, LCDC_DEFAULT) covers the BG entirely.
func _show_cleared_window() -> void:
	_set_auto(true)
	await clear_screen()
	S.swap_maps = true
	S.win_on = true
	S.wx = 7
	S.wy = 0
	S.scx = 0x90


## Trade_SlideTextBoxOffScreen: the window slides right until it is off the screen.
func _slide_text_box_off_screen() -> void:
	await GB.frames(50)
	while true:
		await GB.frame
		S.wx += 2
		if S.wx == 0xA1:
			break
	_clear_tile_map()
	await GB.frames(10)
	S.wx = 7


## PrintTradeWentToText
func _print_went_to_text() -> void:
	await Text.print_text("_TradeWentToText")
	await GB.frames(200)
	await _slide_text_box_off_screen()


## PrintTradeForSendsText
func _print_for_sends_text() -> void:
	await Text.print_text("_TradeForText")
	await GB.frames(80)
	await Text.print_text("_TradeSendsText")
	await GB.frames(80)


## PrintTradeFarewellText
func _print_farewell_text() -> void:
	await Text.print_text("_TradeWavesFarewellText")
	await GB.frames(80)
	await Text.print_text("_TradeTransferredText")
	await GB.frames(80)
	await _slide_text_box_off_screen()


## Trade_Cleanup: LoadGBPal and the letter delay back on.
func _cleanup() -> void:
	S.normal_pals()
	Text.no_delay = false

## The party menu (home/pokemon.asm DisplayPartyMenu / HandlePartyMenuInput and
## engine/menus/party_menu.asm DrawPartyMenu_ / RedrawPartyMenu_) with the
## animated party icons of engine/gfx/mon_icons.asm and the StartMenu_Pokemon
## loop of engine/menus/start_sub_menus.asm.
class_name PartyMenu
extends RefCounted

const MESSAGES := {"normal": "_PartyMenuNormalText", "item": "_PartyMenuItemUseText",
	"battle": "_PartyMenuBattleText", "swap": "_PartyMenuSwapMonText", "tmhm": "_PartyMenuUseTMText"}

## TMHM_PARTY_MENU: the move being taught; ABLE / NOT ABLE replaces the HP bar (CanLearnTM).
static var tm_move := ""

## MonPartySpritePointers: [sheet, top-left tile, bottom-left tile] of the resting
## frame (vSprites tiles ICON << 2) and the alternate frame (ICONOFFSET); the
## symmetric icons mirror the left tiles for the right half. The ball and the
## helix move down one pixel instead of changing tiles.
const ICONS := {
	"ICON_MON": {"rest": ["spr_monster", 12, 14], "alt": ["spr_monster", 0, 2]},
	"ICON_BALL": {"rest": ["spr_poke_ball", 0, 2], "alt": ["spr_poke_ball", 0, 2], "bounce": true},
	"ICON_HELIX": {"asym": ["spr_poke_ball", 4, 5, 6, 7], "bounce": true},
	"ICON_FAIRY": {"rest": ["spr_fairy", 12, 14], "alt": ["spr_fairy", 0, 2]},
	"ICON_BIRD": {"rest": ["spr_bird", 12, 14], "alt": ["spr_bird", 0, 2]},
	"ICON_WATER": {"rest": ["spr_seel", 0, 2], "alt": ["spr_seel", 12, 14]},
	"ICON_BUG": {"rest": ["icon_bug", 2, 3], "alt": ["icon_bug", 0, 1]},
	"ICON_GRASS": {"rest": ["icon_plant", 2, 3], "alt": ["icon_plant", 0, 1]},
	"ICON_SNAKE": {"rest": ["icon_snake", 0, 1], "alt": ["icon_snake", 2, 3]},
	"ICON_QUADRUPED": {"rest": ["icon_quadruped", 0, 1], "alt": ["icon_quadruped", 2, 3]},
}

static var saved_item := 0        # wPartyAndBillsPCSavedMenuItem
static var _anim_counter := 0     # wAnimCounter
static var _alt_frame := {}       # party index -> currently showing the alternate frame


## DisplayPartyMenu: white out, clear, draw and take input. `kind` is "normal",
## "item", "battle", "swap" or a text label starting with "_". `start` < 0 keeps
## the cursor where it was last left (wPartyAndBillsPCSavedMenuItem). With
## `swap_from` >= 0 the menu starts in the SWITCH mode (▷ on that mon).
## Returns the chosen index, or -1 for B.
## Korean layout: the HP bar ("HP:" + bar) starts here on the entry's second row.
const BAR_X_KO := 11


static func show(state: GameState, kind: String, start: int = -1, swap_from: int = -1) -> int:
	var S: GBScreen = GB.screen
	S.white_out()
	await GB.delay3()
	S.clear_sprites()
	await _draw(state, kind, swap_from, true)
	return await _input(state, kind, start, swap_from)


## GoBackToPartyMenu: redraw without the white-out flash, then take input.
static func go_back(state: GameState, kind: String, start: int = -1, swap_from: int = -1) -> int:
	await _draw(state, kind, swap_from, false)
	return await _input(state, kind, start, swap_from)


## RedrawPartyMenu_ with the message for `kind` (no input).
static func redraw(state: GameState, kind: String, _cur: int = 0, swap_from: int = -1) -> void:
	await _draw(state, kind, swap_from, false)


static func _message_label(kind: String) -> String:
	if kind.begins_with("_"):
		return kind
	return MESSAGES.get(kind, "_PartyMenuNormalText")


## DrawPartyMenu_ (full) / RedrawPartyMenu_: one entry per mon on rows 2i / 2i+1.
static func _draw(state: GameState, kind: String, swap_from: int, full: bool) -> void:
	var S: GBScreen = GB.screen
	if full:
		Text.clear_screen()
		S.clear_sprites()
	if kind != "swap":
		# ErasePartyMenuCursors
		for i in 6:
			Text.put(0, 1 + i * 2, Text.SPACE)
		var colors: Array = []
		var ko := GameData.lang == "ko"
		for i in state.party.size():
			var m: PartyMon = state.party[i]
			var y := i * 2
			# Korean: the 8x16 name takes both rows of the entry (top half on row 2i),
			# so the HP bar moves to the right of it and the HP numbers are left out
			Text.place_string(3, y + (1 if ko else 0), m.nickname)
			_place_icon(i, m.species, false)
			if swap_from >= 0 and swap_from == i:
				Text.put(0, y + 1, 0xEC)   # ▷ on the mon being moved
			var px := MonHud.hp_pixels(m.hp, m.max_hp)
			if kind == "tmhm":
				# .teachMoveMenu: "ABLE" / "NOT ABLE" one row down, nine columns right of the name
				var able: bool = tm_move in GameData.pokemon[m.species]["tmhm"]
				if ko:
					# two glyphs so the top halves clear the level on the row above
					Text.place_string(16, y + 1, "가능" if able else "불가")
				else:
					Text.place_string(12, y + 1, "ABLE" if able else "NOT ABLE")
			else:
				var st := MonHud.status_text(m)
				if st != "":
					if ko:
						Text.place_string(16, y, st.strip_edges())
					else:
						Text.place_string(17, y, st)
				MonHud.draw_hp_bar(BAR_X_KO if ko else 4, y + 1, px, true)
				if not ko:
					Text.place_string(13, y + 1, "%3d/%3d" % [m.hp, m.max_hp])
			colors.append(MonHud.bar_color(px))
			MonHud.draw_level(13, y, m.level)
		SGB.run("PARTY_MENU", {"hp_colors": colors, "bar_x": [BAR_X_KO + 1, BAR_X_KO + 7] if ko else []})
	# the message is printed without the letter delay
	var was_no_delay := Text.no_delay
	Text.no_delay = true
	Menu.message_box()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text(_message_label(kind)))
	Text.no_delay = was_no_delay
	await GB.delay3()
	S.normal_pals()


## WriteMonPartySpriteOAM: the 16x16 icon of party member `i` at (8, 16 i) in OAM 4i..4i+3.
static func _place_icon(i: int, species: String, alt: bool) -> void:
	var S: GBScreen = GB.screen
	var icon: Dictionary = ICONS.get(GameData.pokemon[species].get("icon", "ICON_MON"), ICONS["ICON_MON"])
	var x := 8
	var y := i * 16
	if icon.has("bounce") and alt:
		y += 1
	if icon.has("asym"):
		var a: Array = icon["asym"]
		var sheet: String = a[0]
		S.set_sprite(i * 4, x, y, S.tile(sheet, int(a[1])))
		S.set_sprite(i * 4 + 1, x + 8, y, S.tile(sheet, int(a[2])))
		S.set_sprite(i * 4 + 2, x, y + 8, S.tile(sheet, int(a[3])))
		S.set_sprite(i * 4 + 3, x + 8, y + 8, S.tile(sheet, int(a[4])))
	else:
		var f: Array = icon["alt"] if alt else icon["rest"]
		var sheet: String = f[0]
		var tl := S.tile(sheet, int(f[1]))
		var bl := S.tile(sheet, int(f[2]))
		S.set_sprite(i * 4, x, y, tl)
		S.set_sprite(i * 4 + 1, x + 8, y, tl, 0, true)
		S.set_sprite(i * 4 + 2, x, y + 8, bl)
		S.set_sprite(i * 4 + 3, x + 8, y + 8, bl, 0, true)
	_alt_frame[i] = alt


## AnimatePartyMon: only the selected mon animates; the period depends on its HP
## bar colour (5 / 16 / 32 frames per half cycle, one more off the SGB).
static func _animate(state: GameState, cur: int) -> void:
	if cur >= state.party.size():
		return
	var m: PartyMon = state.party[cur]
	var color := MonHud.bar_color(MonHud.hp_pixels(m.hp, m.max_hp))
	var c: int = MonHud.PARTY_MON_SPEEDS[color] + (0 if GB.screen.sgb_on else 1)
	var b := c * 2
	if _anim_counter == 0:
		for i in state.party.size():
			if _alt_frame.get(i, false):
				_place_icon(i, state.party[i].species, false)
	elif _anim_counter == c:
		_place_icon(cur, m.species, true)
	_anim_counter += 1
	if _anim_counter >= b:
		_anim_counter = 0


## HandlePartyMenuInput: wrapping cursor on the HP rows, A/B end the menu and
## leave the ▷ cursor behind; in the SWITCH mode A swaps and B cancels the swap.
static func _input(state: GameState, kind: String, start: int, swap_from: int) -> int:
	var count := state.party.size()
	if count == 0:
		return -1
	var cur := saved_item if start < 0 else start
	cur = clampi(cur, 0, count - 1)
	Menu.place_cursor(0, 1 + cur * 2)
	while true:
		await GB.frame
		_animate(state, cur)
		var keys := GB.joy5
		if keys == 0:
			continue
		var next := cur
		if keys & GB.UP:
			next = count - 1 if cur == 0 else cur - 1
		elif keys & GB.DOWN:
			next = 0 if cur == count - 1 else cur + 1
		if next != cur:
			Text.put(0, 1 + cur * 2, Text.SPACE)
			cur = next
			Menu.place_cursor(0, 1 + cur * 2)
		if keys & (GB.A | GB.B):
			Sound.play_sfx("SFX_PRESS_AB")
			# PlaceUnfilledArrowMenuCursor
			Menu.cursor_pos = Vector2i(-1, -1)
			Text.put(0, 1 + cur * 2, 0xEC)
			saved_item = cur
			if swap_from >= 0:
				if keys & GB.B:
					swap_from = -1
					await _draw(state, "normal", -1, false)
				else:
					await _switch(state, swap_from, cur)
					swap_from = -1
				Menu.place_cursor(0, 1 + cur * 2)
				continue
			if keys & GB.B:
				return -1
			return cur
	return -1


## SwitchPartyMon: swap the two party entries, clear both rows and icons, SFX_SWAP, redraw.
static func _switch(state: GameState, a: int, b: int) -> void:
	var S: GBScreen = GB.screen
	if a != b:
		var tmp: PartyMon = state.party[a]
		state.party[a] = state.party[b]
		state.party[b] = tmp
	for idx in [a, b]:
		Text.clear_area(0, idx * 2, 20, 2)
		for k in 4:
			S.set_sprite(idx * 4 + k, -16, -16, GBScreen.BLANK)
	await Sound.wait_for_sfx()
	Sound.play_sfx("SFX_SWAP")
	await _draw(state, "normal", -1, false)


## UpdateHPBar2 on the party menu row: the HP number counts one point at a time
## and the bar grows one pixel every two frames.
static func animate_hp(state: GameState, index: int, old_hp: int, new_hp: int) -> void:
	var m: PartyMon = state.party[index]
	var y := index * 2 + 1
	var ko := GameData.lang == "ko"
	var bar_x := BAR_X_KO if ko else 4
	var hp := old_hp
	var step := 1 if new_hp > old_hp else -1
	var px := MonHud.hp_pixels(hp, m.max_hp)
	while hp != new_hp:
		hp += step
		var target := MonHud.hp_pixels(hp, m.max_hp)
		if not ko:
			Text.place_string(13, y, "%3d" % (hp - step))
		await GB.frame
		while px != target:
			px += 1 if target > px else -1
			MonHud.draw_hp_bar(bar_x, y, px, true)
			await GB.frames(2)
	if not ko:
		Text.place_string(13, y, "%3d" % new_hp)
	MonHud.draw_hp_bar(bar_x, y, MonHud.hp_pixels(new_hp, m.max_hp), true)
	await GB.frames(2)
	await GB.delay3()


## StartMenu_Pokemon: the party menu, then STATS / SWITCH / CANCEL for the chosen mon.
## Leaves the screen whited out with no sprites; the caller redraws the overworld
## and the start menu, then restores the palettes (RestoreScreenTilesAndReloadTilePatterns + LoadGBPal).
static func start_menu_pokemon(state: GameState, ow) -> bool:
	var S: GBScreen = GB.screen
	if state.party.is_empty():
		return false
	var fresh := true
	var idx := -1
	var need_pick := true
	while true:
		if need_pick:
			if fresh:
				idx = await show(state, "normal")
				fresh = false
			else:
				idx = await go_back(state, "normal")
		need_pick = true
		if idx < 0:
			break
		# FIELD_MOVE_MON_MENU: the mon's field moves above STATS / SWITCH / CANCEL
		var saved := S.snapshot_bg()
		var fm := FieldMoves.of(state.party[idx])
		var nfm: int = fm.moves.size()
		var at := FieldMoves.draw_menu(fm)
		var keys := await Menu.handle_input(at.x, at.y, nfm + 3, GB.A | GB.B)
		var sel := Menu.current
		Menu.erase_cursor()
		S.restore_bg(saved)
		if keys & GB.B:
			continue
		if sel < nfm:
			# .choseOutOfBattleMove
			var result := await FieldMoves.use(state, ow, idx, str(fm.moves[sel]))
			if result == "close":
				# .goBackToMap: RestoreScreenTilesAndReloadTilePatterns + CloseTextDisplay
				S.clear_sprites()
				return true
			continue
		sel -= nfm
		if sel == 2:
			break
		if sel == 1:
			if state.party.size() < 2:
				fresh = true
				continue
			idx = await go_back(state, "swap", idx, idx)
			need_pick = false
			continue
		# STATS
		S.clear_sprites()
		await StatusScreen.show(state, idx)
		fresh = true
	# .exitMenu: GBPalWhiteOutWithDelay3
	S.white_out()
	await GB.delay3()
	S.clear_sprites()
	return false

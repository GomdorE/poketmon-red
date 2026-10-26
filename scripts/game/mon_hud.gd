## Shared HP bar / status / level drawing used by the party menu and the status
## screen (home/pokemon.asm DrawHPBar, PrintStatusCondition, PrintLevel and
## engine/gfx/hp_bar.asm HPBarLength). The HP bar tiles are the ones
## LoadHpBarAndStatusTilePatterns puts at $62 (gfx/font/font_battle_extra.2bpp).
class_name MonHud
extends RefCounted

const PARTY_MON_SPEEDS := [5, 16, 32]   # PartyMonSpeeds: icon animation period by HP bar colour


## Tile loaded at vChars2 $62.. by LoadHpBarAndStatusTilePatterns.
static func hp_tile(id: int) -> int:
	return GB.screen.tile("font_battle_extra", id - 0x62)


## HPBarLength: 48 * hp / max_hp pixels, at least 1 while the mon is alive.
static func hp_pixels(hp: int, max_hp: int) -> int:
	if hp <= 0:
		return 0
	return maxi(hp * 48 / maxi(max_hp, 1), 1)


## GetHealthBarColor: 0 green (>= 27 pixels), 1 yellow (>= 10), 2 red.
static func bar_color(pixels: int) -> int:
	return 0 if pixels >= 27 else (1 if pixels >= 10 else 2)


## DrawHPBar at (x, y): "HP:" ($71), $62, six bar tiles and the end tile
## ($6d on the status screen and in battle, $6c in the party menu).
static func draw_hp_bar(x: int, y: int, pixels: int, party_menu: bool) -> void:
	var S: GBScreen = GB.screen
	S.set_bg(x, y, hp_tile(0x71))
	S.set_bg(x + 1, y, hp_tile(0x62))
	for i in 6:
		var left := pixels - i * 8
		var t := 0x63
		if left >= 8:
			t = 0x6B
		elif left > 0:
			t = 0x63 + left
		S.set_bg(x + 2 + i, y, hp_tile(t))
	S.set_bg(x + 8, y, hp_tile(0x6C if party_menu else 0x6D))


## PrintStatusCondition: "FNT" for a fainted mon, else the ailment (PrintStatusAilment),
## "" when healthy. Three cells wide in both languages.
static func status_text(mon: PartyMon) -> String:
	var ko := GameData.lang == "ko"
	if mon.hp <= 0:
		return "기절 " if ko else "FNT"
	var s := mon.status
	if s & PartyMon.PSN:
		return "중독 " if ko else "PSN"
	if s & PartyMon.BRN:
		return "화상 " if ko else "BRN"
	if s & PartyMon.FRZ:
		return "얼음 " if ko else "FRZ"
	if s & PartyMon.PAR:
		return "마비 " if ko else "PAR"
	if s & PartyMon.SLP_MASK:
		return "잠듦 " if ko else "SLP"
	return ""


## PrintLevel: the ":L" tile (BattleHudTiles1 tile 1, vChars2 $6e) then the level, left aligned.
static func draw_level(x: int, y: int, level: int) -> void:
	var S: GBScreen = GB.screen
	if level >= 100:
		S.set_bg(x - 1, y, S.tile("battle_hud_1", 1))
		Text.place_string(x, y, str(level))
	else:
		S.set_bg(x, y, S.tile("battle_hud_1", 1))
		Text.place_string(x + 1, y, str(level))

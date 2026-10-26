## A Pokédex entry page (engine/menus/pokedex.asm ShowPokedexDataInternal).
class_name PokedexPage
extends RefCounted

var S: GBScreen


func show(species: String) -> void:
	S = GB.screen
	var p: Dictionary = GameData.pokemon[species]
	var saved_sprites := S.oam.duplicate(true)
	S.white_out()
	S.clear_sprites()
	Text.clear_screen()
	SGB.run("POKEDEX", {"species": species})
	var dex := func(t: int) -> int: return S.tile("pokedex_tiles", t - 0x60)
	# borders
	for x in range(1, 19):
		S.set_bg(x, 0, dex.call(0x64))
		S.set_bg(x, 17, dex.call(0x6F))
	for y in range(1, 17):
		S.set_bg(0, y, dex.call(0x66))
		S.set_bg(19, y, dex.call(0x67))
	S.set_bg(0, 0, dex.call(0x63))
	S.set_bg(19, 0, dex.call(0x65))
	S.set_bg(0, 17, dex.call(0x6C))
	S.set_bg(19, 17, dex.call(0x6E))
	var divider := [0x68, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x6B, 0x6B, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6B, 0x69, 0x6A]
	for i in 20:
		S.set_bg(i, 9, dex.call(divider[i]))
	if GameData.lang == "ko":
		Text.place_string(9, 6, "키   ?′??″")
		Text.place_string(9, 8, "무게   ???파운드")
	else:
		Text.place_string(9, 6, "HT  ?′??″")
		Text.place_string(9, 8, "WT   ???lb")
	Text.place_string(9, 2, GameData.mon_name(species))
	var entry: Dictionary = p["dex_entry"]
	Text.place_string(9, 4, entry.get("species", ""))
	# №. and the dex number
	Text.put(2, 8, 0x74)
	Text.put(3, 8, 0xF2)
	Text.place_string(4, 8, "%03d" % p["dex"])
	await GB.delay3()
	S.normal_pals()
	Title.draw_mon_pic(S, species, 1, 1, true)
	# height and weight
	Text.place_string(12, 6, "%2d" % entry.get("height_ft", 0))
	Text.place_string(15, 6, "%02d" % entry.get("height_in", 0))
	var weight: int = entry.get("weight", 0)
	var txt := "%5d" % weight
	# the last digit moves right to make room for the decimal point
	Text.place_string(11, 8, txt.substr(0, 4))
	Text.put(15, 8, 0xF2)
	Text.place_string(16, 8, txt.substr(4, 1))
	if weight < 10:
		Text.place_string(14, 8, "0")
	Text.cursor = Vector2i(1, 11)
	Text.single_spaced = true
	await Text.run_commands(GameData.text(entry.get("text", "")))
	Text.single_spaced = false
	await GB.wait_press(GB.A | GB.B)
	S.white_out()
	Text.clear_screen()
	S.normal_pals()
	S.oam = saved_sprites

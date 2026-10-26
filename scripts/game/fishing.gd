## The fishing rods (engine/items/item_effects.asm ItemUseOldRod / GoodRod / SuperRod,
## FishingInit, RodResponse; engine/overworld/player_animations.asm FishingAnim).
class_name Fishing
extends RefCounted

# FishingRodOAM: screen x, y (OAM - (8, 16)), tile of fishing_rod.2bpp, x flip; by facing
const ROD_OAM := {
	Overworld.FACE_DOWN: [68, 75, 0, false], Overworld.FACE_UP: [68, 52, 0, false],
	Overworld.FACE_LEFT: [56, 64, 1, false], Overworld.FACE_RIGHT: [80, 64, 1, true],
}
# the fishing pose tiles replacing the lower half of the standing frame
const POSE_SHEET := {
	Overworld.FACE_DOWN: "red_fish_front", Overworld.FACE_UP: "red_fish_back",
	Overworld.FACE_LEFT: "red_fish_side", Overworld.FACE_RIGHT: "red_fish_side",
}
const ROD_SLOT := 35   # OAM 39 in the original; kept clear of the emotion bubble (36-39)


## Returns true when the rod was used (the start menu closes); a bite sets the battle.
static func use_rod(state: GameState, ow, item: String) -> bool:
	# FishingInit: water or shore in front, not surfing, not in battle
	if not FieldMoves.is_next_tile_shore_or_water(ow) or state.walk_bike_surf == 2:
		await Text.print_text("_ItemUseNotTimeText")
		return false
	ow.reload_map_view()
	Text.ram["wStringBuffer"] = GameData.item_name(item)
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text("_ItemUseText001"))
	Text.cursor = Vector2i(1, 16)
	await Text.run_commands(GameData.text("_ItemUseText002"))
	Sound.play_sfx("SFX_HEAL_AILMENT")
	await GB.frames(80)
	# RodResponse: 1 = a bite, 0 = no bite, 2 = nothing here
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var response := 0
	var level := 0
	var species := ""
	var rods: Dictionary = GameData.wild.get("rods", {})
	match item:
		"OLD_ROD":
			response = 1
			level = 5
			species = "MAGIKARP"
		"GOOD_ROD":
			while true:
				var r := rng.randi_range(0, 255)
				if r & 1:
					break   # no bite
				var a := (r >> 1) & 3
				if a >= 2:
					continue
				var e: Array = rods["good"][a]
				level = int(e[0])
				species = str(e[1])
				response = 1
				break
		"SUPER_ROD":
			var group: Array = rods["super"].get(ow.map_id, [])
			if group.is_empty():
				response = 2
			else:
				while true:
					var r2 := rng.randi_range(0, 255)
					if r2 & 1:
						break
					var a2 := (r2 >> 1) & 3
					if a2 >= group.size():
						continue
					level = int(group[a2][0])
					species = str(group[a2][1])
					response = 1
					break
	var saved: int = state.walk_bike_surf
	state.walk_bike_surf = 0
	await _fishing_anim(ow, response)
	state.walk_bike_surf = saved
	if response == 1:
		ow.battle_request = {"wild": true, "species": species, "level": level}
	return true


## FishingAnim: the fishing pose and the rod, 100 frames; on a bite the player and the
## rod shake ten times and the "!" bubble shows; then the text.
static func _fishing_anim(ow, response: int) -> void:
	var S: GBScreen = GB.screen
	await GB.frames(10)
	var facing: int = ow.player.facing
	var fr: Array = Overworld._frame_for(facing, 0, 6)
	var top: int = int(fr[0]) * 4
	var pose: String = POSE_SHEET[facing]
	var xf: bool = fr[1]
	var tiles := [S.tile("spr_red", top), S.tile("spr_red", top + 1), S.tile(pose, 0), S.tile(pose, 1)]
	ow.player_anim = {"tiles": tiles, "xflip": xf, "x": 0x40, "y": 0x3C}
	var rod: Array = ROD_OAM[facing]
	var rod_y: int = rod[1]
	_draw_rod(S, rod, rod_y)
	ow._render()
	await GB.frames(100)
	var label := "_NoNibbleText"
	if response == 2:
		label = "_NothingHereText"
	elif response == 1:
		for k in 10:
			ow.player_anim.y = int(ow.player_anim.y) ^ 1
			rod_y = ((rod_y + 16) ^ 1) - 16
			_draw_rod(S, rod, rod_y)
			ow._render()
			await GB.delay3()
		if facing == Overworld.FACE_UP:
			S.set_sprite(ROD_SLOT, -16, -16, GBScreen.BLANK)
		await ow.emotion_bubble(0, "shock")
		if facing == Overworld.FACE_UP:
			rod_y = 0x44 - 16
		_draw_rod(S, rod, rod_y)
		ow._render()
		label = "_ItsABiteText"
	await Text.print_text(label)
	S.set_sprite(ROD_SLOT, -16, -16, GBScreen.BLANK)
	ow.player_anim = {}
	ow._render()


static func _draw_rod(S: GBScreen, rod: Array, y: int) -> void:
	S.set_sprite(ROD_SLOT, int(rod[0]), y, S.tile("fishing_rod", int(rod[2])), 0, bool(rod[3]))

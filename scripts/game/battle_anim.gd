## The battle animation engine (engine/battle/animations.asm): MoveAnimation /
## PlayAnimation run a move's command stream of subanimations (OAM frame blocks
## drawn from the move animation tilesets) and special effects, then
## PlayApplyingAttackAnimation shakes the screen or blinks the enemy. The tables
## come from assets/data/battle_anims.json (tools/export_battle_anims.py).
class_name BattleAnim
extends RefCounted

const SUBANIMTYPE := {"SUBANIMTYPE_NORMAL": 0, "SUBANIMTYPE_HVFLIP": 1, "SUBANIMTYPE_HFLIP": 2,
	"SUBANIMTYPE_COORDFLIP": 3, "SUBANIMTYPE_REVERSE": 4, "SUBANIMTYPE_ENEMY": 5}
const NORMAL := 0
const HVFLIP := 1
const HFLIP := 2
const COORDFLIP := 3
const REVERSE := 4
const ENEMY := 5
const OAM_OBP1 := 0x10
const OAM_XFLIP := 0x20
const OAM_YFLIP := 0x40
const OAM_BEHIND_BG := 0x80
const ANIM_TILE_BASE := 0x31   # vSprites tile where the move animation tileset is loaded
const BALL_TILE := 0x7A - ANIM_TILE_BASE
const LEAF_TILE := 0x37 - ANIM_TILE_BASE
const PETAL_TILE := 0x71 - ANIM_TILE_BASE
const DROPLET_TILE := 0x71 - ANIM_TILE_BASE

## AnimationTypePointerTable
const TYPE_SHAKE_SCREEN_VERTICALLY := 1
const TYPE_SHAKE_SCREEN_HORIZONTALLY_HEAVY := 2
const TYPE_SHAKE_SCREEN_HORIZONTALLY_SLOW := 3
const TYPE_BLINK_ENEMY_MON_SPRITE := 4
const TYPE_SHAKE_SCREEN_HORIZONTALLY_LIGHT := 5
const TYPE_SHAKE_SCREEN_HORIZONTALLY_SLOW_2 := 6

const FLASH_SCREEN_LONG_MONOCHROME := [0xE5, 0xF9, 0xFF, 0xF9, 0xE5, 0xE4, 0x90, 0x40, 0x00, 0x40, 0x90, 0xE4]
const FLASH_SCREEN_LONG_SGB := [0xF8, 0xFC, 0xFF, 0xFC, 0xF8, 0xE4, 0x90, 0x40, 0x00, 0x40, 0x90, 0xE4]
const SPIRAL_BALL_COORDS := [[0x38, 0x28], [0x40, 0x18], [0x50, 0x10], [0x60, 0x18], [0x68, 0x28], [0x60, 0x38], [0x50, 0x40],
	[0x40, 0x38], [0x40, 0x28], [0x46, 0x1E], [0x50, 0x18], [0x5B, 0x1E], [0x60, 0x28], [0x5B, 0x32], [0x50, 0x38], [0x46, 0x32],
	[0x48, 0x28], [0x50, 0x20], [0x58, 0x28], [0x50, 0x30], [0x50, 0x28]]
const FALLING_DELTA_XS := [0, 1, 3, 5, 7, 9, 11, 13, 15]
const FALLING_INITIAL_XS := [0x38, 0x40, 0x50, 0x60, 0x70, 0x88, 0x90, 0x56, 0x67, 0x4A, 0x77, 0x84, 0x98, 0x32, 0x22, 0x5C, 0x6C, 0x7D, 0x8E, 0x99]
const FALLING_INITIAL_MOVEMENT := [0x00, 0x84, 0x06, 0x81, 0x02, 0x88, 0x01, 0x83, 0x05, 0x89, 0x09, 0x80, 0x07, 0x87, 0x03, 0x82, 0x04, 0x85, 0x08, 0x86]
const WAVY_LINE_OFFSETS := [0, 0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 2, 1, 1, 1, 0, 0, 0, 0, 0, -1, -1, -1, -2, -2, -2, -2, -2, -1, -1, -1]

var b: Battle
var S: GBScreen
var D: Dictionary
var player_turn := true     # hWhoseTurn == 0
var anim_id := 0            # wAnimationID
var anim_type := 0          # wAnimationType
var anim_pal := 0xE4        # wAnimPalette
var damage_mult := 10       # wDamageMultipliers (tenths)
var sub_transform := NORMAL
var sub_counter := 0        # wSubAnimCounter
var sub_index := 0          # wSubAnimSubEntryAddr as an entry index
var sub_entries: Array = []
var sub_delay := 0          # wSubAnimFrameDelay
var tileset := 0            # wWhichBattleAnimTileset
var fb_dest := 0            # wFBDestAddr as an OAM index
var num_shakes := 0         # wNumShakes
var cur_item := "POKE_BALL"
var is_trainer_battle := false
var ids := {}               # anim name -> id
var move_by_id := {}        # move id -> move key


func _init(battle: Battle, turn_player: bool) -> void:
	b = battle
	S = GB.screen
	D = GameData.battle_anims
	ids = D["anim_ids"]
	player_turn = turn_player
	is_trainer_battle = not battle.is_wild
	for key in GameData.moves.keys():
		move_by_id[int(GameData.moves[key]["id"])] = key


static func id_of(name: String) -> int:
	return int(GameData.battle_anims["anim_ids"].get(name, 0))


## PlayMoveAnimation: Delay3, then MoveAnimation for a move or an *_ANIM id.
static func play(battle: Battle, anim: String, type: int, turn_player: bool, mult: int = 0) -> void:
	var a := BattleAnim.new(battle, turn_player)
	a.anim_id = id_of(anim)
	a.anim_type = type
	a.damage_mult = mult
	await GB.delay3()
	await a._move_animation()


## MoveAnimation for the ball toss: TossBallAnimation with wPokeBallAnimData.
static func toss_ball(battle: Battle, anim_data: int, item: String) -> void:
	var a := BattleAnim.new(battle, true)
	a.cur_item = item
	a.anim_id = id_of("TOSS_ANIM")
	await Sound.wait_for_sfx()
	a._set_animation_palette()
	await a._toss_ball_animation(anim_data)
	await Sound.wait_for_sfx()
	a._finish()


# --- MoveAnimation -------------------------------------------------------------------

func _move_animation() -> void:
	await Sound.wait_for_sfx()
	_set_animation_palette()
	if anim_id == 0:
		await Sound.wait_for_sfx()
		_finish()
		return
	if not Settings.battle_animation_on():
		await GB.frames(30)   # BATTLE ANIMATION OFF
	else:
		_share_move_animations()
		await _play_animation(anim_id)
	await _play_applying_attack_animation()
	await Sound.wait_for_sfx()
	_finish()


func _finish() -> void:
	sub_index = 0
	sub_transform = NORMAL


## SetAnimationPalette: the animation sprites use $f0 on the SGB, $e4 otherwise; OBP1 = $6c.
func _set_animation_palette() -> void:
	anim_pal = 0xF0 if S.sgb_on else 0xE4
	S.obp0 = GBScreen.pal_byte(0xE4)
	S.obp1 = GBScreen.pal_byte(0x6C)


## ShareMoveAnimations: the enemy's Amnesia and Rest reuse the confusion / sleep animations.
func _share_move_animations() -> void:
	if player_turn:
		return
	if anim_id == id_of("AMNESIA"):
		anim_id = id_of("CONF_ANIM")
	elif anim_id == id_of("REST"):
		anim_id = id_of("SLP_ANIM")


## PlayAnimation: the command stream of `which`.
func _play_animation(which: int) -> void:
	sub_transform = NORMAL
	var cmds: Array = D["anims"].get(str(which), [])
	for c in cmds:
		var cmd: Dictionary = c
		var sound := int(cmd.get("sound", 0))
		if cmd.has("se"):
			if sound != 0:
				_play_move_sound(sound)
			await _special_effect(str(cmd["se"]))
		else:
			sub_delay = int(cmd["delay"])
			tileset = int(cmd["tileset"])
			var saved_obp0 := S.obp0.duplicate()
			S.obp0 = GBScreen.pal_byte(anim_pal)
			_load_subanimation(int(cmd["sub"]))
			await _play_subanimation(sound)
			S.obp0 = saved_obp0


## GetMoveSound + PlaySound: the move's sound effect; Growl and Roar play the user's cry.
func _play_move_sound(move_id: int) -> void:
	var move: String = str(move_by_id.get(move_id, ""))
	if move == "":
		return
	if anim_id == id_of("GROWL") or anim_id == id_of("ROAR"):
		var m: Array = Sound.move_sfx[move_id - 1]
		var mon: PartyMon = b.player_mon if player_turn else b.enemy_mon
		Sound.play_cry_modified(mon.species, int(m[1]), int(m[2]))
		return
	Sound.play_move_sfx(move)


## LoadSubanimation: the entry list, the transform for this turn and the start entry.
func _load_subanimation(sub: int) -> void:
	var entry: Dictionary = D["subanims"][sub]
	sub_entries = entry["entries"]
	sub_counter = sub_entries.size()
	var type: int = int(SUBANIMTYPE[str(entry["type"])])
	if type == ENEMY:
		sub_transform = HFLIP if player_turn else NORMAL   # GetSubanimationTransform2
	else:
		sub_transform = NORMAL if player_turn else type     # GetSubanimationTransform1
	sub_index = sub_counter - 1 if sub_transform == REVERSE else 0


## PlaySubanimation: one frame block per entry, with the animation's special effect.
func _play_subanimation(sound: int) -> void:
	if sound != 0:
		_play_move_sound(sound)
	fb_dest = 0
	while true:
		var e: Array = sub_entries[sub_index]
		await _draw_frame_block(int(e[0]), int(e[1]), int(e[2]))
		await _special_effect_by_animation_id()
		sub_counter -= 1
		if sub_counter == 0:
			return
		sub_index += -1 if sub_transform == REVERSE else 1


## DrawFrameBlock: the sprites of a frame block at the base coordinate, transformed.
func _draw_frame_block(fb: int, base: int, mode: int) -> void:
	var sprites: Array = D["frame_blocks"][fb]
	var bc: Array = D["base_coords"][base]
	var base_y := int(bc[0])
	var base_x := int(bc[1])
	var n := 0
	for sp in sprites:
		var s: Array = sp
		var dy := int(s[0])
		var dx := int(s[1])
		var tile := int(s[2])
		var flags := int(s[3])
		var y := 0
		var x := 0
		match sub_transform:
			HVFLIP:
				y = (136 - ((base_y + dy) & 0xFF)) & 0xFF
				x = (168 - ((base_x + dx) & 0xFF)) & 0xFF
				var f := flags & (OAM_XFLIP | OAM_YFLIP)
				var nf := 0
				if f == 0:
					nf = OAM_XFLIP | OAM_YFLIP
				elif f == OAM_XFLIP:
					nf = OAM_YFLIP
				elif f == OAM_YFLIP:
					nf = OAM_XFLIP
				flags = nf
			HFLIP:
				y = (base_y + dy + 40) & 0xFF
				x = (168 - ((base_x + dx) & 0xFF)) & 0xFF
				flags ^= OAM_XFLIP
			COORDFLIP:
				y = ((136 - base_y) + dy) & 0xFF
				x = ((168 - base_x) + dx) & 0xFF
			_:
				y = (base_y + dy) & 0xFF
				x = (base_x + dx) & 0xFF
		_write_oam(fb_dest + n, y, x, tile, flags)
		n += 1
	if mode == 2:
		fb_dest += n
		return
	await GB.frames(sub_delay)
	if mode == 3:
		fb_dest += n
		return
	if mode == 4:
		return
	if anim_id != id_of("GROWL"):
		await _clean_oam()
	fb_dest = 0


## An OAM entry in hardware coordinates (Y + 16, X + 8) with the animation tileset tile.
func _write_oam(index: int, y: int, x: int, tile: int, flags: int) -> void:
	var sheet := "move_anim_%d" % (0 if tileset == 2 else tileset)
	var v := S.tile(sheet, tile) if tile >= 0 else GBScreen.BLANK
	S.set_sprite(index, x - 8, y - 16, v, 1 if flags & OAM_OBP1 else 0, (flags & OAM_XFLIP) != 0, (flags & OAM_YFLIP) != 0, (flags & OAM_BEHIND_BG) != 0)


## AnimationCleanOAM: one frame, then ClearSprites.
func _clean_oam() -> void:
	await GB.frame
	S.clear_sprites()


# --- AnimationIdSpecialEffects ------------------------------------------------------

func _special_effect_by_animation_id() -> void:
	var name: String = str(D["anim_special_effects"].get(str(anim_id), ""))
	match name:
		"AnimationFlashScreen":
			await _flash_screen()
		"DoGrowlSpecialEffects":
			# copy the musical note (OAM 0-3) to OAM 4-7; clean up at the end
			for k in 4:
				if k < S.oam.size() and S.oam[k] != null:
					var o: Dictionary = S.oam[k]
					S.set_sprite(4 + k, o.x, o.y, o.v, o.pal, o.xflip, o.yflip, o.prio)
			if sub_counter == 1:
				await _clean_oam()
		"DoBlizzardSpecialEffects":
			if sub_counter in [13, 9, 5, 1]:
				await _flash_screen()
		"FlashScreenEveryFourFrameBlocks":
			if (sub_counter & 3) == 0:
				await _flash_screen()
		"FlashScreenEveryEightFrameBlocks":
			if (sub_counter & 7) == 0:
				await _flash_screen()
		"DoExplodeSpecialEffects":
			if sub_counter == 1:
				_hide_pic(true)
			elif (sub_counter & 3) == 0:
				await _flash_screen()
		"DoRockSlideSpecialEffects":
			if sub_counter >= 12:
				return
			if sub_counter >= 8:
				await _shake_screen_horizontally(1)
				await _shake_screen_vertically(1)
			elif sub_counter == 1:
				await _flash_screen()
		"DoBallTossSpecialEffects":
			if cur_item == "MASTER_BALL" or cur_item == "ULTRA_BALL":
				S.obp0 = GBScreen.pal_byte(_pal_to_byte(S.obp0) ^ 0x3C)
			if sub_counter == 11:
				Sound.play_sfx("SFX_BALL_TOSS")
			if is_trainer_battle and sub_counter == 3:
				sub_counter = 2   # the blocked throw is one frame block shorter
		"DoBallShakeSpecialEffects":
			if sub_counter == 4:
				Sound.play_sfx("SFX_TINK")
				await GB.frames(40)
			if sub_counter == 1:
				num_shakes -= 1
				if num_shakes > 0:
					# restart the four-entry shake subanimation
					sub_index = -1
					sub_counter = 5
		"DoPoofSpecialEffects":
			if sub_counter == 5:
				Sound.play_sfx("SFX_BALL_POOF")
		"TailWhipAnimationUnused":
			sub_counter = 1
			await GB.frames(20)
		_:
			pass


static func _pal_to_byte(p: PackedInt32Array) -> int:
	return p[0] | (p[1] << 2) | (p[2] << 4) | (p[3] << 6)


# --- special effects (SpecialEffectPointers) -----------------------------------------

func _special_effect(name: String) -> void:
	match name:
		"SE_DARK_SCREEN_FLASH":
			await _flash_screen()
		"SE_DARK_SCREEN_PALETTE":
			_set_bg_palette(0x6F, 0x6F)
		"SE_RESET_SCREEN_PALETTE":
			_set_bg_palette(0xE4, 0xE4)
		"SE_SHAKE_SCREEN":
			await _shake_screen_horizontally(8)
		"SE_WATER_DROPLETS_EVERYWHERE":
			await _water_droplets_everywhere()
		"SE_DARKEN_MON_PALETTE":
			_set_bg_palette(0xF9, 0xF4)
		"SE_FLASH_SCREEN_LONG":
			await _flash_screen_long()
		"SE_SLIDE_MON_UP":
			await _slide_mon_up()
		"SE_SLIDE_MON_DOWN":
			await _slide_mon_down(player_turn)
		"SE_FLASH_MON_PIC":
			_change_mon_pic(player_turn)
		"SE_SLIDE_MON_OFF":
			await _slide_mon_off(player_turn, 8, 3)
		"SE_BLINK_MON":
			await _blink_mon(player_turn)
		"SE_MOVE_MON_HORIZONTALLY":
			await _move_mon_horizontally()
		"SE_RESET_MON_POSITION":
			await _reset_mon_position()
		"SE_LIGHT_SCREEN_PALETTE":
			_set_bg_palette(0x90, 0x90)
		"SE_HIDE_MON_PIC":
			_hide_pic(player_turn)
		"SE_SQUISH_MON_PIC":
			await _squish_mon_pic()
		"SE_SHOOT_BALLS_UPWARD":
			await _shoot_balls_upward()
		"SE_SHOOT_MANY_BALLS_UPWARD":
			await _shoot_many_balls_upward()
		"SE_BOUNCE_UP_AND_DOWN":
			for i in 5:
				await _slide_mon_down(player_turn)
			await _show_mon_pic(player_turn)
		"SE_MINIMIZE_MON":
			# AnimationMinimizeMon: the pic is replaced by the tiny minimized sprite
			_hide_pic(player_turn)
			await _draw_minimized(player_turn)
			await GB.delay3()
		"SE_SLIDE_MON_DOWN_AND_HIDE":
			await _slide_mon_down_and_hide()
		"SE_TRANSFORM_MON":
			_transform_mon()
		"SE_LEAVES_FALLING":
			var saved_obp0 := S.obp0.duplicate()
			S.obp0 = GBScreen.pal_byte(anim_pal)
			await _falling_objects(LEAF_TILE, 3)
			S.obp0 = saved_obp0
		"SE_PETALS_FALLING":
			await _falling_objects(PETAL_TILE, 20)
			S.clear_sprites()
		"SE_SLIDE_MON_HALF_OFF":
			await _slide_mon_off(player_turn, 4, 4)
			await GB.delay3()
		"SE_SHAKE_ENEMY_HUD", "SE_SHAKE_ENEMY_HUD_2":
			await _shake_enemy_hud()
		"SE_SPIRAL_BALLS_INWARD":
			await _spiral_balls_inward()
		"SE_DELAY_ANIMATION_10":
			await GB.frames(10)
		"SE_FLASH_ENEMY_MON_PIC":
			_change_mon_pic(not player_turn)
		"SE_HIDE_ENEMY_MON_PIC":
			_hide_pic(not player_turn)
			await GB.delay3()
		"SE_BLINK_ENEMY_MON":
			await _blink_mon(not player_turn)
		"SE_SHOW_MON_PIC":
			await _show_mon_pic(player_turn)
		"SE_SHOW_ENEMY_MON_PIC":
			await _show_mon_pic(not player_turn)
		"SE_SLIDE_ENEMY_MON_OFF":
			await _slide_mon_off(not player_turn, 8, 3)
		"SE_SHAKE_BACK_AND_FORTH":
			await _shake_back_and_forth()
		"SE_SUBSTITUTE_MON":
			await _substitute()
		"SE_WAVY_SCREEN":
			await _wavy_screen()
		_:
			push_warning("BattleAnim: unknown special effect " + name)


## AnimationFlashScreen: inverted palette for 2 frames, white for 2 frames.
func _flash_screen() -> void:
	var saved := S.bgp.duplicate()
	S.bgp = GBScreen.pal_byte(0x1B)
	await GB.frames(2)
	S.bgp = GBScreen.pal_byte(0x00)
	await GB.frames(2)
	S.bgp = saved


## SetAnimationBGPalette: the DMG value, or the SGB one on the Super Game Boy.
func _set_bg_palette(dmg: int, sgb: int) -> void:
	S.bgp = GBScreen.pal_byte(sgb if S.sgb_on else dmg)


## AnimationFlashScreenLong: three passes through the palette table.
func _flash_screen_long() -> void:
	var table: Array = FLASH_SCREEN_LONG_SGB if S.sgb_on else FLASH_SCREEN_LONG_MONOCHROME
	var counter := 3
	while counter > 0:
		for p in table:
			S.bgp = GBScreen.pal_byte(int(p))
			await GB.frames(2 if counter == 3 else 1)
		counter -= 1


## PredefShakeScreenVertically: the window moves down by b, back, by b-1, ...
func _shake_screen_vertically(amount: int) -> void:
	var v := amount
	while v > 0:
		S.scy = (256 - v) & 0xFF
		await GB.frames(3)
		S.scy = 0
		await GB.frames(3)
		v -= 1
	S.scy = 0


## PredefShakeScreenHorizontally: the window moves right by b, back, by b-1, ...
func _shake_screen_horizontally(amount: int) -> void:
	var v := amount
	while v > 0:
		S.scx = (256 - v) & 0xFF
		await GB.frames(4)
		await GB.frames(1)
		S.scx = 0
		await GB.frames(4)
		v -= 1
	S.scx = 0


## AnimationShakeScreenHorizontallySlow: b steps right, b steps back, c times.
func _shake_screen_horizontally_slow(steps: int, times: int) -> void:
	var off := 0
	for t in times:
		for i in steps:
			off += 1
			S.scx = (256 - off) & 0xFF
			await GB.frames(2)
		for i in steps:
			off -= 1
			S.scx = (256 - off) & 0xFF
			await GB.frames(2)
	S.scx = 0


## PlayApplyingAttackAnimation (AnimationTypePointerTable).
func _play_applying_attack_animation() -> void:
	match anim_type:
		TYPE_SHAKE_SCREEN_VERTICALLY:
			await Sound.play_applying_attack_sound(damage_mult)
			await _shake_screen_vertically(8)
		TYPE_SHAKE_SCREEN_HORIZONTALLY_HEAVY:
			await Sound.play_applying_attack_sound(damage_mult)
			await _shake_screen_horizontally(8)
		TYPE_SHAKE_SCREEN_HORIZONTALLY_SLOW:
			await _shake_screen_horizontally_slow(6, 2)
		TYPE_BLINK_ENEMY_MON_SPRITE:
			await Sound.play_applying_attack_sound(damage_mult)
			await _blink_mon(not player_turn)
		TYPE_SHAKE_SCREEN_HORIZONTALLY_LIGHT:
			await Sound.play_applying_attack_sound(damage_mult)
			await _shake_screen_horizontally(2)
		TYPE_SHAKE_SCREEN_HORIZONTALLY_SLOW_2:
			await _shake_screen_horizontally_slow(3, 2)
		_:
			pass


# --- the mon pictures ------------------------------------------------------------------

func _pic_x(player: bool) -> int:
	return 1 if player else 12


func _pic_y(player: bool) -> int:
	return 5 if player else 0


func _pic_sheet(player: bool) -> String:
	return b.player_back_sheet if player else b.enemy_sheet


func _hide_pic(player: bool) -> void:
	_clear_pic_area(_pic_x(player), _pic_y(player), 7, 7)


## ClearScreenArea over a picture (Korean name tiles on row 6 are kept, see Battle.pic_bg).
func _clear_pic_area(x: int, y: int, w: int, h: int) -> void:
	var space := Text.code_tile(Text.SPACE)
	for row in h:
		for col in w:
			b.pic_bg(x + col, y + row, space)


## AnimationShowMonPic: CopyPicTiles + Delay3.
func _show_mon_pic(player: bool) -> void:
	_draw_pic_at(player, _pic_x(player), _pic_y(player))
	await GB.delay3()


func _draw_pic_at(player: bool, x: int, y: int) -> void:
	b._draw_sheet(_pic_sheet(player), x, y)


## ChangeMonPic (AnimationFlashMonPic): the picture is reloaded and SET_PAL_BATTLE runs.
func _change_mon_pic(player: bool) -> void:
	_draw_pic_at(player, _pic_x(player), _pic_y(player))
	SGB.run("BATTLE", b._battle_ctx())


## AnimationTransformMon: the user's picture becomes the other mon's.
func _transform_mon() -> void:
	var other: PartyMon = b.enemy_mon if player_turn else b.player_mon
	var p: Dictionary = GameData.pokemon[other.species]
	if player_turn:
		b._draw_sheet(p["back"], 1, 5)
	else:
		b._draw_sheet(p["pic"], 12, 0)
	SGB.run("BATTLE", b._battle_ctx())


## AnimationBlinkMon: hidden 5 frames / shown 5 frames, six times.
func _blink_mon(player: bool) -> void:
	for i in 6:
		_hide_pic(player)
		await GB.frames(5)
		_draw_pic_at(player, _pic_x(player), _pic_y(player))
		await GB.frames(5)


## AnimationMoveMonHorizontally: the picture jumps one tile towards the opponent.
func _move_mon_horizontally() -> void:
	_hide_pic(player_turn)
	_draw_pic_at(player_turn, 2 if player_turn else 11, _pic_y(player_turn))
	await GB.frames(3)


## AnimationResetMonPosition.
func _reset_mon_position() -> void:
	_clear_pic_area(2 if player_turn else 11, _pic_y(player_turn), 7, 7)
	await _show_mon_pic(player_turn)


## _AnimationSlideMonOff: the picture slides off one tile per step (left for the
## player, right for the enemy), `steps` steps of `delay` frames.
func _slide_mon_off(player: bool, steps: int, delay: int) -> void:
	var sheet := _pic_sheet(player)
	var x0 := 0 if player else 12
	var y0 := _pic_y(player)
	for s in range(1, steps + 1):
		for col in 8:
			var pic_col := col - 1 + s if player else col - s
			for row in 7:
				var v := Text.code_tile(Text.SPACE)
				if pic_col >= 0 and pic_col < 7:
					v = S.pic_tile(sheet, pic_col, row)
				b.pic_bg(x0 + col, y0 + row, v)
		await GB.frames(delay)


## AnimationSlideMonUp: the rows scroll up with wrap-around, seven times, 2 frames each.
func _slide_mon_up() -> void:
	var sheet := _pic_sheet(player_turn)
	var x0 := _pic_x(player_turn)
	var y0 := _pic_y(player_turn)
	for k in range(1, 8):
		for row in 7:
			var pic_row := (row + k) % 7
			for col in 7:
				b.pic_bg(x0 + col, y0 + row, S.pic_tile(sheet, col, pic_row))
		await GB.frames(2)


## AnimationSlideMonDown: the top rows of the picture sink into the ground.
func _slide_mon_down(player: bool) -> void:
	var sheet := _pic_sheet(player)
	var x0 := _pic_x(player)
	var y0 := _pic_y(player)
	for rows in range(7, 0, -1):
		for row in rows:
			for col in 7:
				b.pic_bg(x0 + col, y0 + (7 - rows) + row, S.pic_tile(sheet, col, row))
		await GB.delay3()
		_hide_pic(player)


## AnimationSlideMonDownAndHide (TILEMAP_SLIDE_DOWN_MON_PIC_7X5 / 7X3).
func _slide_mon_down_and_hide() -> void:
	var sheet := _pic_sheet(player_turn)
	var x0 := _pic_x(player_turn)
	var y0 := _pic_y(player_turn)
	for c in 2:
		for shape in [[0, 1, 3, 4, 5], [0, 2, 4]]:
			_hide_pic(player_turn)
			var rows: Array = shape
			for i in rows.size():
				for col in 7:
					b.pic_bg(x0 + col, y0 + (7 - rows.size()) + i, S.pic_tile(sheet, col, int(rows[i])))
			await GB.frames(8)
	_hide_pic(player_turn)


## AnimationShakeBackAndForth: the picture jumps left and right 16 times.
func _shake_back_and_forth() -> void:
	var x0 := 0 if player_turn else 11
	var y0 := _pic_y(player_turn)
	for i in 16:
		_draw_pic_at(player_turn, x0, y0)
		await GB.delay3()
		_clear_pic_area(x0, y0, 9, 7)
		_draw_pic_at(player_turn, x0 + 2, y0)
		await GB.delay3()
		Text.clear_area(x0, y0, 9, 7)


## AnimationSquishMonPic: the outer columns are pushed inwards four times, then the picture vanishes.
func _squish_mon_pic() -> void:
	var y0 := _pic_y(player_turn)
	var left_x := 5 if player_turn else 16
	var right_x := 3 if player_turn else 14
	for c in 4:
		# left: the three tiles at left_x.. move one to the left, blank at left_x + 2
		for row in 7:
			for k in 3:
				S.set_bg(left_x - 1 + k, y0 + row, S.get_bg(left_x + k, y0 + row))
			S.set_bg(left_x + 2, y0 + row, Text.code_tile(Text.SPACE))
		await GB.delay3()
		# right: the three tiles at right_x.. move one to the right, blank at right_x - 2
		for row in 7:
			for k in 3:
				S.set_bg(right_x + 1 - k, y0 + row, S.get_bg(right_x - k, y0 + row))
			S.set_bg(right_x - 2, y0 + row, Text.code_tile(Text.SPACE))
		await GB.delay3()
	_hide_pic(player_turn)
	await GB.frames(2)


## MinimizedMonSprite: the 8x5 dot drawn in the middle of the picture area.
func _draw_minimized(player: bool) -> void:
	var img := Image.create(8, 8, false, Image.FORMAT_R8)
	var rows := [0b00011000, 0b00111100, 0b01111110, 0b00111100, 0b00100100]
	for y in rows.size():
		for x in 8:
			if (int(rows[y]) >> (7 - x)) & 1:
				img.set_pixel(x, y + 1, Color8(3, 0, 0))
	S.image_sheet("minimized_mon", img)
	S.set_bg(_pic_x(player) + 3, _pic_y(player) + 4, S.tile("minimized_mon", 0))
	await GB.delay3()


## AnimationSubstitute: the doll in place of the picture.
func _substitute() -> void:
	_hide_pic(player_turn)
	var x0 := _pic_x(player_turn)
	var y0 := _pic_y(player_turn)
	var frame := 0 if not player_turn else 1   # spr_monster facing down / up
	var sheet := "spr_monster"
	var base := frame * 4
	S.set_bg(x0 + (2 if not player_turn else 3), y0 + 4, S.tile(sheet, base))
	S.set_bg(x0 + (3 if not player_turn else 4), y0 + 4, S.tile(sheet, base + 1))
	S.set_bg(x0 + (2 if not player_turn else 3), y0 + 5, S.tile(sheet, base + 2))
	S.set_bg(x0 + (3 if not player_turn else 4), y0 + 5, S.tile(sheet, base + 3))
	await GB.delay3()


# --- sprite effects --------------------------------------------------------------------

## An OAM entry like BattleAnimWriteOAMEntry (tile of tileset 0).
func _ball_sprite(index: int, y: int, x: int, tile: int) -> void:
	S.set_sprite(index, x - 8, y - 16, S.tile("move_anim_0", tile))


## AnimationWaterDropletsEverywhere.
func _water_droplets_everywhere() -> void:
	tileset = 0
	var base_x := 240   # -16
	for d in 32:
		for base_y0 in [16, 24]:
			var base_y := int(base_y0)
			var n := 0
			while true:
				base_x = (base_x + 27) & 0xFF
				_ball_sprite(n, base_y, base_x, DROPLET_TILE)
				n += 1
				if base_x < 144:
					continue
				base_x = (base_x - 168) & 0xFF
				base_y += 16
				if base_y < 112:
					continue
				break
			await _clean_oam()
			await GB.frame


## _AnimationShootBallsUpward: `count` balls in a column rise 4 pixels per step.
func _shoot_balls(base_y: int, base_x: int, count: int, delay: int) -> void:
	var ys: Array = []
	for i in count:
		ys.append(base_y + 8 * (i + 1))
		_ball_sprite(i, int(ys[i]), base_x, BALL_TILE)
	await GB.frame
	var left := count
	while left > 0:
		for i in count:
			var y := int(ys[i])
			if y == 0:
				continue
			if y == base_y + 8:
				ys[i] = 0
				left -= 1
			else:
				ys[i] = (y - 4) & 0xFF
			_ball_sprite(i, int(ys[i]), base_x, BALL_TILE)
		await GB.frames(delay)


func _shoot_balls_upward() -> void:
	if player_turn:
		await _shoot_balls(48, 40, 5, 1)
	else:
		await _shoot_balls(0, 128, 5, 1)
	await _clean_oam()


func _shoot_many_balls_upward() -> void:
	var xs: Array = [0x10, 0x40, 0x28, 0x18, 0x38, 0x30] if player_turn else [0x60, 0x90, 0x78, 0x68, 0x88, 0x80]
	var y := 0x50 if player_turn else 0x28
	for x in xs:
		await _shoot_balls(y, int(x), 4, 1)
	await _clean_oam()


## AnimationSpiralBallsInward: three balls spiral in, then the screen flashes.
func _spiral_balls_inward() -> void:
	var base_y := 0 if player_turn else -40
	var base_x := 0 if player_turn else 80
	var start := 0
	while start + 2 < SPIRAL_BALL_COORDS.size():
		for k in 3:
			var c: Array = SPIRAL_BALL_COORDS[start + k]
			_ball_sprite(k, (base_y + int(c[0])) & 0xFF, (base_x + int(c[1])) & 0xFF, BALL_TILE)
		await GB.frames(5)
		start += 1
	await _clean_oam()
	await _flash_screen()


## AnimationFallingObjects (leaves, petals).
func _falling_objects(tile: int, count: int) -> void:
	var ys: Array = []
	var xs: Array = []
	var mv: Array = []
	for i in count:
		ys.append(8 * (i + 1))
		xs.append(int(FALLING_INITIAL_XS[i]))
		mv.append(int(FALLING_INITIAL_MOVEMENT[i]))
		S.set_sprite(i, int(xs[i]) - 8, int(ys[i]) - 16, S.tile("move_anim_1", tile))
	ys[0] = 0
	while true:
		for i in count:
			# FallingObjects_UpdateMovementByte
			var m := int(mv[i]) + 1
			if (m & 0x7F) == 9:
				m = (m & 0x80) ^ 0x80
			mv[i] = m
			# FallingObjects_UpdateOAMEntry
			var y := int(ys[i]) + 2
			if y >= 112:
				y = 160
			ys[i] = y
			var delta := int(FALLING_DELTA_XS[m & 0x7F])
			var flip := (m & 0x80) != 0
			xs[i] = ((int(xs[i]) - delta) if flip else (int(xs[i]) + delta)) & 0xFF
			S.set_sprite(i, int(xs[i]) - 8, y - 16, S.tile("move_anim_1", tile), 0, flip)
		await GB.delay3()
		if int(ys[0]) == 104:
			break


## AnimationShakeEnemyHUD: the enemy half of the screen shakes while the player's
## picture stays still (it is drawn as sprites in the original).
func _shake_enemy_hud() -> void:
	var sheet := b.player_back_sheet
	var n := 0
	for col in 7:
		for row in 5:
			S.set_sprite(n, 8 + col * 8, 40 + row * 8, S.pic_tile(sheet, col, row))
			n += 1
	_hide_pic(true)
	await GB.delay3()
	for e in 8:
		_set_top_rows_scx(254)
		await GB.frames(2)
		_set_top_rows_scx(2)
		await GB.frames(2)
	S.row_scx = PackedInt32Array()
	await _show_mon_pic(true)
	S.clear_sprites()


func _set_top_rows_scx(v: int) -> void:
	var rows := PackedInt32Array()
	rows.resize(18)
	for r in 7:
		rows[r] = v
	S.row_scx = rows


## AnimationWavyScreen: per-line scroll offsets cycling for 255 frames.
func _wavy_screen() -> void:
	for f in 255:
		var rows := PackedInt32Array()
		rows.resize(18)
		for r in 18:
			rows[r] = int(WAVY_LINE_OFFSETS[(f + r * 8) % WAVY_LINE_OFFSETS.size()]) & 0xFF
		S.row_scx = rows
		await GB.frame
	S.row_scx = PackedInt32Array()


# --- the Poké Ball toss ----------------------------------------------------------------

## TossBallAnimation: TOSS (or GREAT/ULTRA), then POOF, HIDEPIC, SHAKE, POOF, SHOWPIC as
## far as wPokeBallAnimData's upper nybble says; a trainer blocks the ball.
func _toss_ball_animation(anim_data: int) -> void:
	if is_trainer_battle:
		anim_id = id_of("TOSS_ANIM")
		await _play_animation(anim_id)
		Sound.play_sfx("SFX_FAINT_THUD")
		anim_id = id_of("BLOCKBALL_ANIM")
		await _play_animation(anim_id)
		return
	var count := anim_data >> 4
	num_shakes = anim_data & 0xF
	var first := "TOSS_ANIM"
	if cur_item == "GREAT_BALL":
		first = "GREATTOSS_ANIM"
	elif cur_item != "POKE_BALL":
		first = "ULTRATOSS_ANIM"
	var sequence := [first, "POOF_ANIM", "HIDEPIC_ANIM", "SHAKE_ANIM", "POOF_ANIM", "SHOWPIC_ANIM"]
	for i in count:
		anim_id = id_of(sequence[i])
		await _play_animation(anim_id)

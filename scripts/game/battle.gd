## Battles (engine/battle/core.asm, effects.asm, experience.asm, items/item_effects.asm
## ItemUseBall, pokemon/learn_move.asm, pokemon/evos_moves.asm, movie/evolution.asm):
## wild and trainer battles with the transition, intro slide, send-out animations,
## HUDs, menus, Generation 1 damage, status conditions, running, catching, party
## switching, experience split among the participants, level-up moves and evolution.
## Move animations and the ball toss are simplified stand-ins; the sounds are the
## original ones.
class_name Battle
extends RefCounted

const STAGE_MULT := [25, 28, 33, 40, 50, 66, 100, 150, 200, 250, 300, 350, 400]
const STAT_NAMES_EN := {"atk": "ATTACK", "def": "DEFENSE", "spd": "SPEED", "spc": "SPECIAL", "acc": "ACCURACY", "eva": "EVADE"}
const STAT_NAMES_KO := {"atk": "공격", "def": "방어", "spd": "스피드", "spc": "특수", "acc": "명중률", "eva": "회피율"}
const STAT_KEYS := ["atk", "def", "spd", "spc", "acc", "eva"]
const UNFILLED_CURSOR := 0xEC   # '▷'

## `x percent` (macros/data.asm): x * $ff / 100.
const PERCENT_10 := 25
const PERCENT_20 := 51
const PERCENT_25 := 63
const PERCENT_30 := 76
const PERCENT_33 := 84
const PERCENT_40 := 102
const PERCENT_50 := 127

var state: GameState
var request: Dictionary
var S: GBScreen
var rng := RandomNumberGenerator.new()
var is_wild := false
var is_ghost := false         # IsGhostBattle: a wild battle in Pokémon Tower without the SILPH SCOPE
var restless_soul := false    # wCurOpponent = RESTLESS_SOUL (the ghost of Cubone's mother, a MAROWAK)
var ghost_pic := false        # the enemy is drawn as the GhostPic and called "GHOST"
var pic_dodged := false       # the enemy picture was shifted by the dodge (restored at the next menu)
var is_old_man := false       # BATTLE_TYPE_OLD_MAN
var trainer_class := ""
var trainer_pic := "pic_trainer_rival1"
var player_mon: PartyMon
var player_index := 0         # wPlayerMonNumber
var enemy_mon: PartyMon
var enemy_party: Array = []
var enemy_index := -1         # wEnemyMonPartyPos
var ps: BattleSide               # the player's battle mon (wBattleMon + wPlayer* battle variables)
var es: BattleSide               # the enemy's (wEnemyMon + wEnemy*)
var player_turn := true          # hWhoseTurn == 0
var damage := 0                  # wDamage (shared by both sides, kept between turns)
var crit_ohko := 0               # wCriticalHitOrOHKO (1 crit, 2 OHKO, $ff OHKO failed)
var move_missed := false         # wMoveMissed
var move_didnt_miss := false     # wMoveDidntMiss
var damage_mult := 10            # wDamageMultipliers (bit 7 STAB, low bits effectiveness)
var escaped := false             # wEscapedFromBattle
var mon_is_disobedient := false  # wMonIsDisobedient
var ai_count := 0xFF             # wAICount
var ai_layer2_encouragement := 0 # wAILayer2Encouragement
var pay_day_total := 0           # wTotalPayDayMoney
var move_name_buffer := ""       # the move name in wStringBuffer for UsedMoveText
var gym_leader_no := 0           # wGymLeaderNo (= wLoneAttackNo)
var trainer_team_level := 0      # wCurEnemyLevel after ReadTrainer (the prize money level)
var test_item := ""              # --battle-use-item= test helper: used from the first battle menu
var gain_exp_flags: Array = []   # wPartyGainExpFlags
var can_evolve: Array = []       # wCanEvolveFlags
var saved_menu := 0              # wBattleAndStartSavedMenuItem
var move_cursor := 0
var result := ""                 # "won", "lost", "blackout", "ran", "caught", "demo"
var battle_over := false
var took_turn := false           # wActionResultOrTookBattleTurn
var first_mons_not_out_yet := true
var in_handle_player_fainted := false
var run_attempts := 0            # wNumRunAttempts
var last_switch_in_enemy_hp := 0
var enemy_sheet := ""
var player_back_sheet := ""
var trace := "--trace-battle" in OS.get_cmdline_user_args()   # test log of menus and texts
var menu_saved := PackedInt32Array()   # SaveScreenTilesToBuffer1 before the battle menu
## Korean: the 8x16 glyphs need the row above the name, so the enemy HUD sits one row lower.
var ehud := 1 if GameData.lang == "ko" else 0


func _init(s: GameState, req: Dictionary) -> void:
	state = s
	request = req


static func heal_party(s: GameState) -> void:
	for m in s.party:
		m.hp = m.max_hp
		m.status = 0
		for mv in m.moves:
			mv.pp = mv.max_pp


## Runs the whole battle and returns the result string (see `result`).
func run() -> String:
	S = GB.screen
	rng.randomize()
	Text.vars["PLAYER"] = state.player_name
	Text.vars["RIVAL"] = state.rival_name
	is_old_man = str(request.get("type", "")) == "old_man"
	is_wild = is_old_man or bool(request.get("wild", false))
	gym_leader_no = int(request.get("gym_leader", 0))
	for arg in OS.get_cmdline_user_args():
		# test helpers: --battle-gym-leader=N (main.gd's --trainer has no gym key),
		# --battle-seed=N, --battle-moves=A,B.. / --battle-enemy-moves=A,B.. (the first mons' moves)
		if arg.begins_with("--battle-gym-leader="):
			gym_leader_no = int(arg.get_slice("=", 1))
		elif arg.begins_with("--battle-seed="):
			rng.seed = int(arg.get_slice("=", 1))
		elif arg.begins_with("--battle-use-item="):
			test_item = arg.get_slice("=", 1)
		elif arg.begins_with("--battle-moves=") and state.party.size() > 0:
			state.party[0].moves = _test_moves(arg.get_slice("=", 1))
	if is_wild:
		var sp: String = str(request["species"])
		enemy_party.append(PartyMon.create(sp, int(request["level"]), true))
		_write_mon_moves(enemy_party[0])
		state.pokedex_seen[sp] = true   # LoadEnemyMonData sets the seen flag
		restless_soul = bool(request.get("restless_soul", false))
		is_ghost = str(state.cur_map).begins_with("POKEMON_TOWER_") and state.item_count("SILPH_SCOPE") == 0
		ghost_pic = is_ghost or restless_soul
		if ghost_pic:
			enemy_party[0].nickname = "고스트" if GameData.lang == "ko" else "GHOST"
	else:
		trainer_class = str(request["trainer"])
		var tdata: Dictionary = GameData.trainers.get(trainer_class, {})
		trainer_pic = str(tdata.get("pic", "pic_trainer_rival1"))
		Text.ram["wTrainerName"] = str(request.get("name", GameData.trainer_class_name(trainer_class)))
		if gym_leader_no != 0 and not request.has("gym_leader"):
			Text.ram["wTrainerName"] = GameData.trainer_class_name(trainer_class)
		var special := false
		if request.has("party"):
			for p in request["party"]:
				enemy_party.append(PartyMon.create(str(p["species"]), int(p["level"]), false))
				trainer_team_level = int(p["level"])
		else:
			var team_i := int(request["team"]) - 1
			var team: Array = tdata["teams"][team_i]
			for e in team:
				enemy_party.append(PartyMon.create(str(e[1]), int(e[0]), false))
				trainer_team_level = int(e[0])
			special = bool(tdata.get("special_teams", [])[team_i]) if team_i < tdata.get("special_teams", []).size() else false
		for m in enemy_party:
			_write_mon_moves(m)
		if special:
			_add_special_trainer_moves(tdata)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--battle-enemy-moves="):
			enemy_party[0].moves = _test_moves(arg.get_slice("=", 1))
	gain_exp_flags.resize(state.party.size())
	can_evolve.resize(state.party.size())
	for i in state.party.size():
		gain_exp_flags[i] = false
		can_evolve[i] = false
	_load_enemy(_first_alive_enemy(-1))
	if not is_old_man:
		player_index = _first_alive_party()
		player_mon = state.party[player_index]
		Text.ram["wBattleMonNick"] = player_mon.nickname
	# PlayBattleMusic
	var music := "MUSIC_WILD_BATTLE"
	if gym_leader_no != 0:
		music = "MUSIC_GYM_LEADER_BATTLE"
	elif not is_wild:
		music = "MUSIC_TRAINER_BATTLE"
		if trainer_class == "RIVAL3":
			music = "MUSIC_FINAL_BATTLE"
		elif trainer_class == "LANCE":
			music = "MUSIC_GYM_LEADER_BATTLE"
	await Sound.play_battle_music(music)
	await _transition()
	await _intro()
	await _start_battle()
	if not battle_over:
		await _main_loop()
	# EndOfBattle: the Pay Day coins, then evolutions
	if result == "won":
		if pay_day_total > 0:
			state.money = mini(state.money + pay_day_total, 999999)
			Text.ram["wTotalPayDayMoney"] = pay_day_total
			await _text("_PickUpPayDayMoneyText")
		await _evolution_after_battle()
	Sound.low_health_alarm = 0
	Sound.ch_id[Sound.CHAN5] = 0
	if is_old_man:
		Text.vars["PLAYER"] = state.player_name
	S.white_out()
	S.clear_sprites()
	S.row_scx = PackedInt32Array()
	Text.clear_screen()
	return result


static func _test_moves(spec: String) -> Array:
	var out: Array = []
	for mv in spec.split(","):
		var pp: int = GameData.moves[mv]["pp"]
		out.append({"move": mv, "pp": pp, "max_pp": pp})
	return out


func _first_alive_party() -> int:
	for i in state.party.size():
		if state.party[i].hp > 0:
			return i
	return 0


func _first_alive_enemy(exclude: int) -> int:
	for i in enemy_party.size():
		if i != exclude and enemy_party[i].hp > 0:
			return i
	return 0


func _any_party_alive() -> bool:
	for m in state.party:
		if m.hp > 0:
			return true
	return false


func _any_enemy_alive() -> bool:
	for m in enemy_party:
		if m.hp > 0:
			return true
	return false


func _load_enemy(index: int) -> void:
	_load_enemy_mon_data(index)


func _load_player(index: int) -> void:
	_load_battle_mon_from_party(index)


# --- transition ------------------------------------------------------------------

## BattleTransition: three palette flashes, then an inward spiral of black tiles.
func _transition() -> void:
	S.oam = S.oam.slice(0, 4)
	await GB.delay3()
	var flash := [
		GBScreen.pal(3, 3, 2, 1), GBScreen.pal(3, 3, 3, 2), GBScreen.pal(3, 3, 3, 3), GBScreen.pal(3, 3, 3, 2),
		GBScreen.pal(3, 3, 2, 1), GBScreen.pal(3, 2, 1, 0), GBScreen.pal(2, 1, 0, 0), GBScreen.pal(1, 0, 0, 0),
		GBScreen.pal(0, 0, 0, 0), GBScreen.pal(1, 0, 0, 0), GBScreen.pal(2, 1, 0, 0), GBScreen.pal(3, 2, 1, 0),
	]
	for i in 3:
		for p in flash:
			S.bgp = p
			await GB.frames(2)
	# BattleTransition_InwardSpiral: every 7 tiles the screen updates (3 frames)
	var black := S.solid_tile(3)
	var x := 0
	var y := 0
	var left := 0
	var top := 0
	var right := 19
	var bottom := 17
	var count := 0
	var dir := 0
	var placed := 0
	while placed < 360:
		S.set_bg(x, y, black)
		placed += 1
		count += 1
		if count == 7:
			count = 0
			await GB.delay3()
		match dir:
			0:
				if x < right:
					x += 1
				else:
					dir = 1
					top += 1
					y += 1
			1:
				if y < bottom:
					y += 1
				else:
					dir = 2
					right -= 1
					x -= 1
			2:
				if x > left:
					x -= 1
				else:
					dir = 3
					bottom -= 1
					y -= 1
			3:
				if y > top:
					y -= 1
				else:
					dir = 0
					left += 1
					x += 1
	S.set_all_pals(GBScreen.pal(3, 3, 3, 3))
	S.clear_sprites()


# --- pictures -------------------------------------------------------------------

func _prepare_pics() -> void:
	enemy_sheet = _enemy_pic()
	if player_mon != null:
		_prepare_player_back()


## The back pic is a 32x32 sprite scaled by two (ScaleSpriteByTwo): the
## lower-left 28x28 pixels become a 56x56 picture.
func _prepare_player_back(species: String = "") -> void:
	var sp := species if species != "" else player_mon.species
	var back_name: String = GameData.pokemon[sp]["back"]
	var img := S.sheet_image(back_name)
	var crop := img.get_region(Rect2i(0, 4, 28, 28))
	crop.resize(56, 56, Image.INTERPOLATE_NEAREST)
	player_back_sheet = "back_scaled_" + sp
	S.image_sheet(player_back_sheet, crop)


func _downscaled(sheet_name: String, tiles: int) -> String:
	var name := "%s_down%d" % [sheet_name, tiles]
	var img := S.sheet_image(sheet_name)
	var size := tiles * 8
	var small := img.duplicate()
	small.resize(size, size, Image.INTERPOLATE_NEAREST)
	S.image_sheet(name, small)
	return name


func _draw_sheet(sheet_name: String, x: int, y: int) -> void:
	var sh := S.sheet(sheet_name)
	for row in sh.rows:
		for col in sh.tpr:
			pic_bg(x + col, y + row, S.pic_tile(sheet_name, col, row))


## A picture tile written (or cleared) in the battle scene.
## PH-INTENT: in Korean the player's name (row 7) is an 8x16 Hangul string whose top
## halves sit on row 6, the bottom row of the enemy picture. The name is drawn after
## the picture when the HUD appears, so picture redraws (blink, show/hide, slides)
## leave Hangul tiles on row 6 alone instead of cutting the name ("꼬부ㄱ|").
func pic_bg(x: int, y: int, v: int) -> void:
	if y == 6 and GameData.lang == "ko" and (S.get_bg(x, y) >> 16) == S.sid("korean_font"):
		return
	S.set_bg(x, y, v)


func _clear(x: int, y: int, w: int, h: int) -> void:
	Text.clear_area(x, y, w, h)


# --- intro ------------------------------------------------------------------------

## SetPal_Battle context: species and HP bar colours (GetHealthBarColor: 0 green, 1 yellow, 2 red).
func _battle_ctx() -> Dictionary:
	var ctx := {"enemy": es.species if es != null else enemy_mon.species, "enemy_hp": _bar_color(_hp_pixels(enemy_mon.hp, enemy_mon.max_hp))}
	if player_mon != null:
		ctx["player"] = ps.species if ps != null else player_mon.species
		ctx["player_hp"] = _bar_color(_hp_pixels(player_mon.hp, player_mon.max_hp))
	else:
		ctx["player"] = state.party[0].species if state.party.size() > 0 else enemy_mon.species
		ctx["player_hp"] = 0
	return ctx


static func _bar_color(pixels: int) -> int:
	return 0 if pixels >= 27 else (1 if pixels >= 10 else 2)


## _InitBattleCommon / SlidePlayerAndEnemySilhouettesOnScreen / PrintBeginningBattleText.
func _intro() -> void:
	_prepare_pics()
	SGB.run("BATTLE_BLACK")
	Text.clear_screen()
	Menu.message_box()
	# the enemy (trainer pic or wild mon) in rows 0-6, the player's body in rows 8-11, the head as sprites
	_draw_sheet(enemy_sheet if is_wild else trainer_pic, 12, 0)
	var back := "pic_red_back"
	for row in range(3, 7):
		for col in 7:
			S.set_bg(1 + col, 5 + row, S.pic_tile(back, col, row))
	var n := 0
	for col in 7:
		for row in 3:
			S.set_sprite(n, 152 + col * 8, 40 + row * 8, S.pic_tile(back, col, row))
			n += 1
	S.normal_pals()
	var c := 0x90
	var b := 0x70
	while true:
		var rows := PackedInt32Array()
		rows.resize(18)
		for r in 18:
			rows[r] = b if (r >= 8 and r < 12) else (c if r < 12 else 0)
		S.row_scx = rows
		for i in 21:
			S.oam[i].x -= 2
		await GB.frame
		c -= 2
		b = (b + 2) & 0xFF
		if c == 0:
			break
	S.row_scx = PackedInt32Array()
	S.clear_sprites()
	_draw_sheet(back, 1, 5)
	await GB.delay3()
	SGB.run("BATTLE", _battle_ctx())
	if is_wild:
		_draw_enemy_hud()
	# PrintBeginningBattleText
	if is_wild and ghost_pic:
		await _tower_battle_text()
	elif is_wild:
		Sound.play_cry(enemy_mon.species)
		await Sound.wait_for_sfx()
		_draw_all_pokeballs()
		await Text.print_text("_WildMonAppearedText")
	else:
		Sound.play_sfx_modified("SFX_TRAINER_APPEARED", 0, 0x80)
		await Sound.wait_for_sfx()
		await GB.frames(20)
		_draw_all_pokeballs()
		await Text.print_text("_TrainerWantsToFightText")
		await _enemy_send_out(true)


## StartBattle: the player's first mon (or the old man's scripted menu).
func _start_battle() -> void:
	await GB.frames(40)
	if is_old_man:
		await _old_man_battle()
		return
	await _slide_pic(1, 5, 9, -1)
	gain_exp_flags[player_index] = true
	_load_battle_mon_from_party(player_index)
	await _send_out_mon()


## SendOutMon: the message, HUDs, poof and the ball animation.
func _send_out_mon() -> void:
	await _print_send_out_message()
	_reset_player_battle_vars()
	if enemy_mon.hp > 0:
		_draw_enemy_hud()
	_draw_player_hud()
	saved_menu = 0
	SGB.run("BATTLE", _battle_ctx())
	# POOF_ANIM on the enemy's turn (the cloud on the player's side); its frame
	# blocks start at OAM 0 and AnimationCleanOAM clears the party's ball sprites
	await _play_move_animation(false, "POOF_ANIM", 0)
	await _animate_sending_out(player_back_sheet, 1, 5, 4, 11)
	Sound.play_cry(player_mon.species)
	await Sound.wait_for_sfx()
	_print_empty()


## PrintSendOutMonMessage: Go! / Do it! / Get'm! / The enemy's weak! by the enemy's HP.
func _print_send_out_message() -> void:
	var label := "_GoText"
	if enemy_mon.hp > 0 and last_switch_in_enemy_hp > 0:
		var ratio := float(enemy_mon.hp) / float(enemy_mon.max_hp)
		if ratio < 0.25:
			label = "_EnemysWeakText"
		elif ratio < 0.5:
			label = "_GetmText"
		elif ratio < 0.7:
			label = "_DoItText"
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text(label))
	await Text.run_commands([["text", player_mon.nickname + "!"]])


## SlideTrainerPicOffScreen: shift the 7x7 picture at (x, y) one tile per step.
func _slide_pic(x: int, y: int, steps: int, dir: int) -> void:
	for s in steps:
		for row in 7:
			if dir > 0:
				for col in range(19, x, -1):
					S.set_bg(col, y + row, S.get_bg(col - 1, y + row))
				S.set_bg(x, y + row, Text.code_tile(Text.SPACE))
			else:
				for col in range(0, x + 7):
					S.set_bg(col, y + row, S.get_bg(col + 1, y + row))
				S.set_bg(x + 7, y + row, Text.code_tile(Text.SPACE))
		x += dir
		await GB.delay3()


## AnimateSendingOutMon: ball, 3x3, 5x5, then the full picture.
func _animate_sending_out(sheet_name: String, px: int, py: int, bx: int, by: int) -> void:
	S.set_bg(bx, by, S.tile("balls", 0))
	await GB.delay3()
	S.set_bg(bx, by, Text.code_tile(Text.SPACE))
	var s3 := _downscaled(sheet_name, 3)
	_draw_sheet(s3, bx - 1, by - 2)
	await GB.frames(4)
	_clear(bx - 1, by - 2, 3, 3)
	var s5 := _downscaled(sheet_name, 5)
	_draw_sheet(s5, bx - 2, by - 4)
	await GB.frames(5)
	_clear(bx - 2, by - 4, 5, 5)
	_draw_sheet(sheet_name, px, py)
	await GB.delay3()


## AnimateRetreatingPlayerMon: 5x5, 3x3, then the ball.
func _animate_retreating_player_mon() -> void:
	_clear(1, 5, 7, 7)
	var s5 := _downscaled(player_back_sheet, 5)
	_draw_sheet(s5, 3, 7)
	await GB.frames(4)
	_clear(3, 7, 5, 5)
	var s3 := _downscaled(player_back_sheet, 3)
	_draw_sheet(s3, 4, 9)
	await GB.frames(4)
	_clear(4, 9, 3, 3)
	S.set_bg(4, 11, S.tile("balls", 0))
	await GB.frames(4)
	S.set_bg(4, 11, Text.code_tile(Text.SPACE))


func _print_empty() -> void:
	_clear(1, 13, 18, 4)


# --- HUDs ---------------------------------------------------------------------------

## Battle HUD tile ids after LoadHudTilePatterns / LoadHpBarAndStatusTilePatterns.
func _hud_tile(id: int) -> int:
	if id >= 0x6D and id <= 0x6F:
		return S.tile("battle_hud_1", id - 0x6D)
	if id >= 0x73 and id <= 0x75:
		return S.tile("battle_hud_2", id - 0x73)
	if id >= 0x76 and id <= 0x78:
		return S.tile("battle_hud_3", id - 0x76)
	return S.tile("font_battle_extra", id - 0x62)


func _name_start(x: int, name: String) -> int:
	var n := 0
	for c in Text.encode(name):
		n += 2 if c >= 0x100 else 1
	if n >= 5:
		return x - 2
	if n >= 3:
		return x - 1
	return x


## DrawAllPokeballs: the player's six balls (and the trainer's in trainer battles).
func _draw_all_pokeballs() -> void:
	_place_player_hud_tiles()
	if not is_wild:
		_place_enemy_hud_tiles()
	var i := 0
	for k in 6:
		var t := 3  # empty slot
		if k < state.party.size():
			var m: PartyMon = state.party[k]
			t = 2 if m.hp == 0 else (1 if m.status != 0 else 0)
		S.set_sprite(i, 88 + k * 8, 80, S.tile("balls", t))
		i += 1
	if is_wild:
		return
	for k in 6:
		var t := 3
		if k < enemy_party.size():
			t = 2 if enemy_party[k].hp == 0 else 0
		S.set_sprite(i, 64 - k * 8, 16, S.tile("balls", t))
		i += 1


func _place_player_hud_tiles() -> void:
	S.set_bg(18, 10, _hud_tile(0x73))
	S.set_bg(18, 11, _hud_tile(0x77))
	for x in range(17, 9, -1):
		S.set_bg(x, 11, _hud_tile(0x76))
	S.set_bg(9, 11, _hud_tile(0x6F))


func _place_enemy_hud_tiles() -> void:
	S.set_bg(1, 2 + ehud, _hud_tile(0x73))
	S.set_bg(1, 3 + ehud, _hud_tile(0x74))
	for x in range(2, 10):
		S.set_bg(x, 3 + ehud, _hud_tile(0x76))
	S.set_bg(10, 3 + ehud, _hud_tile(0x78))


func _hp_pixels(hp: int, max_hp: int) -> int:
	if hp <= 0:
		return 0
	var px := hp * 48 / max_hp
	return maxi(px, 1)


func _draw_hp_bar(x: int, y: int, pixels: int) -> void:
	S.set_bg(x, y, _hud_tile(0x71))
	S.set_bg(x + 1, y, _hud_tile(0x62))
	for i in 6:
		var left := pixels - i * 8
		var t := 0x63
		if left >= 8:
			t = 0x6B
		elif left > 0:
			t = 0x63 + left
		S.set_bg(x + 2 + i, y, _hud_tile(t))
	S.set_bg(x + 8, y, _hud_tile(0x6D))


func _draw_level(x: int, y: int, level: int) -> void:
	S.set_bg(x, y, _hud_tile(0x6E))
	Text.place_string(x + 1, y, str(level))


## PrintStatusCondition: SLP/PSN/BRN/FRZ/PAR after the level (DrawEnemyHUDAndHPBar
## prints it in place of the level when the mon has a status).
static func status_text(status: int) -> String:
	if status & PartyMon.SLP_MASK:
		return "SLP"
	if status & PartyMon.PSN:
		return "PSN"
	if status & PartyMon.BRN:
		return "BRN"
	if status & PartyMon.FRZ:
		return "FRZ"
	if status & PartyMon.PAR:
		return "PAR"
	return ""


func _draw_enemy_hud(pixels: int = -1) -> void:
	_clear(0, 0, 12, 4 + ehud)
	_place_enemy_hud_tiles()
	Text.place_string(_name_start(3, enemy_mon.nickname), ehud, enemy_mon.nickname)
	var st := status_text(enemy_mon.status)
	if st != "":
		Text.place_string(4, 1 + ehud, st)
	else:
		_draw_level(4, 1 + ehud, enemy_mon.level)
	_draw_hp_bar(2, 2 + ehud, _hp_pixels(enemy_mon.hp, enemy_mon.max_hp) if pixels < 0 else pixels)
	SGB.run("BATTLE", _battle_ctx())


func _draw_player_hud(pixels: int = -1) -> void:
	_clear(9, 7, 11, 5)
	if GameData.lang == "ko":
		# the previous name's Hangul top halves on row 6 (kept by pic_bg)
		for x in range(9, 20):
			if (S.get_bg(x, 6) >> 16) == S.sid("korean_font"):
				S.set_bg(x, 6, Text.code_tile(Text.SPACE))
	_place_player_hud_tiles()
	Text.place_string(_name_start(12, player_mon.nickname), 7, player_mon.nickname)
	var st := status_text(player_mon.status)
	if st != "":
		Text.place_string(14, 8, st)
	else:
		_draw_level(14, 8, player_mon.level)
	_draw_hp_bar(10, 9, _hp_pixels(player_mon.hp, player_mon.max_hp) if pixels < 0 else pixels)
	Text.place_string(11, 10, "%3d/%3d" % [player_mon.hp, player_mon.max_hp])
	SGB.run("BATTLE", _battle_ctx())
	_check_low_health_alarm()


func _draw_huds() -> void:
	if player_mon != null:
		_draw_player_hud()
	_draw_enemy_hud()


## DrawPlayerHUDAndHPBar tail: the alarm starts when the HP bar is red (< 10 pixels)
## and stops (releasing channel 5) otherwise or when the mon has fainted.
func _check_low_health_alarm() -> void:
	if player_mon.hp > 0:
		if Sound.low_health_alarm_disabled:
			return
		if _hp_pixels(player_mon.hp, player_mon.max_hp) < 10:
			Sound.set_low_health_alarm(true)
			return
	var was_on := (Sound.low_health_alarm & 0x80) != 0
	Sound.low_health_alarm = 0
	if was_on:
		Sound.ch_id[Sound.CHAN5] = 0


func _animate_hp(is_player: bool, from_hp: int, to_hp: int) -> void:
	var mon := player_mon if is_player else enemy_mon
	var from_px := _hp_pixels(from_hp, mon.max_hp)
	var to_px := _hp_pixels(to_hp, mon.max_hp)
	var px := from_px
	var step := -1 if to_px < from_px else 1
	var last_color := _bar_color(px)
	while px != to_px:
		px += step
		if _bar_color(px) != last_color:
			# UpdateHPBar: the HP bar palette follows the colour
			last_color = _bar_color(px)
			var ctx := _battle_ctx()
			ctx["player_hp" if is_player else "enemy_hp"] = last_color
			SGB.run("BATTLE", ctx)
		if is_player:
			var shown := int(ceil(float(px) * mon.max_hp / 48.0))
			shown = clampi(shown, 0 if px == 0 else 1, mon.max_hp)
			_draw_hp_bar(10, 9, px)
			Text.place_string(11, 10, "%3d/%3d" % [shown, mon.max_hp])
		else:
			_draw_hp_bar(2, 2 + ehud, px)
		await GB.frames(2)
	if is_player:
		Text.place_string(11, 10, "%3d/%3d" % [to_hp, mon.max_hp])
		_check_low_health_alarm()


# --- menus ----------------------------------------------------------------------------

func _draw_battle_menu_box() -> void:
	Menu.draw_box(8, 12, 10, 4)
	if GameData.lang == "ko":
		Text.place_string(10, 14, "싸운다")
		Text.place_string(16, 14, "<PKMN>")
		Text.place_string(10, 16, "도구")
		Text.place_string(16, 16, "도망")
	else:
		Text.place_string(10, 14, "FIGHT")
		Text.place_string(16, 14, "<PKMN>")
		Text.place_string(10, 16, "ITEM")
		Text.place_string(16, 16, "RUN")


## DisplayBattleMenu. Returns "fight", "pkmn", "item" or "run".
func _battle_menu() -> String:
	if pic_dodged:   # DisplayBattleMenu's LoadScreenTilesFromBuffer1 puts the picture back
		pic_dodged = false
		_draw_sheet(enemy_sheet, 12, 0)
	_draw_huds()
	_print_empty()
	menu_saved = S.snapshot_bg()
	_draw_battle_menu_box()
	if trace:
		print("BATTLE_MENU frame=%d player=%s %d/%d enemy=%s %d/%d" % [GB.frame_count, player_mon.nickname, player_mon.hp, player_mon.max_hp, enemy_mon.nickname, enemy_mon.hp, enemy_mon.max_hp])
	var positions := [Vector2i(9, 14), Vector2i(15, 14), Vector2i(9, 16), Vector2i(15, 16)]
	var cur := saved_menu
	Menu.place_cursor(positions[cur].x, positions[cur].y)
	while true:
		await GB.frame
		var keys := GB.joy5
		if keys == 0:
			continue
		var next := cur
		if keys & GB.RIGHT and (cur % 2) == 0:
			next = cur + 1
		elif keys & GB.LEFT and (cur % 2) == 1:
			next = cur - 1
		elif keys & GB.DOWN and cur < 2:
			next = cur + 2
		elif keys & GB.UP and cur >= 2:
			next = cur - 2
		if next != cur:
			Menu.erase_cursor()
			cur = next
			Menu.place_cursor(positions[cur].x, positions[cur].y)
		if keys & GB.A:
			break
	Menu.erase_cursor()
	saved_menu = cur
	return ["fight", "pkmn", "item", "run"][cur]


## MoveSelectionMenu. Returns the move index or -1 for B.
## MoveSelectionMenu (regular) + SelectMenuItem: the battle mon's moves (wBattleMonMoves,
## so Mimic / Transform show), Up/Down wrapping, A picks, B cancels, SELECT marks a
## move with '▷' and a second SELECT swaps the two (SwapMovesInMenu: battle moves, PP,
## the disabled slot and the party mon's moves). Returns the index or -1.
func _move_menu() -> int:
	var item_to_swap := 0   # wMenuItemToSwap (1-based, 0 = none)
	while true:
		var count := 0
		var names: Array = []
		for m in ps.moves:
			if str(m) != "":
				names.append(GameData.move_name(str(m)))
				count += 1
		Menu.draw_box(4, 12, 14, 4)
		Text.put(4, 12, Menu.HORIZ)
		Text.put(10, 12, Menu.BOTTOM_RIGHT)
		var cursor_pos := Menu.place_move_list(5, 13, names)
		var cur := move_cursor
		if cur >= count:
			cur = 0
		var swap_requested := false
		while not swap_requested:
			_print_menu_item(cur)
			if item_to_swap > 0:
				var sp: Vector2i = cursor_pos[item_to_swap - 1]
				Text.put(sp.x, sp.y, UNFILLED_CURSOR)
			Menu.place_cursor(cursor_pos[cur].x, cursor_pos[cur].y)
			var keys := 0
			while keys == 0:
				await GB.frame
				keys = GB.joy5
			if keys & GB.A:
				Menu.erase_cursor()
				move_cursor = cur
				return cur
			if keys & GB.B:
				Menu.erase_cursor()
				move_cursor = cur
				return -1
			if keys & GB.SELECT:
				move_cursor = cur
				if item_to_swap == 0:
					item_to_swap = cur + 1
				else:
					_swap_moves_in_menu(item_to_swap - 1, cur)
					item_to_swap = 0
				swap_requested = true   # jp MoveSelectionMenu: the list is redrawn
			elif keys & GB.UP:
				Menu.erase_cursor()
				cur = count - 1 if cur == 0 else cur - 1
			elif keys & GB.DOWN:
				Menu.erase_cursor()
				cur = 0 if cur == count - 1 else cur + 1
	return -1


## SwapMovesInMenu: moves and PP of the battle mon, the disabled-move slot, then the
## party mon's moves (and PP) in the same two slots.
func _swap_moves_in_menu(a: int, b: int) -> void:
	if trace:
		print("BATTLE_SWAP %d<->%d frame=%d" % [a, b, GB.frame_count])
	var t = ps.moves[a]
	ps.moves[a] = ps.moves[b]
	ps.moves[b] = t
	t = ps.pp[a]
	ps.pp[a] = ps.pp[b]
	ps.pp[b] = t
	var dslot := (ps.disabled >> 4) & 0xF
	if dslot == b + 1:
		ps.disabled = ((a + 1) << 4) | (ps.disabled & 0xF)
	elif dslot == a + 1:
		ps.disabled = ((b + 1) << 4) | (ps.disabled & 0xF)
	var pm: Array = player_mon.moves
	if a < pm.size() and b < pm.size():
		t = pm[a]
		pm[a] = pm[b]
		pm[b] = t


# --- main loop -----------------------------------------------------------------------

# --- battle structs ------------------------------------------------------------------------

## wBattleMon* / wEnemyMon* plus the per-side battle variables of core.asm
## (wPlayerBattleStatus1-3, wPlayerNumAttacksLeft, wPlayerDisabledMove, ...).
class BattleSide:
	var player := true
	var mon: PartyMon
	var species := ""
	var types: Array = ["NORMAL", "NORMAL"]
	var level := 1
	var dvs := {}
	var stats := {"atk": 1, "def": 1, "spd": 1, "spc": 1}     # wBattleMonAttack..Special
	var unmod := {"atk": 1, "def": 1, "spd": 1, "spc": 1}     # wPlayerMonUnmodifiedAttack..
	var mods := {"atk": 7, "def": 7, "spd": 7, "spc": 7, "acc": 7, "eva": 7}   # wPlayerMonStatMods (1..13)
	var moves: Array = ["", "", "", ""]   # wBattleMonMoves ("" = no move)
	var pp: Array = [0, 0, 0, 0]          # wBattleMonPP
	var status1 := 0
	var status2 := 0
	var status3 := 0
	var num_attacks_left := 0
	var confused_counter := 0
	var toxic_counter := 0
	var disabled := 0                     # wPlayerDisabledMove: slot + 1 in the high nibble, turns in the low
	var disabled_move := ""               # wPlayerDisabledMoveNumber
	var bide_damage := 0
	var substitute_hp := 0
	var selected_move := ""               # wPlayerSelectedMove (CANNOT_MOVE = $ff)
	var move_list_index := 0              # wPlayerMoveListIndex
	var move := {"num": "", "effect": "NO_ADDITIONAL_EFFECT", "power": 0, "type": "NORMAL", "accuracy": 0, "pp": 0}
	var used_move := ""                   # wPlayerUsedMove
	var num_hits := 0
	var minimized := false


# constants/battle_constants.asm
const STORING_ENERGY := 1 << 0
const THRASHING_ABOUT := 1 << 1
const ATTACKING_MULTIPLE_TIMES := 1 << 2
const FLINCHED := 1 << 3
const CHARGING_UP := 1 << 4
const USING_TRAPPING_MOVE := 1 << 5
const INVULNERABLE := 1 << 6
const CONFUSED := 1 << 7
const USING_X_ACCURACY := 1 << 0
const PROTECTED_BY_MIST := 1 << 1
const GETTING_PUMPED := 1 << 2
const HAS_SUBSTITUTE_UP := 1 << 4
const NEEDS_TO_RECHARGE := 1 << 5
const USING_RAGE := 1 << 6
const SEEDED := 1 << 7
const BADLY_POISONED := 1 << 0
const HAS_LIGHT_SCREEN_UP := 1 << 1
const HAS_REFLECT_UP := 1 << 2
const TRANSFORMED := 1 << 3
const CANNOT_MOVE := "CANNOT_MOVE"
const EFFECTIVE := 10
const MAX_STAT_VALUE := 999
const MOD_KEYS := ["atk", "def", "spd", "spc", "acc", "eva"]
# data/battle/stat_modifiers.asm
const STAT_RATIOS := [[25, 100], [28, 100], [33, 100], [40, 100], [50, 100], [66, 100], [1, 1],
	[15, 10], [2, 1], [25, 10], [3, 1], [35, 10], [4, 1]]
# constants/move_effect_constants.asm
const EFFECT_IDS := {
	"NO_ADDITIONAL_EFFECT": 0x00, "EFFECT_01": 0x01, "POISON_SIDE_EFFECT1": 0x02, "DRAIN_HP_EFFECT": 0x03,
	"BURN_SIDE_EFFECT1": 0x04, "FREEZE_SIDE_EFFECT1": 0x05, "PARALYZE_SIDE_EFFECT1": 0x06, "EXPLODE_EFFECT": 0x07,
	"DREAM_EATER_EFFECT": 0x08, "MIRROR_MOVE_EFFECT": 0x09, "ATTACK_UP1_EFFECT": 0x0A, "DEFENSE_UP1_EFFECT": 0x0B,
	"SPEED_UP1_EFFECT": 0x0C, "SPECIAL_UP1_EFFECT": 0x0D, "ACCURACY_UP1_EFFECT": 0x0E, "EVASION_UP1_EFFECT": 0x0F,
	"PAY_DAY_EFFECT": 0x10, "SWIFT_EFFECT": 0x11, "ATTACK_DOWN1_EFFECT": 0x12, "DEFENSE_DOWN1_EFFECT": 0x13,
	"SPEED_DOWN1_EFFECT": 0x14, "SPECIAL_DOWN1_EFFECT": 0x15, "ACCURACY_DOWN1_EFFECT": 0x16, "EVASION_DOWN1_EFFECT": 0x17,
	"CONVERSION_EFFECT": 0x18, "HAZE_EFFECT": 0x19, "BIDE_EFFECT": 0x1A, "THRASH_PETAL_DANCE_EFFECT": 0x1B,
	"SWITCH_AND_TELEPORT_EFFECT": 0x1C, "TWO_TO_FIVE_ATTACKS_EFFECT": 0x1D, "EFFECT_1E": 0x1E, "FLINCH_SIDE_EFFECT1": 0x1F,
	"SLEEP_EFFECT": 0x20, "POISON_SIDE_EFFECT2": 0x21, "BURN_SIDE_EFFECT2": 0x22, "FREEZE_SIDE_EFFECT2": 0x23,
	"PARALYZE_SIDE_EFFECT2": 0x24, "FLINCH_SIDE_EFFECT2": 0x25, "OHKO_EFFECT": 0x26, "CHARGE_EFFECT": 0x27,
	"SUPER_FANG_EFFECT": 0x28, "SPECIAL_DAMAGE_EFFECT": 0x29, "TRAPPING_EFFECT": 0x2A, "FLY_EFFECT": 0x2B,
	"ATTACK_TWICE_EFFECT": 0x2C, "JUMP_KICK_EFFECT": 0x2D, "MIST_EFFECT": 0x2E, "FOCUS_ENERGY_EFFECT": 0x2F,
	"RECOIL_EFFECT": 0x30, "CONFUSION_EFFECT": 0x31, "ATTACK_UP2_EFFECT": 0x32, "DEFENSE_UP2_EFFECT": 0x33,
	"SPEED_UP2_EFFECT": 0x34, "SPECIAL_UP2_EFFECT": 0x35, "ACCURACY_UP2_EFFECT": 0x36, "EVASION_UP2_EFFECT": 0x37,
	"HEAL_EFFECT": 0x38, "TRANSFORM_EFFECT": 0x39, "ATTACK_DOWN2_EFFECT": 0x3A, "DEFENSE_DOWN2_EFFECT": 0x3B,
	"SPEED_DOWN2_EFFECT": 0x3C, "SPECIAL_DOWN2_EFFECT": 0x3D, "ACCURACY_DOWN2_EFFECT": 0x3E, "EVASION_DOWN2_EFFECT": 0x3F,
	"LIGHT_SCREEN_EFFECT": 0x40, "REFLECT_EFFECT": 0x41, "POISON_EFFECT": 0x42, "PARALYZE_EFFECT": 0x43,
	"ATTACK_DOWN_SIDE_EFFECT": 0x44, "DEFENSE_DOWN_SIDE_EFFECT": 0x45, "SPEED_DOWN_SIDE_EFFECT": 0x46,
	"SPECIAL_DOWN_SIDE_EFFECT": 0x47, "CONFUSION_SIDE_EFFECT": 0x4C, "TWINEEDLE_EFFECT": 0x4D,
	"SUBSTITUTE_EFFECT": 0x4F, "HYPER_BEAM_EFFECT": 0x50, "RAGE_EFFECT": 0x51, "MIMIC_EFFECT": 0x52,
	"METRONOME_EFFECT": 0x53, "LEECH_SEED_EFFECT": 0x54, "SPLASH_EFFECT": 0x55, "DISABLE_EFFECT": 0x56,
}
# data/battle/*.asm effect lists
const RESIDUAL_EFFECTS_1 := ["CONVERSION_EFFECT", "HAZE_EFFECT", "SWITCH_AND_TELEPORT_EFFECT", "MIST_EFFECT",
	"FOCUS_ENERGY_EFFECT", "CONFUSION_EFFECT", "HEAL_EFFECT", "TRANSFORM_EFFECT", "LIGHT_SCREEN_EFFECT",
	"REFLECT_EFFECT", "POISON_EFFECT", "PARALYZE_EFFECT", "SUBSTITUTE_EFFECT", "MIMIC_EFFECT",
	"LEECH_SEED_EFFECT", "SPLASH_EFFECT"]
const RESIDUAL_EFFECTS_2 := ["EFFECT_01", "ATTACK_UP1_EFFECT", "DEFENSE_UP1_EFFECT", "SPEED_UP1_EFFECT",
	"SPECIAL_UP1_EFFECT", "ACCURACY_UP1_EFFECT", "EVASION_UP1_EFFECT", "ATTACK_DOWN1_EFFECT",
	"DEFENSE_DOWN1_EFFECT", "SPEED_DOWN1_EFFECT", "SPECIAL_DOWN1_EFFECT", "ACCURACY_DOWN1_EFFECT",
	"EVASION_DOWN1_EFFECT", "BIDE_EFFECT", "SLEEP_EFFECT", "ATTACK_UP2_EFFECT", "DEFENSE_UP2_EFFECT",
	"SPEED_UP2_EFFECT", "SPECIAL_UP2_EFFECT", "ACCURACY_UP2_EFFECT", "EVASION_UP2_EFFECT",
	"ATTACK_DOWN2_EFFECT", "DEFENSE_DOWN2_EFFECT", "SPEED_DOWN2_EFFECT", "SPECIAL_DOWN2_EFFECT",
	"ACCURACY_DOWN2_EFFECT", "EVASION_DOWN2_EFFECT"]
const SPECIAL_EFFECTS := ["DRAIN_HP_EFFECT", "EXPLODE_EFFECT", "DREAM_EATER_EFFECT", "PAY_DAY_EFFECT",
	"SWIFT_EFFECT", "TWO_TO_FIVE_ATTACKS_EFFECT", "EFFECT_1E", "CHARGE_EFFECT", "SUPER_FANG_EFFECT",
	"SPECIAL_DAMAGE_EFFECT", "FLY_EFFECT", "ATTACK_TWICE_EFFECT", "JUMP_KICK_EFFECT", "RECOIL_EFFECT",
	"THRASH_PETAL_DANCE_EFFECT", "TRAPPING_EFFECT"]
const SPECIAL_EFFECTS_CONT := ["THRASH_PETAL_DANCE_EFFECT", "TRAPPING_EFFECT"]
const SET_DAMAGE_EFFECTS := ["SUPER_FANG_EFFECT", "SPECIAL_DAMAGE_EFFECT"]
const ALWAYS_HAPPEN_EFFECTS := ["DRAIN_HP_EFFECT", "EXPLODE_EFFECT", "DREAM_EATER_EFFECT", "PAY_DAY_EFFECT",
	"TWO_TO_FIVE_ATTACKS_EFFECT", "EFFECT_1E", "ATTACK_TWICE_EFFECT", "RECOIL_EFFECT", "TWINEEDLE_EFFECT",
	"RAGE_EFFECT"]
const HIGH_CRITICAL_MOVES := ["KARATE_CHOP", "RAZOR_LEAF", "CRABHAMMER", "SLASH"]
const STATUS_AILMENT_MOVE_EFFECTS := ["EFFECT_01", "SLEEP_EFFECT", "POISON_EFFECT", "PARALYZE_EFFECT"]
const TYPE_MULTIPLIERS := {"SUPER_EFFECTIVE": 20, "NOT_VERY_EFFECTIVE": 5, "NO_EFFECT": 0}
const STATUS_HEAL_ITEMS := ["ANTIDOTE", "BURN_HEAL", "ICE_HEAL", "AWAKENING", "PARLYZ_HEAL", "FULL_HEAL"]
const X_STAT_ITEMS := {"X_ATTACK": "ATTACK_UP1_EFFECT", "X_DEFEND": "DEFENSE_UP1_EFFECT",
	"X_SPEED": "SPEED_UP1_EFFECT", "X_SPECIAL": "SPECIAL_UP1_EFFECT"}


func side(player: bool) -> BattleSide:
	return ps if player else es


func _effect_id(effect: String) -> int:
	return int(EFFECT_IDS.get(effect, 0))


static func _type_id(t: String) -> int:
	return int(GameData.types["ids"].get(t, 0))


## hWhoseTurn (+ the <USER>/<TARGET> names that follow it).
func _set_turn(player: bool) -> void:
	player_turn = player
	_set_user_target(player)


static func _types_of(species: String) -> Array:
	var t: Array = GameData.pokemon[species]["types"]
	return [str(t[0]), str(t[1] if t.size() > 1 else t[0])]


## CalcStat with no stat experience (GetEnemyMonStat: b = 0).
static func _calc_stat(species: String, key: String, dv: int, level: int) -> int:
	var base: int = GameData.pokemon[species][key]
	return ((base + dv) * 2) * level / 100 + 5


## WriteMonMoves for an enemy mon: the base moves, then every learnset move up to
## its level shifts the list up when it is full (the last four moves learnt remain).
static func _write_mon_moves(mon: PartyMon) -> void:
	var data: Dictionary = GameData.pokemon[mon.species]
	var names: Array = []
	for mv in data["moves"]:
		names.append(str(mv))
	for entry in data["learnset"]:
		if int(entry[0]) > mon.level:
			break
		var mv := str(entry[1])
		if mv in names:
			continue
		if names.size() >= 4:
			names.pop_front()
		names.append(mv)
	mon.moves = []
	for mv in names:
		var pp: int = GameData.moves[mv]["pp"]
		mon.moves.append({"move": mv, "pp": pp, "max_pp": pp})


## LoadBattleMonFromParty: the party mon's data, burn/paralysis penalties and badge boosts.
func _load_battle_mon_from_party(index: int) -> void:
	player_index = index
	player_mon = state.party[index]
	if ps == null:
		ps = BattleSide.new()
		ps.player = true
	ps.mon = player_mon
	ps.species = player_mon.species
	ps.types = _types_of(player_mon.species)
	ps.level = player_mon.level
	ps.dvs = player_mon.dvs.duplicate()
	ps.moves = ["", "", "", ""]
	ps.pp = [0, 0, 0, 0]
	for i in mini(4, player_mon.moves.size()):
		ps.moves[i] = str(player_mon.moves[i].move)
		ps.pp[i] = int(player_mon.moves[i].pp)
	for k in ["atk", "def", "spd", "spc"]:
		ps.stats[k] = int(player_mon.stats[k])
		ps.unmod[k] = int(player_mon.stats[k])
	_apply_burn_and_paralysis_penalties(true)
	_apply_badge_stat_boosts()
	for k in MOD_KEYS:
		ps.mods[k] = 7
	Text.ram["wBattleMonNick"] = player_mon.nickname
	_prepare_player_back()


## LoadEnemyMonData (wild and trainer mons): no burn/paralysis penalties here.
func _load_enemy_mon_data(index: int) -> void:
	enemy_index = index
	enemy_mon = enemy_party[index]
	if es == null:
		es = BattleSide.new()
		es.player = false
	es.mon = enemy_mon
	es.species = enemy_mon.species
	es.types = _types_of(enemy_mon.species)
	es.level = enemy_mon.level
	es.dvs = enemy_mon.dvs.duplicate()
	es.moves = ["", "", "", ""]
	es.pp = [0, 0, 0, 0]
	for i in mini(4, enemy_mon.moves.size()):
		es.moves[i] = str(enemy_mon.moves[i].move)
		es.pp[i] = int(GameData.moves[es.moves[i]]["pp"])
	for k in ["atk", "def", "spd", "spc"]:
		es.stats[k] = int(enemy_mon.stats[k])
		es.unmod[k] = int(enemy_mon.stats[k])
	state.pokedex_seen[enemy_mon.species] = true
	last_switch_in_enemy_hp = enemy_mon.hp
	Text.ram["wEnemyMonNick"] = enemy_mon.nickname
	enemy_sheet = _enemy_pic()


## SendOutMon's resets of the player's battle variables.
func _reset_player_battle_vars() -> void:
	damage_mult = 0
	ps.move.num = ""
	ps.used_move = ""
	if es != null:
		es.used_move = ""
	ps.status1 = 0
	ps.status2 = 0
	ps.status3 = 0
	ps.disabled = 0
	ps.disabled_move = ""
	ps.minimized = false
	if es != null:
		es.status1 &= ~USING_TRAPPING_MOVE


## EnemySendOutFirstMon's resets of the enemy's battle variables (before LoadEnemyMonData).
func _reset_enemy_battle_vars() -> void:
	if es != null:
		es.status1 = 0
		es.status2 = 0
		es.status3 = 0
		es.disabled = 0
		es.disabled_move = ""
		es.minimized = false
		es.used_move = ""
	if ps != null:
		ps.used_move = ""
		ps.status1 &= ~USING_TRAPPING_MOVE
	ai_count = 0xFF


# --- stats ------------------------------------------------------------------------------

## QuarterSpeedDueToParalysis + HalveAttackDueToBurn for `on_player`'s mon.
func _apply_burn_and_paralysis_penalties(on_player: bool) -> void:
	_quarter_speed_due_to_paralysis(on_player)
	_halve_attack_due_to_burn(on_player)


func _quarter_speed_due_to_paralysis(on_player: bool) -> void:
	var s := side(on_player)
	if s.mon.status & PartyMon.PAR:
		s.stats.spd = int(s.stats.spd) >> 2
		if s.stats.spd == 0:
			s.stats.spd = 1


func _halve_attack_due_to_burn(on_player: bool) -> void:
	var s := side(on_player)
	if s.mon.status & PartyMon.BRN:
		s.stats.atk = int(s.stats.atk) >> 1
		if s.stats.atk == 0:
			s.stats.atk = 1


## CalculateModifiedStats for one side.
func _calculate_modified_stats(s: BattleSide) -> void:
	for k in ["atk", "def", "spd", "spc"]:
		var r: Array = STAT_RATIOS[int(s.mods[k]) - 1]
		var v: int = int(s.unmod[k]) * int(r[0]) / int(r[1])
		v = mini(v, MAX_STAT_VALUE)
		s.stats[k] = maxi(v, 1)


## ApplyBadgeStatBoosts: x1.125 for the Boulder (atk), Thunder (def), Soul (spd) and Volcano (spc) badges.
func _apply_badge_stat_boosts() -> void:
	var b := state.badges
	var keys := ["atk", "def", "spd", "spc"]
	for i in 4:
		if b & 1:
			var v: int = int(ps.stats[keys[i]])
			ps.stats[keys[i]] = mini(v + (v >> 3), MAX_STAT_VALUE)
		b >>= 2


# --- MainInBattleLoop -----------------------------------------------------------------------

func _main_loop() -> void:
	while not battle_over:
		if player_mon.hp <= 0:
			await _handle_player_mon_fainted()
			continue
		if enemy_mon.hp <= 0:
			await _handle_enemy_mon_fainted()
			continue
		first_mons_not_out_yet = false
		if not (ps.status2 & (NEEDS_TO_RECHARGE | USING_RAGE)):
			es.status1 &= ~FLINCHED
			ps.status1 &= ~FLINCHED
			if not (ps.status1 & (THRASHING_ABOUT | CHARGING_UP)):
				await _display_battle_menu()
				if battle_over:
					return
				if player_mon.status & (PartyMon.FRZ | PartyMon.SLP_MASK):
					pass
				elif ps.status1 & (STORING_ENERGY | USING_TRAPPING_MOVE):
					pass
				elif es.status1 & USING_TRAPPING_MOVE:
					ps.selected_move = CANNOT_MOVE
				elif took_turn:
					pass
				else:
					var chosen := await _move_selection_menu()
					S.restore_bg(menu_saved)
					_draw_huds()
					if not chosen:
						continue
		_select_enemy_move()
		if await _battle_turn():
			return
		_check_num_attacks_left()


## The move order and both executions of one turn. Returns true when the battle ended
## by an escape (wEscapedFromBattle).
func _battle_turn() -> bool:
	var p_sel := ps.selected_move
	var e_sel := es.selected_move
	var player_first := false
	var compare := false
	if p_sel == "QUICK_ATTACK":
		if e_sel == "QUICK_ATTACK":
			compare = true
		else:
			player_first = true
	elif e_sel == "QUICK_ATTACK":
		player_first = false
	elif p_sel == "COUNTER":
		if e_sel == "COUNTER":
			compare = true
	elif e_sel == "COUNTER":
		player_first = true
	else:
		compare = true
	if compare:
		var a: int = ps.stats.spd
		var b: int = es.stats.spd
		if a == b:
			player_first = rng.randi_range(0, 255) < PERCENT_50 + 1
		else:
			player_first = a > b
	if trace:
		print("BATTLE_TURN frame=%d player=%s enemy=%s player_first=%s" % [GB.frame_count, p_sel, e_sel, player_first])
	if player_first:
		if await _execute_move(true):
			if escaped:
				return true
			await _handle_enemy_mon_fainted()
			return battle_over
		if escaped:
			return true
		if await _handle_poison_burn_leech_seed(true):
			await _handle_player_mon_fainted()
			return battle_over
		_draw_huds()
		_set_turn(false)
		if not await _trainer_ai():
			if await _execute_move(false):
				if escaped:
					return true
				await _handle_player_mon_fainted()
				return battle_over
			if escaped:
				return true
		if await _handle_poison_burn_leech_seed(false):
			await _handle_enemy_mon_fainted()
			return battle_over
		_draw_huds()
	else:
		_set_turn(false)
		if not await _trainer_ai():
			if await _execute_move(false):
				if escaped:
					return true
				await _handle_player_mon_fainted()
				return battle_over
			if escaped:
				return true
		if await _handle_poison_burn_leech_seed(false):
			await _handle_enemy_mon_fainted()
			return battle_over
		_draw_huds()
		if await _execute_move(true):
			if escaped:
				return true
			await _handle_enemy_mon_fainted()
			return battle_over
		if escaped:
			return true
		if await _handle_poison_burn_leech_seed(true):
			await _handle_player_mon_fainted()
			return battle_over
		_draw_huds()
	return false


## CheckNumAttacksLeft: a trapping move ends with its counter.
func _check_num_attacks_left() -> void:
	if ps.num_attacks_left == 0:
		ps.status1 &= ~USING_TRAPPING_MOVE
	if es.num_attacks_left == 0:
		es.status1 &= ~USING_TRAPPING_MOVE


## DisplayBattleMenu: returns once FIGHT is chosen or the turn was used.
func _display_battle_menu() -> void:
	if test_item != "":
		var it := test_item
		test_item = ""
		state.give_item(it, 1)
		_draw_huds()
		menu_saved = S.snapshot_bg()
		if ItemUse.is_ball(it):   # test: a ball (the ghost dodges it)
			await _use_ball(it)
			if took_turn and not battle_over:
				_after_bag_item_used()
			return
		if await _use_battle_item(it):
			_after_bag_item_used()
			return
	while true:
		var action := await _battle_menu()
		if trace:
			print("BATTLE_ACTION frame=%d %s" % [GB.frame_count, action])
		match action:
			"fight":
				run_attempts = 0
				S.restore_bg(menu_saved)
				return
			"pkmn":
				if await _party_switch_menu():
					took_turn = true
					return
			"item":
				await _bag()
				if battle_over or took_turn:
					return
			"run":
				if not is_wild:
					await _text("_NoRunningText")
				else:
					if await _try_run(ps.stats.spd):
						return
					took_turn = true
					return


## MoveSelectionMenu (regular): the list UI is `_move_menu`; returns false for B.
## With no usable move Struggle is selected (AnyMoveToSelect).
func _move_selection_menu() -> bool:
	if not _any_move_to_select():
		await _text("_NoMovesLeftText")
		await GB.frames(60)
		return true
	while true:
		move_cursor = ps.move_list_index
		var picked := await _move_menu()
		ps.move_list_index = move_cursor
		if picked < 0:
			return false
		ps.move_list_index = picked
		if int(ps.pp[picked]) == 0:
			await _text("_MoveNoPPText")
			S.restore_bg(menu_saved)
			continue
		if ((ps.disabled >> 4) & 0xF) - 1 == picked:
			await _text("_MoveDisabledText")
			S.restore_bg(menu_saved)
			continue
		ps.selected_move = ps.moves[picked]
		return true
	return false


## AnyMoveToSelect: Struggle when every move (the disabled one excluded) has no PP.
func _any_move_to_select() -> bool:
	ps.selected_move = "STRUGGLE"
	var dslot := (ps.disabled >> 4) & 0xF
	var total := 0
	for i in 4:
		if ps.disabled != 0 and i == dslot - 1:
			continue
		total |= int(ps.pp[i])
	return total != 0


## PrintMenuItem: the TYPE/ and PP box at (0, 8), or "disabled!". The hovered move
## becomes wPlayerSelectedMove (what Counter later checks).
func _print_menu_item(cur: int) -> void:
	Menu.draw_box(0, 8, 9, 3)
	if ps.disabled != 0 and ((ps.disabled >> 4) & 0xF) - 1 == cur:
		Text.place_string(1, 10, "사용불가!" if GameData.lang == "ko" else "disabled!")
		return
	var mv: String = ps.moves[cur]
	ps.selected_move = mv
	var data: Dictionary = GameData.moves[mv]
	var max_pp: int = int(data.pp)
	if cur < player_mon.moves.size() and str(player_mon.moves[cur].move) == mv and not (ps.status3 & TRANSFORMED):
		max_pp = int(player_mon.moves[cur].max_pp)
	if GameData.lang == "ko":
		# the 8x16 Hangul glyphs need two rows: "타입/" on rows 9-10 and the type
		# name beside it instead of below (the Korean ROM overwrites the border here)
		Text.place_string(1, 10, "타입")
		var tname := GameData.type_name(data.type)
		if Text.encode(tname).size() <= 2:
			Text.place_string(5, 10, "/")
			Text.place_string(6, 10, tname)
		else:
			Text.place_string(5, 10, tname)
	else:
		Text.place_string(1, 9, "TYPE")
		Text.place_string(5, 9, "/")
		Text.place_string(2, 10, GameData.type_name(data.type))
	Text.place_string(5, 11, "%2d" % int(ps.pp[cur]))
	Text.place_string(7, 11, "/")
	Text.place_string(8, 11, "%2d" % max_pp)


## SelectEnemyMove (non-link).
func _select_enemy_move() -> void:
	if es.status2 & (NEEDS_TO_RECHARGE | USING_RAGE):
		return
	if es.status1 & (CHARGING_UP | THRASHING_ABOUT):
		return
	if enemy_mon.status & (PartyMon.FRZ | PartyMon.SLP_MASK):
		return
	if es.status1 & (USING_TRAPPING_MOVE | STORING_ENERGY):
		return
	if ps.status1 & USING_TRAPPING_MOVE:
		es.selected_move = CANNOT_MOVE
		return
	if es.moves[1] == "" and es.disabled != 0:
		es.selected_move = "STRUGGLE"
		return
	var pool: Array = es.moves
	if not is_wild:
		pool = _ai_enemy_trainer_choose_moves()
	while true:
		var r := rng.randi_range(0, 255)
		var slot := 3
		if r < PERCENT_25:
			slot = 0
		elif r < PERCENT_50:
			slot = 1
		elif r < 190:   # 75 percent - 1
			slot = 2
		es.move_list_index = slot
		if ((es.disabled >> 4) & 0xF) == slot + 1:
			continue
		var mv: String = pool[slot]
		if mv == "":
			continue
		es.selected_move = mv
		return


# --- ExecutePlayerMove / ExecuteEnemyMove ------------------------------------------------------

## Returns true when the target fainted (b = 0 in the original).
func _execute_move(player: bool) -> bool:
	var a := side(player)
	_set_turn(player)
	if a.selected_move == CANNOT_MOVE:
		return _execute_move_done(player)
	if not player:
		ai_layer2_encouragement += 1
	move_missed = false
	mon_is_disobedient = false
	move_didnt_miss = false
	damage_mult = EFFECTIVE
	if player and took_turn:
		return _execute_move_done(player)
	if is_ghost:   # PrintGhostText
		if player:
			if player_mon.status & (PartyMon.FRZ | PartyMon.SLP_MASK) == 0:
				Text.ram["wBattleMonNick"] = player_mon.nickname
				await _text("_ScaredText")
				return _execute_move_done(player)
		else:
			await _text("_GetOutText")
			return _execute_move_done(player)
	var label := await _check_status_conditions(player)
	if label == "done":
		return _execute_move_done(player)
	if label == "":
		_get_current_move(a)
		label = "can_execute_charging" if a.status1 & CHARGING_UP else "check_charge"
	return await _run_move(player, label)


func _execute_move_done(player: bool) -> bool:
	if player:
		took_turn = false
	return false


## The move execution from one of its entry points (the labels of ExecutePlayerMove).
func _run_move(player: bool, start: String) -> bool:
	var a := side(player)
	var d := side(not player)
	var label := start
	var anim_type := 0
	while true:
		match label:
			"check_charge":
				# CheckIfPlayerNeedsToChargeUp
				if a.move.effect == "CHARGE_EFFECT" or a.move.effect == "FLY_EFFECT":
					await _jump_move_effect(player)
					return false
				label = "can_execute"
			"can_execute_charging":
				a.status1 &= ~(CHARGING_UP | INVULNERABLE)
				if not player:
					move_name_buffer = GameData.move_name(str(a.move.num))
				label = "can_execute"
			"can_execute":
				if not player:
					mon_is_disobedient = false
				await _display_used_move_text(player)
				if player:
					_decrement_pp()
				if a.move.effect in RESIDUAL_EFFECTS_1:
					await _jump_move_effect(player)
					return false
				if a.move.effect in SPECIAL_EFFECTS_CONT:
					await _jump_move_effect(player)
				label = "calc_damage"
			"calc_damage":
				if a.move.effect in SET_DAMAGE_EFFECTS:
					label = "hit_test"
					continue
				_critical_hit_test(player)
				if _handle_counter_move(player):
					label = "handle_missed"
					continue
				var vars := _get_damage_vars(player)
				if not await _calculate_damage(player, vars):
					label = "fly_or_charge"
					continue
				_adjust_damage_for_move_type(player)
				_randomize_damage()
				label = "hit_test"
			"hit_test":
				_move_hit_test(player)
				label = "handle_missed"
			"handle_missed":
				if move_missed:
					if a.move.effect == "EXPLODE_EFFECT":
						anim_type = 0
						label = "play_anim"
					else:
						label = "fly_or_charge"
				else:
					label = "anim_type"
			"anim_type":
				if a.move.effect == "NO_ADDITIONAL_EFFECT":
					anim_type = BattleAnim.TYPE_BLINK_ENEMY_MON_SPRITE if player else BattleAnim.TYPE_SHAKE_SCREEN_VERTICALLY
				else:
					anim_type = BattleAnim.TYPE_SHAKE_SCREEN_HORIZONTALLY_LIGHT if player else BattleAnim.TYPE_SHAKE_SCREEN_HORIZONTALLY_HEAVY
				label = "play_anim"
			"play_anim":
				if a.status2 & HAS_SUBSTITUTE_UP:
					await _hide_substitute_show_mon(player)
				await _play_move_animation(player, str(a.move.num), anim_type)
				await _handle_exploding_animation(player)
				if player:
					_draw_player_hud()
				else:
					_draw_enemy_hud()
				if a.status2 & HAS_SUBSTITUTE_UP:
					await _reshow_substitute(player)
				label = "mirror"
			"fly_or_charge":
				await GB.frames(30)
				if a.move.effect == "FLY_EFFECT" or a.move.effect == "CHARGE_EFFECT":
					await _play_move_animation(player, "STATUS_AFFECTED_ANIM", 0)
				label = "mirror"
			"mirror":
				if a.move.effect == "MIRROR_MOVE_EFFECT":
					if not await _mirror_move_copy_move(player):
						return _execute_move_done(player)
					if player:
						mon_is_disobedient = false
					label = "check_charge"
					continue
				if a.move.effect == "METRONOME_EFFECT":
					await _metronome_pick_move(player)
					label = "check_charge"
					continue
				if a.move.effect in RESIDUAL_EFFECTS_2:
					await _jump_move_effect(player)
					return false
				if move_missed:
					await _print_move_failure_text(player)
					if a.move.effect != "EXPLODE_EFFECT":
						return _execute_move_done(player)
					label = "not_done"
					continue
				await _apply_attack(player)
				await _print_critical_ohko_text()
				await _display_effectiveness()
				move_didnt_miss = true
				label = "not_done"
			"not_done":
				if a.move.effect in ALWAYS_HAPPEN_EFFECTS:
					await _jump_move_effect(player)
				if d.mon.hp <= 0:
					return true
				await _handle_building_rage(player)
				if a.status1 & ATTACKING_MULTIPLE_TIMES:
					a.num_attacks_left = (a.num_attacks_left - 1) & 0xFF
					if a.num_attacks_left != 0:
						label = "anim_type"
						continue
					a.status1 &= ~ATTACKING_MULTIPLE_TIMES
					if player:
						Text.ram["wPlayerNumHits"] = a.num_hits
						await _text("_MultiHitText")
					else:
						Text.ram["wEnemyNumHits"] = a.num_hits
						await _text("_HitXTimesText")
					a.num_hits = 0
				if a.move.effect == "NO_ADDITIONAL_EFFECT":
					return _execute_move_done(player)
				if not a.move.effect in SPECIAL_EFFECTS:
					await _jump_move_effect(player)
				return _execute_move_done(player)
			_:
				push_error("battle: unknown move label " + label)
				return false
	return false


## CheckPlayerStatusConditions / CheckEnemyStatusConditions. Returns "" when the mon
## can move normally, else the label to continue at ("done", "handle_missed",
## "calc_damage", "anim_type", "can_execute").
func _check_status_conditions(player: bool) -> String:
	var a := side(player)
	var d := side(not player)
	var mon := a.mon
	if mon.status & PartyMon.SLP_MASK:
		mon.status = (mon.status & PartyMon.SLP_MASK) - 1
		if mon.status == 0:
			await _text("_WokeUpText")
		elif player:
			await _play_move_animation(true, "SLP_PLAYER_ANIM", 0)
			await _text("_FastAsleepText")
		else:
			await _text("_FastAsleepText")
			await _play_move_animation(false, "SLP_ANIM", 0)
		a.used_move = ""
		return "done"
	if mon.status & PartyMon.FRZ:
		await _text("_IsFrozenText")
		a.used_move = ""
		return "done"
	if d.status1 & USING_TRAPPING_MOVE:
		await _text("_CantMoveText")
		return "done"
	if a.status1 & FLINCHED:
		a.status1 &= ~FLINCHED
		await _text("_FlinchedText")
		return "done"
	if a.status2 & NEEDS_TO_RECHARGE:
		a.status2 &= ~NEEDS_TO_RECHARGE
		await _text("_MustRechargeText")
		return "done"
	if a.disabled != 0:
		a.disabled -= 1
		if (a.disabled & 0xF) == 0:
			a.disabled = 0
			a.disabled_move = ""
			await _text("_DisabledNoMoreText")
	var hurt := false
	if a.status1 & CONFUSED:
		a.confused_counter = (a.confused_counter - 1) & 0xFF
		if a.confused_counter == 0:
			a.status1 &= ~CONFUSED
			await _text("_ConfusedNoMoreText")
		else:
			await _text("_IsConfusedText")
			await _play_move_animation(player, "CONF_PLAYER_ANIM" if player else "CONF_ANIM", 0)
			if rng.randi_range(0, 255) >= PERCENT_50 + 1:
				a.status1 &= CONFUSED
				await _handle_self_confusion_damage(player)
				hurt = true
	if not hurt:
		if a.disabled_move != "" and a.disabled_move == a.selected_move:
			a.status1 &= ~CHARGING_UP
			Text.ram["wNameBuffer"] = GameData.move_name(a.selected_move)
			await _text("_MoveIsDisabledText")
			return "done"
		if mon.status & PartyMon.PAR and rng.randi_range(0, 255) < PERCENT_25:
			await _text("_FullyParalyzedText")
			hurt = true
	if hurt:
		# MonHurtItselfOrFullyParalysed
		a.status1 &= ~(STORING_ENERGY | THRASHING_ABOUT | CHARGING_UP | USING_TRAPPING_MOVE)
		if a.move.effect == "FLY_EFFECT" or a.move.effect == "CHARGE_EFFECT":
			await _play_move_animation(player, "STATUS_AFFECTED_ANIM", 0)
		return "done"
	if a.status1 & STORING_ENERGY:
		a.move.num = ""
		a.bide_damage = (a.bide_damage + damage) & 0xFFFF
		a.num_attacks_left = (a.num_attacks_left - 1) & 0xFF
		if a.num_attacks_left != 0:
			return "done"
		a.status1 &= ~STORING_ENERGY
		await _text("_UnleashedEnergyText")
		a.move.power = 1
		damage = (a.bide_damage * 2) & 0xFFFF
		if damage == 0:
			move_missed = true
		a.bide_damage = 0
		a.move.num = "BIDE"
		return "handle_missed"
	if a.status1 & THRASHING_ABOUT:
		a.move.num = "THRASH"
		await _text("_ThrashingAboutText")
		a.num_attacks_left = (a.num_attacks_left - 1) & 0xFF
		if a.num_attacks_left == 0:
			a.status1 &= ~THRASHING_ABOUT
			a.status1 |= CONFUSED
			a.confused_counter = (rng.randi_range(0, 255) & 3) + 2
		return "calc_damage"
	if a.status1 & USING_TRAPPING_MOVE:
		await _text("_AttackContinuesText")
		a.num_attacks_left = (a.num_attacks_left - 1) & 0xFF
		return "anim_type"
	if a.status2 & USING_RAGE:
		move_name_buffer = GameData.move_name("RAGE")
		a.move.effect = "NO_ADDITIONAL_EFFECT"
		return "can_execute"
	return ""


## HandleSelfConfusionDamage: a typeless 40-power physical hit against its own defense.
func _handle_self_confusion_damage(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	await _text("_HurtItselfText")
	var saved_def: int = d.stats.def
	d.stats.def = a.stats.def
	var saved_effect: String = a.move.effect
	a.move.effect = "NO_ADDITIONAL_EFFECT"
	crit_ohko = 0
	a.move.power = 40
	a.move.type = "NORMAL"
	await _calculate_damage(player, _get_damage_vars(player))
	a.move.effect = saved_effect
	d.stats.def = saved_def
	await _play_move_animation(not player, "POUND", 0)
	if player:
		_draw_player_hud()
	_set_turn(player)
	await _apply_damage(player)


## GetCurrentMove: the selected move's data into wPlayerMoveNum.. and its name.
func _get_current_move(a: BattleSide) -> void:
	_load_move_data(a, a.selected_move)
	move_name_buffer = GameData.move_name(a.selected_move)


func _load_move_data(a: BattleSide, mv: String) -> void:
	var data: Dictionary = GameData.moves[mv]
	a.move = {"num": mv, "effect": str(data.effect), "power": int(data.power), "type": str(data.type),
		"accuracy": int(data.accuracy) * 255 / 100, "pp": int(data.pp)}


## DisplayUsedMoveText: "<USER> used <move>!" (all MoveGrammar sets read the same).
func _display_used_move_text(player: bool) -> void:
	var a := side(player)
	a.used_move = str(a.move.num)
	if trace:
		print("BATTLE_USED frame=%d %s %s" % [GB.frame_count, "player" if player else "enemy", a.move.num])
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text("_ActorNameText"))
	await Text.run_commands(GameData.text("_UsedMove1Text"))
	Text.ram["wStringBuffer"] = move_name_buffer
	await Text.run_commands(GameData.text("_MoveNameText"))
	await Text.run_commands(GameData.text("_EndUsedMove1Text"))


## DecrementPP: not for Struggle, Bide, Thrash, multi-hit moves or Rage; the party
## mon keeps its PP when transformed.
func _decrement_pp() -> void:
	if ps.selected_move == "STRUGGLE":
		return
	if ps.status1 & (STORING_ENERGY | THRASHING_ABOUT | ATTACKING_MULTIPLE_TIMES):
		return
	if ps.status2 & USING_RAGE:
		return
	var i := ps.move_list_index
	ps.pp[i] = maxi(0, int(ps.pp[i]) - 1)
	if ps.status3 & TRANSFORMED:
		return
	if i < player_mon.moves.size():
		player_mon.moves[i].pp = maxi(0, int(player_mon.moves[i].pp) - 1)


## CriticalHitTest: base speed / 2, doubled (halved with Focus Energy, the original
## bug), x4 for the high critical hit moves or / 2 otherwise, against rlc^3(random).
func _critical_hit_test(player: bool) -> void:
	var a := side(player)
	crit_ohko = 0
	var b: int = int(GameData.pokemon[a.species]["spd"]) >> 1
	if int(a.move.power) == 0:
		return
	if a.status2 & GETTING_PUMPED:
		b >>= 1
	else:
		b = mini(b << 1, 255)
	if str(a.move.num) in HIGH_CRITICAL_MOVES:
		b = mini(b << 1, 255)
		b = mini(b << 1, 255)
	else:
		b >>= 1
	var r := rng.randi_range(0, 255)
	r = ((r << 3) | (r >> 5)) & 0xFF
	if r < b:
		crit_ohko = 1


## HandleCounterMove: true when Counter was used (its outcome is final: hit or miss).
func _handle_counter_move(player: bool) -> bool:
	var a := side(player)
	var d := side(not player)
	if a.selected_move != "COUNTER":
		return false
	move_missed = true
	if d.selected_move == "COUNTER":
		return true
	if int(d.move.power) == 0:
		return true
	if not d.move.type in ["NORMAL", "FIGHTING"]:
		return true
	if damage == 0:
		return true
	damage = mini(damage * 2, 0xFFFF)
	move_missed = false
	_move_hit_test(player)
	return true


## GetDamageVarsForPlayerAttack / GetDamageVarsForEnemyAttack: {} for 0 power.
func _get_damage_vars(player: bool) -> Dictionary:
	var a := side(player)
	var d := side(not player)
	damage = 0
	var power: int = a.move.power
	if power == 0:
		return {}
	var physical := _type_id(str(a.move.type)) < _type_id("FIRE")
	var key := "atk" if physical else "spc"
	var dkey := "def" if physical else "spc"
	var defv: int = d.stats[dkey]
	if d.status3 & (HAS_REFLECT_UP if physical else HAS_LIGHT_SCREEN_UP):
		defv = (defv * 2) & 0xFFFF
	var atk: int = a.stats[key]
	if crit_ohko != 0:
		# critical hit: the attacker's party stat and the defender's unmodified stat
		if player:
			defv = _calc_stat(es.species, dkey, int(es.dvs[dkey]), es.level)
			atk = int(player_mon.stats[key])
		else:
			defv = int(player_mon.stats[dkey])
			atk = _calc_stat(es.species, key, int(es.dvs[key]), es.level)
	if (atk >> 8) != 0 or (defv >> 8) != 0:
		defv = (defv >> 2) & 0xFF
		atk = atk >> 2
		if atk == 0:
			atk = 1
		atk &= 0xFF
	else:
		defv &= 0xFF
		atk &= 0xFF
	var level := a.level
	if crit_ohko != 0:
		level = (level << 1) & 0xFF
	return {"atk": atk, "def": defv, "power": power, "level": level}


## CalculateDamage. Returns false for 0 power (and a missed OHKO), which skips the
## type and random adjustments and the hit test.
func _calculate_damage(player: bool, vars: Dictionary) -> bool:
	var a := side(player)
	var eff: String = a.move.effect
	var defv: int = int(vars.get("def", 1))
	if eff == "EXPLODE_EFFECT":
		defv >>= 1
		if defv == 0:
			defv = 1
	if eff == "OHKO_EFFECT":
		await _jump_move_effect(player)
		return not move_missed
	if vars.is_empty():
		return false
	var t: int = (int(vars.level) * 2) / 5 + 2
	var x: int = t * int(vars.power) * int(vars.atk)
	x = x / maxi(defv, 1)   # a 0 defense freezes the original (division by zero)
	x = x / 50
	x = mini(x, 997) + 2
	damage = x
	return true


## AdjustDamageForMoveType: STAB, then every matching TypeEffects pair in table order;
## wDamageMultipliers keeps the last pair's multiplier (plus the STAB bit).
func _adjust_damage_for_move_type(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	var mt: String = a.move.type
	if mt == a.types[0] or mt == a.types[1]:
		damage = (damage + (damage >> 1)) & 0xFFFF
		damage_mult |= 0x80
	for row in GameData.types["matchups"]:
		if str(row[0]) != mt:
			continue
		if str(row[1]) != d.types[0] and str(row[1]) != d.types[1]:
			continue
		var m: int = TYPE_MULTIPLIERS[str(row[2])]
		damage_mult = (damage_mult & 0x80) + m
		damage = (damage * m / 10) & 0xFFFF
		if damage == 0:
			move_missed = true


## RandomizeDamage: x 217..255 / 255 for damage of 2 or more.
func _randomize_damage() -> void:
	if damage < 2:
		return
	var r := 0
	while true:
		r = rng.randi_range(0, 255)
		r = ((r >> 1) | ((r & 1) << 7)) & 0xFF
		if r >= 217:
			break
	damage = (damage * r / 255) & 0xFFFF


## MoveHitTest (with CalcHitChance). The Substitute check for draining moves never
## triggers, like the original.
func _move_hit_test(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	var eff: String = a.move.effect
	var missed := false
	if eff == "DREAM_EATER_EFFECT" and (d.mon.status & PartyMon.SLP_MASK) == 0:
		missed = true
	elif eff == "SWIFT_EFFECT":
		return
	elif d.status1 & INVULNERABLE:
		missed = true
	else:
		var id := _effect_id(eff)
		var mist_affected := (id >= 0x12 and id <= 0x19) or (id >= 0x3A and id <= 0x41)
		if mist_affected and d.status2 & PROTECTED_BY_MIST:
			missed = true
		elif a.status2 & USING_X_ACCURACY:
			return
		else:
			_calc_hit_chance(a, d)
			if rng.randi_range(0, 255) >= int(a.move.accuracy):
				missed = true
	if missed:
		damage = 0
		move_missed = true
		a.status1 &= ~USING_TRAPPING_MOVE


## CalcHitChance: accuracy x the accuracy ratio x the reflected evasion ratio, stored
## back into the move's accuracy.
func _calc_hit_chance(a: BattleSide, d: BattleSide) -> void:
	var acc: int = a.move.accuracy
	for m in [int(a.mods.acc), 14 - int(d.mods.eva)]:
		var r: Array = STAT_RATIOS[m - 1]
		acc = acc * int(r[0]) / int(r[1])
		if (acc & 0xFFFF) == 0:
			acc = 1
	a.move.accuracy = mini(acc, 255)


## ApplyAttackToEnemyPokemon / ApplyAttackToPlayerPokemon.
func _apply_attack(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	var eff: String = a.move.effect
	if eff == "OHKO_EFFECT":
		pass
	elif eff == "SUPER_FANG_EFFECT":
		damage = d.mon.hp >> 1
		if damage == 0:
			damage = 1
	elif eff == "SPECIAL_DAMAGE_EFFECT":
		var b := a.level
		match str(a.move.num):
			"SEISMIC_TOSS", "NIGHT_SHADE":
				pass
			"SONICBOOM":
				b = 20
			"DRAGON_RAGE":
				b = 40
			_:
				# Psywave: [1, level x 1.5) for the player, [0, ...) for the enemy
				b = (a.level + (a.level >> 1)) & 0xFF
				var r := 0
				while true:
					r = rng.randi_range(0, 255)
					if player and r == 0:
						continue
					if r < b:
						break
				b = r
		damage = b
	elif int(a.move.power) == 0:
		_draw_huds()
		return
	await _apply_damage(not player)


## ApplyDamageToEnemyPokemon / ApplyDamageToPlayerPokemon (`target_player`).
func _apply_damage(target_player: bool) -> void:
	if damage == 0:
		_draw_huds()
		return
	var t := side(target_player)
	if t.status2 & HAS_SUBSTITUTE_UP:
		await _attack_substitute()
		return
	var old := t.mon.hp
	var new := old - damage
	if new < 0:
		damage = old
		new = 0
	t.mon.hp = new
	await _animate_hp(target_player, old, new)
	_draw_huds()


## AttackSubstitute: always the substitute of the side whose turn it is not.
func _attack_substitute() -> void:
	await _text("_SubstituteTookDamageText")
	var s := side(not player_turn)
	var broke := damage > 0xFF
	if not broke:
		s.substitute_hp -= damage
		if s.substitute_hp >= 0:
			return
		s.substitute_hp &= 0xFF
		broke = true
	s.status2 &= ~HAS_SUBSTITUTE_UP
	await _text("_SubstituteBrokeText")
	await _hide_substitute_show_mon(not player_turn)
	side(player_turn).move.effect = "NO_ADDITIONAL_EFFECT"
	_draw_huds()


## PrintMoveFailureText (with the Jump Kick crash: 1 HP, wDamage is 0 by then).
func _print_move_failure_text(player: bool) -> void:
	var a := side(player)
	var label := "_DoesntAffectMonText"
	if damage_mult & 0x7F:
		label = "_AttackMissedText"
		if crit_ohko == 0xFF:
			label = "_UnaffectedText"
	await _text(label)
	crit_ohko = 0
	if a.move.effect != "JUMP_KICK_EFFECT":
		return
	damage = damage >> 3
	if damage == 0:
		damage = 1
	await _text("_KeptGoingAndCrashedText")
	await BattleAnim.new(self, player)._shake_screen_horizontally(4)
	await _apply_damage(player)


## PrintCriticalOHKOText + the 20-frame pause.
func _print_critical_ohko_text() -> void:
	if crit_ohko == 1:
		await _text("_CriticalHitText")
		crit_ohko = 0
	elif crit_ohko == 2:
		await _text("_OHKOText")
		crit_ohko = 0
	await GB.frames(20)


## DisplayEffectiveness.
func _display_effectiveness() -> void:
	var m := damage_mult & 0x7F
	if m == EFFECTIVE:
		return
	await _text("_SuperEffectiveText" if m > EFFECTIVE else "_NotVeryEffectiveText")


## HandleBuildingRage: the raging target's attack rises one stage.
func _handle_building_rage(player: bool) -> void:
	var d := side(not player)
	if not (d.status2 & USING_RAGE):
		return
	if int(d.mods.atk) == 13:
		return
	_set_turn(not player)
	d.move.num = ""
	d.move.effect = "ATTACK_UP1_EFFECT"
	await _text("_BuildingRageText")
	await _stat_modifier_up_effect(not player)
	d.move.effect = "NO_ADDITIONAL_EFFECT"
	d.move.num = "RAGE"
	_set_turn(player)


## MirrorMoveCopyMove: the opponent's last used move.
func _mirror_move_copy_move(player: bool) -> bool:
	var a := side(player)
	var d := side(not player)
	var mv := d.used_move
	a.selected_move = mv
	if mv == "MIRROR_MOVE" or mv == "":
		await _text("_MirrorMoveFailedText")
		return false
	_reload_move_data(player, mv)
	return true


## MetronomePickMove: Metronome's animation, then a random move except Metronome and Struggle.
func _metronome_pick_move(player: bool) -> void:
	var a := side(player)
	await _play_move_animation(player, "METRONOME", 0)
	var by_id := {}
	for k in GameData.moves.keys():
		by_id[int(GameData.moves[k]["id"])] = k
	var metronome_id := int(GameData.moves["METRONOME"]["id"])
	var struggle_id := int(GameData.moves["STRUGGLE"]["id"])
	var r := 0
	while true:
		r = rng.randi_range(0, 255)
		if r == 0 or r >= struggle_id or r == metronome_id:
			continue
		break
	a.selected_move = str(by_id[r])
	_reload_move_data(player, a.selected_move)


## ReloadMoveData + IncrementMovePP (the calling move does not lose two PP).
func _reload_move_data(player: bool, mv: String) -> void:
	var a := side(player)
	_load_move_data(a, mv)
	var i := a.move_list_index
	a.pp[i] = int(a.pp[i]) + 1
	if player and i < player_mon.moves.size():
		player_mon.moves[i].pp = int(player_mon.moves[i].pp) + 1
	move_name_buffer = GameData.move_name(mv)


## HandleExplodingAnimation: Selfdestruct / Explosion shake the screen with Mega Punch's
## animation unless the target is invulnerable (always the enemy's flag) or a ghost.
func _handle_exploding_animation(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	var mv := str(a.move.num)
	if mv != "SELFDESTRUCT" and mv != "EXPLOSION":
		return
	if es.status1 & INVULNERABLE:
		return
	if "GHOST" in d.types:
		return
	if move_missed:
		return
	await _play_move_animation(player, "MEGA_PUNCH", BattleAnim.TYPE_SHAKE_SCREEN_HORIZONTALLY_LIGHT)


# --- HandlePoisonBurnLeechSeed -------------------------------------------------------------

## Returns true when the mon fainted.
func _handle_poison_burn_leech_seed(player: bool) -> bool:
	_set_turn(player)
	var a := side(player)
	var mon := a.mon
	if mon.status & (PartyMon.BRN | PartyMon.PSN):
		await _text("_HurtByBurnText" if mon.status & PartyMon.BRN else "_HurtByPoisonText")
		await _play_move_animation(player, "BURN_PSN_ANIM", 0)
		await _poison_burn_seed_decrease_own_hp(player)
	if a.status2 & SEEDED:
		await _play_move_animation(not player, "ABSORB", 0)
		_set_turn(player)
		var dmg := await _poison_burn_seed_decrease_own_hp(player)
		await _poison_burn_seed_increase_enemy_hp(player, dmg)
		await _text("_HurtByLeechSeedText")
	if mon.hp > 0:
		return false
	_draw_huds()
	await GB.frames(20)
	return true


## HandlePoisonBurnLeechSeed_DecreaseOwnHP: max HP / 16 (x the Toxic counter), at least 1.
func _poison_burn_seed_decrease_own_hp(player: bool) -> int:
	var a := side(player)
	var dmg := ((a.mon.max_hp >> 2) & 0xFF) >> 2
	if dmg == 0:
		dmg = 1
	if a.status3 & BADLY_POISONED:
		a.toxic_counter = (a.toxic_counter + 1) & 0xFF
		dmg = (dmg * a.toxic_counter) & 0xFFFF
	var old := a.mon.hp
	a.mon.hp = maxi(0, old - dmg)
	await _animate_hp(player, old, a.mon.hp)
	return dmg


## HandlePoisonBurnLeechSeed_IncreaseEnemyHP.
func _poison_burn_seed_increase_enemy_hp(player: bool, dmg: int) -> void:
	var o := side(not player)
	var old := o.mon.hp
	o.mon.hp = mini(o.mon.max_hp, old + dmg)
	await _animate_hp(not player, old, o.mon.hp)


# --- animations -------------------------------------------------------------------------

## PlayMoveAnimation (core.asm): Delay3, then MoveAnimation.
func _play_move_animation(player: bool, anim: String, type: int) -> void:
	if anim == "":
		return
	await BattleAnim.play(self, anim, type, player, damage_mult & 0x7F)


## PlayBattleAnimation (effects.asm): MoveAnimation without the Delay3.
func _play_battle_animation(player: bool, anim: String, type: int = 0) -> void:
	if anim == "":
		return
	var a := BattleAnim.new(self, player)
	a.anim_id = BattleAnim.id_of(anim)
	a.anim_type = type
	a.damage_mult = damage_mult & 0x7F
	await a._move_animation()


## PlayBattleAnimation2: the slow horizontal shake type for the turn.
func _play_battle_animation2(player: bool, anim: String) -> void:
	await _play_battle_animation(player, anim,
		BattleAnim.TYPE_SHAKE_SCREEN_HORIZONTALLY_SLOW_2 if player else BattleAnim.TYPE_SHAKE_SCREEN_HORIZONTALLY_SLOW)


## PlayCurrentMoveAnimation (type 0) / PlayCurrentMoveAnimation2: nothing for move 0.
func _play_current_move_animation(player: bool) -> void:
	await _play_battle_animation(player, str(side(player).move.num), 0)


func _play_current_move_animation2(player: bool) -> void:
	var mv := str(side(player).move.num)
	if mv == "":
		return
	await _play_battle_animation2(player, mv)


## The picture sheet the animation engine draws for a side (wTempPic / the mon pic in VRAM).
func _set_pic_sheet(player: bool, sheet_name: String) -> void:
	if player:
		player_back_sheet = sheet_name
	else:
		enemy_sheet = sheet_name


## The mon's own picture (its battle species: Transform changes it).
func _restore_mon_pic_sheet(player: bool) -> void:
	var s := side(player)
	if player:
		_prepare_player_back(s.species)
	else:
		enemy_sheet = _enemy_pic(s.species)


## AnimationSubstitute's picture: the doll (MonsterSprite) inside a blank 7x7 pic.
func _substitute_sheet(player: bool) -> String:
	var name := "substitute_doll_%s" % ("player" if player else "enemy")
	var src := S.sheet_image("spr_monster")
	var img := Image.create(56, 56, false, Image.FORMAT_R8)
	img.fill(Color8(0, 0, 0))
	var base := 4 if player else 0
	var x0 := 3 if player else 2
	for k in 4:
		var t := base + k
		var rect := Rect2i((t % 4) * 8, (t / 4) * 8, 8, 8)
		img.blit_rect(src, rect, Vector2i((x0 + (k % 2)) * 8, (4 + k / 2) * 8))
	S.image_sheet(name, img)
	return name


## HideSubstituteShowMonAnim: the substitute slides off (or down when it broke), then
## the mon (or its minimized dot) is shown again.
func _hide_substitute_show_mon(player: bool) -> void:
	var s := side(player)
	var a := BattleAnim.new(self, player)
	if s.status2 & HAS_SUBSTITUTE_UP:
		await a._slide_mon_off(player, 8, 3)
	else:
		await a._slide_mon_down(player)
	_restore_mon_pic_sheet(player)
	if s.minimized:
		a._hide_pic(player)
		await a._draw_minimized(player)
		await GB.delay3()
		return
	a._change_mon_pic(player)
	await a._show_mon_pic(player)


## ReshowSubstituteAnim.
func _reshow_substitute(player: bool) -> void:
	var a := BattleAnim.new(self, player)
	await a._slide_mon_off(player, 8, 3)
	_set_pic_sheet(player, _substitute_sheet(player))
	await a._show_mon_pic(player)
	await a._show_mon_pic(player)


# --- move effects (effects.asm, engine/battle/move_effects) ------------------------------------

## JumpMoveEffect: the handler of the current move's effect (MoveEffectPointerTable).
func _jump_move_effect(player: bool) -> void:
	var eff: String = side(player).move.effect
	if trace:
		print("BATTLE_EFFECT frame=%d %s %s" % [GB.frame_count, "player" if player else "enemy", eff])
	match eff:
		"EFFECT_01", "SLEEP_EFFECT":
			await _sleep_effect(player)
		"POISON_SIDE_EFFECT1", "POISON_SIDE_EFFECT2", "POISON_EFFECT":
			await _poison_effect(player)
		"DRAIN_HP_EFFECT", "DREAM_EATER_EFFECT":
			await _drain_hp_effect(player)
		"BURN_SIDE_EFFECT1", "FREEZE_SIDE_EFFECT1", "PARALYZE_SIDE_EFFECT1", \
		"BURN_SIDE_EFFECT2", "FREEZE_SIDE_EFFECT2", "PARALYZE_SIDE_EFFECT2":
			await _freeze_burn_paralyze_effect(player)
		"EXPLODE_EFFECT":
			_explode_effect(player)
		"ATTACK_UP1_EFFECT", "DEFENSE_UP1_EFFECT", "SPEED_UP1_EFFECT", "SPECIAL_UP1_EFFECT", \
		"ACCURACY_UP1_EFFECT", "EVASION_UP1_EFFECT", "ATTACK_UP2_EFFECT", "DEFENSE_UP2_EFFECT", \
		"SPEED_UP2_EFFECT", "SPECIAL_UP2_EFFECT", "ACCURACY_UP2_EFFECT", "EVASION_UP2_EFFECT":
			await _stat_modifier_up_effect(player)
		"ATTACK_DOWN1_EFFECT", "DEFENSE_DOWN1_EFFECT", "SPEED_DOWN1_EFFECT", "SPECIAL_DOWN1_EFFECT", \
		"ACCURACY_DOWN1_EFFECT", "EVASION_DOWN1_EFFECT", "ATTACK_DOWN2_EFFECT", "DEFENSE_DOWN2_EFFECT", \
		"SPEED_DOWN2_EFFECT", "SPECIAL_DOWN2_EFFECT", "ACCURACY_DOWN2_EFFECT", "EVASION_DOWN2_EFFECT", \
		"ATTACK_DOWN_SIDE_EFFECT", "DEFENSE_DOWN_SIDE_EFFECT", "SPEED_DOWN_SIDE_EFFECT", "SPECIAL_DOWN_SIDE_EFFECT":
			await _stat_modifier_down_effect(player)
		"PAY_DAY_EFFECT":
			await _pay_day_effect(player)
		"CONVERSION_EFFECT":
			await _conversion_effect(player)
		"HAZE_EFFECT":
			await _haze_effect(player)
		"BIDE_EFFECT":
			await _bide_effect(player)
		"THRASH_PETAL_DANCE_EFFECT":
			await _thrash_petal_dance_effect(player)
		"SWITCH_AND_TELEPORT_EFFECT":
			await _switch_and_teleport_effect(player)
		"TWO_TO_FIVE_ATTACKS_EFFECT", "EFFECT_1E", "ATTACK_TWICE_EFFECT", "TWINEEDLE_EFFECT":
			_two_to_five_attacks_effect(player)
		"FLINCH_SIDE_EFFECT1", "FLINCH_SIDE_EFFECT2":
			_flinch_side_effect(player)
		"OHKO_EFFECT":
			_one_hit_ko_effect(player)
		"CHARGE_EFFECT", "FLY_EFFECT":
			await _charge_effect(player)
		"TRAPPING_EFFECT":
			_trapping_effect(player)
		"MIST_EFFECT":
			await _mist_effect(player)
		"FOCUS_ENERGY_EFFECT":
			await _focus_energy_effect(player)
		"RECOIL_EFFECT":
			await _recoil_effect(player)
		"CONFUSION_EFFECT", "CONFUSION_SIDE_EFFECT":
			await _confusion_effect(player)
		"HEAL_EFFECT":
			await _heal_effect(player)
		"TRANSFORM_EFFECT":
			await _transform_effect(player)
		"LIGHT_SCREEN_EFFECT", "REFLECT_EFFECT":
			await _reflect_light_screen_effect(player)
		"PARALYZE_EFFECT":
			await _paralyze_effect(player)
		"SUBSTITUTE_EFFECT":
			await _substitute_effect(player)
		"HYPER_BEAM_EFFECT":
			side(player).status2 |= NEEDS_TO_RECHARGE
		"RAGE_EFFECT":
			side(player).status2 |= USING_RAGE
		"MIMIC_EFFECT":
			await _mimic_effect(player)
		"LEECH_SEED_EFFECT":
			await _leech_seed_effect(player)
		"SPLASH_EFFECT":
			await _play_current_move_animation(player)
			await _text("_NoEffectText")
		"DISABLE_EFFECT":
			await _disable_effect(player)
		_:
			pass   # NULL handlers (Swift, Super Fang, special damage, Jump Kick, ...)


## ClearHyperBeam: the target no longer needs to recharge.
func _clear_hyper_beam(player: bool) -> void:
	side(not player).status2 &= ~NEEDS_TO_RECHARGE


## ConditionalPrintButItFailed.
func _conditional_print_but_it_failed() -> void:
	if move_didnt_miss:
		return
	await _text("_ButItFailedText")


func _sleep_effect(player: bool) -> void:
	var d := side(not player)
	var had_recharge := (d.status2 & NEEDS_TO_RECHARGE) != 0
	d.status2 &= ~NEEDS_TO_RECHARGE
	if not had_recharge:
		if d.mon.status & PartyMon.SLP_MASK:
			await _text("_AlreadyAsleepText")
			return
		if d.mon.status != 0:
			await _text("_DidntAffectText")
			return
		_move_hit_test(player)
		if move_missed:
			await _text("_DidntAffectText")
			return
	var t := 0
	while t == 0:
		t = rng.randi_range(0, 255) & PartyMon.SLP_MASK
	d.mon.status = t
	await _play_current_move_animation2(player)
	await _text("_FellAsleepText")


func _poison_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	var eff: String = a.move.effect
	var no_effect := (d.status2 & HAS_SUBSTITUTE_UP) != 0 or d.mon.status != 0 or "POISON" in d.types
	if no_effect:
		if eff == "POISON_EFFECT":
			await GB.frames(50)
			await _text("_DidntAffectText")
		return
	if eff == "POISON_SIDE_EFFECT1" or eff == "POISON_SIDE_EFFECT2":
		var chance := PERCENT_20 + 1 if eff == "POISON_SIDE_EFFECT1" else PERCENT_40 + 1
		if rng.randi_range(0, 255) >= chance:
			return
	else:
		_move_hit_test(player)
		if move_missed:
			await GB.frames(50)
			await _text("_DidntAffectText")
			return
	d.mon.status |= PartyMon.PSN
	var label := "_PoisonedText"
	if str(a.move.num) == "TOXIC":
		d.status3 |= BADLY_POISONED
		d.toxic_counter = 0
		label = "_BadlyPoisonedText"
	if eff == "POISON_EFFECT":
		await _play_current_move_animation2(player)
	else:
		await _play_battle_animation2(player, "ENEMY_HUD_SHAKE_ANIM" if player else "SHAKE_SCREEN_ANIM")
	await _text(label)


## DrainHPEffect_: half the damage back (at least 1).
func _drain_hp_effect(player: bool) -> void:
	var a := side(player)
	damage = damage >> 1
	if damage == 0:
		damage = 1
	var old := a.mon.hp
	a.mon.hp = mini(old + damage, a.mon.max_hp)
	await _animate_hp(player, old, a.mon.hp)
	_draw_huds()
	await _text("_DreamWasEatenText" if a.move.effect == "DREAM_EATER_EFFECT" else "_SuckedHealthText")


func _explode_effect(player: bool) -> void:
	var a := side(player)
	a.mon.hp = 0
	a.mon.status = 0
	a.status2 &= ~SEEDED


## FreezeBurnParalyzeEffect: only the player's infliction shakes the enemy HUD.
func _freeze_burn_paralyze_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	if d.status2 & HAS_SUBSTITUTE_UP:
		return
	if d.mon.status != 0:
		await _check_defrost(player)
		return
	if a.move.type == d.types[0] or a.move.type == d.types[1]:
		return
	var eff: String = a.move.effect
	var chance := PERCENT_10 + 1 if _effect_id(eff) < 0x07 else PERCENT_30 + 1
	if rng.randi_range(0, 255) >= chance:
		return
	if eff.begins_with("BURN"):
		d.mon.status = PartyMon.BRN
		_halve_attack_due_to_burn(not player)
		if player:
			await _play_battle_animation(player, "ENEMY_HUD_SHAKE_ANIM", 0)
		await _text("_BurnedText")
	elif eff.begins_with("FREEZE"):
		if player:
			_clear_hyper_beam(player)
		d.mon.status = PartyMon.FRZ
		if player:
			await _play_battle_animation(player, "ENEMY_HUD_SHAKE_ANIM", 0)
		await _text("_FrozenText")
	else:
		d.mon.status = PartyMon.PAR
		_quarter_speed_due_to_paralysis(not player)
		if player:
			await _play_battle_animation(player, "ENEMY_HUD_SHAKE_ANIM", 0)
		await _text("_ParalyzedMayNotAttackText")


## CheckDefrost: a fire move thaws a frozen target.
func _check_defrost(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	if not (d.mon.status & PartyMon.FRZ):
		return
	if a.move.type != "FIRE":
		return
	d.mon.status = 0
	await _text("_FireDefrostedText")


## StatModifierUpEffect (also X items and Building Rage).
func _stat_modifier_up_effect(player: bool) -> void:
	var a := side(player)
	var id := _effect_id(str(a.move.effect))
	var idx := id - 0x0A
	if idx >= 8:
		idx -= 0x28
	var key: String = MOD_KEYS[idx]
	var m: int = int(a.mods[key]) + 1
	if m > 13:
		await _text("_NothingHappenedText")
		return
	if id >= 0x0A + 8:
		m += 1
		if m > 13:
			m = 13
	a.mods[key] = m
	if idx < 4:
		if int(a.stats[key]) == MAX_STAT_VALUE:
			a.mods[key] = m - 1   # RestoreOriginalStatModifier (one stage back)
			await _text("_NothingHappenedText")
			return
		var r: Array = STAT_RATIOS[m - 1]
		a.stats[key] = mini(int(a.unmod[key]) * int(r[0]) / int(r[1]), MAX_STAT_VALUE)
	# UpdateStatDone
	Text.ram["wStringBuffer"] = (STAT_NAMES_KO if GameData.lang == "ko" else STAT_NAMES_EN)[key]
	var minimize := str(a.move.num) == "MINIMIZE"
	var sub := (a.status2 & HAS_SUBSTITUTE_UP) != 0
	if minimize and sub:
		await _hide_substitute_show_mon(player)
	await _play_current_move_animation(player)
	if minimize:
		a.minimized = true
		if sub:
			await _reshow_substitute(player)
	if player:
		_apply_badge_stat_boosts()
	_set_turn(player)
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	if trace:
		print("BATTLE_TEXT frame=%d _MonsStatsRoseText %s" % [GB.frame_count, key])
	await Text.run_commands(GameData.text("_MonsStatsRoseText"))
	if id >= 0x12:
		await Text.run_commands([["text_pause", ""]])
		await Text.run_commands(GameData.text("_GreatlyRoseText"))
	await Text.run_commands(GameData.text("_RoseText"))
	# these shouldn't be here (the original): the other side's penalties again
	_quarter_speed_due_to_paralysis(not player)
	_halve_attack_due_to_burn(not player)


## StatModifierDownEffect (also the stat-down side effects).
func _stat_modifier_down_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	var eff: String = a.move.effect
	var id := _effect_id(eff)
	var side_effect := id >= 0x44
	if not player and rng.randi_range(0, 255) < PERCENT_25 + 1:
		if not side_effect:
			await _conditional_print_but_it_failed()
		return
	if d.status2 & HAS_SUBSTITUTE_UP:
		if not side_effect:
			await _conditional_print_but_it_failed()
		return
	var idx := 0
	if side_effect:
		if rng.randi_range(0, 255) >= PERCENT_33 + 1:
			return
		idx = id - 0x44
	else:
		_move_hit_test(player)
		if move_missed or d.status1 & INVULNERABLE:
			await _conditional_print_but_it_failed()
			return
		idx = id - 0x12
		if idx >= 8:
			idx -= 0x28
	var key: String = MOD_KEYS[idx]
	var m: int = int(d.mods[key]) - 1
	if m == 0:
		if not side_effect:
			await _text("_NothingHappenedText")
		return
	if id >= 0x24 and not side_effect:
		m -= 1
		if m == 0:
			m = 1
	d.mods[key] = m
	if idx < 4:
		if int(d.stats[key]) == 1:
			d.mods[key] = m + 1   # CantLowerAnymore_Pop
			if not side_effect:
				await _text("_NothingHappenedText")
			return
		var r: Array = STAT_RATIOS[m - 1]
		d.stats[key] = maxi(int(d.unmod[key]) * int(r[0]) / int(r[1]), 1)
	# UpdateLoweredStatDone
	Text.ram["wStringBuffer"] = (STAT_NAMES_KO if GameData.lang == "ko" else STAT_NAMES_EN)[key]
	if not side_effect:
		await _play_current_move_animation2(player)
	if not player:
		_apply_badge_stat_boosts()
	_set_turn(player)
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	if trace:
		print("BATTLE_TEXT frame=%d _MonsStatsFellText %s" % [GB.frame_count, key])
	await Text.run_commands(GameData.text("_MonsStatsFellText"))
	if id >= 0x1A and not side_effect:
		await Text.run_commands([["text_pause", ""]])
		await Text.run_commands(GameData.text("_GreatlyFellText"))
	await Text.run_commands(GameData.text("_FellText"))
	_quarter_speed_due_to_paralysis(not player)
	_halve_attack_due_to_burn(not player)


## BideEffect: 2-3 turns of storing; both move effects are cleared (the original).
func _bide_effect(player: bool) -> void:
	var a := side(player)
	a.status1 |= STORING_ENERGY
	a.bide_damage = 0
	ps.move.effect = "NO_ADDITIONAL_EFFECT"
	es.move.effect = "NO_ADDITIONAL_EFFECT"
	a.num_attacks_left = (rng.randi_range(0, 255) & 1) + 2
	await _play_battle_animation2(player, "XSTATITEM_ANIM" if player else "XSTATITEM_DUPLICATE_ANIM")


func _thrash_petal_dance_effect(player: bool) -> void:
	var a := side(player)
	a.status1 |= THRASHING_ABOUT
	a.num_attacks_left = (rng.randi_range(0, 255) & 1) + 2
	await _play_battle_animation2(player, "SHRINKING_SQUARE_ANIM" if player else "ANIM_B1")


## SwitchAndTeleportEffect: Teleport / Roar / Whirlwind end a wild battle.
func _switch_and_teleport_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	var mv := str(a.move.num)
	if not is_wild:
		await GB.frames(50)
		if mv == "TELEPORT":
			if player:
				await _text("_ButItFailedText")
			else:
				await _conditional_print_but_it_failed()
		else:
			await _text("_IsUnaffectedText")
		return
	var success := a.level >= d.level
	if not success:
		var c := (a.level + d.level + 1) & 0xFF
		var r := 0
		while true:
			r = rng.randi_range(0, 255)
			if r < c:
				break
		success = r >= (d.level >> 2)
	if not success:
		await GB.frames(50)
		await _text("_ButItFailedText" if mv == "TELEPORT" else "_DidntAffectText")
		return
	escaped = true
	await _play_battle_animation(player, mv, 0)
	await GB.frames(20)
	var label := "_WasBlownAwayText"
	if mv == "TELEPORT":
		label = "_RanFromBattleText"
	elif mv == "ROAR":
		label = "_RanAwayScaredText"
	await _text(label)
	result = "ran"
	battle_over = true


func _two_to_five_attacks_effect(player: bool) -> void:
	var a := side(player)
	if a.status1 & ATTACKING_MULTIPLE_TIMES:
		return
	a.status1 |= ATTACKING_MULTIPLE_TIMES
	var n := 2
	if a.move.effect == "TWINEEDLE_EFFECT":
		a.move.effect = "POISON_SIDE_EFFECT1"
	elif a.move.effect != "ATTACK_TWICE_EFFECT":
		var r := rng.randi_range(0, 255) & 3
		if r >= 2:
			r = rng.randi_range(0, 255) & 3
		n = r + 2
	a.num_attacks_left = n
	a.num_hits = n


func _flinch_side_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	if d.status2 & HAS_SUBSTITUTE_UP:
		return
	var chance: int = PERCENT_10 + 1 if a.move.effect == "FLINCH_SIDE_EFFECT1" else PERCENT_30 + 1
	if rng.randi_range(0, 255) >= chance:
		return
	d.status1 |= FLINCHED
	_clear_hyper_beam(player)


## OneHitKOEffect_: 65535 damage when the user is at least as fast.
func _one_hit_ko_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	damage = 0
	crit_ohko = 0xFF
	if int(a.stats.spd) >= int(d.stats.spd):
		damage = 0xFFFF
		crit_ohko = 2
	else:
		move_missed = true


## ChargeEffect: the first turn of Razor Wind, Solarbeam, Skull Bash, Sky Attack, Fly, Dig.
func _charge_effect(player: bool) -> void:
	var a := side(player)
	a.status1 |= CHARGING_UP
	var anim := "XSTATITEM_ANIM" if player else "XSTATITEM_DUPLICATE_ANIM"
	var mv := str(a.move.num)
	if a.move.effect == "FLY_EFFECT":
		a.status1 |= INVULNERABLE
		anim = "TELEPORT"
	if mv == "DIG":
		a.status1 |= INVULNERABLE
		anim = "SLIDE_DOWN_ANIM"
	await _play_battle_animation(player, anim, 0)
	var labels := {"RAZOR_WIND": "_MadeWhirlwindText", "SOLARBEAM": "_TookInSunlightText",
		"SKULL_BASH": "_LoweredItsHeadText", "SKY_ATTACK": "_SkyAttackGlowingText", "FLY": "_FlewUpHighText"}
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text("_ChargeMoveEffectText"))
	await Text.run_commands(GameData.text(str(labels.get(mv, "_DugAHoleText"))))


func _trapping_effect(player: bool) -> void:
	var a := side(player)
	if a.status1 & USING_TRAPPING_MOVE:
		return
	_clear_hyper_beam(player)
	a.status1 |= USING_TRAPPING_MOVE
	var r := rng.randi_range(0, 255) & 3
	if r >= 2:
		r = rng.randi_range(0, 255) & 3
	a.num_attacks_left = r + 1


func _mist_effect(player: bool) -> void:
	var a := side(player)
	if a.status2 & PROTECTED_BY_MIST:
		await _text("_ButItFailedText")
		return
	a.status2 |= PROTECTED_BY_MIST
	await _play_current_move_animation(player)
	await _text("_ShroudedInMistText")


func _focus_energy_effect(player: bool) -> void:
	var a := side(player)
	if a.status2 & GETTING_PUMPED:
		await GB.frames(50)
		await _text("_ButItFailedText")
		return
	a.status2 |= GETTING_PUMPED
	await _play_current_move_animation(player)
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands([["text_pause", ""]])
	await Text.run_commands(GameData.text("_GettingPumpedText"))


## RecoilEffect_: a quarter of the damage (half for Struggle), at least 1.
func _recoil_effect(player: bool) -> void:
	var a := side(player)
	var r := damage >> 1
	if str(a.move.num) != "STRUGGLE":
		r >>= 1
	if r == 0:
		r = 1
	var old := a.mon.hp
	a.mon.hp = maxi(0, old - r)
	await _animate_hp(player, old, a.mon.hp)
	await _text("_HitWithRecoilText")


## ConfusionEffect / ConfusionSideEffect.
func _confusion_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	var side_effect: bool = a.move.effect == "CONFUSION_SIDE_EFFECT"
	var ok := true
	if side_effect:
		if rng.randi_range(0, 255) >= PERCENT_10:
			return
	else:
		if d.status2 & HAS_SUBSTITUTE_UP:
			ok = false
		else:
			_move_hit_test(player)
			ok = not move_missed
	if ok and d.status1 & CONFUSED:
		ok = false
	if not ok:
		if side_effect:
			return
		await GB.frames(50)
		await _conditional_print_but_it_failed()
		return
	d.status1 |= CONFUSED
	d.confused_counter = (rng.randi_range(0, 255) & 3) + 2
	if not side_effect:
		await _play_current_move_animation2(player)
	await _text("_BecameConfusedText")


## HealEffect_ (Recover, Softboiled, Rest). Only the low bytes are compared to the
## max HP (the original), so 255 / 511 HP short of the max also fails.
func _heal_effect(player: bool) -> void:
	var a := side(player)
	var cur := a.mon.hp
	var mx := a.mon.max_hp
	var c1 := 1 if (cur >> 8) < (mx >> 8) else 0
	if (((cur & 0xFF) - (mx & 0xFF) - c1) & 0xFF) == 0:
		await GB.frames(50)
		await _text("_ButItFailedText")
		return
	var rest := str(a.move.num) == "REST"
	if rest:
		await GB.frames(50)
		var had := a.mon.status != 0
		a.mon.status = 2
		await _text("_FellAsleepBecameHealthyText" if had else "_StartedSleepingEffect")
	var amount := mx if rest else mx >> 1
	var new := mini(cur + amount, mx)
	a.mon.hp = new
	await _play_current_move_animation(player)
	await _animate_hp(player, cur, new)
	_draw_huds()
	await _text("_RegainedHealthText")


## TransformEffect_. The invulnerability check reads the wrong flags (the original):
## the player's own, and never anything on the enemy's turn.
func _transform_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	if player:
		a.move_list_index = 0
		if a.status1 & INVULNERABLE:
			await _text("_ButItFailedText")
			return
	var sub := (a.status2 & HAS_SUBSTITUTE_UP) != 0
	if sub:
		await _hide_substitute_show_mon(player)
	if Settings.battle_animation_on():
		await _play_current_move_animation(player)
	else:
		BattleAnim.new(self, player)._transform_mon()
	if sub:
		await _reshow_substitute(player)
	a.status3 |= TRANSFORMED
	a.species = d.species
	a.types = d.types.duplicate()
	a.moves = d.moves.duplicate()
	a.dvs = d.dvs.duplicate()
	for k in ["atk", "def", "spd", "spc"]:
		a.stats[k] = d.stats[k]
		a.unmod[k] = d.unmod[k]
	for k in MOD_KEYS:
		a.mods[k] = d.mods[k]
	for i in 4:
		a.pp[i] = 5 if a.moves[i] != "" else 0
	if not sub:
		_restore_mon_pic_sheet(player)
		_draw_sheet(player_back_sheet if player else enemy_sheet, 1 if player else 12, 5 if player else 0)
	Text.ram["wNameBuffer"] = GameData.mon_name(d.species)
	await _text("_TransformedText")


func _reflect_light_screen_effect(player: bool) -> void:
	var a := side(player)
	var light: bool = a.move.effect == "LIGHT_SCREEN_EFFECT"
	var bit := HAS_LIGHT_SCREEN_UP if light else HAS_REFLECT_UP
	if a.status3 & bit:
		await GB.frames(50)
		await _text("_ButItFailedText")
		return
	a.status3 |= bit
	await _play_current_move_animation(player)
	await _text("_LightScreenProtectedText" if light else "_ReflectGainedArmorText")


func _paralyze_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	if d.mon.status != 0:
		await GB.frames(50)
		await _text("_DidntAffectText")
		return
	if a.move.type == "ELECTRIC" and "GROUND" in d.types:
		await GB.frames(50)
		await _text("_DoesntAffectMonText")
		return
	_move_hit_test(player)
	if move_missed:
		await GB.frames(50)
		await _text("_DidntAffectText")
		return
	d.mon.status |= PartyMon.PAR
	_quarter_speed_due_to_paralysis(not player)
	await GB.frames(30)
	await _play_current_move_animation(player)
	await _text("_ParalyzedMayNotAttackText")


## SubstituteEffect_: a quarter of the max HP; 0 HP left is allowed (the original).
func _substitute_effect(player: bool) -> void:
	var a := side(player)
	await GB.frames(50)
	if a.status2 & HAS_SUBSTITUTE_UP:
		await _text("_HasSubstituteText")
		return
	var q := (a.mon.max_hp >> 2) & 0xFF
	a.substitute_hp = q
	var new := a.mon.hp - q
	if new < 0:
		await _text("_TooWeakSubstituteText")
		return
	a.mon.hp = new
	a.status2 |= HAS_SUBSTITUTE_UP
	_set_pic_sheet(player, _substitute_sheet(player))
	if Settings.battle_animation_on():
		await _play_current_move_animation(player)   # its SE_SUBSTITUTE_MON shows the doll
	else:
		await BattleAnim.new(self, player)._show_mon_pic(player)   # AnimationSubstitute
	await _text("_SubstituteText")
	_draw_huds()


## MimicEffect: the player picks one of the enemy's moves; the enemy copies a random one.
func _mimic_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	await GB.frames(50)
	_move_hit_test(player)
	if move_missed or d.status1 & INVULNERABLE:
		await _text("_ButItFailedText")
		return
	var mv := ""
	if player:
		var idx := await _mimic_menu()
		mv = es.moves[idx]
	else:
		while mv == "":
			mv = ps.moves[rng.randi_range(0, 255) & 3]
	a.moves[a.move_list_index] = mv
	Text.ram["wNameBuffer"] = GameData.move_name(mv)
	await _play_current_move_animation(player)
	await _text("_MimicLearnedMoveText")


## MoveSelectionMenu with wMoveMenuType 1: the enemy's moves, no B.
func _mimic_menu() -> int:
	var saved := S.snapshot_bg()
	var count := 0
	for mv in es.moves:
		if mv != "":
			count += 1
	Menu.draw_box(0, 7, 14, 4)
	Text.single_spaced = true
	for i in count:
		Text.place_string(2, 8 + i, GameData.move_name(es.moves[i]))
	Text.single_spaced = false
	Text.place_string(1, 14, "어느 기술?" if GameData.lang == "ko" else "WHICH TECHNIQUE?")
	var cur := 0
	while true:
		Menu.place_cursor(1, 8 + cur)
		var keys := 0
		while keys == 0:
			await GB.frame
			keys = GB.joy5
		Menu.erase_cursor()
		if keys & GB.A:
			break
		if keys & GB.UP:
			cur = count - 1 if cur == 0 else cur - 1
		elif keys & GB.DOWN:
			cur = 0 if cur == count - 1 else cur + 1
	S.restore_bg(saved)
	return cur


func _leech_seed_effect(player: bool) -> void:
	var d := side(not player)
	_move_hit_test(player)
	if move_missed or "GRASS" in d.types or d.status2 & SEEDED:
		await GB.frames(50)
		await _text("_EvadedAttackText")
		return
	d.status2 |= SEEDED
	await _play_current_move_animation(player)
	await _text("_WasSeededText")


## DisableEffect: a random move of the target for 1-8 turns (the player's moves need PP).
func _disable_effect(player: bool) -> void:
	var d := side(not player)
	_move_hit_test(player)
	if move_missed or d.disabled != 0:
		await _text("_ButItFailedText")
		return
	var slot := 0
	while true:
		slot = rng.randi_range(0, 255) & 3
		if d.moves[slot] == "":
			continue
		if not player:
			var total := 0
			for v in ps.pp:
				total |= int(v)
			if total == 0:
				await _text("_ButItFailedText")
				return
			if int(ps.pp[slot]) == 0:
				continue
		break
	var turns := (rng.randi_range(0, 255) & 7) + 1
	d.disabled = ((slot + 1) << 4) + turns
	await _play_current_move_animation2(player)
	d.disabled_move = d.moves[slot]
	Text.ram["wNameBuffer"] = GameData.move_name(d.disabled_move)
	await _text("_MoveWasDisabledText")


## PayDayEffect_: level x 2 coins for the end of the battle.
func _pay_day_effect(player: bool) -> void:
	var a := side(player)
	pay_day_total += (a.level * 2) & 0xFF
	await _text("_CoinsScatteredText")


## ConversionEffect_: the target's types (fails while the target is invulnerable).
func _conversion_effect(player: bool) -> void:
	var a := side(player)
	var d := side(not player)
	if d.status1 & INVULNERABLE:
		await _text("_ButItFailedText")
		return
	a.types = d.types.duplicate()
	await _play_current_move_animation(player)
	await _text("_ConvertedTypeText")


## HazeEffect_: every stat mod and stat reset, the target's status cured.
func _haze_effect(player: bool) -> void:
	var d := side(not player)
	for s in [ps, es]:
		var b: BattleSide = s
		for k in MOD_KEYS:
			b.mods[k] = 7
		for k in ["atk", "def", "spd", "spc"]:
			b.stats[k] = b.unmod[k]
	var st := d.mon.status
	d.mon.status = 0
	if st & (PartyMon.FRZ | PartyMon.SLP_MASK):
		d.selected_move = CANNOT_MOVE
	for s in [ps, es]:
		var b: BattleSide = s
		b.disabled = 0
		b.disabled_move = ""
		b.status1 &= ~CONFUSED
		b.status2 &= ~(USING_X_ACCURACY | PROTECTED_BY_MIST | GETTING_PUMPED | SEEDED)
		b.status3 &= 0xF0 | TRANSFORMED
	await _play_current_move_animation(player)
	await _text("_StatusChangesEliminatedText")


# --- TrainerAI (engine/battle/trainer_ai.asm) ----------------------------------------------

## TrainerAI: the class's item / switch routine; true when it used the enemy's turn.
func _trainer_ai() -> bool:
	if is_wild:
		return false
	var tdata: Dictionary = GameData.trainers.get(trainer_class, {})
	if tdata.is_empty() or ai_count == 0:
		return false
	if ai_count == 0xFF:
		ai_count = int(tdata.get("ai_count", 3))
	var r := rng.randi_range(0, 255)
	match str(tdata.get("ai", "GenericAI")):
		"JugglerAI":
			if r >= PERCENT_25 + 1:
				return false
			return await _ai_switch_if_enough_mons()
		"BlackbeltAI":
			if r >= 32:   # 13 percent - 1
				return false
			return await _ai_increase_stat("X_ATTACK", "ATTACK_UP1_EFFECT")
		"GiovanniAI":
			if r >= PERCENT_25 + 1:
				return false
			return await _ai_use_guard_spec()
		"CooltrainerMAI":
			if r >= PERCENT_25 + 1:
				return false
			return await _ai_increase_stat("X_ATTACK", "ATTACK_UP1_EFFECT")
		"CooltrainerFAI":
			# the intended 25% chance is not applied (the original)
			if _ai_hp_below_fraction(10):
				return await _ai_recover_hp("HYPER_POTION", 200)
			if not _ai_hp_below_fraction(5):
				return false
			return await _ai_switch_if_enough_mons()
		"BrockAI":
			if enemy_mon.status == 0:
				return false
			return await _ai_use_full_heal()
		"MistyAI":
			if r >= PERCENT_25 + 1:
				return false
			return await _ai_increase_stat("X_DEFEND", "DEFENSE_UP1_EFFECT")
		"LtSurgeAI":
			if r >= PERCENT_25 + 1:
				return false
			return await _ai_increase_stat("X_SPEED", "SPEED_UP1_EFFECT")
		"ErikaAI":
			if r >= PERCENT_50 + 1 or not _ai_hp_below_fraction(10):
				return false
			return await _ai_recover_hp("SUPER_POTION", 50)
		"KogaAI":
			if r >= PERCENT_25 + 1:
				return false
			return await _ai_increase_stat("X_ATTACK", "ATTACK_UP1_EFFECT")
		"BlaineAI":
			if r >= PERCENT_25 + 1:
				return false
			return await _ai_recover_hp("SUPER_POTION", 50)
		"SabrinaAI":
			if r >= PERCENT_25 + 1 or not _ai_hp_below_fraction(10):
				return false
			return await _ai_recover_hp("HYPER_POTION", 200)
		"Rival2AI":
			if r >= 32 or not _ai_hp_below_fraction(5):
				return false
			return await _ai_recover_hp("POTION", 20)
		"Rival3AI":
			if r >= 32 or not _ai_hp_below_fraction(5):
				return false
			return await _ai_use_full_restore()
		"LoreleiAI":
			if r >= PERCENT_50 + 1 or not _ai_hp_below_fraction(5):
				return false
			return await _ai_recover_hp("SUPER_POTION", 50)
		"BrunoAI":
			if r >= PERCENT_25 + 1:
				return false
			return await _ai_increase_stat("X_DEFEND", "DEFENSE_UP1_EFFECT")
		"AgathaAI":
			if r < 20:   # 8 percent
				return await _ai_switch_if_enough_mons()
			if r >= PERCENT_50 + 1 or not _ai_hp_below_fraction(4):
				return false
			return await _ai_recover_hp("SUPER_POTION", 50)
		"LanceAI":
			if r >= PERCENT_50 + 1 or not _ai_hp_below_fraction(5):
				return false
			return await _ai_recover_hp("HYPER_POTION", 200)
	return false


## AICheckIfHPBelowFraction.
func _ai_hp_below_fraction(n: int) -> bool:
	return enemy_mon.hp < enemy_mon.max_hp / n


## AIPrintItemUse_: "<TRAINER> used <item> on <mon>!".
func _ai_print_item_use(item: String) -> void:
	Text.ram["wNameBuffer"] = GameData.item_name(item)
	await _text("_AIBattleUseItemText")


func _ai_cure_status() -> void:
	enemy_mon.status = 0
	es.status3 &= ~BADLY_POISONED


func _ai_use_full_heal() -> bool:
	await Sound.play_sfx_wait_for_current("SFX_HEAL_AILMENT")
	_ai_cure_status()
	await _ai_print_item_use("FULL_HEAL")
	ai_count -= 1
	return true


func _ai_recover_hp(item: String, amount: int) -> bool:
	var old := enemy_mon.hp
	enemy_mon.hp = mini(old + amount, enemy_mon.max_hp)
	await _ai_print_item_use(item)
	await _animate_hp(false, old, enemy_mon.hp)
	ai_count -= 1
	return true


func _ai_use_full_restore() -> bool:
	_ai_cure_status()
	var old := enemy_mon.hp
	enemy_mon.hp = enemy_mon.max_hp
	await _ai_print_item_use("FULL_RESTORE")
	await _animate_hp(false, old, enemy_mon.hp)
	ai_count -= 1
	return true


func _ai_use_guard_spec() -> bool:
	await Sound.play_sfx_wait_for_current("SFX_HEAL_AILMENT")
	es.status2 |= PROTECTED_BY_MIST
	await _ai_print_item_use("GUARD_SPEC")
	ai_count -= 1
	return true


## AIIncreaseStat: StatModifierUpEffect with XSTATITEM_DUPLICATE_ANIM as the move.
func _ai_increase_stat(item: String, effect: String) -> bool:
	await _ai_print_item_use(item)
	var saved_num: String = es.move.num
	var saved_effect: String = es.move.effect
	es.move.num = "XSTATITEM_DUPLICATE_ANIM"
	es.move.effect = effect
	await _stat_modifier_up_effect(false)
	es.move.num = saved_num
	es.move.effect = saved_effect
	ai_count -= 1
	return true


## AISwitchIfEnoughMons / SwitchEnemyMon.
func _ai_switch_if_enough_mons() -> bool:
	var alive := 0
	for m in enemy_party:
		if m.hp > 0:
			alive += 1
	if alive < 2:
		return false
	await _text("_AIBattleWithdrawText")
	first_mons_not_out_yet = true
	await _enemy_send_out(false)
	first_mons_not_out_yet = false
	return true


## ReadMove: a move's data into wEnemyMoveNum.. (the AI layers leave the last one there).
func _read_move(mv: String) -> void:
	_load_move_data(es, mv)


## AIEnemyTrainerChooseMoves: the moves with the lowest score after the class's layers.
func _ai_enemy_trainer_choose_moves() -> Array:
	var buf := [10, 10, 10, 10]
	var dslot := (es.disabled >> 4) & 0xF
	if dslot != 0:
		buf[dslot - 1] = 0x50
	var tdata: Dictionary = GameData.trainers.get(trainer_class, {})
	var layers: Array = tdata.get("move_choices", [])
	if layers.is_empty():
		return es.moves
	for layer in layers:
		match int(layer):
			1: _ai_move_choice_modification1(buf)
			2: _ai_move_choice_modification2(buf)
			3: _ai_move_choice_modification3(buf)
	var count := 0
	for mv in es.moves:
		if mv == "":
			break
		count += 1
	var lowest := 0x7FFF
	for i in count:
		lowest = mini(lowest, int(buf[i]))
	var out := ["", "", "", ""]
	for i in count:
		if int(buf[i]) == lowest:
			out[i] = es.moves[i]
	return out


## AIMoveChoiceModification1: no status-only moves against a statused mon.
func _ai_move_choice_modification1(buf: Array) -> void:
	if player_mon.status == 0:
		return
	for i in 4:
		var mv: String = es.moves[i]
		if mv == "":
			return
		_read_move(mv)
		if int(es.move.power) != 0:
			continue
		if es.move.effect in STATUS_AILMENT_MOVE_EFFECTS:
			buf[i] = int(buf[i]) + 5


## AIMoveChoiceModification2: on the second turn, stat-modifying moves are encouraged.
func _ai_move_choice_modification2(buf: Array) -> void:
	if ai_layer2_encouragement != 1:
		return
	for i in 4:
		var mv: String = es.moves[i]
		if mv == "":
			return
		_read_move(mv)
		var id := _effect_id(str(es.move.effect))
		if (id >= 0x0A and id < 0x1A) or (id >= 0x32 and id < 0x42):
			buf[i] = int(buf[i]) - 1


## AIMoveChoiceModification3: super effective moves are encouraged, weak ones
## discouraged when a better damaging move exists.
func _ai_move_choice_modification3(buf: Array) -> void:
	for i in 4:
		var mv: String = es.moves[i]
		if mv == "":
			return
		_read_move(mv)
		var te := _ai_get_type_effectiveness()
		if te == 0x10:
			continue
		if te > 0x10:
			buf[i] = int(buf[i]) - 1
			continue
		var my_type: String = es.move.type
		var better := false
		for other in es.moves:
			if other == "":
				break
			_read_move(other)
			var eff: String = es.move.effect
			if eff == "SUPER_FANG_EFFECT" or eff == "SPECIAL_DAMAGE_EFFECT" or eff == "FLY_EFFECT":
				better = true
				break
			if es.move.type == my_type:
				continue
			if int(es.move.power) != 0:
				better = true
				break
		if better:
			buf[i] = int(buf[i]) + 1


## AIGetTypeEffectiveness: the first matching pair only ($10 when none, the original).
func _ai_get_type_effectiveness() -> int:
	var mt: String = es.move.type
	for row in GameData.types["matchups"]:
		if str(row[0]) == mt and (str(row[1]) == ps.types[0] or str(row[1]) == ps.types[1]):
			return int(TYPE_MULTIPLIERS[str(row[2])])
	return 0x10


func _text(label: String) -> void:
	if trace:
		print("BATTLE_TEXT frame=%d %s" % [GB.frame_count, label])
	await Text.print_text(label)


## The display name used by <USER>/<TARGET>: "Enemy " before the enemy's nick.
func _display_name(is_player: bool) -> String:
	if is_player:
		return player_mon.nickname
	return ("상대 " if GameData.lang == "ko" else "Enemy ") + enemy_mon.nickname


func _set_user_target(is_player: bool) -> void:
	Text.vars["USER"] = _display_name(is_player)
	Text.vars["TARGET"] = _display_name(not is_player)


# --- fainting ---------------------------------------------------------------------

## SlideDownFaintedMonPic: the picture slides down one row at a time.
func _slide_down_pic(x: int, y: int) -> void:
	for step in 7:
		for row in range(6, 0, -1):
			for col in 7:
				S.set_bg(x + col, y + row, S.get_bg(x + col, y + row - 1))
		for col in 7:
			S.set_bg(x + col, y, Text.code_tile(Text.SPACE))
		await GB.frames(2)
	_clear(x, y, 7, 7)


## HandleEnemyMonFainted.
func _handle_enemy_mon_fainted() -> void:
	in_handle_player_fainted = false
	await _faint_enemy_pokemon()
	if not _any_party_alive():
		await _handle_player_black_out()
		return
	if player_mon.hp > 0:
		_draw_player_hud()
	if is_wild:
		result = "won"
		battle_over = true
		return
	if not _any_enemy_alive():
		await _trainer_battle_victory()
		return
	if player_mon.hp <= 0:
		await _choose_next_mon()
	await _replace_fainted_enemy_mon()


## FaintEnemyPokemon: the slide, the sounds (or the wild victory music), then the experience.
func _faint_enemy_pokemon() -> void:
	ps.status1 &= ~ATTACKING_MULTIPLE_TIMES
	ps.bide_damage &= 0xFF   # only the high byte is cleared (the original)
	es.status1 = 0
	es.status2 = 0
	es.status3 = 0
	es.disabled = 0
	es.disabled_move = ""
	es.minimized = false
	ps.used_move = ""
	es.used_move = ""
	_draw_enemy_hud(0)
	await _slide_down_pic(12, 0)
	_clear(0, 0, 11, 4 + ehud)
	if is_wild:
		Sound.end_low_health_alarm()
		await Sound.play_battle_victory_music("MUSIC_DEFEATED_WILD_MON")
	else:
		Sound.frequency_modifier = 0
		Sound.tempo_modifier = 0
		await Sound.play_sfx_wait_for_current("SFX_FAINT_FALL")
		await Sound.wait_while_channel5_is("SFX_FAINT_FALL")
		Sound.play_sfx("SFX_FAINT_THUD")
		await Sound.wait_for_sfx()
	if player_mon.hp <= 0 and not in_handle_player_fainted:
		await _remove_fainted_player_mon()
	if not _any_party_alive():
		return
	await _text("_EnemyMonFaintedText")
	_print_empty()
	await _gain_experience()


## HandlePlayerMonFainted.
func _handle_player_mon_fainted() -> void:
	in_handle_player_fainted = true
	await _remove_fainted_player_mon()
	if not _any_party_alive():
		await _handle_player_black_out()
		return
	if enemy_mon.hp <= 0:
		await _faint_enemy_pokemon()
		if is_wild:
			result = "won"
			battle_over = true
			return
		if not _any_enemy_alive():
			await _trainer_battle_victory()
			return
	# DoUseNextMonDialogue (wild battles only)
	if is_wild:
		_print_empty()
		await _text("_UseNextMonText")
		if not await Menu.yes_no(13, 9):
			# NO: try running with the first party mon's speed
			if await _try_run(state.party[0].stats.spd):
				return
	await _choose_next_mon()
	if enemy_mon.hp > 0:
		return
	await _replace_fainted_enemy_mon()


## RemoveFaintedPlayerMon.
func _remove_fainted_player_mon() -> void:
	gain_exp_flags[player_index] = false
	if Sound.low_health_alarm & 0x80:
		Sound.set_low_health_alarm(false)
		await Sound.wait_for_sfx()
	es.status1 &= ~ATTACKING_MULTIPLE_TIMES
	es.bide_damage = 0
	player_mon.status = 0
	_clear(9, 7, 11, 5)
	await _slide_down_pic(1, 5)
	if not in_handle_player_fainted:
		return
	Sound.play_cry(player_mon.species)
	await Sound.wait_for_sfx()
	await _text("_PlayerMonFaintedText")


## ChooseNextMon: the party menu until a healthy mon is picked, then SendOutMon.
func _choose_next_mon() -> void:
	var saved := S.snapshot_bg()
	var cur := 0
	while true:
		var idx := await PartyMenu.show(state, "battle", cur)
		if idx < 0:
			continue
		cur = idx
		if state.party[idx].hp <= 0:
			await Text.print_text("_NoWillText")
			continue
		break
	S.white_out()
	S.clear_sprites()
	_load_player(cur)
	gain_exp_flags[cur] = true
	S.restore_bg(saved)
	SGB.run("BATTLE", _battle_ctx())
	S.normal_pals()
	await _send_out_mon()


## HandlePlayerBlackOut: the rival gloats first; in Oak's Lab there is no blackout.
func _handle_player_black_out() -> void:
	if trainer_class == "RIVAL1":
		Text.clear_area(0, 0, 20, 8)
		await _scroll_trainer_pic_in()
		await GB.frames(40)
		await _text("_Rival1WinText")
		if state.cur_map == "OAKS_LAB":
			result = "lost"
			battle_over = true
			return
	SGB.run("BATTLE_BLACK")
	await _text("_PlayerBlackedOutText2")
	Text.clear_screen()
	result = "blackout"
	battle_over = true


# --- the enemy trainer's party ---------------------------------------------------------

## ReplaceFaintedEnemyMon: the enemy's balls, EnemySendOut, then a fresh move and AI state.
func _replace_fainted_enemy_mon() -> void:
	_draw_enemy_pokeballs()
	await _enemy_send_out(false)
	es.move.num = ""
	took_turn = false
	ai_layer2_encouragement = 0


## DrawEnemyPokeballs.
func _draw_enemy_pokeballs() -> void:
	_place_enemy_hud_tiles()
	for k in 6:
		var t := 3
		if k < enemy_party.size():
			t = 2 if enemy_party[k].hp == 0 else 0
		S.set_sprite(6 + k, 64 - k * 8, 16, S.tile("balls", t))


## EnemySendOut / EnemySendOutFirstMon: the next mon, the battle-style prompt and
## the send-out animation.
func _enemy_send_out(first: bool) -> void:
	if not first:
		for i in gain_exp_flags.size():
			gain_exp_flags[i] = false
		gain_exp_flags[player_index] = true
	_reset_enemy_battle_vars()
	await _slide_pic(12, 0, 8, 1)
	_print_empty()
	_load_enemy(_first_alive_enemy(enemy_index if not first else -1))
	var switch_to := -1
	if not first_mons_not_out_yet and state.party.size() > 1 and Settings.battle_style_shift():
		await _text("_TrainerAboutToUseText")
		if await Menu.yes_no(0, 7):
			var saved := S.snapshot_bg()
			var cur := 0
			while true:
				var idx := await PartyMenu.show(state, "battle", cur)
				if idx < 0:
					break
				cur = idx
				if idx == player_index:
					await Text.print_text("_AlreadyOutText")
					continue
				if state.party[idx].hp <= 0:
					await Text.print_text("_NoWillText")
					continue
				switch_to = idx
				break
			S.white_out()
			S.clear_sprites()
			S.restore_bg(saved)
	S.clear_sprites()
	_clear(0, 0, 11, 4 + ehud)
	SGB.run("BATTLE", _battle_ctx())
	S.normal_pals()
	await _text("_TrainerSentOutText")
	enemy_sheet = _enemy_pic()
	await _animate_sending_out(enemy_sheet, 12, 0, 15, 6)
	Sound.play_cry(enemy_mon.species)
	await Sound.wait_for_sfx()
	_draw_enemy_hud()
	if switch_to >= 0:
		for i in gain_exp_flags.size():
			gain_exp_flags[i] = false
		await _switch_player_mon(switch_to)


## BattleMenu <PKMN>: the party menu; returns true when a switch used the turn.
func _party_switch_menu() -> bool:
	var saved := S.snapshot_bg()
	var cur := 0
	while true:
		var idx := await PartyMenu.show(state, "normal", cur)
		if idx < 0:
			S.white_out()
			S.clear_sprites()
			S.restore_bg(saved)
			SGB.run("BATTLE", _battle_ctx())
			S.normal_pals()
			return false
		cur = idx
		if idx == player_index:
			await Text.print_text("_AlreadyOutText")
			continue
		if state.party[idx].hp <= 0:
			await Text.print_text("_NoWillText")
			continue
		break
	S.white_out()
	S.clear_sprites()
	S.restore_bg(saved)
	SGB.run("BATTLE", _battle_ctx())
	S.normal_pals()
	await _switch_player_mon(cur)
	return true


## SwitchPlayerMon: RetreatMon, 50 frames, the retreat animation, then SendOutMon.
func _switch_player_mon(idx: int) -> void:
	await _retreat_mon()
	await GB.frames(50)
	await _animate_retreating_player_mon()
	_load_player(idx)
	gain_exp_flags[idx] = true
	await _send_out_mon()


## RetreatMon (PlayerMon2Text): "<mon> enough! / Come back! / OK! / good!" by the
## share of HP the enemy lost since it came out.
func _retreat_mon() -> void:
	var lost := last_switch_in_enemy_hp - enemy_mon.hp
	var pct := 0
	if enemy_mon.max_hp / 4 > 0:
		pct = (lost * 25) / (enemy_mon.max_hp / 4)
	var label := "_EnoughText"
	if pct < 0:
		pct = 0
	if pct == 0:
		label = "_EnoughText"
	elif pct < 30:
		label = ""
	elif pct < 70:
		label = "_OKExclamationText"
	else:
		label = "_GoodText"
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text("_PlayerMon2Text"))
	if label != "":
		await Text.run_commands(GameData.text(label))
	await Text.run_commands(GameData.text("_ComeBackText"))


# --- running ---------------------------------------------------------------------------

## TryRunningFromBattle. Returns true when the player escaped (the battle ends).
func _try_run(player_speed: int) -> bool:
	var enemy_speed: int = es.stats.spd
	run_attempts += 1
	var escaped := false
	if is_ghost:
		escaped = true
	elif player_speed > enemy_speed:
		escaped = true
	else:
		var divisor := (enemy_speed / 4) % 256
		if divisor == 0:
			escaped = true
		else:
			var q := (player_speed * 32) / divisor
			if q > 255:
				escaped = true
			else:
				for i in run_attempts - 1:
					q += 30
					if q > 255:
						escaped = true
						break
				if not escaped and rng.randi_range(0, 255) <= q:
					escaped = true
	if not escaped:
		await _text("_CantEscapeText")
		return false
	await Sound.play_sfx_wait_for_current("SFX_RUN")
	await _text("_GotAwayText")
	await Sound.wait_for_sfx()
	result = "ran"
	battle_over = true
	return true


# --- items -----------------------------------------------------------------------------

## BagWasSelected / UseBagItem.
func _bag() -> void:
	var saved := S.snapshot_bg()
	while true:
		S.restore_bg(saved)
		_draw_huds()
		var names: Array = []
		for it in state.items:
			names.append(str(it.item))
		if trace:
			print("BATTLE_BAG frame=%d items=%s" % [GB.frame_count, str(names)])
		var pick := await ListMenu.show_items(names, false, true, state)
		if trace:
			print("BATTLE_BAG frame=%d pick=%d" % [GB.frame_count, pick])
		if pick < 0:
			S.restore_bg(saved)
			return
		var item: String = names[pick]
		S.restore_bg(saved)
		if ItemUse.is_ball(item):
			await _use_ball(item)
			if took_turn and not battle_over:
				_after_bag_item_used()
			return
		if item == "POKE_FLUTE":
			await _use_poke_flute()
			_after_bag_item_used()
			return
		if ItemUse.is_medicine(item):
			if await _use_medicine(item):
				_after_bag_item_used()
				return
			continue
		if item in X_STAT_ITEMS or item in ["X_ACCURACY", "GUARD_SPEC", "DIRE_HIT", "POKE_DOLL"]:
			if await _use_battle_item(item):
				_after_bag_item_used()
				return
			continue
		# TOWN MAP, OAK's PARCEL, TMs...: ItemUseNotTime
		await _text("_ItemUseNotTimeText")


## The enemy's picture: the GhostPic while the enemy is an unidentified ghost.
func _enemy_pic(species: String = "") -> String:
	if ghost_pic:
		return "pic_ghost"
	return GameData.pokemon[species if species != "" else enemy_mon.species]["pic"]


## PrintBeginningBattleText in Pokémon Tower: without the SILPH SCOPE "The GHOST can't be
## ID'd"; the ghost MAROWAK is unveiled (LoadEnemyMonData, MarowakAnim) with the trainer
## jingle after "Wild MAROWAK appeared!".
func _tower_battle_text() -> void:
	Text.ram["wEnemyMonNick"] = enemy_mon.nickname
	await _text("_EnemyAppearedText")
	if is_ghost:
		await _text("_GhostCantBeIDdText")
		return
	await _text("_UnveiledGhostText")
	ghost_pic = false
	enemy_mon.nickname = GameData.mon_name(enemy_mon.species)
	Text.ram["wEnemyMonNick"] = enemy_mon.nickname
	await _marowak_anim()
	await _text("_WildMonAppearedText")
	Sound.play_sfx_modified("SFX_TRAINER_APPEARED", 0, 0x80)
	await Sound.wait_for_sfx()


## MarowakAnim (engine/battle/ghost_marowak_anim.asm): the ghost picture becomes sprites
## (OBP1), flashes eight times and fades out; the MAROWAK fades in as sprites and then is
## drawn in the background.
func _marowak_anim() -> void:
	var obp := 0xE4
	S.obp1 = GBScreen.pal_byte(obp)
	_copy_pic_to_sprites("pic_ghost")
	for row in 7:   # ClearScreenArea (12, 0) 7x7
		for col in 7:
			S.set_bg(12 + col, row, Text.code_tile(Text.SPACE))
	await GB.delay3()
	enemy_sheet = _enemy_pic()   # ChangeMonPic (not shown yet: hAutoBGTransferEnabled = 0)
	for i in 8:   # FlashSprite8Times (d = $80)
		obp ^= 0x80
		S.obp1 = GBScreen.pal_byte(obp)
		await GB.frames(10)
	while true:   # .fadeOutGhostLoop
		await GB.frames(10)
		obp = (obp << 2) & 0xFF
		S.obp1 = GBScreen.pal_byte(obp)
		if obp == 0:
			break
	S.clear_sprites()
	_copy_pic_to_sprites(enemy_sheet)
	var b := 0xE4
	obp = 0
	while true:   # .fadeInMarowakLoop: two bits of $e4 shifted in every ten frames
		await GB.frames(10)
		for k in 2:
			var c := b & 1
			b >>= 1
			obp = (obp >> 1) | (c << 7)
		S.obp1 = GBScreen.pal_byte(obp)
		if b == 0:
			break
	_draw_sheet(enemy_sheet, 12, 0)   # hAutoBGTransferEnabled = 1
	await GB.delay3()
	S.clear_sprites()


## CopyMonPicFromBGToSpriteVRAM: the inner 6x6 tiles of the enemy picture as OBP1 sprites.
func _copy_pic_to_sprites(sheet_name: String) -> void:
	var n := 0
	for col in 6:
		for row in 6:
			S.set_sprite(n, 104 + col * 8, 8 + row * 8, S.pic_tile(sheet_name, col + 1, row + 1), 1)
			n += 1


## ItemUsePokeFlute in battle: every sleeping Pokémon of both sides wakes up; with any
## asleep the flute plays (unless the low HP alarm sounds) before "All sleeping POKéMON
## woke up".
func _use_poke_flute() -> void:
	var any_asleep := false
	var mons: Array = state.party.duplicate()
	if not is_wild:
		mons += enemy_party
	mons += [player_mon, enemy_mon]
	for m in mons:
		if m == null:
			continue
		if m.status & PartyMon.SLP_MASK:
			any_asleep = true
		m.status &= ~PartyMon.SLP_MASK
	_draw_huds()
	if not any_asleep:
		await _text("_PlayedFluteNoEffectText")
		took_turn = true
		return
	await _text("_PlayedFluteHadEffectText")
	if Sound.low_health_alarm & 0x80 == 0:
		await Sound.wait_for_sfx()
		Sound.play_sfx("SFX_POKEFLUTE")   # Music_PokeFluteInBattle
		await GB.frame
		while Sound.ch_id[Sound.CHAN7] != 0:
			await GB.frame
	await _text("_FluteWokeUpText")
	took_turn = true


## UseBagItem: a used item also spends a turn of the player's trapping move.
func _after_bag_item_used() -> void:
	if ps == null:
		return
	if ps.status1 & USING_TRAPPING_MOVE:
		ps.num_attacks_left = (ps.num_attacks_left - 1) & 0xFF
		if ps.num_attacks_left == 0:
			ps.status1 &= ~USING_TRAPPING_MOVE


## PrintItemUseTextAndRemoveItem: "<PLAYER> used <item>!", SFX_HEAL_AILMENT, the button.
func _print_item_use_text_and_remove(item: String) -> void:
	Text.ram["wStringBuffer"] = GameData.item_name(item)
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text("_ItemUseText001"))
	Text.cursor = Vector2i(1, 16)
	await Text.run_commands(GameData.text("_ItemUseText002"))
	Sound.play_sfx("SFX_HEAL_AILMENT")
	await Text.wait_scroll_button(false)
	state.remove_item(item, 1)


## ItemUseXStat, ItemUseXAccuracy, ItemUseGuardSpec, ItemUseDireHit, ItemUsePokeDoll.
## Returns false when the item could not be used (ItemUseNotTime).
func _use_battle_item(item: String) -> bool:
	match item:
		"POKE_DOLL":
			if not is_wild:
				await _text("_ItemUseNotTimeText")
				return false
			escaped = true
			await _print_item_use_text_and_remove(item)
			result = "ran"
			battle_over = true
		"X_ACCURACY":
			ps.status2 |= USING_X_ACCURACY
			await _print_item_use_text_and_remove(item)
		"GUARD_SPEC":
			ps.status2 |= PROTECTED_BY_MIST
			await _print_item_use_text_and_remove(item)
		"DIRE_HIT":
			ps.status2 |= GETTING_PUMPED
			await _print_item_use_text_and_remove(item)
		_:
			var saved_num: String = ps.move.num
			var saved_effect: String = ps.move.effect
			ps.move.effect = X_STAT_ITEMS[item]
			await _print_item_use_text_and_remove(item)
			ps.move.num = "XSTATITEM_ANIM"
			S.restore_bg(menu_saved)
			await GB.delay3()
			_set_turn(true)
			await _stat_modifier_up_effect(true)
			ps.move.effect = saved_effect
			ps.move.num = saved_num
	took_turn = true
	return true


## ItemUseMedicine in battle: the party menu, the HP bar in the menu, then the message.
func _use_medicine(item: String) -> bool:
	var saved := S.snapshot_bg()
	var cur := 0
	while true:
		var idx := await PartyMenu.show(state, "item", cur)
		if idx < 0:
			S.white_out()
			S.clear_sprites()
			S.restore_bg(saved)
			SGB.run("BATTLE", _battle_ctx())
			S.normal_pals()
			return false
		cur = idx
		var mon: PartyMon = state.party[idx]
		var r: Dictionary = ItemUse.apply_medicine(mon, item)
		if not bool(r.get("ok", false)):
			await Text.print_text("_ItemUseNoEffectText")
			# back to the bag
			S.white_out()
			S.clear_sprites()
			S.restore_bg(saved)
			SGB.run("BATTLE", _battle_ctx())
			S.normal_pals()
			return false
		if bool(r.get("cured", false)) and idx == player_index and ps != null:
			# the in-battle stats are copied back from the party data (stat mods and
			# badge boosts are lost, the original)
			for k in ["atk", "def", "spd", "spc"]:
				ps.stats[k] = int(mon.stats[k])
			ps.status3 &= ~BADLY_POISONED
		var old_hp := int(r.get("old_hp", mon.hp))
		var new_hp := int(r.get("new_hp", mon.hp))
		if new_hp != old_hp:
			Sound.play_sfx("SFX_HEAL_HP")
			await PartyMenu.animate_hp(state, idx, old_hp, new_hp)
		else:
			Sound.play_sfx("SFX_HEAL_AILMENT")
			await Sound.wait_for_sfx()
		var msg := str(r.get("message", ""))
		if msg != "":
			await Text.print_text(msg)
		await GB.frames(50)
		await Text.wait_scroll_button(false)
		state.remove_item(item, 1)
		break
	S.white_out()
	S.clear_sprites()
	S.restore_bg(saved)
	_draw_huds()
	SGB.run("BATTLE", _battle_ctx())
	S.normal_pals()
	took_turn = true
	return true


## ItemUseBall.
func _use_ball(item: String) -> void:
	if is_wild and not is_old_man and state.party.size() >= 6 and state.box.size() >= 20:
		await _text("_BoxFullCannotThrowBallText")
		return
	# ItemUseText00: "<PLAYER> used <item>!"
	Text.ram["wStringBuffer"] = GameData.item_name(item)
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text("_ItemUseText001"))
	Text.cursor = Vector2i(1, 16)
	await Text.run_commands(GameData.text("_ItemUseText002"))
	if not is_wild:
		# ThrowBallAtTrainerMon
		await GB.delay3()
		await _toss_ball_animation(item, 0)
		await _text("_ThrowBallAtTrainerMonText1")
		await _text("_ThrowBallAtTrainerMonText2")
		state.remove_item(item, 1)
		took_turn = true
		return
	if is_ghost or restless_soul:
		# an unidentified ghost or the ghost MAROWAK can't be caught: the ball is dodged ($10)
		await GB.frames(20)
		await _toss_ball_animation(item, 0x10)
		pic_dodged = true
		await _text("_ItemUseBallText00")
		state.remove_item(item, 1)
		took_turn = true
		return
	var caught := false
	var shakes := 0
	var missed := false
	if is_old_man or item == "MASTER_BALL":
		caught = true
		shakes = 3
	else:
		var rand1 := rng.randi_range(0, 255)
		if item == "GREAT_BALL":
			rand1 = rand1 % 201
		elif item == "ULTRA_BALL":
			rand1 = rand1 % 151
		var status_value := 0
		if enemy_mon.status & (PartyMon.FRZ | PartyMon.SLP_MASK):
			status_value = 25
		elif enemy_mon.status != 0:
			status_value = 12
		if rand1 < status_value:
			caught = true
		else:
			rand1 -= status_value
			var ball_factor := 8 if item == "GREAT_BALL" else 12
			var x: int = (enemy_mon.max_hp * 255 / ball_factor) / maxi(enemy_mon.hp / 4, 1)
			x = mini(x, 255)
			var catch_rate: int = GameData.pokemon[enemy_mon.species]["catch_rate"]
			if rand1 > catch_rate:
				caught = false
			else:
				var rand2 := rng.randi_range(0, 255)
				caught = rand2 <= x
			if not caught:
				# the number of shakes
				var factor2 := 255
				if item == "GREAT_BALL":
					factor2 = 200
				elif item == "ULTRA_BALL":
					factor2 = 150
				var y: int = catch_rate * 100 / factor2
				var z: int = x * y / 255
				if enemy_mon.status & (PartyMon.FRZ | PartyMon.SLP_MASK):
					z += 10
				elif enemy_mon.status != 0:
					z += 5
				if z < 10:
					shakes = 0
					missed = true
				elif z < 30:
					shakes = 1
				elif z < 70:
					shakes = 2
				else:
					shakes = 3
	await GB.frames(20)
	var anim_data := 0x43   # successful capture
	if not caught:
		anim_data = 0x20 if missed else (0x60 | shakes)
	await _toss_ball_animation(item, anim_data)
	if not caught:
		if missed:
			await _text("_ItemUseBallText01")
		else:
			await _text(["_ItemUseBallText02", "_ItemUseBallText02", "_ItemUseBallText03", "_ItemUseBallText04"][shakes])
		state.remove_item(item, 1)
		took_turn = true
		return
	# caught
	Text.ram["wEnemyMonNick"] = enemy_mon.nickname
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text("_ItemUseBallText05"))
	if is_old_man:
		await Text.wait_scroll_button(true)
		S.clear_sprites()
		result = "demo"
		battle_over = true
		return
	await Sound.text_sound("sound_caught_mon")
	await Text.wait_scroll_button(false)
	var sp := enemy_mon.species
	var new_dex: bool = not state.pokedex_owned.get(sp, false)
	state.pokedex_owned[sp] = true
	if new_dex:
		await _text("_ItemUseBallText06")
		await Sound.text_sound("sound_dex_page_added")
		await Text.wait_scroll_button(false)
		S.clear_sprites()
		var saved := S.snapshot_bg()
		await PokedexPage.new().show(sp)
		S.restore_bg(saved)
		SGB.run("BATTLE", _battle_ctx())
		S.normal_pals()
	if state.party.size() < 6:
		S.clear_sprites()
		# AddPartyMon → AskName
		await _ask_nickname(enemy_mon)
		state.party.append(enemy_mon)
	else:
		S.clear_sprites()
		state.box.append(enemy_mon)
		Text.ram["wBoxMonNicks"] = enemy_mon.nickname
		await _text("_ItemUseBallText07" if state.has_event("EVENT_MET_BILL") else "_ItemUseBallText08")
	state.remove_item(item, 1)
	result = "caught"
	battle_over = true


## AskName (engine/menus/naming_screen.asm): "Do you want to give a nickname to X?"
func _ask_nickname(mon: PartyMon) -> void:
	_clear(0, 0, 11, 4 + ehud)
	Text.ram["wNameBuffer"] = GameData.mon_name(mon.species)
	await _text("_DoYouWantToNicknameText")
	if await Menu.yes_no(14, 7):
		var saved := S.snapshot_bg()
		var name: String = await NamingScreen.new().run(NamingScreen.Kind.MON, mon.species)
		if name != "":
			mon.nickname = name
		S.restore_bg(saved)
		SGB.run("BATTLE", _battle_ctx())
		S.normal_pals()


## TossBallAnimation through the animation engine with wPokeBallAnimData.
func _toss_ball_animation(item: String, anim_data: int) -> void:
	await BattleAnim.toss_ball(self, anim_data, item)


## The old man's catch demonstration (DisplayBattleMenu .oldManBattle,
## BagWasSelected OldManItemList): the cursor walks to ITEM on its own.
func _old_man_battle() -> void:
	Text.vars["PLAYER"] = "할아버지" if GameData.lang == "ko" else "OLD MAN"
	_draw_battle_menu_box()
	Text.put(9, 14, Text.CURSOR)
	await GB.frames(80)
	Text.put(9, 14, Text.SPACE)
	Text.put(9, 16, Text.CURSOR)
	await GB.frames(50)
	Text.put(9, 16, UNFILLED_CURSOR)
	var demo_state := GameState.new()
	demo_state.items = [{"item": "POKE_BALL", "qty": 50}]
	var saved := S.snapshot_bg()
	while true:
		S.restore_bg(saved)
		var pick := await ListMenu.show_items(["POKE_BALL"], false, true, demo_state)
		if pick >= 0:
			break
	S.restore_bg(saved)
	await _use_ball("POKE_BALL")


# --- experience, victory ------------------------------------------------------------------

## GainExperience: the base experience is split among the participants, boosted
## in trainer battles, then each mon's level is recalculated.
func _gain_experience() -> void:
	var data: Dictionary = GameData.pokemon[enemy_mon.species]
	var participants := 0
	for i in state.party.size():
		if gain_exp_flags[i] and state.party[i].hp > 0:
			participants += 1
	var base_exp: int = int(data["base_exp"])
	if participants > 1:
		base_exp = base_exp / participants
	for i in state.party.size():
		var mon: PartyMon = state.party[i]
		if mon.hp <= 0 or not gain_exp_flags[i]:
			continue
		# stat experience: the enemy's base stats (split among the participants), capped at 65535
		for key in ["hp", "atk", "def", "spd", "spc"]:
			var add: int = int(data[key])
			if participants > 1:
				add = add / participants
			mon.stat_exp[key] = mini(65535, int(mon.stat_exp[key]) + add)
		var exp: int = base_exp * enemy_mon.level / 7
		if not is_wild:
			exp = exp + exp / 2   # BoostExp
		var growth: String = GameData.pokemon[mon.species]["growth"]
		var max_exp := PartyMon.exp_for_level(growth, 100)
		mon.exp = mini(mon.exp + exp, max_exp)
		Text.ram["wNameBuffer"] = mon.nickname
		Text.ram["wExpAmountGained"] = exp
		Menu.message_box()
		await GB.delay3()
		Text.cursor = Vector2i(1, 14)
		await Text.run_commands(GameData.text("_GainedText"))
		await Text.run_commands(GameData.text("_ExpPointsText"))
		var new_level := mon.level
		while new_level < 100 and mon.exp >= PartyMon.exp_for_level(growth, new_level + 1):
			new_level += 1
		if new_level == mon.level:
			continue
		var old_max := mon.max_hp
		mon.level = new_level
		mon.recalc_stats()
		mon.hp += mon.max_hp - old_max
		if i == player_index:
			ps.level = mon.level
			for k in ["atk", "def", "spd", "spc"]:
				ps.stats[k] = int(mon.stats[k])
				if not (ps.status3 & TRANSFORMED):
					ps.unmod[k] = int(mon.stats[k])
			_calculate_modified_stats(ps)
			_apply_burn_and_paralysis_penalties(true)
			_apply_badge_stat_boosts()
			_draw_player_hud()
			_print_empty()
		Text.ram["wCurEnemyLevel"] = mon.level
		Menu.message_box()
		await GB.delay3()
		Text.cursor = Vector2i(1, 14)
		await Text.run_commands(GameData.text("_GrewLevelText"))
		await Sound.text_sound("sound_level_up")
		await Text.run_commands([["prompt", ""]])
		await _level_up_stats_box(mon)
		await _learn_move_from_level_up(i, mon)
		can_evolve[i] = true


## PrintStatsBox (LEVEL_UP_STATS_BOX): box at (9, 2) with the four stats.
func _level_up_stats_box(mon: PartyMon) -> void:
	var saved := S.snapshot_bg()
	Menu.draw_box(9, 2, 9, 8)
	var names := ["공격", "방어", "스피드", "특수"] if GameData.lang == "ko" else ["ATTACK", "DEFENSE", "SPEED", "SPECIAL"]
	var keys := ["atk", "def", "spd", "spc"]
	for i in 4:
		Text.place_string(11, 3 + i * 2, names[i])
		Text.place_string(15, 4 + i * 2, "%3d" % int(mon.stats[keys[i]]))
	await Text.wait_scroll_button(false)
	S.restore_bg(saved)


## LearnMoveFromLevelUp: the moves learnt at exactly this level.
func _learn_move_from_level_up(party_index: int, mon: PartyMon) -> void:
	for entry in GameData.pokemon[mon.species]["learnset"]:
		if int(entry[0]) == mon.level:
			await _learn_move(party_index, mon, str(entry[1]))


## LearnMove (engine/pokemon/learn_move.asm) — shared with the TM flow.
func _learn_move(party_index: int, mon: PartyMon, move: String) -> bool:
	return await LearnMove.learn(mon, party_index, move, true)


## TrainerBattleVictory (+ PrintEndBattleText: "<trainer>: <win text>" in one box).
func _trainer_battle_victory() -> void:
	Sound.end_low_health_alarm()
	var music := "MUSIC_DEFEATED_TRAINER"
	if gym_leader_no != 0 or trainer_class == "RIVAL3":
		music = "MUSIC_DEFEATED_GYM_LEADER"
	await Sound.play_battle_victory_music(music)
	await _text("_TrainerDefeatedText")
	await _scroll_trainer_pic_in()
	await GB.frames(40)
	if request.has("win_text"):
		Text.ram["wNameBuffer"] = str(Text.ram.get("wTrainerName", ""))
		if trace:
			print("BATTLE_TEXT frame=%d _TrainerNameText+%s" % [GB.frame_count, request["win_text"]])
		Menu.message_box()
		await GB.delay3()
		Text.cursor = Vector2i(1, 14)
		await Text.run_commands(GameData.text("_TrainerNameText"))
		await Text.run_commands(GameData.text(str(request["win_text"])))
		await Sound.wait_for_sfx()
	var tdata: Dictionary = GameData.trainers.get(trainer_class, {})
	var base_money := int(tdata.get("money", 3500)) / 100
	var prize := base_money * (trainer_team_level if trainer_team_level > 0 else enemy_mon.level)
	state.money = mini(state.money + prize, 999999)
	Text.ram["wAmountMoneyWon"] = prize
	await _text("_MoneyForWinningText")
	result = "won"
	battle_over = true


## ReadTrainer .AddLoneMove / .AddTeamMove / .ChampionRival: the third move slot.
func _add_special_trainer_moves(tdata: Dictionary) -> void:
	if gym_leader_no != 0:
		var lone: Array = GameData.trainers["_lone_moves"][gym_leader_no - 1]
		_set_third_move(int(lone[0]), str(lone[1]))
		return
	var team_move := str(tdata.get("team_move", ""))
	if team_move != "":
		_set_third_move(4, team_move)
	elif trainer_class == "RIVAL3":
		_set_third_move(0, "SKY_ATTACK")
		var starter_move := "BLIZZARD"
		if state.rival_starter == "BULBASAUR":
			starter_move = "MEGA_DRAIN"
		elif state.rival_starter == "CHARMANDER":
			starter_move = "FIRE_BLAST"
		_set_third_move(5, starter_move)


func _set_third_move(mon_index: int, mv: String) -> void:
	if mon_index >= enemy_party.size():
		return
	var mon: PartyMon = enemy_party[mon_index]
	var pp: int = GameData.moves[mv]["pp"]
	var entry := {"move": mv, "pp": pp, "max_pp": pp}
	if mon.moves.size() > 2:
		mon.moves[2] = entry
	else:
		mon.moves.append(entry)


## ScrollTrainerPicAfterBattle: the trainer picture slides in from the right.
func _scroll_trainer_pic_in() -> void:
	for step in 8:
		var x := 19 - step
		for row in 7:
			for col in range(x, 19):
				S.set_bg(col, row, S.get_bg(col + 1, row))
			S.set_bg(19, row, S.pic_tile(trainer_pic, 7 - step - 1 if step < 7 else 0, row) if step < 7 else Text.code_tile(Text.SPACE))
		await GB.frames(2)
	_draw_sheet(trainer_pic, 12, 0)


# --- evolution ----------------------------------------------------------------------------

## EvolutionAfterBattle: every mon that levelled up is checked for a level evolution.
func _evolution_after_battle() -> void:
	for i in state.party.size():
		if not can_evolve[i]:
			continue
		var mon: PartyMon = state.party[i]
		for evo in GameData.pokemon[mon.species]["evolutions"]:
			if str(evo.get("method", "")) == "LEVEL" and mon.level >= int(evo.get("level", 101)):
				await _evolve(i, mon, str(evo["species"]))
				break


## Evolution_PartyMonLoop .doEvolution + EvolveMon (engine/movie/evolution.asm).
func _evolve(party_index: int, mon: PartyMon, new_species: String) -> void:
	var old := mon.species
	Text.ram["wStringBuffer"] = mon.nickname
	await Text.print_text("_IsEvolvingText")
	await GB.frames(50)
	Text.clear_area(0, 0, 20, 12)
	S.clear_sprites()
	# EvolveMon
	Sound.low_health_alarm = 0
	Sound.ch_id[Sound.CHAN5] = 0
	Sound.stop_all_music()
	Sound.play_sfx("SFX_TINK")
	await GB.delay3()
	SGB.run("POKEMON_WHOLE_SCREEN", {"species": old, "black": false})
	Title.draw_mon_pic(S, old, 7, 2, true)
	Sound.play_cry(old)
	await Sound.wait_for_sfx()
	Sound.play_music("MUSIC_SAFARI_ZONE")
	await GB.frames(80)
	SGB.run("POKEMON_WHOLE_SCREEN", {"species": old, "black": true})
	var cancelled := false
	var b := 1
	var c := 16
	while c > 0 and not cancelled:
		# Evolution_CheckForCancel: c frames, B cancels
		for f in c:
			await GB.frame
			if GB.joy5 & GB.B:
				cancelled = true
				break
		if cancelled:
			break
		for k in b:
			Title.draw_mon_pic(S, new_species, 7, 2, true)
			await GB.delay3()
			Title.draw_mon_pic(S, old, 7, 2, true)
			await GB.delay3()
		b += 1
		c -= 2
	Sound.stop_all_music()
	if cancelled:
		Sound.play_cry(old)
		SGB.run("POKEMON_WHOLE_SCREEN", {"species": old, "black": false})
		await Sound.wait_for_sfx()
		await Text.print_text("_StoppedEvolvingText")
		Text.clear_screen()
		return
	Title.draw_mon_pic(S, new_species, 7, 2, true)
	Sound.play_cry(new_species)
	SGB.run("POKEMON_WHOLE_SCREEN", {"species": new_species, "black": false})
	await Sound.wait_for_sfx()
	Text.ram["wNameBuffer"] = GameData.mon_name(new_species)
	await Text.print_text("_EvolvedText")
	await Text.run_commands(GameData.text("_IntoText"))
	await Sound.play_sfx_wait_for_current("SFX_GET_ITEM_2")
	await Sound.wait_for_sfx()
	await GB.frames(40)
	Text.clear_screen()
	# RenameEvolvedMon: the default name follows the species
	if mon.nickname == GameData.mon_name(old):
		mon.nickname = GameData.mon_name(new_species)
	var old_max := mon.max_hp
	mon.species = new_species
	mon.recalc_stats()
	mon.hp += mon.max_hp - old_max
	await _learn_move_from_level_up(party_index, mon)
	state.pokedex_owned[new_species] = true
	state.pokedex_seen[new_species] = true

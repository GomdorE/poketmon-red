## The map trainer engine (home/trainers.asm, engine/overworld/trainer_sight.asm):
## CheckFightingMapTrainers, DisplayEnemyTrainerTextAndStartBattle, EndTrainerBattle
## and TalkToTrainer over the current map's trainer headers (maps.json
## "trainer_headers": sprite = 1-based object index = trainer flag bit).
class_name TrainerEngine
extends RefCounted

const PLAYER_SCREEN_X := 0x40   # (fixed) player sprite screen X
const PLAYER_SCREEN_Y := 0x3c   # (fixed) player sprite screen Y (SPRITESTATEDATA1_YPIXELS)
# data/trainers/encounter_types.asm
const FEMALE_TRAINERS := ["LASS", "JR_TRAINER_F", "BEAUTY", "COOLTRAINER_F"]
const EVIL_TRAINERS := ["UNUSED_JUGGLER", "GAMBLER", "ROCKER", "JUGGLER", "CHIEF", "SCIENTIST", "GIOVANNI", "ROCKET"]
const RIVALS := ["RIVAL1", "RIVAL2", "RIVAL3"]

var ms: MapScripts
var ow: Overworld
var state: GameState
var header := {}                # wTrainerHeaderPtr
var seen_by_trainer := false    # wMiscFlags BIT_SEEN_BY_TRAINER
var engaged_class := ""         # wEngagedTrainerClass (without OPP_)
var engaged_set := 0            # wEngagedTrainerSet
var gym_leader_no := 0          # wGymLeaderNo (set by the gym scripts)


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state


func headers() -> Array:
	return ow.map.get("trainer_headers", [])


## The trainer header whose sprite is `npc_index` (0-based), or {}.
func header_for_npc(npc_index: int) -> Dictionary:
	for h in headers():
		if int(h.sprite) == npc_index + 1:
			return h
	return {}


func beaten(h: Dictionary) -> bool:
	return state.has_event(str(h.event))


static func _byte(v: int) -> int:
	return v & 0xFF


## CalcDifference: |a - b| on bytes (a - b, or its two's complement on a borrow).
static func _calc_difference(a: int, b: int) -> int:
	var d := a - b
	if d < 0:
		d = -d
	return d & 0xFF


func _screen_x(n: Dictionary) -> int:
	return _byte(n.px - ow.player.px + PLAYER_SCREEN_X)


func _screen_y(n: Dictionary) -> int:
	return _byte(n.py - ow.player.py + PLAYER_SCREEN_Y)


## CheckSpriteAvailability's screen-region test (the sprite's image index is $ff
## outside it): player Y - 4 .. Y + 4 and X - 4 .. X + 5 blocks.
func _on_screen(n: Dictionary) -> bool:
	if n.hidden:
		return false
	if n.y < ow.player.y - 4 or n.y > ow.player.y + 4:
		return false
	if n.x < ow.player.x - 4 or n.x > ow.player.x + 5:
		return false
	return true


# --- script functions ---------------------------------------------------------------

## CheckFightingMapTrainers: a trainer that sees the player shows the exclamation
## bubble, starts walking up to the player and the map script advances.
func check_fighting_map_trainers() -> void:
	var h := _check_for_engaging_trainers()
	if h.is_empty():
		return
	header = h
	var sprite: int = h.sprite
	if "--trace-scripts" in OS.get_cmdline_user_args() or "--trace-battle" in OS.get_cmdline_user_args():
		print("TRAINER_SEES sprite=%d %s frame=%d player=(%d,%d)" % [sprite, engaged_class, GB.frame_count, ow.player.x, ow.player.y])
	await ow.emotion_bubble(sprite, "shock")   # EXCLAMATION_BUBBLE
	ow.joy_ignore = GB.CTRL_PAD
	_trainer_walk_up_to_player()
	ms._set_script(ms._script_index() + 1)


## DisplayEnemyTrainerTextAndStartBattle: once the trainer has reached the player.
func display_enemy_trainer_text_and_start_battle() -> void:
	var idx: int = int(header.sprite) - 1
	if ow.npc_moving(idx):
		if "--trace-npc" in OS.get_cmdline_user_args():
			var n: Dictionary = ow.npcs[idx]
			print("NPC moving (%d,%d) wc=%d moves=%s idx=%d" % [n.x, n.y, n.walk_counter, str(n.moves), n.move_idx])
		return
	ow.joy_ignore = 0
	await ow.display_text_id(str(ow.npcs[idx].text), idx)
	_start_trainer_battle()


## EndTrainerBattle: the trainer is flagged as beaten (unless the player lost).
func end_trainer_battle() -> void:
	seen_by_trainer = false
	if not ow.last_battle_won:
		_reset_button_pressed_and_map_script()
		return
	if not header.is_empty():
		state.set_event(str(header.event))
		set_enemy_trainer_to_stay()
	_reset_button_pressed_and_map_script()


## TalkToTrainer: the after-battle text for a beaten trainer, otherwise the
## before-battle text and (when the player walked up to them) the battle.
func talk_to_trainer(h: Dictionary) -> void:
	header = h
	if beaten(h):
		await ow.print_text(str(h.after))
		return
	await ow.print_text(str(h.before))
	if seen_by_trainer:
		return
	_engage_map_trainer(int(h.sprite))
	ms._set_script(ms._script_index() + 1)
	_start_trainer_battle()


## The text handler shared by every trainer NPC (its text pointer calls TalkToTrainer).
## Returns false when `npc_index` is not a map trainer.
func handle_text(npc_index: int) -> bool:
	if npc_index < 0:
		return false
	var h := header_for_npc(npc_index)
	if h.is_empty():
		return false
	await talk_to_trainer(h)
	return true


## SetEnemyTrainerToStayAndFaceAnyDirection (PrintEndBattleText after a win): the
## trainer keeps facing the player from now on (the rivals walk away instead).
func set_enemy_trainer_to_stay() -> void:
	if header.is_empty() or engaged_class in RIVALS:
		return
	var n: Dictionary = ow.npcs[int(header.sprite) - 1]
	n.movement = "STAY"
	n.range = "NONE"
	n.face_any = true


# --- internals --------------------------------------------------------------------

## CheckForEngagingTrainers + TrainerEngage.
func _check_for_engaging_trainers() -> Dictionary:
	for h in headers():
		if beaten(h):
			continue
		var n: Dictionary = ow.npcs[int(h.sprite) - 1]
		if not _on_screen(n):
			continue
		if _trainer_engage(n, int(h.range) << 4):
			seen_by_trainer = true
			_engage_map_trainer(int(h.sprite))
			return h
	return {}


func _trainer_engage(n: Dictionary, distance: int) -> bool:
	var sx := _screen_x(n)
	var sy := _screen_y(n)
	var facing: int = n.facing
	var d := 0
	if sy == PLAYER_SCREEN_Y:
		d = _calc_difference(PLAYER_SCREEN_X, sx)
	elif sx == PLAYER_SCREEN_X:
		d = _calc_difference(PLAYER_SCREEN_Y, sy)
	else:
		return false
	if d == 0:
		return false
	# CheckSpriteCanSeePlayer
	if d > distance:
		return false
	match facing:
		Overworld.FACE_DOWN, Overworld.FACE_UP:
			if sx != PLAYER_SCREEN_X:
				return false
		_:
			if sy != PLAYER_SCREEN_Y:
				return false
	# CheckPlayerIsInFrontOfSprite (a sprite on the topmost tile, Y = $fc, counts as $0c)
	if sy == 0xfc:
		sy = 0x0c
	match facing:
		Overworld.FACE_DOWN: return sy < PLAYER_SCREEN_Y
		Overworld.FACE_UP: return sy >= PLAYER_SCREEN_Y
		Overworld.FACE_LEFT: return sx >= PLAYER_SCREEN_X
		_: return sx < PLAYER_SCREEN_X


## EngageMapTrainer: the trainer's class / set from the map object, then PlayTrainerMusic.
func _engage_map_trainer(sprite: int) -> void:
	var o: Dictionary = ow.map["objects"][sprite - 1]
	engaged_class = str(o.trainer).trim_prefix("OPP_")
	engaged_set = int(o.trainer_no)
	_play_trainer_music()


## PlayTrainerMusic: none for the rivals and gym leaders.
func _play_trainer_music() -> void:
	if engaged_class in RIVALS or gym_leader_no != 0:
		return
	Sound.fade_out_control = 0
	Sound.stop_all_music()
	var music := "MUSIC_MEET_MALE_TRAINER"
	if engaged_class in EVIL_TRAINERS:
		music = "MUSIC_MEET_EVIL_TRAINER"
	elif engaged_class in FEMALE_TRAINERS:
		music = "MUSIC_MEET_FEMALE_TRAINER"
	Sound.play_music(music)


## TrainerWalkUpToPlayer: (distance / 16) - 1 steps in the trainer's facing direction.
func _trainer_walk_up_to_player() -> void:
	var n: Dictionary = ow.npcs[int(header.sprite) - 1]
	var sx := _screen_x(n)
	var sy := _screen_y(n)
	var d := 0
	var move := 0
	match int(n.facing):
		Overworld.FACE_DOWN:
			d = _calc_difference(PLAYER_SCREEN_Y, sy)
			move = Overworld.NPC_DOWN
		Overworld.FACE_UP:
			d = _calc_difference(PLAYER_SCREEN_Y, sy)
			move = Overworld.NPC_UP
		Overworld.FACE_RIGHT:
			d = _calc_difference(PLAYER_SCREEN_X, sx)
			move = Overworld.NPC_RIGHT
		_:
			d = _calc_difference(PLAYER_SCREEN_X, sx)
			move = Overworld.NPC_LEFT
	if d == 0x10:
		return   # right next to the player
	var steps := (((d >> 4) | (d << 4)) & 0xFF) - 1   # swap a / dec a
	var moves: Array = []
	for i in steps:
		moves.append(move)
	ow.move_sprite(int(header.sprite) - 1, moves)


## StartTrainerBattle + InitBattleEnemyParameters.
func _start_trainer_battle() -> void:
	ow.joy_ignore = 0
	var req := {
		"trainer": engaged_class, "team": engaged_set,
		"win_text": str(header["end"]), "lose_text": str(header["end"]),
	}
	if gym_leader_no != 0:
		req["gym_leader"] = gym_leader_no
	ow.battle_request = req
	ms._set_script(ms._script_index() + 1)


## ResetButtonPressedAndMapScript.
func _reset_button_pressed_and_map_script() -> void:
	ow.joy_ignore = 0
	ms._set_script(0)

from pathlib import Path
root = str(Path(__file__).resolve().parents[1] / "scripts" / "game") + "/"


def patch(path, pairs):
    s = open(root + path, encoding="utf-8").read()
    for old, new in pairs:
        assert old in s, (path, old[:70])
        s = s.replace(old, new, 1)
    open(root + path, "w", encoding="utf-8", newline="\n").write(s)


patch("battle_anim.gd", [
    ('''var move_by_id := {}        # move id -> move key
''', '''var move_by_id := {}        # move id -> move key
var force_on := false       # the trade movie clears wOptions: animations always play
'''),
    ('''	player_turn = turn_player
	is_trainer_battle = not battle.is_wild''', '''	player_turn = turn_player
	is_trainer_battle = battle != null and not battle.is_wild'''),
    ('''## MoveAnimation for the ball toss: TossBallAnimation with wPokeBallAnimData.''',
     '''## Trade_ShowAnimation: MoveAnimation outside a battle (wAnimationType 0, wOptions
## cleared by TradeAnimCommon so the animation always plays).
static func play_trade(anim: String) -> void:
	var a := BattleAnim.new(null, true)
	a.anim_id = id_of(anim)
	a.anim_type = 0
	a.force_on = true
	await a._move_animation()


## MoveAnimation for the ball toss: TossBallAnimation with wPokeBallAnimData.'''),
    ('''	if not Settings.battle_animation_on():
		await GB.frames(30)   # BATTLE ANIMATION OFF''', '''	if not force_on and not Settings.battle_animation_on():
		await GB.frames(30)   # BATTLE ANIMATION OFF'''),
    ('''		"TailWhipAnimationUnused":
			sub_counter = 1
			await GB.frames(20)''', '''		"TailWhipAnimationUnused":
			sub_counter = 1
			await GB.frames(20)
		"TradeHidePokemon":
			# ClearMonPicFromTileMap at (7, 2): the mon disappears into the ball
			if sub_counter == 6:
				Text.clear_area(7, 2, 7, 7)
		"TradeShakePokeball":
			# at the end the shaking ball jumps up (BallMoveDistances1), then SFX_TRADE_MACHINE
			if sub_counter == 1:
				for dy in [-12, -12, -8]:
					_move_oam_y(4, dy)
					await GB.delay3()
				await _clean_oam()
				Sound.play_sfx("SFX_TRADE_MACHINE")
		"TradeJumpPokeball":
			# BallMoveDistances2: the ball bounces left while the screen scrolls, SFX_SWAP on
			# the 12-pixel rises and the last bounce; ClearScreen at the end
			var dist := [11, 12, -12, -7, 7, 12, -8, 8]
			for i in dist.size():
				_move_oam_y(4, int(dist[i]))
				if i + 1 >= dist.size() or int(dist[i + 1]) == 12:
					Sound.play_sfx("SFX_SWAP")
				await GB.frames(5)
				S.scx = (S.scx - 8) & 0xFF
			Text.clear_screen()'''),
    ('''## AnimationCleanOAM: one frame, then ClearSprites.''', '''## Add `dy` to the Y of the first `count` OAM entries.
func _move_oam_y(count: int, dy: int) -> void:
	for k in mini(count, S.oam.size()):
		if S.oam[k] != null:
			S.oam[k].y += dy


## AnimationCleanOAM: one frame, then ClearSprites.'''),
])
print("ok")

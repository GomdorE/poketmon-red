## LearnMove (engine/pokemon/learn_move.asm): TryingToLearn, WhichMoveToForget,
## AbandonLearning, OneTwoAnd / Poof / ForgotAnd, LearnedMove1Text. Shared by the
## battle (level up, evolution) and the TM/HM items.
class_name LearnMove
extends RefCounted


## Returns true when the move was learnt. `in_battle` picks the sound bank for
## sound_get_item_1 (SFX_LEVEL_UP in battle, SFX_GET_ITEM_1 outside).
static func learn(mon: PartyMon, _party_index: int, move: String, in_battle: bool) -> bool:
	var S: GBScreen = GB.screen
	if mon.has_move(move):
		return false
	Text.ram["wLearnMoveMonName"] = mon.nickname
	Text.ram["wStringBuffer"] = GameData.move_name(move)
	var pp: int = GameData.moves[move]["pp"]
	var saved := S.snapshot_bg()
	if mon.moves.size() >= 4:
		var forget := -1
		while forget < 0:
			# TryingToLearn
			await Text.print_text("_TryingToLearnText")
			if await Menu.yes_no(14, 7):
				await Text.print_text("_WhichMoveToForgetText")
				Menu.draw_box(4, 7, 14, 4)
				var names: Array = []
				for m in mon.moves:
					names.append(GameData.move_name(m.move))
				var pos := Menu.place_move_list(5, 8, names)
				var keys := await Menu.handle_input(5, 8, mon.moves.size(), GB.A | GB.B, 1, 0, pos)
				var chosen := Menu.current
				Menu.erase_cursor()
				S.restore_bg(saved)
				if keys & GB.A:
					forget = chosen
					break
			# AbandonLearning
			await Text.print_text("_AbandonLearningText")
			if await Menu.yes_no(14, 7):
				await Text.print_text("_DidNotLearnText")
				return false
		# OneTwoAndText, SFX_SWAP, PoofText, ForgotAndText
		Text.ram["wNameBuffer"] = GameData.move_name(mon.moves[forget].move)
		Menu.message_box()
		await GB.delay3()
		Text.cursor = Vector2i(1, 14)
		await Text.run_commands(GameData.text("_OneTwoAndText"))
		await Text.run_commands([["text_pause", ""]])
		await Sound.play_sfx_wait_for_current("SFX_SWAP")
		await Text.run_commands(GameData.text("_PoofText"))
		await Text.run_commands([["text_pause", ""]])
		await Text.run_commands(GameData.text("_ForgotAndText"))
		mon.moves[forget] = {"move": move, "pp": pp, "max_pp": pp}
	else:
		mon.moves.append({"move": move, "pp": pp, "max_pp": pp})
	# LearnedMove1Text + sound_get_item_1 + text_promptbutton
	Menu.message_box()
	await GB.delay3()
	Text.cursor = Vector2i(1, 14)
	await Text.run_commands(GameData.text("_LearnedMove1Text"))
	Sound.play_sfx("SFX_LEVEL_UP" if in_battle else "SFX_GET_ITEM_1")
	await Sound.wait_for_sfx()
	await Text.run_commands([["prompt", ""]])
	return true

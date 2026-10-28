## Chapter 5: the S.S. Anne (scripts/SSAnne2F.asm rival, SSAnne2FRooms.asm,
## SSAnneCaptainsRoom.asm, SSAnneKitchen.asm and the cry-only texts). The cabin maps
## with trainers (1F rooms, B1F rooms, bow) only need the generic trainer table.
class_name SSAnneScripts
extends RefCounted

var chapter: Chapter5Scripts
var ms: MapScripts
var ow: Overworld
var state: GameState


func _init(c: Chapter5Scripts) -> void:
	chapter = c
	ms = c.ms
	ow = c.ow
	state = c.state


func run_map_script(_entered: bool) -> bool:
	match ow.map_id:
		"SS_ANNE_2F":
			await _2f()
			return true
		"SS_ANNE_2F_ROOMS":
			# SSAnne2FRooms_Script: BIT_NO_AUTO_TEXT_BOX, then the trainer table
			ow.no_auto_text_box = true
			ow.do_not_wait_after_text = false
			return false
		"SS_ANNE_CAPTAINS_ROOM":
			# SSAnneCaptainsRoomEventScript: the captain does not turn to the player until
			# his back has been rubbed
			if not state.has_event("EVENT_RUBBED_CAPTAINS_BACK"):
				ow.no_npc_face_player = true
			return true
	return false


func text(text_id: String, _npc_index: int) -> bool:
	match text_id:
		"TEXT_SSANNE2F_RIVAL":
			await ow.print_text("_SSAnne2FRivalText")
		"TEXT_SSANNE2F_RIVAL_CUT_MASTER":
			await ow.print_text("_SSAnne2FRivalCutMasterText")
		"TEXT_SSANNE1FROOMS_WIGGLYTUFF":
			Sound.play_cry("WIGGLYTUFF")
		"TEXT_SSANNEB1FROOMS_MACHOKE":
			Sound.play_cry("MACHOKE")
		"TEXT_SSANNE2FROOMS_GENTLEMAN3":
			# the text, then the Pokédex page of SNORLAX over the restored screen
			var saved: PackedInt32Array = GB.screen.snapshot_bg()
			await ow.print_text("_SSAnne2FRoomsGentleman3Text")
			GB.screen.restore_bg(saved)
			Text.no_delay = true
			await PokedexPage.new().show("SNORLAX")
			SGB.run("DEFAULT")
			Text.no_delay = false
			ow.reload_map_view()
		"TEXT_SSANNEKITCHEN_COOK7": await _cook7()
		"TEXT_SSANNECAPTAINSROOM_CAPTAIN": await _captain()
		_:
			return false
	return true


# --- 2F: the rival ---------------------------------------------------------------------

## SSAnne2F_ScriptPointers.
func _2f() -> void:
	match ms._script_index():
		0:
			# SSAnne2FDefaultScript: in front of the captain's cabin door
			var pos := Vector2i(ow.player.x, ow.player.y)
			if not pos in [Vector2i(36, 8), Vector2i(37, 8)]:
				return
			Sound.stop_all_music()
			Sound.play_music("MUSIC_MEET_RIVAL")
			ow.show_object(1)   # TOGGLE_SS_ANNE_2F_RIVAL
			await GB.delay3()
			ow.joy_ignore = GB.CTRL_PAD
			var moves: Array = []
			for i in (4 if ow.player.x == 37 else 3):
				moves.append(Overworld.NPC_DOWN)
			ow.move_sprite(1, moves)
			ms._set_script(1)
		1:
			# SSAnne2FRivalStartBattleScript
			if ow.npc_moving(1):
				return
			await _set_rival_facing()
			ow.joy_ignore = 0
			await ow.display_text_id("TEXT_SSANNE2F_RIVAL", 1)
			await GB.delay3()
			var team: int = {"SQUIRTLE": 1, "BULBASAUR": 2, "CHARMANDER": 3}.get(state.rival_starter, 3)
			await _set_rival_facing()
			ow.battle_request = {"trainer": "RIVAL2", "team": team, "name": state.rival_name,
				"win_text": "SSAnne2FRivalDefeatedText", "lose_text": "SSAnne2FRivalVictoryText"}
			ms._set_script(2)
		2:
			# SSAnne2FRivalAfterBattleScript
			if not ow.last_battle_won:
				_reset_scripts()
				return
			await _set_rival_facing()
			ow.joy_ignore = GB.CTRL_PAD
			await ow.display_text_id("TEXT_SSANNE2F_RIVAL_CUT_MASTER", 1)
			var moves: Array = []
			if ow.player.x != 37:
				moves = [Overworld.NPC_RIGHT, Overworld.NPC_DOWN]
			for i in 4:
				moves.append(Overworld.NPC_DOWN)
			ow.move_sprite(1, moves)
			Sound.stop_all_music()
			Sound.rival_alternate_start()
			ms._set_script(3)
		3:
			# SSAnne2FRivalExitScript
			if ow.npc_moving(1):
				return
			ow.joy_ignore = 0
			ow.hide_object(1)
			await Sound.play_default_music()
			ms._set_script(4)   # SCRIPT_SSANNE2F_NOOP
			chapter.trace("SS_ANNE_RIVAL_DONE")
		4:
			pass


## SSAnne2FResetScripts.
func _reset_scripts() -> void:
	ow.joy_ignore = 0
	ms._set_script(0)


## SSAnne2FSetFacingDirectionScript: beside the door the player turns left and the rival
## right, below it the rival faces down.
func _set_rival_facing() -> void:
	if ow.player.x == 37:
		ow.player.facing = Overworld.FACE_LEFT
		ow.set_npc_facing(1, Overworld.FACE_RIGHT)
	else:
		ow.set_npc_facing(1, Overworld.FACE_DOWN)
	await GB.delay3()


# --- kitchen, captain ------------------------------------------------------------------

## SSAnneKitchenCook7Text: the main course from hRandomAdd.
func _cook7() -> void:
	await ow.print_text("_SSAnneKitchenCook7MainCourseIsText")
	var r := ow.rng.randi_range(0, 255)
	var label := "SSAnneKitchenCook7PrimeBeefSteakText"
	if r & 0x80:
		label = "SSAnneKitchenCook7SalmonDuSaladText"
	elif r & 0x10:
		label = "SSAnneKitchenCook7EelsAuBarbecueText"
	await ow.print_text(label)


## SSAnneCaptainsRoomCaptainText.
func _captain() -> void:
	if state.has_event("EVENT_GOT_HM01"):
		await ow.print_text("_SSAnneCaptainsRoomCaptainNotSickAnymoreText")
		return
	# SSAnneCaptainsRoomRubCaptainsBackText: the text, then the "healed" jingle to its end
	await ow.print_text("_SSAnneCaptainsRoomRubCaptainsBackText")
	Sound.play_new_sound_in_own_bank("MUSIC_PKMN_HEALED")
	while Sound.channel1_is("MUSIC_PKMN_HEALED"):
		await GB.frame
	await Sound.play_default_music()
	state.set_event("EVENT_RUBBED_CAPTAINS_BACK")
	ow.no_npc_face_player = false
	await ow.print_text("_SSAnneCaptainsRoomCaptainIFeelMuchBetterText")
	if state.give_item("HM01", 1):
		Text.ram["wStringBuffer"] = GameData.item_name("HM01")
		await ow.print_text("_SSAnneCaptainsRoomCaptainReceivedHM01Text")
		await Sound.text_sound("sound_get_key_item")
		state.set_event("EVENT_GOT_HM01")
		chapter.trace("HM01_RECEIVED")
	else:
		await ow.print_text("_SSAnneCaptainsRoomCaptainHM01NoRoomText")
		ow.no_npc_face_player = true

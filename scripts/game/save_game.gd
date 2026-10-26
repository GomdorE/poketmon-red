## The save file (engine/menus/save.asm SaveMenu / TryLoadSaveFile) as user://save.json:
## the game state, the party and the play time. There is one file, like the SRAM save.
class_name SaveGame
extends RefCounted

const PATH := "user://save.json"
const VERSION := 1


static func exists() -> bool:
	return FileAccess.file_exists(PATH)


static func read_dict() -> Dictionary:
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return {}
	return GameData._intify(parsed)


static func read() -> GameState:
	var d := read_dict()
	var state := GameState.new()
	state.from_dict(d.get("state", {}))
	var t: Dictionary = d.get("play_time", {})
	GB.play_time_hours = int(t.get("h", 0))
	GB.play_time_minutes = int(t.get("m", 0))
	GB.play_time_seconds = int(t.get("s", 0))
	GB.play_time_frames = int(t.get("f", 0))
	GB.play_time_maxed = bool(t.get("maxed", false))
	return state


static func write(state: GameState) -> void:
	var d := {
		"version": VERSION,
		"state": state.to_dict(),
		"play_time": {"h": GB.play_time_hours, "m": GB.play_time_minutes, "s": GB.play_time_seconds,
			"f": GB.play_time_frames, "maxed": GB.play_time_maxed},
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()


## CheckPreviousSaveFile: does the existing file belong to this game (same name and id)?
static func same_game(state: GameState) -> bool:
	var d := read_dict()
	var s: Dictionary = d.get("state", {})
	return s.get("player_name", "") == state.player_name and int(s.get("player_id", -1)) == state.player_id


## PrintSaveScreenText / DisplayContinueGameInfo: the info box with the player's name,
## badges, owned Pokémon and play time, its top-left corner at (x, y).
static func print_info_box(state: GameState, x: int, y: int) -> void:
	var ko := GameData.lang == "ko"
	Menu.draw_box(x, y, 14, 8)
	Text.place_string(x + 1, y + 2, "플레이어" if ko else "PLAYER")
	Text.place_string(x + 1, y + 4, "배지" if ko else "BADGES")
	Text.place_string(x + 1, y + 6, "도감" if ko else "#DEX")
	Text.place_string(x + 1, y + 8, "시간" if ko else "TIME")
	Text.place_string(x + 8, y + 2, state.player_name)
	Text.place_string(x + 13, y + 4, "%2d" % state.badges)
	Text.place_string(x + 12, y + 6, "%3d" % state.pokedex_owned.size())
	Text.place_string(x + 9, y + 8, "%3d" % GB.play_time_hours)
	Text.put(x + 12, y + 8, 0x6D)   # ':'
	Text.place_string(x + 13, y + 8, "%02d" % GB.play_time_minutes)


## SaveMenu (Start menu > SAVE). Runs inside the overworld with the map on screen.
static func save_menu(state: GameState) -> void:
	var ko := GameData.lang == "ko"
	print_info_box(state, 4, 0)
	await Text.print_text("_WouldYouLikeToSaveText")
	if not await Menu.yes_no(0, 7):
		return
	if exists() and not same_game(state):
		await Text.print_text("_OlderFileWillBeErasedText")
		if not await Menu.yes_no(0, 7):
			return
	write(state)
	Text.clear_area(1, 13, 18, 4)
	Text.place_string(1, 14, "저장 중..." if ko else "Now saving...")
	await GB.frames(120)
	await Text.print_text("_GameSavedText")
	await Sound.play_sfx_wait_for_current("SFX_SAVE")
	await Sound.wait_for_sfx()
	await GB.frames(30)

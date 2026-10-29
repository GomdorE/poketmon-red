## The elevators (scripts/CeladonMartElevator.asm, RocketHideoutElevator.asm with
## engine/events/elevator.asm DisplayElevatorFloorMenu and engine/overworld/elevator.asm
## ShakeElevator). The elevator map's two warps lead back to the warp the player came in
## by (wWarpedFromWhichWarp/Map) until a floor is chosen from the panel's list menu.
class_name Elevator
extends RefCounted

var used := false   # wCurrentMapScriptFlags BIT_CUR_MAP_USED_ELEVATOR


## The elevator map script: on entry the warps point back where the player came from; the
## frame after a floor was chosen the elevator shakes (the Rocket Hideout one after Delay3).
## wDoNotWaitForButtonPressAfterDisplayingText is set every frame (the panel text ends
## without a button), which the text handler does here.
func run_map_script(ow: Overworld, entered: bool, delay_first: bool = false) -> void:
	if entered and GameData.maps.has(ow.warped_from_map):   # (a test stage has no origin)
		_store_warp_entries(ow, ow.warped_from_warp, ow.warped_from_map)
	if used:
		used = false
		if delay_first:
			await GB.delay3()
		await shake(ow)


## CeladonMartElevatorStoreWarpEntriesScript / DisplayElevatorFloorMenu.UpdateWarp: both
## warps of the elevator get destination warp `warp` (0-based) of `map`. The map data is
## shared, so the elevator works on its own copy.
func _store_warp_entries(ow: Overworld, warp: int, map: String) -> void:
	if not ow.map.get("_elevator_copy", false):
		ow.map = ow.map.duplicate(true)
		ow.map["_elevator_copy"] = true
	for i in 2:
		ow.map["warps"][i]["warp_id"] = warp + 1
		ow.map["warps"][i]["map"] = map
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("ELEVATOR_WARPS -> %s warp=%d" % [map, warp])


## DisplayElevatorFloorMenu: "Which floor do you want?" and the floors as a list menu
## (SPECIALLISTMENU); the chosen floor's warp replaces the elevator's exits.
func floor_menu(ow: Overworld, floors: Array, warp_maps: Array) -> void:
	await Text.print_text("_WhichFloorText")
	var saved_offset := ListMenu.last_offset
	var pick := await ListMenu.show_items(floors, false, false)
	ListMenu.last_offset = saved_offset
	if pick < 0:
		return
	used = true
	_store_warp_entries(ow, int(warp_maps[pick][0]), str(warp_maps[pick][1]))


## ShakeElevator: the rows beyond the screen edges are drawn, then the BG scrolls up and
## down one pixel 100 times with SFX_COLLISION every two frames, SFX_SAFARI_ZONE_PA plays
## to the end and the map music restarts.
static func shake(ow: Overworld) -> void:
	var S: GBScreen = GB.screen
	ow._render(true)   # ShakeElevatorRedrawRow (above and below the screen)
	await GB.delay3()
	Sound.stop_all_music()
	var d := S.scy
	var e := 1
	for i in 100:
		e = -e   # e ^= $fe: 1 <-> -1
		S.scy = d + e
		Sound.play_sfx("SFX_COLLISION")
		await GB.frames(2)
	S.scy = d
	Sound.stop_all_music()
	Sound.play_sfx("SFX_SAFARI_ZONE_PA")
	await Sound.wait_while_channel5_is("SFX_SAFARI_ZONE_PA")
	Sound.play_default_music()
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("ELEVATOR_SHAKE_DONE frame=%d" % GB.frame_count)

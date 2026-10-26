## Overworld engine: map rendering from blocks, the player, NPC sprites, warps,
## signs and dialogue, map scripts (home/overworld.asm, engine/overworld/movement.asm).
##
## Coordinates: map coordinates (x, y) count 16x16 blocks ("steps"); the tile grid
## has BORDER tiles of padding around the map so the camera can show the border
## blocks and connected maps. Screen pixel (64, 64) is always the player's block.
class_name Overworld
extends RefCounted

const FACE_DOWN := 0
const FACE_UP := 4
const FACE_LEFT := 8
const FACE_RIGHT := 12
const NPC_DOWN := 0x00
const NPC_UP := 0x40
const NPC_LEFT := 0x80
const NPC_RIGHT := 0xC0
const NPC_CHANGE_FACING := 0xE0
const BORDER := 12

## Sprite sheet of a SPRITE_* constant (data/sprites/sprites.asm: the sheet file names).
static func sprite_sheet(sprite: String) -> String:
	var n := sprite.trim_prefix("SPRITE_").trim_prefix("UNUSED_")
	if n.begins_with("GAMBLER_ASLEEP"):
		n = "GAMBLER_ASLEEP"
	return "spr_" + n.to_lower()

var state: GameState
var S: GBScreen
var map_id := ""
var map: Dictionary
var tileset: Dictionary
var ts_sheet := ""
var grid_w := 0
var grid_h := 0
var grid_ids := PackedByteArray()
var npcs: Array = []
var player := PlayerState.new()


class PlayerState:
	var x := 0
	var y := 0
	var px := 0
	var py := 0
	var facing := 0
	var walk_counter := 0
	var step_dx := 0
	var step_dy := 0
	var intra := 0
	var anim := 0
	var direction := 0
	var moving_dir := 0
	var last_stop_dir := 0
	var check_180 := true
var sim_queue: Array = []          # simulated joypad states (front first)
var joy_ignore := 0
var anim_counter1 := 0
var anim_counter2 := 0
var water_shift := 0
var flower_frame := 1
var scripts: MapScripts
var follow_script := {}            # the Pallet Town "follow Oak" movement script
var scripted_npc := {}             # DoScriptedNPCMovement state (8 frames per step)
var running := true
var battle_request := {}
var do_not_wait_after_text := false
var no_auto_text_box := false
var in_text := false
var start_menu_item := 0   # wBattleAndStartSavedMenuItem
var last_battle_won := false
var catch_demo_request := {}   # BATTLE_TYPE_OLD_MAN
var rng := RandomNumberGenerator.new()
var oam_emote := -1
var debug_walk: Array = []        # --sim=RRUU|A... test input: one step per letter, A = press A, | = next map
var debug_segments: Array = []
var _debug_last := Vector2i(-1, -1)


func _init(s: GameState) -> void:
	state = s


# --- main loop ----------------------------------------------------------------

## The overworld loop. `reload` false resumes after a battle (the map is already
## loaded and the map-script state is kept).
func run(reload: bool = true) -> void:
	S = GB.screen
	Text.vars["PLAYER"] = state.player_name
	Text.vars["RIVAL"] = state.rival_name
	if reload:
		rng.randomize()
		scripts = MapScripts.new(self)
		load_map(state.cur_map, state.x, state.y, state.facing)
		_enter_map_music(false)
		S.normal_pals()
	GB.play_time_counting = true
	if not GB.frame.is_connected(_hide_sprites_under_text_boxes):
		GB.frame.connect(_hide_sprites_under_text_boxes)
	if reload:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--sim="):
				for seg in arg.get_slice("=", 1).split("|"):
					var steps: Array = []
					for ch in seg:
						if ch in "UDLRA":
							steps.append(ch)
					debug_segments.append(steps)
		_next_debug_segment()
	while running:
		await GB.frame
		_tick_tile_animation()
		if player.walk_counter > 0:
			_advance_player()
			_update_npcs()
			_render()
			if player.walk_counter == 0:
				await _after_step()
			continue
		# a battle requested by a text script (TalkToTrainer, the old man) starts before
		# the next JoypadOverworld / RunMapScript (OverworldLoop .displayDialogue -> .newBattle)
		if not battle_request.is_empty():
			running = false
			break
		# JoypadOverworld
		await scripts.run_map_script()
		if not battle_request.is_empty():
			running = false
		if not running:
			break
		var simulating := sim_queue.size() > 0
		var held := _joypad()
		var pressed := GB.pressed & ~joy_ignore
		if simulating or follow_script.size() > 0:
			pressed = held
		elif debug_walk.size() > 0 and joy_ignore == 0 and follow_script.is_empty() and scripted_npc.is_empty():
			var ch: String = debug_walk[0]
			pressed = 0
			held = 0
			if ch == "A":
				debug_walk.pop_front()
				print("debug walk: A at (%d,%d) facing %d frame %d" % [player.x, player.y, player.facing, GB.frame_count])
				pressed = GB.A
			else:
				held = {"U": GB.UP, "D": GB.DOWN, "L": GB.LEFT, "R": GB.RIGHT}[ch]
				var face_before := player.facing
				var dir_face: int = {"U": FACE_UP, "D": FACE_DOWN, "L": FACE_LEFT, "R": FACE_RIGHT}[ch]
				await _handle_direction(held)
				if player.walk_counter > 0:
					print("debug walk: %s from (%d,%d) frame %d" % [ch, player.x, player.y, GB.frame_count])
					debug_walk.pop_front()
				elif face_before == dir_face:
					print("debug walk: blocked %s at (%d,%d) on %s" % [ch, player.x, player.y, map_id])
					debug_walk.pop_front()
				_update_npcs()
				_render()
				continue
		if pressed & GB.START and not _controlled_by_game():
			await _start_menu()
		elif pressed & GB.A and not _controlled_by_game():
			await _interact()
		elif held & GB.CTRL_PAD:
			await _handle_direction(held)
		else:
			player.check_180 = true
			if player.moving_dir != 0:
				player.last_stop_dir = player.moving_dir
				player.moving_dir = 0
		_update_npcs()
		_render()


func _next_debug_segment() -> void:
	if debug_segments.size() > 0:
		debug_walk = debug_segments.pop_front()
	else:
		debug_walk = []


## Back from a battle: the map is reloaded and fades in from white (MapEntryAfterBattle);
## a blackout returns the player to the last Pokémon Center instead (HandleBlackOut).
func after_battle(battle_result: String) -> void:
	last_battle_won = battle_result == "won"
	state.encounter_cooldown = 3   # EnterMap: three steps without wild battles
	if battle_result == "blackout":
		# AllPokemonFainted: the map script runs once with wIsInBattle = LOST_BATTLE
		await scripts.run_map_script()
		await _black_out()
	else:
		# the map data and the sprites' positions are kept; only the screen is redrawn
		S.white_out()
		S.clear_sprites()
		SGB.run("OVERWORLD", {"map": map_id, "last_map": state.last_map})
		_render()
		_enter_map_music(true)
		await Intro.fade_in_from_white()
		S.normal_pals()
	running = true
	await run(false)


## Fly-warp spots (data/maps/special_warps.asm): where a blackout puts the player.
const FLY_WARPS := {
	"PALLET_TOWN": Vector2i(5, 6), "VIRIDIAN_CITY": Vector2i(23, 26), "PEWTER_CITY": Vector2i(13, 26),
	"CERULEAN_CITY": Vector2i(19, 18), "LAVENDER_TOWN": Vector2i(3, 6), "VERMILION_CITY": Vector2i(11, 4),
	"CELADON_CITY": Vector2i(41, 10), "FUCHSIA_CITY": Vector2i(19, 28), "CINNABAR_ISLAND": Vector2i(11, 12),
	"INDIGO_PLATEAU": Vector2i(9, 6), "SAFFRON_CITY": Vector2i(9, 30), "ROUTE_4": Vector2i(11, 6), "ROUTE_10": Vector2i(11, 20),
}


## HandleBlackOut: fade to black, stop the music, halve the money, heal the party
## (ResetStatusAndHalveMoneyOnBlackout) and warp to the last blackout map's fly spot.
func _black_out() -> void:
	if "--trace-battle" in OS.get_cmdline_user_args():
		print("BLACKOUT frame=%d money=%d dest=%s" % [GB.frame_count, state.money, state.last_blackout_map])
	await Intro.fade_out_to_black()
	Sound.fade_out_then(8)
	await GB.frames(8 * 8)
	Sound.stop_all_sound()
	state.money = state.money / 2
	Battle.heal_party(state)
	var dest: String = state.last_blackout_map
	var pos: Vector2i = FLY_WARPS.get(dest, Vector2i(5, 6))
	state.last_map = dest
	load_map(dest, pos.x, pos.y, FACE_DOWN)
	_enter_map_music(false)
	S.normal_pals()


## A text box shown from the overworld loop itself (DisplayTextID with auto text boxes).
func _show_overworld_text(label: String, wait_for_button: bool) -> void:
	in_text = true
	Menu.message_box()
	await GB.delay3()
	await Text.print_text_no_box(label)
	if wait_for_button:
		await Text.wait_scroll_button(false)
	await Text.hold_text_display_open()
	in_text = false
	_render()


## ApplyOutOfBattlePoisonDamage: every fourth step each poisoned mon loses 1 HP; a
## mon that faints is announced; the screen flashes with SFX_POISONED while any mon
## is still poisoned. Returns true when the player blacked out.
func _apply_poison_step() -> bool:
	if state.party.is_empty() or (state.step_counter & 3) != 0:
		return false
	for m in state.party:
		if not (m.status & PartyMon.PSN) or m.hp <= 0:
			continue
		m.hp -= 1
		if "--trace-battle" in OS.get_cmdline_user_args():
			print("POISON_STEP frame=%d %s hp=%d step=%d" % [GB.frame_count, m.nickname, m.hp, state.step_counter])
		if m.hp == 0:
			m.status = 0
			Text.ram["wNameBuffer"] = m.nickname
			joy_ignore = 0
			await _show_overworld_text("_PokemonFaintedText", true)
	var any_poisoned := false
	for m in state.party:
		if m.status & PartyMon.PSN:
			any_poisoned = true
	if any_poisoned:
		# ChangeBGPalColor0_4Frames: BG colour 0 becomes dark gray for 4 frames
		var saved_bgp := S.bgp.duplicate()
		S.bgp = GBScreen.pal(3, 2, 1, 2)
		Sound.play_sfx("SFX_POISONED")
		await GB.frames(4)
		S.bgp = saved_bgp
	for m in state.party:
		if m.hp > 0:
			return false
	await _show_overworld_text("_PlayerBlackedOutText", false)
	await _black_out()
	return true


## TryDoWildEncounter: standing on the map's grass tile (or anywhere in a cave), the
## encounter rate against a random byte, then the slot table (WildMonEncounterSlotChances).
func _try_wild_encounter() -> void:
	if not sim_queue.is_empty() or not follow_script.is_empty() or not scripted_npc.is_empty():
		return
	if state.encounter_cooldown > 0:
		return
	var wild: Dictionary = GameData.wild["maps"].get(map_id, {})
	if wild.is_empty() or not wild.has("grass"):
		return
	if _is_warp_at(player.x, player.y):
		var tid := _tile_id_under(player.x, player.y)
		if tid in tileset["warp_tiles"] or tid in tileset["door_tiles"]:
			return
	# the bottom-right 8x8 tile of the half-block the player stands on
	var gx := BORDER + player.x * 2 + 1
	var gy := BORDER + player.y * 2 + 1
	var t: int = grid_ids[gy * grid_w + gx]
	var grass: int = int(tileset.get("grass_tile", -1))
	var rate: int = int(wild.get("rate", 0))
	if t != grass:
		# indoor maps (caves) allow encounters anywhere, except the forest tileset
		if not map["connections"].is_empty() or map["tileset"] == "FOREST":
			return
	if rng.randi_range(0, 255) >= rate:
		return
	var r := rng.randi_range(0, 255)
	var slots: Array = wild["grass"]
	var chances: Array = GameData.wild["slot_chances"]
	var slot := 0
	for i in chances.size():
		if int(chances[i]) >= r:
			slot = i
			break
	var entry: Array = slots[mini(slot, slots.size() - 1)]
	battle_request = {"wild": true, "species": str(entry[1]), "level": int(entry[0])}
	if "--trace-battle" in OS.get_cmdline_user_args():
		print("WILD_ENCOUNTER frame=%d at (%d,%d) %s" % [GB.frame_count, player.x, player.y, str(battle_request)])


func _controlled_by_game() -> bool:
	return sim_queue.size() > 0 or follow_script.size() > 0


## JoypadOverworld: real input masked by wJoyIgnore, or the next simulated state.
func _joypad() -> int:
	if sim_queue.size() > 0:
		var v: int = sim_queue.pop_front()
		if sim_queue.is_empty():
			joy_ignore = 0
		return v
	return GB.held & ~joy_ignore


func _handle_direction(held: int) -> void:
	var dir := FACE_DOWN
	var dx := 0
	var dy := 0
	if held & GB.DOWN:
		dir = FACE_DOWN
		dy = 1
	elif held & GB.UP:
		dir = FACE_UP
		dy = -1
	elif held & GB.LEFT:
		dir = FACE_LEFT
		dx = -1
	else:
		dir = FACE_RIGHT
		dx = 1
	player.direction = dir
	var scripted := sim_queue.size() > 0 or follow_script.size() > 0
	if not scripted and player.check_180 and dir != player.last_stop_dir:
		# a new direction only turns the player this frame (BIT_TURNING)
		player.check_180 = false
		player.facing = dir
		player.moving_dir = dir
		return
	player.check_180 = false
	player.facing = dir
	player.moving_dir = dir
	if _collision_on_land(player.x + dx, player.y + dy):
		# collision while standing on a warp: ExtraWarpCheck -> CheckWarpsCollision
		if _is_warp_at(player.x, player.y) and _extra_warp_check():
			await _warp_from(player.x, player.y)
		return
	player.step_dx = dx
	player.step_dy = dy
	player.walk_counter = 8
	_advance_player()


## AdvancePlayerSprite: 2 pixels per frame; the map coordinates update on the last frame.
func _advance_player() -> void:
	player.px += player.step_dx * 2
	player.py += player.step_dy * 2
	player.intra += 1
	if player.intra == 4:
		player.intra = 0
		player.anim = (player.anim + 1) & 3
	player.walk_counter -= 1
	if player.walk_counter == 0:
		player.x += player.step_dx
		player.y += player.step_dy


func _after_step() -> void:
	player.px = (BORDER + player.x * 2) * 8
	player.py = (BORDER + player.y * 2) * 8
	# CheckMapConnections: stepping off the map edge into a connected map
	var w: int = map["width"] * 2
	var h: int = map["height"] * 2
	if player.x < 0 or player.x >= w or player.y < 0 or player.y >= h:
		for c in map["connections"]:
			if not GameData.maps.has(c.map):
				continue
			var other: Dictionary = GameData.maps[c.map]
			var off: int = c.offset
			var dir: String = c.dir
			if (dir == "north" and player.y < 0) or (dir == "south" and player.y >= h) \
					or (dir == "west" and player.x < 0) or (dir == "east" and player.x >= w):
				var nx := player.x
				var ny := player.y
				match dir:
					"north":
						ny = other["height"] * 2 - 1
						nx = player.x - 2 * off
					"south":
						ny = 0
						nx = player.x - 2 * off
					"west":
						nx = other["width"] * 2 - 1
						ny = player.y - 2 * off
					"east":
						nx = 0
						ny = player.y - 2 * off
				var facing := player.facing
				load_map(c.map, nx, ny, facing)
				_enter_map_music(false)
				_next_debug_segment()
				return
	# step counting (not while button presses are simulated), then the poison damage
	if sim_queue.is_empty() and follow_script.is_empty():
		state.step_counter = (state.step_counter - 1) & 0xFF
		if state.encounter_cooldown > 0:
			state.encounter_cooldown -= 1
		if await _apply_poison_step():
			return
	# CheckWarpsNoCollision
	if _is_warp_at(player.x, player.y):
		var tile_id := _tile_id_under(player.x, player.y)
		if tile_id in tileset["warp_tiles"] or tile_id in tileset["door_tiles"]:
			await _warp_from(player.x, player.y)
			return
		# ExtraWarpCheck, then pass through only while a direction is held
		if _extra_warp_check() and _held_after_step() & GB.CTRL_PAD:
			await _warp_from(player.x, player.y)
			return
	# NewBattle → InitBattle → TryDoWildEncounter
	_try_wild_encounter()


func _is_warp_at(x: int, y: int) -> bool:
	for w in map["warps"]:
		if w.x == x and w.y == y:
			return true
	return false


## A warp that is not on a door/warp tile only triggers when the player keeps
## pressing a direction (e.g. walking off the bottom row of a house).
## data/tilesets/warp_carpet_tile_ids.asm, by facing direction.
const WARP_CARPET_TILES := {
	FACE_DOWN: [0x01, 0x12, 0x17, 0x3D, 0x04, 0x18, 0x33],
	FACE_UP: [0x01, 0x5C],
	FACE_LEFT: [0x1A, 0x4B],
	FACE_RIGHT: [0x0F, 0x4E],
}


## ExtraWarpCheck: outdoor-style tilesets (and a few maps) need a warp carpet tile in
## front of the player (IsWarpTileInFrontOfPlayer); the others need the player to
## face the map edge (IsPlayerFacingEdgeOfMap).
func _extra_warp_check() -> bool:
	var function2: bool = map_id in ["ROCKET_HIDEOUT_B1F", "ROCKET_HIDEOUT_B2F", "ROCKET_HIDEOUT_B4F", "ROCK_TUNNEL_1F"] \
			or (map_id != "SS_ANNE_3F" and map["tileset"] in ["OVERWORLD", "SHIP", "SHIP_PORT", "PLATEAU"])
	var d := _facing_delta()
	if function2:
		if map_id == "SS_ANNE_BOW":
			return _tile_id_under(player.x + d.x, player.y + d.y) == 0x15
		return _tile_id_under(player.x + d.x, player.y + d.y) in WARP_CARPET_TILES[player.facing]
	var tx := player.x + d.x
	var ty := player.y + d.y
	return tx < 0 or ty < 0 or tx >= map["width"] * 2 or ty >= map["height"] * 2


## hJoyHeld as CheckWarpsNoCollision reads it right after a step (the simulated or
## test-walk direction counts as held).
func _held_after_step() -> int:
	var held := _joypad()
	if debug_walk.size() > 0 and debug_walk[0] in ["U", "D", "L", "R"]:
		held |= {"U": GB.UP, "D": GB.DOWN, "L": GB.LEFT, "R": GB.RIGHT}[debug_walk[0]]
	return held


# --- collision ---------------------------------------------------------------

## Tile id under the lower-left quadrant of block (x, y).
func _tile_id_under(x: int, y: int) -> int:
	var gx := BORDER + x * 2
	var gy := BORDER + y * 2 + 1
	if gx < 0 or gy < 0 or gx >= grid_w or gy >= grid_h:
		return -1
	return grid_ids[gy * grid_w + gx]


func _is_walkable(x: int, y: int) -> bool:
	var id := _tile_id_under(x, y)
	return id in tileset["collision"]


## CollisionCheckOnLand for the player: map bounds, tile collision and sprites,
## with the collision sound (unless it is already playing on channel 5).
func _collision_on_land(x: int, y: int) -> bool:
	if not _collision_check(x, y):
		return false
	if not Sound.channel5_is("SFX_COLLISION"):
		Sound.play_sfx("SFX_COLLISION")
	return true


## There are no collisions while the game controls the player (simulated joypad).
func _collision_check(x: int, y: int) -> bool:
	if sim_queue.size() > 0 or (follow_script.size() > 0 and follow_script.get("fn", 0) >= 3):
		return false
	# beyond the map the tiles are the border blocks or a connected map's strip
	if not _is_walkable(x, y):
		return true
	# PH-INTENT: chapter boundary. A connection to a map this build does not export yet
	# (e.g. Pewter City east -> Route 3 before chapter 4) is treated as a wall instead of
	# letting the player walk into the border blocks.
	if _leads_to_missing_map(x, y):
		return true
	for n in npcs:
		if n.hidden:
			continue
		if scripted_npc.size() > 0 and scripted_npc.npc == n.index:
			# an NPC walking in lockstep with the player (DoScriptedNPCMovement)
			# only blocks the tile it is moving into
			var d := _scripted_npc_delta()
			if n.x + d.x == x and n.y + d.y == y:
				return true
			continue
		if (n.x == x and n.y == y) or (n.walk_counter > 0 and n.x + n.step_dx == x and n.y + n.step_dy == y):
			return true
	return false


func _leads_to_missing_map(x: int, y: int) -> bool:
	var w: int = map["width"] * 2
	var h: int = map["height"] * 2
	var dir := ""
	if y < 0: dir = "north"
	elif y >= h: dir = "south"
	elif x < 0: dir = "west"
	elif x >= w: dir = "east"
	else:
		return false
	for c in map["connections"]:
		if c.dir == dir:
			return not GameData.maps.has(c.map)
	return false


func _scripted_npc_delta() -> Vector2i:
	if scripted_npc.is_empty() or scripted_npc.idx >= scripted_npc.moves.size():
		return Vector2i.ZERO
	match int(scripted_npc.moves[scripted_npc.idx]):
		NPC_UP: return Vector2i(0, -1)
		NPC_DOWN: return Vector2i(0, 1)
		NPC_LEFT: return Vector2i(-1, 0)
		NPC_RIGHT: return Vector2i(1, 0)
	return Vector2i.ZERO


func _npc_can_walk(n: Dictionary, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= map["width"] * 2 or y >= map["height"] * 2:
		return false
	if not _is_walkable(x, y):
		return false
	if player.x == x and player.y == y:
		return false
	if player.walk_counter > 0 and player.x + player.step_dx == x and player.y + player.step_dy == y:
		return false
	for o in npcs:
		if o == n or o.hidden:
			continue
		if (o.x == x and o.y == y) or (o.walk_counter > 0 and o.x + o.step_dx == x and o.y + o.step_dy == y):
			return false
	# sprites never wander off screen
	var sx := x - player.x
	var sy := y - player.y
	return sx >= -4 and sx <= 4 and sy >= -4 and sy <= 4


# --- map loading -------------------------------------------------------------

func load_map(id: String, x: int, y: int, facing: int) -> void:
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("MAP_LOAD %s (%d,%d) last=%s frame %d" % [id, x, y, state.last_map, GB.frame_count])
	map_id = id
	map = GameData.maps[id]
	tileset = GameData.tilesets[map["tileset"]]
	ts_sheet = tileset["gfx"]
	state.cur_map = id
	Sound.set_map_music(id)   # LoadMapHeader: wMapMusicSoundID / wMapMusicROMBank
	SGB.run("OVERWORLD", {"map": id, "last_map": state.last_map})
	var w: int = map["width"]
	var h: int = map["height"]
	grid_w = w * 4 + BORDER * 2
	grid_h = h * 4 + BORDER * 2
	grid_ids = PackedByteArray()
	grid_ids.resize(grid_w * grid_h)
	# border blocks everywhere first
	for by in range(-3, h + 3):
		for bx in range(-3, w + 3):
			_put_block(bx, by, map["border_block"], tileset)
	# connected maps: three block rows/columns of each neighbour (the `connection` macro:
	# current block = neighbour block + offset)
	for c in map["connections"]:
		if not GameData.maps.has(c.map):
			continue
		var other: Dictionary = GameData.maps[c.map]
		var ots: Dictionary = GameData.tilesets[other["tileset"]]
		var ow: int = other["width"]
		var oh: int = other["height"]
		var off: int = c.offset
		match c.dir:
			"north":
				for by in 3:
					for bx in range(-3, w + 3):
						var obx: int = bx - off
						var oby: int = oh - 3 + by
						if obx >= 0 and obx < ow:
							_put_block(bx, by - 3, other["blocks"][oby * ow + obx], ots)
			"south":
				for by in 3:
					for bx in range(-3, w + 3):
						var obx: int = bx - off
						if obx >= 0 and obx < ow:
							_put_block(bx, h + by, other["blocks"][by * ow + obx], ots)
			"west":
				for bx in 3:
					for by in range(-3, h + 3):
						var oby: int = by - off
						var obx: int = ow - 3 + bx
						if oby >= 0 and oby < oh:
							_put_block(bx - 3, by, other["blocks"][oby * ow + obx], ots)
			"east":
				for bx in 3:
					for by in range(-3, h + 3):
						var oby: int = by - off
						if oby >= 0 and oby < oh:
							_put_block(w + bx, by, other["blocks"][oby * ow + bx], ots)
	for by in h:
		for bx in w:
			_put_block(bx, by, map["blocks"][by * w + bx], tileset)
	# objects (toggleable ones start hidden when their toggle state is OFF)
	npcs.clear()
	var hidden: Array = []
	for t in map.get("toggles", []):
		if not t[1]:
			hidden.append(int(t[0]))
	var i := 0
	for o in map["objects"]:
		var sheet := sprite_sheet(o.sprite)
		var n := {
			"index": i, "x": o.x, "y": o.y, "sprite": sheet,
			"movement": o.movement, "range": o.direction, "text": o.text, "trainer": o.trainer,
			"item": o.trainer if (o.sprite == "SPRITE_POKE_BALL" and o.trainer != "") else "",
			"hidden": i in hidden or state.has_event("HIDE_%s_%d" % [id, i]),
			"facing": _initial_facing(o.direction), "orig_facing": 0,
			"walk_counter": 0, "step_dx": 0, "step_dy": 0, "px": 0, "py": 0, "intra": 0, "anim": 0,
			"delay": rng.randi_range(1, 128), "moves": [], "move_idx": 0, "frames": S.sheet(sheet).rows,
		}
		if state.has_event("SHOW_%s_%d" % [id, i]):
			n.hidden = false
		n.px = (BORDER + n.x * 2) * 8
		n.py = (BORDER + n.y * 2) * 8
		npcs.append(n)
		i += 1
	# player
	player = PlayerState.new()
	player.x = x
	player.y = y
	player.px = (BORDER + x * 2) * 8
	player.py = (BORDER + y * 2) * 8
	player.facing = facing
	state.x = x
	state.y = y
	sim_queue.clear()
	follow_script = {}
	scripted_npc = {}
	joy_ignore = 0
	no_auto_text_box = false
	S.clear_sprites()
	S.row_scx = PackedInt32Array()
	S.win_on = false
	_render()
	if "--dump-grid" in OS.get_cmdline_user_args():
		print("grid %dx%d player px=%d py=%d" % [grid_w, grid_h, player.px, player.py])
		for gy in range(BORDER - 2, BORDER + 20):
			var row := ""
			for gx in range(BORDER - 2, BORDER + 20):
				row += "%02x " % grid_ids[gy * grid_w + gx]
			print("%2d: %s" % [gy, row])
		var vy := player.py - 64
		print("vy=%d ty0=%d scy=%d" % [vy, vy >> 3, vy & 7])
		var bgrow := ""
		for k in 21:
			bgrow += "%d," % (S.bg[k] & 0x3FFF)
		print("bg row0:", bgrow)


func _put_block(bx: int, by: int, block_id: int, ts: Dictionary) -> void:
	var block: Array = ts["blocks"][block_id]
	for ty in 4:
		for tx in 4:
			var gx := BORDER + bx * 4 + tx
			var gy := BORDER + by * 4 + ty
			if gx < 0 or gy < 0 or gx >= grid_w or gy >= grid_h:
				continue
			grid_ids[gy * grid_w + gx] = block[ty * 4 + tx]


func _initial_facing(direction: String) -> int:
	match direction:
		"UP": return FACE_UP
		"LEFT": return FACE_LEFT
		"RIGHT": return FACE_RIGHT
	return FACE_DOWN




# --- warps ---------------------------------------------------------------------

func _warp_from(x: int, y: int) -> void:
	var warp: Dictionary
	var idx := 0
	for i in map["warps"].size():
		var w: Dictionary = map["warps"][i]
		if w.x == x and w.y == y:
			warp = w
			idx = i
			break
	var dest: String = warp.map
	if dest == "LAST_MAP":
		dest = state.last_map
	var dest_map: Dictionary = GameData.maps[dest]
	var dw: Dictionary = dest_map["warps"][warp.warp_id - 1]
	if follow_script.size() > 0:
		# PalletMovementScript_Done: Oak is hidden once the walk to the lab is over
		state.set_event("HIDE_PALLET_TOWN_0")
		state.events.erase("SHOW_PALLET_TOWN_0")
		follow_script = {}
	_play_map_change_sound()
	await Intro.fade_out_to_black()
	await GB.delay3()
	# CheckIfInOutsideMap: the OVERWORLD and PLATEAU tilesets
	var from_outside: bool = map["tileset"] in ["OVERWORLD", "PLATEAU"]
	if from_outside:
		state.last_map = map_id
	load_map(dest, dw.x, dw.y, player.facing)
	state.encounter_cooldown = 3   # EnterMap: three steps without wild battles
	_enter_map_music(false)
	_next_debug_segment()
	S.normal_pals()
	await GB.frame


## PlayMapChangeSound: the door sound when the player stands on the overworld door
## tile ($0b), the "go outside" sound otherwise.
func _play_map_change_sound() -> void:
	var gx := BORDER + player.x * 2
	var gy := BORDER + player.y * 2
	var t := grid_ids[gy * grid_w + gx]
	Sound.play_sfx("SFX_GO_INSIDE" if t == 0x0B else "SFX_GO_OUTSIDE")


## LoadMapData: UpdateMusic6Times, then PlayDefaultMusicFadeOutCurrent unless the
## map music is suppressed (BIT_NO_MAP_MUSIC).
func _enter_map_music(battle_over: bool) -> void:
	if Sound.no_map_music:
		return
	Sound.update_music_6_times()
	Sound.play_default_music_fade_out_current(battle_over)


# --- rendering -----------------------------------------------------------------

func _tick_tile_animation() -> void:
	if map["tileset"] != "OVERWORLD" and map["tileset"] != "DOJO":
		return
	anim_counter1 += 1
	if anim_counter1 < 20:
		return
	if anim_counter1 == 20:
		anim_counter2 = (anim_counter2 + 1) & 7
		if anim_counter2 & 4:
			water_shift = (water_shift + 1) & 7
		else:
			water_shift = (water_shift - 1) & 7
		if map["tileset"] != "OVERWORLD":
			anim_counter1 = 0
		return
	# frame 21: flowers
	anim_counter1 = 0
	var c := anim_counter2 & 3
	flower_frame = 1 if c < 2 else (2 if c == 2 else 3)


func _tile_value(id: int) -> int:
	if map["tileset"] == "OVERWORLD":
		if id == 0x03:
			return S.tile("flower%d" % flower_frame, 0)
		if id == 0x14:
			return S.tile("water_anim", water_shift)
	return S.tile(ts_sheet, id)


func _render() -> void:
	var vx := player.px - 64
	var vy := player.py - 64
	var tx0 := vx >> 3
	var ty0 := vy >> 3
	S.scx = vx & 7
	S.scy = vy & 7
	for j in 19:
		var gy := ty0 + j
		for i in 21:
			var gx := tx0 + i
			var v := GBScreen.BLANK
			if gx >= 0 and gy >= 0 and gx < grid_w and gy < grid_h:
				v = _tile_value(grid_ids[gy * grid_w + gx])
			S.bg[(j & 31) * GBScreen.MAP_W + (i & 31)] = v
	# sprites: player at OAM 0-3, NPC i at 4 + 4i
	_draw_player()
	for n in npcs:
		var base: int = 4 + 4 * n.index
		if n.hidden:
			for k in 4:
				S.set_sprite(base + k, -16, -16, GBScreen.BLANK)
			continue
		var sx: int = n.px - vx
		var sy: int = n.py - vy - 4
		var fr := _frame_for(n.facing, n.anim, n.frames)
		draw_sprite_frame(S, base, n.sprite, fr[0], sx, sy, fr[1])


## CheckSpriteAvailability: an NPC standing on tiles that are not map tiles (a text
## box, a menu) is invisible. Checked every frame while a text box is open, like
## UpdateSprites does with the font loaded.
func _hide_sprites_under_text_boxes() -> void:
	if not in_text or not running:
		return
	var vx := player.px - 64
	var vy := player.py - 64
	# UpdatePlayerSprite .checkIfTextBoxInFrontOfSprite: the player's lower-left tile (8, 9)
	if not _is_map_tile(S.get_bg(8, 9)):
		for k in 4:
			S.set_sprite(k, -16, -16, GBScreen.BLANK)
	for n in npcs:
		if n.hidden:
			continue
		var sx: int = n.px - vx
		var sy: int = n.py - vy - 4
		var col := sx >> 3
		var row := ((sy + 4) & 0xF0) >> 3
		var covered := false
		for dy in 2:
			for dx in 2:
				var tx := col + dx
				var ty := row + dy
				if tx < 0 or ty < 0 or tx >= 20 or ty >= 18:
					continue
				if not _is_map_tile(S.get_bg(tx, ty)):
					covered = true
		if covered:
			var base: int = 4 + 4 * n.index
			for k in 4:
				S.set_sprite(base + k, -16, -16, GBScreen.BLANK)


func _is_map_tile(v: int) -> bool:
	if v == GBScreen.BLANK:
		return true
	var sheet := v >> 16
	if sheet == S.sid(ts_sheet) or sheet == S.sid("water_anim"):
		return true
	for f in range(1, 4):
		if sheet == S.sid("flower%d" % f):
			return true
	return false


func _draw_player() -> void:
	var fr := _frame_for(player.facing, player.anim if player.walk_counter > 0 else 0, 6)
	draw_sprite_frame(S, 0, "spr_red", fr[0], 64, 60, fr[1])


## [frame, xflip] for a facing direction and animation counter (0-3).
static func _frame_for(facing: int, anim: int, frames: int) -> Array:
	if frames == 1:
		return [0, false]
	var stand := 0
	var flip := false
	match facing:
		FACE_UP: stand = 1
		FACE_LEFT: stand = 2
		FACE_RIGHT:
			stand = 2
			flip = true
	if frames < 6 or anim == 0 or anim == 2:
		return [stand, flip]
	var walk := stand + 3
	if anim == 3 and (facing == FACE_DOWN or facing == FACE_UP):
		flip = not flip
	return [walk, flip]


## Draw a 16x16 overworld sprite frame as four 8x8 sprites starting at OAM index.
static func draw_sprite_frame(screen: GBScreen, oam_index: int, sheet: String, frame: int, x: int, y: int, xflip: bool, prio: bool = false) -> void:
	var base := frame * 4
	var order := [0, 1, 2, 3]
	if xflip:
		order = [1, 0, 3, 2]
	for i in 4:
		var dx := (i % 2) * 8
		var dy := (i / 2) * 8
		screen.set_sprite(oam_index + i, x + dx, y + dy, screen.tile(sheet, base + order[i]), 0, xflip, false, prio)


static func draw_player_sprite_static(screen: GBScreen, x: int, y: int, facing: int) -> void:
	var fr := _frame_for(facing, 0, 6)
	draw_sprite_frame(screen, 0, "spr_red", fr[0], x, y, fr[1])


# --- NPCs ------------------------------------------------------------------------

func _update_npcs() -> void:
	_update_follow_script()
	for n in npcs:
		if n.hidden:
			continue
		if scripted_npc.size() > 0 and scripted_npc.npc == n.index:
			continue
		if n.walk_counter > 0:
			n.px += n.step_dx
			n.py += n.step_dy
			n.intra += 1
			if n.intra == 4:
				n.intra = 0
				n.anim = (n.anim + 1) & 3
			n.walk_counter -= 1
			if n.walk_counter == 0:
				n.x += n.step_dx
				n.y += n.step_dy
				n.anim = 0
				n.intra = 0
				if n.moves.size() == 0:
					n.delay = rng.randi_range(0, 127)
					if n.delay == 0:
						n.delay = 256
			continue
		if in_text:
			continue
		if n.moves.size() > 0:
			_npc_scripted_step(n)
			continue
		if n.movement != "WALK":
			continue
		n.delay -= 1
		if n.delay > 0:
			continue
		# pick a random direction within the allowed range
		var dirs: Array
		match n.range:
			"UP_DOWN": dirs = [FACE_UP, FACE_DOWN]
			"LEFT_RIGHT": dirs = [FACE_LEFT, FACE_RIGHT]
			_: dirs = [FACE_DOWN, FACE_UP, FACE_LEFT, FACE_RIGHT]
		var d: int = dirs[rng.randi_range(0, dirs.size() - 1)]
		n.facing = d
		var dx := 0
		var dy := 0
		match d:
			FACE_UP: dy = -1
			FACE_DOWN: dy = 1
			FACE_LEFT: dx = -1
			FACE_RIGHT: dx = 1
		if _npc_can_walk(n, n.x + dx, n.y + dy):
			n.step_dx = dx
			n.step_dy = dy
			n.walk_counter = 16
		else:
			n.delay = rng.randi_range(0, 127)
			if n.delay == 0:
				n.delay = 256


## MoveSprite: a list of NPC_MOVEMENT_* bytes walked one block per 16 frames.
func move_sprite(index: int, moves: Array) -> void:
	var n: Dictionary = npcs[index]
	n.moves = moves.duplicate()
	n.move_idx = 0


func npc_moving(index: int) -> bool:
	var n: Dictionary = npcs[index]
	return n.moves.size() > 0 or n.walk_counter > 0


func _npc_scripted_step(n: Dictionary) -> void:
	if n.move_idx >= n.moves.size():
		n.moves = []
		return
	var m: int = n.moves[n.move_idx]
	n.move_idx += 1
	if m == NPC_CHANGE_FACING:
		n.facing = n.get("change_facing", n.facing)
		return
	var dx := 0
	var dy := 0
	match m:
		NPC_UP:
			dy = -1
			n.facing = FACE_UP
		NPC_DOWN:
			dy = 1
			n.facing = FACE_DOWN
		NPC_LEFT:
			dx = -1
			n.facing = FACE_LEFT
		NPC_RIGHT:
			dx = 1
			n.facing = FACE_RIGHT
	n.step_dx = dx
	n.step_dy = dy
	n.walk_counter = 16
	if n.move_idx >= n.moves.size():
		n.moves = []


func set_npc_facing(index: int, facing: int) -> void:
	npcs[index].facing = facing


func show_object(index: int) -> void:
	npcs[index].hidden = false
	state.set_event("SHOW_%s_%d" % [map_id, index])
	state.events.erase("HIDE_%s_%d" % [map_id, index])


func hide_object(index: int) -> void:
	npcs[index].hidden = true
	state.set_event("HIDE_%s_%d" % [map_id, index])
	state.events.erase("SHOW_%s_%d" % [map_id, index])


## FindPathToPlayer: greedy path from an NPC to (ydist, xdist) away; the larger
## distance is reduced first, ties go to X.
func find_path_to_player(index: int, y_stop_short: int = 1) -> Array:
	var n: Dictionary = npcs[index]
	var ydist: int = absi(player.y - n.y) - y_stop_short
	var xdist: int = absi(player.x - n.x)
	var player_above: bool = player.y < n.y
	var player_left: bool = player.x < n.x
	var path: Array = []
	var yp := 0
	var xp := 0
	while true:
		var d := ydist - yp
		var e := xdist - xp
		if d <= 0 and e <= 0:
			break
		if e > 0 and (d <= 0 or e >= d):
			path.append(NPC_LEFT if player_left else NPC_RIGHT)
			xp += 1
		else:
			path.append(NPC_UP if player_above else NPC_DOWN)
			yp += 1
	return path


## DoScriptedNPCMovement: the NPC moves 2 px per frame together with the player
## (used while following Oak). `moves` are NPC_MOVEMENT_* bytes.
func start_scripted_npc(index: int, moves: Array) -> void:
	scripted_npc = {"npc": index, "moves": moves.duplicate(), "idx": 0, "counter": 8, "intra": 0, "anim": 0}


func _update_follow_script() -> void:
	if scripted_npc.is_empty():
		return
	var n: Dictionary = npcs[scripted_npc.npc]
	if scripted_npc.idx >= scripted_npc.moves.size():
		scripted_npc = {}
		n.anim = 0
		return
	var m: int = scripted_npc.moves[scripted_npc.idx]
	var dx := 0
	var dy := 0
	match m:
		NPC_UP:
			dy = -1
			n.facing = FACE_UP
		NPC_DOWN:
			dy = 1
			n.facing = FACE_DOWN
		NPC_LEFT:
			dx = -1
			n.facing = FACE_LEFT
		NPC_RIGHT:
			dx = 1
			n.facing = FACE_RIGHT
		_:
			scripted_npc.idx += 1
			return
	n.px += dx * 2
	n.py += dy * 2
	scripted_npc.intra += 1
	if scripted_npc.intra == 4:
		scripted_npc.intra = 0
		n.anim = (n.anim + 1) & 3
	scripted_npc.counter -= 1
	if scripted_npc.counter == 0:
		scripted_npc.counter = 8
		scripted_npc.idx += 1
		n.x += dx
		n.y += dy


# --- interaction and text -------------------------------------------------------

func _facing_delta() -> Vector2i:
	match player.facing:
		FACE_UP: return Vector2i(0, -1)
		FACE_LEFT: return Vector2i(-1, 0)
		FACE_RIGHT: return Vector2i(1, 0)
	return Vector2i(0, 1)


func _interact() -> void:
	var d := _facing_delta()
	var tx := player.x + d.x
	var ty := player.y + d.y
	# talking across a counter (tileset counter tiles): the NPC is one tile further
	if _tile_id_under(tx, ty) in tileset.get("counter_tiles", []):
		tx += d.x
		ty += d.y
	for n in npcs:
		if n.hidden or n.walk_counter > 0:
			continue
		if n.x == tx and n.y == ty:
			if n.item != "":
				await _pick_up_item(n)
				return
			await display_text_id(n.text, n.index)
			return
	for b in map["bg_events"]:
		if b.x == tx and b.y == ty:
			await display_text_id(b.text, -1)
			return
	await HiddenEvents.check(self)


## PickUpItem: an item ball on the map.
func _pick_up_item(n: Dictionary) -> void:
	in_text = true
	Menu.message_box()
	await GB.delay3()
	if state.give_item(n.item, 1):
		hide_object(n.index)
		state.set_event("HIDE_%s_%d" % [map_id, n.index])
		Text.ram["wStringBuffer"] = GameData.item_name(n.item)
		await Text.print_text_no_box("_FoundItemText")
		await Sound.text_sound("sound_get_item_1")
	else:
		await Text.print_text_no_box("_NoMoreRoomForItemText")
		await Text.wait_scroll_button(false)
	await Text.hold_text_display_open()
	in_text = false
	_render()
	await GB.frame


## DisplayTextID: the NPC turns to the player, the box is drawn (unless the map
## disables it), the text handler runs, then the box waits for A/B and closes.
func display_text_id(text_id: String, npc_index: int) -> void:
	in_text = true
	do_not_wait_after_text = false
	var saved_facing := {}
	for n in npcs:
		saved_facing[n.index] = n.facing
		n.anim = 0
	if npc_index >= 0:
		var n: Dictionary = npcs[npc_index]
		match player.facing:
			FACE_UP: n.facing = FACE_DOWN
			FACE_DOWN: n.facing = FACE_UP
			FACE_LEFT: n.facing = FACE_RIGHT
			FACE_RIGHT: n.facing = FACE_LEFT
	_render()
	if not no_auto_text_box:
		Menu.message_box()
	await scripts.text(text_id, npc_index)
	if not do_not_wait_after_text:
		await Text.wait_scroll_button(false)
	await Text.hold_text_display_open()
	# CloseTextDisplay
	for n in npcs:
		if saved_facing.has(n.index) and not n.get("keep_facing", false) and not n.get("face_any", false):
			n.facing = saved_facing[n.index]
		n.keep_facing = false
	in_text = false
	_render()
	await GB.frame


## PrintText inside a map text handler (draws the box).
func print_text(label: String) -> void:
	await Text.print_text(label)


## EmotionBubble: a 16x16 bubble above a sprite for 60 frames.
func emotion_bubble(sprite_index: int, which: String) -> void:
	var sheet := "emote_" + which
	var x := 64
	var y := 60
	if sprite_index > 0:
		var n: Dictionary = npcs[sprite_index - 1]
		x = n.px - (player.px - 64)
		y = n.py - (player.py - 64) - 4
	var base := 36
	for i in 4:
		S.set_sprite(base + i, x + (i % 2) * 8, y - 16 + (i / 2) * 8, S.tile(sheet, i))
	await GB.frames(60)
	for i in 4:
		S.set_sprite(base + i, -16, -16, GBScreen.BLANK)
	await GB.frame


## Simulate joypad presses for the player (StartSimulatingJoypadStates).
func simulate(presses: Array) -> void:
	sim_queue = presses.duplicate()
	joy_ignore = GB.BUTTONS | GB.CTRL_PAD


func reload_map_view() -> void:
	S.clear_sprites()
	_render()


# --- start menu ----------------------------------------------------------------

func _start_menu() -> void:
	in_text = true
	Sound.play_sfx("SFX_START_MENU")
	var saved := S.snapshot_bg()
	var has_dex := state.has_event("EVENT_GOT_POKEDEX")
	var ko := GameData.lang == "ko"
	var items: Array = []
	if has_dex:
		items.append("도감" if ko else "POKéDEX")
	items.append("포켓몬" if ko else "POKéMON")
	items.append("도구" if ko else "ITEM")
	items.append(state.player_name)
	items.append("리포트" if ko else "SAVE")
	items.append("설정" if ko else "OPTION")
	items.append("닫기" if ko else "EXIT")
	var option_index := items.size() - 2
	var save_index := items.size() - 3
	var cur := mini(start_menu_item, items.size() - 1)
	while true:
		# RedisplayStartMenu
		Menu.draw_box(10, 0, 8, 14 if has_dex else 12)
		for i in items.size():
			Text.place_string(12, 2 + i * 2, items[i])
		var keys := await Menu.handle_input(11, 2, items.size(), GB.A | GB.B | GB.START, 2, cur)
		cur = Menu.current
		start_menu_item = cur
		Menu.erase_cursor()
		if keys & (GB.B | GB.START) or cur == items.size() - 1:
			break
		if cur == option_index:
			# StartMenu_Option: ClearScreen, DisplayOptionMenu, LoadScreenTilesFromBuffer2
			S.clear_sprites()
			await OptionMenu.run()
			S.restore_bg(saved)
			_render()
			continue
		if cur == save_index:
			# StartMenu_SaveReset: SaveMenu, LoadScreenTilesFromBuffer2, HoldTextDisplayOpen
			state.x = player.x
			state.y = player.y
			state.facing = player.facing
			await SaveGame.save_menu(state)
			S.restore_bg(saved)
			_render()
			await Text.hold_text_display_open()
			break
		var base := 1 if has_dex else 0
		if has_dex and cur == 0:
			# StartMenu_Pokedex
			S.clear_sprites()
			await PokedexMenu.show(state)
			_restore_after_screen(saved)
			continue
		if cur == base:
			# StartMenu_Pokemon
			if state.party.is_empty():
				continue
			S.clear_sprites()
			await PartyMenu.start_menu_pokemon(state, self)
			_restore_after_screen(saved)
			continue
		if cur == base + 1:
			# StartMenu_Item
			var close_menu: bool = await Bag.show(state, self)
			_restore_after_screen(saved)
			if close_menu:
				break
			continue
		if cur == base + 2:
			# StartMenu_TrainerInfo
			S.clear_sprites()
			await TrainerCard.show(state)
			_restore_after_screen(saved)
			continue
	S.restore_bg(saved)
	in_text = false
	_render()
	await GB.frame


## LoadScreenTilesFromBuffer2 + ReloadMapData after a full-screen menu.
func _restore_after_screen(saved: PackedInt32Array) -> void:
	S.clear_sprites()
	S.restore_bg(saved)
	SGB.run("DEFAULT")
	S.normal_pals()
	_render()


## Place an object on a map square (SetSpritePosition1 / the sprite position restores
## of map scripts): map coordinates and the matching pixel position.
func set_npc_position(index: int, x: int, y: int) -> void:
	var n: Dictionary = npcs[index]
	n.x = x
	n.y = y
	n.px = (BORDER + x * 2) * 8
	n.py = (BORDER + y * 2) * 8
	n.walk_counter = 0
	n.moves = []
	n.move_idx = 0

## Entry point: runs the game flow and the debug options.
##
## Command line:
##   --stage=splash|intro|title|oak|overworld|lab|battle   start at a stage
##   --shot=<path>                                           save a screenshot every 60 frames
##   --smoke-test                                            load data and quit
extends Node2D

var stage := "splash"
var shot_path := ""
var shot_every := 60
var quit_after := 0
var keys_script := ""   # "frame:key,frame:key" injected presses for tests
var audio_out := "audio_test.wav"


var border: Sprite2D


func _ready() -> void:
	GB.screen = $Screen/View/GBScreen
	GB.set_palette_name(GB.palette_name)
	RenderingServer.set_default_clear_color(Color.BLACK)
	border = Sprite2D.new()
	border.texture = load("res://assets/gb/sgb_border.png")
	border.centered = false
	border.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	border.z_index = -1
	add_child(border)
	get_tree().root.size_changed.connect(_layout)
	Settings.changed.connect(_layout)
	_layout()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stage="):
			stage = arg.get_slice("=", 1)
		elif arg.begins_with("--shot="):
			shot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--shot-every="):
			shot_every = int(arg.get_slice("=", 1))
		elif arg.begins_with("--quit-after="):
			quit_after = int(arg.get_slice("=", 1))
		elif arg.begins_with("--keys="):
			keys_script = arg.get_slice("=", 1)
		elif arg == "--fast":
			GB.speed = 8.0
		elif arg.begins_with("--palette="):
			Settings.palette = arg.get_slice("=", 1)
			Settings.apply_all()
		elif arg == "--smoke-test":
			print("SMOKE_TEST=PASS maps=%d pokemon=%d" % [GameData.maps.size(), GameData.pokemon.size()])
			get_tree().quit()
			return
		elif arg.begins_with("--overlay-shot="):
			_overlay_shot(arg.get_slice("=", 1), true)
		elif arg.begins_with("--window-shot="):
			_overlay_shot(arg.get_slice("=", 1), false)
		elif arg.begins_with("--audio-out="):
			audio_out = arg.get_slice("=", 1)
		elif arg.begins_with("--audio-test="):
			_audio_test(arg.get_slice("=", 1))
			get_tree().quit()
			return
	if keys_script != "":
		GB.load_key_script(keys_script)
	if shot_path != "":
		_screenshot_loop()
	if quit_after > 0:
		_quit_loop()
	_run()


## --overlay-shot=path: open the settings overlay after 30 frames and save the window.
func _overlay_shot(path: String, open_overlay: bool) -> void:
	await GB.frames(30)
	if open_overlay:
		Settings.overlay.open()
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("OVERLAY_SHOT ", path)
	get_tree().quit()


## Integer-scale the 160x144 Game Boy screen to the largest factor that fits the
## window and centre it (black borders in fullscreen).
func _layout() -> void:
	var size: Vector2 = get_viewport().get_visible_rect().size
	var avail := Vector2(size.x, size.y - EngineMenuBar.HEIGHT)
	var bordered := Settings.palette == "sgb"
	var base := Vector2(Settings.base_size())
	var k := maxi(1, int(floor(minf(avail.x / base.x, avail.y / base.y))))
	var origin := ((avail - base * k) / 2.0).floor() + Vector2(0, EngineMenuBar.HEIGHT)
	var screen: SubViewportContainer = $Screen
	screen.scale = Vector2(k, k)
	screen.position = origin + (Vector2(48, 40) * k if bordered else Vector2.ZERO)
	if border:
		border.visible = bordered
		border.scale = Vector2(k, k)
		border.position = origin


## --audio-test=music|sfx|cry:NAME:frames[:solo] with --audio-out=path.wav — render the
## sound engine offline (one engine frame = 549 samples at 32768 Hz) into a 16-bit stereo
## WAV; solo 1-4 keeps only that hardware channel audible.
func _audio_test(spec: String) -> void:
	var parts := spec.split(":")
	var kind := parts[0]
	var name := parts[1]
	var frames := int(parts[2])
	var solo := int(parts[3]) if parts.size() > 3 else 0
	match kind:
		"music":
			Sound.play_music(name)
		"sfx":
			Sound.set_audio_bank(Sound._bank(name))
			Sound.play_sfx(name)
		"cry":
			Sound.set_audio_bank(1)
			Sound.play_cry(name)
	var bytes := PackedByteArray()
	bytes.resize(frames * 549 * 4)
	var pos := 0
	for i in frames:
		Sound.vblank()
		if solo > 0:
			var mask := 0x11 << (solo - 1)
			Sound.apu.nr51 &= mask
		var buf := Sound.apu.generate(549)
		for s in buf:
			bytes.encode_s16(pos, int(clampf(s.x, -1.0, 1.0) * 32767.0))
			bytes.encode_s16(pos + 2, int(clampf(s.y, -1.0, 1.0) * 32767.0))
			pos += 4
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = GBApu.RATE
	wav.data = bytes
	var err := wav.save_to_wav(audio_out)
	print("AUDIO_TEST %s -> %s (%d) sfx_still_playing=%s" % [spec, audio_out, err, Sound.sfx_playing()])


func _screenshot_loop() -> void:
	var n := 0
	while true:
		await GB.frames(shot_every)
		n += 1
		await GB.screenshot(shot_path.replace("%d", "%03d" % n))


func _quit_loop() -> void:
	await GB.frames(quit_after)
	print("QUIT_AFTER_FRAMES")
	get_tree().quit()


func _run() -> void:
	var state := GameState.new()
	if stage == "splash":
		await Splash.new().run()
		stage = "intro"
	if stage == "intro":
		await Intro.new().run()
		stage = "title"
	if stage == "title":
		var title := Title.new()
		await title.run()
		if title.choice == "continue":
			state = SaveGame.read()
			state.facing = 0   # PLAYER_DIR_DOWN
			stage = "overworld"
		else:
			stage = "oak"
	if stage == "oak":
		await OakSpeech.new(state).run()
		stage = "overworld"
	if stage.begins_with("map:"):
		var parts := stage.substr(4).split(",")
		state.cur_map = parts[0]
		state.x = int(parts[1])
		state.y = int(parts[2])
		state.facing = 0
		state.starter = "BULBASAUR"
		state.rival_starter = "CHARMANDER"
		var party_spec := "BULBASAUR:5"
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--party="):
				party_spec = arg.get_slice("=", 1)
		state.party = _parse_party(party_spec)
		for e in ["EVENT_OAK_APPEARED_IN_PALLET", "EVENT_FOLLOWED_OAK_INTO_LAB", "EVENT_FOLLOWED_OAK_INTO_LAB_2",
				"EVENT_OAK_ASKED_TO_CHOOSE_MON", "EVENT_GOT_STARTER", "EVENT_BATTLED_RIVAL_IN_OAKS_LAB", "HIDE_PALLET_TOWN_0", "HIDE_OAKS_LAB_0"]:
			state.set_event(e)
		state.map_scripts["OAKS_LAB"] = 18
		state.map_scripts["PALLET_TOWN"] = 5   # SCRIPT_PALLETTOWN_DAISY
		# test helpers: --give=ITEM:qty,... --event=EVENT_A,EVENT_B --script=MAP:index
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--give="):
				for spec in arg.get_slice("=", 1).split(","):
					state.give_item(spec.get_slice(":", 0), int(spec.get_slice(":", 1)) if spec.contains(":") else 1)
			elif arg.begins_with("--event="):
				for e in arg.get_slice("=", 1).split(","):
					state.set_event(e)
			elif arg.begins_with("--teach="):
				# test: moves added to the first party mon (the oldest one is dropped at four)
				for mv in arg.get_slice("=", 1).split(","):
					var m0: PartyMon = state.party[0]
					if m0.moves.size() >= 4:
						m0.moves.pop_front()
					m0.moves.append({"move": mv, "pp": GameData.moves[mv]["pp"], "max_pp": GameData.moves[mv]["pp"]})
			elif arg.begins_with("--visited="):
				for m in arg.get_slice("=", 1).split(","):
					state.town_visited.append(m)
			elif arg.begins_with("--badges="):
				state.badges = int(arg.get_slice("=", 1))
			elif arg.begins_with("--repel="):
				state.repel_steps = int(arg.get_slice("=", 1))
			elif arg.begins_with("--script="):
				var spec := arg.get_slice("=", 1)
				state.map_scripts[spec.get_slice(":", 0)] = int(spec.get_slice(":", 1))
			elif arg.begins_with("--last-map="):
				state.last_map = arg.get_slice("=", 1)   # wLastMap (the LAST_MAP warps of indoor maps)
			elif arg == "--trade-mon":
				# test: the first party mon came from a trade (another OT)
				state.party[0].ot_name = "TRAINER"
				state.party[0].ot_id = 12345
			elif arg.begins_with("--owned="):
				# test: the first N species (by dex number) count as owned (Oak's aides)
				var n := int(arg.get_slice("=", 1))
				for sp in GameData.pokemon:
					if int(GameData.pokemon[sp]["dex"]) <= n:
						state.pokedex_owned[sp] = true
						state.pokedex_seen[sp] = true
		state.last_map = "PALLET_TOWN" if parts[0].begins_with("VIRIDIAN") or parts[0] == "ROUTE_1" else state.last_map
		if parts[0].begins_with("VIRIDIAN_") and parts[0] != "VIRIDIAN_CITY":
			state.last_map = "VIRIDIAN_CITY"
		stage = "overworld"
	if stage == "lab":
		state.cur_map = "OAKS_LAB"
		state.x = 5
		state.y = 11
		state.facing = 4
		state.set_event("EVENT_OAK_APPEARED_IN_PALLET")
		state.last_map = "PALLET_TOWN"
		stage = "overworld"
	if stage == "battle":
		# test helpers: --party=SPECIES:LEVEL,... (default BULBASAUR:5), --give=ITEM:qty,...
		# --wild=SPECIES:LEVEL (a wild battle), --trainer=CLASS:team (a trainer battle),
		# --old-man (the catch demonstration); default: the Oak's Lab rival battle
		state.starter = "BULBASAUR"
		state.rival_starter = "CHARMANDER"
		state.cur_map = "ROUTE_1"
		var req := {"trainer": "RIVAL1", "name": state.rival_name, "party": [{"species": "CHARMANDER", "level": 5}],
			"win_text": "_OaksLabRivalIPickedTheWrongPokemonText"}
		var party_spec := "BULBASAUR:5"
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--party="):
				party_spec = arg.get_slice("=", 1)
			elif arg.begins_with("--give="):
				for spec in arg.get_slice("=", 1).split(","):
					state.give_item(spec.get_slice(":", 0), int(spec.get_slice(":", 1)) if spec.contains(":") else 1)
			elif arg.begins_with("--wild="):
				var spec := arg.get_slice("=", 1)
				req = {"wild": true, "species": spec.get_slice(":", 0), "level": int(spec.get_slice(":", 1))}
			elif arg.begins_with("--trainer="):
				var spec := arg.get_slice("=", 1)
				req = {"trainer": spec.get_slice(":", 0), "team": int(spec.get_slice(":", 1)),
					"name": state.rival_name, "win_text": "_Route22Rival1DefeatedText"}
			elif arg == "--old-man":
				req = {"type": "old_man", "species": "WEEDLE", "level": 5}
		state.party = _parse_party(party_spec)
		state.pokedex_owned[state.party[0].species] = true
		state.pokedex_seen[state.party[0].species] = true
		GB.screen.normal_pals()
		var battle_result: String = await Battle.new(state, req).run()
		print("BATTLE_DONE result=%s party=%d box=%d money=%d" % [battle_result, state.party.size(), state.box.size(), state.money])
		for m in state.party:
			print("  %s L%d hp=%d/%d exp=%d status=%d moves=%s" % [m.species, m.level, m.hp, m.max_hp, m.exp, m.status, str(m.moves)])
		get_tree().quit()
		return
	if stage == "overworld":
		var ow := Overworld.new(state)
		while true:
			await ow.run()
			if ow.battle_request.is_empty():
				break
			var req := ow.battle_request
			ow.battle_request = {}
			var battle_result: String = await Battle.new(state, req).run()
			await ow.after_battle(battle_result)
	print("GAME_FLOW_END")


## Test party spec: SPECIES:LEVEL[:STATUS[:EXTRA_EXP[:HP]]],... (STATUS = PSN/BRN/PAR/FRZ/SLP).
static func _parse_party(spec: String) -> Array:
	var party: Array = []
	for entry in spec.split(","):
		var fields := entry.split(":")
		var mon := PartyMon.create(fields[0], int(fields[1]))
		if fields.size() > 2:
			mon.status = {"PSN": PartyMon.PSN, "BRN": PartyMon.BRN, "PAR": PartyMon.PAR, "FRZ": PartyMon.FRZ, "SLP": 3}.get(fields[2], 0)
		if fields.size() > 3:
			mon.exp += int(fields[3])
		if fields.size() > 4 and fields[4] != "":
			mon.hp = clampi(int(fields[4]), 0, mon.max_hp)
		party.append(mon)
	return party

## Chapter 7 map scripts and text handlers: Routes 7 and 8 and their Saffron City gates
## (scripts/Route7Gate.asm, Route8Gate.asm; the routes themselves only have trainers),
## the Underground Path between them (UndergroundPathRoute7.asm, UndergroundPathRoute8.asm,
## UndergroundPathWestEast.asm) and Celadon City in its own file (CeladonScripts).
## Maps with only trainer headers need no code here (TrainerEngine handles them).
class_name Chapter7Scripts
extends RefCounted

var ms: MapScripts
var ow: Overworld
var state: GameState
var celadon: CeladonScripts            # Celadon City and its buildings
var game_corner: GameCornerScripts     # the Game Corner and the prize room
var hideout: RocketHideoutScripts      # the Rocket Hideout
var entered_map := ""


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state
	celadon = CeladonScripts.new(self)
	game_corner = GameCornerScripts.new(self)
	hideout = RocketHideoutScripts.new(self)


## The per-frame map script of the chapter 7 maps (see MtMoonScripts.run_map_script).
func run_map_script() -> bool:
	var entered := entered_map != ow.map_id
	entered_map = ow.map_id
	match ow.map_id:
		"ROUTE_7_GATE":
			await _gate(7)
			return true
		"ROUTE_8_GATE":
			await _gate(8)
			return true
		"UNDERGROUND_PATH_ROUTE_7":
			state.last_map = "ROUTE_7"   # the LAST_MAP warps lead back to Route 7
			return true
		"UNDERGROUND_PATH_ROUTE_8":
			state.last_map = "ROUTE_8"
			return true
		_:
			if await celadon.run_map_script(entered):
				return true
			if await game_corner.run_map_script(entered):
				return true
			return await hideout.run_map_script(entered)


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		# the Saffron gate guards share the Route 5/6 texts (SaffronGateGuardText...)
		"TEXT_ROUTE7GATE_GUARD", "TEXT_ROUTE8GATE_GUARD": await ms.ch5.route56._guard_text()
		"TEXT_ROUTE7GATE_GUARD_GEE_IM_THIRSTY", "TEXT_ROUTE8GATE_GUARD_GEE_IM_THIRSTY":
			await ow.print_text("_SaffronGateGuardGeeImThirstyText")
		"TEXT_ROUTE7GATE_GUARD_GIVE_DRINK", "TEXT_ROUTE8GATE_GUARD_GIVE_DRINK":
			await ms.ch5.route56._give_drink_text()
		_:
			if await celadon.text(text_id, npc_index):
				return true
			if await game_corner.text(text_id, npc_index):
				return true
			return await hideout.text(text_id, npc_index)
	return true


## Route7DefaultScript / Route8GateDefaultScript and the *PlayerMovingScript: the guard
## stops the player on the two tiles in front of the Saffron door; without a drink the
## player is walked back (left on Route 7, right on Route 8).
func _gate(route: int) -> void:
	var route56: Route56Scripts = ms.ch5.route56
	match ms._script_index():
		0:
			if state.has_event(Route56Scripts.GAVE_DRINK):
				return
			var coords: Array = [Vector2i(3, 3), Vector2i(3, 4)] if route == 7 else [Vector2i(2, 3), Vector2i(2, 4)]
			if not Vector2i(ow.player.x, ow.player.y) in coords:
				return
			# wPlayerMovingDirection: PLAYER_DIR_UP (Route 7) / PLAYER_DIR_LEFT (Route 8)
			ow.player.facing = Overworld.FACE_UP if route == 7 else Overworld.FACE_LEFT
			var drink := route56._remove_guard_drink()
			if drink == "":
				await ow.display_text_id("TEXT_ROUTE%dGATE_GUARD_GEE_IM_THIRSTY" % route, -1)
				# Route7GateMovePlayerLeftScript / Route8GateMovePlayerRightScript
				ow.simulate([GB.LEFT if route == 7 else GB.RIGHT])
				ms._set_script(1)
			else:
				trace("GUARD_DRINK item=%s" % drink)
				if route == 8:   # Route 8 sets the flag before the text, Route 7 after it
					state.set_event(Route56Scripts.GAVE_DRINK)
				await ow.display_text_id("TEXT_ROUTE%dGATE_GUARD_GIVE_DRINK" % route, -1)
				state.set_event(Route56Scripts.GAVE_DRINK)
		1:
			if not ow.sim_queue.is_empty():
				return
			await GB.delay3()
			ow.joy_ignore = 0
			ms._set_script(0)


## EngageMapTrainer / SaveEndBattleTextPointers for non-header event opponents
## (the same as MtMoonScripts.event_battle).
func event_battle(npc_index: int, post: int, win: String, lose: String = "", gym: int = 0) -> void:
	ms.trainers.header = {}
	ms.trainers._engage_map_trainer(npc_index + 1)
	ow.battle_request = {"trainer": ms.trainers.engaged_class, "team": ms.trainers.engaged_set,
		"win_text": win, "lose_text": lose if lose != "" else win}
	if gym > 0:
		ow.battle_request["gym_leader"] = gym
	ms._set_script(post)


func trace(message: String) -> void:
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("CHAPTER7 %s frame=%d" % [message, GB.frame_count])

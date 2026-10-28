## Chapter 5 map scripts and text handlers: Route 9, Route 10 and the Rock Tunnel
## Pokémon Center (scripts/Route9.asm, Route10.asm, RockTunnelPokecenter.asm), then
## Routes 5/6, the Underground Path and Vermilion City in their own files.
## Maps with only trainer headers need no code here (TrainerEngine handles them).
class_name Chapter5Scripts
extends RefCounted

var ms: MapScripts
var ow: Overworld
var state: GameState
var route56: Route56Scripts   # Routes 5/6, their gates, the Underground Path, the Daycare
var vermilion: VermilionScripts   # Vermilion City and its buildings
var ss_anne: SSAnneScripts        # the S.S. Anne
var entered_map := ""


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state
	route56 = Route56Scripts.new(self)
	vermilion = VermilionScripts.new(self)
	ss_anne = SSAnneScripts.new(self)


## The per-frame map script of the chapter 5 maps (see MtMoonScripts.run_map_script).
func run_map_script() -> bool:
	var entered := entered_map != ow.map_id
	entered_map = ow.map_id
	match ow.map_id:
		"ROUTE_5_GATE", "ROUTE_6_GATE", "UNDERGROUND_PATH_ROUTE_5", "UNDERGROUND_PATH_ROUTE_6":
			return await route56.run_map_script(entered)
		"VERMILION_CITY", "VERMILION_DOCK", "VERMILION_GYM":
			return await vermilion.run_map_script(entered)
		"SS_ANNE_2F", "SS_ANNE_2F_ROOMS", "SS_ANNE_CAPTAINS_ROOM":
			return await ss_anne.run_map_script(entered)
		_:
			return false


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		"TEXT_ROCKTUNNELPOKECENTER_NURSE": await Pokecenter.nurse(ow, npc_index)
		"TEXT_ROCKTUNNELPOKECENTER_LINK_RECEPTIONIST": await ow.print_text("_CableClubNPCWelcomeText")
		"TEXT_ROUTE10_POKECENTER_SIGN": await ms._far("_PokeCenterSignText")
		_:
			if await route56.text(text_id, npc_index):
				return true
			if await vermilion.text(text_id, npc_index):
				return true
			return await ss_anne.text(text_id, npc_index)
	return true


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
		print("CHAPTER5 %s frame=%d" % [message, GB.frame_count])

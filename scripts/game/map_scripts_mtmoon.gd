## Chapter 4 map scripts and text handlers: Route 3, the Mt. Moon Pokémon Center,
## Mt. Moon 1F/B1F/B2F and Route 4 (scripts/Route3.asm, MtMoonPokecenter.asm,
## MtMoon1F.asm, MtMoonB1F.asm, MtMoonB2F.asm, Route4.asm).
## Maps with only trainer headers need no code here (TrainerEngine handles them).
class_name MtMoonScripts
extends RefCounted

var ms: MapScripts
var ow: Overworld
var state: GameState


func _init(m: MapScripts) -> void:
	ms = m
	ow = m.ow
	state = m.state


## The per-frame map script of the chapter 4 maps (called for maps map_scripts.gd
## does not handle itself, before the generic trainer table).
func run_map_script() -> void:
	match ow.map_id:
		_:
			pass


## The map text handlers; returns false when `text_id` is not one of them.
func text(text_id: String, npc_index: int) -> bool:
	match text_id:
		_:
			return false

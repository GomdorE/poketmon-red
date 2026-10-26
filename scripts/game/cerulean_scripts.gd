## Chapter 4 city and indoor scripts (original scripts/Cerulean*.asm).
class_name CeruleanScripts
extends RefCounted

var chapter: MtMoonScripts
var ms: MapScripts
var ow: Overworld
var state: GameState

func _init(c: MtMoonScripts) -> void:
	chapter = c
	ms = c.ms
	ow = c.ow
	state = c.state

func run_map_script(_entered: bool) -> bool:
	return false

func text(_text_id: String, _npc_index: int) -> bool:
	return false

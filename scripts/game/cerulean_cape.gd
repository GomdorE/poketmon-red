## Chapter 4 Nugget Bridge and Bill scripts (scripts/Route24, Route25, BillsHouse).
class_name CeruleanCapeScripts
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

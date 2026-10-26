## Loads the JSON data exported from the disassembly. Autoloaded as `GameData`.
extends Node

var charmap := {}
var text_ko := {}
var text_en := {}
var maps := {}
var tilesets := {}
var pokemon := {}
var moves := {}
var types := {}
var lang := "ko"
var items := {}
var wild := {}
var battle_anims := {}   # tools/export_battle_anims.py
var marts := {}
var trainers := {}
var _text_index := {}


## The far-text label of a map text id by naming convention
## (TEXT_VIRIDIANCITY_YOUNGSTER1 -> _ViridianCityYoungster1Text).
func text_label_for(text_id: String) -> String:
	var key := text_id.trim_prefix("TEXT_").to_lower().replace("_", "") + "text"
	return _text_index.get(key, "")


func item_name(item: String) -> String:
	if items.has(item):
		var it: Dictionary = items[item]
		return it["name_ko"] if lang == "ko" else it["name_en"]
	if item.begins_with("TM") or item.begins_with("HM"):
		return item
	return item


func trainer_class_name(cls: String) -> String:
	var t: Dictionary = trainers[cls]
	return t["name_ko"] if lang == "ko" else t["name_en"]


func _ready() -> void:
	charmap = _load("charmap")
	text_ko = _load("text_ko")
	text_en = _load("text_en")
	maps = _load("maps")
	tilesets = _load("tilesets")
	pokemon = _load("pokemon")
	moves = _load("moves")
	types = _load("types")
	items = _load("items")
	wild = _load("wild")
	battle_anims = _load("battle_anims")
	marts = _load("marts")
	trainers = _load("trainers")
	for label in text_en.keys():
		_text_index[label.to_lower().replace("_", "")] = label
	for label in text_ko.keys():
		_text_index[label.to_lower().replace("_", "")] = label


func _load(name: String) -> Dictionary:
	var path := "res://assets/data/%s.json" % name
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "missing data file: " + path)
	var parsed = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "bad json: " + path)
	return _intify(parsed)


## JSON numbers arrive as floats; Array.has(int) then fails against them, so
## every whole number is converted back to int.
static func _intify(v: Variant) -> Variant:
	if v is float:
		return int(v) if v == floor(v) else v
	if v is Array:
		var out: Array = []
		for e in v:
			out.append(_intify(e))
		return out
	if v is Dictionary:
		var out := {}
		for k in v.keys():
			out[k] = _intify(v[k])
		return out
	return v


## Text commands for a label, preferring the Korean fork.
func text(label: String) -> Array:
	if lang == "ko" and text_ko.has(label):
		return text_ko[label]
	if text_en.has(label):
		return text_en[label]
	push_warning("missing text label: " + label)
	return [["text", label], ["done", ""]]


func mon_name(mon: String) -> String:
	var p: Dictionary = pokemon[mon]
	return p["name_ko"] if lang == "ko" else p["name_en"]


func move_name(move: String) -> String:
	var m: Dictionary = moves[move]
	return m["name_ko"] if lang == "ko" else m["name_en"]


func type_name(t: String) -> String:
	var key := t.replace("PSYCHIC_TYPE", "PSYCHIC")
	var names: Dictionary = types["names_ko"] if lang == "ko" else types["names_en"]
	return names.get(key, key)

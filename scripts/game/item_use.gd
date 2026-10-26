## Item effect tables and the medicine rules of ItemUseMedicine
## (engine/items/item_effects.asm). Pure helpers; the screens that call them do
## the drawing, sounds and messages.
class_name ItemUse
extends RefCounted

const BALLS := ["POKE_BALL", "GREAT_BALL", "ULTRA_BALL", "MASTER_BALL", "SAFARI_BALL"]
const HEAL_HP := {"POTION": 20, "SUPER_POTION": 50, "HYPER_POTION": 200, "MAX_POTION": -1, "FULL_RESTORE": -1,
	"FRESH_WATER": 50, "SODA_POP": 60, "LEMONADE": 80}
const CURE := {"ANTIDOTE": "PSN", "BURN_HEAL": "BRN", "ICE_HEAL": "FRZ", "AWAKENING": "SLP", "PARLYZ_HEAL": "PAR",
	"FULL_HEAL": "ALL", "FULL_RESTORE": "ALL"}
const CURE_MESSAGE := {"PSN": "_AntidoteText", "BRN": "_BurnHealText", "FRZ": "_IceHealText", "SLP": "_AwakeningText",
	"PAR": "_ParlyzHealText", "ALL": "_FullHealText"}


## {"hp": 20/50/200, -1 for a full heal, 0 for none; "cure": "PSN".."PAR"/"ALL"/""; "revive": bool}
static func medicine(item: String) -> Dictionary:
	return {"hp": int(HEAL_HP.get(item, 0)), "cure": str(CURE.get(item, "")),
		"revive": item == "REVIVE" or item == "MAX_REVIVE"}


static func is_medicine(item: String) -> bool:
	return HEAL_HP.has(item) or CURE.has(item) or item == "REVIVE" or item == "MAX_REVIVE"


static func is_ball(item: String) -> bool:
	return item in BALLS


## Status bits an item cures (SLP_MASK for Awakening, $ff for Full Heal).
static func _cure_mask(cure: String) -> int:
	match cure:
		"PSN": return PartyMon.PSN
		"BRN": return PartyMon.BRN
		"FRZ": return PartyMon.FRZ
		"SLP": return PartyMon.SLP_MASK
		"PAR": return PartyMon.PAR
		"ALL": return 0xFF
	return 0


## ItemUseMedicine on one mon. Returns {"ok", "old_hp", "new_hp", "cured", "message"}:
## `ok` false means "It won't have any effect."; `cured` true means a status cure
## (SFX_HEAL_AILMENT, no HP bar animation). Sets Text.ram for the message.
static func apply_medicine(mon: PartyMon, item: String) -> Dictionary:
	var m := medicine(item)
	var res := {"ok": false, "old_hp": mon.hp, "new_hp": mon.hp, "cured": false, "message": ""}
	Text.ram["wNameBuffer"] = mon.nickname
	if m.revive:
		if mon.hp > 0:
			return res
		mon.hp = mon.max_hp / 2 if item == "REVIVE" else mon.max_hp
		mon.status = 0
		res.new_hp = mon.hp
		res.ok = true
		res.message = "_ReviveText"
		Text.ram["wHPBarHPDifference"] = mon.hp
		return res
	if m.hp != 0:
		if mon.hp <= 0:
			return res
		if mon.hp >= mon.max_hp:
			# a Full Restore at full HP acts as a Full Heal
			if item == "FULL_RESTORE" and mon.status != 0:
				mon.status = 0
				res.ok = true
				res.cured = true
				res.message = "_FullHealText"
			return res
		var new_hp := mon.max_hp if m.hp < 0 else mini(mon.max_hp, mon.hp + m.hp)
		mon.hp = new_hp
		if item == "FULL_RESTORE":
			mon.status = 0
		res.new_hp = new_hp
		res.ok = true
		res.message = "_PotionText"
		Text.ram["wHPBarHPDifference"] = new_hp - int(res.old_hp)
		return res
	if m.cure != "":
		if (mon.status & _cure_mask(m.cure)) == 0:
			return res
		mon.status = 0
		res.ok = true
		res.cured = true
		res.message = CURE_MESSAGE[m.cure]
	return res

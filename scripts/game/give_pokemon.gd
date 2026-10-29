## _GivePokemon (engine/events/give_pokemon.asm): a gift Pokémon goes to the party, or to
## the current box when the party is full ("<MON> was transferred to BOX n"); nothing is
## given when the box is full too. Returns true when the Pokémon was received.
class_name GivePokemon
extends RefCounted


static func give(ow: Overworld, species: String, level: int) -> bool:
	var state: GameState = ow.state
	if state.party.size() >= 6 and state.box.size() >= 20:
		await ow.print_text("_BoxIsFullText")
		return false
	var mon := PartyMon.create(species, level)
	# SetPokedexOwnedFlag + GotMonText
	state.pokedex_owned[species] = true
	state.pokedex_seen[species] = true
	Text.ram["wNameBuffer"] = GameData.mon_name(species)
	await ow.print_text("_GotMonText")
	await Sound.text_sound("sound_get_item_1")
	if state.party.size() < 6:
		state.party.append(mon)   # AddPartyMon
		ow.do_not_wait_after_text = true
		return true
	# SendNewMonToBox, then "transferred to BOX n"
	state.box.push_front(mon)
	Text.ram["wBoxMonNicks"] = mon.nickname
	Text.ram["wStringBuffer"] = str(state.current_box + 1)
	await ow.print_text("_SentToBoxText")
	return true

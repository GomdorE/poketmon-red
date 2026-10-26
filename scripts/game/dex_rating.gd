## DisplayDexRating (engine/events/pokedex_rating.asm) with PlayPokedexRatingSfx
## (audio/pokedex_rating_sfx.asm): Oak's completion summary, the rating text for the
## number of owned species, a jingle, then the map music resumes.
class_name DexRating
extends RefCounted

## DexRatingsTable: owned count upper bound (exclusive) -> text label.
const RATINGS := [
	[10, "_DexRatingText_Own0To9"], [20, "_DexRatingText_Own10To19"], [30, "_DexRatingText_Own20To29"],
	[40, "_DexRatingText_Own30To39"], [50, "_DexRatingText_Own40To49"], [60, "_DexRatingText_Own50To59"],
	[70, "_DexRatingText_Own60To69"], [80, "_DexRatingText_Own70To79"], [90, "_DexRatingText_Own80To89"],
	[100, "_DexRatingText_Own90To99"], [110, "_DexRatingText_Own100To109"], [120, "_DexRatingText_Own110To119"],
	[130, "_DexRatingText_Own120To129"], [140, "_DexRatingText_Own130To139"], [150, "_DexRatingText_Own140To149"],
	[152, "_DexRatingText_Own150To151"],
]
## OwnedMonValues -> PokedexRatingSfxPointers
const SFX_LIMITS := [10, 40, 60, 90, 120, 150, 256]
const SFX_NAMES := ["SFX_DENIED", "SFX_POKEDEX_RATING", "SFX_GET_ITEM_1", "SFX_CAUGHT_MON", "SFX_LEVEL_UP", "SFX_GET_KEY_ITEM", "SFX_GET_ITEM_2"]


static func display(state: GameState) -> void:
	var seen := state.pokedex_seen.size()
	var owned := state.pokedex_owned.size()
	Text.ram["hDexRatingNumMonsSeen"] = seen
	Text.ram["hDexRatingNumMonsOwned"] = owned
	var label := ""
	for r in RATINGS:
		if owned < int(r[0]):
			label = str(r[1])
			break
	await Text.print_text("_DexCompletionText")
	await Text.print_text(label)
	# PlayPokedexRatingSfx: stop the music (waiting for the current sfx), play the
	# jingle as music from its own bank, then PlayDefaultMusic
	var sfx: String = SFX_NAMES[SFX_NAMES.size() - 1]
	for i in SFX_LIMITS.size():
		if owned < int(SFX_LIMITS[i]):
			sfx = str(SFX_NAMES[i])
			break
	await Sound.wait_for_sfx()
	Sound.stop_all_music()
	Sound.play_music(sfx)
	Sound.play_default_music()
	await Text.wait_scroll_button(false)

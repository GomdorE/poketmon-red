## DisplayListMenuID (home/list_menu.asm): the scrolling list box used by the bag
## and the Poké Mart, and DisplayChooseQuantityMenu. Autoload-free static helpers.
class_name ListMenu
extends RefCounted

const MONEY_SIGN := 0xF0   # '¥'
const TIMES := 0xF1        # '×'
const ARROW_DOWN := 0xEE   # '▼'

static var last_cursor := 0   # wCurrentMenuItem when the list closed (saved by the bag / mart)
static var last_offset := 0   # wListScrollOffset when the list closed


## Money (3-byte BCD) right-aligned in 7 cells: spaces, '¥', then the digits.
static func place_money(x: int, y: int, amount: int) -> void:
	var digits := "%06d" % amount
	var first := 0
	while first < 5 and digits[first] == "0":
		first += 1
	var cx := x
	for i in first:
		Text.put(cx, y, Text.SPACE)
		cx += 1
	Text.put(cx, y, MONEY_SIGN)
	cx += 1
	Text.place_string(cx, y, digits.substr(first))


## Shows a list of items (LIST_MENU_BOX at (4,2), four entries, CANCEL last).
## `prices`: print the price under each name (PRICEDITEMLISTMENU);
## `quantities`: print ×NN of the player's bag entries (ITEMLISTMENU).
## Returns the chosen index or -1 for CANCEL / B.
static func show_items(items: Array, prices: bool, quantities: bool, state: GameState = null, start_offset: int = 0, start_cursor: int = 0) -> int:
	var S: GBScreen = GB.screen
	var ko := GameData.lang == "ko"
	Menu.draw_box(4, 2, 14, 9)
	var count := items.size()
	var max_item := 1 if count < 2 else 2
	var offset := clampi(start_offset, 0, maxi(count - 3, 0))
	var cur := clampi(start_cursor, 0, max_item)
	await GB.frames(10)
	while true:
		# PrintListMenuEntries
		Text.clear_area(5, 3, 14, 9)
		var printed := 0
		for i in 4:
			var idx := offset + i
			var y := 4 + i * 2
			if idx == count:
				Text.place_string(6, y, "취소" if ko else "CANCEL")
				break
			if idx > count:
				break
			var item: String = items[idx]
			Text.place_string(6, y, GameData.item_name(item))
			if prices:
				place_money(11, y + 1, int(GameData.items[item]["price"]))
			if quantities and state != null and not (GameData.items.has(item) and GameData.items[item]["key"]):
				Text.put(14, y + 1, TIMES)
				Text.place_string(15, y + 1, "%2d" % state.item_count(item))
			printed += 1
		if printed == 4:
			Text.put(18, 11, ARROW_DOWN)
		await GB.delay3()
		Menu.place_cursor(5, 4 + cur * 2)
		var keys := 0
		while keys == 0:
			await GB.frame
			keys = GB.joy5
		if keys & GB.A:
			Sound.play_sfx("SFX_PRESS_AB")
			Menu.erase_cursor()
			var chosen := offset + cur
			if chosen >= count:
				return -1
			return chosen
		if keys & GB.B:
			Sound.play_sfx("SFX_PRESS_AB")
			Menu.erase_cursor()
			return -1
		if keys & GB.DOWN:
			if cur < max_item:
				Menu.erase_cursor()
				cur += 1
			elif offset + 3 < count:
				offset += 1
		elif keys & GB.UP:
			if cur > 0:
				Menu.erase_cursor()
				cur -= 1
			elif offset > 0:
				offset -= 1
	return -1


## DisplayChooseQuantityMenu: ×NN (and the total price when `unit_price` >= 0).
## Returns the quantity or -1 when cancelled with B.
static func choose_quantity(unit_price: int, max_qty: int) -> int:
	var priced := unit_price >= 0
	if priced:
		Menu.draw_box(7, 9, 11, 1)
		Text.put(8, 10, TIMES)
	else:
		Menu.draw_box(15, 9, 3, 1)
		Text.put(16, 10, TIMES)
	var qty := 1
	while true:
		if priced:
			Text.place_string(9, 10, "%02d" % qty)
			place_money(12, 10, unit_price * qty)
		else:
			Text.place_string(17, 10, "%02d" % qty)
		await GB.frame
		var keys := GB.pressed
		if keys & GB.A:
			return qty
		if keys & GB.B:
			return -1
		if keys & GB.UP:
			qty = 1 if qty >= max_qty else qty + 1
		elif keys & GB.DOWN:
			qty = max_qty if qty <= 1 else qty - 1
	return -1

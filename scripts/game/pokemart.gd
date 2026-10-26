## Poké Mart dialogue (engine/events/pokemart.asm): BUY / SELL / QUIT with the money box.
## The list menus follow home/list_menu.asm (DisplayListMenuID) layout.
class_name Pokemart
extends RefCounted


static func dialogue(ow: Overworld, mart_id: String) -> void:
	var S: GBScreen = GB.screen
	var state: GameState = ow.state
	var stock: Array = GameData.marts.get(mart_id, [])
	var bought_or_sold := false
	await Text.print_text("_PokemartGreetingText")
	var saved_screen := S.snapshot_bg()
	while true:
		S.restore_bg(saved_screen)
		_money_box(state)
		var choice := await _buy_sell_quit()
		if choice == 2:
			break
		if choice == 0:
			await Text.print_text("_PokemartBuyingGreetingText")
			var saved := S.snapshot_bg()
			while true:
				S.restore_bg(saved)
				_money_box(state)
				var pick := await ListMenu.show_items(stock, true, false)
				if pick < 0:
					break
				var item: String = stock[pick]
				var price: int = GameData.items[item]["price"]
				var qty := await ListMenu.choose_quantity(price, 99)
				if qty <= 0:
					continue
				Text.ram["wStringBuffer"] = GameData.item_name(item)
				Text.ram["hMoney"] = price * qty
				await Text.print_text("_PokemartTellBuyPriceText")
				if not await Menu.yes_no(14, 7):
					continue
				if state.money < price * qty:
					await Text.print_text("_PokemartNotEnoughMoneyText")
					continue
				if not state.give_item(item, qty):
					await Text.print_text("_PokemartItemBagFullText")
					continue
				state.money -= price * qty
				bought_or_sold = true
				await Sound.play_sfx_wait_for_current("SFX_PURCHASE")
				await Sound.wait_for_sfx()
				await Text.print_text("_PokemartBoughtItemText")
			S.restore_bg(saved)
			_money_box(state)
			await Text.print_text("_PokemartAnythingElseText")
			continue
		# SELL
		if state.items.is_empty():
			await Text.print_text("_PokemartItemBagEmptyText")
			await Text.print_text("_PokemartAnythingElseText")
			continue
		await Text.print_text("_PokemonSellingGreetingText")
		var saved2 := S.snapshot_bg()
		while true:
			S.restore_bg(saved2)
			_money_box(state)
			var names: Array = []
			for it in state.items:
				names.append(it.item)
			var pick := await ListMenu.show_items(names, false, true, state)
			if pick < 0:
				break
			var item: String = state.items[pick].item
			if (GameData.items.has(item) and GameData.items[item]["key"]) or item.begins_with("HM"):
				await Text.print_text("_PokemartUnsellableItemText")
				break
			var price: int = GameData.items[item]["price"] / 2
			var qty := await ListMenu.choose_quantity(price, state.items[pick].qty)
			if qty <= 0:
				continue
			Text.ram["wStringBuffer"] = GameData.item_name(item)
			Text.ram["hMoney"] = price * qty
			await Text.print_text("_PokemartTellSellPriceText")
			if not await Menu.yes_no(14, 7):
				continue
			bought_or_sold = true
			state.money += price * qty
			state.remove_item(item, qty)
		S.restore_bg(saved2)
		_money_box(state)
		await Text.print_text("_PokemartAnythingElseText")
	S.restore_bg(saved_screen)
	await Text.print_text("_PokemartThankYouText")


## MONEY_BOX_TEMPLATE: box (11,0)-(19,2) with MONEY on the top border and the amount at (12, 1).
static func _money_box(state: GameState) -> void:
	Menu.draw_box(11, 0, 7, 1)
	Text.place_string(13, 0, "소지금" if GameData.lang == "ko" else "MONEY")
	ListMenu.place_money(12, 1, state.money)


## BUY_SELL_QUIT_MENU_TEMPLATE: box (0,0)-(10,6), text at (2,1): returns 0 buy, 1 sell, 2 quit.
static func _buy_sell_quit() -> int:
	var ko := GameData.lang == "ko"
	Menu.draw_box(0, 0, 9, 5)
	Text.place_string(2, 1, "구입" if ko else "BUY")
	Text.place_string(2, 3, "판매" if ko else "SELL")
	Text.place_string(2, 5, "그만" if ko else "QUIT")
	var keys := await Menu.handle_input(1, 1, 3, GB.A | GB.B)
	Menu.erase_cursor()
	if keys & GB.B:
		return 2
	return Menu.current

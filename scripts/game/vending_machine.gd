## The vending machines (engine/events/vending_machine.asm VendingMachineMenu,
## data/items/vending_prices.asm): FRESH WATER ¥200, SODA POP ¥300, LEMONADE ¥350.
## The money check compares with ¥200 whatever the drink (the original does), so a
## pricier drink can take the money below zero (the BCD subtraction wraps).
class_name VendingMachine
extends RefCounted

const DRINKS := [["FRESH_WATER", 200], ["SODA_POP", 300], ["LEMONADE", 350]]


static func menu(ow: Overworld) -> void:
	var state: GameState = ow.state
	var ko := GameData.lang == "ko"
	await ow.print_text("_VendingMachineText1")
	Pokemart._money_box(state)
	Text.no_delay = true
	Menu.draw_box(0, 3, 12, 8)
	var names := ["맛있는물", "미네랄사이다", "후르츠밀크", "취소"] if ko else ["FRESH WATER", "SODA POP", "LEMONADE", "CANCEL"]
	for i in 4:
		Text.place_string(2, 5 + i * 2, names[i])
	for i in 3:
		Text.put(9, 6 + i * 2, ListMenu.MONEY_SIGN)
		Text.place_string(10, 6 + i * 2, str(DRINKS[i][1]))
	Text.no_delay = false
	var keys := await Menu.handle_input(1, 5, 4, GB.A | GB.B)
	Menu.erase_cursor()
	if keys & GB.B or Menu.current == 3:
		await ow.print_text("_VendingMachineText7")   # Not thirsty!
		return
	var item: String = DRINKS[Menu.current][0]
	var price: int = DRINKS[Menu.current][1]
	if state.money < 200:   # HasEnoughMoney against hMoney = ¥200
		await ow.print_text("_VendingMachineText4")   # Oops, not enough money!
		return
	if not state.give_item(item, 1):
		await ow.print_text("_VendingMachineText6")   # There's no more room for stuff!
		return
	for i in 60:   # the "brrrrr" delivery sound
		await GB.frames(2)
		Sound.play_sfx("SFX_PUSH_BOULDER")
	Text.ram["wStringBuffer"] = GameData.item_name(item)
	await ow.print_text("_VendingMachineText5")   # <item> popped out!
	state.money = posmod(state.money - price, 1000000)   # SubBCDPredef on three bytes
	Pokemart._money_box(state)
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("VENDING item=%s money=%d" % [item, state.money])

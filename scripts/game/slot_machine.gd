## The Game Corner slot machines (engine/slots/slot_machine.asm, data/events/slot_machine_wheels.asm,
## gfx/slots/slots.tilemap, gfx/slots/red_slots_1/2.2bpp). The wheels are the original byte
## lists read with the original offsets, so the odds, the early stops and the "allow a win"
## rerolls behave like the ROM (bugs included: wheel 1 stops at random in 7/BAR mode).
class_name SlotMachine
extends RefCounted

const SYM_7 := 0x02      # HIGH(SLOTS7) ... the low byte is the symbol's first sprite tile
const SYM_BAR := 0x06
const SYM_CHERRY := 0x0A
const SYM_FISH := 0x0E
const SYM_BIRD := 0x12
const SYM_MOUSE := 0x16
## SlotMachineWheel1..3 as symbol words (tile = symbol - 2)
const WHEEL_SYMBOLS := [
	[SYM_7, SYM_MOUSE, SYM_FISH, SYM_BAR, SYM_CHERRY, SYM_7, SYM_FISH, SYM_BIRD, SYM_BAR, SYM_CHERRY, SYM_7, SYM_MOUSE, SYM_BIRD, SYM_BAR, SYM_CHERRY, SYM_7, SYM_MOUSE, SYM_FISH],
	[SYM_7, SYM_FISH, SYM_CHERRY, SYM_BIRD, SYM_MOUSE, SYM_BAR, SYM_CHERRY, SYM_FISH, SYM_BIRD, SYM_CHERRY, SYM_BAR, SYM_FISH, SYM_BIRD, SYM_CHERRY, SYM_MOUSE, SYM_7, SYM_FISH, SYM_CHERRY],
	[SYM_7, SYM_BIRD, SYM_FISH, SYM_CHERRY, SYM_MOUSE, SYM_BIRD, SYM_FISH, SYM_CHERRY, SYM_MOUSE, SYM_BIRD, SYM_FISH, SYM_CHERRY, SYM_MOUSE, SYM_BIRD, SYM_BAR, SYM_7, SYM_BIRD, SYM_FISH],
]
## gfx/slots/slots.tilemap: the top 12 rows of the screen
const TILEMAP := [
	0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x03, 0x04, 0x05, 0x00, 0x00, 0x06, 0x07, 0x08, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01, 0x01,
	0x0a, 0x0e, 0x0b, 0x23, 0x1c, 0x1e, 0x1f, 0x1c, 0x1c, 0x1e, 0x1f, 0x1c, 0x1c, 0x1e, 0x1f, 0x1c, 0x23, 0x0a, 0x0e, 0x0b,
	0x0c, 0x0f, 0x0d, 0x24, 0x1d, 0x20, 0x21, 0x1d, 0x1d, 0x20, 0x21, 0x1d, 0x1d, 0x20, 0x21, 0x1d, 0x24, 0x0c, 0x0f, 0x0d,
	0x0a, 0x10, 0x0b, 0x23, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x23, 0x0a, 0x10, 0x0b,
	0x0c, 0x11, 0x0d, 0x24, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x24, 0x0c, 0x11, 0x0d,
	0x0a, 0x12, 0x0b, 0x23, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x23, 0x0a, 0x12, 0x0b,
	0x0c, 0x13, 0x0d, 0x24, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x24, 0x0c, 0x13, 0x0d,
	0x0a, 0x10, 0x0b, 0x23, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x23, 0x0a, 0x10, 0x0b,
	0x0c, 0x11, 0x0d, 0x24, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x16, 0x17, 0x17, 0x16, 0x24, 0x0c, 0x11, 0x0d,
	0x0a, 0x0e, 0x0b, 0x23, 0x00, 0x18, 0x19, 0x00, 0x00, 0x18, 0x19, 0x00, 0x00, 0x18, 0x19, 0x00, 0x23, 0x0a, 0x0e, 0x0b,
	0x0c, 0x0f, 0x0d, 0x24, 0x01, 0x1a, 0x1b, 0x01, 0x01, 0x1a, 0x1b, 0x01, 0x01, 0x1a, 0x1b, 0x01, 0x24, 0x0c, 0x0f, 0x0d,
]
## SlotRewardPointers by winning symbol tile: [coins, screen flashes]
const REWARDS := {0: [300, 20], 4: [100, 8], 8: [8, 2], 12: [15, 4], 16: [15, 4], 20: [15, 4]}
const WHEEL_X := [0x30, 0x50, 0x70]   # OAM X of each wheel's left column

var ow: Overworld
var state: GameState
var S: GBScreen
var wheels: Array = []                 # three byte lists: tile, symbol, tile, symbol...
var offsets := [0x1c, 0x1c, 0x1c]      # wSlotMachineWheel1Offset..
var slip := [4, 4, 4]                  # wSlotMachineWheel1SlipCounter..
var stopping := 0                      # wStoppingWhichSlotMachineWheel
var can_win := false                   # wSlotMachineFlags BIT_SLOTS_CAN_WIN
var can_win_7_or_bar := false          # BIT_SLOTS_CAN_WIN_WITH_7_OR_BAR
var allow_matches_counter := 0         # wSlotMachineAllowMatchesCounter
var reroll_counter := 0                # wSlotMachineRerollCounter
var bet := 0
var payout := 0
var winning_symbol := 0
var seven_and_bar_chance := 253        # wSlotMachineSevenAndBarModeChance
var bottom := [0, 0, 0]                # wSlotMachineWheelNBottomTile / Middle / Top (symbol bytes)
var middle := [0, 0, 0]
var top := [0, 0, 0]
var bgp_dark := false                  # rBGP ^ $40 while the screen flashes
var joy_last := 0                      # hJoyLast of the spin loop's own JoypadLowSensitivity calls
var obp_dark := false                  # rOBP0 ^ $40 while the coins are paid


func _init() -> void:
	for w in WHEEL_SYMBOLS:
		var bytes := PackedInt32Array()
		for sym in w:
			bytes.append(sym - 2)
			bytes.append(sym)
		wheels.append(bytes)


## PromptUserToPlaySlots: "A slot machine! Want to play?", then the game on its own screen;
## the map comes back afterwards (the caller closes the text display).
func play(o: Overworld, chance: int) -> void:
	ow = o
	state = o.state
	S = GB.screen
	seven_and_bar_chance = chance
	ow.in_text = true
	var saved := S.snapshot_bg()   # SaveScreenTilesToBuffer2
	Menu.message_box()             # DisplayTextIDInit
	await GB.delay3()
	await Text.print_text_no_box("_PlaySlotMachineText")
	if await Menu.yes_no():
		reroll_counter = 0
		ow.update_sprites = false   # wUpdateSpritesEnabled = -1: the OAM is the machine's now
		await ow.emotion_bubble(0, "happy")   # SMILE_BUBBLE over the player
		S.white_out()
		await GB.delay3()
		S.clear_sprites()
		_load_tiles()
		SGB.run("SLOTS")
		S.normal_pals()
		S.obp0 = GBScreen.pal(3, 2, 1, 0)     # rOBP0 = $e4
		Text.no_delay = true
		allow_matches_counter = 0
		# FillMemory wStoppingWhichSlotMachineWheel, $14: the wheels restart from offset 0
		stopping = 0
		offsets = [0, 0, 0]
		payout = 0
		can_win = false
		can_win_7_or_bar = false
		await _main_loop()
		Text.no_delay = false
		allow_matches_counter = 0
		S.white_out()
		await GB.delay3()
		SGB.run("DEFAULT")
		S.clear_sprites()
		ow.update_sprites = true
	S.restore_bg(saved)   # LoadScreenTilesFromBuffer2
	await GB.delay3()
	S.normal_pals()
	S.obp0 = GBScreen.pal(3, 2, 1, 0)
	# CloseTextDisplay
	ow.in_text = false
	ow._render()
	await GB.frame


## MainSlotMachineLoop: the bet menu (×3 ×2 ×1), the spin, the payout, "One more go?".
func _main_loop() -> void:
	while true:
		_print_credit_coins()
		payout = 0
		_print_payout_coins()
		await Text.print_text("_BetHowManySlotMachineText")
		var saved := S.snapshot_bg()   # SaveScreenTilesToBuffer1
		while true:
			Menu.draw_box(14, 11, 4, 5)
			for i in 3:
				Text.put(16, 12 + i * 2, ListMenu.TIMES)
				Text.place_string(17, 12 + i * 2, str(3 - i))
			var keys := await Menu.handle_input(15, 12, 3, GB.A | GB.B)
			Menu.erase_cursor()
			if keys & GB.B:
				S.restore_bg(saved)
				return
			bet = 3 - Menu.current
			if state.coins < bet:
				await Text.print_text("_NotEnoughCoinsSlotMachineText")
				continue
			break
		S.restore_bg(saved)
		_trace("bet=%d coins=%d" % [bet, state.coins])
		state.coins -= bet   # SlotMachine_SubtractBetFromPlayerCoins
		_print_credit_coins()
		_light_balls()
		_set_flags()
		slip = [4, 4, 4]
		await Sound.wait_for_sfx()
		Sound.play_sfx("SFX_SLOTS_NEW_SPIN")
		await Text.print_text("_StartSlotMachineText")
		await _spin_wheels()
		_trace("stopped offsets=%s flags=%s/%s" % [str(offsets), str(can_win), str(can_win_7_or_bar)])
		await _check_for_matches()
		_trace("checked coins=%d" % state.coins)
		if state.coins == 0:
			await Text.print_text("_OutOfCoinsSlotMachineText")
			await GB.frames(60)
			return
		await Text.print_text("_OneMoreGoSlotMachineText")
		if not await Menu.yes_no(14, 12):
			return
		_trace("one more go")
		_put_out_lit_balls()


## SlotMachine_SetFlags: whether this spin may win (and with 7/BAR symbols).
func _set_flags() -> void:
	if can_win_7_or_bar:
		return
	if allow_matches_counter != 0:
		can_win = true
		return
	var r := ow.rng.randi_range(0, 255)
	if r == 0:   # 1/256: sixty spins that may win
		allow_matches_counter = 60
		return
	if seven_and_bar_chance < r:
		can_win_7_or_bar = true
		return
	if 210 < r:   # 55/256 (or 52/256 on the lucky machine)
		can_win = true
		return
	can_win = false
	can_win_7_or_bar = false


## SlotMachine_SpinWheels: twenty free turns, then A stops the wheels one by one.
func _spin_wheels() -> void:
	for i in 20:
		_anim_wheel(0)
		_anim_wheel(1)
		_anim_wheel(2)
		await GB.frames(2)
	stopping = 0
	joy_last = GB.held
	while true:
		await _handle_input_while_wheels_spin()
		_stop_or_anim_wheel1()
		_stop_or_anim_wheel2()
		if _stop_or_anim_wheel3():
			return
		await GB.frames(1 if S.sgb_on else 2)


## SlotMachine_HandleInputWhileWheelsSpin: A stops the next wheel (not while the wheel
## being stopped still slips). JoypadLowSensitivity is called here every other frame, so a
## press counts as new against the state of the previous call, not the previous frame.
func _handle_input_while_wheels_spin() -> void:
	await GB.frame
	var held := GB.held
	var newly := held & ~joy_last
	joy_last = held
	if newly & GB.A == 0:
		return
	if stopping == 1 and slip[0] != 0:
		return
	if stopping == 2 and slip[1] != 0:
		return
	stopping += 1
	Sound.play_sfx("SFX_SLOTS_STOP_WHEEL")
	_trace("stopping wheel %d offsets=%s slip=%s" % [stopping, str(offsets), str(slip)])


## The wheels only stop with a symbol centred (an odd offset).
func _stop_or_anim_wheel1() -> void:
	if stopping < 1 or offsets[0] & 1 == 0:
		_anim_wheel(0)
		return
	if slip[0] == 0:
		return
	slip[0] -= 1
	if _stop_wheel1_early():
		return
	_anim_wheel(0)


## SlotMachine_StopWheel1Early: stop unless the middle symbol is a cherry; in 7/BAR mode
## the wheel never stops early (the loop's flags make it slip to the end).
func _stop_wheel1_early() -> bool:
	_get_wheel_tiles(0)
	if can_win_7_or_bar:
		return false
	if middle[0] != SYM_CHERRY:
		slip[0] = 0
		return true
	return false


func _stop_or_anim_wheel2() -> void:
	if stopping < 2 or offsets[1] & 1 == 0:
		_anim_wheel(1)
		return
	if slip[1] == 0:
		return
	slip[1] -= 1
	if _stop_wheel2_early():
		return
	_anim_wheel(1)


## SlotMachine_StopWheel2Early: stop when wheels 1 and 2 line something up; in 7/BAR mode
## when the symbol the comparison ended on is a 7 or a BAR.
func _stop_wheel2_early() -> bool:
	_get_wheel_tiles(1)
	var found := _find_wheel1_wheel2_matches()
	if not can_win_7_or_bar:
		if found[0]:
			slip[1] = 0
			return true
		return false
	if int(found[1]) >= SYM_BAR + 1:
		return false
	slip[1] = 0
	return true


## SlotMachine_FindWheel1Wheel2Matches: [matched, the wheel-2 symbol the routine left de on].
func _find_wheel1_wheel2_matches() -> Array:
	if bottom[1] == bottom[0]:
		return [true, bottom[1]]
	if middle[1] == bottom[0] or middle[1] == middle[0] or middle[1] == top[0]:
		return [true, middle[1]]
	if top[1] == top[0]:
		return [true, top[1]]
	return [false, bottom[1]]


## Returns true once wheel 3 has stopped.
func _stop_or_anim_wheel3() -> bool:
	if stopping < 3 or offsets[2] & 1 == 0:
		_anim_wheel(2)
		return false
	return true


## SlotMachine_CheckForMatches: the lines of the bet; a win the machine does not allow
## rolls wheel 3 on by one symbol, and an allowed spin without a match keeps rolling
## wheel 3 until something lines up.
func _check_for_matches() -> void:
	while true:
		_get_wheel_tiles(2)
		var sym := -1
		if bet == 3:
			sym = _match(bottom[0], middle[1], top[2])
			if sym < 0:
				sym = _match(top[0], middle[1], bottom[2])
		if sym < 0 and bet >= 2:
			sym = _match(top[0], top[1], top[2])
			if sym < 0:
				sym = _match(bottom[0], bottom[1], bottom[2])
		if sym < 0:
			sym = _match(middle[0], middle[1], middle[2])
		if sym < 0:
			if can_win or can_win_7_or_bar:
				reroll_counter = (reroll_counter - 1) & 0xFF
				if reroll_counter != 0:
					await _roll_wheel3_down_by_one_symbol()
					continue
			await Text.print_text("_NotThisTimeText")
			break
		if not (can_win or can_win_7_or_bar):
			await _roll_wheel3_down_by_one_symbol()
			continue
		if not can_win_7_or_bar and sym < SYM_BAR + 1:
			await _roll_wheel3_down_by_one_symbol()
			continue
		await _accept_match(sym)
		break
	Sound.set_mute_music(false)   # wMuteAudioAndPauseMusic = 0


func _trace(message: String) -> void:
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("SLOTS %s frame=%d" % [message, GB.frame_count])


static func _match(a: int, b: int, c: int) -> int:
	return a if a == b and a == c else -1


func _roll_wheel3_down_by_one_symbol() -> void:
	_anim_wheel(2)
	await GB.frame
	_anim_wheel(2)
	await GB.frame


## .acceptMatch: the reward's side effects, the flashing screen, "<symbol> lined up!
## Scored N coins!" and the coins counted into the credit one by one.
func _accept_match(sym: int) -> void:
	winning_symbol = sym - 2
	var reward: Array = REWARDS[winning_symbol]
	var coins: int = reward[0]
	match winning_symbol:
		8, 12, 16, 20:   # SlotReward8Func / SlotReward15Func
			if allow_matches_counter != 0:
				allow_matches_counter -= 1
		4:               # SlotReward100Func
			Sound.play_sfx("SFX_GET_KEY_ITEM")
			can_win = false
			can_win_7_or_bar = false
		0:               # SlotReward300Func
			await Text.print_text("_YeahText")
			Sound.play_sfx("SFX_GET_ITEM_2")
			if ow.rng.randi_range(0, 255) >= 0x80:
				can_win = false
				can_win_7_or_bar = false
			allow_matches_counter = 0
	Text.ram["wStringBuffer"] = str(coins)
	for i in int(reward[1]):
		bgp_dark = not bgp_dark
		S.bgp = GBScreen.pal(2, 2, 1, 0) if bgp_dark else GBScreen.pal(3, 2, 1, 0)
		await GB.frames(5)
	payout = coins
	_print_payout_coins()
	# SymbolLinedUpSlotMachineText: the symbol in the text box, then the text four cells on
	Menu.message_box()
	await GB.delay3()
	_print_winning_symbol()
	Text.cursor = Vector2i(5, 14)
	await Text.run_commands(GameData.text("_LinedUpText"))
	await Text.wait_scroll_button()
	await _pay_coins_to_player()
	_print_payout_coins()
	S.obp0 = GBScreen.pal(3, 2, 1, 0)
	if "--trace-scripts" in OS.get_cmdline_user_args():
		print("SLOTS win symbol=%d coins=%d credit=%d" % [winning_symbol, coins, state.coins])


## SlotMachine_PrintWinningSymbol: the 2x2 symbol at (2, 13) and the ▼ at (18, 16).
func _print_winning_symbol() -> void:
	var t := winning_symbol
	S.set_bg(2, 14, S.tile("slots_2", t))
	S.set_bg(3, 14, S.tile("slots_2", t + 1))
	S.set_bg(2, 13, S.tile("slots_2", t + 2))
	S.set_bg(3, 13, S.tile("slots_2", t + 3))
	Text.put(18, 16, ListMenu.ARROW_DOWN)


## SlotMachine_PayCoinsToPlayer: the music pauses while the payout ticks into the credit
## with SFX_SLOTS_REWARD (faster for a 7 or a BAR), the symbols flashing every five coins.
func _pay_coins_to_player() -> void:
	Sound.set_mute_music(true)
	await Sound.wait_for_sfx()
	var anim_counter := 5
	while payout != 0:
		payout -= 1
		state.coins = mini(state.coins + 1, 9999)
		_print_credit_coins()
		_print_payout_coins()
		Sound.play_sfx("SFX_SLOTS_REWARD")
		anim_counter -= 1
		if anim_counter == 0:
			obp_dark = not obp_dark
			S.obp0 = GBScreen.pal(2, 2, 1, 0) if obp_dark else GBScreen.pal(3, 2, 1, 0)
			anim_counter = 5
		await GB.frames(4 if winning_symbol < SYM_BAR + 1 else 8)


# --- drawing -------------------------------------------------------------------------------

## LoadSlotMachineTiles: the machine's tilemap and the three wheels at offset $1c.
func _load_tiles() -> void:
	for y in 12:
		for x in 20:
			S.set_bg(x, y, S.tile("slots_1", TILEMAP[y * 20 + x]))
	offsets = [0x1c, 0x1c, 0x1c]
	_anim_wheel(0)
	_anim_wheel(1)
	_anim_wheel(2)


## SlotMachine_AnimWheel: six rows of two sprites (behind the background) from the wheel's
## bytes at its offset, then the offset advances (wrapping at 30).
func _anim_wheel(k: int) -> void:
	var w: PackedInt32Array = wheels[k]
	var off: int = offsets[k]
	var x: int = WHEEL_X[k]
	var y := 0x58
	var oam := 12 * k
	var de := off
	while y != 0x28:
		var t: int = w[de]
		S.set_sprite(oam, x - 8, y - 16, S.tile("slots_2", t), 0, false, false, true)
		S.set_sprite(oam + 1, x, y - 16, S.tile("slots_2", t + 1), 0, false, false, true)
		oam += 2
		de += 1
		y -= 8
	offsets[k] = 0 if off + 1 == 30 else off + 1


## SlotMachine_GetWheel3Tiles / 2 / 1 (each falls through to the wheels before it).
func _get_wheel_tiles(k: int) -> void:
	for j in range(k, -1, -1):
		var w: PackedInt32Array = wheels[j]
		var off: int = offsets[j]
		bottom[j] = w[off]
		middle[j] = w[off + 2]
		top[j] = w[off + 4]


func _print_credit_coins() -> void:
	Text.place_string(5, 1, "%04d" % state.coins)


func _print_payout_coins() -> void:
	Text.place_string(11, 1, "%04d" % payout)


## SlotMachine_LightBalls: the bet lines' balls lit ($14/$15) at columns 3 and 16.
func _light_balls() -> void:
	_update_ball_tiles(6, 0x14)
	if bet >= 2:
		_update_ball_tiles(4, 0x14)
		_update_ball_tiles(8, 0x14)
	if bet >= 3:
		_update_ball_tiles(2, 0x14)
		_update_ball_tiles(10, 0x14)


func _put_out_lit_balls() -> void:
	for y in [2, 4, 6, 8, 10]:
		_update_ball_tiles(y, 0x23)


func _update_ball_tiles(y: int, tile: int) -> void:
	S.set_bg(3, y, S.tile("slots_1", tile))
	S.set_bg(16, y, S.tile("slots_1", tile))
	S.set_bg(3, y + 1, S.tile("slots_1", tile + 1))
	S.set_bg(16, y + 1, S.tile("slots_1", tile + 1))

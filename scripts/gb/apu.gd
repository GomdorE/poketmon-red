## Game Boy (DMG) sound hardware: two pulse channels with envelope (and sweep
## on channel 1), the 4-bit wave channel and the LFSR noise channel, mixed
## through NR50/NR51. Registers are written exactly like the hardware ones so
## the ported sound engine can poke them by address.
class_name GBApu
extends RefCounted

const CLOCK := 4194304
const RATE := 32768                      # 128 clock cycles per sample
const CYCLES_PER_SAMPLE := CLOCK / RATE
const SEQ_SAMPLES := 64                  # frame sequencer step = 8192 cycles
const DUTY := [
	[0, 0, 0, 0, 0, 0, 0, 1],
	[1, 0, 0, 0, 0, 0, 0, 1],
	[1, 0, 0, 0, 0, 1, 1, 1],
	[0, 1, 1, 1, 1, 1, 1, 0],
]
const NOISE_DIV := [8, 16, 32, 48, 64, 80, 96, 112]

var power := true
var nr50 := 0x77
var nr51 := 0xFF

# channel 1
var c1_sweep := 0
var c1_duty := 2
var c1_len := 0
var c1_env := 0
var c1_freq := 0
var c1_len_on := false
var c1_on := false
var c1_timer := 0
var c1_pos := 0
var c1_vol := 0
var c1_env_timer := 0
var c1_sw_timer := 0
var c1_sw_shadow := 0
var c1_sw_on := false
# channel 2
var c2_duty := 2
var c2_len := 0
var c2_env := 0
var c2_freq := 0
var c2_len_on := false
var c2_on := false
var c2_timer := 0
var c2_pos := 0
var c2_vol := 0
var c2_env_timer := 0
# channel 3
var c3_dac := false
var c3_len := 0
var c3_level := 0
var c3_freq := 0
var c3_len_on := false
var c3_on := false
var c3_timer := 0
var c3_pos := 0
var wave := PackedInt32Array()
# channel 4
var c4_len := 0
var c4_env := 0
var c4_poly := 0
var c4_len_on := false
var c4_on := false
var c4_timer := 0
var c4_lfsr := 0x7FFF
var c4_vol := 0
var c4_env_timer := 0

var _seq_step := 0
var _seq_counter := 0


func _init() -> void:
	wave.resize(32)
	wave.fill(0)


# --- registers ----------------------------------------------------------------

func write(addr: int, v: int) -> void:
	v &= 0xFF
	match addr:
		0xFF10:
			c1_sweep = v
		0xFF11:
			c1_duty = v >> 6
			c1_len = 64 - (v & 0x3F)
		0xFF12:
			c1_env = v
			if (v & 0xF8) == 0:
				c1_on = false
		0xFF13:
			c1_freq = (c1_freq & 0x700) | v
		0xFF14:
			c1_freq = (c1_freq & 0xFF) | ((v & 7) << 8)
			c1_len_on = (v & 0x40) != 0
			if v & 0x80:
				_trigger1()
		0xFF16:
			c2_duty = v >> 6
			c2_len = 64 - (v & 0x3F)
		0xFF17:
			c2_env = v
			if (v & 0xF8) == 0:
				c2_on = false
		0xFF18:
			c2_freq = (c2_freq & 0x700) | v
		0xFF19:
			c2_freq = (c2_freq & 0xFF) | ((v & 7) << 8)
			c2_len_on = (v & 0x40) != 0
			if v & 0x80:
				_trigger2()
		0xFF1A:
			c3_dac = (v & 0x80) != 0
			if not c3_dac:
				c3_on = false
		0xFF1B:
			c3_len = 256 - v
		0xFF1C:
			c3_level = (v >> 5) & 3
		0xFF1D:
			c3_freq = (c3_freq & 0x700) | v
		0xFF1E:
			c3_freq = (c3_freq & 0xFF) | ((v & 7) << 8)
			c3_len_on = (v & 0x40) != 0
			if v & 0x80:
				_trigger3()
		0xFF20:
			c4_len = 64 - (v & 0x3F)
		0xFF21:
			c4_env = v
			if (v & 0xF8) == 0:
				c4_on = false
		0xFF22:
			c4_poly = v
		0xFF23:
			c4_len_on = (v & 0x40) != 0
			if v & 0x80:
				_trigger4()
		0xFF24:
			nr50 = v
		0xFF25:
			nr51 = v
		0xFF26:
			power = (v & 0x80) != 0
		_:
			if addr >= 0xFF30 and addr <= 0xFF3F:
				var i := (addr - 0xFF30) * 2
				wave[i] = v >> 4
				wave[i + 1] = v & 0xF


func read(addr: int) -> int:
	match addr:
		0xFF10: return c1_sweep
		0xFF24: return nr50
		0xFF25: return nr51
		0xFF11: return (c1_duty << 6) | 0x3F
		0xFF16: return (c2_duty << 6) | 0x3F
	return 0


func _trigger1() -> void:
	c1_on = (c1_env & 0xF8) != 0
	if c1_len == 0:
		c1_len = 64
	c1_timer = (2048 - c1_freq) * 4
	c1_env_timer = c1_env & 7
	c1_vol = c1_env >> 4
	c1_sw_shadow = c1_freq
	var period := (c1_sweep >> 4) & 7
	var shift := c1_sweep & 7
	c1_sw_timer = period if period != 0 else 8
	c1_sw_on = period != 0 or shift != 0
	if shift != 0 and _sweep_calc() > 2047:
		c1_on = false


func _trigger2() -> void:
	c2_on = (c2_env & 0xF8) != 0
	if c2_len == 0:
		c2_len = 64
	c2_timer = (2048 - c2_freq) * 4
	c2_env_timer = c2_env & 7
	c2_vol = c2_env >> 4


func _trigger3() -> void:
	c3_on = c3_dac
	if c3_len == 0:
		c3_len = 256
	c3_timer = (2048 - c3_freq) * 2
	c3_pos = 0


func _trigger4() -> void:
	c4_on = (c4_env & 0xF8) != 0
	if c4_len == 0:
		c4_len = 64
	c4_timer = NOISE_DIV[c4_poly & 7] << (c4_poly >> 4)
	c4_env_timer = c4_env & 7
	c4_vol = c4_env >> 4
	c4_lfsr = 0x7FFF


func _sweep_calc() -> int:
	var shift := c1_sweep & 7
	var delta := c1_sw_shadow >> shift
	if c1_sweep & 8:
		return c1_sw_shadow - delta
	return c1_sw_shadow + delta


# --- frame sequencer --------------------------------------------------------------

func _clock_length() -> void:
	if c1_len_on and c1_len > 0:
		c1_len -= 1
		if c1_len == 0:
			c1_on = false
	if c2_len_on and c2_len > 0:
		c2_len -= 1
		if c2_len == 0:
			c2_on = false
	if c3_len_on and c3_len > 0:
		c3_len -= 1
		if c3_len == 0:
			c3_on = false
	if c4_len_on and c4_len > 0:
		c4_len -= 1
		if c4_len == 0:
			c4_on = false


func _clock_sweep() -> void:
	if not c1_sw_on:
		return
	c1_sw_timer -= 1
	if c1_sw_timer > 0:
		return
	var period := (c1_sweep >> 4) & 7
	c1_sw_timer = period if period != 0 else 8
	if period == 0:
		return
	var nf := _sweep_calc()
	if nf > 2047:
		c1_on = false
		return
	if (c1_sweep & 7) != 0:
		c1_sw_shadow = nf
		c1_freq = nf
		if _sweep_calc() > 2047:
			c1_on = false


func _clock_envelope() -> void:
	var p := c1_env & 7
	if p != 0:
		c1_env_timer -= 1
		if c1_env_timer <= 0:
			c1_env_timer = p
			if c1_env & 8:
				if c1_vol < 15:
					c1_vol += 1
			elif c1_vol > 0:
				c1_vol -= 1
	p = c2_env & 7
	if p != 0:
		c2_env_timer -= 1
		if c2_env_timer <= 0:
			c2_env_timer = p
			if c2_env & 8:
				if c2_vol < 15:
					c2_vol += 1
			elif c2_vol > 0:
				c2_vol -= 1
	p = c4_env & 7
	if p != 0:
		c4_env_timer -= 1
		if c4_env_timer <= 0:
			c4_env_timer = p
			if c4_env & 8:
				if c4_vol < 15:
					c4_vol += 1
			elif c4_vol > 0:
				c4_vol -= 1


func _sequencer_step() -> void:
	match _seq_step:
		0, 4:
			_clock_length()
		2, 6:
			_clock_length()
			_clock_sweep()
		7:
			_clock_envelope()
	_seq_step = (_seq_step + 1) & 7


# --- synthesis ---------------------------------------------------------------------

## Generate n stereo samples.
func generate(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(n)
	if not power:
		out.fill(Vector2.ZERO)
		return out
	var vol_l := ((nr50 >> 4) & 7) + 1
	var vol_r := (nr50 & 7) + 1
	var scale_l := float(vol_l) / 8.0 * 0.25 / 15.0
	var scale_r := float(vol_r) / 8.0 * 0.25 / 15.0
	var d1: Array = DUTY[c1_duty]
	var d2: Array = DUTY[c2_duty]
	var p1 := (2048 - c1_freq) * 4
	var p2 := (2048 - c2_freq) * 4
	var p3 := (2048 - c3_freq) * 2
	var p4: int = NOISE_DIV[c4_poly & 7] << (c4_poly >> 4)
	var width7 := (c4_poly & 8) != 0
	var shift3 := 4 if c3_level == 0 else c3_level - 1
	var pan := nr51
	var wave_local := wave
	for i in n:
		# channel timers
		if c1_on:
			c1_timer -= CYCLES_PER_SAMPLE
			while c1_timer <= 0:
				c1_timer += p1
				c1_pos = (c1_pos + 1) & 7
		if c2_on:
			c2_timer -= CYCLES_PER_SAMPLE
			while c2_timer <= 0:
				c2_timer += p2
				c2_pos = (c2_pos + 1) & 7
		if c3_on:
			c3_timer -= CYCLES_PER_SAMPLE
			while c3_timer <= 0:
				c3_timer += p3
				c3_pos = (c3_pos + 1) & 31
		if c4_on:
			c4_timer -= CYCLES_PER_SAMPLE
			while c4_timer <= 0:
				c4_timer += p4
				var x := (c4_lfsr ^ (c4_lfsr >> 1)) & 1
				c4_lfsr = (c4_lfsr >> 1) | (x << 14)
				if width7:
					c4_lfsr = (c4_lfsr & ~0x40) | (x << 6)
		# outputs (0..15 per channel, DAC-centred)
		var o1 := 0
		var o2 := 0
		var o3 := 0
		var o4 := 0
		var dac1 := (c1_env & 0xF8) != 0
		var dac2 := (c2_env & 0xF8) != 0
		var dac4 := (c4_env & 0xF8) != 0
		if c1_on and d1[c1_pos] == 1:
			o1 = c1_vol
		if c2_on and d2[c2_pos] == 1:
			o2 = c2_vol
		if c3_on:
			o3 = wave_local[c3_pos] >> shift3
		if c4_on and (c4_lfsr & 1) == 0:
			o4 = c4_vol
		var l := 0.0
		var r := 0.0
		if dac1:
			var s := float(o1 * 2 - 15)
			if pan & 0x10: l += s
			if pan & 0x01: r += s
		if dac2:
			var s := float(o2 * 2 - 15)
			if pan & 0x20: l += s
			if pan & 0x02: r += s
		if c3_dac:
			var s := float(o3 * 2 - 15)
			if pan & 0x40: l += s
			if pan & 0x04: r += s
		if dac4:
			var s := float(o4 * 2 - 15)
			if pan & 0x80: l += s
			if pan & 0x08: r += s
		out[i] = Vector2(l * scale_l, r * scale_r)
		# frame sequencer
		_seq_counter += 1
		if _seq_counter == SEQ_SAMPLES:
			_seq_counter = 0
			_sequencer_step()
			# registers may have changed through sweep
			p1 = (2048 - c1_freq) * 4
	return out

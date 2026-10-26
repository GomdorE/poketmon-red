## The pokered sound engine (audio/engine_1.asm, with the bank 2 additions for
## battle sfx and the low-health alarm) plus the home-bank helpers of
## home/audio.asm and home/fade_audio.asm, driving a Game Boy APU model.
## Autoloaded as `Sound`; GB._tick calls vblank() once per Game Boy frame, like
## the original VBlank handler (FadeOutAudio, [Music_DoLowHealthAlarm,] UpdateMusic).
##
## PH-INTENT: nothing here is re-sequenced by hand. Music, sfx and cries are the
## exported original command streams (assets/data/audio.json) interpreted with the
## original engine semantics, including its quirks (pitch slide borrow bug, channel 8
## continuing from its stale pointer during cries, sfx ignored while a fade is pending,
## sound ids resolved in the current audio bank so SFX_GET_ITEM_1 is SFX_LEVEL_UP in battle).
extends Node

const NUM_CHANNELS := 8
const CHAN1 := 0
const CHAN3 := 2
const CHAN4 := 3
const CHAN5 := 4
const CHAN6 := 5
const CHAN7 := 6
const CHAN8 := 7
# wChannelFlags1 bits
const F_PERFECT_PITCH := 1
const F_SOUND_CALL := 2
const F_NOISE_OR_SFX := 4
const F_VIBRATO_DIR := 8
const F_SLIDE_ON := 16
const F_SLIDE_DEC := 32
const F_ROTATE_DUTY := 64
# wChannelFlags2
const F2_EXECUTE_MUSIC := 1
const HW_BASE: Array[int] = [0xFF10, 0xFF15, 0xFF1A, 0xFF1F, 0xFF10, 0xFF15, 0xFF1A, 0xFF1F]
const HW_ENABLE: Array[int] = [0x11, 0x22, 0x44, 0x88, 0x11, 0x22, 0x44, 0x88]
const SFX_STOP_ALL_MUSIC := 0xFF
const DISABLE_LOW_HEALTH_ALARM := 0xFF
const SAMPLES_PER_FRAME := 32768.0 / 59.7275
const TARGET_BUFFERED := 3.0 * SAMPLES_PER_FRAME
const MASTER_GAIN := 0.5
# TextCommandSounds (home/text.asm)
const TEXT_SOUNDS := {
	"sound_get_item_1": "SFX_GET_ITEM_1", "sound_caught_mon": "SFX_CAUGHT_MON",
	"sound_pokedex_rating": "SFX_POKEDEX_RATING", "sound_get_item_1_duplicate": "SFX_GET_ITEM_1",
	"sound_get_item_2": "SFX_GET_ITEM_2", "sound_get_key_item": "SFX_GET_KEY_ITEM",
	"sound_dex_page_added": "SFX_DEX_PAGE_ADDED", "sound_level_up": "SFX_GET_ITEM_1",
}
const TEXT_CRIES := {"sound_cry_nidorina": "NIDORINA", "sound_cry_pidgeot": "PIDGEOT", "sound_cry_dewgong": "DEWGONG"}

var enabled := true          # false: the engine still runs (identical timing), no audio output
var apu := GBApu.new()
var cmds: Array = []
var labels := {}
var banks := {}              # bank -> {id -> {"name", "channels": [[software channel, cmd index], ...]}}
var sounds := {}             # constant name -> {"bank", "id"}
var notes := PackedInt32Array()
var waves: Array = []
var ranges := {}
var cries: Array = []
var move_sfx: Array = []
var map_music := {}
var ret_cmd_index := -1      # a lone sound_ret (Audio1_CryRet)

# wChannel* arrays
var ch_id := PackedInt32Array()
var ch_ptr := PackedInt32Array()
var ch_ret := PackedInt32Array()
var ch_flags1 := PackedInt32Array()
var ch_flags2 := PackedInt32Array()
var ch_duty := PackedInt32Array()
var ch_dutypat := PackedInt32Array()
var ch_vib_delay := PackedInt32Array()
var ch_vib_extent := PackedInt32Array()
var ch_vib_rate := PackedInt32Array()
var ch_freq_lo := PackedInt32Array()
var ch_vib_delay_reload := PackedInt32Array()
var ch_slide_len_mod := PackedInt32Array()
var ch_slide_steps := PackedInt32Array()
var ch_slide_steps_frac := PackedInt32Array()
var ch_slide_cur_frac := PackedInt32Array()
var ch_slide_cur_hi := PackedInt32Array()
var ch_slide_cur_lo := PackedInt32Array()
var ch_slide_tgt_hi := PackedInt32Array()
var ch_slide_tgt_lo := PackedInt32Array()
var ch_loop := PackedInt32Array()
var ch_delay := PackedInt32Array()
var ch_speed := PackedInt32Array()
var ch_delay_frac := PackedInt32Array()
var ch_octave := PackedInt32Array()
var ch_volume := PackedInt32Array()

# engine globals
var music_tempo := 0x0100
var sfx_tempo := 0x0100
var music_wave := 0
var sfx_wave := 0
var stereo_panning := 0xFF
var saved_volume := 0
var disable_output_when_sfx_ends := 0
var frequency_modifier := 0
var tempo_modifier := 0x80
var current_bank := 1        # the engine copy running (wAudioROMBank when called)
var _header_bank := 1        # fallback header table for a sound missing from the current bank
# home/audio.asm state
var audio_rom_bank := 1
var audio_saved_rom_bank := 1
var fade_out_control := 0
var fade_out_counter := 0
var fade_out_reload := 0
var new_sound_id := 0
var last_music_sound_id := 0
var map_music_sound_id := 0
var map_music_rom_bank := 1
var no_audio_fade_out := false   # wStatusFlags2 BIT_NO_AUDIO_FADE_OUT
var no_map_music := false        # wStatusFlags7 BIT_NO_MAP_MUSIC
var low_health_alarm := 0        # wLowHealthAlarm
var low_health_alarm_disabled := false

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _capacity := 0
var _sample_acc := 0.0
var _warned := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--no-audio":
			enabled = false
	if DisplayServer.get_name() == "headless":
		enabled = false
	_load()
	_reset_channels_all()
	# home/init.asm
	audio_rom_bank = 1
	audio_saved_rom_bank = 1
	new_sound_id = 0
	last_music_sound_id = 0
	_home_play_sound(SFX_STOP_ALL_MUSIC)
	# Init: ld a, BANK(SFX_Shooting_Star); ld [wAudioROMBank], a
	audio_rom_bank = 3
	audio_saved_rom_bank = 3
	if not enabled:
		return
	_player = AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = GBApu.RATE
	gen.buffer_length = 0.25
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	_capacity = _playback.get_frames_available()
	var silence := PackedVector2Array()
	silence.resize(int(TARGET_BUFFERED))
	silence.fill(Vector2.ZERO)
	_playback.push_buffer(silence)


func _load() -> void:
	var f := FileAccess.open("res://assets/data/audio.json", FileAccess.READ)
	assert(f != null, "missing audio.json")
	var data: Dictionary = GameData._intify(JSON.parse_string(f.get_as_text()))
	cmds = data["cmds"]
	labels = data["labels"]
	for b in data["banks"].keys():
		var d := {}
		for k in data["banks"][b].keys():
			d[int(k)] = data["banks"][b][k]
		banks[int(b)] = d
	sounds = data["sounds"]
	for n in data["notes"]:
		notes.append(int(n))
	waves = data["waves"]
	ranges = data["ranges"]
	cries = data["cries"]
	move_sfx = data["move_sfx"]
	map_music = data["map_music"]
	for i in cmds.size():
		if cmds[i][0] == "ret":
			ret_cmd_index = i
			break
	for arr in _all_channel_arrays():
		arr.resize(NUM_CHANNELS)
		arr.fill(0)


func _all_channel_arrays() -> Array:
	return [ch_id, ch_ptr, ch_ret, ch_flags1, ch_flags2, ch_duty, ch_dutypat, ch_vib_delay, ch_vib_extent,
			ch_vib_rate, ch_freq_lo, ch_vib_delay_reload, ch_slide_len_mod, ch_slide_steps, ch_slide_steps_frac,
			ch_slide_cur_frac, ch_slide_cur_hi, ch_slide_cur_lo, ch_slide_tgt_hi, ch_slide_tgt_lo, ch_loop,
			ch_delay, ch_speed, ch_delay_frac, ch_octave, ch_volume]


# --- public API (home/audio.asm) -------------------------------------------------------------

func _id(name: String) -> int:
	assert(sounds.has(name), "unknown sound " + name)
	return int(sounds[name]["id"])


func _bank(name: String) -> int:
	return int(sounds[name]["bank"])


## PlayMusic: switches the audio bank to the song's bank and starts it.
func play_music(name: String) -> void:
	_home_play_music(_id(name), _bank(name))


## `ld a, X; call PlaySound` (wNewSoundID = 0): a sound effect in the current audio bank.
func play_sfx(name: String) -> void:
	_header_bank = _bank(name)
	_home_play_sound(_id(name))


## `ld a, X; ld [wNewSoundID], a; call PlaySound`: music started in the current bank.
func play_new_sound(name: String) -> void:
	_header_bank = _bank(name)
	new_sound_id = _id(name)
	_home_play_sound(new_sound_id)


## PlaySound after setting wFrequencyModifier / wTempoModifier (cries, battle sfx).
func play_sfx_modified(name: String, freq_mod: int, tempo_mod: int) -> void:
	frequency_modifier = freq_mod & 0xFF
	tempo_modifier = tempo_mod & 0xFF
	play_sfx(name)


## PlayCry minus its WaitForSoundToFinish; callers await wait_for_sfx() like the original.
func play_cry(species: String) -> void:
	var p: Dictionary = GameData.pokemon[species]
	var c: Array = cries[int(p["internal_id"]) - 1]
	play_sfx_modified("SFX_CRY_%02X" % int(c[0]), int(c[1]), int(c[2]))


## GetMoveSound for Growl / Roar: the mon's cry with the table's modifiers added.
func play_cry_modified(species: String, freq_add: int, tempo_add: int) -> void:
	var p: Dictionary = GameData.pokemon[species]
	var c: Array = cries[int(p["internal_id"]) - 1]
	play_sfx_modified("SFX_CRY_%02X" % int(c[0]), int(c[1]) + freq_add, int(c[2]) + tempo_add)


## MoveSoundTable: the sound effect of a move with its modifiers.
func play_move_sfx(move: String) -> void:
	var id: int = int(GameData.moves[move]["id"])
	var m: Array = move_sfx[id - 1]
	play_sfx_modified(m[0], int(m[1]), int(m[2]))


## PlayApplyingAttackSound: damage multiplier in tenths (10 = neutral), 0 = no sound.
func play_applying_attack_sound(multiplier: int) -> void:
	await wait_for_sfx()
	if multiplier == 0:
		return
	if multiplier == 10:
		play_sfx_modified("SFX_DAMAGE", 0x20, 0x30)
	elif multiplier > 10:
		play_sfx_modified("SFX_SUPER_EFFECTIVE", 0xE0, 0xFF)
	else:
		play_sfx_modified("SFX_NOT_VERY_EFFECTIVE", 0x50, 0x01)


## A text command sound (TextCommand_SOUND): plays and waits.
func text_sound(op: String) -> void:
	if TEXT_CRIES.has(op):
		play_cry(TEXT_CRIES[op])
		await wait_for_sfx()
		return
	play_sfx(TEXT_SOUNDS[op])
	await wait_for_sfx()


## StopAllMusic (wNewSoundID = SFX_STOP_ALL_MUSIC; PlaySound).
func stop_all_music() -> void:
	new_sound_id = SFX_STOP_ALL_MUSIC
	_home_play_sound(SFX_STOP_ALL_MUSIC)


## `ld a, SFX_STOP_ALL_MUSIC; call PlaySound` (wNewSoundID untouched).
func stop_all_sound() -> void:
	_home_play_sound(SFX_STOP_ALL_MUSIC)


## PlaySoundWaitForCurrent.
func play_sfx_wait_for_current(name: String) -> void:
	await wait_for_sfx()
	play_sfx(name)


## PlayBattleMusic (audio/play_battle_music.asm).
func play_battle_music(name: String) -> void:
	fade_out_control = 0
	low_health_alarm = 0
	low_health_alarm_disabled = false
	stop_all_music()
	await GB.frame
	play_music(name)


## PlayBattleVictoryMusic (engine/battle/core.asm).
func play_battle_victory_music(name: String) -> void:
	new_sound_id = SFX_STOP_ALL_MUSIC
	await wait_for_sfx()
	_home_play_sound(SFX_STOP_ALL_MUSIC)
	play_music(name)
	await GB.delay3()


## wAudioROMBank / wAudioSavedROMBank written directly by game code.
func set_audio_bank(bank: int) -> void:
	audio_rom_bank = bank
	audio_saved_rom_bank = bank


## The map header's music (wMapMusicSoundID / wMapMusicROMBank), set on map load.
func set_map_music(map_id: String) -> void:
	var name: String = map_music[map_id]
	map_music_sound_id = _id(name)
	map_music_rom_bank = _bank(name)


## PlayDefaultMusic (waits for sfx first, no fade).
func play_default_music() -> void:
	await wait_for_sfx()
	last_music_sound_id = 0
	_play_default_music_common(0)


## PlayDefaultMusicFadeOutCurrent.
func play_default_music_fade_out_current(battle_over: bool = false) -> void:
	var c := 10
	if battle_over:
		last_music_sound_id = 0
		c = 8
	_play_default_music_common(c)


## `ld a, frames; ld [wAudioFadeOutControl], a; ld a, id; ld [wNewSoundID], a; call PlaySound`
func fade_out_then(frames: int, name: String = "") -> void:
	fade_out_control = frames
	var id := SFX_STOP_ALL_MUSIC if name == "" else _id(name)
	if name != "":
		_header_bank = _bank(name)
	new_sound_id = id
	_home_play_sound(id)


## UpdateMusic6Times (run while the LCD is off during map loads).
func update_music_6_times() -> void:
	for i in 6:
		current_bank = audio_rom_bank
		_update_music()


## Music_RivalAlternateStart: MeetRival starting at the alternate labels.
func rival_alternate_start() -> void:
	play_music("MUSIC_MEET_RIVAL")
	ch_ptr[0] = int(labels["Music_MeetRival_Ch1_AlternateStart"])
	ch_ptr[1] = int(labels["Music_MeetRival_Ch2_AlternateStart"])
	ch_ptr[2] = int(labels["Music_MeetRival_Ch3_AlternateStart"])


## wLowHealthAlarm: set bit 7 (start), or DISABLE_LOW_HEALTH_ALARM.
func set_low_health_alarm(on: bool) -> void:
	if on:
		low_health_alarm |= 0x80
	else:
		low_health_alarm = DISABLE_LOW_HEALTH_ALARM


## EndLowHealthAlarm (battle won).
func end_low_health_alarm() -> void:
	low_health_alarm = 0
	ch_id[CHAN5] = 0
	low_health_alarm_disabled = true


## Master volume (0..1) of the generator output.
func set_volume(linear: float) -> void:
	if _player == null:
		return
	_player.volume_db = linear_to_db(linear) if linear > 0.0 else -80.0


func sfx_playing() -> bool:
	return (ch_id[CHAN5] | ch_id[CHAN6] | ch_id[CHAN8]) != 0


## WaitForSoundToFinish.
func wait_for_sfx() -> void:
	if low_health_alarm & 0x80:
		return
	while sfx_playing():
		await GB.frame


## Wait while a given sfx occupies channel 5 (e.g. the `.sfxwait` loop on SFX_FAINT_FALL).
func wait_while_channel5_is(name: String) -> void:
	var id := _id(name)
	while ch_id[CHAN5] == id:
		await GB.frame


func channel5_is(name: String) -> bool:
	return ch_id[CHAN5] == _id(name)


func channel1_is(name: String) -> bool:
	return ch_id[CHAN1] == _id(name)


## AnimateHealingMachine: play a song through PlaySound after switching to its bank.
func play_new_sound_in_own_bank(name: String) -> void:
	if audio_rom_bank != _bank(name):
		stop_all_music()
		audio_rom_bank = _bank(name)
	play_new_sound(name)


## After the healing machine: the map music restarts from the saved bank.
func restart_map_music() -> void:
	fade_out_control = 0
	audio_rom_bank = audio_saved_rom_bank
	last_music_sound_id = map_music_sound_id
	new_sound_id = map_music_sound_id
	_header_bank = map_music_rom_bank
	_home_play_sound(map_music_sound_id)


# --- home/audio.asm ---------------------------------------------------------------------------

func _home_play_music(id: int, bank: int) -> void:
	new_sound_id = id
	fade_out_control = 0
	audio_rom_bank = bank
	audio_saved_rom_bank = bank
	_header_bank = bank
	_home_play_sound(id)


func _home_play_sound(b: int) -> void:
	if new_sound_id != 0:
		for c in range(CHAN5, NUM_CHANNELS):
			ch_id[c] = 0
	if fade_out_control != 0:
		if new_sound_id == 0:
			return
		new_sound_id = 0
		if last_music_sound_id != 0xFF:
			last_music_sound_id = b
			fade_out_reload = fade_out_control
			fade_out_counter = fade_out_control
			fade_out_control = b
			return
		fade_out_control = 0
	new_sound_id = 0
	current_bank = audio_rom_bank
	_play_sound(b)


func _play_default_music_common(c: int) -> void:
	var b := map_music_sound_id
	# CompareMapMusicBankWithCurrentBank
	if map_music_rom_bank == audio_rom_bank:
		audio_saved_rom_bank = audio_rom_bank
		if last_music_sound_id == b:
			return
	else:
		if c == 0:
			audio_rom_bank = map_music_rom_bank
		audio_saved_rom_bank = map_music_rom_bank
	fade_out_control = c
	last_music_sound_id = b
	new_sound_id = b
	_header_bank = map_music_rom_bank
	_home_play_sound(b)


## One VBlank (home/vblank.asm order).
func vblank() -> void:
	_fade_out_audio()
	current_bank = audio_rom_bank
	if current_bank == 2:
		_do_low_health_alarm()
	_update_music()
	_push_audio()


func _fade_out_audio() -> void:
	if fade_out_control == 0:
		if not no_audio_fade_out:
			apu.write(0xFF24, 0x77)
		return
	if fade_out_counter != 0:
		fade_out_counter -= 1
		return
	fade_out_counter = fade_out_reload
	var vol := apu.nr50
	if vol != 0:
		var lo := ((vol & 0xF) - 1) & 0xF
		var hi := (((vol >> 4) & 0xF) - 1) & 0xF
		apu.write(0xFF24, (hi << 4) | lo)
		return
	var b := fade_out_control
	fade_out_control = 0
	new_sound_id = SFX_STOP_ALL_MUSIC
	_home_play_sound(SFX_STOP_ALL_MUSIC)
	audio_rom_bank = audio_saved_rom_bank
	new_sound_id = b
	_header_bank = audio_rom_bank
	_home_play_sound(b)


## Music_DoLowHealthAlarm (audio/low_health_alarm.asm).
func _do_low_health_alarm() -> void:
	var a := low_health_alarm
	if a == DISABLE_LOW_HEALTH_ALARM:
		low_health_alarm = 0
		ch_id[CHAN5] = 0
		_alarm_tone(0x00, 0x00, 0x8000)
		return
	if (a & 0x80) == 0:
		return
	var t := a & 0x7F
	if t == 0:
		_alarm_tone(0xA0, 0xE2, 0x8750)
		a = 30
	else:
		if t == 20:
			_alarm_tone(0xB0, 0xE2, 0x86EE)
		ch_id[CHAN5] = int(ranges["cry_end"])
		a = (t - 1) & 0x7F
	low_health_alarm = a | 0x80


func _alarm_tone(len: int, env: int, freq: int) -> void:
	apu.write(0xFF10, 0)
	apu.write(0xFF11, len)
	apu.write(0xFF12, env)
	apu.write(0xFF13, freq & 0xFF)
	apu.write(0xFF14, freq >> 8)


func _push_audio() -> void:
	if _playback == null:
		return
	_sample_acc += SAMPLES_PER_FRAME
	var n := int(_sample_acc)
	_sample_acc -= n
	var avail := _playback.get_frames_available()
	var buffered := _capacity - avail
	if buffered < TARGET_BUFFERED - SAMPLES_PER_FRAME:
		n += 32
	elif buffered > TARGET_BUFFERED + SAMPLES_PER_FRAME:
		n -= 32
	if avail < n:
		return
	var buf := apu.generate(n)
	for i in n:
		buf[i] *= MASTER_GAIN
	_playback.push_buffer(buf)


# --- Audio1_UpdateMusic / ApplyMusicAffects ------------------------------------------------------

func _update_music() -> void:
	for c in NUM_CHANNELS:
		if ch_id[c] != 0:
			_apply_music_affects(c)


func _apply_music_affects(c: int) -> void:
	if ch_delay[c] == 1:
		_play_next_note(c)
		return
	ch_delay[c] = (ch_delay[c] - 1) & 0xFF
	if c < CHAN5 and ch_id[c + CHAN5] != 0:
		return
	if ch_flags1[c] & F_ROTATE_DUTY:
		_apply_duty_cycle_pattern(c)
	if (ch_flags2[c] & F2_EXECUTE_MUSIC) == 0 and (ch_flags1[c] & F_NOISE_OR_SFX):
		return
	if ch_flags1[c] & F_SLIDE_ON:
		_apply_pitch_slide(c)
		return
	if ch_vib_delay[c] != 0:
		ch_vib_delay[c] -= 1
		return
	if ch_vib_extent[c] == 0:
		return
	var d := ch_vib_extent[c]
	if (ch_vib_rate[c] & 0xF) != 0:
		ch_vib_rate[c] -= 1
		return
	ch_vib_rate[c] = (ch_vib_rate[c] & 0xF0) | (ch_vib_rate[c] >> 4)
	var e := ch_freq_lo[c]
	var a: int
	if ch_flags1[c] & F_VIBRATO_DIR:
		ch_flags1[c] &= ~F_VIBRATO_DIR
		a = maxi(e - (d & 0xF), 0)
	else:
		ch_flags1[c] |= F_VIBRATO_DIR
		a = mini(e + (d >> 4), 0xFF)
	apu.write(HW_BASE[c] + 3, a)


func _apply_duty_cycle_pattern(c: int) -> void:
	var p := ch_dutypat[c]
	p = ((p << 2) | (p >> 6)) & 0xFF
	ch_dutypat[c] = p
	var reg := HW_BASE[c] + 1
	apu.write(reg, (apu.read(reg) & 0x3F) | (p & 0xC0))


func _play_next_note(c: int) -> void:
	ch_vib_delay[c] = ch_vib_delay_reload[c]
	ch_flags1[c] &= ~(F_SLIDE_ON | F_SLIDE_DEC)
	if current_bank == 2 and c == CHAN5 and (low_health_alarm & 0x80):
		return
	_run_commands(c)


# --- command execution ------------------------------------------------------------------------------

func _run_commands(c: int) -> void:
	while true:
		if ch_ptr[c] < 0 or ch_ptr[c] >= cmds.size():
			ch_ptr[c] = ret_cmd_index
		var cmd: Array = cmds[ch_ptr[c]]
		ch_ptr[c] += 1
		match cmd[0]:
			"ret":
				if _sound_ret(c):
					continue
				return
			"call":
				ch_ret[c] = ch_ptr[c]
				ch_ptr[c] = cmd[1]
				ch_flags1[c] |= F_SOUND_CALL
			"loop":
				var count: int = cmd[1]
				if count == 0:
					ch_ptr[c] = cmd[2]
				elif ch_loop[c] == count:
					ch_loop[c] = 1
				else:
					ch_loop[c] += 1
					ch_ptr[c] = cmd[2]
			"notetype":
				ch_speed[c] = cmd[1]
				var byte: int = (cmd[2] << 4) | _fade_nibble(cmd[3])
				if c == CHAN3 or c == CHAN7:
					if c == CHAN3:
						music_wave = byte & 0xF
					else:
						sfx_wave = byte & 0xF
					byte = (byte & 0x30) << 1
				ch_volume[c] = byte
			"drumspeed":
				ch_speed[c] = cmd[1]
			"perfect":
				ch_flags1[c] ^= F_PERFECT_PITCH
			"vibrato":
				ch_vib_delay[c] = cmd[1]
				ch_vib_delay_reload[c] = cmd[1]
				var n: int = cmd[2]
				ch_vib_extent[c] = (((n >> 1) + (n & 1)) << 4) | (n >> 1)
				ch_vib_rate[c] = (cmd[3] << 4) | cmd[3]
			"slide":
				ch_slide_len_mod[c] = (cmd[1] - 1) & 0xFF
				var freq := _calc_frequency(cmd[3], 8 - cmd[2])
				ch_slide_tgt_hi[c] = freq >> 8
				ch_slide_tgt_lo[c] = freq & 0xFF
				ch_flags1[c] |= F_SLIDE_ON
				# the following command is the note the slide applies to
			"duty":
				ch_duty[c] = (cmd[1] << 6) & 0xC0
			"tempo":
				if c < CHAN5:
					music_tempo = cmd[1]
					for i in 4:
						ch_delay_frac[i] = 0
				else:
					sfx_tempo = cmd[1]
					for i in range(4, 8):
						ch_delay_frac[i] = 0
			"pan":
				stereo_panning = cmd[1]
			"m0xef":
				_play_sound(cmd[1])
				if disable_output_when_sfx_ends == 0:
					disable_output_when_sfx_ends = ch_id[CHAN8]
					ch_id[CHAN8] = 0
			"dutypat":
				ch_dutypat[c] = cmd[1]
				ch_duty[c] = cmd[1] & 0xC0
				ch_flags1[c] |= F_ROTATE_DUTY
			"volume":
				apu.write(0xFF24, (cmd[1] << 4) | cmd[2])
			"exec":
				ch_flags2[c] |= F2_EXECUTE_MUSIC
			"octave":
				ch_octave[c] = 8 - cmd[1]
			"sq", "noise":
				if c >= CHAN4 and (ch_flags2[c] & F2_EXECUTE_MUSIC) == 0:
					_sfx_note(c, cmd)
				else:
					# the command byte $2x read as a note (D, length x+1)
					_note_length(c, cmd[1])
					_note_pitch(c, 2)
				return
			"sweep":
				if c >= CHAN5 and (ch_flags2[c] & F2_EXECUTE_MUSIC) == 0:
					apu.write(0xFF10, (cmd[1] << 4) | _fade_nibble(cmd[2]))
			"drum":
				if c == CHAN4:
					if disable_output_when_sfx_ends == 0:
						_play_sound(cmd[1])
				_note_length(c, cmd[2] - 1)
				_note_pitch(c, 0xB)
				return
			"rest":
				_note_length(c, cmd[1] - 1)
				_note_pitch(c, -1)
				return
			"note":
				_note_length(c, cmd[2] - 1)
				_note_pitch(c, cmd[1])
				return
			_:
				push_warning("audio: unhandled command " + str(cmd[0]))


## signed-magnitude nibble used by the note_type / square_note / pitch_sweep macros
func _fade_nibble(v: int) -> int:
	return v if v >= 0 else (8 | -v)


## Audio1_sound_ret; true = continue reading commands (returned from a sound_call).
func _sound_ret(c: int) -> bool:
	if ch_flags1[c] & F_SOUND_CALL:
		ch_flags1[c] &= ~F_SOUND_CALL
		ch_ptr[c] = ch_ret[c]
		return true
	if c < CHAN4:
		_disable_channel_output(c)
	else:
		ch_flags1[c] &= ~F_NOISE_OR_SFX
		ch_flags2[c] &= ~F2_EXECUTE_MUSIC
		if c == CHAN7:
			apu.write(0xFF1A, 0)
			apu.write(0xFF1A, 0x80)
			if disable_output_when_sfx_ends != 0:
				disable_output_when_sfx_ends = 0
				_disable_channel_output(c)
	if _is_cry():
		if c != CHAN5:
			# Audio1_GoBackOneCommandIfCry: stay on this sound_ret until channel 5 ends
			ch_ptr[c] -= 1
			return false
		apu.write(0xFF24, saved_volume)
		saved_volume = 0
	ch_id[c] = 0
	return false


func _disable_channel_output(c: int) -> void:
	apu.write(0xFF25, apu.nr51 & ~HW_ENABLE[c])


func _is_cry() -> bool:
	var id := ch_id[CHAN5]
	return id >= int(ranges["cry_start"]) and id < int(ranges["cry_end"])


func _is_battle_sfx() -> bool:
	var id := ch_id[CHAN8] | ch_id[CHAN5]
	return id >= int(ranges["battle_start"]) and id < int(ranges["battle_end"])


func _modifiers_apply() -> bool:
	if current_bank == 2:
		return _is_cry() or _is_battle_sfx()
	return _is_cry()


## Audio1_note_length: delay = frac + (len * speed & $ff) * tempo, 16-bit.
func _note_length(c: int, len_nibble: int) -> void:
	var a := ((len_nibble + 1) * ch_speed[c]) & 0xFF
	var tempo: int
	if c < CHAN5:
		tempo = music_tempo
	else:
		tempo = 0x0100
		if c != CHAN8:
			_set_sfx_tempo()
			tempo = sfx_tempo
	var total := ch_delay_frac[c] + a * tempo
	ch_delay_frac[c] = total & 0xFF
	ch_delay[c] = (total >> 8) & 0xFF


func _set_sfx_tempo() -> void:
	if _modifiers_apply():
		sfx_tempo = (tempo_modifier + 0x80) & 0x1FF
	else:
		sfx_tempo = 0x0100


## Audio1_note_pitch; pitch -1 = rest.
func _note_pitch(c: int, pitch: int) -> void:
	if (ch_flags2[c] & F2_EXECUTE_MUSIC) == 0 and (ch_flags1[c] & F_NOISE_OR_SFX):
		return
	if pitch < 0:
		if c < CHAN5 and ch_id[c + CHAN5] != 0:
			return
		if c == CHAN3 or c == CHAN7:
			_disable_channel_output(c)
		else:
			apu.write(HW_BASE[c] + 2, 0x08)
			apu.write(HW_BASE[c] + 4, 0x80)
		return
	var freq := _calc_frequency(pitch, ch_octave[c])
	if ch_flags1[c] & F_SLIDE_ON:
		_init_pitch_slide(c, freq)
	if c < CHAN5 and ch_id[c + CHAN5] != 0:
		return
	apu.write(HW_BASE[c] + 2, ch_volume[c])
	_apply_duty_and_length(c)
	_enable_channel_output(c)
	if ch_flags1[c] & F_PERFECT_PITCH:
		freq = (freq & 0xFF00) | ((freq + 1) & 0xFF)
	ch_freq_lo[c] = freq & 0xFF
	_apply_wave_and_frequency(c, freq)


## Audio1_CalculateFrequency: signed pitch table entry >> (7 - stored octave), high byte + 8.
func _calc_frequency(pitch: int, octave: int) -> int:
	var v := notes[pitch]
	if v >= 0x8000:
		v -= 0x10000
	var shifts := (7 - octave) & 0xFF
	v >>= mini(shifts, 31)
	return (v + 0x800) & 0xFFFF


func _apply_duty_and_length(c: int) -> void:
	var d := ch_delay[c]
	if c != CHAN3 and c != CHAN7:
		d = (d & 0x3F) | ch_duty[c]
	apu.write(HW_BASE[c] + 1, d)


func _enable_channel_output(c: int) -> void:
	var d := apu.nr51 | HW_ENABLE[c]
	if c == CHAN8 or (c < CHAN5 and ch_id[c + CHAN5] == 0):
		d = (apu.nr51 & ~HW_ENABLE[c]) | (stereo_panning & HW_ENABLE[c])
	apu.write(0xFF25, d)


func _apply_wave_and_frequency(c: int, freq: int) -> void:
	if c == CHAN3 or c == CHAN7:
		var inst := music_wave if c == CHAN3 else sfx_wave
		var w: Array = waves[mini(inst, waves.size() - 1)]
		apu.write(0xFF1A, 0)
		for i in 16:
			apu.write(0xFF30 + i, (int(w[i * 2]) << 4) | int(w[i * 2 + 1]))
		apu.write(0xFF1A, 0x80)
	var lo := freq & 0xFF
	var hi := ((freq >> 8) | 0x80) & 0xC7
	apu.write(HW_BASE[c] + 3, lo)
	apu.write(HW_BASE[c] + 4, hi)
	# Audio1_ApplyFrequencyModifier (bank 2: sfx channels only)
	if current_bank == 2 and c < CHAN5:
		return
	if _modifiers_apply():
		lo += frequency_modifier
		if lo > 0xFF:
			lo &= 0xFF
			hi = (hi + 1) & 0xFF
		apu.write(HW_BASE[c] + 3, lo)
		apu.write(HW_BASE[c] + 4, hi)


## Audio1_sfx_note: square_note / noise_note.
func _sfx_note(c: int, cmd: Array) -> void:
	_note_length(c, cmd[1])
	apu.write(HW_BASE[c] + 1, ch_delay[c] | ch_duty[c])
	apu.write(HW_BASE[c] + 2, (cmd[2] << 4) | _fade_nibble(cmd[3]))
	var freq: int = cmd[4] & 0xFF if c == CHAN8 else cmd[4]
	_apply_duty_and_length(c)
	_enable_channel_output(c)
	_apply_wave_and_frequency(c, freq)


# --- pitch slide ----------------------------------------------------------------------------------

func _init_pitch_slide(c: int, freq: int) -> void:
	ch_slide_cur_hi[c] = freq >> 8
	ch_slide_cur_lo[c] = freq & 0xFF
	var a := ch_delay[c] - ch_slide_len_mod[c]
	if a < 0:
		a = 1
	ch_slide_len_mod[c] = a & 0xFF
	var tgt := (ch_slide_tgt_hi[c] << 8) | ch_slide_tgt_lo[c]
	var e := (freq & 0xFF) - (tgt & 0xFF)
	var dd := (freq >> 8) - (1 if e < 0 else 0) - (tgt >> 8)
	var diff: int
	if dd >= 0:
		diff = (dd << 8) | (e & 0xFF)
		ch_flags1[c] |= F_SLIDE_DEC
	else:
		var e2 := (tgt & 0xFF) - (freq & 0xFF)
		# original bug: the borrow is taken from the current frequency's high byte
		var d2 := ((freq >> 8) - (1 if e2 < 0 else 0)) & 0xFF
		d2 = ((tgt >> 8) - d2) & 0xFF
		diff = (d2 << 8) | (e2 & 0xFF)
		ch_flags1[c] &= ~F_SLIDE_DEC
	var len := maxi(ch_slide_len_mod[c], 1)
	ch_slide_steps[c] = (diff / len + 1) & 0xFF
	ch_slide_steps_frac[c] = (diff % len) & 0xFF
	ch_slide_cur_frac[c] = ch_slide_steps_frac[c]


func _apply_pitch_slide(c: int) -> void:
	var d: int
	var e: int
	var reached: bool
	if ch_flags1[c] & F_SLIDE_DEC:
		e = ch_slide_cur_lo[c] - ch_slide_steps[c]
		d = ch_slide_cur_hi[c] - (1 if e < 0 else 0)
		e &= 0xFF
		var f := ch_slide_steps_frac[c] * 2
		ch_slide_steps_frac[c] = f & 0xFF
		e -= 1 if f > 0xFF else 0
		d -= 1 if e < 0 else 0
		e &= 0xFF
		d &= 0xFF
		reached = d < ch_slide_tgt_hi[c] or (d == ch_slide_tgt_hi[c] and e < ch_slide_tgt_lo[c])
	else:
		var v := ((ch_slide_cur_hi[c] << 8) | ch_slide_cur_lo[c]) + ch_slide_steps[c]
		var f := ch_slide_cur_frac[c] + ch_slide_steps_frac[c]
		ch_slide_cur_frac[c] = f & 0xFF
		if f > 0xFF:
			v += 1
		d = (v >> 8) & 0xFF
		e = v & 0xFF
		reached = ch_slide_tgt_hi[c] < d or (ch_slide_tgt_hi[c] == d and ch_slide_tgt_lo[c] < e)
	if reached:
		ch_flags1[c] &= ~(F_SLIDE_ON | F_SLIDE_DEC)
		return
	ch_slide_cur_hi[c] = d
	ch_slide_cur_lo[c] = e
	apu.write(HW_BASE[c] + 3, e)
	apu.write(HW_BASE[c] + 4, d)


# --- Audio1_PlaySound ---------------------------------------------------------------------------------

func _max_sfx_id() -> int:
	return int(ranges["max_sfx"][str(current_bank)])


## The header at this id in the current bank, as the original does. Only when the id does not
## exist in the current bank at all is the sound's own bank used (with a warning).
func _header_for(id: int) -> Dictionary:
	var table: Dictionary = banks[current_bank]
	if table.has(id):
		return table[id]
	var own: Dictionary = banks[_header_bank][id]
	if not _warned.has(own["name"]):
		_warned[own["name"]] = true
		push_warning("audio: id %d (%s) is not in bank %d, using bank %d" % [id, own["name"], current_bank, _header_bank])
	return own


func _play_sound(id: int) -> void:
	if id == SFX_STOP_ALL_MUSIC:
		_stop_all_audio()
		return
	if id > _max_sfx_id() and id < 0xFE:
		disable_output_when_sfx_ends = 0
		music_tempo = 0x0100
		music_wave = 0
		sfx_wave = 0
		for c in NUM_CHANNELS:
			ch_ret[c] = 0
			ch_ptr[c] = 0
		for c in 4:
			_reset_channel(c)
		stereo_panning = 0xFF
		apu.write(0xFF24, 0)
		apu.write(0xFF10, 0x08)
		apu.write(0xFF25, 0)
		apu.write(0xFF1A, 0)
		apu.write(0xFF1A, 0x80)
		apu.write(0xFF24, 0x77)
		_play_sound_common(id)
		return
	# sfx: channel priority, last header channel first
	var chans: Array = _header_for(id)["channels"]
	for i in range(chans.size() - 1, -1, -1):
		var e: int = chans[i][0]
		var cur := ch_id[e]
		if cur != 0:
			if e == CHAN8:
				if id < int(ranges["noise_end"]):
					return
				if cur >= int(ranges["noise_end"]) and id > cur:
					return
			elif id > cur:
				return
		ch_ret[e] = 0
		ch_ptr[e] = 0
		_reset_channel(e)
		if e == CHAN5:
			apu.write(0xFF10, 0x08)
	_play_sound_common(id)


func _reset_channel(c: int) -> void:
	ch_id[c] = 0
	ch_flags1[c] = 0
	ch_flags2[c] = 0
	ch_duty[c] = 0
	ch_dutypat[c] = 0
	ch_vib_delay[c] = 0
	ch_vib_extent[c] = 0
	ch_vib_rate[c] = 0
	ch_freq_lo[c] = 0
	ch_vib_delay_reload[c] = 0
	ch_slide_len_mod[c] = 0
	ch_slide_steps[c] = 0
	ch_slide_steps_frac[c] = 0
	ch_slide_cur_frac[c] = 0
	ch_slide_cur_hi[c] = 0
	ch_slide_cur_lo[c] = 0
	ch_slide_tgt_hi[c] = 0
	ch_slide_tgt_lo[c] = 0
	ch_loop[c] = 1
	ch_delay[c] = 1
	ch_speed[c] = 1


func _play_sound_common(id: int) -> void:
	var header := _header_for(id)
	for entry in header["channels"]:
		var e: int = entry[0]
		ch_ptr[e] = entry[1]
		ch_id[e] = id
		if e >= CHAN4:
			ch_flags1[e] |= F_NOISE_OR_SFX
	if id >= int(ranges["cry_start"]) and id < int(ranges["cry_end"]):
		for e in range(CHAN5, NUM_CHANNELS):
			ch_id[e] = id
		ch_ptr[CHAN7] = ret_cmd_index
		if saved_volume == 0:
			saved_volume = apu.nr50
			apu.write(0xFF24, 0x77)


func _stop_all_audio() -> void:
	apu.write(0xFF26, 0x80)
	apu.write(0xFF1A, 0x80)
	apu.write(0xFF25, 0)
	apu.write(0xFF1C, 0)
	apu.write(0xFF10, 0x08)
	apu.write(0xFF12, 0x08)
	apu.write(0xFF17, 0x08)
	apu.write(0xFF21, 0x08)
	apu.write(0xFF14, 0x40)
	apu.write(0xFF19, 0x40)
	apu.write(0xFF23, 0x40)
	apu.write(0xFF24, 0x77)
	disable_output_when_sfx_ends = 0
	music_tempo = 0x0100
	sfx_tempo = 0x0100
	music_wave = 0
	sfx_wave = 0
	_reset_channels_all()
	stereo_panning = 0xFF


func _reset_channels_all() -> void:
	for arr in _all_channel_arrays():
		arr.fill(0)
	ch_loop.fill(1)
	ch_delay.fill(1)
	ch_speed.fill(1)

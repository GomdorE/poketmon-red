## Game Boy picture processor stand-in: a 32x32 background map, a window map,
## 40 sprites, scroll registers and the three palette registers, drawn every
## frame from index tile sheets. Tile values are packed as (sheet_id << 16) | tile;
## value 0 is a blank white tile.
extends Node2D
class_name GBScreen

const W := 160
const H := 144
const BLANK := 0
const MAP_W := 32

class Sheet:
	var name: String
	var tpr: int       # tiles per row
	var rows: int
	var tiles: int
	var width: int
	var height: int
	var idx: PackedByteArray
	var tex: Array = [null, null, null, null]  # by flip bits: 1 = x, 2 = y

var _sheet_ids := {}
var _sheets: Array = [null]

var bg := PackedInt32Array()
var win := PackedInt32Array()
var oam: Array = []
var scx := 0
var scy := 0
var wx := 7
var wy := 144
var win_on := false
var obj_on := true
var bg_on := true
var lcd_on := true
var bgp := PackedInt32Array([0, 1, 2, 3])   # colour index -> shade
var obp0 := PackedInt32Array([0, 1, 2, 3])
var obp1 := PackedInt32Array([0, 1, 2, 3])
var row_scx := PackedInt32Array()           # optional per-screen-row SCX (18 entries)
var swap_maps := false                      # LCDC map select: the BG layer shows `win`, the window shows `bg`
var _mat: ShaderMaterial
var _pal: Array = [Color.WHITE, Color("aaaaaa"), Color("555555"), Color.BLACK]
var _blank_tex: ImageTexture   # 8x8 texture of colour index 0; every fill goes through the shader
# Super Game Boy colours: four 4-colour palettes and a palette number per screen cell
var sgb_on := false
var sgb_colors := PackedColorArray()
var attr := PackedByteArray()
var _attr_uniform := true
const SCREEN_COLS := 20
const SCREEN_ROWS := 18


func _ready() -> void:
	bg.resize(MAP_W * MAP_W)
	win.resize(MAP_W * MAP_W)
	bg.fill(BLANK)
	win.fill(BLANK)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://scripts/gb/gb_tile.gdshader")
	material = _mat
	var zeros := PackedByteArray()
	zeros.resize(64)
	_blank_tex = ImageTexture.create_from_image(Image.create_from_data(8, 8, false, Image.FORMAT_R8, zeros))
	attr.resize(SCREEN_COLS * SCREEN_ROWS)
	attr.fill(0)
	sgb_colors.resize(16)
	sgb_colors.fill(Color.WHITE)
	set_palette(GB.palette())


## Fill the screen with one shade (0-3) through the tile shader, per SGB cell when needed.
func _fill_shade(rect: Rect2, shade: int) -> void:
	if sgb_on and not _attr_uniform:
		for cy in SCREEN_ROWS:
			for cx in SCREEN_COLS:
				var m := (shade + 1) / 4.0 - attr[cy * SCREEN_COLS + cx] / 32.0
				draw_texture_rect(_blank_tex, Rect2(cx * 8, cy * 8, 8, 8), true, Color(m, m, m, m))
		return
	var m := (shade + 1) / 4.0 - _cell_pal(0, 0) / 32.0
	draw_texture_rect(_blank_tex, rect, true, Color(m, m, m, m))


func set_palette(colors: Array) -> void:
	_pal = colors
	_refresh_colors()


## The four SGB palettes (16 colours) used while sgb_on.
func set_sgb_colors(colors: PackedColorArray) -> void:
	sgb_colors = colors
	_refresh_colors()


func set_sgb_on(on: bool) -> void:
	sgb_on = on
	_refresh_colors()


func _refresh_colors() -> void:
	var cols := PackedColorArray()
	if sgb_on:
		cols = sgb_colors
	else:
		for p in 4:
			for i in 4:
				cols.append(_pal[i])
	_mat.set_shader_parameter("pal", cols)
	queue_redraw()


## SGB ATTR_BLK: entries of [regions, inside, line, outside, x1, y1, x2, y2] applied in order
## (bit 0 = inside, bit 1 = the rectangle's border line, bit 2 = outside).
func set_attr_blk(entries: Array) -> void:
	attr.fill(0)
	for e in entries:
		var regions: int = e[0]
		for y in SCREEN_ROWS:
			for x in SCREEN_COLS:
				var x1: int = e[4]
				var y1: int = e[5]
				var x2: int = e[6]
				var y2: int = e[7]
				var inside: bool = x >= x1 and y >= y1 and x <= x2 and y <= y2
				if inside:
					var on_line: bool = x == x1 or x == x2 or y == y1 or y == y2
					if on_line and regions & 2:
						attr[y * SCREEN_COLS + x] = int(e[2])
					elif not on_line and regions & 1:
						attr[y * SCREEN_COLS + x] = int(e[1])
				elif regions & 4:
					attr[y * SCREEN_COLS + x] = int(e[3])
	_attr_uniform = true
	for v in attr:
		if v != attr[0]:
			_attr_uniform = false
			break
	queue_redraw()


func _cell_pal(x: int, y: int) -> int:
	if not sgb_on or _attr_uniform:
		return attr[0] if sgb_on else 0
	var cx := clampi((x + 4) >> 3, 0, SCREEN_COLS - 1)
	var cy := clampi((y + 4) >> 3, 0, SCREEN_ROWS - 1)
	return attr[cy * SCREEN_COLS + cx]


# --- sheets -----------------------------------------------------------------

func sid(name: String) -> int:
	if _sheet_ids.has(name):
		return _sheet_ids[name]
	var tex: Texture2D = load("res://assets/gb/%s.png" % name)
	assert(tex != null, "missing tile sheet: " + name)
	var img: Image = tex.get_image()
	img.convert(Image.FORMAT_L8)
	var w := img.get_width()
	var h := img.get_height()
	var src := img.get_data()
	var s := Sheet.new()
	s.name = name
	s.width = w
	s.height = h
	s.tpr = w / 8
	s.rows = h / 8
	s.tiles = s.tpr * s.rows
	s.idx = PackedByteArray()
	s.idx.resize(w * h)
	for i in w * h:
		# exported sheets use 255 / 170 / 85 / 0 for colour 0 / 1 / 2 / 3
		s.idx[i] = 3 - int((src[i] + 42) / 85)
	var sidv := _sheets.size()
	_sheets.append(s)
	_sheet_ids[name] = sidv
	return sidv


func sheet(name: String) -> Sheet:
	return _sheets[sid(name)]


## Register an 8-bit image whose pixels are colour indices (0..3) as a sheet.
func image_sheet(name: String, img: Image) -> int:
	if _sheet_ids.has(name):
		var old: Sheet = _sheets[_sheet_ids[name]]
		old.width = img.get_width()
		old.height = img.get_height()
		old.tpr = old.width / 8
		old.rows = old.height / 8
		old.tiles = old.tpr * old.rows
		old.idx = img.get_data()
		old.tex = [null, null, null, null]
		return _sheet_ids[name]
	var s := Sheet.new()
	s.name = name
	s.width = img.get_width()
	s.height = img.get_height()
	s.tpr = s.width / 8
	s.rows = s.height / 8
	s.tiles = s.tpr * s.rows
	s.idx = img.get_data()
	var sidv := _sheets.size()
	_sheets.append(s)
	_sheet_ids[name] = sidv
	return sidv


## Index image (FORMAT_R8) of a loaded sheet.
func sheet_image(name: String) -> Image:
	var s := sheet(name)
	return Image.create_from_data(s.width, s.height, false, Image.FORMAT_R8, s.idx)


## Packed value of a solid tile of one colour index.
func solid_tile(index: int) -> int:
	var name := "solid%d" % index
	if not _sheet_ids.has(name):
		var data := PackedByteArray()
		data.resize(64)
		data.fill(index)
		image_sheet(name, Image.create_from_data(8, 8, false, Image.FORMAT_R8, data))
	return tile(name, 0)


func _tex(s: Sheet, flip: int) -> ImageTexture:
	if s.tex[flip] == null:
		var img := Image.create_from_data(s.width, s.height, false, Image.FORMAT_R8, s.idx)
		if flip & 1:
			img.flip_x()
		if flip & 2:
			img.flip_y()
		s.tex[flip] = ImageTexture.create_from_image(img)
	return s.tex[flip]


## Packed tile value for a tile of a sheet. Bits 14-15 hold flip flags
## (1 = x, 2 = y), bits 0-13 the tile index.
func tile(name: String, t: int, flip: int = 0) -> int:
	return (sid(name) << 16) | (flip << 14) | t


## Packed tile for the 8x8 cell (col, row) of a picture sheet (e.g. 7x7 pics).
func pic_tile(name: String, col: int, row: int, flip: int = 0) -> int:
	var s := sheet(name)
	return (sid(name) << 16) | (flip << 14) | (row * s.tpr + col)


## Colour index of a pixel inside a packed tile (used for priority tests).
func tile_pixel(v: int, x: int, y: int) -> int:
	if v == BLANK:
		return 0
	var s: Sheet = _sheets[v >> 16]
	var t := v & 0x3FFF
	var flip := (v >> 14) & 3
	if flip & 1:
		x = 7 - x
	if flip & 2:
		y = 7 - y
	var px := (t % s.tpr) * 8 + x
	var py := (t / s.tpr) * 8 + y
	return s.idx[py * s.width + px]


# --- maps -------------------------------------------------------------------

func set_bg(x: int, y: int, v: int) -> void:
	bg[(y & 31) * MAP_W + (x & 31)] = v


func get_bg(x: int, y: int) -> int:
	return bg[(y & 31) * MAP_W + (x & 31)]


func fill_bg(x: int, y: int, w: int, h: int, v: int) -> void:
	for j in h:
		for i in w:
			bg[((y + j) & 31) * MAP_W + ((x + i) & 31)] = v


func clear_bg(v: int = BLANK) -> void:
	bg.fill(v)


func set_win(x: int, y: int, v: int) -> void:
	win[(y & 31) * MAP_W + (x & 31)] = v


func fill_win(x: int, y: int, w: int, h: int, v: int) -> void:
	for j in h:
		for i in w:
			win[((y + j) & 31) * MAP_W + ((x + i) & 31)] = v


func clear_win(v: int = BLANK) -> void:
	win.fill(v)


## Copy the visible 20x18 screen area of the background map into the window map.
func copy_bg_to_win() -> void:
	for y in 18:
		for x in 20:
			win[y * MAP_W + x] = bg[y * MAP_W + x]


func snapshot_bg() -> PackedInt32Array:
	return bg.duplicate()


func restore_bg(saved: PackedInt32Array) -> void:
	bg = saved.duplicate()


# --- sprites ----------------------------------------------------------------

## Add or replace a sprite. Coordinates are screen pixels of the top-left corner.
func set_sprite(i: int, x: int, y: int, v: int, pal: int = 0, xflip: bool = false, yflip: bool = false, prio: bool = false) -> void:
	while oam.size() <= i:
		oam.append(null)
	oam[i] = {"x": x, "y": y, "v": v, "pal": pal, "xflip": xflip, "yflip": yflip, "prio": prio}


func clear_sprites() -> void:
	oam.clear()


# --- palettes ---------------------------------------------------------------

## Palette from a hardware register byte (bits 7-6 = colour 3 ... bits 1-0 = colour 0).
static func pal_byte(b: int) -> PackedInt32Array:
	return PackedInt32Array([b & 3, (b >> 2) & 3, (b >> 4) & 3, (b >> 6) & 3])


## Palette in the disassembly's `dc c3, c2, c1, c0` order.
static func pal(c3: int, c2: int, c1: int, c0: int) -> PackedInt32Array:
	return PackedInt32Array([c0, c1, c2, c3])


func set_all_pals(p: PackedInt32Array) -> void:
	bgp = p
	obp0 = p
	obp1 = p


func white_out() -> void:
	set_all_pals(PackedInt32Array([0, 0, 0, 0]))


## wMapPalOffset (home/fade.asm LoadGBPal): 0 = FadePal4 (the normal palettes), 6 = FadePal2
## (a dark cave before Flash: BG nearly black, sprites black silhouettes).
var pal_offset := 0


func normal_pals() -> void:
	if pal_offset == 6:
		bgp = pal(3, 3, 3, 2)
		obp0 = pal(3, 3, 3, 2)
		obp1 = pal(3, 3, 2, 0)
		return
	set_all_pals(PackedInt32Array([0, 1, 2, 3]))


# --- drawing ----------------------------------------------------------------

static func _mod(map: PackedInt32Array, transparent0: bool, p: int = 0) -> Color:
	var d := p / 32.0
	return Color(
		0.0 if transparent0 else (map[0] + 1) / 4.0 - d,
		(map[1] + 1) / 4.0 - d,
		(map[2] + 1) / 4.0 - d,
		(map[3] + 1) / 4.0 - d)


## The modulate colours of a palette register for the four SGB palettes.
static func _mods(map: PackedInt32Array, transparent0: bool) -> Array:
	return [_mod(map, transparent0, 0), _mod(map, transparent0, 1), _mod(map, transparent0, 2), _mod(map, transparent0, 3)]


func _draw() -> void:
	if not lcd_on:
		_fill_shade(Rect2(0, 0, W, H), 0)
		return
	_fill_shade(Rect2(0, 0, W, H), bgp[0])
	var has_prio := false
	for s in oam:
		if s != null and s.prio:
			has_prio = true
			break
	if bg_on:
		_draw_bg(false)
	if win_on:
		_draw_window(false)
	if obj_on and has_prio:
		_draw_sprites(true)
		if bg_on:
			_draw_bg(true)
		if win_on:
			_draw_window(true)
	if obj_on:
		_draw_sprites(false)


func _draw_tile(v: int, x: int, y: int, mods: Array, flip: int = 0) -> void:
	var mod: Color = mods[_cell_pal(x, y)]
	if v == BLANK:
		if mod.r >= 0.125:
			draw_texture_rect(_blank_tex, Rect2(x, y, 8, 8), false, mod)
		return
	var s: Sheet = _sheets[v >> 16]
	var t := v & 0x3FFF
	flip ^= (v >> 14) & 3
	var cx := t % s.tpr
	var cy := t / s.tpr
	if flip & 1:
		cx = s.tpr - 1 - cx
	if flip & 2:
		cy = s.rows - 1 - cy
	draw_texture_rect_region(_tex(s, flip), Rect2(x, y, 8, 8), Rect2(cx * 8, cy * 8, 8, 8), mod)


func _draw_bg(transparent0: bool) -> void:
	var mods := _mods(bgp, transparent0)
	var map := win if swap_maps else bg
	var use_rows := row_scx.size() >= 18
	for j in 19:
		var sx := row_scx[mini(j, 17)] if use_rows else scx
		var y := j * 8 - (scy & 7)
		var my := ((scy >> 3) + j) & 31
		for i in 21:
			var x := i * 8 - (sx & 7)
			if x >= W:
				continue
			var mx := ((sx >> 3) + i) & 31
			_draw_tile(map[my * MAP_W + mx], x, y, mods)


func _draw_window(transparent0: bool) -> void:
	if wy >= H or wx >= W + 7:
		return
	var mods := _mods(bgp, transparent0)
	var map := bg if swap_maps else win
	var ox := wx - 7
	var j := 0
	var y := wy
	while y < H:
		var x := ox
		var i := 0
		while x < W and i < MAP_W:
			_draw_tile(map[j * MAP_W + i], x, y, mods)
			x += 8
			i += 1
		y += 8
		j += 1


func _draw_sprites(prio_pass: bool) -> void:
	for n in range(oam.size() - 1, -1, -1):
		var s = oam[n]
		if s == null or s.prio != prio_pass:
			continue
		if s.y <= -8 or s.y >= H or s.x <= -8 or s.x >= W:
			continue
		var map := obp1 if s.pal == 1 else obp0
		var flip := (1 if s.xflip else 0) | (2 if s.yflip else 0)
		_draw_tile(s.v, s.x, s.y, _mods(map, true), flip)

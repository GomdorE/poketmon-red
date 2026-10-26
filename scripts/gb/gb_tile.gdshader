// Draws Game Boy tiles. The texture holds colour indices 0..3 in its red
// channel (value / 255). The per-draw modulate colour carries the palette
// register and the Super Game Boy palette number: component n =
// (shade + 1) / 4 - sgb_palette / 32 for index n, or 0 for transparent.
// pal[sgb_palette * 4 + shade] is the final colour (all four palettes are the
// same when running without SGB colours).
shader_type canvas_item;

uniform vec4 pal[16];

varying vec4 v_map;

void vertex() {
	v_map = COLOR;
}

void fragment() {
	float idx = floor(texture(TEXTURE, UV).r * 255.0 + 0.5);
	float m = idx < 0.5 ? v_map.r : (idx < 1.5 ? v_map.g : (idx < 2.5 ? v_map.b : v_map.a));
	if (m < 0.125) {
		discard;
	}
	float level = ceil(m * 4.0 - 0.02);
	float p = floor((level * 0.25 - m) * 32.0 + 0.5);
	int i = int(clamp(p, 0.0, 3.0)) * 4 + int(clamp(level - 1.0, 0.0, 3.0));
	COLOR = pal[i];
}

shader_type canvas_item;

// The menu's background patterns (Settings > Menu Customizer, WaveMenuBG.gd),
// besides the contour lines (wave_menu.shader). Three colours: the background,
// the lines and an accent; speed 0 stands still.
// pattern: 0 grid, 1 dots, 2 waves, 3 hexagons, 4 stripes, 5 stars, 6 plain

uniform int pattern = 0;
uniform vec4 c_bg : hint_color = vec4(0.07, 0.03, 0.08, 1.0);
uniform vec4 c_line : hint_color = vec4(0.46, 0.2, 0.42, 1.0);
uniform vec4 c_accent : hint_color = vec4(1.0, 0.45, 0.62, 1.0);
uniform float speed = 1.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
vec2 hash2(vec2 p) { return vec2(hash(p), hash(p + vec2(17.3, 9.1))); }

// how much of a line of `width` pixels covers this pixel; d in the same units as v
float line_at(float d, float v_fw, float width) {
	float px = d / max(v_fw, 0.00001);
	return 1.0 - smoothstep(width - 0.75, width + 0.75, px);
}

float hex_dist(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

void fragment() {
	float t = TIME * speed;
	float sh = 1.0 / SCREEN_PIXEL_SIZE.y; // the screen's height in pixels
	vec2 px = FRAGCOORD.xy;
	vec2 p = px / sh * 12.0; // about 12 cells up the screen
	vec3 bg = c_bg.rgb;
	// (a soft light from the top so the plain colour isn't flat)
	bg = mix(bg, bg * 1.35 + vec3(0.01), smoothstep(0.0, 1.0, px.y / sh));
	vec3 col = bg;

	if (pattern == 0) {
		// grid drifting on a slant; every 4th line bright, a glow sweeping along it
		vec2 q = p + vec2(t * 0.35, t * 0.2);
		vec2 g = abs(fract(q + 0.5) - 0.5);
		float fw = fwidth(q.x);
		float minor = line_at(min(g.x, g.y), fw, 0.9);
		vec2 q4 = q / 4.0;
		vec2 g4 = abs(fract(q4 + 0.5) - 0.5);
		float major = line_at(min(g4.x, g4.y), fwidth(q4.x), 1.4);
		float sweep = 0.5 + 0.5 * sin((q.x + q.y) * 0.25 - t * 1.5);
		col = mix(col, c_line.rgb, minor * 0.75);
		col = mix(col, mix(c_line.rgb, c_accent.rgb, sweep), major);
	} else if (pattern == 1) {
		// dots pulsing in a ripple from the middle
		vec2 q = p + vec2(0.0, t * 0.15);
		vec2 id = floor(q);
		vec2 f = fract(q) - 0.5;
		float ripple = 0.5 + 0.5 * sin(length(id - vec2(12.0, 6.0)) * 0.55 - t * 2.2);
		float r = 0.08 + 0.13 * ripple;
		float d = length(f);
		float dot_cov = 1.0 - smoothstep(r - fwidth(q.x), r + fwidth(q.x), d);
		col = mix(col, mix(c_line.rgb, c_accent.rgb, ripple * ripple), dot_cov);
	} else if (pattern == 2) {
		// flowing wave lines, the colour changing across the screen
		float v = p.y * 0.5 + sin(p.x * 0.35 + t * 0.8) * 0.45 + sin(p.x * 0.17 - t * 0.5 + p.y * 0.1) * 0.6;
		float d = abs(fract(v + 0.5) - 0.5);
		float ln = line_at(d, fwidth(v), 1.3);
		float band = floor(v + 0.5);
		float k = 0.5 + 0.5 * sin(band * 0.9 + p.x * 0.08 + t * 0.4);
		col = mix(col, mix(c_line.rgb, c_accent.rgb, k), ln);
		col = mix(col, c_line.rgb, 0.06 * (0.5 + 0.5 * sin(band * 1.7)));
	} else if (pattern == 3) {
		// honeycomb; a few cells light up and fade
		vec2 uv = p * 0.8 + vec2(t * 0.1, 0.0);
		vec2 rr = vec2(1.0, 1.7320508);
		vec2 h = rr * 0.5;
		vec2 a = mod(uv, rr) - h;
		vec2 b = mod(uv - h, rr) - h;
		vec2 gv = dot(a, a) < dot(b, b) ? a : b;
		vec2 id = uv - gv;
		float edge = 0.5 - hex_dist(gv);
		float ln = line_at(edge, fwidth(uv.x), 0.9);
		float glow = pow(max(0.0, sin(hash(floor(id * 2.0)) * 6.283 + t * 0.9)), 6.0);
		col = mix(col, mix(bg, c_accent.rgb, 0.35), glow * (1.0 - ln));
		col = mix(col, c_line.rgb, ln);
	} else if (pattern == 4) {
		// wide diagonal stripes sliding by, a thin accent line between
		float v = (p.x + p.y) * 0.18 - t * 0.25;
		float f = fract(v);
		col = mix(bg, mix(bg, c_line.rgb, 0.28), step(0.5, f));
		float d = min(abs(f - 0.5), min(f, 1.0 - f));
		col = mix(col, c_accent.rgb, line_at(d, fwidth(v), 0.8) * 0.8);
	} else if (pattern == 5) {
		// stars in three layers drifting at different speeds, twinkling
		for (int layer = 0; layer < 3; layer++) {
			float fl = float(layer);
			float sc = 1.0 + fl * 0.8;
			vec2 uv = p * sc * 0.6 + vec2(t * (0.08 + fl * 0.07), fl * 13.7);
			vec2 id = floor(uv);
			vec2 f = fract(uv);
			float h = hash(id + fl * 3.1);
			if (h > 0.3) {
				vec2 sp = 0.15 + 0.7 * hash2(id + fl);
				float d = length(f - sp) / max(fwidth(uv.x), 0.00001);
				float tw = 0.55 + 0.45 * sin(t * (1.5 + h * 3.0) + h * 40.0);
				float size = 1.3 + 2.2 * (1.0 - fl / 2.0) * h;
				float s = exp(-d * d / (size * size)) * tw;
				col += mix(mix(c_line.rgb, vec3(1.0), 0.35), c_accent.rgb, step(0.8, h)) * s * (1.6 - fl * 0.4);
			}
		}
	}
	// pattern 6 (plain): just the background
	COLOR = vec4(col, 1.0);
}

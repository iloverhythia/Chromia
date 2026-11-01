shader_type canvas_item;
// The map editor track's background and waveform in one quad (SSQETrack.gd):
// for each pixel column, which waveform bar is there and how far it reaches,
// read from the levels SSQEAudio worked out on its thread (L = lowest,
// A = highest, a level for each zoom). Nothing is built while you play,
// scroll or zoom: only these numbers change.

uniform sampler2D data;
uniform float on = 0.0;        // 0: just the background (waveform off / not ready)
uniform float tex_w = 2048.0;
uniform float tex_h = 1.0;
uniform float row0 = 0.0;      // the level's first row
uniform float count = 0.0;     // bars in the level
uniform float origin = 0.0;    // where bar 0 is, px from the left of the track
uniform float step = 1.0;      // px from one bar to the next (1 or more)
uniform float width = 1.0;     // the track, px
uniform float height = 1.0;
uniform float classic = 0.0;   // the one peak line of the original SSQE
uniform vec4 tint : hint_color = vec4(1.0);
uniform vec4 bg : hint_color = vec4(0.153, 0.153, 0.153, 1.0);

vec2 bar_at(float e) {
	float row = floor(e / tex_w);
	float col = e - row * tex_w;
	vec4 t = texture(data, vec2((col + 0.5) / tex_w, (row0 + row + 0.5) / tex_h));
	return vec2(t.r, t.a) * 2.0 - 1.0; // (lowest, highest), -1..1
}

void fragment() {
	COLOR = bg;
	if (on > 0.5) {
		float x = UV.x * width;
		float y = UV.y * height;
		float e = floor((x - origin) / step);
		if (e >= 0.0 && e < count) {
			// zoomed in, bars are more than a pixel apart: the shape between two
			// of them is blended, so it reads as one wave instead of a comb
			float f = clamp((x - (origin + e * step)) / step, 0.0, 1.0);
			float slope = 1.0 / step; // (the blend's change over one pixel)
			vec2 v = bar_at(e);
			vec2 w = bar_at(min(e + 1.0, count - 1.0));
			float hit = 0.0;
			if (classic > 0.5) {
				// the original SSQE's one peak line
				float y0 = (1.0 - max(abs(v.x), abs(v.y))) * height;
				float y1 = (1.0 - max(abs(w.x), abs(w.y))) * height;
				float yc = mix(y0, y1, f);
				float reach = max(0.6, abs(y1 - y0) * slope * 0.5);
				hit = abs(y - yc) <= reach ? 1.0 : 0.0;
			} else if (step < 2.0) {
				// an upright bar from the lowest to the highest point (each bar
				// already reaches its neighbour's first point, so they join up)
				float lo = (v.x + 1.0) * 0.5 * height;
				float hi = (v.y + 1.0) * 0.5 * height;
				hit = (y >= lo - 0.5 && y <= hi + 0.5) ? 1.0 : 0.0;
			} else {
				// zoomed in: from one bar to the next, so the wave reads as a line
				float lo = mix((v.x + 1.0) * 0.5 * height, (w.x + 1.0) * 0.5 * height, f);
				float hi = mix((v.y + 1.0) * 0.5 * height, (w.y + 1.0) * 0.5 * height, f);
				hit = (y >= lo - 0.5 && y <= hi + 0.5) ? 1.0 : 0.0;
			}
			if (hit > 0.0) {
				COLOR = vec4(mix(bg.rgb, tint.rgb, tint.a), max(bg.a, tint.a));
			}
		}
	}
}

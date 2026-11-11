shader_type canvas_item;
// The patterned looks of the song HUD's side panels (HudPanels.gd). Works on
// GLES2 too (floats only, no int maths).

uniform float mode = 1.0;
uniform vec4 accent : hint_color = vec4(1.0, 0.76, 0.96, 1.0);
uniform vec4 base : hint_color = vec4(0.0, 0.0, 0.0, 0.6);
uniform vec2 size = vec2(300.0, 900.0);

vec3 hue(float h) {
	vec3 k = clamp(abs(mod(h * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
	return k;
}

// distance to a rounded box inset from the edges (< 0 inside)
float box(vec2 px, float inset, float r) {
	vec2 q = abs(px - size * 0.5) - (size * 0.5 - vec2(inset + r));
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * size;
	float sd = box(px, 4.0, 24.0);
	float inside = clamp(0.5 - sd, 0.0, 1.0);
	vec4 c = base;
	if (mode < 1.5) { // gradient: your accent fading into the dark
		c = vec4(mix(accent.rgb * 0.85, base.rgb, smoothstep(0.0, 1.0, UV.y)), mix(0.75, base.a, UV.y));
	} else if (mode < 2.5) { // sunset
		vec3 a = mix(vec3(1.0, 0.36, 0.62), vec3(1.0, 0.62, 0.26), smoothstep(0.0, 0.5, UV.y));
		c = vec4(mix(a, vec3(0.32, 0.13, 0.52), smoothstep(0.45, 1.0, UV.y)), 0.78);
	} else if (mode < 3.5) { // ocean
		vec3 a = mix(vec3(0.15, 0.85, 0.9), vec3(0.06, 0.32, 0.62), smoothstep(0.0, 0.55, UV.y));
		c = vec4(mix(a, vec3(0.02, 0.06, 0.2), smoothstep(0.5, 1.0, UV.y)), 0.78);
	} else if (mode < 4.5) { // rainbow border, slowly turning
		vec2 p = px - size * 0.5;
		vec3 h = hue(fract(atan(p.y, p.x) / 6.28318 + TIME * 0.12));
		float band = clamp(sd + 7.5, 0.0, 1.0);
		c = vec4(mix(base.rgb, h, band), mix(base.a, 1.0, band));
	} else if (mode < 5.5) { // corner brackets
		float cx = min(px.x, size.x - px.x);
		float cy = min(px.y, size.y - px.y);
		float on = 0.0;
		if ((cx >= 8.0 && cx < 15.0 && cy >= 8.0 && cy < 80.0) || (cy >= 8.0 && cy < 15.0 && cx >= 8.0 && cx < 80.0)) {
			on = 1.0;
		}
		c = vec4(mix(base.rgb, accent.rgb, on), mix(base.a * 0.6, 1.0, on));
		inside = 1.0;
	} else if (mode < 6.5) { // diagonal stripes
		float s = step(0.5, fract((px.x + px.y) / 30.0));
		c = vec4(mix(base.rgb, accent.rgb, s * 0.16), base.a);
		float band = clamp(sd + 4.5, 0.0, 1.0);
		c = mix(c, vec4(accent.rgb, 1.0), band);
	} else if (mode < 7.5) { // CRT scanlines
		float line = 0.7 + 0.3 * sin(px.y * 0.8);
		vec2 v = UV - 0.5;
		float vig = 1.0 - dot(v * vec2(1.2, 0.7), v * vec2(1.2, 0.7)) * 1.6;
		c = vec4(mix(base.rgb, accent.rgb * 0.35, 0.5) * line * vig, max(base.a, 0.7));
	} else if (mode < 8.5) { // dots
		vec2 g = fract(px / 22.0) - 0.5;
		float d = 1.0 - smoothstep(0.1, 0.17, length(g));
		c = vec4(mix(base.rgb, accent.rgb, d * 0.5), base.a);
	} else if (mode < 9.5) { // hologram: cyan, a light band running down
		float y = fract(TIME * 0.22);
		float dy = (UV.y - y) * 10.0;
		float band = exp(-dy * dy) * 0.35;
		float line = 0.85 + 0.15 * sin(px.y * 0.6);
		float edge = exp(max(sd, -200.0) / 16.0) * 0.7;
		vec3 cy = vec3(0.35, 0.95, 1.0);
		c = vec4(cy * line, (0.16 + band) * line + edge);
	} else if (mode < 10.5) { // carbon fibre
		vec2 cell = floor(px / 12.0);
		vec2 f = fract(px / 12.0);
		float k = mod(cell.x + cell.y, 2.0);
		float shade = mix(f.x, f.y, k);
		float g = 0.025 + 0.05 * (0.5 + 0.5 * sin(shade * 3.14159));
		c = vec4(vec3(g), 0.93);
		float band = clamp(sd + 3.5, 0.0, 1.0);
		c = mix(c, vec4(accent.rgb, 1.0), band * 0.8);
	} else if (mode < 11.5) { // soft glow from the edges
		float glow = exp(min(sd, 0.0) / 34.0);
		c = vec4(mix(base.rgb, accent.rgb, glow * 0.85), max(base.a, glow * 0.9));
	} else { // aurora: slow moving colours
		float t = TIME * 0.18;
		float w1 = 0.5 + 0.5 * sin(UV.y * 5.0 + t * 3.0 + sin(UV.x * 3.0 + t) * 1.5);
		float w2 = 0.5 + 0.5 * sin(UV.y * 3.0 - t * 2.0 + 2.0);
		vec3 col = mix(vec3(0.1, 0.85, 0.55), vec3(0.55, 0.3, 1.0), w1);
		col = mix(col, vec3(0.15, 0.4, 0.95), w2 * 0.5);
		c = vec4(mix(base.rgb, col, 0.7), 0.8);
	}
	COLOR = vec4(c.rgb, c.a * inside);
}

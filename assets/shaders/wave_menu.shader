shader_type canvas_item;

// Animated topographic / contour-line background ("Wave menu").
// A smooth height field made of layered waves; lines are drawn where the
// height crosses evenly spaced levels, like the lines on a hiking map.

uniform float speed = 0.12;
uniform float scale = 5.0;          // how zoomed-in the pattern is (bigger = more hills on screen)
uniform float levels = 9.0;        // lines per unit of height
uniform vec4 bg_color : hint_color = vec4(0.13, 0.025, 0.03, 1.0);
uniform vec4 minor_color : hint_color = vec4(0.62, 0.16, 0.16, 0.75);
uniform vec4 major_a : hint_color = vec4(1.0, 0.36, 0.45, 1.0);  // pink
uniform vec4 major_b : hint_color = vec4(1.0, 0.42, 0.27, 1.0);  // orange

float height(vec2 p, float t) {
	float h = 0.0;
	h += sin(p.x * 1.10 + t * 0.9) * cos(p.y * 0.95 - t * 0.7);
	h += 0.65 * sin(p.x * 0.63 - p.y * 1.27 + t * 0.5);
	h += 0.45 * cos(p.x * 1.71 + p.y * 0.52 - t * 0.6);
	h += 0.30 * sin(length(p - vec2(2.5 + sin(t * 0.3), 1.2)) * 1.9 - t);
	return h;
}

void fragment() {
	float t = TIME * speed * 6.0;
	// Scale by screen height so the pattern keeps its shape on any window size.
	vec2 p = FRAGCOORD.xy * SCREEN_PIXEL_SIZE.y * scale;
	float h = height(p, t) * levels * 0.35;

	float w = max(fwidth(h), 0.0001);
	float idx = floor(h + 0.5);
	float dist = abs(h - idx) / w;            // distance to nearest line, in pixels

	bool major = mod(idx, 4.0) == 0.0;
	float width = major ? 3.4 : 0.7;
	float line = 1.0 - smoothstep(width - 0.75, width + 0.75, dist);

	vec4 col = bg_color;
	if (major) {
		vec4 mc = mod(idx, 8.0) == 0.0 ? major_a : major_b;
		col = mix(col, mc, line);
	} else {
		col = mix(col, minor_color, line * minor_color.a);
	}
	COLOR = vec4(col.rgb, 1.0);
}

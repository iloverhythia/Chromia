// Unshaded textured surface matching Rhythia's (Godot 4) StandardMaterial3D
// settings used by its spaces: albedo texture x color, UV scale/offset,
// "pixel alpha" distance fade, and depth fog. Godot 3 doesn't fog unshaded
// materials, so the fog is done here: mixed toward fog_color with distance.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_opaque;

uniform vec4 albedo : hint_color = vec4(1.0);
uniform sampler2D tex : hint_albedo;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform bool use_alpha = false;      // "transparency = alpha": use the texture's alpha
uniform float opacity = 1.0;         // GeometryInstance3D.transparency (1 - it)
uniform bool fade_on = false;        // distance_fade_mode = pixel alpha
uniform float fade_min = 0.0;        // invisible at/inside this distance...
uniform float fade_max = 10.0;       // ...fully visible here (reversed when min > max)
uniform bool fog_on = false;
uniform vec4 fog_color : hint_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float fog_begin = 10.0;
uniform float fog_end = 100.0;
uniform float fog_curve = 1.0;
uniform float fog_density = 1.0;

void fragment() {
	vec4 t = texture(tex, UV * uv_scale + uv_offset);
	vec3 col = t.rgb * albedo.rgb;
	float a = (use_alpha ? t.a * albedo.a : 1.0) * opacity;
	float d = length(VERTEX);
	if (fade_on) {
		if (fade_min <= fade_max) {
			a *= smoothstep(fade_min, fade_max, d);
		} else {
			a *= 1.0 - smoothstep(fade_max, fade_min, d);
		}
	}
	if (fog_on) {
		// Godot 4's depth fog: smoothstep over begin..end, then ^curve x density
		float f = pow(smoothstep(fog_begin, fog_end, d), fog_curve) * fog_density;
		col = mix(col, fog_color.rgb, clamp(f, 0.0, 1.0));
	}
	ALBEDO = col;
	if (use_alpha || fade_on || opacity < 1.0) {
		ALPHA = a;
	}
}

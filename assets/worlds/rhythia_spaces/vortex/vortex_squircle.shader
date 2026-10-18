shader_type spatial;
// Unshaded transparent squircle with Rhythia Vortex's depth fog baked in
// (Godot 4 depth fog: begin 0, end 950, curve 0.5176, colour black).
// dist_scale undoes the scale applied to bring the quads inside the camera's
// far plane, so the fog uses the original distances.
render_mode unshaded, cull_disabled, blend_mix, shadows_disabled;

uniform vec4 color : hint_color = vec4(1.0);
uniform sampler2D tex : hint_albedo;
uniform float dist_scale = 1.0;

void fragment() {
	vec4 t = texture(tex, UV);
	float f = pow(smoothstep(0.0, 950.0, length(VERTEX) * dist_scale), 0.5176324);
	ALBEDO = color.rgb * t.rgb * (1.0 - f);
	ALPHA = color.a * t.a;
}

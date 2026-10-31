shader_type spatial;
// The VR menu screen (MenuPointer.gd): the menu, drawn into a viewport, shown
// on the big screen in front of you. The viewport has no mipmaps, so where
// the screen shows the picture smaller than it is (further away, at an angle,
// near the edges of the curve) plain sampling skipped texels and the text
// looked jagged and shimmered. This averages four samples spread over the
// area one screen pixel covers instead.
render_mode unshaded, cull_disabled, shadows_disabled;

uniform sampler2D menu : hint_albedo;

vec3 to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec2 dx = dFdx(UV) * 0.25;
	vec2 dy = dFdy(UV) * 0.25;
	vec3 c = texture(menu, UV + dx + dy).rgb
		+ texture(menu, UV + dx - dy).rgb
		+ texture(menu, UV - dx + dy).rgb
		+ texture(menu, UV - dx - dy).rgb;
	// (the menu is drawn in sRGB, like the material this replaces assumed)
	ALBEDO = to_linear(c * 0.25);
}

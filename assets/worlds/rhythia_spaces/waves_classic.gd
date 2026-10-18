extends "res://assets/worlds/rhythia_spaces/rhythia_space.gd"
# Rhythia "Waves": a dark rolling ocean under a night sky. The map cover hangs
# in the sky (with its reflection in the water); ripples ("echo") build up over
# the first seconds. With background effects disabled the cover is hidden.

const WATER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque, shadows_disabled;
uniform vec4 tint : hint_color = vec4(0.5, 0.7, 1.0, 1.0);
uniform vec4 deep : hint_color = vec4(0.01, 0.015, 0.035, 1.0);
uniform float echo = 0.0;
varying float h;
varying vec3 lp;
void vertex() {
	vec2 p = VERTEX.xz;
	float t = TIME;
	h = sin(p.x * 0.35 + t * 1.1) * 0.5
	  + sin(p.y * 0.27 - t * 1.6 + p.x * 0.12) * 0.6
	  + sin((p.x + p.y) * 0.7 + t * 2.3) * 0.25;
	VERTEX.y += h * 0.55;
	lp = VERTEX;
}
void fragment() {
	float crest = smoothstep(0.55, 1.25, h);
	float r = length(lp.xz - vec2(0.0, -25.0));
	float ripple = smoothstep(0.9, 1.0, sin(r * 0.9 - TIME * 2.5)) * echo * smoothstep(60.0, 5.0, r);
	float far = smoothstep(10.0, 60.0, -lp.z);
	vec3 c = deep.rgb + tint.rgb * (crest * 0.45 + ripple * 0.7) * (1.0 - far * 0.6);
	ALBEDO = c;
	ALPHA = 0.86;
}
"""
const COVER_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D image_a : hint_albedo;
uniform float has_image = 1.0;
uniform float coverage = 1.0;
uniform float strength = 1.0;
uniform vec4 glow_col : hint_color = vec4(0.55, 0.6, 0.9, 1.0);
void fragment() {
	vec2 c = UV - 0.5;
	float img_mask = 1.0 - smoothstep(0.30, 0.5, max(abs(c.x), abs(c.y)));
	vec3 img = texture(image_a, UV).rgb * img_mask * has_image;
	float d = length(c);
	vec3 halo = glow_col.rgb * (1.0 - smoothstep(0.0, 0.5, d)) * (1.0 - has_image * 0.6) * 0.5;
	ALBEDO = (img * 0.9 + halo) * coverage * strength;
}
"""
var water_mat: ShaderMaterial
var sky_mat: ShaderMaterial
var refl_mat: ShaderMaterial

func _build():
	env.background_color = Color(0.008, 0.01, 0.025)
	var wsh := Shader.new()
	wsh.code = WATER_SHADER
	water_mat = ShaderMaterial.new()
	water_mat.shader = wsh
	var pm := PlaneMesh.new()
	pm.size = Vector2(140, 100)
	pm.subdivide_width = 47
	pm.subdivide_depth = 39
	var water := MeshInstance.new()
	water.name = "Water"
	water.mesh = pm
	water.material_override = water_mat
	water.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	water.translation = Vector3(0, -3.5, -45)
	add_child(water)

	var csh := Shader.new()
	csh.code = COVER_SHADER
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = csh
	var show_cover = cover != null and space_effects
	if show_cover:
		sky_mat.set_shader_param("image_a", cover)
	sky_mat.set_shader_param("has_image", 1.0 if show_cover else 0.0)
	refl_mat = sky_mat.duplicate()
	refl_mat.set_shader_param("strength", 0.35)
	var size = 40.0
	var y_sky = 20.0
	add_quad(self, Vector2(size, size), sky_mat, Vector3(0, y_sky, -85))
	# mirrored copy below the water surface acts as its reflection
	var water_y = -3.5
	add_quad(self, Vector2(size, size), refl_mat, Vector3(0, water_y - (y_sky - water_y), -85), Vector3(180, 0, 0))

	# a sprinkling of stars
	var stars := CPUParticles.new()
	var smat := make_unshaded(Color(1, 1, 1), dot_texture(32, 0.2), true)
	smat.vertex_color_use_as_albedo = true
	smat.params_billboard_mode = SpatialMaterial.BILLBOARD_ENABLED
	var q := QuadMesh.new()
	q.size = Vector2(0.35, 0.35)
	q.material = smat
	stars.mesh = q
	stars.amount = 120
	stars.lifetime = 8.0
	stars.preprocess = 8.0
	stars.emission_shape = CPUParticles.EMISSION_SHAPE_BOX
	stars.emission_box_extents = Vector3(110, 25, 4)
	stars.translation = Vector3(0, 30, -95)
	stars.gravity = Vector3()
	stars.initial_velocity = 0.0
	stars.scale_amount_random = 0.8
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.5, Color(0.8, 0.85, 1, 1))
	stars.color_ramp = g
	add_child(stars)

func _tick(_delta):
	water_mat.set_shader_param("echo", min(0.5, time / 24.0))
	var t = Color(0.45, 0.6, 1.0).linear_interpolate(note_hit_color, 0.5)
	water_mat.set_shader_param("tint", t)

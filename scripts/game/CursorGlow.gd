extends Node

# Cursor Bloom (Settings > World & Cursor > Cursor): the engine's own bloom
# (the same Glow the worlds use), on the cursor only. The cursor (and its
# trail, if you want) is drawn a second time, full size, by its own camera
# into an off-screen view whose environment has Glow on in "replace" mode, so
# that view holds just the cursor's bloom. That is added on top of the screen.
# Nothing else blooms.
#
# Cursor.gd adds it when the setting is on.

const LAYER_BIT := 19                # render layer 20: only what should bloom
const PULSE_DECAY := 5.0             # how quickly a hit pulse fades (per second)

# the bloom view added onto the screen (optionally tinted)
const ADD_SHADER := """
shader_type canvas_item;
render_mode blend_add;
uniform float use_tint = 0.0;
uniform float intensity = 1.0;
uniform vec4 tint : hint_color = vec4(1.0);
// the wide haze, worked out per pixel so it's perfectly round (the engine's
// widest glow levels are blurred at a very low resolution and come out square)
uniform vec2 center = vec2(0.5);      // the cursor, 0..1 across the screen
uniform float aspect = 1.0;           // screen width / height
uniform float radius = 0.05;          // in screen heights
uniform vec3 haze_col = vec3(1.0);
uniform float haze = 0.0;             // 0 = none (cursor hidden)
void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	vec2 d = UV - center;
	d.x *= aspect;
	float r2 = dot(d, d) / (radius * radius);
	// soft layers, each twice as wide and fainter: a bright middle with a
	// long, slow falloff
	float h = 0.40 * exp(-r2) + 0.25 * exp(-r2 / 4.0) + 0.15 * exp(-r2 / 16.0)
		+ 0.08 * exp(-r2 / 64.0) + 0.04 * exp(-r2 / 256.0);
	c += haze_col * h * haze;
	vec3 tinted = tint.rgb * max(c.r, max(c.g, c.b));
	vec3 rgb = mix(c, tinted, use_tint) * intensity;
	// a little noise so the dark end of the fade doesn't show steps
	float n = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453);
	COLOR = vec4(max(rgb + (n - 0.5) / 255.0, vec3(0.0)), 1.0);
}
"""

static func add_to(cursor: Spatial, game: Node) -> void:
	if cursor == null or cursor.has_node("Bloom") or Rhythia.vr:
		return
	var b = load("res://scripts/game/CursorGlow.gd").new()
	b.name = "Bloom"
	b._cursor = cursor
	# what blooms: the cursor (and the trail, before its copies are made)
	_mark(cursor.get_node_or_null("Mesh"))
	_mark(cursor.get_node_or_null("Mesh2"))
	if Rhythia.get("cursor_glow_trail"):
		_mark(cursor.get_node_or_null("../../CursorTrail/Mesh"))
	cursor.add_child(b)
	if game != null and game.has_signal("hit"):
		game.connect("hit", b, "_on_hit")

static func _mark(m):
	if m is VisualInstance:
		m.set_layer_mask_bit(LAYER_BIT, true)

var _cursor: Spatial
var _vp := Viewport.new()
var _cam := Camera.new()
var _env := Environment.new()
var _rect := TextureRect.new()
var _mat := ShaderMaterial.new()
var _layer := CanvasLayer.new()
var _pulse := 0.0
var _levels := -1

func _ready():
	process_priority = 1000 # after the camera has moved this frame
	_vp.transparent_bg = false
	_vp.hdr = true # (bright parts bloom properly)
	_vp.render_target_v_flip = true
	_vp.render_target_update_mode = Viewport.UPDATE_ALWAYS
	_vp.msaa = Viewport.MSAA_DISABLED
	_vp.shadow_atlas_size = 0
	add_child(_vp)

	# black background, glow in "replace" mode: the view holds only the bloom
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0, 0, 0)
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.glow_enabled = true
	_env.glow_blend_mode = Environment.GLOW_BLEND_MODE_REPLACE
	_env.glow_hdr_threshold = 0.0
	_env.glow_hdr_scale = 1.0
	_env.glow_intensity = 1.0
	_env.glow_strength = 1.0
	_env.glow_bloom = 0.0
	_env.glow_high_quality = true
	_env.glow_bicubic_upscale = true
	_cam.environment = _env
	_cam.cull_mask = 1 << LAYER_BIT
	_vp.add_child(_cam)
	_cam.current = true

	var tex: ViewportTexture = _vp.get_texture()
	tex.flags = Texture.FLAG_FILTER
	_mat.shader = Shader.new()
	_mat.shader.code = ADD_SHADER
	_rect.material = _mat
	_rect.expand = true
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.texture = tex
	_layer.layer = -5 # over the game, under menus / pause screen
	_layer.add_child(_rect)
	add_child(_layer)
	_update(0.0)

func _on_hit(_col = null):
	if Rhythia.get("cursor_glow_pulse"):
		_pulse = 1.0

func _process(delta):
	_update(delta)

func _update(delta: float):
	var vp: Viewport = _cursor.get_viewport() if _cursor != null else null
	var main_cam: Camera = vp.get_camera() if vp != null else null
	if main_cam == null:
		_layer.visible = false
		return
	_layer.visible = true
	if _pulse > 0.0:
		_pulse = max(0.0, _pulse - delta * PULSE_DECAY)

	var full: Vector2 = vp.size
	if _vp.size != full:
		_vp.size = full
	_rect.rect_position = Vector2.ZERO
	_rect.rect_size = full

	if _vp.world != main_cam.get_world():
		_vp.world = main_cam.get_world()
	_cam.global_transform = main_cam.global_transform
	_cam.projection = main_cam.projection
	_cam.fov = main_cam.fov
	_cam.size = main_cam.size
	_cam.near = main_cam.near
	_cam.far = main_cam.far
	_cam.keep_aspect = main_cam.keep_aspect
	_cam.h_offset = main_cam.h_offset
	_cam.v_offset = main_cam.v_offset

	# The engine's glow: only its tight levels (1-3), the halo that follows the
	# cursor's (and trail's) shape. The wide haze is the shader's, round.
	if _levels != 3:
		_levels = 3
		for i in range(1, 8):
			_env.set("glow_levels/%d" % i, i <= 3)
	# Size: how far the haze reaches (compared to the cursor on screen)
	var size: float = clamp(float(Rhythia.get("cursor_glow_size")), 1.0, 10.0)
	var mesh: Spatial = _cursor.get_node_or_null("Mesh")
	var at: Vector3 = mesh.global_transform.origin if mesh != null else _cursor.global_transform.origin
	var shown: bool = _cursor.is_visible_in_tree() and not main_cam.is_position_behind(at)
	var px: Vector2 = main_cam.unproject_position(at)
	# the cursor's size on screen: its plane (0.263 wide) at its scale
	var side: Vector3 = main_cam.global_transform.basis.x.normalized() * 0.263 * 0.5 * float(Rhythia.cursor_scale)
	var cursor_px: float = (main_cam.unproject_position(at + side) - px).length()
	var h: float = max(1.0, full.y)
	_mat.set_shader_param("center", px / full)
	_mat.set_shader_param("aspect", full.x / h)
	_mat.set_shader_param("radius", max(2.0, cursor_px * (0.35 + size * 0.25) * (1.0 + 0.3 * _pulse)) / h)
	var col := Color(1, 1, 1)
	var m = mesh.get("material/0") if mesh is MeshInstance else null
	if m is SpatialMaterial:
		col = m.albedo_color
	_mat.set_shader_param("haze_col", Vector3(col.r, col.g, col.b))
	_mat.set_shader_param("haze", 1.0 if shown else 0.0)
	# Strength: how bright, scaled evenly (0.01 steps)
	var strength: float = max(0.0, float(Rhythia.get("cursor_glow_strength")))
	_mat.set_shader_param("intensity", strength * 0.25 * (1.0 + 0.8 * _pulse))
	_mat.set_shader_param("use_tint", 1.0 if Rhythia.get("cursor_glow_custom_color") else 0.0)
	_mat.set_shader_param("tint", Rhythia.get("cursor_glow_color"))

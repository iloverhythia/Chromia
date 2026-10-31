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
void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	vec3 tinted = tint.rgb * max(c.r, max(c.g, c.b));
	COLOR = vec4(mix(c, tinted, use_tint) * intensity, 1.0);
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

	# Size: how far the soft haze reaches. Every glow level is a wider blur;
	# adding them up gives a bright core with a long, slow falloff. Size 1
	# uses levels 1-3, 3 (default) 1-5, 5 and up all 7.
	# Strength: how bright, scaled evenly (0.01 steps)
	var size: float = clamp(float(Rhythia.get("cursor_glow_size")), 1.0, 10.0)
	var levels: int = int(clamp(round(2.0 + size), 3, 7))
	if levels != _levels:
		_levels = levels
		for i in range(1, 8):
			_env.set("glow_levels/%d" % i, i <= levels)
	var strength: float = max(0.0, float(Rhythia.get("cursor_glow_strength")))
	_mat.set_shader_param("intensity", strength * 0.25 * (1.0 + 0.8 * _pulse))
	_mat.set_shader_param("use_tint", 1.0 if Rhythia.get("cursor_glow_custom_color") else 0.0)
	_mat.set_shader_param("tint", Rhythia.get("cursor_glow_color"))

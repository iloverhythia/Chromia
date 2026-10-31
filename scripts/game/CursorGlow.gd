extends Node

# Cursor Bloom (Settings > World & Cursor > Cursor): real bloom on the cursor
# only. The cursor (and its trail, if you want) is drawn a second time by its
# own camera into a small off-screen image, that image is blurred by a
# two-pass Gaussian shader, and the result is added on top of the screen.
# Nothing else on screen blooms.
#
# Cursor.gd adds it when the setting is on.

const LAYER_BIT := 19                # render layer 20: only what should bloom
const PULSE_DECAY := 5.0             # how quickly a hit pulse fades (per second)

const BLUR_SHADER := """
shader_type canvas_item;
render_mode %s;
uniform vec2 dir = vec2(1.0, 0.0);
uniform float spread = 1.0;
uniform float intensity = 1.0;
uniform float use_tint = 0.0;
uniform vec4 tint : hint_color = vec4(1.0);

void fragment() {
	vec2 o = TEXTURE_PIXEL_SIZE * dir * spread;
	// 9-tap Gaussian; the image is premultiplied, so it blurs without dark edges
	vec4 c = texture(TEXTURE, UV) * 0.227027;
	c += (texture(TEXTURE, UV + o) + texture(TEXTURE, UV - o)) * 0.1945946;
	c += (texture(TEXTURE, UV + o * 2.0) + texture(TEXTURE, UV - o * 2.0)) * 0.1216216;
	c += (texture(TEXTURE, UV + o * 3.0) + texture(TEXTURE, UV - o * 3.0)) * 0.054054;
	c += (texture(TEXTURE, UV + o * 4.0) + texture(TEXTURE, UV - o * 4.0)) * 0.016216;
	%s
}
"""
# first pass: keep it premultiplied, written as is
const PASS_H := "c"
# second pass: added onto the screen
const PASS_V := """vec3 rgb = mix(c.rgb, tint.rgb * max(c.r, max(c.g, c.b)), use_tint);
	COLOR = vec4(rgb * intensity, 1.0);"""

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
		var tb = cursor.get_node_or_null("../../CursorTrail/Mesh")
		_mark(tb)
	cursor.add_child(b)
	if game != null and game.has_signal("hit"):
		game.connect("hit", b, "_on_hit")

static func _mark(m):
	if m is VisualInstance:
		m.set_layer_mask_bit(LAYER_BIT, true)

var _cursor: Spatial
var _va := Viewport.new()   # the cursor, small
var _vb := Viewport.new()   # blurred one way
var _cam := Camera.new()
var _rect_h := TextureRect.new()
var _rect_v := TextureRect.new()
var _mat_h := ShaderMaterial.new()
var _mat_v := ShaderMaterial.new()
var _layer := CanvasLayer.new()
var _pulse := 0.0
var _div := 4

func _blur_shader(mode: String, body: String) -> Shader:
	var s := Shader.new()
	s.code = BLUR_SHADER % [mode, body]
	return s

func _ready():
	process_priority = 1000 # after the camera has moved this frame
	for v in [_va, _vb]:
		v.transparent_bg = true
		v.render_target_v_flip = true
		v.render_target_update_mode = Viewport.UPDATE_ALWAYS
		v.hdr = false
		v.msaa = Viewport.MSAA_DISABLED
		v.shadow_atlas_size = 0
		add_child(v)
	_vb.usage = Viewport.USAGE_2D
	_vb.disable_3d = true

	# the cursor's own camera: same view as the game's, sees only layer 20,
	# with an empty environment (no sky, fog or tonemapping in the way)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	_cam.environment = env
	_cam.cull_mask = 1 << LAYER_BIT
	_va.add_child(_cam)
	_cam.current = true

	_mat_h.shader = _blur_shader("blend_disabled", PASS_H)
	_mat_h.set_shader_param("dir", Vector2(1, 0))
	_rect_h.material = _mat_h
	_rect_h.expand = true
	_rect_h.texture = _va.get_texture()
	_vb.add_child(_rect_h)

	_mat_v.shader = _blur_shader("blend_add", PASS_V)
	_mat_v.set_shader_param("dir", Vector2(0, 1))
	_rect_v.material = _mat_v
	_rect_v.expand = true
	_rect_v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect_v.texture = _vb.get_texture()
	_layer.layer = -5 # over the game, under menus / pause screen
	_layer.add_child(_rect_v)
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

	var size: float = clamp(float(Rhythia.get("cursor_glow_size")), 1.0, 10.0)
	# bigger blooms are worked out at a lower resolution (smoother, cheaper)
	_div = 4 if size <= 5.0 else 8
	var full: Vector2 = vp.size
	var small := Vector2(max(16, round(full.x / _div)), max(16, round(full.y / _div)))
	if _va.size != small:
		_va.size = small
		_vb.size = small
		_rect_h.rect_size = small
	_rect_v.rect_position = Vector2.ZERO
	_rect_v.rect_size = full

	if _va.world != main_cam.get_world():
		_va.world = main_cam.get_world()
	_cam.global_transform = main_cam.global_transform
	_cam.projection = main_cam.projection
	_cam.fov = main_cam.fov
	_cam.size = main_cam.size
	_cam.near = main_cam.near
	_cam.far = main_cam.far
	_cam.keep_aspect = main_cam.keep_aspect
	_cam.h_offset = main_cam.h_offset
	_cam.v_offset = main_cam.v_offset

	var spread: float = size * 0.6 * (4.0 / _div) * (1.0 + 0.3 * _pulse)
	_mat_h.set_shader_param("spread", spread)
	_mat_v.set_shader_param("spread", spread)
	var strength: float = max(0.0, float(Rhythia.get("cursor_glow_strength")))
	_mat_v.set_shader_param("intensity", strength * 1.6 * (1.0 + 0.8 * _pulse))
	_mat_v.set_shader_param("use_tint", 1.0 if Rhythia.get("cursor_glow_custom_color") else 0.0)
	_mat_v.set_shader_param("tint", Rhythia.get("cursor_glow_color"))

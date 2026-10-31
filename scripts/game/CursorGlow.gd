extends MeshInstance

# Cursor Bloom (Settings > World & Cursor > Cursor): a soft glow drawn behind
# the cursor only, so nothing else on screen blooms. It sits on the cursor's
# own mesh, so it follows the cursor's scale, and by default its colour
# (rainbow and note colour included). Optional pulse when you hit a note.
#
# Cursor.gd adds it when the setting is on.

const BASE_SIZE := 0.263 # the cursor plane's size (scenes/song.tscn)
const PULSE_DECAY := 6.0  # how quickly a hit pulse fades (per second)

static func add_to(cursor_mesh: MeshInstance, game: Node) -> void:
	if cursor_mesh == null or cursor_mesh.has_node("Glow"):
		return
	var g = load("res://scripts/game/CursorGlow.gd").new()
	g.name = "Glow"
	g._cursor_mesh = cursor_mesh
	cursor_mesh.add_child(g)
	if game != null and game.has_signal("hit"):
		game.connect("hit", g, "_on_hit")

var _cursor_mesh: MeshInstance
var _mat := SpatialMaterial.new()
var _pulse := 0.0

static func _glow_texture() -> ImageTexture:
	# soft round falloff, made once and kept
	var key := "chromia_cursor_glow_tex"
	if Engine.has_meta(key):
		return Engine.get_meta(key)
	var n := 128
	var img := Image.new()
	img.create(n, n, false, Image.FORMAT_RGBA8)
	img.lock()
	var c := (n - 1) / 2.0
	for y in range(n):
		for x in range(n):
			var d: float = Vector2(x - c, y - c).length() / c
			var a := 0.0
			if d < 1.0:
				# a bright core that fades out smoothly to the edge
				a = exp(-d * d * 5.0) * (1.0 - d * d)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.unlock()
	var tex := ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
	Engine.set_meta(key, tex)
	return tex

func _ready():
	var plane := PlaneMesh.new()
	plane.size = Vector2(BASE_SIZE, BASE_SIZE)
	mesh = plane
	_mat.flags_transparent = true
	_mat.flags_unshaded = true
	_mat.flags_no_depth_test = true
	_mat.flags_do_not_receive_shadows = true
	_mat.flags_disable_ambient_light = true
	_mat.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	_mat.render_priority = 99 # just under the cursor (100)
	_mat.albedo_texture = _glow_texture()
	material_override = _mat
	cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	_update(0.0)

func _on_hit(_col = null):
	if Rhythia.get("cursor_glow_pulse"):
		_pulse = 1.0

func _process(delta):
	_update(delta)

func _update(delta: float):
	if _pulse > 0.0:
		_pulse = max(0.0, _pulse - delta * PULSE_DECAY)
	var size: float = max(0.5, float(Rhythia.get("cursor_glow_size"))) * (1.0 + 0.35 * _pulse)
	scale = Vector3(size, 1, size)
	var col: Color = Color(1, 1, 1)
	if Rhythia.get("cursor_glow_custom_color"):
		col = Rhythia.get("cursor_glow_color")
	elif _cursor_mesh != null:
		var m = _cursor_mesh.get("material/0")
		if m is SpatialMaterial:
			col = m.albedo_color
	var strength: float = max(0.0, float(Rhythia.get("cursor_glow_strength"))) * (1.0 + 0.6 * _pulse)
	# above 1 it gets brighter instead of more opaque
	var boost: float = max(1.0, strength)
	_mat.albedo_color = Color(col.r * boost, col.g * boost, col.b * boost, min(strength, 1.0))

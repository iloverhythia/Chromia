extends Spatial
# Shared base for the Rhythia (Godot 4 C#) "spaces" recreated for Godot 3.5.
# Mirrors BaseSpace.cs: keeps a NoteHitColor that lerps toward the colour of the
# last hit note, exposes the map cover and the SpaceEffects toggle
# (= !Rhythia.disable_bg_effects).
#
# Subclasses must NOT define _ready/_process (Godot 3 calls the parent's too);
# override _build() and _tick(delta) instead.

var note_hit_color: Color = Color(1, 1, 1)
var last_hit_color: Color = Color(1, 1, 1)
var space_effects: bool = true
var approach_rate: float = 40.0
var cover: Texture = null
var env: Environment = null
var time: float = 0.0

func _ready():
	space_effects = !Rhythia.disable_bg_effects
	approach_rate = float(Rhythia.approach_rate)
	if Rhythia.selected_colorset != null and Rhythia.selected_colorset.colors.size() > 0:
		var cols: Array = Rhythia.selected_colorset.colors
		note_hit_color = cols[cols.size() - 1]
		last_hit_color = note_hit_color
	if Rhythia.selected_song != null and Rhythia.selected_song.has_cover:
		var c = Rhythia.selected_song.cover
		if c is Texture:
			cover = c

	var we = get_node_or_null("WorldEnvironment")
	if we == null:
		we = WorldEnvironment.new()
		we.name = "WorldEnvironment"
		add_child(we)
	if we.environment == null:
		we.environment = Environment.new()
	env = we.environment
	env.background_mode = Environment.BG_COLOR
	if Rhythia.glow > 0:
		env.glow_enabled = true
		env.glow_intensity = Rhythia.glow
		env.glow_strength = 1
		env.glow_bloom = Rhythia.bloom
		env.glow_blend_mode = 1
		env.glow_hdr_scale = 1.72
		env.glow_high_quality = true
		env.glow_bicubic_upscale = true

	var p = get_parent()
	if p != null:
		var game = p.get_node_or_null("Game")
		if game != null and game.has_signal("hit"):
			game.connect("hit", self, "_on_game_hit")

	_build()

func _on_game_hit(col: Color):
	last_hit_color = col
	_on_hit(col)

func _process(delta):
	time += delta
	note_hit_color = note_hit_color.linear_interpolate(last_hit_color, min(1.0, delta * 8.0))
	_tick(delta)

# --- overridables -----------------------------------------------------------
func _build():
	pass

func _tick(_delta: float):
	pass

func _on_hit(_col: Color):
	pass

# --- helpers ----------------------------------------------------------------

# Average colour of the map cover (downscaled first so it is cheap).
func cover_average(fallback: Color) -> Color:
	if cover == null:
		return fallback
	var img: Image = cover.get_data()
	if img == null or img.is_empty():
		return fallback
	img = img.duplicate()
	if img.is_compressed():
		if img.decompress() != OK:
			return fallback
	img.resize(8, 8, Image.INTERPOLATE_BILINEAR)
	var sum := Vector3()
	var n := 0
	img.lock()
	for x in range(8):
		for y in range(8):
			var px := img.get_pixel(x, y)
			if px.a <= 0.0:
				continue
			sum += Vector3(px.r, px.g, px.b)
			n += 1
	img.unlock()
	if n == 0:
		return fallback
	sum /= n
	return Color(sum.x, sum.y, sum.z)

func make_unshaded(col: Color, tex: Texture = null, additive: bool = true, fade_dist: float = 0.0) -> SpatialMaterial:
	var m := SpatialMaterial.new()
	m.flags_unshaded = true
	m.flags_transparent = true
	m.params_cull_mode = SpatialMaterial.CULL_DISABLED
	if additive:
		m.params_blend_mode = SpatialMaterial.BLEND_MODE_ADD
	m.albedo_color = col
	if tex != null:
		m.albedo_texture = tex
	if fade_dist > 0.0:
		m.distance_fade_mode = SpatialMaterial.DISTANCE_FADE_PIXEL_ALPHA
		m.distance_fade_min_distance = fade_dist
		m.distance_fade_max_distance = 0.0
	return m

func add_quad(parent: Node, size: Vector2, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3()) -> MeshInstance:
	var q := QuadMesh.new()
	q.size = size
	var mi := MeshInstance.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance.SHADOW_CASTING_SETTING_OFF
	mi.translation = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi

# Writes a pixel and its mirror images in the other three quadrants
# (all generated shapes are symmetric, so only a quarter is computed).
static func _set4(img: Image, size: int, x: int, y: int, c: Color):
	var x2 = size - 1 - x
	var y2 = size - 1 - y
	img.set_pixel(x, y, c)
	img.set_pixel(x2, y, c)
	img.set_pixel(x, y2, c)
	img.set_pixel(x2, y2, c)

func image_to_texture(img: Image, repeat: bool = true) -> ImageTexture:
	img.generate_mipmaps()
	var t := ImageTexture.new()
	var flags = Texture.FLAG_MIPMAPS | Texture.FLAG_FILTER | Texture.FLAG_ANISOTROPIC_FILTER
	if repeat:
		flags |= Texture.FLAG_REPEAT
	t.create_from_image(img, flags)
	return t

static func _smooth(e0: float, e1: float, x: float) -> float:
	var t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

# Signed distance to a superellipse ("squircle") of half-size 1 in unit coords.
static func _squircle_d(x: float, y: float, n: float) -> float:
	return pow(pow(abs(x), n) + pow(abs(y), n), 1.0 / n) - 1.0

# White outline shape on transparent background.
#  shape: 0 = square, 1 = circle, 2 = squircle, 3 = square corner brackets
func shape_texture(size: int, shape: int, thickness: float, glow: float = 0.0) -> ImageTexture:
	var img := Image.new()
	img.create(size, size, false, Image.FORMAT_RGBA8)
	img.lock()
	var inner := 1.0 - glow - thickness * 0.5 - 2.0 / size
	var half := size / 2
	for y in range(half):
		var fy = (y + 0.5) / size * 2.0 - 1.0
		for x in range(half):
			var fx = (x + 0.5) / size * 2.0 - 1.0
			var d: float
			if shape == 0 or shape == 3:
				d = max(abs(fx), abs(fy))
			elif shape == 1:
				d = sqrt(fx * fx + fy * fy)
			else:
				d = _squircle_d(fx, fy, 4.0) + 1.0
			var e = abs(d - inner)
			var a = 1.0 - _smooth(thickness * 0.5 - 1.5 / size, thickness * 0.5 + 1.5 / size, e)
			if glow > 0.0:
				a = max(a, 0.35 * (1.0 - _smooth(0.0, glow + thickness, e)))
			if shape == 3:
				# keep only the corners
				var c = min(abs(fx), abs(fy))
				a *= 1.0 - _smooth(0.45, 0.5, 1.0 - c)
			_set4(img, size, x, y, Color(1, 1, 1, a))
	img.unlock()
	return image_to_texture(img, false)

# Tile / grid texture: lines on the border of the tile (tileable).
func tile_texture(size: int, line: float, fill: float, glow: float) -> ImageTexture:
	var img := Image.new()
	img.create(size, size, false, Image.FORMAT_RGBA8)
	img.lock()
	var half := size / 2
	for y in range(half):
		var fy = abs((y + 0.5) / size * 2.0 - 1.0)
		for x in range(half):
			var fx = abs((x + 0.5) / size * 2.0 - 1.0)
			var e = 1.0 - max(fx, fy)
			var a = 1.0 - _smooth(line - 1.5 / size, line + 1.5 / size, e)
			a = max(a, (1.0 - _smooth(0.0, glow, e)) * 0.35)
			a = max(a, fill)
			_set4(img, size, x, y, Color(1, 1, 1, a))
	img.unlock()
	return image_to_texture(img, true)

# Soft round dot (for particles / stars).
func dot_texture(size: int, hardness: float = 0.4) -> ImageTexture:
	var img := Image.new()
	img.create(size, size, false, Image.FORMAT_RGBA8)
	img.lock()
	var half := size / 2
	for y in range(half):
		var fy = (y + 0.5) / size * 2.0 - 1.0
		for x in range(half):
			var fx = (x + 0.5) / size * 2.0 - 1.0
			var d = sqrt(fx * fx + fy * fy)
			var a = 1.0 - _smooth(hardness, 1.0, d)
			_set4(img, size, x, y, Color(1, 1, 1, a * a))
	img.unlock()
	return image_to_texture(img, false)

func dynamic_font(size: int) -> DynamicFont:
	var f := DynamicFont.new()
	var data = load("res://assets/font/Lato/Lato-Black.ttf")
	if data != null:
		f.font_data = data
	f.size = size
	return f

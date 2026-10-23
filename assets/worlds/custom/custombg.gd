extends Spatial

# Custom Background: your picture wrapped around you as a sky.
#
# The picture is turned into a sky image (the cube projection in V/R's shader)
# by drawing V once when the song starts; that drawing is then copied into a
# normal texture for the sky and V is removed. The sky used to show V itself,
# redrawn every frame at 4096x2048: very slow on phones, and a live viewport
# as a sky crashed iPhones at the start of songs.

var _sky: PanoramaSky

func _ready():
	var env = $WorldEnvironment.environment
	_sky = env.background_sky
	_sky.panorama = _black()
	var pano = Globals.imageLoader.load_if_exists("user://panobg")
	if pano:
		_sky.panorama = pano
		$V.queue_free()
	else:
		var img = Globals.imageLoader.load_if_exists("user://custombg")
		var col: Color = Rhythia.custombg_color
		if img: $V/R.material.set_shader_param("tex",img)
		elif col != Color(1, 1, 1):
			# no image + a color picked: a solid color background
			var white = Image.new()
			white.create(1, 1, false, Image.FORMAT_RGB8)
			white.fill(Color(1, 1, 1))
			var wt = ImageTexture.new()
			wt.create_from_image(white, 0)
			$V/R.material.set_shader_param("tex", wt)
		$V/R.material.set_shader_param("tint", col)
		_bake()
	# Shaders
	if Rhythia.glow > 0:
		env.glow_enabled = true
		env.glow_intensity = Rhythia.glow
		env.glow_strength = 1
		env.glow_bloom = Rhythia.bloom
		env.glow_blend_mode = 1
		env.glow_hdr_scale = 1.72
		env.glow_high_quality = true
		env.glow_bicubic_upscale = true

static func _black() -> ImageTexture:
	var b := Image.new()
	b.create(2, 1, false, Image.FORMAT_RGB8)
	b.fill(Color(0, 0, 0))
	var t := ImageTexture.new()
	t.create_from_image(b, 0)
	return t

# V draws once (UPDATE_ONCE in the scene) on the next frame; copy it then.
func _bake():
	var v: Viewport = $V
	# colors stay as in the picture; the sky image is marked to be converted
	# to linear (once, on every device) instead
	$V/R.material.set_shader_param("raw", true)
	v.render_target_update_mode = Viewport.UPDATE_ONCE
	for i in range(2):
		yield(VisualServer, "frame_post_draw")
		if not is_instance_valid(v) or not is_inside_tree():
			return
	var img: Image = v.get_texture().get_data()
	v.queue_free()
	if img == null or img.is_empty():
		return
	var tex := ImageTexture.new()
	tex.create_from_image(img, Texture.FLAGS_DEFAULT | Texture.FLAG_CONVERT_TO_LINEAR)
	_sky.panorama = tex
	Rhythia.trail("custom background ready")

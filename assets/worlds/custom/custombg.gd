extends Spatial

# Custom Background: your picture wrapped around you as a sky.
#
# The picture is turned into a sky image (the cube projection in V/R's shader)
# by drawing V once; that drawing is copied into a normal texture for the sky
# and V is removed. The sky used to show V itself, redrawn every frame at
# 4096x2048: very slow on phones, and a live viewport as a sky crashed iPhones
# at the start of songs.
#
# The sky image is made once and saved (user://cache/custombg_sky.bin), and
# made again only when the picture or the color changes. It used to be drawn
# and read back from the GPU at the start of every song; iPhones crashed right
# after that when starting a second song. Phones also use a smaller sky
# (2048x1024) and lighter sky lighting.

const CACHE_DIR := "user://cache"
const CACHE_FILE := "user://cache/custombg_sky.bin"
const CACHE_KEY := "user://cache/custombg_sky.key"
const EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "gif"]

var _sky: PanoramaSky
var _save_thread: Thread = null

# the picture (and panorama) to use: theirs while spectating with their
# settings (SpectateSettings.gd; "" = they have none), else yours
static func _pic(meta: String, own: String) -> String:
	return String(Rhythia.get_meta(meta)) if Rhythia.has_meta(meta) else own

static func _phone() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("iOS") or OS.has_feature("Android")

func _ready():
	var env = $WorldEnvironment.environment
	_sky = env.background_sky
	_sky.panorama = _black()
	if _phone():
		_sky.radiance_size = Sky.RADIANCE_SIZE_64 # (only the soft light from the sky uses it)
	var pano_path := _pic("spec_panobg", "user://panobg")
	var pano = Globals.imageLoader.load_if_exists(pano_path) if pano_path != "" else null
	if pano:
		_sky.panorama = pano
		_drop_viewport()
	else:
		var size := Vector2(2048, 1024) if _phone() else Vector2(4096, 2048)
		var key := _cache_key(size)
		var cached = _load_cached(key)
		if cached != null:
			_sky.panorama = cached
			_drop_viewport()
			Rhythia.trail("custom background ready (saved)")
		else:
			_setup_viewport(size)
			_bake(key)
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

func _exit_tree():
	if _save_thread != null:
		_save_thread.wait_to_finish()
		_save_thread = null

static func _black() -> ImageTexture:
	var b := Image.new()
	b.create(2, 1, false, Image.FORMAT_RGB8)
	b.fill(Color(0, 0, 0))
	var t := ImageTexture.new()
	t.create_from_image(b, 0)
	return t

func _drop_viewport():
	var v = get_node_or_null("V")
	if v:
		v.render_target_update_mode = Viewport.UPDATE_DISABLED
		remove_child(v)
		v.queue_free()

static func _source_path() -> String:
	var f := File.new()
	var own := _pic("spec_custombg", "user://custombg")
	if own == "":
		return ""
	var base := Globals.p(own)
	for e in EXTS:
		if f.file_exists(base + "." + e):
			return base + "." + e
	if f.file_exists(base):
		return base
	return ""

# what the saved sky was made from: the picture (and when it was changed),
# the color and the size
func _cache_key(size: Vector2) -> String:
	var src := _source_path()
	var mtime := 0
	if src != "":
		mtime = File.new().get_modified_time(src)
	return "2|%s|%d|%s|%dx%d" % [src.get_file(), mtime, Rhythia.custombg_color.to_html(true), int(size.x), int(size.y)]

static func _sky_texture(img: Image) -> ImageTexture:
	var tex := ImageTexture.new()
	tex.create_from_image(img, Texture.FLAGS_DEFAULT | Texture.FLAG_CONVERT_TO_LINEAR)
	return tex

func _load_cached(key: String):
	var f := File.new()
	if f.open(Globals.p(CACHE_KEY), File.READ) != OK:
		return null
	var saved := f.get_as_text().strip_edges()
	f.close()
	if saved != key:
		return null
	if f.open_compressed(Globals.p(CACHE_FILE), File.READ, File.COMPRESSION_ZSTD) != OK:
		return null
	var w := f.get_32()
	var h := f.get_32()
	var fmt := f.get_32()
	var n := f.get_32()
	if w < 1 or h < 1 or w > 8192 or h > 8192 or fmt != Image.FORMAT_RGB8 or n != w * h * 3:
		f.close()
		return null
	var data := f.get_buffer(n)
	f.close()
	if data.size() != n:
		return null
	var img := Image.new()
	img.create_from_data(w, h, false, fmt, data)
	return _sky_texture(img)

func _setup_viewport(size: Vector2):
	var v: Viewport = $V
	v.size = size
	$V/R.rect_size = size
	var pic := _pic("spec_custombg", "user://custombg")
	var img = Globals.imageLoader.load_if_exists(pic) if pic != "" else null
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

# V draws once on the next frame; copy it then.
func _bake(key: String):
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
	_drop_viewport()
	if img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGB8) # (no see-through in a sky; a quarter smaller)
	_sky.panorama = _sky_texture(img)
	Rhythia.trail("custom background ready")
	if _all_black(img):
		return # (a failed copy, or a black picture: not worth keeping)
	if Rhythia.has_meta("spec_custombg"):
		return # (someone else's background while spectating: your saved one stays)
	# saved for next time, on the side (it takes a moment)
	_save_thread = Thread.new()
	if _save_thread.start(self, "_save_cache", [img, key]) != OK:
		_save_thread = null
		_save_cache([img, key])

static func _all_black(img: Image) -> bool:
	var w := img.get_width()
	var h := img.get_height()
	img.lock()
	for i in range(64):
		var c := img.get_pixel(int((i % 8 + 0.5) * w / 8), int((i / 8 + 0.5) * h / 8))
		if c.r + c.g + c.b > 0.004:
			img.unlock()
			return false
	img.unlock()
	return true

func _save_cache(args: Array):
	var img: Image = args[0]
	var key: String = args[1]
	var d := Directory.new()
	if not d.dir_exists(Globals.p(CACHE_DIR)):
		d.make_dir_recursive(Globals.p(CACHE_DIR))
	var f := File.new()
	# the key goes last, so a half-written sky is never used
	if f.open(Globals.p(CACHE_KEY), File.WRITE) == OK:
		f.store_string("")
		f.close()
	if f.open_compressed(Globals.p(CACHE_FILE), File.WRITE, File.COMPRESSION_ZSTD) != OK:
		return
	var data := img.get_data()
	f.store_32(img.get_width())
	f.store_32(img.get_height())
	f.store_32(img.get_format())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
	if f.open(Globals.p(CACHE_KEY), File.WRITE) == OK:
		f.store_string(key)
		f.close()

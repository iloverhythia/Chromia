


























extends Node
class_name ImageLoader

func report_errors(err, filepath):

	var result_hash = {
		ERR_FILE_NOT_FOUND: "File: not found",
		ERR_FILE_BAD_DRIVE: "File: Bad drive error",
		ERR_FILE_BAD_PATH: "File: Bad path error.",
		ERR_FILE_NO_PERMISSION: "File: No permission error.",
		ERR_FILE_ALREADY_IN_USE: "File: Already in use error.",
		ERR_FILE_CANT_OPEN: "File: Can't open error.",
		ERR_FILE_CANT_WRITE: "File: Can't write error.",
		ERR_FILE_CANT_READ: "File: Can't read error.",
		ERR_FILE_UNRECOGNIZED: "File: Unrecognized error.",
		ERR_FILE_CORRUPT: "File: Corrupt error.",
		ERR_FILE_MISSING_DEPENDENCIES: "File: Missing dependencies error.",
		ERR_FILE_EOF: "File: End of file (EOF) error."
	}
	if err in result_hash:
		print("Error: ", result_hash[err], " ", filepath)
	else:
		print("Unknown error with file ", filepath, " error code: ", err)

func get_format(bytes: PoolByteArray) -> String:
	if bytes.size() < 10: return "unknown"



	if bytes.subarray(0, 7) == PoolByteArray([137, 80, 78, 71, 13, 10, 26, 10]): return "png"
	if bytes.subarray(0, 2) == PoolByteArray([66, 77]): return "bmp"
	if bytes.subarray(0, 2) == PoolByteArray([255, 216, 255]): return "jpg"
	if bytes.subarray(0, 3) == PoolByteArray([82, 73, 70, 70]) and bytes.subarray(8, 11) == PoolByteArray([87, 69, 66, 80]): return "webp"
	if bytes.subarray(0, 3) == PoolByteArray([71, 73, 70, 56]): return "gif"


	return "unknown"

var error_texture: Texture = load("res://assets/images/error.jpg")
var invalid_texture: Texture = load("res://assets/images/error2.jpg")



func load_buffer_image(bytes: PoolByteArray) -> Image:
	var format = get_format(bytes)
	var img: Image = Image.new()

	if format == "png": img.load_png_from_buffer(bytes)
	elif format == "bmp": img.load_bmp_from_buffer(bytes)
	elif format == "jpg": img.load_jpg_from_buffer(bytes)
	elif format == "webp": img.load_webp_from_buffer(bytes)
	elif format == "gif": return GifDecoder.decode_first_frame_image(bytes)
	else: return null
	return img

# Decoding a GIF in GDScript can take seconds, and the same GIF (custom cursor,
# background, ...) is requested every time a song or menu loads. Decoded GIFs are
# kept in memory for the session and in a compressed cache file on disk, keyed
# on the file's path, size and modified time.
const GIF_CACHE_DIR = "user://caches/gif"
const GIF_CACHE_VERSION = 1
var _gif_cache := {}
var _gif_cache_mutex := Mutex.new()

func _load_gif_cached(path: String, bytes: PoolByteArray) -> Texture:
	var file := File.new()
	var key: String = ("%s|%s|%s" % [path, bytes.size(), file.get_modified_time(path)]).md5_text()
	_gif_cache_mutex.lock()
	var hit = _gif_cache.get(key)
	_gif_cache_mutex.unlock()
	if hit != null:
		return hit

	var tex: Texture = null
	var cache_path: String = Globals.p(GIF_CACHE_DIR).plus_file(key + ".gifc")
	if file.file_exists(cache_path) and file.open_compressed(cache_path, File.READ, File.COMPRESSION_ZSTD) == OK:
		var meta = file.get_var()
		if meta is Dictionary and meta.get("v", 0) == GIF_CACHE_VERSION:
			var frames := []
			var frame_len: int = int(meta.width) * int(meta.height) * 4
			for i in range(meta.count):
				frames.append(file.get_buffer(frame_len))
			tex = GifDecoder.texture_from_decoded({"frames": frames, "delays": meta.delays, "width": meta.width, "height": meta.height})
		file.close()

	if tex == null:
		var result = GifDecoder.decode(bytes)
		if result.empty():
			return invalid_texture
		tex = GifDecoder.texture_from_decoded(result)
		var dir := Directory.new()
		dir.make_dir_recursive(Globals.p(GIF_CACHE_DIR))
		if file.open_compressed(cache_path, File.WRITE, File.COMPRESSION_ZSTD) == OK:
			file.store_var({"v": GIF_CACHE_VERSION, "width": result.width, "height": result.height,
				"count": result.frames.size(), "delays": result.delays})
			for frame in result.frames:
				file.store_buffer(frame)
			file.close()

	_gif_cache_mutex.lock()
	_gif_cache[key] = tex
	_gif_cache_mutex.unlock()
	return tex

func load_buffer(bytes: PoolByteArray) -> Texture:
	if get_format(bytes) == "gif":
		var anim = GifDecoder.decode_to_animated_texture(bytes)
		return anim if anim != null else invalid_texture

	var img = load_buffer_image(bytes)
	if img == null: return invalid_texture

	var imgtex: ImageTexture = ImageTexture.new()
	imgtex.create_from_image(img)
	return imgtex

# Custom images (background, note, cursor, hit...) are loaded every time a
# song starts. Decoding a big PNG/JPG takes a while, so loaded textures are
# kept until the file changes (same path, size and modified time).
const TEX_CACHE_MAX = 24
var _tex_cache := {}
var _tex_cache_order := []
var _tex_cache_mutex := Mutex.new()

func load_file(filepath: String) -> Texture:
	var full: String = Globals.p(filepath)
	var file = File.new()
	var err = file.open(full, File.READ)
	if err != OK:
		report_errors(err, full)
		file.close()
		return error_texture

	var key: String = "%s|%d|%d" % [full, file.get_len(), file.get_modified_time(full)]
	_tex_cache_mutex.lock()
	var hit = _tex_cache.get(key)
	_tex_cache_mutex.unlock()
	if hit != null and is_instance_valid(hit):
		file.close()
		return hit

	var bytes: PoolByteArray = file.get_buffer(file.get_len())
	file.close()
	var tex: Texture
	if get_format(bytes) == "gif":
		tex = _load_gif_cached(full, bytes)
	else:
		tex = load_buffer(bytes)
	if tex != null and tex != error_texture and tex != invalid_texture:
		_tex_cache_mutex.lock()
		_tex_cache[key] = tex
		_tex_cache_order.append(key)
		while _tex_cache_order.size() > TEX_CACHE_MAX:
			_tex_cache.erase(_tex_cache_order.pop_front())
		_tex_cache_mutex.unlock()
	return tex

func load_if_exists(path: String):
	var file: File = File.new()
	path = Globals.p(path)
	if file.file_exists(path + ".png"): path += ".png"
	elif file.file_exists(path + ".jpg"): path += ".jpg"
	elif file.file_exists(path + ".jpeg"): path += ".jpeg"
	elif file.file_exists(path + ".webp"): path += ".webp"
	elif file.file_exists(path + ".bmp"): path += ".bmp"
	elif file.file_exists(path + ".gif"): path += ".gif"
	if file.file_exists(path): return load_file(path)
	else: return null

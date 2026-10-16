


























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

func load_buffer(bytes: PoolByteArray) -> Texture:
	if get_format(bytes) == "gif":
		var anim = GifDecoder.decode_to_animated_texture(bytes)
		return anim if anim != null else invalid_texture

	var img = load_buffer_image(bytes)
	if img == null: return invalid_texture

	var imgtex: ImageTexture = ImageTexture.new()
	imgtex.create_from_image(img)
	return imgtex

func load_file(filepath: String) -> Texture:
	var file = File.new()
	var err = file.open(Globals.p(filepath), File.READ)
	if err != OK:
		report_errors(err, Globals.p(filepath))
		file.close()
		return error_texture

	var bytes: PoolByteArray = file.get_buffer(file.get_len())
	file.close()
	return load_buffer(bytes)

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

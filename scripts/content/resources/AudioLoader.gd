
extends Node
class_name AudioLoader

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
	if bytes.size() < 12: return "unknown"

	if bytes.subarray(0, 3) == PoolByteArray([79, 103, 103, 83]): return "ogg"

	# RIFF .... WAVE (it was never recognised: WAV songs, like some rhythia.com
	# maps', all came up as "broken audio")
	if bytes.subarray(0, 3) == PoolByteArray([82, 73, 70, 70]) and bytes.subarray(8, 11) == PoolByteArray([87, 65, 86, 69]): return "wav"

	if bytes.subarray(0, 2) == PoolByteArray([73, 68, 51]): return "mp3" # ID3 tag
	# an MP3 frame: 11 sync bits set (FF Ex / FF Fx: MPEG 1, 2 and 2.5)
	if bytes[0] == 255 and (bytes[1] & 224) == 224: return "mp3"

	return "unknown"

static func _u16(b: PoolByteArray, i: int) -> int:
	return b[i] | (b[i + 1] << 8)

static func _u32(b: PoolByteArray, i: int) -> int:
	return b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)

# A WAV file: its chunks one after another (fmt, data, and others to skip:
# JUNK, LIST, bext...). PCM 8 / 16 / 24 / 32 bits and 32-bit float, mono or
# stereo; anything else is Globals.error_sound.
func _load_wav(bytes: PoolByteArray, loop: bool):
	var n := bytes.size()
	var pos := 12
	var fmt_code := -1
	var channels := 0
	var rate := 0
	var bits := 0
	var data := PoolByteArray()
	var have_data := false
	while pos + 8 <= n:
		var cid := bytes.subarray(pos, pos + 3).get_string_from_ascii()
		var csize := _u32(bytes, pos + 4)
		var body := pos + 8
		if cid == "fmt " and body + 16 <= n:
			fmt_code = _u16(bytes, body)
			channels = _u16(bytes, body + 2)
			rate = _u32(bytes, body + 4)
			bits = _u16(bytes, body + 14)
			if fmt_code == 65534 and csize >= 26 and body + 26 <= n:
				fmt_code = _u16(bytes, body + 24) # WAVE_FORMAT_EXTENSIBLE: the real one
		elif cid == "data":
			# (a size past the end, or 0xFFFFFFFF from a recorder that never
			# filled it in: up to the end)
			var last: int = min(n, body + csize) - 1
			if last >= body:
				data = bytes.subarray(body, last)
				have_data = true
			break
		if csize < 0:
			break
		pos = body + csize + (csize & 1)
	if not have_data or channels < 1 or channels > 2 or rate <= 0:
		print("ERROR: unsupported WAV (format %d, %d channels, %d Hz, %d bits)" % [fmt_code, channels, rate, bits])
		return Globals.error_sound
	var s := AudioStreamSample.new()
	s.stereo = channels == 2
	s.mix_rate = rate
	if fmt_code == 1 and bits == 16:
		s.format = AudioStreamSample.FORMAT_16_BITS
		s.data = data
	elif fmt_code == 1 and bits == 8:
		# (WAV's 8-bit is unsigned, Godot's signed)
		for i in range(data.size()):
			data[i] = (data[i] + 128) & 255
		s.format = AudioStreamSample.FORMAT_8_BITS
		s.data = data
	elif (fmt_code == 1 and (bits == 24 or bits == 32)) or (fmt_code == 3 and bits == 32):
		s.format = AudioStreamSample.FORMAT_16_BITS
		s.data = convert_to_16bit(data, bits, fmt_code == 3)
	else:
		print("ERROR: unsupported WAV (format %d, %d bits)" % [fmt_code, bits])
		return Globals.error_sound
	var frame: int = channels * (1 if s.format == AudioStreamSample.FORMAT_8_BITS else 2)
	s.loop_end = s.data.size() / frame
	s.loop_mode = AudioStreamSample.LOOP_FORWARD if loop else AudioStreamSample.LOOP_DISABLED
	return s

func load_buffer(bytes: PoolByteArray, loop: bool = false):
	var format = get_format(bytes)

	if format == "wav":
		return _load_wav(bytes, loop)

	elif format == "ogg":
		var newstream = AudioStreamOGGVorbis.new()
		newstream.loop = loop
		newstream.data = bytes
		return newstream


	elif format == "mp3":
		var newstream = AudioStreamMP3.new()
		newstream.loop = loop
		newstream.data = bytes
		return newstream

	else:
		print("ERROR: Unknown filetype or format")
		push_error("Unknown filetype or format!")
		return Globals.error_sound

func load_file(filepath: String, loop: bool = false):
	var file = File.new()
	var err = file.open(Globals.p(filepath), File.READ)
	if err != OK:
		report_errors(err, Globals.p(filepath))
		file.close()
		return Globals.error_sound

	var bytes: PoolByteArray = file.get_buffer(file.get_len())
	file.close()
	return load_buffer(bytes, loop)

func convert_to_16bit(data: PoolByteArray, from: int, is_float: bool = true) -> PoolByteArray:
	print("converting to 16-bit from %d" % from)
	var time = OS.get_ticks_msec()


	if from == 24:
		var j = 0
		for i in range(0, data.size(), 3):
			data[j] = data[i + 1]
			data[j + 1] = data[i + 2]
			j += 2
		data.resize(data.size() * 2 / 3)


	if from == 32 and not is_float:
		# (whole numbers: their top two bytes)
		var j = 0
		for i in range(0, data.size(), 4):
			data[j] = data[i + 2]
			data[j + 1] = data[i + 3]
			j += 2
		data.resize(data.size() / 2)

	if from == 32 and is_float:
		var spb := StreamPeerBuffer.new()
		var single_float: float
		var value: int
		for i in range(0, data.size(), 4):
			spb.data_array = data.subarray(i, i + 3)
			single_float = spb.get_float()
			value = single_float * 32768
			data[i / 2] = value
			data[i / 2 + 1] = value >> 8
		data.resize(data.size() / 2)
	print("Took %f seconds for slow conversion" % ((OS.get_ticks_msec() - time) / 1000.0))
	return data

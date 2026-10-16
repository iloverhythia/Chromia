
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
	if bytes.size() < 10: return "unknown"

	if bytes.subarray(0, 3) == PoolByteArray([79, 103, 103, 83]): return "ogg"

	if (bytes.subarray(0, 1) == PoolByteArray([255, 251])
	or bytes.subarray(0, 1) == PoolByteArray([255, 243])
	or bytes.subarray(0, 1) == PoolByteArray([255, 250])
	or bytes.subarray(0, 1) == PoolByteArray([255, 242])
	or bytes.subarray(0, 2) == PoolByteArray([73, 68, 51])): return "mp3"

	return "unknown"

func load_buffer(bytes: PoolByteArray, loop: bool = false):
	var format = get_format(bytes)


	if format == "wav":
		var newstream = AudioStreamSample.new()




		var bits_per_sample = 0

		for i in range(0, 100):
			var those4bytes = str(char(bytes[i]) + char(bytes[i + 1]) + char(bytes[i + 2]) + char(bytes[i + 3]))

			if those4bytes == "fmt ":



				var _formatsubchunksize = bytes[i + 4] + (bytes[i + 5] << 8) + (bytes[i + 6] << 16) + (bytes[i + 7] << 24)



				var fsc0 = i + 8


				var format_code = bytes[fsc0] + (bytes[fsc0 + 1] << 8)
				var _format_name
				if format_code == 0: _format_name = "8_BITS"
				elif format_code == 1: _format_name = "16_BITS"
				elif format_code == 2: _format_name = "IMA_ADPCM"
				else:
					_format_name = "UNKNOWN (trying to interpret as 16_BITS)"
					format_code = 1


				newstream.format = format_code


				var channel_num = bytes[fsc0 + 2] + (bytes[fsc0 + 3] << 8)


				if channel_num == 2: newstream.stereo = true


				var sample_rate = bytes[fsc0 + 4] + (bytes[fsc0 + 5] << 8) + (bytes[fsc0 + 6] << 16) + (bytes[fsc0 + 7] << 24)


				newstream.mix_rate = sample_rate


				var _byte_rate = bytes[fsc0 + 8] + (bytes[fsc0 + 9] << 8) + (bytes[fsc0 + 10] << 16) + (bytes[fsc0 + 11] << 24)



				var _bits_sample_channel = bytes[fsc0 + 12] + (bytes[fsc0 + 13] << 8)



				bits_per_sample = bytes[fsc0 + 14] + (bytes[fsc0 + 15] << 8)


			if those4bytes == "data":
				assert(bits_per_sample != 0)

				var audio_data_size = bytes[i + 4] + (bytes[i + 5] << 8) + (bytes[i + 6] << 16) + (bytes[i + 7] << 24)


				var data_entry_point = (i + 8)


				var data = bytes.subarray(data_entry_point, data_entry_point + audio_data_size - 1)

				if bits_per_sample in [24, 32]:
					newstream.data = convert_to_16bit(data, bits_per_sample)
				else:
					newstream.data = data




		var samplenum = newstream.data.size() / 4
		newstream.loop_end = samplenum
		newstream.loop_mode = int(loop)
		return newstream


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

func convert_to_16bit(data: PoolByteArray, from: int) -> PoolByteArray:
	print("converting to 16-bit from %d" % from)
	var time = OS.get_ticks_msec()


	if from == 24:
		var j = 0
		for i in range(0, data.size(), 3):
			data[j] = data[i + 1]
			data[j + 1] = data[i + 2]
			j += 2
		data.resize(data.size() * 2 / 3)


	if from == 32:
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

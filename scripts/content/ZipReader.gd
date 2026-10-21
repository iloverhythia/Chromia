extends Reference

# Reads a zip archive in GDScript (stored and deflated files), so .rhm maps
# open on every platform (phones and the browser have no unzip tool).

# A zip's files (stored or deflated) -> {name: bytes}
static func read(bytes: PoolByteArray) -> Dictionary:
	var out := {}
	var n := bytes.size()
	var end := -1
	var i := n - 22
	while i >= max(0, n - 65557):
		if bytes[i] == 0x50 and bytes[i + 1] == 0x4b and bytes[i + 2] == 0x05 and bytes[i + 3] == 0x06:
			end = i
			break
		i -= 1
	if end < 0:
		return out
	var count := _u16(bytes, end + 10)
	var p := _u32(bytes, end + 16)
	for _k in range(count):
		if p + 46 > n or _u32(bytes, p) != 0x02014b50:
			break
		var method := _u16(bytes, p + 10)
		var crc := _u32(bytes, p + 16)
		var csize := _u32(bytes, p + 20)
		var usize := _u32(bytes, p + 24)
		var name_len := _u16(bytes, p + 28)
		var extra_len := _u16(bytes, p + 30)
		var comment_len := _u16(bytes, p + 32)
		var local := _u32(bytes, p + 42)
		var name := bytes.subarray(p + 46, p + 46 + name_len - 1).get_string_from_utf8()
		p += 46 + name_len + extra_len + comment_len
		var start := local + 30 + _u16(bytes, local + 26) + _u16(bytes, local + 28)
		if csize == 0:
			out[name] = PoolByteArray()
			continue
		var data := bytes.subarray(start, start + csize - 1)
		if method == 0:
			out[name] = data
		elif method == 8:
			# raw deflate: wrapped as gzip (its crc and size from the zip) for Godot to inflate
			var gz := PoolByteArray([0x1f, 0x8b, 8, 0, 0, 0, 0, 0, 0, 0xff])
			gz.append_array(data)
			for v in [crc, usize]:
				for b in range(4):
					gz.append((v >> (8 * b)) & 0xff)
			out[name] = gz.decompress(usize, File.COMPRESSION_GZIP)
	return out

static func _u16(b: PoolByteArray, at: int) -> int:
	return b[at] | (b[at + 1] << 8)

static func _u32(b: PoolByteArray, at: int) -> int:
	return b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24)

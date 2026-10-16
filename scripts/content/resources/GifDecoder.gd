extends Reference
class_name GifDecoder

const MAX_FRAMES := 256
const MAX_DIM := 1024
const MAX_TOTAL_PIXELS := 20000000

class Reader:
	var b: PoolByteArray
	var pos: int = 0
	func _init(bytes: PoolByteArray):
		b = bytes
	func ok(n: int = 1) -> bool:
		return pos + n <= b.size()
	func u8() -> int:
		var v = b[pos]
		pos += 1
		return v
	func u16() -> int:
		var lo = u8()
		var hi = u8()
		return lo | (hi << 8)
	func skip(n: int):
		pos += n
	func read_bytes(n: int) -> PoolByteArray:
		var out = b.subarray(pos, pos + n - 1)
		pos += n
		return out
	func read_sub_blocks() -> PoolByteArray:
		var out := PoolByteArray()
		while ok(1):
			var size = u8()
			if size == 0:
				break
			if not ok(size):
				break
			out.append_array(read_bytes(size))
		return out
	func skip_sub_blocks():
		while ok(1):
			var size = u8()
			if size == 0:
				break
			skip(size)

static func can_decode(bytes: PoolByteArray) -> bool:
	if bytes.size() < 6:
		return false
	return bytes[0] == 71 and bytes[1] == 73 and bytes[2] == 70 and bytes[3] == 56

static func _make_initial_dict(min_code_size: int) -> Array:
	var clear_code = 1 << min_code_size
	var dict := []
	for i in range(clear_code):
		var single := PoolIntArray()
		single.append(i)
		dict.append(single)
	dict.append(PoolIntArray())
	dict.append(PoolIntArray())
	return dict

static func _lzw_decode(data: PoolByteArray, min_code_size: int, expected_pixels: int) -> PoolIntArray:
	var out := PoolIntArray()
	if min_code_size < 2 or min_code_size > 8 or data.size() == 0:
		return out
	var clear_code = 1 << min_code_size
	var end_code = clear_code + 1

	var dict := _make_initial_dict(min_code_size)
	var code_size = min_code_size + 1
	var next_code = end_code + 1

	var bit_pos = 0
	var total_bits = data.size() * 8
	var prev_indices := PoolIntArray()

	while bit_pos + code_size <= total_bits and out.size() < expected_pixels:
		var code = 0
		for b in range(code_size):
			var byte_index = (bit_pos + b) >> 3
			var bit_index = (bit_pos + b) & 7
			var bit = (data[byte_index] >> bit_index) & 1
			code |= (bit << b)
		bit_pos += code_size

		if code == clear_code:
			dict = _make_initial_dict(min_code_size)
			code_size = min_code_size + 1
			next_code = end_code + 1
			prev_indices = PoolIntArray()
			continue
		if code == end_code:
			break

		var entry: PoolIntArray
		if code < dict.size() and dict[code].size() > 0:
			entry = dict[code]
		elif code == next_code and prev_indices.size() > 0:
			entry = prev_indices
			entry.append(prev_indices[0])
		else:
			break

		out.append_array(entry)

		if prev_indices.size() > 0 and next_code < 4096:
			var new_entry: PoolIntArray = prev_indices
			new_entry.append(entry[0])
			if next_code >= dict.size():
				dict.append(new_entry)
			else:
				dict[next_code] = new_entry
			next_code += 1
			if next_code == (1 << code_size) and code_size < 12:
				code_size += 1

		prev_indices = entry

	return out

static func _read_color_table(r: Reader, size: int) -> Array:
	var colors := []
	for i in range(size):
		if not r.ok(3):
			colors.append(Color(0, 0, 0))
			continue
		var red = r.u8()
		var green = r.u8()
		var blue = r.u8()
		colors.append(Color(red / 255.0, green / 255.0, blue / 255.0))
	return colors

static func _clear_region(canvas: PoolByteArray, left: int, top: int, w: int, h: int, screen_w: int, screen_h: int) -> PoolByteArray:
	var x0 = max(left, 0)
	var x1 = min(left + w, screen_w)
	for y in range(h):
		var py = top + y
		if py < 0 or py >= screen_h:
			continue
		for px in range(x0, x1):
			var i = (py * screen_w + px) * 4
			canvas[i] = 0
			canvas[i + 1] = 0
			canvas[i + 2] = 0
			canvas[i + 3] = 0
	return canvas

static func _blit_frame(canvas: PoolByteArray, indices: PoolIntArray, colors: Array, w: int, h: int, left: int, top: int, interlace: bool, transparent_index: int, screen_w: int, screen_h: int) -> PoolByteArray:
	var num_colors = colors.size()
	var r_lut := PoolIntArray()
	var g_lut := PoolIntArray()
	var b_lut := PoolIntArray()
	r_lut.resize(num_colors)
	g_lut.resize(num_colors)
	b_lut.resize(num_colors)
	for ci in range(num_colors):
		var cc: Color = colors[ci]
		r_lut[ci] = int(round(cc.r * 255.0))
		g_lut[ci] = int(round(cc.g * 255.0))
		b_lut[ci] = int(round(cc.b * 255.0))

	var row_order := []
	if interlace:
		var y = 0
		while y < h:
			row_order.append(y)
			y += 8
		y = 4
		while y < h:
			row_order.append(y)
			y += 8
		y = 2
		while y < h:
			row_order.append(y)
			y += 4
		y = 1
		while y < h:
			row_order.append(y)
			y += 2
	else:
		for y2 in range(h):
			row_order.append(y2)

	for src_row in range(row_order.size()):
		var dest_y = row_order[src_row]
		var py = top + dest_y
		if py < 0 or py >= screen_h:
			continue
		var row_base = src_row * w
		for x in range(w):
			if row_base + x >= indices.size():
				continue
			var idx = indices[row_base + x]
			if idx == transparent_index or idx >= num_colors or idx < 0:
				continue
			var px = left + x
			if px < 0 or px >= screen_w:
				continue
			var i = (py * screen_w + px) * 4
			canvas[i] = r_lut[idx]
			canvas[i + 1] = g_lut[idx]
			canvas[i + 2] = b_lut[idx]
			canvas[i + 3] = 255
	return canvas

static func decode(bytes: PoolByteArray) -> Dictionary:
	if not can_decode(bytes):
		return {}
	var r := Reader.new(bytes)
	r.skip(6)
	if not r.ok(7):
		return {}
	var screen_w = r.u16()
	var screen_h = r.u16()
	var packed = r.u8()
	r.skip(2)
	var gct_flag = (packed & 128) != 0
	var gct_size = 1 << ((packed & 7) + 1)
	var global_colors := []
	if gct_flag:
		global_colors = _read_color_table(r, gct_size)

	if screen_w <= 0 or screen_h <= 0 or screen_w > MAX_DIM or screen_h > MAX_DIM:
		return {}

	var canvas := PoolByteArray()
	canvas.resize(screen_w * screen_h * 4)

	var frames := []
	var delays := []

	var pending_delay := 0.1
	var pending_transparent_index := -1
	var pending_disposal := 0

	while r.ok(1):
		var introducer = r.u8()
		if introducer == 59:
			break
		elif introducer == 33:
			if not r.ok(1):
				break
			var label = r.u8()
			if label == 249:
				r.u8()
				var gc_packed = r.u8()
				var delay_cs = r.u16()
				var trans_idx = r.u8()
				r.skip(1)
				pending_disposal = (gc_packed >> 2) & 7
				pending_transparent_index = trans_idx if (gc_packed & 1) != 0 else -1
				pending_delay = (delay_cs / 100.0) if delay_cs > 0 else 0.1
			else:
				r.skip_sub_blocks()
		elif introducer == 44:
			if not r.ok(9):
				break
			var left = r.u16()
			var top = r.u16()
			var w = r.u16()
			var h = r.u16()
			var img_packed = r.u8()
			var lct_flag = (img_packed & 128) != 0
			var interlace = (img_packed & 64) != 0
			var lct_size = 1 << ((img_packed & 7) + 1)
			var colors = global_colors
			if lct_flag:
				colors = _read_color_table(r, lct_size)
			if not r.ok(1):
				break
			var min_code_size = r.u8()
			var lzw_data = r.read_sub_blocks()
			if w <= 0 or h <= 0 or w > MAX_DIM or h > MAX_DIM:
				pending_transparent_index = -1
				pending_disposal = 0
				pending_delay = 0.1
				continue
			var indices = _lzw_decode(lzw_data, min_code_size, w * h)
			if indices.empty():
				pending_transparent_index = -1
				pending_disposal = 0
				pending_delay = 0.1
				continue

			var pre_disposal_snapshot := PoolByteArray()
			if pending_disposal == 3:
				pre_disposal_snapshot = canvas

			canvas = _blit_frame(canvas, indices, colors, w, h, left, top, interlace, pending_transparent_index, screen_w, screen_h)

			frames.append(canvas)
			delays.append(pending_delay)

			if pending_disposal == 2:
				canvas = _clear_region(canvas, left, top, w, h, screen_w, screen_h)
			elif pending_disposal == 3 and pre_disposal_snapshot.size() > 0:
				canvas = pre_disposal_snapshot

			pending_transparent_index = -1
			pending_disposal = 0
			pending_delay = 0.1

			if frames.size() >= MAX_FRAMES:
				break
			if screen_w * screen_h * (frames.size() + 1) > MAX_TOTAL_PIXELS:
				break
		else:
			break

	if frames.empty():
		return {}
	return {"frames": frames, "delays": delays, "width": screen_w, "height": screen_h}

static func decode_first_frame_image(bytes: PoolByteArray) -> Image:
	var result = decode(bytes)
	if result.empty():
		return null
	var img := Image.new()
	img.create_from_data(result.width, result.height, false, Image.FORMAT_RGBA8, result.frames[0])
	return img

static func decode_to_animated_texture(bytes: PoolByteArray) -> Texture:
	var result = decode(bytes)
	if result.empty():
		return null
	var frame_bytes_list: Array = result.frames
	var delays: Array = result.delays
	var w: int = result.width
	var h: int = result.height

	if frame_bytes_list.size() == 1:
		var img := Image.new()
		img.create_from_data(w, h, false, Image.FORMAT_RGBA8, frame_bytes_list[0])
		var tex := ImageTexture.new()
		tex.create_from_image(img)
		return tex

	var total_delay := 0.0
	for d in delays:
		total_delay += d
	var avg_delay: float = total_delay / delays.size()
	var fps: float = clamp(1.0 / max(avg_delay, 0.01), 1.0, 60.0)

	var anim := AnimatedTexture.new()
	anim.frames = frame_bytes_list.size()
	anim.fps = fps
	for i in range(frame_bytes_list.size()):
		var img := Image.new()
		img.create_from_data(w, h, false, Image.FORMAT_RGBA8, frame_bytes_list[i])
		var tex := ImageTexture.new()
		tex.create_from_image(img)
		anim.set_frame_texture(i, tex)
	return anim

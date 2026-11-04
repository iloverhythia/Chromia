extends Reference

# DXT1 / DXT3 / DXT5 (S3TC) pictures to plain RGBA8, in script. Some older
# maps keep their cover in one of these. A PC's graphics card shows them and
# can unpack them, but on the Quest (and phones) the engine can't, so those
# maps had no cover in the map list there. Only used when Image.decompress()
# fails, on the thumbnail builder's thread (each cover once: thumbnails are
# kept on disk).

static func decode(img: Image) -> Image:
	if img == null or img.is_empty():
		return null
	var fmt := img.get_format()
	if fmt != Image.FORMAT_DXT1 and fmt != Image.FORMAT_DXT3 and fmt != Image.FORMAT_DXT5:
		return null
	var w := img.get_width()
	var h := img.get_height()
	var src: PoolByteArray = img.get_data()
	var block := 8 if fmt == Image.FORMAT_DXT1 else 16
	var bw := int(max(1, (w + 3) / 4))
	var bh := int(max(1, (h + 3) / 4))
	if src.size() < bw * bh * block:
		return null
	var out := PoolByteArray()
	out.resize(w * h * 4)
	var off := 0
	for by in range(bh):
		for bx in range(bw):
			var alpha := []
			var coff := off
			if fmt == Image.FORMAT_DXT3:
				for k in range(16):
					var byte: int = src[off + k / 2]
					var a4 := (byte >> 4) & 15 if k % 2 == 1 else byte & 15
					alpha.append(a4 * 17)
				coff = off + 8
			elif fmt == Image.FORMAT_DXT5:
				var a0: int = src[off]
				var a1: int = src[off + 1]
				var pal := [a0, a1]
				if a0 > a1:
					for i in range(1, 7):
						pal.append(((7 - i) * a0 + i * a1) / 7)
				else:
					for i in range(1, 5):
						pal.append(((5 - i) * a0 + i * a1) / 5)
					pal.append(0)
					pal.append(255)
				var bits := 0
				for i in range(6):
					bits |= int(src[off + 2 + i]) << (8 * i)
				for k in range(16):
					alpha.append(pal[(bits >> (3 * k)) & 7])
				coff = off + 8
			var c0: int = src[coff] | (src[coff + 1] << 8)
			var c1: int = src[coff + 2] | (src[coff + 3] << 8)
			var cols := [_rgb565(c0), _rgb565(c1)]
			if c0 > c1 or fmt != Image.FORMAT_DXT1:
				cols.append(cols[0].linear_interpolate(cols[1], 1.0 / 3.0))
				cols.append(cols[0].linear_interpolate(cols[1], 2.0 / 3.0))
			else:
				cols.append(cols[0].linear_interpolate(cols[1], 0.5))
				cols.append(Color(0, 0, 0, 0))
			var idx: int = src[coff + 4] | (src[coff + 5] << 8) | (src[coff + 6] << 16) | (src[coff + 7] << 24)
			for k in range(16):
				var x := bx * 4 + k % 4
				var y := by * 4 + k / 4
				if x >= w or y >= h:
					continue
				var c: Color = cols[(idx >> (2 * k)) & 3]
				var p := (y * w + x) * 4
				out[p] = int(c.r * 255)
				out[p + 1] = int(c.g * 255)
				out[p + 2] = int(c.b * 255)
				out[p + 3] = int(alpha[k]) if not alpha.empty() else int(c.a * 255)
			off += block
	var res := Image.new()
	res.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)
	return res

static func _rgb565(v: int) -> Color:
	return Color(((v >> 11) & 31) / 31.0, ((v >> 5) & 63) / 63.0, (v & 31) / 31.0, 1.0)

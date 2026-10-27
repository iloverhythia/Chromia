extends Reference

# A small QR code maker (byte mode, error correction level M, versions 1-20,
# so up to about 330 bytes of text). Used for the VR Discord login: scan the
# code with your phone instead of typing a long link in the headset.
# Follows Project Nayuki's QR code generator (MIT), simplified.
#
#   var modules: Array = QRCode.encode("https://...")  # rows of bools
#   var tex: ImageTexture = QRCode.texture("https://...", 8)

# error correction codewords per block, and blocks, for level M (index = version)
const ECC_PER_BLOCK := [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26]
const BLOCKS := [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16]
const FORMAT_M := 0 # format bits for level M

static func _raw_modules(ver: int) -> int:
	var r: int = (16 * ver + 128) * ver + 64
	if ver >= 2:
		var na: int = ver / 7 + 2
		r -= (25 * na - 10) * na - 55
		if ver >= 7:
			r -= 36
	return r

static func _data_codewords(ver: int) -> int:
	return _raw_modules(ver) / 8 - ECC_PER_BLOCK[ver] * BLOCKS[ver]

static func _align_positions(ver: int) -> Array:
	if ver == 1:
		return []
	var na: int = ver / 7 + 2
	var size: int = ver * 4 + 17
	var step: int = (ver * 4 + na * 2 + 1) / (na * 2 - 2) * 2
	var out := []
	out.resize(na)
	out[0] = 6
	var pos: int = size - 7
	for i in range(na - 1, 0, -1):
		out[i] = pos
		pos -= step
	return out

static func _gf_mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = ((z << 1) ^ ((z >> 7) * 0x11D)) & 0xFF
		z ^= ((y >> i) & 1) * x
	return z & 0xFF

static func _rs_divisor(degree: int) -> Array:
	var r := []
	for i in range(degree - 1):
		r.append(0)
	r.append(1)
	var root := 1
	for _i in range(degree):
		for j in range(degree):
			r[j] = _gf_mul(r[j], root)
			if j + 1 < degree:
				r[j] ^= r[j + 1]
		root = _gf_mul(root, 0x02)
	return r

static func _rs_remainder(data: Array, divisor: Array) -> Array:
	var r := []
	for _i in range(divisor.size()):
		r.append(0)
	for b in data:
		var factor: int = int(b) ^ int(r[0])
		r.pop_front()
		r.append(0)
		for i in range(r.size()):
			r[i] ^= _gf_mul(divisor[i], factor)
	return r

# rows (y) of columns (x): true = dark. [] if the text is too long.
static func encode(text: String) -> Array:
	var bytes: PoolByteArray = text.to_utf8()
	var ver := 0
	for v in range(1, 21):
		var cc_bits: int = 8 if v <= 9 else 16
		if 4 + cc_bits + bytes.size() * 8 <= _data_codewords(v) * 8:
			ver = v
			break
	if ver == 0:
		return []
	# --- data bits
	var bits := []
	_put(bits, 0x4, 4) # byte mode
	_put(bits, bytes.size(), 8 if ver <= 9 else 16)
	for b in bytes:
		_put(bits, b, 8)
	var cap: int = _data_codewords(ver) * 8
	_put(bits, 0, min(4, cap - bits.size()))
	_put(bits, 0, (8 - bits.size() % 8) % 8)
	var pad := 0xEC
	while bits.size() < cap:
		_put(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var data := []
	for i in range(0, bits.size(), 8):
		var v := 0
		for k in range(8):
			v = (v << 1) | int(bits[i + k])
		data.append(v)
	# --- error correction, interleaved
	var nb: int = BLOCKS[ver]
	var ecc_len: int = ECC_PER_BLOCK[ver]
	var raw: int = _raw_modules(ver) / 8
	var n_short: int = nb - raw % nb
	var short_len: int = raw / nb
	var divisor := _rs_divisor(ecc_len)
	var blocks := []
	var k := 0
	for i in range(nb):
		var n: int = short_len - ecc_len + (0 if i < n_short else 1)
		var dat: Array = data.slice(k, k + n - 1)
		k += n
		var ecc := _rs_remainder(dat, divisor)
		if i < n_short:
			dat.append(0)
		blocks.append(dat + ecc)
	var all := []
	for i in range(blocks[0].size()):
		for j in range(blocks.size()):
			if i != short_len - ecc_len or j >= n_short:
				all.append(blocks[j][i])
	# --- the grid
	var size: int = ver * 4 + 17
	var m := []
	var fn := []
	for y in range(size):
		var row := []
		var frow := []
		for x in range(size):
			row.append(false)
			frow.append(false)
		m.append(row)
		fn.append(frow)
	for i in range(size):
		_mod(m, fn, 6, i, i % 2 == 0)
		_mod(m, fn, i, 6, i % 2 == 0)
	for c in [[3, 3], [size - 4, 3], [3, size - 4]]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var xx: int = c[0] + dx
				var yy: int = c[1] + dy
				if xx >= 0 and xx < size and yy >= 0 and yy < size:
					var dist: int = int(max(abs(dx), abs(dy)))
					_mod(m, fn, xx, yy, dist != 2 and dist != 4)
	var al := _align_positions(ver)
	var na: int = al.size()
	for i in range(na):
		for j in range(na):
			if (i == 0 and j == 0) or (i == 0 and j == na - 1) or (i == na - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_mod(m, fn, al[i] + dx, al[j] + dy, int(max(abs(dx), abs(dy))) != 1)
	_format(m, fn, size, 0) # reserve (redrawn below)
	if ver >= 7:
		var rem: int = ver
		for _i in range(12):
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var vbits: int = ver << 12 | rem
		for i in range(18):
			var bit: bool = ((vbits >> i) & 1) != 0
			var a: int = size - 11 + i % 3
			var b: int = i / 3
			_mod(m, fn, a, b, bit)
			_mod(m, fn, b, a, bit)
	# --- codewords, zigzag
	var bi := 0
	var right: int = size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in range(size):
			for j in range(2):
				var x: int = right - j
				var up: bool = ((right + 1) & 2) == 0
				var y: int = size - 1 - vert if up else vert
				if not fn[y][x] and bi < all.size() * 8:
					m[y][x] = ((int(all[bi >> 3]) >> (7 - (bi & 7))) & 1) != 0
					bi += 1
		right -= 2
	# --- mask 0 ((x + y) even) and the real format bits
	for y in range(size):
		for x in range(size):
			if not fn[y][x] and (x + y) % 2 == 0:
				m[y][x] = not m[y][x]
	_format(m, fn, size, 0)
	return m

static func _put(bits: Array, val: int, n: int):
	for i in range(n - 1, -1, -1):
		bits.append((val >> i) & 1)

static func _mod(m: Array, fn: Array, x: int, y: int, dark: bool):
	m[y][x] = dark
	fn[y][x] = true

static func _format(m: Array, fn: Array, size: int, mask: int):
	var data: int = FORMAT_M << 3 | mask
	var rem: int = data
	for _i in range(10):
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits: int = (data << 10 | rem) ^ 0x5412
	for i in range(6):
		_mod(m, fn, 8, i, ((bits >> i) & 1) != 0)
	_mod(m, fn, 8, 7, ((bits >> 6) & 1) != 0)
	_mod(m, fn, 8, 8, ((bits >> 7) & 1) != 0)
	_mod(m, fn, 7, 8, ((bits >> 8) & 1) != 0)
	for i in range(9, 15):
		_mod(m, fn, 14 - i, 8, ((bits >> i) & 1) != 0)
	for i in range(8):
		_mod(m, fn, size - 1 - i, 8, ((bits >> i) & 1) != 0)
	for i in range(8, 15):
		_mod(m, fn, 8, size - 15 + i, ((bits >> i) & 1) != 0)
	_mod(m, fn, 8, size - 8, true)

# The code as a texture: black on white, scale pixels a module, with the
# 4-module white border scanners need.
static func texture(text: String, scale: int = 8) -> ImageTexture:
	var m := encode(text)
	if m.empty():
		return null
	var size: int = m.size()
	var px: int = (size + 8) * scale
	var img := Image.new()
	img.create(px, px, false, Image.FORMAT_RGB8)
	img.fill(Color(1, 1, 1))
	img.lock()
	for y in range(size):
		for x in range(size):
			if m[y][x]:
				for yy in range(scale):
					for xx in range(scale):
						img.set_pixel((x + 4) * scale + xx, (y + 4) * scale + yy, Color(0, 0, 0))
	img.unlock()
	var t := ImageTexture.new()
	t.create_from_image(img, 0) # no filtering: crisp squares
	return t

extends Reference

# Moving profile pictures and banners (GIFs). The server keeps a small GIF
# next to an animated upload (savia_web profile.js) and sends its address as
# avatar_gif_url / banner_gif_url (the online list, public profiles). Places
# that show a picture ask pic_url() / banner_url() which address to load, and
# hand the downloaded bytes to load_async() when they are a GIF: it decodes
# them on a thread (GifDecoder, in GDScript, takes a moment), rounds every
# frame for a profile picture, then makes an AnimatedTexture on the main
# thread and calls back with it. Results are kept per address.

const MAX_FRAMES := 90

# p: an online player / public profile dictionary
static func pic_url(p: Dictionary) -> String:
	var g := String(p.get("avatar_gif_url", "")) if p.get("avatar_gif_url") != null else ""
	return g if g != "" else (String(p.get("avatar_url", "")) if p.get("avatar_url") != null else "")

static func banner_url(p: Dictionary) -> String:
	var g := String(p.get("banner_gif_url", "")) if p.get("banner_gif_url") != null else ""
	return g if g != "" else (String(p.get("banner_url", "")) if p.get("banner_url") != null else "")

static func is_gif(bytes: PoolByteArray) -> bool:
	return bytes.size() > 6 and bytes[0] == 0x47 and bytes[1] == 0x49 and bytes[2] == 0x46

static func _cache() -> Dictionary:
	if not Engine.has_meta("animpic_cache"):
		Engine.set_meta("animpic_cache", {})
	return Engine.get_meta("animpic_cache")

static func cached(key: String):
	return _cache().get(key)

# Decode `bytes` (a GIF) on a thread; then target.call(method, texture, *binds)
# on the main thread (texture: an AnimatedTexture, or an ImageTexture for a
# one-frame GIF, or null if it couldn't be read).
# px > 0: made px x px (square from the middle); round: a round picture.
# key: kept under this (the address), handed back at once next time.
static func load_async(bytes: PoolByteArray, key: String, px: int, round_it: bool, target: Object, method: String, binds: Array = []):
	if key != "" and _cache().has(key):
		target.callv(method, [_cache()[key]] + binds)
		return
	var job = Job.new()
	job.start(bytes, key, px, round_it, target, method, binds)

class Job extends Reference:
	var thread := Thread.new()
	var bytes: PoolByteArray
	var key := ""
	var px := 0
	var round_it := false
	var target: WeakRef
	var method := ""
	var binds := []
	var frames := [] # Images
	var delays := []

	func start(b: PoolByteArray, k: String, p: int, r: bool, t: Object, m: String, bi: Array):
		bytes = b
		key = k
		px = p
		round_it = r
		target = weakref(t)
		method = m
		binds = bi
		# (kept alive until it's done)
		if not Engine.has_meta("animpic_jobs"):
			Engine.set_meta("animpic_jobs", [])
		Engine.get_meta("animpic_jobs").append(self)
		if OS.can_use_threads():
			thread.start(self, "_work")
		else:
			_work(null)

	func _work(_u):
		var res: Dictionary = GifDecoder.decode(bytes)
		if not res.empty():
			var w: int = res.width
			var h: int = res.height
			var n: int = min(res.frames.size(), 90)
			for i in n:
				var img := Image.new()
				img.create_from_data(w, h, false, Image.FORMAT_RGBA8, res.frames[i])
				if px > 0:
					var side: int = min(w, h)
					if w != h:
						img = img.get_rect(Rect2((w - side) / 2, (h - side) / 2, side, side))
					img.resize(px, px, Image.INTERPOLATE_BILINEAR)
					if round_it:
						_round(img, px)
				frames.append(img)
				delays.append(float(res.delays[i]) if i < res.delays.size() else 0.1)
		call_deferred("_done")

	static func _round(img: Image, s: int):
		var c := (s - 1) / 2.0
		var rad := s / 2.0
		img.lock()
		for y in s:
			for x in s:
				var d := Vector2(x - c, y - c).length()
				if d > rad - 1.5:
					var cc := img.get_pixel(x, y)
					cc.a *= clamp((rad - d) / 1.5, 0.0, 1.0)
					img.set_pixel(x, y, cc)
		img.unlock()

	func _done():
		if thread.is_active():
			thread.wait_to_finish()
		var tex: Texture = null
		if frames.size() == 1:
			var t1 := ImageTexture.new()
			t1.create_from_image(frames[0])
			tex = t1
		elif frames.size() > 1:
			var anim := AnimatedTexture.new()
			anim.frames = frames.size()
			anim.fps = 0 # (each frame keeps its own delay)
			for i in frames.size():
				var t := ImageTexture.new()
				t.create_from_image(frames[i])
				anim.set_frame_texture(i, t)
				anim.set_frame_delay(i, clamp(float(delays[i]), 0.02, 2.0))
			tex = anim
		if tex != null and key != "":
			var c: Dictionary = Engine.get_meta("animpic_cache") if Engine.has_meta("animpic_cache") else {}
			c[key] = tex
			Engine.set_meta("animpic_cache", c)
		var t2 = target.get_ref()
		if t2 != null:
			t2.callv(method, [tex] + binds)
		Engine.get_meta("animpic_jobs").erase(self)

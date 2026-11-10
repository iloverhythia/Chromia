extends Reference

# Settings transfer (Settings > Transfer, TransferTab.gd): packs your settings
# and custom content into one bundle, to move it to another device. Everything
# in the user folder goes except maps (unless Include maps is ticked: they
# follow as a stream), replays, scores / progress, logs and caches, and a few settings that belong to the device (window, frame rate,
# touch layout, mouse sensitivity, audio offset).
#
# The bundle goes over the local network with a transfer code, or as a file.
# A code is 12 letters / digits: the sending device's local IP address, which
# of 4 ports it listens on, and a random 26-bit PIN (the one-time password).
#
# Bundle: "CHROMIASET1", u32 raw size, deflate(var2bytes({
#   v, version, from, settings (dict), cfg ({section: {key: value}}),
#   files: [[root "p" / "u", relative path, bytes], ...],
#   maps: how many maps follow, maps_size }))
#
# Maps (optional, "Include maps"): too big to hold in memory, so they follow
# the bundle as a stream, one file at a time (MapSource / MapSink below):
#   per map: u16 name length, name ("maps/x.sspm" or "vmaps/..."), u64 size,
#   the file's bytes; then u16 0. Over the network the bundle's size is sent
#   first, so it's the bundle and then the stream. A file with maps is
#   "CHROMIASET2", u32 raw size, u32 packed size, the packed bundle, the stream.

const MAGIC := "CHROMIASET1"
const MAGIC2 := "CHROMIASET2" # (a file with maps after the bundle)
const PORTS := [47821, 47822, 47823, 47824]
const MAX_FILE := 64 * 1024 * 1024
const MAX_TOTAL := 256 * 1024 * 1024
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ" # Crockford base 32

# top-level folders / files of the user folder that never go
const SKIP_DIRS := ["maps", "vmaps", "packs", "mods", "replays", "logs", "caches", "cache",
	"editor", "pack_update", "savia", "score_history", "play_tracking", "bests", "chromia", "friend",
	"temp", "imported", "_picked_content", "chromia_upload", "chromia_export", "transfer",
	"crashes", "downloads"]
const SKIP_FILES := ["settings.json", "settings", "settings.cfg", "active_profile.txt",
	"map_cache.json", "map_browser.json", "map_folders.txt", "map_folders.json",
	"vmap_folders.txt", "install_path.txt", "pb.json", "pb", "stats.json", "level.json",
	"rp_plays.json", "furry_tree.json", ".sound_space_backup.json", "mapdl.sspm.part",
	"upgrade_temp.sspm"]
const SKIP_EXT := ["sspm", "sspre", "rhm", "osu", "zip", "part", "dat", "tmp", "import"]
# settings that stay as they are on the receiving device
const DEVICE_KEYS := ["resolution", "window_fullscreen", "window_borderless", "auto_maximize",
	"vsync_enabled", "target_fps", "max_fps_mode", "mirror_buttons", "mobile_high_hz",
	"mobile_no_delay", "mobile_old_cursor", "touch_style", "show_touch_indicator", "lock_mouse", "sensitivity",
	"absolute_mode", "absolute_scale", "ignore_controller_detection", "music_offset",
	"vr_play_lock", "vr_play_lock_frame", "vr_play_lock_pitch"] # (a headset's place in its room)
const CFG_SKIP_SECTIONS := ["internal", "profile"]

# --- Where things are --------------------------------------------------------
# On Android (phones, Meta Quest) the game keeps files in two places: the
# folder Globals.p() points to, and the app's own user:// folder. Elsewhere
# they are the same folder.
static func roots() -> Dictionary:
	var out = {"u": "user://"}
	var p: String = Globals.p("user://")
	if p != "user://":
		out["p"] = p
	return out

static func _skip_top(name: String, is_dir: bool) -> bool:
	if name.begins_with("tmp_") or name.begins_with("."):
		return true
	if is_dir:
		return SKIP_DIRS.has(name)
	return SKIP_FILES.has(name) or SKIP_EXT.has(name.get_extension().to_lower())

static func _list(base: String, rel: String, out: Array):
	var d = Directory.new()
	if d.open(base.plus_file(rel) if rel != "" else base) != OK:
		return
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		var r: String = rel.plus_file(n) if rel != "" else n
		var is_dir = d.current_is_dir()
		if rel != "" or not _skip_top(n, is_dir):
			if is_dir:
				_list(base, r, out)
			elif not SKIP_EXT.has(n.get_extension().to_lower()) or rel == "":
				out.append(r)
		n = d.get_next()
	d.list_dir_end()

# --- Packing -----------------------------------------------------------------
static func build_bundle(maps: Array = [], file_with_maps: bool = false) -> Dictionary:
	var files = []
	var total = 0
	var skipped = []
	var seen = {}
	var rs = roots()
	for tag in ["p", "u"]:
		if not rs.has(tag):
			continue
		var list = []
		_list(rs[tag], "", list)
		for rel in list:
			if seen.has(rel):
				continue
			var f = File.new()
			if f.open(String(rs[tag]).plus_file(rel), File.READ) != OK:
				continue
			var n: int = f.get_len()
			if n > MAX_FILE or total + n > MAX_TOTAL:
				skipped.append(rel)
				f.close()
				continue
			files.append([tag, rel, f.get_buffer(n)])
			f.close()
			seen[rel] = true
			total += n
	var settings = {}
	var f = File.new()
	if f.open(Rhythia.get_startup_settings_path(), File.READ) == OK:
		var parsed = parse_json(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			settings = parsed
	var cfg = {}
	var c = ConfigFile.new()
	if c.load("user://settings.cfg") == OK:
		for s in c.get_sections():
			if CFG_SKIP_SECTIONS.has(s):
				continue
			cfg[s] = {}
			for k in c.get_section_keys(s):
				cfg[s][k] = c.get_value(s, k)
	var data = {
		"v": 1,
		"version": str(ProjectSettings.get_setting("application/config/version")),
		"from": device_name(),
		"settings": settings,
		"cfg": cfg,
		"files": files,
		"maps": maps.size(),
		"maps_size": maps_size(maps),
	}
	var raw: PoolByteArray = var2bytes(data)
	var comp: PoolByteArray = raw.compress(File.COMPRESSION_DEFLATE)
	var packed = PoolByteArray()
	packed.append_array((MAGIC2 if file_with_maps else MAGIC).to_ascii())
	var head = StreamPeerBuffer.new()
	head.put_u32(raw.size())
	if file_with_maps:
		head.put_u32(comp.size())
	packed.append_array(head.data_array)
	packed.append_array(comp)
	return {"bytes": packed, "files": files.size(), "size": total, "skipped": skipped}

static func device_name() -> String:
	if OS.has_feature("quest"):
		return "Meta Quest"
	var n = OS.get_name()
	var m = OS.get_model_name()
	if m != "" and m != "GenericDevice":
		return "%s (%s)" % [n, m]
	return n

# --- Unpacking ---------------------------------------------------------------
# The start of a transfer file: how big its bundle part is (a file with maps
# has more after it), or -1 if it isn't one.
static func bundle_length(head: PoolByteArray, file_size: int) -> int:
	var ml = MAGIC.length()
	if head.size() < ml + 8:
		return file_size if head.size() >= ml and head.subarray(0, ml - 1).get_string_from_ascii() == MAGIC else -1
	var m: String = head.subarray(0, ml - 1).get_string_from_ascii()
	if m == MAGIC:
		return file_size
	if m != MAGIC2:
		return -1
	var sp = StreamPeerBuffer.new()
	sp.data_array = head.subarray(ml + 4, ml + 7)
	return ml + 8 + sp.get_u32()

static func read_bundle(bytes: PoolByteArray) -> Dictionary:
	var ml = MAGIC.length()
	if bytes.size() < ml + 4:
		return {"error": "That isn't a Chromia settings transfer."}
	var magic: String = bytes.subarray(0, ml - 1).get_string_from_ascii()
	if magic != MAGIC and magic != MAGIC2:
		return {"error": "That isn't a Chromia settings transfer."}
	var head = StreamPeerBuffer.new()
	head.data_array = bytes.subarray(ml, ml + 3)
	var raw_size: int = head.get_u32()
	if raw_size <= 0 or raw_size > MAX_TOTAL * 2:
		return {"error": "The transfer is damaged."}
	var start: int = ml + 4
	var end: int = bytes.size() - 1
	if magic == MAGIC2:
		if bytes.size() < ml + 8:
			return {"error": "The transfer is damaged."}
		head.data_array = bytes.subarray(ml + 4, ml + 7)
		start = ml + 8
		end = min(bytes.size() - 1, start + head.get_u32() - 1)
	var raw: PoolByteArray = bytes.subarray(start, end).decompress(raw_size, File.COMPRESSION_DEFLATE)
	if raw.size() != raw_size:
		return {"error": "The transfer is damaged."}
	var data = bytes2var(raw, false)
	if not (data is Dictionary) or not (data.get("files") is Array) or not (data.get("settings") is Dictionary):
		return {"error": "The transfer is damaged."}
	var total = 0
	var good = []
	for e in data.files:
		if e is Array and e.size() == 3 and e[1] is String and e[2] is PoolByteArray and _safe_rel(e[1]):
			good.append(e)
			total += e[2].size()
	data.files = good
	data["size"] = total
	return {"data": data}

# only plain paths inside the user folder
static func _safe_rel(rel: String) -> bool:
	if rel == "" or rel.begins_with("/") or rel.find("\\") != -1 or rel.find(":") != -1:
		return false
	for part in rel.split("/"):
		if part == "" or part == "." or part == "..":
			return false
	var top: String = rel.split("/")[0]
	return not _skip_top(top, rel.find("/") != -1)

# Writes the bundle on this device. Your settings from before are kept as the
# profile "before transfer" (Settings > Select Profile) to go back to.
static func apply_bundle(data: Dictionary) -> Dictionary:
	var rs = roots()
	var written = 0
	var failed = 0
	var dir = Directory.new()
	var startup: String = Rhythia.get_startup_settings_path()
	# keep the old settings as a profile
	var old = {}
	var f = File.new()
	if f.open(startup, File.READ) == OK:
		var parsed = parse_json(f.get_as_text())
		f.close()
		if parsed is Dictionary:
			old = parsed
			var pdir: String = Globals.p(Rhythia.PROFILES_DIR)
			dir.make_dir_recursive(pdir)
			if f.open(pdir.plus_file("before transfer.settings.json"), File.WRITE) == OK:
				f.store_string(to_json(old))
				f.close()
	for e in data.files:
		var rel: String = e[1]
		var top: String = rel.split("/")[0]
		# Android: put it where this device keeps it; if neither has it yet, both
		var targets = []
		for tag in rs:
			if dir.dir_exists(String(rs[tag]).plus_file(top)) or dir.file_exists(String(rs[tag]).plus_file(top)):
				targets.append(rs[tag])
		if targets.empty():
			targets = rs.values()
		for base in targets:
			var path: String = String(base).plus_file(rel)
			dir.make_dir_recursive(path.get_base_dir())
			if f.open(path, File.WRITE) == OK:
				f.store_buffer(e[2])
				f.close()
				written += 1
			else:
				failed += 1
	# settings: theirs, except what belongs to this device
	var merged: Dictionary = data.settings.duplicate(true)
	for k in DEVICE_KEYS:
		if old.has(k):
			merged[k] = old[k]
		else:
			merged.erase(k)
	for path in [startup, Globals.p("user://settings.json")]:
		if f.open(path, File.WRITE) == OK:
			f.store_string(to_json(merged))
			f.close()
	# keybinds and the other settings.cfg parts
	if data.get("cfg") is Dictionary:
		var c = ConfigFile.new()
		c.load("user://settings.cfg")
		for s in data.cfg:
			if CFG_SKIP_SECTIONS.has(s) or not (data.cfg[s] is Dictionary):
				continue
			for k in data.cfg[s]:
				c.set_value(s, k, data.cfg[s][k])
		c.save("user://settings.cfg")
	return {"written": written, "failed": failed}

# --- Maps --------------------------------------------------------------------
const MAP_DIRS := ["maps", "vmaps"]
const MAP_SKIP_EXT := ["part", "tmp"]

static func map_dir(kind: String) -> String:
	return Rhythia.user_vmap_dir if kind == "vmaps" else Rhythia.user_map_dir

# every map file: [name ("maps/x.sspm"), full path, size]
static func list_maps() -> Array:
	var out := []
	for kind in MAP_DIRS:
		var files := []
		_list_all(map_dir(kind), "", files)
		for rel in files:
			if MAP_SKIP_EXT.has(String(rel).get_extension().to_lower()):
				continue
			var path: String = map_dir(kind).plus_file(rel)
			var f := File.new()
			if f.open(path, File.READ) == OK:
				out.append([kind + "/" + rel, path, f.get_len()])
				f.close()
	return out

static func _list_all(base: String, rel: String, out: Array):
	var d = Directory.new()
	if d.open(base.plus_file(rel) if rel != "" else base) != OK:
		return
	d.list_dir_begin(true, true)
	var n = d.get_next()
	while n != "":
		var r: String = rel.plus_file(n) if rel != "" else n
		if d.current_is_dir():
			_list_all(base, r, out)
		else:
			out.append(r)
		n = d.get_next()
	d.list_dir_end()

static func maps_size(maps: Array) -> int:
	var t := 0
	for m in maps:
		t += int(m[2])
	return t

# a name from the other device: "maps/..." or "vmaps/...", nothing outside
static func safe_map_name(name: String) -> bool:
	if name == "" or name.begins_with("/") or name.find("\\") != -1 or name.find(":") != -1:
		return false
	var parts := name.split("/")
	if parts.size() < 2 or not MAP_DIRS.has(parts[0]):
		return false
	for part in parts:
		if part == "" or part == "." or part == "..":
			return false
	return true

static func map_target(name: String) -> String:
	var i := name.find("/")
	return map_dir(name.substr(0, i)).plus_file(name.substr(i + 1))

# The sending side: the map stream, a piece at a time (next() -> bytes, empty
# when it's all out). Files are read as they go, never all at once.
class MapSource extends Reference:
	var maps := []
	var i := 0
	var f: File = null
	var left := 0
	var ended := false
	var sent_maps := 0
	func _init(list: Array):
		maps = list
	func next(max_bytes: int) -> PoolByteArray:
		if ended:
			return PoolByteArray()
		if f == null:
			while i < maps.size():
				var m: Array = maps[i]
				i += 1
				var nf := File.new()
				if nf.open(m[1], File.READ) != OK:
					continue
				f = nf
				left = f.get_len()
				var name: PoolByteArray = String(m[0]).to_utf8()
				var h := StreamPeerBuffer.new()
				h.put_u16(name.size())
				h.put_data(name)
				h.put_u64(left)
				return h.data_array
			ended = true
			var e := StreamPeerBuffer.new()
			e.put_u16(0)
			return e.data_array
		var n: int = min(max_bytes, left)
		var b: PoolByteArray = f.get_buffer(n) if n > 0 else PoolByteArray()
		left -= n
		if left <= 0:
			f.close()
			f = null
			sent_maps += 1
		return b

# The receiving side: bytes in (feed), maps written as they arrive. A map you
# already have (same name and size) is left as it is.
class MapSink extends Reference:
	var buf := PoolByteArray()
	var f: File = null
	var path := ""
	var skipping := false
	var left := 0
	var done := false
	var failed := false
	var got := 0 # maps through (added + kept + errors)
	var added := 0
	var kept := 0
	var errors := 0
	func feed(b: PoolByteArray):
		buf.append_array(b)
		while not done and not failed:
			if path != "":
				if left > 0:
					if buf.empty():
						return
					var n: int = min(left, buf.size())
					if f != null:
						f.store_buffer(buf.subarray(0, n - 1))
					buf = buf.subarray(n, buf.size() - 1) if n < buf.size() else PoolByteArray()
					left -= n
				if left == 0:
					_finish()
				continue
			if buf.size() < 2:
				return
			var sp := StreamPeerBuffer.new()
			sp.data_array = buf.subarray(0, 1)
			var nl: int = sp.get_u16()
			if nl == 0:
				done = true
				buf = PoolByteArray()
				return
			if buf.size() < 2 + nl + 8:
				return
			var name: String = buf.subarray(2, 1 + nl).get_string_from_utf8()
			sp.data_array = buf.subarray(2 + nl, 9 + nl)
			var size: int = sp.get_u64()
			buf = buf.subarray(10 + nl, buf.size() - 1) if buf.size() > 10 + nl else PoolByteArray()
			var ST = load("res://scripts/SettingsTransfer.gd")
			if not ST.safe_map_name(name) or size < 0 or size > 2147483647:
				failed = true
				return
			path = ST.map_target(name)
			left = size
			f = null
			skipping = false
			var have := File.new()
			if have.open(path, File.READ) == OK:
				skipping = have.get_len() == size
				have.close()
			if not skipping:
				Directory.new().make_dir_recursive(path.get_base_dir())
				f = File.new()
				if f.open(path + ".part", File.WRITE) != OK:
					f = null
	func _finish():
		if f != null:
			f.close()
			f = null
			var d := Directory.new()
			if d.file_exists(path):
				d.remove(path)
			if d.rename(path + ".part", path) == OK:
				added += 1
			else:
				errors += 1
		elif skipping:
			kept += 1
		else:
			errors += 1
		got += 1
		path = ""
		skipping = false

# --- Codes -------------------------------------------------------------------
static func make_code(ip: String, port_index: int, pin: int) -> String:
	var parts = ip.split(".")
	var n = 0
	for p in parts:
		n = (n << 8) | (int(p) & 255)
	n = (n << 2) | (port_index & 3)
	n = (n << 26) | (pin & 0x3ffffff)
	var s = ""
	for i in range(12):
		s = ALPHABET[n & 31] + s
		n = n >> 5
	return s.substr(0, 4) + "-" + s.substr(4, 4) + "-" + s.substr(8, 4)

# {ip, port, pin}, or {} if it isn't a code
static func parse_code(text: String) -> Dictionary:
	var t = text.to_upper().replace("-", "").replace(" ", "").replace("O", "0").replace("I", "1").replace("L", "1")
	if t.length() != 12:
		return {}
	var n = 0
	for ch in t:
		var v = ALPHABET.find(ch)
		if v < 0:
			return {}
		n = (n << 5) | v
	var pin: int = n & 0x3ffffff
	n = n >> 26
	var port: int = PORTS[n & 3]
	n = n >> 2
	var ip = "%d.%d.%d.%d" % [(n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255]
	return {"ip": ip, "port": port, "pin": pin}

# This device's address on the local network (Wi-Fi / Ethernet), or "".
static func local_ip() -> String:
	var best = ""
	var best_rank = 99
	for a in IP.get_local_addresses():
		var ip = String(a)
		if ip.find(":") != -1 or ip.split(".").size() != 4:
			continue
		var p = ip.split(".")
		var rank = 99
		if p[0] == "192" and p[1] == "168":
			rank = 0
		elif p[0] == "10":
			rank = 1
		elif p[0] == "172" and int(p[1]) >= 16 and int(p[1]) <= 31:
			rank = 2
		elif p[0] != "127" and not (p[0] == "169" and p[1] == "254"):
			rank = 3
		if rank < best_rank:
			best_rank = rank
			best = ip
	return best

static func human_size(n: int) -> String:
	if n >= 1024 * 1024:
		return "%.1f MB" % (n / 1048576.0)
	if n >= 1024:
		return "%d KB" % int(n / 1024)
	return "%d bytes" % n

extends Node

# Moving everything from the sideloaded Meta Quest app to the store one
# (Settings > Transfer > "Move to the store version").
#
# To the headset they are two different apps. Each keeps its files in a
# private folder the other can't read, and only one of them runs at a time,
# so nothing can be handed over on the headset itself. It goes through the
# game's server instead (savia_web: server/src/storetransfer.js):
#
#   the sideloaded game   packs everything into one file, uploads it in parts
#                         and shows a code of 8 letters and digits;
#   the store game        is given the code, downloads the parts, and puts the
#                         files in a waiting folder. They move into place at
#                         its next start, before anything is read (apply_staged,
#                         called by PackUpdate.gd, the first script to run), so
#                         nothing the running game saves can overwrite them.
#
# Everything goes: the account (so the store game is the same player),
# settings and profiles, scores, level and progress, colorsets, meshes,
# sounds, skins, hands, and (ticked by default) maps and replays. Not logs,
# caches, or a downloaded update of the sideloaded app.
#
# The packed file: "CHROMIAMOVE1", u32 length + a JSON header {v, version,
# roots: {tag: the folder it was in}}, then per file: u8 tag ('p' / 'u'),
# u16 length + path, u64 size, the bytes; a 0 byte ends it.

signal progress(text, part) # part: 0..1, or -1 when there is nothing to measure
signal finished(ok, text, code)

const MAGIC := "CHROMIAMOVE1"
const TMP := "user://store_transfer.tmp"
const STAGE := "_store_transfer_in"
const READY := "user://store_transfer_ready.txt" # the waiting folder is whole: move it in at the next start
const NOTICE := "user://store_transfer_done.txt" # moved in: the menu says so once
const ASKED := "user://store_transfer_asked.txt" # the store version offered it once

const SKIP_TOP := ["logs", "cache", "caches", "shader_cache", "temp", "pack_update", "transfer", "crashes",
	"_picked_content", "chromia_upload", "chromia_export", "spectate_cache", "tools", "render", "vulkan",
	STAGE, "downloads"]
const SKIP_FILES := ["map_cache.json", "install_path.txt", "store_transfer.tmp", "store_transfer_ready.txt",
	"store_transfer_done.txt", "store_transfer_asked.txt", "mapdl.sspm.part", "upgrade_temp.sspm"]
const SKIP_EXT := ["part", "tmp", "import"]
const MAP_TOP := ["maps", "vmaps", "packs"]
const REPLAY_TOP := ["replays"]
const TEXT_EXT := ["json", "txt", "cfg"] # (small ones: the old app's folder in them becomes this app's)
const CHUNK := 1024 * 1024
const MB := 1024.0 * 1024.0

var busy := false
var _stop := false

# --- which build this is ---------------------------------------------------------

# the Meta Horizon Store version (it takes a transfer in)
static func is_store() -> bool:
	return OS.has_feature("store") or (OS.is_debug_build() and OS.get_environment("CHROMIA_STORE") == "1")

# the sideloaded Meta Quest app (it sends one)
static func can_send() -> bool:
	return (OS.has_feature("quest") and not OS.has_feature("store")) or (OS.is_debug_build() and OS.get_environment("CHROMIA_STORE_SEND") == "1")

# The production server, also from a test build (the store version is always
# on it). Written in pieces: the test builds' server address is put in place
# of the whole name wherever it stands in the scripts.
static func base_url() -> String:
	var dbg := OS.get_environment("CHROMIA_TRANSFER_URL") if OS.is_debug_build() else ""
	if dbg != "":
		return dbg
	return "https://" + "savia" + ".nysr" + ".host"

# the folders the game keeps files in: {"u": user://, "p": the Android files folder}
static func roots() -> Dictionary:
	var out := {"u": "user://"}
	if OS.has_feature("Android"):
		var p: String = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP, false)
		if p != "" and p != "RETRY":
			out["p"] = p.rstrip("/") + "/"
	return out

static func _abs(root: String) -> String:
	return ProjectSettings.globalize_path(root).rstrip("/") if root.begins_with("user://") else root.rstrip("/")

# --- what there is to send ---------------------------------------------------------

static func _kind(rel: String) -> String:
	var top := rel.split("/")[0]
	if MAP_TOP.has(top) or rel.get_extension().to_lower() == "sspm":
		return "maps"
	if REPLAY_TOP.has(top):
		return "replays"
	return "rest"

static func _walk(base: String, rel: String, out: Array, tag: String):
	var d := Directory.new()
	if d.open(base + rel) != OK:
		return
	d.list_dir_begin(true, false)
	var n := d.get_next()
	while n != "":
		var r: String = (rel + "/" + n) if rel != "" else n
		if d.current_is_dir():
			if not (rel == "" and SKIP_TOP.has(n)):
				_walk(base, r, out, tag)
		elif not (rel == "" and SKIP_FILES.has(n)) and not SKIP_EXT.has(n.get_extension().to_lower()):
			var f := File.new()
			if f.open(base + r, File.READ) == OK:
				out.append([tag, r, f.get_len(), _kind(r)])
				f.close()
		n = d.get_next()
	d.list_dir_end()

# -> {files: [[tag, path, size, kind]], maps: [count, bytes], replays: [...], rest: [...]}
static func survey() -> Dictionary:
	var files := []
	var rs := roots()
	var seen := {}
	for tag in ["p", "u"]:
		if not rs.has(tag):
			continue
		var list := []
		_walk(rs[tag], "", list, tag)
		for e in list:
			if not seen.has(e[1]): # (the same file in both folders: the first one counts, as the game reads it)
				seen[e[1]] = true
				files.append(e)
	var out := {files = files, maps = [0, 0], replays = [0, 0], rest = [0, 0]}
	for e in files:
		out[e[3]][0] += 1
		out[e[3]][1] += int(e[2])
	return out

static func mb(bytes) -> String:
	var v: float = float(bytes) / MB
	return ("%.1f MB" % v) if v < 10.0 else ("%d MB" % int(round(v)))

# --- talking to the server ---------------------------------------------------------

# -> a Dictionary: {ok = true, ...the answer} or {ok = false, error}; with bytes: {ok, bytes}
func _http(method: int, path: String, body = null, want_bytes: bool = false):
	yield(get_tree(), "idle_frame")
	var req := HTTPRequest.new()
	req.timeout = 180
	req.use_threads = OS.can_use_threads()
	add_child(req)
	var err: int
	if body != null:
		err = req.request_raw(base_url() + path, ["Content-Type: application/octet-stream"], true, method, body)
	else:
		err = req.request(base_url() + path, [], true, method)
	if err != OK:
		req.queue_free()
		return {ok = false, error = "Couldn't reach the server."}
	var res: Array = yield(req, "request_completed")
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return {ok = false, error = "Couldn't reach the server. Check the internet connection."}
	if want_bytes and res[1] == 200:
		return {ok = true, bytes = res[3]}
	var parsed = JSON.parse((res[3] as PoolByteArray).get_string_from_utf8())
	var d: Dictionary = parsed.result if parsed.error == OK and parsed.result is Dictionary else {}
	if res[1] != 200 or not bool(d.get("ok", false)):
		return {ok = false, error = String(d.get("error", "The server said %d." % res[1]))}
	return d

# the same, tried again a few times (a part of many shouldn't end the whole thing)
func _http_retry(method: int, path: String, body = null, want_bytes: bool = false):
	var r = {ok = false, error = ""}
	for attempt in range(4):
		r = yield(_http(method, path, body, want_bytes), "completed")
		if r.ok or _stop:
			return r
		yield(get_tree().create_timer(1.5 + attempt * 2.0), "timeout")
	return r

func _end(ok: bool, text: String, code: String = ""):
	busy = false
	Directory.new().remove(TMP)
	emit_signal("finished", ok, text, code)

func stop():
	_stop = true

# --- sending (the sideloaded game) ---------------------------------------------------

func send(include_maps: bool, include_replays: bool):
	if busy:
		return
	busy = true
	_stop = false
	emit_signal("progress", "Looking at what there is...", -1.0)
	yield(get_tree(), "idle_frame")
	var sv := survey()
	var files := []
	var total := 0
	for e in sv.files:
		if (e[3] == "maps" and not include_maps) or (e[3] == "replays" and not include_replays):
			continue
		files.append(e)
		total += int(e[2])
	if files.empty():
		return _end(false, "There is nothing to send.")
	Rhythia.save_settings() # (as they are right now)
	# one file with everything in it
	var rs := roots()
	var out := File.new()
	if out.open(TMP, File.WRITE) != OK:
		return _end(false, "Couldn't make the file to send (is the headset's storage full?).")
	var roots_abs := {}
	for tag in rs:
		roots_abs[tag] = _abs(rs[tag])
	var header := to_json({v = 1, version = String(ProjectSettings.get_setting("application/config/version")), roots = roots_abs, files = files.size()}).to_utf8()
	out.store_buffer(MAGIC.to_ascii())
	out.store_32(header.size())
	out.store_buffer(header)
	var done := 0
	var slice := OS.get_ticks_msec()
	for i in range(files.size()):
		var e: Array = files[i]
		var f := File.new()
		if f.open(String(rs[e[0]]) + String(e[1]), File.READ) != OK:
			continue # (gone since it was listed)
		var path: PoolByteArray = String(e[1]).to_utf8()
		var n: int = f.get_len()
		out.store_8(ord(e[0]))
		out.store_16(path.size())
		out.store_buffer(path)
		out.store_64(n)
		var left := n
		while left > 0:
			var take: int = int(min(left, CHUNK))
			out.store_buffer(f.get_buffer(take))
			left -= take
			done += take
			if OS.get_ticks_msec() - slice > 10:
				emit_signal("progress", "Packing: %d of %d files, %s of %s" % [i + 1, files.size(), mb(done), mb(total)], float(done) / max(1.0, float(total)) * 0.3)
				yield(get_tree(), "idle_frame")
				slice = OS.get_ticks_msec()
				if _stop:
					f.close()
					out.close()
					return _end(false, "Stopped.")
		f.close()
	out.store_8(0)
	out.close()

	var src := File.new()
	if src.open(TMP, File.READ) != OK:
		return _end(false, "Couldn't read the file to send.")
	var size: int = src.get_len()
	emit_signal("progress", "Asking the server (%s to send)..." % mb(size), 0.3)
	var s = yield(_http_retry(HTTPClient.METHOD_POST, "/savia-transfer/start?client_id=%s&size=%d&version=%s" % [String(Rhythia.cid).http_escape(), size, String(ProjectSettings.get_setting("application/config/version")).http_escape()]), "completed")
	if not s.ok:
		src.close()
		return _end(false, String(s.error))
	var part_bytes: int = int(s.part_bytes)
	var parts: int = int(s.parts)
	for n in range(parts):
		if _stop:
			src.close()
			return _end(false, "Stopped.")
		src.seek(n * part_bytes)
		var buf: PoolByteArray = src.get_buffer(int(min(part_bytes, size - n * part_bytes)))
		emit_signal("progress", "Uploading: %s of %s" % [mb(n * part_bytes), mb(size)], 0.3 + 0.7 * float(n) / float(parts))
		var r = yield(_http_retry(HTTPClient.METHOD_POST, "/savia-transfer/part?id=%s&key=%s&n=%d" % [s.id, s.key, n], buf), "completed")
		if not r.ok:
			src.close()
			return _end(false, "The upload stopped: %s" % String(r.error))
	src.close()
	var fin = yield(_http_retry(HTTPClient.METHOD_POST, "/savia-transfer/finish?id=%s&key=%s" % [s.id, s.key]), "completed")
	if not fin.ok:
		return _end(false, String(fin.error))
	Rhythia.trail("store transfer: sent %s in %d files" % [mb(size), files.size()])
	_end(true, "Everything is on the server (%s). It waits there for a day." % mb(size), String(fin.code))

# --- receiving (the store game) ------------------------------------------------------

static func clean_code(code: String) -> String:
	var out := ""
	for c in code.to_upper():
		if (c >= "0" and c <= "9") or (c >= "A" and c <= "Z"):
			out += c
	return out

func receive(code: String):
	if busy:
		return
	busy = true
	_stop = false
	code = clean_code(code)
	if code.length() != 8:
		return _end(false, "The code is 8 letters and digits. It is shown in the sideloaded version, in Settings > Transfer.")
	emit_signal("progress", "Looking for the transfer...", -1.0)
	var info = yield(_http_retry(HTTPClient.METHOD_GET, "/savia-transfer/info?code=%s" % code), "completed")
	if not info.ok:
		return _end(false, String(info.error))
	var size: int = int(info.size)
	var parts: int = int(info.parts)
	var out := File.new()
	if out.open(TMP, File.WRITE) != OK:
		return _end(false, "Couldn't make room for it (is the headset's storage full?).")
	for n in range(parts):
		if _stop:
			out.close()
			return _end(false, "Stopped.")
		emit_signal("progress", "Downloading: %s of %s" % [mb(n * int(info.part_bytes)), mb(size)], 0.75 * float(n) / float(parts))
		var r = yield(_http_retry(HTTPClient.METHOD_GET, "/savia-transfer/part?code=%s&n=%d" % [code, n], null, true), "completed")
		if not r.ok:
			out.close()
			return _end(false, "The download stopped: %s" % String(r.error))
		out.store_buffer(r.bytes)
	out.close()
	var res = yield(_unpack(size), "completed")
	if not res[0]:
		_clear_stage()
		return _end(false, String(res[1]))
	# (whole and in the waiting folder: the server's copy can go)
	yield(_http(HTTPClient.METHOD_POST, "/savia-transfer/done?code=%s" % code), "completed")
	var mark := File.new()
	if mark.open(READY, File.WRITE) == OK:
		mark.store_string("%d files\n" % int(res[2]))
		mark.close()
	Rhythia.trail("store transfer: received %s in %d files, waiting for the next start" % [mb(size), int(res[2])])
	_end(true, "Everything is here (%d files, %s). Close Chromia and open it again to use it." % [int(res[2]), mb(size)])

static func _safe(rel: String) -> bool:
	if rel == "" or rel.begins_with("/") or rel.find("\\") != -1 or rel.find(":") != -1:
		return false
	for p in rel.split("/"):
		if p == "" or p == "." or p == "..":
			return false
	return true

static func _clear_stage():
	var rs := roots()
	for tag in rs:
		_remove_tree(String(rs[tag]) + STAGE)
	Directory.new().remove(READY)

static func _remove_tree(path: String):
	var d := Directory.new()
	if d.open(path) != OK:
		return
	d.list_dir_begin(true, false)
	var n := d.get_next()
	while n != "":
		if d.current_is_dir():
			_remove_tree(path + "/" + n)
		else:
			d.remove(path + "/" + n)
		n = d.get_next()
	d.list_dir_end()
	Directory.new().remove(path)

# the packed file -> the waiting folders. -> [ok, what went wrong, how many files]
func _unpack(size: int):
	yield(get_tree(), "idle_frame")
	_clear_stage()
	var src := File.new()
	if src.open(TMP, File.READ) != OK or src.get_len() != size:
		return [false, "The download isn't whole. Try again.", 0]
	if src.get_buffer(MAGIC.length()).get_string_from_ascii() != MAGIC:
		src.close()
		return [false, "That isn't a Chromia transfer.", 0]
	var hl: int = src.get_32()
	var parsed = JSON.parse(src.get_buffer(hl).get_string_from_utf8()) if hl > 0 and hl < 65536 else null
	if parsed == null or parsed.error != OK or not (parsed.result is Dictionary):
		src.close()
		return [false, "The transfer can't be read.", 0]
	var from: Dictionary = parsed.result.get("roots", {}) if parsed.result.get("roots") is Dictionary else {}
	var rs := roots()
	# where the old app kept things -> where this one does (longest first)
	var swaps := []
	for tag in from:
		var to_tag: String = tag if rs.has(tag) else "u"
		var a := String(from[tag]).rstrip("/")
		var b := _abs(rs[to_tag])
		if a != "" and a != b:
			swaps.append([a, b])
	swaps.sort_custom(load("res://scripts/StoreTransfer.gd"), "_longer_first")
	var d := Directory.new()
	var count := 0
	var slice := OS.get_ticks_msec()
	while src.get_position() < size:
		var tag_n: int = src.get_8()
		if tag_n == 0:
			break
		var tag := char(tag_n)
		var rel: String = src.get_buffer(src.get_16()).get_string_from_utf8()
		var n: int = src.get_64()
		if n < 0 or src.get_position() + n > size or not _safe(rel):
			src.close()
			return [false, "The transfer is damaged. Make a new code and try again.", count]
		if not rs.has(tag):
			tag = "u" # (a folder this device doesn't have: its own)
		var dest: String = String(rs[tag]) + STAGE + "/" + rel
		d.make_dir_recursive(dest.get_base_dir())
		var out := File.new()
		if out.open(dest, File.WRITE) != OK:
			src.close()
			return [false, "Couldn't save %s (is the headset's storage full?)." % rel.get_file(), count]
		if n <= 2 * 1024 * 1024 and TEXT_EXT.has(rel.get_extension().to_lower()) and not swaps.empty():
			var text: String = src.get_buffer(n).get_string_from_utf8()
			for sw in swaps:
				text = text.replace(sw[0], sw[1])
			out.store_string(text)
		else:
			var left := n
			while left > 0:
				var take: int = int(min(left, CHUNK))
				out.store_buffer(src.get_buffer(take))
				left -= take
				if OS.get_ticks_msec() - slice > 10:
					emit_signal("progress", "Unpacking: %d files" % count, 0.75 + 0.25 * float(src.get_position()) / max(1.0, float(size)))
					yield(get_tree(), "idle_frame")
					slice = OS.get_ticks_msec()
		out.close()
		count += 1
	src.close()
	if count == 0:
		return [false, "The transfer is empty.", 0]
	return [true, "", count]

static func _longer_first(a: Array, b: Array) -> bool:
	return String(a[0]).length() > String(b[0]).length()

# --- at the next start: the waiting files move into place --------------------------
# (PackUpdate.gd calls this before any other script runs or reads a file)

static func apply_staged():
	var f := File.new()
	var rs := roots()
	if not f.file_exists(READY):
		# (a download that was cut short: its pieces go)
		for tag in rs:
			if Directory.new().dir_exists(String(rs[tag]) + STAGE):
				_remove_tree(String(rs[tag]) + STAGE)
		return
	var moved := 0
	for tag in rs:
		moved += _move_in(String(rs[tag]) + STAGE, String(rs[tag]), "")
		_remove_tree(String(rs[tag]) + STAGE)
	var d := Directory.new()
	d.remove(READY)
	if f.open(NOTICE, File.WRITE) == OK:
		f.store_string(str(moved))
		f.close()
	print("[store transfer] %d files moved into place" % moved)

static func _move_in(stage: String, root: String, rel: String) -> int:
	var d := Directory.new()
	if d.open(stage + ("/" + rel if rel != "" else "")) != OK:
		return 0
	var n_moved := 0
	d.list_dir_begin(true, false)
	var n := d.get_next()
	while n != "":
		var r: String = (rel + "/" + n) if rel != "" else n
		if d.current_is_dir():
			n_moved += _move_in(stage, root, r)
		else:
			var dest: String = root + r
			var dd := Directory.new()
			dd.make_dir_recursive(dest.get_base_dir())
			if dd.file_exists(dest):
				dd.remove(dest)
			if dd.rename(stage + "/" + r, dest) == OK or dd.copy(stage + "/" + r, dest) == OK:
				n_moved += 1
		n = d.get_next()
	d.list_dir_end()
	return n_moved

# the menu's one-time notice after a transfer moved in -> how many files (0: nothing to say)
static func take_notice() -> int:
	var f := File.new()
	if not f.file_exists(NOTICE) or f.open(NOTICE, File.READ) != OK:
		return 0
	var n := int(f.get_as_text())
	f.close()
	Directory.new().remove(NOTICE)
	return int(max(n, 1))

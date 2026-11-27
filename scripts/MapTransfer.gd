extends Reference

# Settings > Transfer > "Transfer maps only": your maps to another device on
# the same Wi-Fi, with a code, and nothing else (no settings, no restart).
#
# Fast and without lag:
#  - the network and the files are handled on a thread of their own, so the
#    game keeps its frame rate (the settings transfer sends maps a piece per
#    frame on the game's own thread);
#  - the receiving device first says which maps it has (name and size), and
#    only the ones it doesn't have are sent;
#  - files go in big pieces, written straight to disk as they come.
# The maps that came are added to the map list as they arrive (TransferTab
# does that part, a few per frame: the map list belongs to the game's thread).
#
# The wire (after TCP connects):
#   receiver -> "CHMP", u32 pin, u32 n, n x (u16 name length, name, u64 size)
#   sender   -> "NO" (wrong code)  or  "OK", u32 maps, u64 bytes,
#               then per map: u16 name length, name, u64 size, the bytes;
#               u16 0 at the end
#   receiver -> "DN" once everything is written
# Names are "maps/..." or "vmaps/..." (SettingsTransfer.safe_map_name).
#
# Nothing here loads scripts or touches the game's nodes: it runs on a thread.

const ST = preload("res://scripts/SettingsTransfer.gd")
const HELLO := "CHMP"
const WAIT_MS := 15 * 60 * 1000
const IDLE_MS := 30000
const PIECE := 1024 * 1024
const MAX_LIST := 200000

var _thread: Thread = null
var _mutex := Mutex.new()
var _stop := false
var _dirs := {} # "maps" / "vmaps" -> folder
var _server: TCP_Server = null
var _peer: StreamPeerTCP = null
var _pin := 0
var _target := {}

# what the tab shows (read with state())
var _st := {
	"busy": false, "finished": false, "ok": false, "text": "",
	"maps": 0, "maps_done": 0, "bytes": 0, "bytes_done": 0, "skipped": 0,
}
var _added := [] # full paths of maps written here, for the map list (take_added)

func _init(dirs: Dictionary):
	_dirs = dirs

# --- the game's thread -------------------------------------------------------------
func state() -> Dictionary:
	_mutex.lock()
	var s := _st.duplicate()
	_mutex.unlock()
	return s

func take_added() -> Array:
	_mutex.lock()
	var a := _added
	_added = []
	_mutex.unlock()
	return a

func busy() -> bool:
	return bool(state().busy)

# -> the code to type on the other device, or "" (then state().text says why)
func send() -> String:
	stop()
	var ip: String = ST.local_ip()
	if ip == "":
		_put({"text": "Not on Wi-Fi. Connect to the same Wi-Fi as the other device.", "finished": true})
		return ""
	_server = TCP_Server.new()
	var idx := -1
	for i in range(ST.PORTS.size()):
		if _server.listen(ST.PORTS[i]) == OK:
			idx = i
			break
	if idx < 0:
		_server = null
		_put({"text": "Couldn't open a connection (ports %d-%d are in use: close the other transfer)." % [ST.PORTS[0], ST.PORTS[-1]], "finished": true})
		return ""
	randomize()
	_pin = randi() & 0x3ffffff
	_begin("Waiting for the other device...", "_send_job")
	return ST.make_code(ip, idx, _pin)

func receive(code: String) -> bool:
	stop()
	var c: Dictionary = ST.parse_code(code)
	if c.empty():
		_put({"text": "Not a valid code (it looks like 7K2M-9QXA-4T0B).", "finished": true})
		return false
	_target = c
	_begin("Connecting to %s..." % c.ip, "_receive_job")
	return true

func stop():
	if _thread != null:
		_stop = true
		_thread.wait_to_finish()
		_thread = null
	_stop = false
	if _server != null:
		_server.stop()
		_server = null
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null

# (the thread has ended: let it go)
func reap():
	if _thread != null and not busy():
		_thread.wait_to_finish()
		_thread = null

func _begin(text: String, job: String):
	_mutex.lock()
	_st = {"busy": true, "finished": false, "ok": false, "text": text,
		"maps": 0, "maps_done": 0, "bytes": 0, "bytes_done": 0, "skipped": 0}
	_added = []
	_mutex.unlock()
	_stop = false
	_thread = Thread.new()
	if _thread.start(self, job, null) != OK:
		_thread = null
		_put({"busy": false, "finished": true, "text": "Couldn't start the transfer."})

func _put(d: Dictionary):
	_mutex.lock()
	for k in d:
		_st[k] = d[k]
	_mutex.unlock()

func _end(ok: bool, text: String):
	if _peer != null:
		_peer.disconnect_from_host()
		_peer = null
	if _server != null:
		_server.stop()
		_server = null
	_put({"busy": false, "finished": true, "ok": ok, "text": text})

# --- the maps here (on the thread) ---------------------------------------------------
# [[name, full path, size], ...]
func _list() -> Array:
	var out := []
	for kind in ST.MAP_DIRS:
		var base: String = String(_dirs.get(kind, ""))
		if base == "":
			continue
		var files := []
		_walk(base, "", files)
		for rel in files:
			if ST.MAP_SKIP_EXT.has(String(rel).get_extension().to_lower()):
				continue
			var path: String = base.plus_file(rel)
			var f := File.new()
			if f.open(path, File.READ) == OK:
				out.append([kind + "/" + rel, path, f.get_len()])
				f.close()
			if _stop or out.size() >= MAX_LIST:
				return out
	return out

func _walk(base: String, rel: String, out: Array):
	var d := Directory.new()
	if d.open(base.plus_file(rel) if rel != "" else base) != OK:
		return
	d.list_dir_begin(true, true)
	var n := d.get_next()
	while n != "":
		var r: String = rel.plus_file(n) if rel != "" else n
		if d.current_is_dir():
			_walk(base, r, out)
		else:
			out.append(r)
		n = d.get_next()
	d.list_dir_end()

func _target_path(name: String) -> String:
	var i := name.find("/")
	return String(_dirs.get(name.substr(0, i), "")).plus_file(name.substr(i + 1))

# --- reading and writing the connection (on the thread) ------------------------------
# exactly n bytes, or null (stopped, lost, or nothing for too long)
func _read(n: int):
	var out := PoolByteArray()
	var quiet_since := OS.get_ticks_msec()
	while out.size() < n:
		if _stop or _peer == null:
			return null
		# (what came before the other side closed is still read: its "NO")
		var avail: int = _peer.get_available_bytes()
		if avail <= 0 and _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return null
		if avail <= 0:
			if OS.get_ticks_msec() - quiet_since > IDLE_MS:
				return null
			OS.delay_usec(1000)
			continue
		var r: Array = _peer.get_partial_data(min(avail, n - out.size()))
		if r[0] != OK:
			return null
		out.append_array(r[1])
		quiet_since = OS.get_ticks_msec()
	return out

func _write(b: PoolByteArray) -> bool:
	var at := 0
	var quiet_since := OS.get_ticks_msec()
	while at < b.size():
		if _stop or _peer == null or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			return false
		var r: Array = _peer.put_partial_data(b.subarray(at, b.size() - 1) if at > 0 else b)
		if r[0] != OK:
			return false
		var n: int = int(r[1])
		if n <= 0:
			if OS.get_ticks_msec() - quiet_since > IDLE_MS:
				return false
			OS.delay_usec(1000)
			continue
		at += n
		quiet_since = OS.get_ticks_msec()
	return true

static func _u16(b: PoolByteArray) -> int:
	return (int(b[0]) << 8) | int(b[1])

static func _u32(b: PoolByteArray, at: int = 0) -> int:
	return (int(b[at]) << 24) | (int(b[at + 1]) << 16) | (int(b[at + 2]) << 8) | int(b[at + 3])

static func _u64(b: PoolByteArray, at: int = 0) -> int:
	var v := 0
	for i in range(8):
		v = (v << 8) | int(b[at + i])
	return v

static func _head(name: String, size: int) -> PoolByteArray:
	var nb: PoolByteArray = name.to_utf8()
	var sp := StreamPeerBuffer.new()
	sp.big_endian = true
	sp.put_u16(nb.size())
	sp.put_data(nb)
	sp.put_u64(size)
	return sp.data_array

# --- sending (on the thread) ---------------------------------------------------------
func _send_job(_u):
	var until := OS.get_ticks_msec() + WAIT_MS
	var bad := 0
	while not _stop:
		if OS.get_ticks_msec() > until:
			_end(false, "The code expired. Make a new one.")
			return
		if not _server.is_connection_available():
			OS.delay_msec(50)
			continue
		_peer = _server.take_connection()
		_peer.set_no_delay(true)
		var their = _hello()
		if their == null:
			_peer.disconnect_from_host()
			_peer = null
			bad += 1
			if bad >= 10:
				_end(false, "Too many wrong codes. Make a new one.")
				return
			continue
		_server.stop() # (one device per code)
		_send_maps(their)
		return
	_end(false, "Stopped.")

# the receiver's hello -> {name: size} of the maps it has, or null (wrong code)
func _hello():
	var h = _read(12)
	if h == null or h.subarray(0, 3).get_string_from_ascii() != HELLO or _u32(h, 4) != _pin:
		if _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_peer.put_data("NO".to_ascii())
		return null
	var n := _u32(h, 8)
	if n < 0 or n > MAX_LIST:
		return null
	var have := {}
	for i in range(n):
		var l = _read(2)
		if l == null:
			return null
		var nm = _read(_u16(l) + 8)
		if nm == null:
			return null
		var name: String = nm.subarray(0, _u16(l) - 1).get_string_from_utf8() if _u16(l) > 0 else ""
		have[name] = _u64(nm, _u16(l))
	return have

func _send_maps(have: Dictionary):
	_put({"text": "Connected. Looking at which maps the other device is missing..."})
	var mine := _list()
	var todo := []
	var total := 0
	for m in mine:
		if have.has(m[0]) and int(have[m[0]]) == int(m[2]):
			continue
		todo.append(m)
		total += int(m[2])
	_put({"maps": todo.size(), "bytes": total, "skipped": mine.size() - todo.size()})
	var sp := StreamPeerBuffer.new()
	sp.big_endian = true
	sp.put_data("OK".to_ascii())
	sp.put_u32(todo.size())
	sp.put_u64(total)
	if not _write(sp.data_array):
		_end(false, "The other device stopped.")
		return
	var done_bytes := 0
	for i in range(todo.size()):
		var m: Array = todo[i]
		var f := File.new()
		if f.open(m[1], File.READ) != OK:
			# (gone since it was counted: sent as empty, the other side skips it)
			if not _write(_head(m[0], 0)):
				_end(false, "The other device stopped.")
				return
			continue
		var size: int = f.get_len()
		if not _write(_head(m[0], size)):
			f.close()
			_end(false, "The other device stopped.")
			return
		var left := size
		while left > 0:
			var piece: PoolByteArray = f.get_buffer(min(PIECE, left))
			if piece.empty() or not _write(piece):
				f.close()
				_end(false, "Stopped." if _stop else "The other device stopped.")
				return
			left -= piece.size()
			done_bytes += piece.size()
			_put({"bytes_done": done_bytes})
		f.close()
		_put({"maps_done": i + 1})
	var e := StreamPeerBuffer.new()
	e.big_endian = true
	e.put_u16(0)
	if not _write(e.data_array):
		_end(false, "The other device stopped.")
		return
	_read(2) # ("DN": everything is written there)
	_end(true, "Sent %d map%s (%s)%s." % [todo.size(), "" if todo.size() == 1 else "s", ST.human_size(total),
		(", %d the other device had already" % (mine.size() - todo.size())) if mine.size() > todo.size() else ""])

# --- receiving (on the thread) -------------------------------------------------------
func _receive_job(_u):
	_peer = StreamPeerTCP.new()
	if _peer.connect_to_host(_target.ip, _target.port) != OK:
		_end(false, "Couldn't connect. Are both on the same Wi-Fi?")
		return
	_peer.set_no_delay(true)
	var since := OS.get_ticks_msec()
	while _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
		if _stop:
			_end(false, "Stopped.")
			return
		if OS.get_ticks_msec() - since > 10000:
			_end(false, "No answer. Check the code, the Wi-Fi, and that the other device is showing it.")
			return
		OS.delay_msec(20)
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		_end(false, "Couldn't connect. Are both on the same Wi-Fi?")
		return
	_put({"text": "Connected. Telling the other device which maps are here..."})
	var mine := _list()
	var sp := StreamPeerBuffer.new()
	sp.big_endian = true
	sp.put_data(HELLO.to_ascii())
	sp.put_u32(_target.pin)
	sp.put_u32(mine.size())
	for m in mine:
		var nb: PoolByteArray = String(m[0]).to_utf8()
		sp.put_u16(nb.size())
		sp.put_data(nb)
		sp.put_u64(int(m[2]))
	if not _write(sp.data_array):
		_end(false, "The connection was lost.")
		return
	var ok = _read(2)
	if ok == null:
		_end(false, "Stopped." if _stop else "The connection was lost (a used or expired code?).")
		return
	if ok.get_string_from_ascii() == "NO":
		_end(false, "Wrong code.")
		return
	var head = _read(12)
	if ok.get_string_from_ascii() != "OK" or head == null:
		_end(false, "The other device answered something else. Are both on the same version?")
		return
	var count := _u32(head)
	var total := _u64(head, 4)
	_put({"maps": count, "bytes": total, "text": "Receiving %d maps..." % count})
	var got_bytes := 0
	var n := 0
	var errors := 0
	while true:
		var l = _read(2)
		if l == null:
			_end(false, _partial(n, count, errors))
			return
		var nl := _u16(l)
		if nl == 0:
			break
		var nm = _read(nl + 8)
		if nm == null:
			_end(false, _partial(n, count, errors))
			return
		var name: String = nm.subarray(0, nl - 1).get_string_from_utf8()
		var size := _u64(nm, nl)
		if not ST.safe_map_name(name) or size < 0 or size > 2147483647:
			_end(false, "The other device sent something that isn't a map. Stopped.")
			return
		var path := _target_path(name)
		var f: File = null
		if size > 0:
			Directory.new().make_dir_recursive(path.get_base_dir())
			f = File.new()
			if f.open(path + ".part", File.WRITE) != OK:
				f = null
		var left := size
		var quiet_since := OS.get_ticks_msec()
		while left > 0:
			if _stop or _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				if f != null:
					f.close()
					Directory.new().remove(path + ".part")
				_end(false, "Stopped." if _stop else _partial(n, count, errors))
				return
			var avail: int = _peer.get_available_bytes()
			if avail <= 0:
				if OS.get_ticks_msec() - quiet_since > IDLE_MS:
					if f != null:
						f.close()
						Directory.new().remove(path + ".part")
					_end(false, _partial(n, count, errors))
					return
				OS.delay_usec(1000)
				continue
			var r: Array = _peer.get_partial_data(min(avail, min(left, 4 * PIECE)))
			if r[0] != OK:
				continue
			var b: PoolByteArray = r[1]
			if f != null:
				f.store_buffer(b)
			left -= b.size()
			got_bytes += b.size()
			quiet_since = OS.get_ticks_msec()
			_put({"bytes_done": got_bytes})
		n += 1
		if f != null:
			f.close()
			var d := Directory.new()
			if d.file_exists(path):
				d.remove(path)
			if d.rename(path + ".part", path) == OK:
				_mutex.lock()
				_added.append(path)
				_mutex.unlock()
			else:
				errors += 1
		elif size > 0:
			errors += 1
		_put({"maps_done": n})
	_write("DN".to_ascii())
	OS.delay_msec(200)
	_end(errors == 0, "Got %d map%s (%s)%s." % [n - errors, "" if n - errors == 1 else "s", ST.human_size(got_bytes),
		(", %d couldn't be saved" % errors) if errors > 0 else ""])

static func _partial(n: int, count: int, errors: int) -> String:
	return "The connection was lost after %d of %d maps (the ones that came are kept)." % [max(0, n - errors), count]

extends Reference

const OP_HANDSHAKE := 0
const OP_FRAME := 1

var _pipe: File = null
var _connected := false
var _thread: Thread = null

var _mutex := Mutex.new()
var _queued = null
var _busy := false

# Sends on a worker thread. If a send is in progress, the newest request is
# kept and sent right after it (older queued ones are dropped).
func request_activity(details: String, state: String, assets: Dictionary, buttons: Array) -> void:
	var args = {"details": details, "state": state, "assets": assets, "buttons": buttons}
	_mutex.lock()
	if _busy:
		_queued = args
		_mutex.unlock()
		return
	_busy = true
	_mutex.unlock()
	if _thread != null and _thread.is_active():
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread.start(self, "_worker", args)

func _worker(args) -> void:
	while args != null:
		_do_set_activity(args.details, args.state, args.assets, args.buttons)
		_mutex.lock()
		args = _queued
		_queued = null
		if args == null:
			_busy = false
		_mutex.unlock()

func shutdown() -> void:
	if _thread != null and _thread.is_active():
		_thread.wait_to_finish()
		_thread = null
	_disconnect()

func _do_set_activity(details: String, state: String, assets: Dictionary, buttons: Array) -> void:
	if not _connected and not _try_connect():
		return
	var activity = {
		"details": details,
		"state": state,
		"assets": assets
	}
	if buttons.size() > 0:
		activity["buttons"] = buttons
	var nonce := "%d_%d" % [OS.get_unix_time(), randi()]
	var ok := _write_frame(OP_FRAME, {
		"cmd": "SET_ACTIVITY",
		"args": {"pid": OS.get_process_id(), "activity": activity},
		"nonce": nonce
	})
	if not ok or _read_frame().empty():
		_disconnect()

func _try_connect() -> bool:
	for i in range(10):
		var f := File.new()
		var path := "//./pipe/discord-ipc-%d" % i
		if f.open(path, File.READ_WRITE) == OK:
			_pipe = f
			if _handshake():
				_connected = true
				return true
			f.close()
	_pipe = null
	_connected = false
	return false

func _handshake() -> bool:
	if not _write_frame(OP_HANDSHAKE, {"v": 1, "client_id": str(Globals.DISCORD_APP_ID)}):
		return false
	return not _read_frame().empty()

func _disconnect() -> void:
	if _pipe:
		_pipe.close()
	_pipe = null
	_connected = false

func _write_frame(opcode: int, payload: Dictionary) -> bool:
	if _pipe == null: return false
	var body := to_json(payload).to_utf8()
	_pipe.store_32(opcode)
	_pipe.store_32(body.size())
	_pipe.store_buffer(body)
	return _pipe.get_error() == OK

func _read_frame() -> Dictionary:
	if _pipe == null: return {}
	var opcode = _pipe.get_32()
	if _pipe.get_error() != OK: return {}
	var length = _pipe.get_32()
	if _pipe.get_error() != OK: return {}
	var data = null
	if length > 0:
		var buf = _pipe.get_buffer(length)
		data = parse_json(buf.get_string_from_utf8())
	return {"opcode": opcode, "data": data}

extends Reference

const DISCORD_CLIENT_ID := "1507913571055702117"
const OP_HANDSHAKE := 0
const OP_FRAME := 1

var _pipe: File = null
var _connected := false
var _thread: Thread = null

func request_activity(details: String, state: String, large_image: String, buttons: Array) -> void:
	if _thread != null:
		if _thread.is_active():
			return
		_thread.wait_to_finish()
		_thread = null
	_thread = Thread.new()
	_thread.start(self, "_worker", {"details": details, "state": state, "large_image": large_image, "buttons": buttons})

func _worker(args: Dictionary) -> void:
	_do_set_activity(args.details, args.state, args.large_image, args.buttons)

func _do_set_activity(details: String, state: String, large_image: String, buttons: Array) -> void:
	if not _connected and not _try_connect():
		return
	var activity = {
		"details": details,
		"state": state,
		"assets": {"large_image": large_image}
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
	if not _write_frame(OP_HANDSHAKE, {"v": 1, "client_id": DISCORD_CLIENT_ID}):
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

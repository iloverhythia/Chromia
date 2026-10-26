extends VBoxContainer

# Settings > Transfer: move your settings and custom content (not maps) to
# another device with a transfer code, or with a file. SettingsTransfer.gd
# packs and unpacks; this tab shows it and does the network part:
#  - Send: makes a code, then waits (up to 15 minutes, while the game is open)
#    for the other device to connect with it and sends the bundle.
#  - Receive: you type the other device's code; it connects, downloads, shows
#    what came, and Apply writes it and restarts the menu with it.
# Both devices have to be on the same network (Wi-Fi). The browser version
# can't make direct connections: files only.

const ST = preload("res://scripts/SettingsTransfer.gd")
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)
const GOOD := Color(0.6, 1, 0.7)
const BAD := Color(1, 0.55, 0.55)
const HELLO := "CHXF"
const WAIT_MS := 15 * 60 * 1000
const CHUNK := 256 * 1024

var f_body: DynamicFont
var f_bold: DynamicFont
var f_title: DynamicFont
var f_code: DynamicFont
var box: VBoxContainer

var _code_l: Label
var _send_status: Label
var _send_btn: Button
var _stop_btn: Button
var _code_in: LineEdit
var _recv_status: Label
var _recv_btn: Button
var _apply_box: HBoxContainer
var _file_status: Label

# sending
var _server: TCP_Server = null
var _pin = 0
var _payload = PoolByteArray()
var _server_until = 0
var _peer: StreamPeerTCP = null
var _peer_buf = PoolByteArray()
var _peer_since = 0
var _sent = 0
var _sending = false
var _bad_tries = 0

# receiving
var _client: StreamPeerTCP = null
var _client_since = 0
var _client_hello_sent = false
var _got = PoolByteArray()
var _want = -1
var _received = null # bundle data waiting for Apply

static func web() -> bool:
	return OS.get_name() == "HTML5"

static func add_tab(tab_container) -> void:
	if tab_container == null or not is_instance_valid(tab_container) or tab_container.has_node("Transfer"):
		return
	var t = load("res://scripts/ui/settings/TransferTab.gd").new()
	t.name = "Transfer"
	tab_container.add_child(t)
	var after = tab_container.get_node_or_null("Replays & Misc")
	if after:
		tab_container.move_child(t, after.get_index() + 1)

func _font(path: String, size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	return f

func _ready():
	f_body = _font("res://assets/font/Lato/Lato-Regular.ttf", 17)
	f_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 18)
	f_title = _font("res://assets/font/Lato/Lato-Black.ttf", 26)
	f_code = _font("res://assets/font/Lato/Lato-Black.ttf", 44)
	var m = MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_constant_override("margin_" + side, 18)
	add_child(m)
	box = VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_constant_override("separation", 8)
	m.add_child(box)

	_label("Transfer settings", f_title, ACCENT)
	_label("Move your settings and custom content to another device: colorsets, note meshes, cursors and trails, hit / miss / menu sounds, borders, backgrounds, profiles, keybinds and VR settings. Maps, replays, scores and stats stay where they are. A few settings that belong to each device stay as they are on the receiving one (window, frame rate, touch layout, sensitivity, audio offset).", f_body, DIM, true)

	if not web():
		box.add_child(HSeparator.new())
		_label("Send from this device", f_title, ACCENT)
		_label("Make a code, then enter it on the other device. Both need to be on the same Wi-Fi, with Chromia open. The code works for 15 minutes, once.", f_body, DIM, true)
		var h = HBoxContainer.new()
		h.add_constant_override("separation", 10)
		box.add_child(h)
		_send_btn = _button(h, "Generate code", "_start_send")
		_stop_btn = _button(h, "Stop", "_stop_send")
		_stop_btn.visible = false
		_code_l = _label("", f_code, TEXT)
		_code_l.visible = false
		_send_status = _label("", f_body, TEXT, true)

		box.add_child(HSeparator.new())
		_label("Receive on this device", f_title, ACCENT)
		_label("Enter the code shown on the other device (letters and numbers, the dashes don't matter).", f_body, DIM, true)
		var h2 = HBoxContainer.new()
		h2.add_constant_override("separation", 10)
		box.add_child(h2)
		_code_in = LineEdit.new()
		_code_in.theme = load("res://uitheme.tres")
		_code_in.add_font_override("font", f_bold)
		_code_in.placeholder_text = "XXXX-XXXX-XXXX"
		_code_in.rect_min_size = Vector2(260, 40)
		_code_in.max_length = 20
		_code_in.connect("text_entered", self, "_on_code_entered")
		h2.add_child(_code_in)
		_recv_btn = _button(h2, "Enter code", "_start_receive")
		_recv_status = _label("", f_body, TEXT, true)
		_apply_box = HBoxContainer.new()
		_apply_box.add_constant_override("separation", 10)
		_apply_box.visible = false
		box.add_child(_apply_box)
		_button(_apply_box, "Apply", "_apply")
		_button(_apply_box, "Cancel", "_cancel_apply")

	box.add_child(HSeparator.new())
	_label("Or use a file", f_title, ACCENT)
	_label("Save everything to one file and open it on the other device (copy it over any way you like)." + (" The browser version can only use files." if web() else ""), f_body, DIM, true)
	var h3 = HBoxContainer.new()
	h3.add_constant_override("separation", 10)
	box.add_child(h3)
	_button(h3, "Save to file", "_save_file")
	_button(h3, "Load from file", "_load_file")
	_file_status = _label("", f_body, TEXT, true)
	set_process(false)

func _label(text: String, f: Font, col: Color, wrap: bool = false, parent: Node = null) -> Label:
	var l = Label.new()
	l.autowrap = wrap
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	(parent if parent != null else box).add_child(l)
	return l

func _button(parent: Node, text: String, method: String) -> Button:
	var b = Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", f_bold)
	b.rect_min_size = Vector2(180, 40)
	b.size_flags_horizontal = 0
	b.connect("pressed", self, method)
	parent.add_child(b)
	return b

func _say(l: Label, text: String, col: Color = TEXT):
	if l == null:
		return
	l.text = text
	l.add_color_override("font_color", col)

# --- Sending -----------------------------------------------------------------
func _start_send():
	_stop_send()
	var ip: String = ST.local_ip()
	if ip == "":
		_say(_send_status, "Not connected to a local network. Connect to Wi-Fi and try again, or use a file below.", BAD)
		return
	_say(_send_status, "Packing your settings and content...")
	_send_btn.disabled = true
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var b: Dictionary = ST.build_bundle()
	_payload = b.bytes
	_server = TCP_Server.new()
	var idx = -1
	for i in range(ST.PORTS.size()):
		if _server.listen(ST.PORTS[i]) == OK:
			idx = i
			break
	_send_btn.disabled = false
	if idx < 0:
		_server = null
		_say(_send_status, "Couldn't open a connection on this device (ports %d-%d are in use)." % [ST.PORTS[0], ST.PORTS[-1]], BAD)
		return
	randomize()
	_pin = randi() & 0x3ffffff
	_bad_tries = 0
	_server_until = OS.get_ticks_msec() + WAIT_MS
	_code_l.text = ST.make_code(ip, idx, _pin)
	_code_l.visible = true
	_stop_btn.visible = true
	var extra = ""
	if not b.skipped.empty():
		extra = "\n%d file(s) too big to send were left out: %s" % [b.skipped.size(), PoolStringArray(b.skipped).join(", ")]
	_say(_send_status, "Ready: %d files (%s). Enter this code on the other device...%s" % [b.files, ST.human_size(b.size), extra])
	Rhythia.trail("transfer: sending from %s port %d" % [ip, ST.PORTS[idx]])
	set_process(true)

func _stop_send(text: String = ""):
	if _server != null:
		_server.stop()
	_server = null
	if _peer != null:
		_peer.disconnect_from_host()
	_peer = null
	_sending = false
	_payload = PoolByteArray()
	if _code_l:
		_code_l.visible = false
	if _stop_btn:
		_stop_btn.visible = false
	if text != "":
		_say(_send_status, text)
	elif _send_status:
		_say(_send_status, "")

func _process_send():
	if _server == null:
		return
	if OS.get_ticks_msec() > _server_until and not _sending:
		_stop_send("The code ran out. Make a new one.")
		return
	if _peer == null and _server.is_connection_available():
		_peer = _server.take_connection()
		_peer.set_no_delay(true)
		_peer_buf = PoolByteArray()
		_peer_since = OS.get_ticks_msec()
		_sent = 0
		_sending = false
	if _peer == null:
		return
	if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		if _sending:
			_say(_send_status, "The other device stopped receiving. Its code still works: try again there.", BAD)
		_peer = null
		_sending = false
		return
	if not _sending:
		var n = _peer.get_available_bytes()
		if n > 0:
			var r = _peer.get_partial_data(n)
			if r[0] == OK:
				_peer_buf.append_array(r[1])
		if _peer_buf.size() >= 8:
			var sp = StreamPeerBuffer.new()
			sp.data_array = _peer_buf
			var hello = sp.get_data(4)[1].get_string_from_ascii()
			var pin = sp.get_u32()
			var ok: bool = hello == HELLO and pin == _pin
			var reply = StreamPeerBuffer.new()
			if ok:
				reply.put_data("OK".to_ascii())
				reply.put_u64(_payload.size())
				_peer.put_data(reply.data_array)
				_sending = true
				_sent = 0
				Rhythia.trail("transfer: sending %d bytes" % _payload.size())
			else:
				reply.put_data("NO".to_ascii())
				_peer.put_data(reply.data_array)
				_peer.disconnect_from_host()
				_peer = null
				_bad_tries += 1
				if _bad_tries >= 10:
					_stop_send("Too many wrong codes were tried: stopped. Make a new code.")
			return
		if OS.get_ticks_msec() - _peer_since > 10000:
			_peer.disconnect_from_host()
			_peer = null
		return
	# send a piece each frame
	var budget = 8
	while budget > 0 and _sent < _payload.size():
		budget -= 1
		var end: int = min(_sent + CHUNK, _payload.size())
		var r = _peer.put_partial_data(_payload.subarray(_sent, end - 1))
		if r[0] != OK:
			break
		var n: int = int(r[1])
		_sent += n
		if n < end - (_sent - n):
			break # the connection is full: more next frame
	_say(_send_status, "Sending... %d %%" % int(100.0 * _sent / max(1, _payload.size())))
	if _sent >= _payload.size():
		Rhythia.trail("transfer: sent")
		var p = _peer
		_peer = null
		_stop_send("Sent! Apply it on the other device.")
		_send_status.add_color_override("font_color", GOOD)
		# let the last bytes go out before closing
		get_tree().create_timer(5.0).connect("timeout", self, "_close_later", [p])

func _close_later(p):
	if p != null:
		p.disconnect_from_host()

# --- Receiving ---------------------------------------------------------------
func _on_code_entered(_t):
	_start_receive()

func _start_receive():
	_stop_receive()
	_apply_box.visible = false
	_received = null
	var c: Dictionary = ST.parse_code(_code_in.text)
	if c.empty():
		_say(_recv_status, "That isn't a transfer code: it has 12 letters and numbers, like 7K2M-9QXA-4T0B.", BAD)
		return
	_client = StreamPeerTCP.new()
	if _client.connect_to_host(c.ip, c.port) != OK:
		_client = null
		_say(_recv_status, "Couldn't connect. Check that both devices are on the same Wi-Fi.", BAD)
		return
	_client.set_no_delay(true)
	_client_since = OS.get_ticks_msec()
	_client_hello_sent = false
	_got = PoolByteArray()
	_want = -1
	set_meta("pin", c.pin)
	_say(_recv_status, "Connecting to %s..." % c.ip)
	Rhythia.trail("transfer: receiving from %s:%d" % [c.ip, c.port])
	set_process(true)

func _stop_receive():
	if _client != null:
		_client.disconnect_from_host()
	_client = null

func _process_receive():
	if _client == null:
		return
	var st = _client.get_status()
	if st == StreamPeerTCP.STATUS_CONNECTING:
		if OS.get_ticks_msec() - _client_since > 10000:
			_stop_receive()
			_say(_recv_status, "No answer. Check the code, that the other device still shows it, and that both are on the same Wi-Fi.", BAD)
		return
	if st != StreamPeerTCP.STATUS_CONNECTED:
		_stop_receive()
		_say(_recv_status, "The connection was lost%s." % (" (the code may be wrong or used up)" if _want < 0 else ""), BAD)
		return
	if not _client_hello_sent:
		var hello = StreamPeerBuffer.new()
		hello.put_data(HELLO.to_ascii())
		hello.put_u32(int(get_meta("pin")))
		_client.put_data(hello.data_array)
		_client_hello_sent = true
		_say(_recv_status, "Connected, waiting...")
	var n = _client.get_available_bytes()
	if n > 0:
		var r = _client.get_partial_data(n)
		if r[0] == OK:
			_got.append_array(r[1])
	if _want < 0:
		if _got.size() >= 2 and _got.subarray(0, 1).get_string_from_ascii() == "NO":
			_stop_receive()
			_say(_recv_status, "Wrong code. Check it on the other device.", BAD)
			return
		if _got.size() >= 10:
			var sp = StreamPeerBuffer.new()
			sp.data_array = _got.subarray(2, 9)
			_want = sp.get_u64()
			_got = _got.subarray(10, _got.size() - 1) if _got.size() > 10 else PoolByteArray()
		elif OS.get_ticks_msec() - _client_since > 30000:
			_stop_receive()
			_say(_recv_status, "No answer. Try again.", BAD)
		return
	_say(_recv_status, "Receiving... %d %%  (%s)" % [int(100.0 * _got.size() / max(1, _want)), ST.human_size(_want)])
	if _got.size() >= _want:
		_stop_receive()
		_got_bundle(_got.subarray(0, _want - 1) if _want > 0 else PoolByteArray(), _recv_status)
		_got = PoolByteArray()

func _got_bundle(bytes: PoolByteArray, status: Label):
	var r: Dictionary = ST.read_bundle(bytes)
	if r.has("error"):
		_say(status, r.error, BAD)
		return
	_received = r.data
	var from: String = str(_received.get("from", "another device"))
	_say(status, "Got %d files (%s) and the settings from %s. Apply them? Your settings now are kept as the profile 'before transfer' (Settings > Select Profile) if you want them back." % [_received.files.size(), ST.human_size(int(_received.size)), from], GOOD)
	if _apply_box == null:
		# browser: no apply row in the code part, so ask here
		_apply_box = HBoxContainer.new()
		_apply_box.add_constant_override("separation", 10)
		box.add_child(_apply_box)
		_button(_apply_box, "Apply", "_apply")
		_button(_apply_box, "Cancel", "_cancel_apply")
	box.move_child(_apply_box, status.get_index() + 1)
	_apply_box.visible = true

func _cancel_apply():
	_received = null
	_apply_box.visible = false
	_say(_recv_status, "")
	_say(_file_status, "")

func _apply():
	if _received == null:
		return
	var r: Dictionary = ST.apply_bundle(_received)
	_received = null
	_apply_box.visible = false
	Rhythia.trail("transfer: applied %d files (%d failed)" % [r.written, r.failed])
	# like picking a profile: the menu starts again with everything loaded
	var path: String = Rhythia.get_startup_settings_path()
	var menu = Rhythia.menu_node()
	if menu != null and "black_fade_target" in menu:
		menu.black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/init.tscn")
	Rhythia.load_saved_settings(path)
	Rhythia.save_settings()

# --- Files -------------------------------------------------------------------
func _save_file():
	Globals.file_sel.save_file(self, "_save_picked", PoolStringArray(["*.chromiasettings ; Chromia settings"]), "user://chromia.chromiasettings")

func _save_picked(path: String):
	if path == "":
		return
	if path.get_extension() != "chromiasettings":
		path += ".chromiasettings"
	var b: Dictionary = ST.build_bundle()
	var f = File.new()
	if f.open(path, File.WRITE) != OK:
		_say(_file_status, "Couldn't write %s." % path, BAD)
		return
	f.store_buffer(b.bytes)
	f.close()
	_say(_file_status, "Saved %d files (%s) to %s" % [b.files, ST.human_size(b.size), path], GOOD)

func _load_file():
	Globals.file_sel.open_file(self, "_load_picked", PoolStringArray(["*.chromiasettings ; Chromia settings"]), false)

func _load_picked(files: PoolStringArray):
	if files.empty():
		return
	var f = File.new()
	if f.open(files[0], File.READ) != OK:
		_say(_file_status, "Couldn't open %s." % files[0], BAD)
		return
	var bytes = f.get_buffer(f.get_len())
	f.close()
	_got_bundle(bytes, _file_status)

func _process(_d):
	_process_send()
	_process_receive()
	if _server == null and _client == null:
		set_process(false)

func _exit_tree():
	_stop_send()
	_stop_receive()

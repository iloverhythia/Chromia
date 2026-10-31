extends CanvasLayer

# Report the player you're spectating (HUD.gd's Report button): skin, chat or
# something else, with a short note. Sent to the server with a screenshot of
# your screen (taken when you pressed Report, before this window opened), the
# settings their game sent for spectators, and the chat you can see. Staff
# see it in the admin panel's Reports page (savia_web src/reports.js).

const REPORT_URL := "https://savia.nysr.host/savia-report"
const CATEGORIES := [["skin", "Skin"], ["chat", "Chat"], ["other", "Other"]]

var target_number: int = 0
var target_name: String = ""
var settings: Dictionary = {}
var song: String = ""
var shot_png: PoolByteArray = PoolByteArray()

var _cat: String = "skin"
var _cat_buttons := {}
var _note: LineEdit
var _status: Label
var _send: Button
var _http: HTTPRequest = null

static func open_for(parent: Node, number: int, who: String, their_settings: Dictionary, song_name: String):
	# the screenshot first (this window isn't drawn yet)
	var img: Image = parent.get_viewport().get_texture().get_data()
	img.flip_y()
	if img.get_width() > 1280:
		img.resize(1280, int(round(img.get_height() * 1280.0 / img.get_width())), Image.INTERPOLATE_BILINEAR)
	var w = load("res://scripts/game/SpectateReport.gd").new()
	w.target_number = number
	w.target_name = who
	w.settings = their_settings
	w.song = song_name
	w.shot_png = img.save_png_to_buffer()
	parent.add_child(w)
	return w

func _font(size: int) -> DynamicFont:
	var f = DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = size
	return f

func _ready():
	layer = 60
	pause_mode = PAUSE_MODE_PROCESS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	# the game's own look (uitheme.tres, like its other windows)
	var root := Control.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.theme = load("res://uitheme.tres")
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.4)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	root.add_child(dim)
	var center := CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.rect_min_size = Vector2(360, 0)
	center.add_child(panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_constant_override("margin_" + side, 12)
	panel.add_child(m)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 8)
	m.add_child(v)

	var title := Label.new()
	title.add_font_override("font", _font(18))
	title.text = "Report %s" % target_name
	v.add_child(title)

	var row := HBoxContainer.new()
	v.add_child(row)
	for c in CATEGORIES:
		var b := Button.new()
		b.text = c[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.connect("pressed", self, "_pick", [c[0]])
		row.add_child(b)
		_cat_buttons[c[0]] = b
	_pick(_cat)

	_note = LineEdit.new()
	_note.placeholder_text = "Details"
	_note.max_length = 500
	v.add_child(_note)

	_status = Label.new()
	_status.autowrap = true
	_status.visible = false
	v.add_child(_status)

	var btns := HBoxContainer.new()
	btns.alignment = BoxContainer.ALIGN_END
	v.add_child(btns)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.connect("pressed", self, "_close")
	btns.add_child(cancel)
	_send = Button.new()
	_send.text = "Send"
	_send.focus_mode = Control.FOCUS_NONE
	_send.connect("pressed", self, "_submit")
	btns.add_child(_send)

func _pick(cat: String):
	_cat = cat
	for k in _cat_buttons:
		_cat_buttons[k].pressed = (k == cat)

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
		get_tree().set_input_as_handled()
		_close()

func _close():
	queue_free()

func _say(text: String, bad: bool):
	_status.visible = true
	_status.text = text
	_status.add_color_override("font_color", Color("#ff8282") if bad else Color("#9be89b"))

func _chat_lines() -> Array:
	var out := []
	var lm = get_node_or_null("/root/LobbyManager")
	if lm == null:
		return out
	for m in lm.lobby_chat_history + lm.global_chat_history:
		if m is Dictionary:
			out.append({"name": Globals.s(m.get("name", "")), "text": Globals.s(m.get("text", ""))})
	return out.slice(max(0, out.size() - 40), out.size() - 1) if out.size() > 0 else out

func _submit():
	if _http != null:
		return
	_send.disabled = true
	_say("Sending...", false)
	var body := {
		"target_number": target_number, "category": _cat, "note": _note.text.strip_edges(),
		"settings": settings, "song": song, "chat": _chat_lines(),
		"screenshot": Marshalls.raw_to_base64(shot_png),
	}
	_http = HTTPRequest.new()
	add_child(_http)
	_http.connect("request_completed", self, "_on_sent")
	var url := "%s?client_id=%s" % [REPORT_URL, String(Rhythia._ensure_client_id()).http_escape()]
	if _http.request(url, ["Content-Type: application/json"], true, HTTPClient.METHOD_POST, JSON.print(body)) != OK:
		_http.queue_free()
		_http = null
		_send.disabled = false
		_say("Couldn't send it.", true)

func _on_sent(result, code, _headers, body):
	_http.queue_free()
	_http = null
	var j = JSON.parse(body.get_string_from_utf8()).result if result == HTTPRequest.RESULT_SUCCESS else null
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and j is Dictionary and bool(j.get("ok", false)):
		_say("Report sent.", false)
		yield(get_tree().create_timer(1.4), "timeout")
		_close()
		return
	_send.disabled = false
	var why: String = Globals.s(j.get("error", "")) if j is Dictionary else ""
	_say(why if why != "" else "Couldn't send it.", true)

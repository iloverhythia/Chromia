extends Control
# The ban screen ("Access Denied"). It used to be one flat picture with a
# made-up reason drawn into it. Now it's built here, in the same look (the
# dark page, the navy card, the red warning sign over the message), alive:
# a slow red glow drifts behind the card, the warning sign pulses, the card
# eases in. The reason is the one the admin wrote when banning (the server
# sends it with the ban status, and a changed reason shows within seconds),
# and under the message a clip plays on a loop (click it to mute it).

const RECHECK_INTERVAL_SEC = 10.0
const CLIP := "res://scenes/errors/banned.ogv"
const BG := Color(0.098, 0.098, 0.098)
const CARD := Color(0.118, 0.161, 0.231)
const CARD_EDGE := Color(0.17, 0.22, 0.33)
const BOX := Color(0.2, 0.153, 0.204)
const BOX_EDGE := Color(0.42, 0.14, 0.2)
const RED := Color(1.0, 0.42, 0.45)
const TEXT := Color(0.82, 0.83, 0.87)

var _recheck_timer: Timer
var _reason := ""
var _card: PanelContainer = null
var _reason_label: Label = null
var _video: VideoPlayer = null
var _muted := false
var _built_for := Vector2.ZERO

func _ready():
	Rhythia.trail("ban screen")
	anchor_right = 1.0
	anchor_bottom = 1.0
	_reason = String(Rhythia.get("live_ban_reason")) if Rhythia.get("live_ban_reason") != null else ""
	var bg := ColorRect.new()
	bg.name = "Glow"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.color = BG
	var sh := Shader.new()
	sh.code = GLOW
	var mat := ShaderMaterial.new()
	mat.shader = sh
	bg.material = mat
	add_child(bg)
	_build()
	get_viewport().connect("size_changed", self, "_build")
	_recheck_timer = Timer.new()
	_recheck_timer.wait_time = RECHECK_INTERVAL_SEC
	_recheck_timer.autostart = true
	_recheck_timer.connect("timeout", self, "_recheck_live_ban")
	add_child(_recheck_timer)
	_recheck_live_ban() # (the reason right away, when this screen came from the built-in list)

# the page behind the card: its dark grey with two soft red lights wandering
# slowly, and darker corners (plain maths, works on every renderer)
const GLOW := """
shader_type canvas_item;
uniform float aspect = 1.78;
void fragment() {
	vec2 p = vec2(UV.x * aspect, UV.y);
	float t = TIME * 0.22;
	vec2 a = vec2(aspect * 0.5 + sin(t) * aspect * 0.28, 0.42 + cos(t * 0.7) * 0.22);
	vec2 b = vec2(aspect * 0.5 + cos(t * 0.6 + 2.0) * aspect * 0.34, 0.6 + sin(t * 0.9 + 1.0) * 0.25);
	float g = 0.085 * exp(-dot(p - a, p - a) * 3.2) + 0.06 * exp(-dot(p - b, p - b) * 4.5);
	g *= 0.85 + 0.15 * sin(TIME * 1.3);
	vec2 v = UV - 0.5;
	float vig = 1.0 - dot(v, v) * 0.55;
	COLOR = vec4((vec3(0.098) + vec3(1.0, 0.22, 0.28) * g) * vig, 1.0);
}
"""

func _font(file: String, size: float) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/%s.ttf" % file)
	f.size = int(max(round(size), 8))
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return f

func _box(bg: Color, edge: Color, radius: float, pad_h: float, pad_v: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = edge
	s.set_border_width_all(2)
	s.set_corner_radius_all(int(radius))
	s.corner_detail = 16
	s.anti_aliasing = true
	s.anti_aliasing_size = 1.0
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s

func _label(text: String, f: Font, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.align = Label.ALIGN_CENTER
	l.autowrap = true
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	return l

# Everything is sized from the window's height (the design is 720 tall), and
# made again when the window changes; the clip keeps playing through that.
func _build():
	var size: Vector2 = get_viewport_rect().size
	if size == _built_for or size.y < 50:
		return
	var first: bool = _card == null
	_built_for = size
	var k: float = size.y / 720.0
	$Glow.material.set_shader_param("aspect", size.x / max(size.y, 1.0))
	if _video != null and _video.get_parent() != null:
		_video.get_parent().remove_child(_video)
	if _card != null:
		_card.queue_free()

	_card = PanelContainer.new()
	_card.add_stylebox_override("panel", _box(CARD, CARD_EDGE, 28 * k, 26 * k, 24 * k))
	var w: float = min(440.0 * k, size.x - 24.0)
	_card.rect_min_size = Vector2(w, 0)
	add_child(_card)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", int(12 * k))
	_card.add_child(v)

	var sign_holder := CenterContainer.new()
	v.add_child(sign_holder)
	var warn := Sign.new()
	warn.rect_min_size = Vector2(84, 84) * k
	sign_holder.add_child(warn)

	v.add_child(_label("Access Denied", _font("Lato-Black", 25 * k), Color(1, 1, 1)))

	var box := PanelContainer.new()
	box.add_stylebox_override("panel", _box(BOX, BOX_EDGE, 22 * k, 18 * k, 14 * k))
	v.add_child(box)
	var bv := VBoxContainer.new()
	bv.add_constant_override("separation", int(9 * k))
	box.add_child(bv)
	bv.add_child(_label("You have been banned from using Chromia", _font("Lato-Regular", 17 * k), TEXT))
	var line := ColorRect.new()
	line.color = Color(BOX_EDGE.r, BOX_EDGE.g, BOX_EDGE.b, 0.7)
	line.rect_min_size = Vector2(0, max(1.0, round(k)))
	bv.add_child(line)
	bv.add_child(_label("Reason:", _font("Lato-Regular", 13 * k), RED))
	_reason_label = _label("", _font("Lato-Italic", 15 * k), TEXT)
	bv.add_child(_reason_label)
	_show_reason()

	# the clip, under the message
	var frame := PanelContainer.new()
	frame.add_stylebox_override("panel", _box(Color(0, 0, 0), BOX_EDGE, 6 * k, 2, 2))
	frame.size_flags_horizontal = SIZE_SHRINK_CENTER
	frame.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	frame.hint_tooltip = "Click to mute / unmute"
	frame.connect("gui_input", self, "_on_clip_input")
	v.add_child(frame)
	# (as tall as the window leaves it, at the clip's own 9:16 shape)
	var used: float = (84 + 34 + 150 + 12 * 4 + 24 * 2 + 30) * k
	var vh: float = clamp(size.y * 0.94 - used, 120.0 * k, 360.0 * k)
	if _video == null:
		_video = VideoPlayer.new()
		_video.expand = true
		_video.mouse_filter = MOUSE_FILTER_IGNORE
		_video.volume_db = -8.0
		var st = load(CLIP) if ResourceLoader.exists(CLIP) else null
		if st != null:
			_video.stream = st
			_video.connect("finished", self, "_loop_clip")
	_video.rect_min_size = Vector2(round(vh * 9.0 / 16.0), round(vh))
	frame.add_child(_video)
	frame.visible = _video.stream != null
	if _video.stream != null and not _video.is_playing():
		_video.play()

	# in the middle of the window (after its size is known)
	yield(get_tree(), "idle_frame")
	if not is_instance_valid(_card):
		return
	var cs: Vector2 = _card.get_combined_minimum_size()
	_card.rect_size = cs
	_card.rect_position = ((size - cs) / 2.0).round()
	if first:
		# eases in: a little lower and see-through, to its place
		_card.modulate.a = 0.0
		var tw := Tween.new()
		add_child(tw)
		var to: Vector2 = _card.rect_position
		tw.interpolate_property(_card, "modulate:a", 0.0, 1.0, 0.45, Tween.TRANS_SINE, Tween.EASE_OUT)
		tw.interpolate_property(_card, "rect_position", to + Vector2(0, 26 * k), to, 0.55, Tween.TRANS_CUBIC, Tween.EASE_OUT)
		tw.connect("tween_all_completed", tw, "queue_free")
		tw.start()

func _show_reason():
	if _reason_label == null or not is_instance_valid(_reason_label):
		return
	var r := _reason.strip_edges()
	_reason_label.text = ("“%s”" % r) if r != "" else "No reason was given."
	_reason_label.modulate.a = 1.0 if r != "" else 0.6

func _loop_clip():
	if _video != null and is_instance_valid(_video):
		_video.play()

func _on_clip_input(ev: InputEvent):
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT and _video != null:
		_muted = not _muted
		_video.volume_db = -80.0 if _muted else -8.0

func _recheck_live_ban():
	if Rhythia.cid == "":
		return
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_recheck_completed", [http_request])
	var error = http_request.request(Rhythia.LIVE_BAN_STATUS_URL + "?client_id=" + Rhythia.cid.http_escape())
	if error != OK:
		http_request.queue_free()

func _on_recheck_completed(result, response_code, headers, body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		return
	var json_result = JSON.parse(body.get_string_from_utf8())
	if json_result.error != OK or typeof(json_result.result) != TYPE_DICTIONARY:
		return
	if bool(json_result.result.get("banned", false)):
		# (the admin's words, and their change: banning again with a new reason)
		var r = json_result.result.get("reason", "")
		r = String(r) if r is String else ""
		if r != _reason:
			_reason = r
			Rhythia.set("live_ban_reason", r)
			_show_reason()
			_built_for = Vector2.ZERO # (a longer or shorter reason: the card's size again)
			_build()
	elif not Rhythia.is_client_banned(Rhythia.cid):
		# (banned by the built-in list: that one stays; going back to the start
		# only put this screen up again, every ten seconds)
		get_tree().change_scene("res://scenes/init.tscn")

# The warning sign: the red triangle with its "!" in a dark red disc, and a
# ring that swells out of it and fades, again and again.
class Sign extends Control:
	var t := 0.0
	func _process(delta):
		t += delta
		update()
	func _draw():
		var c: Vector2 = rect_size / 2.0
		var r: float = min(c.x, c.y) * 0.78
		var ph: float = fmod(t, 2.2) / 2.2
		draw_arc(c, r * (1.0 + ph * 0.28), 0, TAU, 48, Color(1.0, 0.3, 0.36, (1.0 - ph) * 0.45), max(1.5, r * 0.05), true)
		draw_circle(c, r, Color(0.29, 0.13, 0.2))
		draw_arc(c, r, 0, TAU, 64, Color(0.55, 0.15, 0.22), max(2.0, r * 0.09), true)
		var beat: float = 0.92 + 0.08 * sin(t * 2.6)
		var col := Color(1.0, 0.42, 0.45, beat)
		var s: float = r * 0.62
		var top := c + Vector2(0, -s * 0.92)
		var left := c + Vector2(-s, s * 0.72)
		var right := c + Vector2(s, s * 0.72)
		var wd: float = max(2.0, r * 0.11)
		draw_polyline(PoolVector2Array([top, right, left, top, right]), col, wd, true)
		for p in [top, left, right]:
			draw_circle(p, wd * 0.5, col)
		draw_line(c + Vector2(0, -s * 0.38), c + Vector2(0, s * 0.18), col, wd, true)
		draw_circle(c + Vector2(0, -s * 0.38), wd * 0.5, col)
		draw_circle(c + Vector2(0, s * 0.18), wd * 0.5, col)
		draw_circle(c + Vector2(0, s * 0.46), wd * 0.62, col)

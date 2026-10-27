extends Control

# Discord login in VR (Savia.gd start_discord_login): the login page as a QR
# code to scan with your phone, so you never have to leave the headset or type
# a password in it. The server links your Discord account to this game when
# you finish on the phone, and the game notices by itself (it keeps checking).
# On the Meta Quest app there's also a button to open the page in the
# headset's browser; on PC VR the page opens on the computer as well.
#
# A plain Control on the VR menu screen (a CanvasLayer there gets the pointer
# at the wrong spot), or in a CanvasLayer on the window.

var url := ""
var _status: Label
var _close_t := -1.0
var _font: DynamicFont
var _bold: DynamicFont
var _big: DynamicFont

static func show_for(link: String):
	var vp = null
	if Rhythia.vr and is_instance_valid(Rhythia.vr_menu) and Rhythia.vr_menu.has_node("Viewport"):
		vp = Rhythia.vr_menu.get_node("Viewport")
	for old in _all_panels():
		old.queue_free()
	var p = load("res://scripts/ui/settings/DiscordLoginPanel.gd").new()
	p.name = "DiscordLoginPanel"
	p.url = link
	if vp != null:
		vp.add_child(p)
	else:
		var holder := CanvasLayer.new()
		holder.layer = 112
		holder.add_child(p)
		Rhythia.get_tree().root.add_child(holder)

static func _all_panels() -> Array:
	var out := []
	var places := [Rhythia.get_tree().root]
	if is_instance_valid(Rhythia.vr_menu) and Rhythia.vr_menu.has_node("Viewport"):
		places.append(Rhythia.vr_menu.get_node("Viewport"))
	for pl in places:
		for c in pl.get_children():
			if c.name == "DiscordLoginPanel":
				out.append(c)
			elif c is CanvasLayer and c.has_node("DiscordLoginPanel"):
				out.append(c.get_node("DiscordLoginPanel"))
	return out

func _font_of(path: String, size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	return f

func _ready():
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_STOP
	_font = _font_of("res://assets/font/Lato/Lato-Regular.ttf", 18)
	_bold = _font_of("res://assets/font/Lato/Lato-Bold.ttf", 19)
	_big = _font_of("res://assets/font/Lato/Lato-Black.ttf", 30)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	add_child(dim)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.065, 0.11, 0.98)
	sb.border_color = Color(0.35, 0.40, 0.95, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	for side in ["left", "right", "top", "bottom"]:
		sb.set("content_margin_" + side, 20)
	panel.add_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = GROW_DIRECTION_BOTH
	panel.grow_vertical = GROW_DIRECTION_BOTH
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 24)
	panel.add_child(row)
	var qr := TextureRect.new()
	qr.texture = load("res://scripts/QRCode.gd").texture(url, 6)
	qr.expand = true
	qr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	qr.rect_min_size = Vector2(330, 330)
	row.add_child(qr)
	var col := VBoxContainer.new()
	col.add_constant_override("separation", 12)
	col.rect_min_size = Vector2(420, 0)
	row.add_child(col)
	_label(col, "Connect Discord", _big, Color(0.62, 0.67, 1.0))
	var how := "Scan the code with your phone's camera and log in with Discord there. The game links by itself when you're done: keep this open."
	if not OS.has_feature("quest"):
		how += "\n\nThe login page also opened on your computer's screen."
	_label(col, how, _font, Color(0.85, 0.86, 0.92), true)
	_status = _label(col, "Waiting for you to log in...", _bold, Color(1, 1, 1), true)
	var buttons := HBoxContainer.new()
	buttons.add_constant_override("separation", 10)
	col.add_child(buttons)
	if OS.has_feature("quest"):
		_button(buttons, "Open in the headset's browser", "_open_here")
	_button(buttons, "Cancel", "_cancel")
	Rhythia.connect("discord_login_changed", self, "_on_changed")
	yield(get_tree(), "idle_frame")
	panel.margin_left = -panel.rect_size.x / 2
	panel.margin_top = -panel.rect_size.y / 2

func _label(parent: Node, text: String, f: Font, c: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap = wrap
	l.add_font_override("font", f)
	l.add_color_override("font_color", c)
	parent.add_child(l)
	return l

func _button(parent: Node, text: String, method: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", _bold)
	b.rect_min_size = Vector2(120, 44)
	b.focus_mode = FOCUS_NONE
	b.connect("pressed", self, method)
	parent.add_child(b)
	return b

func _open_here():
	OS.shell_open(url)

func _cancel():
	Rhythia.cancel_discord_login()
	_close()

func _close():
	var p = get_parent()
	if p is CanvasLayer and p.get_child_count() == 1:
		p.queue_free()
	else:
		queue_free()

func _on_changed():
	if Rhythia.discord_user.has("username") and String(Rhythia.discord_user.username) != "":
		_status.text = "Linked as %s!" % String(Rhythia.discord_user.username)
		_status.add_color_override("font_color", Color(0.6, 1, 0.7))
		_close_t = 2.0
	elif Rhythia.discord_login_error != "":
		_status.text = Rhythia.discord_login_error
		_status.add_color_override("font_color", Color(1, 0.6, 0.6))

func _process(delta):
	if _close_t >= 0.0:
		_close_t -= delta
		if _close_t < 0.0:
			_close()
		return
	var left: float = Rhythia.discord_login_left()
	if left > 0.0 and Rhythia.discord_login_error == "":
		_status.text = "Waiting for you to log in... (%d:%02d left)" % [int(left) / 60, int(left) % 60]

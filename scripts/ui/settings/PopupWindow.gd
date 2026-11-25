extends Control
# A window over the whole screen with the Background picker's frame
# (WorldPicker.gd): the screen dimmed behind it, a title, Close, and `content`
# in a scrolling area. Follows the Menu Customizer look the same way.
# Used by Settings > VR > Hands for the Hand Creator (HandCreatorPanel.gd).
#
#   var w = PopupWindow.new(); w.title_text = "..."; w.content = some_control
#   PopupWindow.show_over(button, w)   # on the window, or on the VR menu screen

signal closed

var title_text := ""
var content: Control = null
var max_width := 1100.0

var _root: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _S = null
var _radius := -1

# (as WorldSel.gd puts the Background picker: in a CanvasLayer on the window,
# or straight on the VR menu screen, where a CanvasLayer gets the pointer wrong)
static func show_over(near: Node, w: Control):
	var vp = near.get_viewport()
	if vp == near.get_tree().root:
		var holder := CanvasLayer.new()
		holder.layer = 110
		holder.add_child(w)
		vp.add_child(holder)
	else:
		vp.add_child(w)

func _ready():
	var MS = load("res://scripts/ui/menu/MenuStyle.gd")
	var st: Dictionary = MS.data().style
	if not st.empty():
		_S = load("res://scripts/ui/menu/OnlineStyle.gd").new()
		if st.has("btn_radius"):
			_radius = int(MS.get_value("btn_radius"))
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = MOUSE_FILTER_IGNORE
	_build()
	get_viewport().connect("size_changed", self, "_layout")
	_layout()

func _build():
	_root = Control.new()
	_root.anchor_right = 1.0
	_root.anchor_bottom = 1.0
	add_child(_root)

	var dim := ColorRect.new()
	dim.add_to_group("wheel_blocker")
	dim.color = Color(0, 0, 0, 0.62)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.connect("gui_input", self, "_on_dim_input")
	_root.add_child(dim)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.075, 0.065, 0.11, 0.98) if _S == null else Color(_S.CARD_BG.r, _S.CARD_BG.g, _S.CARD_BG.b, 0.98)
	sb.border_color = Color(0.78, 0.62, 1.0, 0.45) if _S == null else Color(_S.LILAC.r, _S.LILAC.g, _S.LILAC.b, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14 if _radius < 0 else int(clamp(_radius * 2, 0, 24)))
	sb.corner_detail = 16
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_panel.add_stylebox_override("panel", sb)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.5
	_root.add_child(_panel)

	var col := VBoxContainer.new()
	col.add_constant_override("separation", 8)
	_panel.add_child(col)

	var top := HBoxContainer.new()
	col.add_child(top)
	var big := DynamicFont.new()
	big.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	big.size = 26
	var title := Label.new()
	title.text = title_text
	title.add_font_override("font", big)
	title.add_color_override("font_color", Color(0.898, 0.949, 1.0) if _S == null else _S.ACCENT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var font := DynamicFont.new()
	font.font_data = load("res://assets/font/Lato/Lato-Regular.ttf")
	font.size = 17
	var close := Button.new()
	close.text = "Close"
	close.add_font_override("font", font)
	if _S != null:
		_S.button(close, true)
		if _radius >= 0:
			for k in ["normal", "hover", "pressed", "disabled"]:
				var b = close.get_stylebox(k)
				if b is StyleBoxFlat:
					b.set_corner_radius_all(int(clamp(_radius, 0, 20)))
	close.rect_min_size = Vector2(96, 44)
	close.connect("pressed", self, "close")
	top.add_child(close)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.scroll_horizontal_enabled = false
	col.add_child(_scroll)
	if content != null:
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_scroll.add_child(content)

func _layout():
	if _panel == null:
		return
	var vp: Vector2 = _root.get_viewport_rect().size
	var size = Vector2(min(vp.x - 20, max_width), vp.y - 20)
	_panel.margin_left = -size.x / 2
	_panel.margin_right = size.x / 2
	_panel.margin_top = -size.y / 2
	_panel.margin_bottom = size.y / 2

func _on_dim_input(e: InputEvent):
	if e is InputEventMouseButton and e.pressed:
		close()

func _unhandled_input(e: InputEvent):
	if e.is_action_pressed("ui_cancel"):
		get_tree().set_input_as_handled()
		close()

func close():
	emit_signal("closed")
	var p = get_parent()
	if p is CanvasLayer and p.get_child_count() == 1:
		p.queue_free()
	else:
		queue_free()

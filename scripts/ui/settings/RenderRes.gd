extends HBoxContainer

# Settings > Video & Audio > Graphics: "Render Resolution" (computers only).
# How many pixels the game draws: Auto, or a share of the window's size.
# See Rhythia.apply_render_res.

var _pick: OptionButton

static func attach(after: Control) -> Node:
	var p = after.get_parent()
	if p == null or p.has_node("RenderRes"):
		return null
	if Rhythia.device("mobile") or OS.has_feature("JavaScript") or OS.has_feature("quest"):
		return null
	var row = load("res://scripts/ui/settings/RenderRes.gd").new()
	row.name = "RenderRes"
	row._build(after)
	p.add_child(row)
	p.move_child(row, after.get_index() + 1)
	return row

func _build(like: Control):
	add_constant_override("separation", 10)
	hint_tooltip = "How many pixels the game draws. Fewer is faster and a little less sharp.\nAuto: on a Mac's Retina screen the pixels of a normal screen (a quarter of the work), everything else at full resolution.\nYour mouse feels the same at every choice."
	var l := Label.new()
	l.text = "Render Resolution"
	l.theme = like.theme
	if like.has_font("font"):
		l.add_font_override("font", like.get_font("font"))
	l.add_color_override("font_color", Color(0.898039, 0.94902, 1))
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(l)
	_pick = OptionButton.new()
	_pick.theme = like.theme
	if like.has_font("font"):
		_pick.add_font_override("font", like.get_font("font"))
	_pick.rect_min_size = Vector2(200, 28)
	_pick.hint_tooltip = hint_tooltip
	for v in Rhythia.RENDER_RES_CHOICES:
		_pick.add_item(_name_of(v))
		_pick.set_item_metadata(_pick.get_item_count() - 1, v)
	_pick.connect("item_selected", self, "_picked")
	add_child(_pick)
	_show()

static func _name_of(v: int) -> String:
	if v > 0:
		return "%d%%" % v
	var auto := 100.0
	if OS.has_feature("OSX"):
		auto = 100.0 / clamp(OS.get_screen_scale(), 1.0, 3.0)
	return "Auto (%d%%)" % int(round(auto))

func _show():
	for i in range(_pick.get_item_count()):
		if int(_pick.get_item_metadata(i)) == Rhythia.render_res:
			_pick.select(i)

func _picked(i: int):
	Rhythia.render_res = int(_pick.get_item_metadata(i))
	Rhythia.apply_render_res()
	Rhythia.save_settings()

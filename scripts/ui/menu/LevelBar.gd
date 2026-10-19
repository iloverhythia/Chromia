extends PanelContainer
# Level / Prestige bar for the Profile tab (BeatLeader style): a hexagon badge,
# "Prestige: N", the experience bar and the level. At level 100 a Prestige
# button shows up. Data: scripts/PlayerLevel.gd.

const PlayerLevel = preload("res://scripts/PlayerLevel.gd")
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)
# badge color per prestige (0 = gray, then up the rainbow)
const PRESTIGE_COLORS = [
	Color(0.45, 0.42, 0.5), Color(0.55, 0.85, 1.0), Color(0.5, 1.0, 0.65), Color(1.0, 0.92, 0.45),
	Color(1.0, 0.65, 0.35), Color(1.0, 0.45, 0.45), Color(1.0, 0.5, 0.85), Color(0.75, 0.55, 1.0),
	Color(0.5, 0.6, 1.0), Color(0.6, 1.0, 1.0), Color(1.0, 1.0, 1.0),
]

var store
var badge: Control
var prestige_label: Label
var level_label: Label
var bar: Control
var prestige_btn: Button
var _shown := 0.0 # animated fill

func _ready():
	store = PlayerLevel.get_store()
	var sb = StyleBoxFlat.new()
	sb.draw_center = false # no background, just the badge, text and bar
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_stylebox_override("panel", sb)
	mouse_filter = MOUSE_FILTER_PASS

	var h = HBoxContainer.new()
	h.add_constant_override("separation", 10)
	add_child(h)

	badge = Control.new()
	badge.rect_min_size = Vector2(30, 30)
	badge.connect("draw", self, "_draw_badge")
	h.add_child(badge)

	prestige_label = Label.new()
	prestige_label.add_color_override("font_color", TEXT)
	prestige_label.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(prestige_label)

	bar = Control.new()
	bar.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	bar.rect_min_size = Vector2(60, 10)
	bar.connect("draw", self, "_draw_bar")
	h.add_child(bar)

	level_label = Label.new()
	level_label.add_color_override("font_color", TEXT)
	level_label.size_flags_vertical = SIZE_SHRINK_CENTER
	level_label.rect_min_size = Vector2(28, 0)
	level_label.align = Label.ALIGN_RIGHT
	h.add_child(level_label)

	prestige_btn = Button.new()
	prestige_btn.text = "Prestige"
	prestige_btn.theme = load("res://uitheme.tres")
	prestige_btn.focus_mode = FOCUS_NONE
	prestige_btn.visible = false
	prestige_btn.connect("pressed", self, "_on_prestige")
	h.add_child(prestige_btn)

	store.connect("changed", self, "_refresh")
	_refresh()
	_shown = store.progress()

func _refresh():
	if not is_instance_valid(prestige_label):
		return
	prestige_label.text = "Prestige: %d" % store.prestige
	level_label.text = str(store.level)
	prestige_btn.visible = store.can_prestige()
	if store.level >= PlayerLevel.MAX_LEVEL:
		hint_tooltip = "Level %d (max). %s" % [store.level, "You can Prestige now!" if store.can_prestige() else "Max prestige reached."]
	else:
		hint_tooltip = "Level %d — %d | %d to level %d\nEarn experience by playing any map, even failing.\nReach level 100 to Prestige.\nTotal earned: %s" % [
			store.level, store.cur_exp, store.required(), store.level + 1, Globals.comma_sep(store.total_exp)]
	badge.update()
	set_process(true)

func _process(delta):
	var target: float = store.progress()
	if abs(_shown - target) < 0.002:
		_shown = target
		set_process(false)
	else:
		_shown = lerp(_shown, target, min(delta * 6.0, 1.0))
	bar.update()

func _draw_bar():
	var r = Rect2(Vector2.ZERO, bar.rect_size)
	var h = r.size.y
	bar.draw_style_box(_rounded(Color(0.2, 0.2, 0.22, 1), h / 2), r)
	var w = r.size.x * clamp(_shown, 0.0, 1.0)
	if w > 1:
		var col = LILAC.linear_interpolate(Color(1, 1, 1), 0.15)
		bar.draw_style_box(_rounded(col, h / 2), Rect2(Vector2.ZERO, Vector2(max(w, h), h)))

func _rounded(c: Color, rad: float) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(int(rad))
	return sb

func _draw_badge():
	var c = badge.rect_size / 2
	var rad = min(c.x, c.y) - 1
	var pts = PoolVector2Array()
	for i in range(7):
		var a = PI / 6.0 + i * PI / 3.0
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	var col: Color = PRESTIGE_COLORS[clamp(store.prestige, 0, PRESTIGE_COLORS.size() - 1)]
	badge.draw_polyline(pts, col, 3.5, true)
	if store.prestige > 0:
		var inner = PoolVector2Array()
		for i in range(6):
			var a = PI / 6.0 + i * PI / 3.0
			inner.append(c + Vector2(cos(a), sin(a)) * (rad - 5))
		badge.draw_colored_polygon(inner, Color(col.r, col.g, col.b, 0.25))

func _on_prestige():
	if store.do_prestige():
		Globals.notify(Globals.NOTIFY_INFO, "You're now Prestige %d. Every level costs 20%% more experience." % store.prestige, "Prestige!")

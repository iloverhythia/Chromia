extends PanelContainer
# Level / Prestige bar for the Profile tab (BeatLeader style): a hexagon badge,
# "Prestige: N", the experience bar and the level. At level 100 a Prestige
# button shows up. Data: scripts/PlayerLevel.gd.

const PlayerLevel = preload("res://scripts/PlayerLevel.gd")
const LILAC = Color(0.764706, 0.65098, 0.8)
const ACCENT = Color(1, 0.756863, 0.960784)
const TEXT = Color(0.898039, 0.94902, 1, 1)
const PrestigeBadge = preload("res://scripts/ui/PrestigeBadge.gd") # (a badge of its own for every prestige)

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
	badge.rect_min_size = Vector2(36, 36)
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

	if _style != null:
		use_style(_style)
	store.connect("changed", self, "_refresh")
	_refresh()
	_shown = store.progress()

# the Online page's fonts and button (OnlineStyle.gd), for the profile panel
var _style = null
func use_style(S):
	_style = S
	if not is_instance_valid(prestige_label):
		return # not built yet: _ready applies it
	prestige_label.add_font_override("font", S.f_bold)
	level_label.add_font_override("font", S.f_bold)
	S.button(prestige_btn, true, true)

func _refresh():
	if not is_instance_valid(prestige_label):
		return
	prestige_label.text = "Prestige: %s" % Globals.comma_sep(store.prestige)
	level_label.text = Globals.comma_sep(store.level) if store.level >= 1000 else str(store.level)
	prestige_btn.visible = store.can_prestige()
	var badge_line: String = PrestigeBadge.describe(store.prestige)
	if store.level >= store.max_level():
		hint_tooltip = "Level %d (max). %s\n%s" % [store.level, "You can Prestige now!" if store.can_prestige() else "Max prestige reached.", badge_line]
	elif store.endless():
		hint_tooltip = "Level %s — %s | %s to level %s\nPrestige 10,000 is the last one: from here your level has no end.\nTotal earned: %s\n%s" % [
			Globals.comma_sep(store.level), Globals.comma_sep(store.cur_exp), Globals.comma_sep(store.required()), Globals.comma_sep(store.level + 1), Globals.comma_sep(store.total_exp), badge_line]
	else:
		hint_tooltip = "Level %d — %d | %d to level %d\nEarn experience by playing any map, even failing.\nReach level 100 to Prestige (there are 10,000, each with its own badge).\nTotal earned: %s\n%s" % [
			store.level, store.cur_exp, store.required(), store.level + 1, Globals.comma_sep(store.total_exp), badge_line]
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
	PrestigeBadge.draw(badge, c, min(c.x, c.y) - 1, store.prestige)

func _on_prestige():
	if store.do_prestige():
		var note: String = "You're now Prestige %s, with a new badge." % Globals.comma_sep(store.prestige)
		if store.prestige >= PlayerLevel.MAX_PRESTIGE:
			note = "Prestige 10,000: the last one. Your level has no end from here."
		elif store.prestige <= PlayerLevel.COST_PRESTIGES:
			note += " Every level costs 20% more experience."
		Globals.notify(Globals.NOTIFY_INFO, note, "Prestige!")

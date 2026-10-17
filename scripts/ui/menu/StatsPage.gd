extends Control

# Stats page: lifetime play stats (user://stats.json) plus a summary of
# personal bests. Rebuilt every time the page is shown.

const COLOR_VALUE = Color(1, 1, 1)
const COLOR_LABEL = Color(0.75, 0.78, 0.85)
const COLOR_TILE = Color(0.12, 0.12, 0.18, 0.85)

var _grid: GridContainer
var _most_played: VBoxContainer
var _since: Label

func _font(size: int, bold: bool) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf" if bold else "res://assets/font/Lato/Lato-Regular.ttf")
	f.size = size
	return f

func _ready():
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.margin_left = 80
	scroll.margin_right = -40
	scroll.margin_top = 30
	scroll.margin_bottom = -20
	scroll.scroll_horizontal_enabled = false
	add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_constant_override("separation", 18)
	scroll.add_child(v)

	var title := Label.new()
	title.text = "Stats"
	title.add_font_override("font", _font(40, true))
	v.add_child(title)

	_since = Label.new()
	_since.add_font_override("font", _font(18, false))
	_since.add_color_override("font_color", COLOR_LABEL)
	v.add_child(_since)

	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_constant_override("hseparation", 14)
	_grid.add_constant_override("vseparation", 14)
	v.add_child(_grid)

	var mp_title := Label.new()
	mp_title.text = "Most played"
	mp_title.add_font_override("font", _font(26, true))
	v.add_child(mp_title)

	_most_played = VBoxContainer.new()
	v.add_child(_most_played)

	connect("visibility_changed", self, "_on_visibility_changed")
	refresh()

func _on_visibility_changed():
	if is_visible_in_tree():
		refresh()

func _tile(value: String, label: String):
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_TILE
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_stylebox_override("panel", sb)
	panel.rect_min_size = Vector2(250, 0)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var val := Label.new()
	val.text = value
	val.add_font_override("font", _font(30, true))
	val.add_color_override("font_color", COLOR_VALUE)
	box.add_child(val)
	var lab := Label.new()
	lab.text = label
	lab.add_font_override("font", _font(16, false))
	lab.add_color_override("font_color", COLOR_LABEL)
	box.add_child(lab)
	_grid.add_child(panel)

func _duration(ms: int) -> String:
	var seconds := int(ms / 1000)
	if seconds < 60:
		return "%ds" % seconds
	var minutes := seconds / 60
	if minutes < 60:
		return "%dm %02ds" % [minutes, seconds % 60]
	return "%dh %02dm" % [minutes / 60, minutes % 60]

func _pct(a: float, b: float) -> String:
	if b <= 0:
		return "-"
	return "%.2f%%" % (100.0 * a / b)

func refresh():
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	for c in _most_played.get_children():
		c.queue_free()

	var st: Dictionary = Rhythia.get_lifetime_stats()
	var pb: Dictionary = Rhythia.get_pb_summary()
	var plays := int(st.plays)
	var hit := int(st.notes_hit)
	var missed := int(st.notes_missed)

	if int(st.first_play_ts) > 0:
		var d := OS.get_datetime_from_unix_time(int(st.first_play_ts))
		_since.text = "Tracking since %04d-%02d-%02d" % [d.year, d.month, d.day]
	else:
		_since.text = "Play a map to start tracking stats."

	_tile(Globals.comma_sep(plays), "Plays")
	_tile(Globals.comma_sep(int(st.passes)), "Passes (%s)" % _pct(int(st.passes), plays))
	_tile(Globals.comma_sep(int(st.fails)), "Fails")
	_tile(Globals.comma_sep(int(st.give_ups)), "Give ups")
	_tile(_duration(int(st.play_time_ms)), "Time played")
	_tile(Globals.comma_sep(hit), "Notes hit")
	_tile(Globals.comma_sep(missed), "Notes missed")
	_tile(_pct(hit, hit + missed), "Overall accuracy")
	_tile(Globals.comma_sep(int(st.best_combo)), "Best combo")
	_tile(Globals.comma_sep(int(pb.maps_passed)), "Maps passed")
	_tile(Globals.comma_sep(int(pb.full_combos)), "Full combos")
	_tile(("%.2f%%" % (pb.avg_best_accuracy * 100.0)) if pb.maps_passed > 0 else "-", "Avg. best accuracy")
	_tile(Globals.comma_sep(int(Rhythia.jp)), "XP")
	_tile(Globals.comma_sep(int(Rhythia.sp)), "SP")
	_tile(Globals.comma_sep(int(pb.maps_played)), "Maps with a record")

	var counts: Dictionary = st.get("map_plays", {})
	var ids := counts.keys()
	ids.sort_custom(self, "_by_count_desc")
	if ids.empty():
		var none := Label.new()
		none.text = "Nothing yet."
		none.add_color_override("font_color", COLOR_LABEL)
		_most_played.add_child(none)
	for i in range(min(10, ids.size())):
		var song = Rhythia.registry_song.get_item(ids[i]) if Rhythia.registry_song else null
		var row := Label.new()
		var n := int(counts[ids[i]])
		row.text = "%d.  %s  —  %s %s" % [i + 1, song.name if song else String(ids[i]), Globals.comma_sep(n), "play" if n == 1 else "plays"]
		row.add_font_override("font", _font(18, false))
		_most_played.add_child(row)

func _by_count_desc(a, b) -> bool:
	var counts: Dictionary = Rhythia.get_lifetime_stats().get("map_plays", {})
	return int(counts.get(a, 0)) > int(counts.get(b, 0))

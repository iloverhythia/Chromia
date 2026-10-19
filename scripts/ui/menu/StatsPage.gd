extends Control

# Stats page: lifetime play stats (user://stats.json) plus a summary of
# personal bests. Rebuilt every time the page is shown.

const COLOR_VALUE = Color(1, 1, 1)
const COLOR_LABEL = Color(0.75, 0.78, 0.85)
const COLOR_TILE = Color(0.12, 0.12, 0.18, 0.85)
const COLOR_ACCENT = Color(1, 0.756863, 0.960784)
const COLOR_DIM = Color(1, 1, 1, 0.55)

var _grid: GridContainer
# Compact: shown as a tab in the profile panel (smaller margins, 2 columns).
var compact := false
var _most_played: VBoxContainer
var _since: Label

# Fonts are made once and reused (each new DynamicFont builds its own glyph
# textures, and refresh() used to make ~40 of them every time the page opened).
var _fonts := {}
func _font(size: int, bold: bool) -> DynamicFont:
	var key := "%d_%s" % [size, bold]
	if _fonts.has(key):
		return _fonts[key]
	var f := DynamicFont.new()
	_fonts[key] = f
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf" if bold else "res://assets/font/Lato/Lato-Regular.ttf")
	f.size = size
	return f

func _ready():
	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.margin_left = 4 if compact else 80
	scroll.margin_right = -4 if compact else -40
	scroll.margin_top = 8 if compact else 30
	scroll.margin_bottom = -4 if compact else -20
	scroll.scroll_horizontal_enabled = false
	add_child(scroll)

	if compact:
		# Same look as the Profile / Leaderboard tabs next to it: theme font, plain rows.
		theme = load("res://uitheme.tres")
		scroll.margin_left = 0
		scroll.margin_right = 0
		scroll.margin_top = 0
		scroll.margin_bottom = 0
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.rect_clip_content = true
	v.add_constant_override("separation", 8 if compact else 18)
	scroll.add_child(v)

	var title := Label.new()
	title.text = "Stats"
	title.add_font_override("font", _font(40, true))
	title.visible = not compact
	v.add_child(title)

	_since = Label.new()
	if not compact:
		_since.add_font_override("font", _font(18, false))
	_since.add_color_override("font_color", COLOR_LABEL)
	v.add_child(_since)

	_grid = GridContainer.new()
	_grid.columns = 1 if compact else 4
	_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_grid.add_constant_override("hseparation", 14)
	_grid.add_constant_override("vseparation", 2 if compact else 14)
	v.add_child(_grid)

	var mp_title := Label.new()
	mp_title.text = "Most played"
	if compact:
		mp_title.add_color_override("font_color", COLOR_ACCENT)
	else:
		mp_title.add_font_override("font", _font(26, true))
	v.add_child(mp_title)

	_most_played = VBoxContainer.new()
	_most_played.size_flags_horizontal = SIZE_EXPAND_FILL
	_most_played.add_constant_override("separation", 2)
	v.add_child(_most_played)

	connect("visibility_changed", self, "_on_visibility_changed")
	refresh()

# Opening the page refreshes it once it has stayed open for a moment, and at
# most every few seconds, so clicking quickly through the sidebar is cheap
# (the refresh reads every personal-best file from disk).
const REFRESH_EVERY_MS := 5000
var _last_refresh := -100000
var _refresh_timer: SceneTreeTimer = null
func _on_visibility_changed():
	if not is_visible_in_tree():
		return
	if OS.get_ticks_msec() - _last_refresh < REFRESH_EVERY_MS:
		return
	_refresh_timer = get_tree().create_timer(0.15)
	_refresh_timer.connect("timeout", self, "_delayed_refresh", [_refresh_timer])

func _delayed_refresh(t):
	if t != _refresh_timer or not is_inside_tree() or not is_visible_in_tree():
		return
	_refresh_timer = null
	refresh()

func _tile(value: String, label: String):
	if compact:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = SIZE_EXPAND_FILL
		var lab := Label.new()
		lab.text = label
		lab.size_flags_horizontal = SIZE_EXPAND_FILL
		lab.clip_text = true
		row.add_child(lab)
		var val := Label.new()
		val.text = value
		val.add_color_override("font_color", COLOR_ACCENT)
		row.add_child(val)
		_grid.add_child(row)
		return
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COLOR_TILE
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_stylebox_override("panel", sb)
	panel.rect_min_size = Vector2(0 if compact else 250, 0)
	if compact:
		panel.size_flags_horizontal = SIZE_EXPAND_FILL
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
	_last_refresh = OS.get_ticks_msec()
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
		var n := int(counts[ids[i]])
		if compact:
			var h := HBoxContainer.new()
			h.size_flags_horizontal = SIZE_EXPAND_FILL
			h.add_constant_override("separation", 8)
			var rk := Label.new()
			rk.text = "#%d" % (i + 1)
			rk.rect_min_size = Vector2(34, 0)
			rk.add_color_override("font_color", COLOR_DIM)
			h.add_child(rk)
			var nm := Label.new()
			nm.text = song.name if song else String(ids[i])
			nm.clip_text = true
			nm.size_flags_horizontal = SIZE_EXPAND_FILL
			nm.hint_tooltip = nm.text
			nm.mouse_filter = MOUSE_FILTER_PASS
			h.add_child(nm)
			var pc := Label.new()
			pc.text = "%s %s" % [Globals.comma_sep(n), "play" if n == 1 else "plays"]
			pc.add_color_override("font_color", COLOR_ACCENT)
			h.add_child(pc)
			_most_played.add_child(h)
			continue
		var row := Label.new()
		row.text = "%d.  %s  —  %s %s" % [i + 1, song.name if song else String(ids[i]), Globals.comma_sep(n), "play" if n == 1 else "plays"]
		row.add_font_override("font", _font(18, false))
		row.clip_text = true
		row.hint_tooltip = row.text
		row.mouse_filter = MOUSE_FILTER_PASS
		_most_played.add_child(row)

func _by_count_desc(a, b) -> bool:
	var counts: Dictionary = Rhythia.get_lifetime_stats().get("map_plays", {})
	return int(counts.get(a, 0)) > int(counts.get(b, 0))

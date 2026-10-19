extends Control
# "History" view on the map screen: your previous attempts on the selected map,
# best first. Sits in the same slot as the Best Attempt / PB box (EndInfo), with
# a small "Best | History" switch in the empty strip just above both (left of
# the "Modifiers" title).
#
# Hooked up from SongInfoScreen._ready() with ScoreHistoryPanel.attach(self).

const ScoreHistory = preload("res://scripts/ScoreHistory.gd")
const UI_THEME = preload("res://uitheme.tres")
const FONT_REGULAR = preload("res://assets/font/Lato/Lato-Regular.ttf")
const FONT_BOLD = preload("res://assets/font/Lato/Lato-Bold.ttf")
const FONT_BLACK = preload("res://assets/font/Lato/Lato-Black.ttf")
const FONT_JP = preload("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf")

const PREFS_PATH = "user://score_history/ui.cfg"
const MODE_BEST = 0
const MODE_HISTORY = 1
const SWITCH_H = 28
# The slot's rect is wider than what's visible: the sidebar covers its left
# edge and the Mods box's labels hang over its right edge.
const PAD_L = 19
const PAD_R = 40
# Header sits above the slot, in the gap between the separator and the PB box.
const HEAD_Y = -34
# Keep the list clear of the version label in the bottom left corner.
const BOTTOM_CLEAR = 76

const C_TEXT = Color(0.898039, 0.94902, 1, 1)
const C_DIM = Color(0.898039, 0.94902, 1, 0.6)
const C_ACCENT = Color(1, 0.756863, 0.960784)
const C_LILAC = Color(0.764706, 0.65098, 0.8)
const RANK_COLORS = [Color(1, 0.82, 0.36), Color(0.82, 0.86, 0.94), Color(0.9, 0.6, 0.38)]

var end_info: Control
var mode: int = MODE_BEST
var hide_failed: bool = false

var _rows: VBoxContainer
var _rows_wrap: MarginContainer
var _scroll: ScrollContainer
var _empty: Label
var _hide_box: CheckBox
var _head: HBoxContainer
var _switches: Array = [] # [[best_btn, hist_btn], ...]

var _loaded_id: String = ""
var _entries: Array = []
var _dirty: bool = true

var _f_name: DynamicFont
var _f_small: DynamicFont
var _f_rank: DynamicFont
var _f_grade: DynamicFont
var _f_tab: DynamicFont
var _f_avatar: DynamicFont

static func attach(screen: Node) -> Node:
	var ei = screen.get_node_or_null("RS/H2/EndInfo")
	if ei == null or not is_instance_valid(ei):
		return null
	var p = load("res://scripts/ui/menu/ScoreHistoryPanel.gd").new()
	p.name = "ScoreHistory"
	p.end_info = ei
	var h2 = ei.get_parent()
	h2.add_child(p)
	h2.move_child(p, ei.get_index() + 1)
	return p

func _font(data, size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = data
	f.size = size
	f.use_filter = true
	f.add_fallback(FONT_JP)
	return f

func _ready():
	theme = UI_THEME
	_f_name = _font(FONT_BOLD, 15)
	_f_small = _font(FONT_REGULAR, 13)
	_f_rank = _font(FONT_BLACK, 14)
	_f_grade = _font(FONT_BLACK, 24)
	_f_tab = _font(FONT_BOLD, 15)
	_f_avatar = _font(FONT_BLACK, 13)

	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	rect_min_size = Vector2(274, 280)
	mouse_filter = MOUSE_FILTER_IGNORE

	_load_prefs()

	# Switch + "Hide failed" for this view.
	var head := HBoxContainer.new()
	_head = head
	head.add_constant_override("separation", 12)
	head.add_child(_make_switch())
	_hide_box = CheckBox.new()
	_hide_box.text = "Hide failed"
	_hide_box.pressed = hide_failed
	_hide_box.focus_mode = FOCUS_NONE
	_hide_box.add_font_override("font", _f_tab)
	_hide_box.hint_tooltip = "Only show passed attempts"
	_hide_box.connect("toggled", self, "_on_hide_failed")
	head.add_child(_hide_box)
	add_child(head)

	_scroll = ScrollContainer.new()
	_scroll.scroll_horizontal_enabled = false
	add_child(_scroll)
	# Rows keep clear of the scrollbar's lane even when it's hidden, so the
	# grade letters never slide under the Mods box's labels.
	_rows_wrap = MarginContainer.new()
	_rows_wrap.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows_wrap.mouse_filter = MOUSE_FILTER_IGNORE
	_scroll.add_child(_rows_wrap)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows.add_constant_override("separation", 4)
	_rows_wrap.add_child(_rows)
	var vbar = _scroll.get_v_scrollbar()
	if vbar != null:
		vbar.connect("visibility_changed", self, "_on_vbar_visibility")
	_on_vbar_visibility()

	_empty = Label.new()
	_empty.align = Label.ALIGN_CENTER
	_empty.autowrap = true
	_empty.add_font_override("font", _f_name)
	_empty.add_color_override("font_color", C_DIM)
	_empty.size_flags_horizontal = SIZE_EXPAND_FILL
	_rows.add_child(_empty)

	connect("resized", self, "_layout")
	_layout()

	# Same switch, same spot, above the Best Attempt box.
	if is_instance_valid(end_info):
		var sw = _make_switch()
		sw.rect_position = Vector2(PAD_L, HEAD_Y)
		end_info.add_child(sw)
		end_info.connect("visibility_changed", self, "_on_end_info_visibility")

	Rhythia.connect("selected_song_changed", self, "_on_song_changed")
	set_process(false)

	# Coming back from a song: show the result box first, the attempt is
	# already in the history for when you switch.
	if ScoreHistory.take_just_ended() or Rhythia.just_ended_song:
		_set_mode(MODE_BEST, false)
	else:
		_set_mode(mode, false)

func _layout():
	if _scroll == null: return
	_head.rect_position = Vector2(PAD_L, HEAD_Y)
	_head.rect_size = Vector2(0, SWITCH_H)
	var w = max(rect_size.x - PAD_L - PAD_R, 120)
	var h = rect_size.y
	var vp = get_viewport()
	if vp != null:
		var bottom = vp.get_visible_rect().size.y - BOTTOM_CLEAR
		h = min(h, bottom - get_global_rect().position.y)
	_scroll.rect_position = Vector2(PAD_L, 0)
	_scroll.rect_size = Vector2(w, max(h, 120))

func _on_vbar_visibility():
	if _rows_wrap == null: return
	var vbar = _scroll.get_v_scrollbar()
	var bar_w = 0.0
	if vbar != null and not vbar.visible:
		bar_w = max(vbar.get_combined_minimum_size().x, 10)
	_rows_wrap.add_constant_override("margin_right", int(bar_w) + 2)

func _make_switch() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 2)
	var group := ButtonGroup.new()
	var pair := []
	for i in range(2):
		var b := Button.new()
		b.text = "Best" if i == MODE_BEST else "History"
		b.toggle_mode = true
		b.group = group
		b.focus_mode = FOCUS_NONE
		b.rect_min_size = Vector2(58 if i == MODE_BEST else 76, SWITCH_H)
		b.add_font_override("font", _f_tab)
		b.connect("pressed", self, "_set_mode", [i, true])
		h.add_child(b)
		pair.append(b)
	_switches.append(pair)
	return h

func _set_mode(m: int, save: bool = true):
	mode = m
	for pair in _switches:
		for i in range(pair.size()):
			if is_instance_valid(pair[i]):
				pair[i].pressed = (i == mode)
				pair[i].modulate = Color(1, 1, 1, 1) if i == mode else Color(1, 1, 1, 0.5)
	if is_instance_valid(end_info):
		var want_end = (mode == MODE_BEST)
		if end_info.visible != want_end:
			end_info.visible = want_end
	visible = (mode == MODE_HISTORY)
	if mode == MODE_HISTORY:
		_refresh()
		call_deferred("_layout")
	if save:
		_save_prefs()

# SongInfoScreen / EndInfo turn the PB box on whenever they update; keep it
# hidden while History is showing.
func _on_end_info_visibility():
	if mode == MODE_HISTORY and is_instance_valid(end_info) and end_info.visible:
		end_info.call_deferred("hide")

func _on_song_changed(_s = null):
	_dirty = true
	if mode == MODE_HISTORY:
		_refresh()

func _on_hide_failed(on: bool):
	hide_failed = on
	_save_prefs()
	_rebuild()

func _refresh():
	var song = Rhythia.selected_song
	var id := String(song.id) if song != null else ""
	if id != _loaded_id or _dirty:
		_loaded_id = id
		_entries = ScoreHistory.load_entries(id)
		_dirty = false
	_rebuild()

# Rows not built yet: [entry, rank]. The first screenful is built right away,
# the rest a few per frame so a long history doesn't hitch map selection.
var _pending: Array = []
const ROWS_NOW = 8
const ROWS_PER_FRAME = 6

func _rebuild():
	if _rows == null: return
	for c in _rows.get_children():
		if c != _empty:
			_rows.remove_child(c)
			c.queue_free()
	_pending.clear()
	var rank := 0
	for e in _entries:
		rank += 1
		if hide_failed and String(e.get("r", "")) != ScoreHistory.RESULT_PASS:
			continue
		_pending.append([e, rank])
	var shown := _pending.size()
	_empty.visible = shown == 0
	if shown == 0:
		if _entries.empty():
			_empty.text = "\nNo attempts yet.\nPlay this map and your scores show up here."
		else:
			_empty.text = "\nNo passes yet.\n(%d failed attempt%s hidden)" % [_entries.size(), "" if _entries.size() == 1 else "s"]
	_build_some(ROWS_NOW)
	_scroll.scroll_vertical = 0

func _build_some(n: int):
	var show_fc: bool = Rhythia.show_fc_grade
	while n > 0 and not _pending.empty():
		var p = _pending.pop_front()
		_rows.add_child(_make_row(p[0], p[1], show_fc))
		n -= 1
	set_process(not _pending.empty())

func _process(_d):
	if _pending.empty():
		set_process(false)
		return
	_build_some(ROWS_PER_FRAME)

func _label(text: String, font: Font, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", font)
	l.add_color_override("font_color", col)
	l.valign = Label.VALIGN_CENTER
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l

static func _time_str(ms: float) -> String:
	var s = max(floor(ms / 1000.0), 0)
	return "%d:%02d" % [floor(s / 60), fmod(s, 60)]

# Compact age ("now", "5m", "3h", "2d", "4w", "6mo", "1y"); the tooltip has the date.
static func _ago(ts: int) -> String:
	if ts <= 0: return ""
	var d = OS.get_unix_time() - ts
	if d < 60: return "now"
	if d < 3600: return "%dm" % int(d / 60)
	if d < 86400: return "%dh" % int(d / 3600)
	if d < 604800: return "%dd" % int(d / 86400)
	if d < 2629800: return "%dw" % int(d / 604800)
	if d < 31557600: return "%dmo" % int(d / 2629800)
	return "%dy" % int(d / 31557600)

static func _speed_str(spd: float) -> String:
	var t := "%.2f" % spd
	while t.ends_with("0"): t = t.substr(0, t.length() - 1)
	if t.ends_with("."): t = t.substr(0, t.length() - 1)
	return t + "x"

static func _date_str(ts: int) -> String:
	if ts <= 0: return ""
	var dt = OS.get_datetime_from_unix_time(ts)
	return "%d-%02d-%02d %02d:%02d" % [dt.year, dt.month, dt.day, dt.hour, dt.minute]

func _make_row(e: Dictionary, rank: int, show_fc: bool) -> Control:
	var result := String(e.get("r", ""))
	var passed := result == ScoreHistory.RESULT_PASS
	var misses := int(e.get("m", 0))
	var acc := ScoreHistory.accuracy(e)
	var top := rank <= 3
	var rank_col: Color = RANK_COLORS[rank - 1] if top else C_DIM

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = SIZE_EXPAND_FILL
	panel.mouse_filter = MOUSE_FILTER_PASS
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.07, 0.11, 0.92)
	if top:
		sb.bg_color = sb.bg_color.linear_interpolate(rank_col, 0.12)
		sb.border_color = rank_col
		sb.border_width_left = 3
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	panel.add_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_constant_override("separation", 4)
	h.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(h)

	var rl := _label("#%d" % rank, _f_rank, rank_col)
	rl.rect_min_size = Vector2(24, 0)
	h.add_child(rl)

	# Avatar: your initial in a round badge.
	var nm := String(e.get("nm", "You"))
	var av := Panel.new()
	av.rect_min_size = Vector2(22, 22)
	av.size_flags_vertical = SIZE_SHRINK_CENTER
	av.mouse_filter = MOUSE_FILTER_IGNORE
	var avs := StyleBoxFlat.new()
	avs.bg_color = C_LILAC
	avs.set_corner_radius_all(11)
	av.add_stylebox_override("panel", avs)
	var ini := _label(nm.substr(0, 1).to_upper() if nm != "" else "?", _f_avatar, Color(0.12, 0.08, 0.16))
	ini.align = Label.ALIGN_CENTER
	ini.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	av.add_child(ini)
	h.add_child(av)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_constant_override("separation", -2)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	h.add_child(v)

	var l1 := HBoxContainer.new()
	l1.mouse_filter = MOUSE_FILTER_IGNORE
	var name_l := _label(nm, _f_name, C_TEXT)
	name_l.clip_text = true
	name_l.size_flags_horizontal = SIZE_EXPAND_FILL
	l1.add_child(name_l)
	l1.add_child(_label("%.2f%%" % (acc * 100.0), _f_name, C_ACCENT))
	v.add_child(l1)

	# Line 2: how it ended, and when.
	var status := ""
	var status_col := C_DIM
	if passed:
		if misses == 0:
			status = "Full combo"
			status_col = Color("#fa6afa")
		else:
			status = "Passed"
			status_col = Color("#6ff1ff")
	else:
		var verb := "Gave up at " if result == ScoreHistory.RESULT_GIVEUP else "Failed at "
		status = verb + _time_str(float(e.get("p", 0)))
		status_col = Color("#ff8282")
	var l2 := HBoxContainer.new()
	l2.mouse_filter = MOUSE_FILTER_IGNORE
	var st_l := _label(status, _f_small, status_col)
	st_l.clip_text = true
	st_l.size_flags_horizontal = SIZE_EXPAND_FILL
	l2.add_child(st_l)
	v.add_child(l2)

	# Line 3: misses, speed, mods.
	var extra := PoolStringArray()
	extra.append("%d miss%s" % [misses, "" if misses == 1 else "es"])
	var spd := float(e.get("s", 1.0))
	if abs(spd - 1.0) > 0.001:
		extra.append(_speed_str(spd))
	var mods = e.get("mods", [])
	var mods_txt := ""
	if typeof(mods) == TYPE_ARRAY and mods.size() > 0:
		mods_txt = PoolStringArray(mods).join(" ")
		extra.append(mods_txt)
	if int(e.get("so", 0)) > 0:
		extra.append("from " + _time_str(float(e.get("so", 0))))
	var l3 := _label(extra.join(" · "), _f_small, C_DIM)
	l3.clip_text = true
	v.add_child(l3)

	var g = ScoreHistory.grade_for(acc, show_fc)
	var gl := _label(g[0], _f_grade, g[1])
	gl.align = Label.ALIGN_RIGHT
	gl.rect_min_size = Vector2(28, 0)
	h.add_child(gl)

	panel.hint_tooltip = "%s  %s\n%d / %d notes hit, max combo %d%s%s" % [
		nm, _date_str(int(e.get("t", 0))), int(e.get("h", 0)), int(e.get("n", 0)), int(e.get("c", 0)),
		(", %d pause%s" % [int(e.get("pz", 0)), "" if int(e.get("pz", 0)) == 1 else "s"]) if int(e.get("pz", 0)) > 0 else "",
		("\nMods: " + mods_txt) if mods_txt != "" else ""
	]
	return panel

func _load_prefs():
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) == OK:
		mode = MODE_HISTORY if int(cfg.get_value("ui", "mode", MODE_BEST)) == MODE_HISTORY else MODE_BEST
		hide_failed = bool(cfg.get_value("ui", "hide_failed", false))

func _save_prefs():
	var dir := Directory.new()
	if not dir.dir_exists(ScoreHistory.DIR):
		dir.make_dir_recursive(ScoreHistory.DIR)
	var cfg := ConfigFile.new()
	cfg.set_value("ui", "mode", mode)
	cfg.set_value("ui", "hide_failed", hide_failed)
	cfg.save(PREFS_PATH)

func _exit_tree():
	if Rhythia.is_connected("selected_song_changed", self, "_on_song_changed"):
		Rhythia.disconnect("selected_song_changed", self, "_on_song_changed")

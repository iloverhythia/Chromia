extends Node

# Chat lines from players you blocked, folded away like Discord does:
#   "1 blocked message   Show"
# A run of them in a row is one fold ("3 blocked messages"). Show opens the
# run (and keeps it open when the chat is drawn again); Hide folds it back.
#   BlockedChat.place(box, line, line_id, lobby_manager)
#     adds a chat line (any Control) to a chat box (a VBoxContainer), folded
#     when its writer is blocked
#   BlockedChat.trim(box, max_lines)
#     drops the oldest lines past max_lines (folds don't count)
# (The Spectate window's chat is one RichTextLabel: it folds with
# BlockedChat.rtl_fold, below.)

const DIM := Color(0.6, 0.57, 0.68)
const META_FOLD := "blocked_fold"
const META_MID := "blocked_mid"
const META_SHOW := "chromia_showblocked:"

static func place(box: Container, line: Control, mid: String, lm) -> void:
	var blocked: bool = lm != null and lm.has_method("is_blocked_chat") and lm.is_blocked_chat(mid)
	if not blocked:
		box.add_child(line)
		return
	line.set_meta(META_MID, mid)
	var fold: Control = null
	var n := box.get_child_count()
	if n > 0:
		var last = box.get_child(n - 1)
		if last.has_meta(META_FOLD) and is_instance_valid(last.get_meta(META_FOLD)):
			fold = last.get_meta(META_FOLD) # (the run goes on)
	if fold == null:
		fold = _make_fold(lm)
		box.add_child(fold)
	line.set_meta(META_FOLD, fold)
	var lines: Array = fold.get_meta("lines")
	lines.append(line)
	fold.set_meta("lines", lines)
	box.add_child(line)
	var open: bool = lm.shown_blocked.has(mid) if "shown_blocked" in lm else false
	if open:
		fold.set_meta("open", true)
	_draw_fold(fold)

static func _make_fold(lm) -> Control:
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 8)
	row.set_meta("lines", [])
	row.set_meta("open", false)
	var label := Label.new()
	label.name = "Count"
	label.add_color_override("font_color", DIM)
	row.add_child(label)
	var b := LinkButton.new()
	b.name = "Toggle"
	b.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_color_override("font_color", Color(0.85, 0.82, 0.92))
	b.add_color_override("font_color_hover", Color(1, 1, 1))
	row.add_child(b)
	var h = load("res://scripts/ui/BlockedChat.gd").new()
	h.name = "Fold"
	h._fold = row
	h._lm = lm
	row.add_child(h)
	b.connect("pressed", h, "_on_toggle")
	return row

static func _draw_fold(fold: Control):
	var lines: Array = fold.get_meta("lines")
	var live := []
	for l in lines:
		if is_instance_valid(l):
			live.append(l)
	var open: bool = bool(fold.get_meta("open"))
	var n := live.size()
	fold.get_node("Count").text = "%d blocked message%s" % [n, "" if n == 1 else "s"]
	fold.get_node("Toggle").text = "Hide" if open else "Show"
	for l in live:
		l.visible = open
		l.modulate.a = 0.7 if open else 1.0
	fold.visible = n > 0

var _fold: Control
var _lm

func _on_toggle():
	if not is_instance_valid(_fold):
		return
	var open: bool = not bool(_fold.get_meta("open"))
	_fold.set_meta("open", open)
	if is_instance_valid(_lm) and "shown_blocked" in _lm:
		for l in _fold.get_meta("lines"):
			if is_instance_valid(l) and l.has_meta(META_MID):
				if open:
					_lm.shown_blocked[String(l.get_meta(META_MID))] = true
				else:
					_lm.shown_blocked.erase(String(l.get_meta(META_MID)))
	_draw_fold(_fold)

# Drops the oldest lines past max_lines. (Removed from the box right away:
# queue_free alone leaves them counted until the frame ends.)
static func trim(box: Container, max_lines: int):
	var lines := 0
	for c in box.get_children():
		if not c.has_meta("lines"):
			lines += 1
	while lines > max_lines and box.get_child_count() > 0:
		var c = box.get_child(0)
		if not c.has_meta("lines"):
			lines -= 1
		box.remove_child(c)
		c.queue_free()
	# (a fold whose lines all went)
	while box.get_child_count() > 0 and box.get_child(0).has_meta("lines"):
		var f = box.get_child(0)
		box.remove_child(f)
		f.queue_free()

# --- one RichTextLabel (the Spectate window's chat) ------------------------------
# rtl_fold(rtl, mids): writes the "N blocked messages  Show" line for a run of
# blocked lines (the chat box draws the run itself only when it's open:
# rtl_open). Clicking Show / Hide calls redraw_target.redraw_method().
static func rtl_open(lm, mids: Array) -> bool:
	if lm == null or not ("shown_blocked" in lm):
		return false
	for m in mids:
		if not lm.shown_blocked.has(String(m)):
			return false
	return true

static func rtl_fold(rtl: RichTextLabel, mids: Array, lm, redraw_target: Object, redraw_method: String):
	if not rtl.has_meta("_blocked_hook"):
		rtl.set_meta("_blocked_hook", true)
		var h = load("res://scripts/ui/BlockedChat.gd").new()
		h.name = "BlockedFold"
		h._lm = lm
		h._target = redraw_target
		h._method = redraw_method
		rtl.add_child(h)
		rtl.connect("meta_clicked", h, "_on_rtl_meta")
	var open: bool = rtl_open(lm, mids)
	var n := mids.size()
	rtl.push_color(DIM)
	rtl.add_text("%d blocked message%s   " % [n, "" if n == 1 else "s"])
	rtl.pop()
	rtl.push_meta(META_SHOW + PoolStringArray(mids).join(","))
	rtl.push_color(Color(0.85, 0.82, 0.92))
	rtl.add_text("Hide" if open else "Show")
	rtl.pop()
	rtl.pop()

var _target: Object
var _method := ""

func _on_rtl_meta(meta):
	var m := String(meta)
	if not m.begins_with(META_SHOW) or not is_instance_valid(_lm):
		return
	var mids: Array = Array(m.substr(META_SHOW.length()).split(",", false))
	var open: bool = not rtl_open(_lm, mids)
	for x in mids:
		if open:
			_lm.shown_blocked[String(x)] = true
		else:
			_lm.shown_blocked.erase(String(x))
	if is_instance_valid(_target) and _target.has_method(_method):
		_target.call(_method)

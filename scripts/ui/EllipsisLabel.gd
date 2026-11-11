extends Label
# A one-line label that is never cut off in the middle of a letter: when its
# text doesn't fit the room it gets, it ends in "…" and the whole text is its
# tooltip. Set `full` (not `text`).

var full := "" setget set_full
var tip := "" # (a tooltip of its own, shown when the text fits)

func _init():
	clip_text = true # (takes the room it's given instead of asking for the text's width)
	valign = VALIGN_CENTER

func set_full(v: String):
	full = v
	_fit()

func _notification(what):
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED or what == NOTIFICATION_READY:
		_fit()

static func shorten(f: Font, s: String, width: float) -> String:
	if f == null or width <= 0.0 or f.get_string_size(s).x <= width:
		return s
	var lo := 0
	var hi := s.length()
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if f.get_string_size(s.left(mid).strip_edges(false, true) + "…").x <= width:
			lo = mid
		else:
			hi = mid - 1
	return s.left(lo).strip_edges(false, true) + "…"

func _fit():
	var t := shorten(get_font("font"), full, rect_size.x)
	if text != t:
		text = t
	var cut := t != full
	hint_tooltip = full if cut else tip
	mouse_filter = MOUSE_FILTER_PASS if (cut or tip != "") else MOUSE_FILTER_IGNORE

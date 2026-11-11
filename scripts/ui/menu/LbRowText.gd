extends Container
# The text of a leaderboard row (Profile > Leaderboard): the name with their
# tag and "Ranked Team" on the first line, level and ranked plays on the
# second. It fits whatever width it gets and never cuts a word in half:
#  - "Ranked Team" drops to the second line when the first has no room,
#  - the details use a shorter wording when theirs doesn't fit,
#  - only then is the name (or the details) ended with "…".

const EllipsisLabel = preload("res://scripts/ui/EllipsisLabel.gd")
const GAP := 6.0
const LINE_GAP := 1.0

var name_full := ""
var details := [] # the second line, longest wording first
var name_label: Label
var tag: Control = null
var team: Label = null
var detail_label: Label

func setup(S, nm: String, tag_node: Control, is_team: bool, team_col: Color, detail_variants: Array):
	mouse_filter = MOUSE_FILTER_IGNORE
	name_full = nm
	details = detail_variants
	name_label = S.label(nm, S.f_bold, S.TEXT)
	name_label.clip_text = true
	name_label.valign = Label.VALIGN_CENTER
	add_child(name_label)
	tag = tag_node
	if tag != null:
		add_child(tag)
	if is_team:
		team = S.label("Ranked Team", S.f_small, team_col)
		team.valign = Label.VALIGN_CENTER
		add_child(team)
	detail_label = S.label(String(details[0]) if details.size() > 0 else "", S.f_small, S.DIM)
	detail_label.clip_text = true
	detail_label.valign = Label.VALIGN_CENTER
	add_child(detail_label)

func _line_heights() -> Array:
	var h1: float = name_label.get_font("font").get_height()
	if tag != null:
		h1 = max(h1, tag.get_combined_minimum_size().y)
	var h2: float = detail_label.get_font("font").get_height()
	return [h1, h2]

func _get_minimum_size() -> Vector2:
	if name_label == null:
		return Vector2.ZERO
	var h := _line_heights()
	return Vector2(0, h[0] + LINE_GAP + h[1])

func _notification(what):
	if what == NOTIFICATION_SORT_CHILDREN and name_label != null:
		_fit()

func _fit():
	var w := rect_size.x
	var hs := _line_heights()
	var nf: Font = name_label.get_font("font")
	var df: Font = detail_label.get_font("font")
	var name_w: float = nf.get_string_size(name_full).x
	var tag_w: float = (tag.get_combined_minimum_size().x + GAP) if tag != null else 0.0
	var team_w: float = (team.get_combined_minimum_size().x + GAP) if team != null else 0.0

	# first line: name, tag, and Ranked Team when all three fit
	var team_up: bool = team != null and name_w + tag_w + team_w <= w
	var name_room: float = max(w - tag_w - (team_w if team_up else 0.0), 24.0)
	var shown: String = EllipsisLabel.shorten(nf, name_full, name_room)
	if name_label.text != shown:
		name_label.text = shown
	var x: float = min(nf.get_string_size(shown).x, name_room)
	fit_child_in_rect(name_label, Rect2(0, 0, x, hs[0]))
	if tag != null:
		var ts: Vector2 = tag.get_combined_minimum_size()
		fit_child_in_rect(tag, Rect2(x + GAP, (hs[0] - ts.y) / 2.0, ts.x, ts.y))
		x += GAP + ts.x
	if team_up:
		var s: Vector2 = team.get_combined_minimum_size()
		fit_child_in_rect(team, Rect2(x + GAP, 0, s.x, hs[0]))

	# second line: Ranked Team when it didn't fit above, then the details
	var y: float = hs[0] + LINE_GAP
	var x2 := 0.0
	if team != null and not team_up:
		var s2: Vector2 = team.get_combined_minimum_size()
		fit_child_in_rect(team, Rect2(0, y, min(s2.x, w), hs[1]))
		x2 = s2.x + GAP
	var room: float = max(w - x2, 0.0)
	var text := ""
	for d in details:
		text = String(d)
		if df.get_string_size(text).x <= room:
			break
	if text != "" and df.get_string_size(text).x > room:
		text = EllipsisLabel.shorten(df, text, room) if room > 30.0 else ""
	if detail_label.text != text:
		detail_label.text = text
	fit_child_in_rect(detail_label, Rect2(x2, y, room, hs[1]))

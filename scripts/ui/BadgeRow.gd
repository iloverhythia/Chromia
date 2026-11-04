extends HFlowContainer

# A player's badges as small chips (the in-game profile, Spectate > View stats),
# from the server's profile (compat.js): the Map of the Day badge (its tier by
# how many days' maps they completed, as the website names them), Ranker, and
# the badges the admins gave (name, colours, description on hover).

const MOTD_TIERS = [[100, "Prismatic"], [60, "Supernova"], [30, "Eclipse"], [15, "Golden Sun"], [5, "Sunshine"], [1, "Sunrise"]]

var _font: Font

static func make(p: Dictionary, font: Font, k: float = 1.0) -> Control:
	var row = load("res://scripts/ui/BadgeRow.gd").new()
	row._font = font
	row.add_constant_override("hseparation", int(6 * k))
	row.add_constant_override("vseparation", int(4 * k))
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var motd := int(p.get("motd_count", 0))
	if motd > 0:
		var tier := "Sunrise"
		for t in MOTD_TIERS:
			if motd >= int(t[0]):
				tier = t[1]
				break
		row._chip("%s  x%d" % [tier, motd], Color(1, 0.86, 0.2), "Map of the Day: completed %d map%s of the day" % [motd, "" if motd == 1 else "s"], k)
	if bool(p.get("is_ranker", false)):
		row._chip("Ranker", Color(0.55, 0.85, 1.0), "Ranks maps", k)
	var badges = p.get("badges", [])
	if badges is Array:
		for b in badges:
			if not (b is Dictionary):
				continue
			var cols = b.get("colors", [])
			var col := Color(0.8, 0.7, 1.0)
			if cols is Array and cols.size() > 0 and String(cols[0]).is_valid_html_color():
				col = Color(String(cols[0]))
			row._chip(Globals.s(b.get("name", "Badge")), col, Globals.s(b.get("desc", "")), k)
	row.visible = row.get_child_count() > 0
	return row

func _chip(text: String, col: Color, tip: String, k: float):
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(col.r * 0.18 + 0.05, col.g * 0.18 + 0.05, col.b * 0.18 + 0.06, 0.95)
	sb.border_color = Color(col.r, col.g, col.b, 0.85)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(int(6 * k))
	sb.content_margin_left = 8 * k
	sb.content_margin_right = 8 * k
	sb.content_margin_top = 2 * k
	sb.content_margin_bottom = 2 * k
	pc.add_stylebox_override("panel", sb)
	pc.hint_tooltip = tip
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := HBoxContainer.new()
	h.add_constant_override("separation", int(5 * k))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(h)
	var dot := ColorRect.new()
	dot.color = col
	dot.rect_min_size = Vector2(7, 7) * k
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(dot)
	var l := Label.new()
	l.text = text
	if _font != null:
		l.add_font_override("font", _font)
	l.add_color_override("font_color", col.lightened(0.35))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(l)
	add_child(pc)

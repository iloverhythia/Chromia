extends Reference

# Trophies: how many ranked maps a player is #1 on (the server works it out:
# savia_web src/trophies.js). The little trophy drawn next to the number is
# the emoji pack's (Emoji.gd, U+1F3C6).

const GOLD := Color("#f6c453")

static func texture() -> Texture:
	return load("res://scripts/ui/Emoji.gd")._texture("1f3c6")

# the trophy, px tall
static func icon(px: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = texture()
	t.expand = true
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.rect_min_size = Vector2(px, px)
	t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

# the trophy and the count side by side ("🏆 12")
static func row(n: int, font: Font, col: Color = GOLD, px: float = 0.0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.hint_tooltip = "%s trophies: ranked maps where they have the #1 pass" % Globals.comma_sep(n)
	var size: float = px if px > 0.0 else (float(font.get_height()) * 0.85 if font != null else 16.0)
	h.add_child(icon(size))
	var l := Label.new()
	l.text = Globals.comma_sep(n)
	if font != null:
		l.add_font_override("font", font)
	l.add_color_override("font_color", col)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(l)
	return h

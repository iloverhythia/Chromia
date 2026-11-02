extends Reference

# Legacy UI (editor setting "legacyUI"): the editor in Sound Space Quantum
# Editor Plus's own look instead of Chromia's. SSQE's fonts (Source Sans Pro
# Bold for everything, SquareFont for the title), its dark controls (fill
# 26,26,26 with a 2 px 52,52,52 outline, round checkboxes, magenta / cyan
# sliders, boxes with grey outlines and magenta text) and its colours
# (cyan / magenta / pink-red / grey / amber) on a solid 30,30,30 background.
# Values from SSQE+'s NewGUI/Base/ControlStyle.cs, GuiButton/GuiCheckbox/
# GuiSlider/GuiTextbox.cs and Preferences/AllSettings.cs.

const FONT_MAIN := "res://assets/font/SSQE/main.ttf"         # Source Sans Pro Bold
const FONT_SEMIBOLD := "res://assets/font/SSQE/semibold.ttf" # Source Sans Pro Semibold
const FONT_SQUARE := "res://assets/font/SSQE/square.ttf"     # SquareFont (the title)

const BG := Color8(30, 30, 30)
const FILL := Color8(26, 26, 26)
const OUTLINE := Color8(52, 52, 52)
const CHECK_FILL := Color8(13, 13, 13)
const BOX_OUTLINE := Color8(128, 128, 128)
const UNCOLORED := Color8(75, 75, 75)

# SSQE's own colours, used in Legacy UI where a colour is still Chromia's default
const SSQE_COLORS := {
	"color1": [0, 255, 200], "color2": [255, 0, 255], "color3": [255, 0, 100],
	"color4": [90, 90, 90], "color5": [255, 204, 0],
}
const CHROMIA_COLORS := {
	"color1": [195, 166, 204], "color2": [255, 193, 245], "color3": [214, 120, 196],
	"color4": [90, 90, 90], "color5": [255, 204, 0],
}

static func on(s: Dictionary) -> bool:
	return bool(s.get("legacyUI", false))

# a colour setting as Legacy UI shows it: SSQE's default where the setting is
# still Chromia's default (a colour you picked stays yours)
static func color_value(s: Dictionary, key: String) -> Array:
	var c = s.get(key, [255, 255, 255])
	if on(s) and SSQE_COLORS.has(key) and c is Array and c.size() >= 3 and int(c[0]) == CHROMIA_COLORS[key][0] and int(c[1]) == CHROMIA_COLORS[key][1] and int(c[2]) == CHROMIA_COLORS[key][2]:
		return SSQE_COLORS[key]
	return c

static func box(bg: Color, border: Color = OUTLINE, bw := 2, radius := 5) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(bw)
	b.set_corner_radius_all(radius)
	b.corner_detail = 8
	b.anti_aliasing = true
	b.content_margin_left = 6
	b.content_margin_right = 6
	b.content_margin_top = 2
	b.content_margin_bottom = 2
	return b

static func _mix(c: Color, white: float) -> Color:
	return Color(lerp(c.r, 1.0, white), lerp(c.g, 1.0, white), lerp(c.b, 1.0, white), c.a)

# the Theme every Legacy UI control uses (font sizes are set per control)
static func make_theme(s: Dictionary) -> Theme:
	var t := Theme.new()
	var c1: Color = col(s, "color1")
	var c2: Color = col(s, "color2")
	var white := Color(1, 1, 1)
	# buttons: GuiButton (hover mask white x 0.05, pressed + 0.04)
	for cls in ["Button", "OptionButton", "MenuButton"]:
		var sq: bool = cls == "OptionButton" # (SSQE's dropdowns have square corners)
		t.set_stylebox("normal", cls, box(FILL, OUTLINE, 2, 0 if sq else 5))
		t.set_stylebox("hover", cls, box(_mix(FILL, 0.05), OUTLINE, 2, 0 if sq else 5))
		t.set_stylebox("pressed", cls, box(_mix(FILL, 0.09), OUTLINE, 2, 0 if sq else 5))
		t.set_stylebox("disabled", cls, box(FILL, Color8(40, 40, 40), 2, 0 if sq else 5))
		t.set_stylebox("focus", cls, StyleBoxEmpty.new())
		for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_focus", "font_color_hover_pressed"]:
			t.set_color(k, cls, white)
		t.set_color("font_color_disabled", cls, Color(1, 1, 1, 0.35))
	# checkboxes: the box is an icon (checkbox_icons); the label is color1
	for k in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		t.set_stylebox(k, "CheckBox", StyleBoxEmpty.new())
	for k in ["font_color", "font_color_hover", "font_color_pressed", "font_color_hover_pressed", "font_color_focus"]:
		t.set_color(k, "CheckBox", c1)
	# text boxes: GuiTextbox (Textbox_Colored): magenta text and caret
	t.set_stylebox("normal", "LineEdit", box(FILL, BOX_OUTLINE, 2, 5))
	t.set_stylebox("focus", "LineEdit", box(FILL, _mix(BOX_OUTLINE, 0.3), 2, 5))
	t.set_stylebox("read_only", "LineEdit", box(FILL, OUTLINE, 2, 5))
	t.set_color("font_color", "LineEdit", c2)
	t.set_color("cursor_color", "LineEdit", c2)
	t.set_color("font_color_uneditable", "LineEdit", Color(c2.r, c2.g, c2.b, 0.6))
	t.set_color("selection_color", "LineEdit", Color(c2.r, c2.g, c2.b, 0.3))
	# a dropdown's list: the same square buttons
	t.set_stylebox("panel", "PopupMenu", box(FILL, OUTLINE, 2, 0))
	t.set_stylebox("hover", "PopupMenu", box(_mix(FILL, 0.08), OUTLINE, 0, 0))
	t.set_color("font_color", "PopupMenu", white)
	t.set_color("font_color_hover", "PopupMenu", white)
	t.set_color("font_color", "Label", white)
	# scrollbars
	for cls in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", cls, box(Color8(20, 20, 20), Color8(20, 20, 20), 0, 2))
		t.set_stylebox("grabber", cls, box(UNCOLORED, UNCOLORED, 0, 2))
		t.set_stylebox("grabber_highlight", cls, box(_mix(UNCOLORED, 0.2), UNCOLORED, 0, 2))
		t.set_stylebox("grabber_pressed", cls, box(_mix(UNCOLORED, 0.3), UNCOLORED, 0, 2))
	t.default_font = font(FONT_MAIN, 20)
	return t

static func col(s: Dictionary, key: String, a := 1.0) -> Color:
	var c: Array = color_value(s, key)
	return Color(c[0] / 255.0, c[1] / 255.0, c[2] / 255.0, a)

static func font(path: String, px: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(path)
	f.size = int(max(6, px))
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return f

# GuiCheckbox's box at `px` pixels: a circle (corner radius 0.5) filled 13,13,13
# with a 2 px 52,52,52 outline; checked, a rounded square at 75 % in `check`
static func checkbox_icons(px: int, check: Color) -> Array:
	px = int(clamp(px, 8, 200))
	var off := _circle_img(px, false, check)
	var onn := _circle_img(px, true, check)
	var t0 := ImageTexture.new()
	t0.create_from_image(off, Texture.FLAG_FILTER)
	var t1 := ImageTexture.new()
	t1.create_from_image(onn, Texture.FLAG_FILTER)
	return [t0, t1]

static func _circle_img(px: int, checked: bool, check: Color) -> Image:
	var ss := 4 # supersampled
	var n := px * ss
	var img := Image.new()
	img.create(px, px, false, Image.FORMAT_RGBA8)
	img.lock()
	var r := n / 2.0
	var bw := 2.0 * ss
	var inner_r := r * 0.75
	for y in px:
		for x in px:
			var acc := Color(0, 0, 0, 0)
			var hits := 0.0
			var cr := 0.0
			var cg := 0.0
			var cb := 0.0
			for sy in ss:
				for sx in ss:
					var px_: float = x * ss + sx + 0.5 - r
					var py_: float = y * ss + sy + 0.5 - r
					var d: float = sqrt(px_ * px_ + py_ * py_)
					if d > r:
						continue
					var c: Color = CHECK_FILL
					if d > r - bw:
						c = OUTLINE
					if checked and d <= inner_r - bw * 0.25:
						c = check
					cr += c.r
					cg += c.g
					cb += c.b
					hits += 1.0
			if hits > 0:
				img.set_pixel(x, y, Color(cr / hits, cg / hits, cb / hits, hits / float(ss * ss)))
	img.unlock()
	return img

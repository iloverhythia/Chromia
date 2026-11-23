extends ReferenceRect

# Inventory & Misc (its own button on the sidebar): what you have and what you
# look like, laid out like Settings: the title, a list of tabs down the left,
# the open tab on the right.
#
#   Cards           the card your player card shows (scripts/ui/CardsMenu.gd)
#   Frames          the frame round your picture (scripts/ui/FramesMenu.gd)
#   Codes           secret codes that unlock things
#   Avatar Creator  your avatar's colours and items (scenes/menu/AvatarEditor.tscn)
#
# Cards and Frames were buttons on the profile page that opened windows, the
# code box was in the Cards window, and the avatar editor was a screen of its
# own behind Settings > Replays & Misc > Experimental.
#
# Sidebar.gd adds the page (_add_extra_pages). open_tab("Codes") from anywhere
# opens it on a tab.

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")
const TABS := ["Cards", "Frames", "Codes", "Avatar Creator"]
const CATS_W := 198.0

var S
var lm
var _header: VBoxContainer
var _cats: VBoxContainer
var _body: Control
var _cat_btns := []
var _panels := [] # one per tab (Control)
var _tab := 0
var _built := false
# Codes
var _code: LineEdit
var _code_msg: Label
var _code_list: VBoxContainer
# Avatar Creator
var _avatar_holder: Control
var _avatar_ed: Node = null

func _ready():
	S = OnlineStyle.new()
	lm = get_node_or_null("/root/LobbyManager")
	if Engine.has_meta("inventory_tab"):
		_tab = int(clamp(int(Engine.get_meta("inventory_tab")), 0, TABS.size() - 1))
	connect("visibility_changed", self, "_on_shown")
	connect("resized", self, "_fit")
	_on_shown()

# (built the first time the page is opened: nothing of it costs anything before)
func _on_shown():
	if not is_visible_in_tree():
		_drop_avatar()
		return
	if not _built:
		_built = true
		_build()
	_show_tab(_tab)

func open_tab(title: String):
	var i := TABS.find(title)
	if i < 0:
		return
	_tab = i
	var sidebar = get_node_or_null("../../Sidebar")
	if sidebar != null and sidebar.has_method("press_page") and not visible:
		sidebar.press_page(self)
	elif _built:
		_show_tab(i)

func _build():
	var bg := Panel.new()
	bg.name = "Bg"
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	bg.add_stylebox_override("panel", OnlineStyle.flat(S.WINDOW_BG, 0, Color(0, 0, 0, 0), 0))
	add_child(bg)

	_header = VBoxContainer.new()
	_header.name = "Header"
	_header.anchor_right = 1.0
	_header.margin_left = 22
	_header.margin_right = -22
	_header.margin_top = 12
	_header.add_constant_override("separation", 8)
	add_child(_header)
	_header.add_child(S.title("Inventory & Misc"))
	_header.add_child(S.rule())
	_header.connect("resized", self, "_fit")

	_cats = VBoxContainer.new()
	_cats.name = "Tabs"
	_cats.add_constant_override("separation", 3)
	add_child(_cats)
	for i in range(TABS.size()):
		var b := _cat_button(TABS[i], i)
		_cats.add_child(b)
		_cat_btns.append(b)

	_body = Control.new()
	_body.name = "Body"
	add_child(_body)

	var cards = load("res://scripts/ui/CardsMenu.gd").new()
	cards.name = "Cards"
	var frames = load("res://scripts/ui/FramesMenu.gd").new()
	frames.name = "Frames"
	_avatar_holder = Control.new()
	_avatar_holder.name = "AvatarCreator"
	_avatar_holder.rect_clip_content = true
	for p in [cards, frames, _build_codes(), _avatar_holder]:
		p.visible = false
		p.anchor_right = 1.0
		p.anchor_bottom = 1.0
		_body.add_child(p)
		_panels.append(p)
	if lm != null:
		lm.connect("code_result", self, "_on_code_result")
	_fit()

# the tabs and the open tab start under the header (as in Settings)
func _fit():
	if not _built:
		return
	var top: float = _header.margin_top + _header.rect_size.y + 10
	_cats.rect_position = Vector2(14, top)
	_cats.rect_size = Vector2(CATS_W, max(rect_size.y - top - 12, 40))
	var left: float = 14 + CATS_W + 14
	_body.rect_position = Vector2(left, top)
	_body.rect_size = Vector2(max(rect_size.x - left - 8, 40), max(rect_size.y - top - 12, 40))

# (the look of the Settings categories: SettingsNewUI.gd _cat_button)
func _cat_button(title: String, i: int) -> Button:
	var b := Button.new()
	b.text = title
	b.toggle_mode = true
	b.align = Button.ALIGN_LEFT
	b.focus_mode = FOCUS_NONE
	b.clip_text = true
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	b.rect_min_size = Vector2(0, 32)
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.add_font_override("font", S.f_bold)
	b.add_color_override("font_color", S.DIM)
	for k in ["font_color_hover", "font_color_pressed", "font_color_hover_pressed"]:
		b.add_color_override(k, S.TEXT)
	var none: StyleBoxFlat = OnlineStyle.flat(Color(0, 0, 0, 0), 4, Color(0, 0, 0, 0), 0, 12, 5)
	var on: StyleBoxFlat = OnlineStyle.flat(Color(S.LILAC.r, S.LILAC.g, S.LILAC.b, 0.2), 4, Color(S.LILAC.r, S.LILAC.g, S.LILAC.b, 0.75), 1, 12, 5)
	b.add_stylebox_override("normal", none)
	b.add_stylebox_override("hover", OnlineStyle.flat(S.BTN_HOVER, 4, Color(0, 0, 0, 0), 0, 12, 5))
	b.add_stylebox_override("pressed", on)
	b.add_stylebox_override("hover_pressed", on)
	b.add_stylebox_override("focus", StyleBoxEmpty.new())
	b.connect("pressed", self, "_on_cat", [i])
	return b

func _on_cat(i: int):
	var press = get_node_or_null("../../Press")
	if press != null and i != _tab:
		press.play()
	_show_tab(i)

func _show_tab(i: int):
	_tab = i
	Engine.set_meta("inventory_tab", i) # (the same tab when the menu comes back after a song)
	for k in range(_panels.size()):
		_panels[k].visible = k == i
		_cat_btns[k].pressed = k == i
	if TABS[i] == "Avatar Creator":
		_make_avatar()
	else:
		_drop_avatar()

# --- Codes -----------------------------------------------------------------------

func _build_codes() -> Control:
	var p := PanelContainer.new()
	p.name = "Codes"
	p.add_stylebox_override("panel", OnlineStyle.flat(S.SECTION_BG, 4, Color(1, 1, 1, 0.05), 1, 18, 16))
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 10)
	p.add_child(v)
	v.add_child(S.heading("Codes"))
	v.add_child(S.label("Got a secret code? Type it here to unlock what it is for. What you unlock shows up on the Cards and Frames tabs.", S.f_small, S.DIM, true))
	var row := HBoxContainer.new()
	row.add_constant_override("separation", 8)
	v.add_child(row)
	_code = LineEdit.new()
	_code.placeholder_text = "Secret code"
	_code.max_length = 64
	_code.rect_min_size = Vector2(320, 38)
	S.field(_code)
	_code.connect("text_entered", self, "_redeem")
	row.add_child(_code)
	var go := Button.new()
	go.text = "Use code"
	S.button(go, true)
	go.connect("pressed", self, "_redeem")
	row.add_child(go)
	_code_msg = S.label("", S.f_small, S.DIM, true)
	v.add_child(_code_msg)
	# what the codes typed this time gave
	_code_list = VBoxContainer.new()
	_code_list.add_constant_override("separation", 6)
	v.add_child(_code_list)
	return p

func _redeem(_t = null):
	var code := _code.text.strip_edges()
	if code == "":
		return
	var Ascend = load("res://scripts/ui/menu/Ascend.gd")
	if Ascend.is_word(code):
		_code.text = ""
		_code.release_focus()
		Ascend.open_on(self)
		return
	if lm == null:
		_code_msg.text = "Codes need the server, and the game isn't connected to it."
		return
	_code_msg.add_color_override("font_color", S.DIM)
	_code_msg.text = "Checking the code..."
	lm.redeem_card_code(code)
	_code.text = ""

# the server's answer (LobbyManager "card_code"; the unlock notices are shown there)
func _on_code_result(ok: bool, text: String, cards: Array):
	if _code_msg == null:
		return
	_code_msg.text = text
	_code_msg.add_color_override("font_color", S.PLAYING if ok else S.BAD)
	if not ok:
		return
	for c in cards:
		if not (c is Dictionary):
			continue
		var fresh: bool = bool(c.get("is_new", true))
		var h: HBoxContainer = S.card(_code_list)
		var sw := Panel.new() # the card's own colours
		sw.rect_min_size = Vector2(46, 28)
		sw.size_flags_vertical = SIZE_SHRINK_CENTER
		var bg := Color(String(c.get("bg", ""))) if String(c.get("bg", "")).is_valid_html_color() else S.CARD_BG
		var border := Color(String(c.get("border", ""))) if String(c.get("border", "")).is_valid_html_color() else S.LILAC
		sw.add_stylebox_override("panel", OnlineStyle.flat(bg, 4, border, 2))
		h.add_child(sw)
		var nm: Label = S.label(String(c.get("name", "Card")), S.f_bold, S.TEXT)
		nm.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(nm)
		var what := ("Card and frame unlocked" if c.get("frame") is Dictionary else "Card unlocked") if fresh else "You had this already"
		h.add_child(S.label(what, S.f_small, S.PLAYING if fresh else S.DIM))
		if fresh:
			h.add_child(S.make_button("Show", self, "open_tab", ["Cards"], false, true))
		_code_list.move_child(h.get_parent(), 0) # (the newest on top)
	while _code_list.get_child_count() > 8:
		var old = _code_list.get_child(_code_list.get_child_count() - 1)
		_code_list.remove_child(old)
		old.queue_free()

# --- Avatar Creator --------------------------------------------------------------
# The editor's own scene, in the tab. It draws your avatar in a 3D view of its
# own, so it is only there while the tab is open.

func _make_avatar():
	if _avatar_ed != null and is_instance_valid(_avatar_ed):
		return
	var scene = load("res://scenes/menu/AvatarEditor.tscn")
	if scene == null:
		return
	_avatar_ed = scene.instance()
	# (its 3D view keeps to itself: not the menu's 3D things in it, nor the
	# avatar out in the menu's world, which in VR is the room you stand in)
	var vp = _avatar_ed.get_node_or_null("VPContainer/VP")
	if vp is Viewport:
		vp.own_world = true
	var back = _avatar_ed.get_node_or_null("Back") # (to the menu: we are in it)
	if back != null:
		back.visible = false
	_avatar_holder.add_child(_avatar_ed)

func _drop_avatar():
	if _avatar_ed != null and is_instance_valid(_avatar_ed):
		_avatar_ed.queue_free()
	_avatar_ed = null

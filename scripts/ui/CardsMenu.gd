extends PanelContainer

# Inventory & Misc > Cards (scripts/ui/menu/InventoryPage.gd): the card your
# player card shows in the Spectate grid (its background and border) and as
# the border of your website profile. Everyone has Default; the cards you
# don't have aren't shown. The server keeps which cards you have
# (LobbyManager get_cards / set_card); secret codes are typed on the Codes tab.
# (This was a window opened from the profile page, with the code box in it.)

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")
const TILE_W := 160.0

var S
var lm
var _grid: GridContainer
var _scroll: ScrollContainer = null
var _msg: Label
var _chosen := "default"

func _init():
	S = OnlineStyle.new()
	add_stylebox_override("panel", OnlineStyle.flat(S.SECTION_BG, 4, Color(1, 1, 1, 0.05), 1, 18, 16))
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 10)
	add_child(v)
	v.add_child(S.heading("Cards"))
	v.add_child(S.label("The colors of your card in the Spectate grid, and the border of your website profile. Some cards are unlocked by what you do; how is a secret.", S.f_small, S.DIM, true))
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_constant_override("hseparation", 10)
	_grid.add_constant_override("vseparation", 10)
	_scroll = S.scroll(ScrollContainer.new())
	_scroll.scroll_horizontal_enabled = false
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_scroll.add_child(_grid)
	_msg = S.label("Loading your cards...", S.f_small, S.DIM)
	v.add_child(_msg)

func _ready():
	lm = get_node_or_null("/root/LobbyManager")
	if lm != null:
		lm.connect("cards_received", self, "_on_cards")
		lm.connect("card_message", self, "_on_message")
	_scroll.connect("resized", self, "_fit")
	connect("visibility_changed", self, "_on_shown")
	_on_shown()

# asked for when the tab is first looked at, and again each time it's opened
# (a card unlocked meanwhile, by a code or by playing, is there then)
func _on_shown():
	if is_visible_in_tree():
		refresh()

func refresh():
	if lm != null:
		lm.get_cards()

# as many tiles side by side as fit
func _fit():
	if _scroll == null:
		return
	var sep: float = _grid.get_constant("hseparation")
	var cols := int(max(1.0, floor((_scroll.rect_size.x - 14.0 + sep) / (TILE_W + sep))))
	if _grid.columns != cols:
		_grid.columns = cols

func _on_cards(cards: Array, chosen: String):
	_chosen = chosen
	for c in _grid.get_children():
		_grid.remove_child(c) # (out of the list now: its size is worked out right after)
		c.queue_free()
	# Only the cards you have are shown (the others stay a secret until you get
	# them); admins see every card, the locked ones too. The server sends the
	# list that way; an older server's locked cards are left out here.
	var see_all: bool = bool(Rhythia.get("is_staff"))
	var locked := 0
	var shown := 0
	for c in cards:
		if c is Dictionary:
			var have := bool(c.get("unlocked", false))
			if not have and not see_all:
				continue
			_grid.add_child(_card(c))
			shown += 1
			if not have:
				locked += 1
	if locked > 0:
		_msg.text = "%d locked (only admins see these)." % locked
	else:
		_msg.text = "These are the cards you have. There are more to find: keep playing (and looking)."
	_fit()

func _card(c: Dictionary) -> Control:
	var id := String(c.get("id", ""))
	var have := bool(c.get("unlocked", false))
	var bg := Color(String(c.get("bg", "#13111a"))) if String(c.get("bg", "")).is_valid_html_color() else S.CARD_BG
	var border := Color(String(c.get("border", "#2b2734"))) if String(c.get("border", "")).is_valid_html_color() else Color(1, 1, 1, 0.1)
	var b := Button.new()
	b.rect_min_size = Vector2(TILE_W, 92)
	b.focus_mode = FOCUS_NONE
	b.toggle_mode = false
	var picked := id == _chosen
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb = OnlineStyle.flat(bg.lightened(0.06) if st == "hover" else bg, 6, S.TEXT if picked else border, 3 if picked else 2)
		b.add_stylebox_override(st, sb)
	# the card's own picture (an admin's upload), dimmed behind its name
	var iu := String(c.get("image_url", "")) if c.get("image_url") != null else ""
	if iu != "":
		var pic := TextureRect.new()
		pic.anchor_right = 1
		pic.anchor_bottom = 1
		pic.margin_left = 3
		pic.margin_top = 3
		pic.margin_right = -3
		pic.margin_bottom = -3
		pic.expand = true
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		pic.modulate = Color(0.6, 0.6, 0.6)
		pic.set_meta("url", iu)
		b.add_child(pic)
		var fi = load("res://scripts/ui/FrameImages.gd").instance()
		pic.texture = fi.pic(iu)
		if not fi.is_connected("loaded", self, "_on_art_loaded"):
			fi.connect("loaded", self, "_on_art_loaded")
	# a moving card (Supporter's hearts: CardFx.gd)
	var fx: String = String(c.get("fx", "")) if c.get("fx") != null else ""
	if fx != "":
		var cfx = load("res://scripts/ui/CardFx.gd").new()
		cfx.anchor_right = 1
		cfx.anchor_bottom = 1
		cfx.inset = 1.0
		b.add_child(cfx)
		cfx.set_fx(fx, border)
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND if have else CURSOR_ARROW
	b.disabled = not have
	b.hint_tooltip = ("Showing" if picked else "Use this card") if have else "Locked"
	var v := VBoxContainer.new()
	v.anchor_right = 1
	v.anchor_bottom = 1
	v.alignment = BoxContainer.ALIGN_CENTER
	v.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(v)
	var nm: Label = S.label(String(c.get("name", "Card")), S.f_bold, S.TEXT)
	nm.align = Label.ALIGN_CENTER
	nm.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(nm)
	var sub: Label = S.label("Showing" if picked else ("" if have else "Locked"), S.f_small, S.DIM)
	sub.align = Label.ALIGN_CENTER
	sub.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(sub)
	if not have:
		b.modulate = Color(1, 1, 1, 0.45)
	b.connect("pressed", self, "_pick", [id])
	return b

# a card picture arrived: put it on its tiles
func _on_art_loaded(url: String):
	var fi = load("res://scripts/ui/FrameImages.gd").instance()
	for t in _grid.get_children():
		for ch in t.get_children():
			if ch is TextureRect and ch.has_meta("url") and String(ch.get_meta("url")) == url:
				ch.texture = fi.pic(url)

func _pick(id: String):
	if lm != null:
		_msg.text = "Saving..."
		lm.set_card(id)

func _on_message(text: String, again: bool):
	_msg.text = text
	if again and lm != null and is_visible_in_tree():
		lm.get_cards()

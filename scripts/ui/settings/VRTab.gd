extends VBoxContainer

# Settings > VR (only while playing in VR / on the Meta Quest app):
#  - Menu screen: how big and far the menu screen is, and whether it curves
#    around you (vr/MenuPointer.gd rebuilds it).
#  - Controller grip: the pointer's angle and offset on your hand, like the
#    controller settings of other VR rhythm games. The beam moves as you change
#    it. Set for the right hand; the left hand gets the mirror image.
#  - Controller buttons: which button does what (up to two each).
#
# menu2.gd adds it (add_tab). Saved with the other settings (Savia.gd
# vr_grip_rot / vr_grip_pos / vr_binds).

const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)
const NONE_ID := 1000 # the "(none)" item (an id of -1 would become 0)

# [label, which value, axis, min, max, step, unit]
const GRIP_ROWS := [
	["Tilt (up / down)", "rot", 0, -90.0, 90.0, 1.0, "°"],
	["Turn (left / right)", "rot", 1, -60.0, 60.0, 1.0, "°"],
	["Roll", "rot", 2, -90.0, 90.0, 1.0, "°"],
	["Move left / right", "pos", 0, -15.0, 15.0, 0.5, " cm"],
	["Move up / down", "pos", 1, -15.0, 15.0, 0.5, " cm"],
	["Move forward / back", "pos", 2, -15.0, 15.0, 0.5, " cm"],
]

var f_body: DynamicFont
var f_bold: DynamicFont
var f_title: DynamicFont
var box: VBoxContainer
var _sliders := [] # [slider, value label, row]
var _pickers := {} # action -> [OptionButton, OptionButton]
var _loading := false
# [label, setting, min, max, step, unit]
const SCREEN_ROWS := [
	["Size", "vr_menu_size", 50.0, 150.0, 5.0, "°"],
	["Distance", "vr_menu_distance", 1.0, 3.0, 0.1, " m"],
	["Text and buttons", "vr_menu_ui", 60.0, 140.0, 10.0, " %"],
]
# how far the note grid (where the notes come from) is in songs
const GRID_ROW := ["Grid distance", "vr_grid_distance", 0.75, 5.0, 0.05, " m"]
var _screen := [] # [slider, value label, row]
var _curve_box: CheckBox
var _screen_t: SceneTreeTimer = null

static func wanted() -> bool:
	return Rhythia.vr or OS.has_feature("quest")

static func add_tab(tab_container) -> void:
	if tab_container == null or not is_instance_valid(tab_container) or tab_container.has_node("VR") or not wanted():
		return
	var t = load("res://scripts/ui/settings/VRTab.gd").new()
	t.name = "VR"
	tab_container.add_child(t)
	var after = tab_container.get_node_or_null("Generator")
	if after == null:
		after = tab_container.get_node_or_null("Gameplay")
	if after:
		tab_container.move_child(t, after.get_index() + 1)

func _font(path: String, size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	return f

func _ready():
	f_body = _font("res://assets/font/Lato/Lato-Regular.ttf", 17)
	f_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 18)
	f_title = _font("res://assets/font/Lato/Lato-Black.ttf", 26)
	var m := MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_constant_override("margin_" + side, 18)
	add_child(m)
	box = VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_constant_override("separation", 8)
	m.add_child(box)

	_label("Menu screen", f_title, ACCENT)
	_label("How big the menu screen is (how much of your view it fills), how far away, how big its text and buttons are (smaller fits more on it), and whether it curves around you so every part is just as far. You can also drag the icon in the screen's bottom right corner to resize it, or tap it for size buttons. Scroll lists and settings with the thumbstick while you point at them.", f_body, DIM, true)
	for row in SCREEN_ROWS:
		_screen_row(row)
	_curve_box = CheckBox.new()
	_curve_box.text = "Curved around you"
	_curve_box.theme = load("res://uitheme.tres")
	_curve_box.add_font_override("font", f_bold)
	_curve_box.connect("toggled", self, "_on_curve")
	box.add_child(_curve_box)
	_button(box, "Reset screen", "_reset_screen")
	box.add_child(HSeparator.new())
	_label("Play area", f_title, ACCENT)
	_label("Locked: nothing moves where the menu and the grid are (holding the recenter button or a view reset on the headset do nothing), and it stays the same after you reopen the game. Press the recenter button 5 times quickly to lock or unlock it.", f_body, DIM, true)
	_lock_area_box = CheckBox.new()
	_lock_area_box.text = "Lock the play area"
	_lock_area_box.theme = load("res://uitheme.tres")
	_lock_area_box.add_font_override("font", f_bold)
	_lock_area_box.connect("toggled", self, "_on_lock_area")
	box.add_child(_lock_area_box)
	box.add_child(HSeparator.new())
	_label("Menu environment", f_title, ACCENT)
	_label("What's around you in the menu: a built-in place, or any background from the background list (also your own custom ones).", f_body, DIM, true)
	var envs := []
	for b in load("res://vr/MenuEnvs.gd").BUILT_IN:
		envs.append([b[1], b[0]])
	envs.append(["A background...", BG_ITEM])
	_env_pick = _option_row("Environment", envs, "_on_env")
	box.add_child(HSeparator.new())
	_label("In songs", f_title, ACCENT)
	_label("How far away the grid is (where the notes come from and where you hit them). Closer fills more of your view, like a wider FOV; further fits it all in view. Changes from the next song you play. Default 2.25 m.", f_body, DIM, true)
	_screen_row(GRID_ROW)
	_button(box, "Reset grid distance", "_reset_grid")
	_label("Aim sensitivity: how far the cursor moves for how far you turn the controller. 1 = exactly where you point (like a laser); higher reaches the whole grid with smaller wrist turns, lower is steadier. The beam bends to end on the cursor.", f_body, DIM, true)
	_value_row(["Aim sensitivity", "vr_sensitivity", 0.5, 3.0, 0.05, "x", 1.0])
	box.add_child(HSeparator.new())
	_label("Haptics", f_title, ACCENT)
	_label("A short buzz in the pointing hand when you hit a note, a stronger one when you miss.", f_body, DIM, true)
	_value_row(["Strength", "vr_haptics", 0.0, 1.0, 0.05, " %", 100.0])
	_miss_box = _check("Buzz on misses", "vr_haptic_miss")
	box.add_child(HSeparator.new())
	_label("Pointer", f_title, ACCENT)
	_label("The beam from your hand: how thick it is, its colour (and see-through-ness), or a rainbow.", f_body, DIM, true)
	_value_row(["Thickness", "vr_beam_width", 0.25, 4.0, 0.05, "x", 1.0])
	var ch := HBoxContainer.new()
	ch.add_constant_override("separation", 12)
	box.add_child(ch)
	var cl := _label("Colour", f_bold, TEXT, false, ch)
	cl.rect_min_size = Vector2(230, 0)
	cl.size_flags_horizontal = 0
	_beam_color = ColorPickerButton.new()
	_beam_color.rect_min_size = Vector2(140, 34)
	_beam_color.edit_alpha = true
	_beam_color.connect("color_changed", self, "_on_beam_color")
	ch.add_child(_beam_color)
	_button(ch, "Reset", "_reset_beam")
	_rainbow_box = _check("Rainbow pointer", "vr_beam_rainbow")
	_lock_box = _check("Lock the pointer to the grid in songs (the beam ends on the cursor and never goes past the grid's edges; a thin blue beam still shows where you really point)", "vr_lock_beam")
	_eyes_box = _check("Hitboxes feel like on PC (turning the controller moves the cursor as far as it looks from your eyes; off: exactly where the beam points)", "vr_aim_from_eyes")
	box.add_child(HSeparator.new())
	_label("Hands", f_title, ACCENT)
	_label("What your hands look like. Custom uses vr_hand.obj from the user folder (the right hand, in metres, controller at the middle, pointing along -Z; the left hand is mirrored).", f_body, DIM, true)
	_hand_pick = _option_row("Hands", [["Default", "default"], ["Furry paws", "paw"], ["Custom (vr_hand.obj)", "custom"]], "_on_hand")
	box.add_child(HSeparator.new())
	_label("Graphics", f_title, ACCENT)
	_label("Foveated rendering draws the edges of your view (blurry in the lenses anyway) at lower resolution: a big speed-up on the Meta Quest. Higher refresh rates look smoother but cost more. Render resolution applies the next time VR starts. Glow (bloom) is a full-screen effect per eye; it's off on the Quest unless you turn it on.", f_body, DIM, true)
	if OS.has_feature("quest"):
		_fov_pick = _option_row("Foveated rendering", [["Off", 0], ["Low", 1], ["Medium", 2], ["High", 3]], "_on_foveation")
		var rates: Array = load("res://vr/VRPlayer.gd").refresh_rates()
		var items := [["Headset default", 0.0]]
		for r in rates:
			items.append(["%d Hz" % int(round(r)), float(r)])
		_rate_pick = _option_row("Refresh rate", items, "_on_rate")
		_value_row(["Render resolution", "vr_render_scale", 0.6, 1.4, 0.05, " %", 100.0])
	_glow_pick = _option_row("Glow", [["Auto (off on Quest)", -1], ["Off", 0], ["On", 1]], "_on_glow")
	_simple_box = _check("Simple background in songs (fastest: the plain VOID background in VR, whatever background is picked)", "vr_simple_bg")
	box.add_child(HSeparator.new())
	_label("Controller grip", f_title, ACCENT)
	_label("Changes the angle and position of the pointer on your hand, so it points where feels natural to you. Watch the beam move while you change it. This is for the right hand; the left hand gets the mirror image.", f_body, DIM, true)
	for row in GRIP_ROWS:
		_grip_row(row)
	_button(box, "Reset grip", "_reset_grip")

	var sep := HSeparator.new()
	box.add_child(sep)
	_label("Controller buttons", f_title, ACCENT)
	_label("Pick which controller button does each thing (both controllers work the same). An action can have two buttons.", f_body, DIM, true)
	for a in Rhythia.VR_ACTIONS:
		_bind_row(a[0], a[1])
	_button(box, "Reset buttons", "_reset_binds")
	_load_values()
	# the corner icon on the screen changes the size too
	connect("visibility_changed", self, "_on_shown")

func _on_shown():
	if is_visible_in_tree():
		_load_values()

func _label(text: String, f: Font, col: Color, wrap: bool = false, parent: Node = null) -> Label:
	var l := Label.new()
	l.autowrap = wrap
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	(parent if parent != null else box).add_child(l)
	return l

func _button(parent: Node, text: String, method: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", f_bold)
	b.rect_min_size = Vector2(180, 36)
	b.size_flags_horizontal = 0
	b.connect("pressed", self, method)
	parent.add_child(b)
	return b

func _grip_row(row: Array):
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 12)
	box.add_child(h)
	var name_l := _label(row[0], f_bold, TEXT, false, h)
	name_l.rect_min_size = Vector2(230, 0)
	name_l.size_flags_horizontal = 0
	var s := HSlider.new()
	s.min_value = row[3]
	s.max_value = row[4]
	s.step = row[5]
	s.size_flags_horizontal = SIZE_EXPAND_FILL
	s.size_flags_vertical = SIZE_SHRINK_CENTER
	s.rect_min_size = Vector2(300, 28)
	s.theme = load("res://uitheme.tres")
	h.add_child(s)
	var val := _label("", f_body, TEXT, false, h)
	val.rect_min_size = Vector2(80, 0)
	val.size_flags_horizontal = 0
	_sliders.append([s, val, row])
	s.connect("value_changed", self, "_on_grip", [_sliders.size() - 1])

func _screen_row(row: Array):
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 12)
	box.add_child(h)
	var name_l := _label(row[0], f_bold, TEXT, false, h)
	name_l.rect_min_size = Vector2(230, 0)
	name_l.size_flags_horizontal = 0
	var sl := HSlider.new()
	sl.min_value = row[2]
	sl.max_value = row[3]
	sl.step = row[4]
	sl.size_flags_horizontal = SIZE_EXPAND_FILL
	sl.size_flags_vertical = SIZE_SHRINK_CENTER
	sl.rect_min_size = Vector2(300, 28)
	sl.theme = load("res://uitheme.tres")
	h.add_child(sl)
	var val := _label("", f_body, TEXT, false, h)
	val.rect_min_size = Vector2(80, 0)
	val.size_flags_horizontal = 0
	_screen.append([sl, val, row])
	sl.connect("value_changed", self, "_on_screen", [_screen.size() - 1])

static func _screen_fmt(v: float, row: Array) -> String:
	if row[4] < 0.1:
		return ("%.2f" % v) + row[5]
	return ("%.1f" % v if row[4] < 1.0 else str(int(round(v)))) + row[5]

func _on_screen(v: float, i: int):
	var e: Array = _screen[i]
	e[1].text = _screen_fmt(v, e[2])
	if _loading:
		return
	Rhythia.set(e[2][1], v)
	_apply_screen_soon()

func _on_curve(on: bool):
	if _loading:
		return
	Rhythia.vr_menu_curve = on
	_apply_screen_soon()

# --- Aim, haptics, hands, graphics --------------------------------------------
var _values := [] # [slider, value label, row [label, setting, min, max, step, unit, shown scale]]
var _miss_box: CheckBox
var _hand_pick: OptionButton
var _fov_pick: OptionButton
var _rate_pick: OptionButton
var _glow_pick: OptionButton
var _simple_box: CheckBox
var _beam_color: ColorPickerButton
var _rainbow_box: CheckBox
var _lock_box: CheckBox
var _eyes_box: CheckBox

func _on_beam_color(c: Color):
	if _loading:
		return
	Rhythia.vr_beam_color = c
	_save_soon()

func _reset_beam():
	Rhythia.vr_beam_width = 1.0
	Rhythia.vr_beam_color = Color(0, 1, 1, 0.63)
	Rhythia.vr_beam_rainbow = false
	Rhythia.vr_lock_beam = false
	_load_values()
	_save_soon()

func _value_row(row: Array):
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 12)
	box.add_child(h)
	var name_l := _label(row[0], f_bold, TEXT, false, h)
	name_l.rect_min_size = Vector2(230, 0)
	name_l.size_flags_horizontal = 0
	var sl := HSlider.new()
	sl.min_value = row[2]
	sl.max_value = row[3]
	sl.step = row[4]
	sl.size_flags_horizontal = SIZE_EXPAND_FILL
	sl.size_flags_vertical = SIZE_SHRINK_CENTER
	sl.rect_min_size = Vector2(300, 28)
	sl.theme = load("res://uitheme.tres")
	h.add_child(sl)
	var val := _label("", f_body, TEXT, false, h)
	val.rect_min_size = Vector2(80, 0)
	val.size_flags_horizontal = 0
	_values.append([sl, val, row])
	sl.connect("value_changed", self, "_on_value", [_values.size() - 1])

static func _value_fmt(v: float, row: Array) -> String:
	var shown: float = v * float(row[6])
	if row[6] == 1.0:
		return "%.2f" % shown + row[5]
	return str(int(round(shown))) + row[5]

func _on_value(v: float, i: int):
	var e: Array = _values[i]
	e[1].text = _value_fmt(v, e[2])
	if _loading:
		return
	Rhythia.set(e[2][1], v)
	_save_soon()

func _check(text: String, setting: String) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.theme = load("res://uitheme.tres")
	c.add_font_override("font", f_bold)
	c.connect("toggled", self, "_on_check", [setting])
	box.add_child(c)
	return c

func _on_check(on: bool, setting: String):
	if _loading:
		return
	Rhythia.set(setting, on)
	_save_soon()

func _option_row(title: String, items: Array, method: String) -> OptionButton:
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 12)
	box.add_child(h)
	var name_l := _label(title, f_bold, TEXT, false, h)
	name_l.rect_min_size = Vector2(230, 0)
	name_l.size_flags_horizontal = 0
	var o := OptionButton.new()
	o.theme = load("res://uitheme.tres")
	o.add_font_override("font", f_body)
	o.rect_min_size = Vector2(260, 34)
	for i in range(items.size()):
		o.add_item(items[i][0], i)
		o.set_item_metadata(i, items[i][1])
	o.connect("item_selected", self, method)
	h.add_child(o)
	return o

static func _select_meta(o: OptionButton, value):
	if o == null:
		return
	for i in range(o.get_item_count()):
		var m = o.get_item_metadata(i)
		if (typeof(m) == TYPE_REAL or typeof(m) == TYPE_INT) and (typeof(value) == TYPE_REAL or typeof(value) == TYPE_INT):
			if abs(float(m) - float(value)) < 0.5:
				o.select(i)
				return
		elif m == value:
			o.select(i)
			return
	o.select(0)

var _lock_area_box: CheckBox

func _on_lock_area(on: bool):
	if _loading or on == Rhythia.vr_play_lock:
		return
	if Rhythia.vr_player != null and Rhythia.vr_player.has_method("set_play_lock"):
		Rhythia.vr_player.set_play_lock(on)
	else:
		Rhythia.vr_play_lock = on
		_save_soon()

# (the 5 presses can change it while this page is open)
func _process(_d):
	if _lock_area_box != null and _lock_area_box.pressed != Rhythia.vr_play_lock:
		var was := _loading
		_loading = true
		_lock_area_box.pressed = Rhythia.vr_play_lock
		_loading = was

const BG_ITEM := "__bg__"
var _env_pick: OptionButton
var _env_picker = null

func _on_env(i: int):
	if _loading:
		return
	var v = str(_env_pick.get_item_metadata(i))
	if v == BG_ITEM:
		_open_env_picker()
		return
	_set_env(v)

func _set_env(v: String):
	Rhythia.vr_menu_env = v
	var sc = get_tree().current_scene
	if sc != null and sc.has_method("apply_env"):
		sc.apply_env()
	_show_env()
	_save_soon()

# every background as a tile (the background setting's picker)
func _open_env_picker():
	if _env_picker != null and is_instance_valid(_env_picker):
		return
	_env_picker = preload("res://scripts/ui/settings/WorldPicker.gd").new()
	_env_picker.worlds = Rhythia.registry_world.get_items()
	var cur = null
	if Rhythia.vr_menu_env.begins_with("bg:"):
		cur = Rhythia.registry_world.get_item(Rhythia.vr_menu_env.substr(3))
	_env_picker.selected = cur
	_env_picker.connect("picked", self, "_on_env_bg_picked")
	_env_picker.connect("tree_exited", self, "_show_env")
	get_viewport().add_child(_env_picker)

func _on_env_bg_picked(w):
	if w != null:
		_set_env("bg:" + w.id)

func _show_env():
	if _env_pick == null or not is_instance_valid(_env_pick):
		return
	var last := _env_pick.get_item_count() - 1
	if Rhythia.vr_menu_env.begins_with("bg:"):
		_env_pick.set_item_text(last, load("res://vr/MenuEnvs.gd").name_of(Rhythia.vr_menu_env))
		_env_pick.select(last)
	else:
		_env_pick.set_item_text(last, "A background...")
		_select_meta(_env_pick, Rhythia.vr_menu_env)

func _on_hand(i: int):
	if _loading:
		return
	Rhythia.vr_hand = str(_hand_pick.get_item_metadata(i))
	if Rhythia.vr_player != null and Rhythia.vr_player.has_method("apply_hand"):
		Rhythia.vr_player.apply_hand()
		if Rhythia.vr_hand == "custom" and Rhythia.vr_player._hand_shown != "custom":
			Globals.notify(Globals.NOTIFY_ERROR, "No vr_hand.obj in the user folder (or it couldn't be read).", "VR hands")
	_save_soon()

func _on_foveation(i: int):
	if _loading:
		return
	Rhythia.vr_foveation = int(_fov_pick.get_item_metadata(i))
	_apply_xr()

func _on_rate(i: int):
	if _loading:
		return
	Rhythia.vr_refresh = float(_rate_pick.get_item_metadata(i))
	_apply_xr()

func _on_glow(i: int):
	if _loading:
		return
	Rhythia.vr_glow = int(_glow_pick.get_item_metadata(i))
	_save_soon()

func _apply_xr():
	if Rhythia.vr_player != null and Rhythia.vr_player.has_method("apply_xr_settings"):
		Rhythia.vr_player.apply_xr_settings()
	_save_soon()

func _reset_grid():
	Rhythia.vr_grid_distance = 2.25
	_load_values()
	_save_soon()

func _reset_screen():
	Rhythia.vr_menu_size = 100.0
	Rhythia.vr_menu_distance = 1.6
	Rhythia.vr_menu_curve = true
	Rhythia.vr_menu_ui = 100.0
	_load_values()
	_apply_screen_soon()

# The screen you're pointing at changes shape: only once you let go of the
# slider for a moment.
func _apply_screen_soon():
	_screen_t = get_tree().create_timer(0.5)
	_screen_t.connect("timeout", self, "_apply_screen", [_screen_t])
	_save_soon()

func _apply_screen(t):
	if t != _screen_t:
		return
	if Input.is_mouse_button_pressed(BUTTON_LEFT) or Input.is_action_pressed("vr_click"):
		_apply_screen_soon() # still holding the slider
		return
	if is_instance_valid(Rhythia.vr_menu) and Rhythia.vr_menu.has_method("rebuild"):
		Rhythia.vr_menu.rebuild()

func _bind_row(action: String, title: String):
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 12)
	box.add_child(h)
	var name_l := _label(title, f_bold, TEXT, false, h)
	name_l.rect_min_size = Vector2(230, 0)
	name_l.size_flags_horizontal = 0
	var pair := []
	for slot in range(2):
		var o := OptionButton.new()
		o.theme = load("res://uitheme.tres")
		o.add_font_override("font", f_body)
		o.rect_min_size = Vector2(200, 34)
		o.add_item("(none)", NONE_ID)
		for b in Rhythia.VR_BUTTONS:
			o.add_item(b[0], b[1])
		o.connect("item_selected", self, "_on_bind", [action])
		h.add_child(o)
		pair.append(o)
	_pickers[action] = pair

func _load_values():
	_loading = true
	for e in _values:
		var v: float = float(Rhythia.get(e[2][1]))
		e[0].value = v
		e[1].text = _value_fmt(v, e[2])
	if _miss_box:
		_miss_box.pressed = bool(Rhythia.vr_haptic_miss)
	_select_meta(_hand_pick, Rhythia.vr_hand)
	_show_env()
	_select_meta(_fov_pick, Rhythia.vr_foveation)
	_select_meta(_rate_pick, Rhythia.vr_refresh)
	_select_meta(_glow_pick, Rhythia.vr_glow)
	if _simple_box:
		_simple_box.pressed = bool(Rhythia.vr_simple_bg)
	if _beam_color:
		_beam_color.color = Rhythia.vr_beam_color
	if _rainbow_box:
		_rainbow_box.pressed = bool(Rhythia.vr_beam_rainbow)
	if _lock_box:
		_lock_box.pressed = bool(Rhythia.vr_lock_beam)
	if _eyes_box:
		_eyes_box.pressed = bool(Rhythia.vr_aim_from_eyes)
	for e in _screen:
		var v: float = float(Rhythia.get(e[2][1]))
		e[0].value = v
		e[1].text = _screen_fmt(v, e[2])
	if _curve_box:
		_curve_box.pressed = bool(Rhythia.vr_menu_curve)
	for e in _sliders:
		var row: Array = e[2]
		var v: Vector3 = Rhythia.vr_grip_rot if row[1] == "rot" else Rhythia.vr_grip_pos
		e[0].value = v[row[2]]
		e[1].text = _fmt(v[row[2]], row)
	for action in _pickers:
		var bs: Array = Rhythia.vr_bind(action)
		for slot in range(2):
			var o: OptionButton = _pickers[action][slot]
			o.select(o.get_item_index(bs[slot]) if slot < bs.size() and o.get_item_index(bs[slot]) != -1 else 0)
	_loading = false

static func _fmt(v: float, row: Array) -> String:
	return (("%+.1f" if row[5] < 1.0 else "%+d") % (v if row[5] < 1.0 else int(round(v)))) + row[6]

func _on_grip(v: float, i: int):
	var e: Array = _sliders[i]
	var row: Array = e[2]
	e[1].text = _fmt(v, row)
	if _loading:
		return
	if row[1] == "rot":
		var r: Vector3 = Rhythia.vr_grip_rot
		r[row[2]] = v
		Rhythia.vr_grip_rot = r
	else:
		var p: Vector3 = Rhythia.vr_grip_pos
		p[row[2]] = v
		Rhythia.vr_grip_pos = p
	_save_soon()

func _on_bind(_idx: int, action: String):
	if _loading:
		return
	var out := []
	for o in _pickers[action]:
		var id: int = o.get_selected_id()
		if id != NONE_ID and id >= 0 and not out.has(id):
			out.append(id)
	var binds: Dictionary = Rhythia.vr_binds.duplicate()
	binds[action] = out
	Rhythia.vr_binds = binds
	if Rhythia.vr and not Rhythia.fake_vr:
		Rhythia.apply_vr_binds()
	_save_soon()

func _reset_grip():
	Rhythia.vr_grip_rot = Vector3.ZERO
	Rhythia.vr_grip_pos = Vector3.ZERO
	_load_values()
	_save_soon()

func _reset_binds():
	Rhythia.vr_binds = {}
	if Rhythia.vr and not Rhythia.fake_vr:
		Rhythia.apply_vr_binds()
	_load_values()
	_save_soon()

# sliders send many changes while dragged: save once they stop
var _save_t: SceneTreeTimer = null
func _save_soon():
	_save_t = get_tree().create_timer(0.6)
	_save_t.connect("timeout", self, "_save", [_save_t])

func _save(t):
	if t == _save_t:
		Rhythia.save_settings()

extends VBoxContainer

# Settings > Pinned: the settings you use most, together on one page.
#
# Pinning: rest the pointer on any setting on any Settings page and a small
# "Pin" button shows just after it ("Unpin" when it is pinned already).
#
# A pinned setting is not moved (everything that finds a setting by its
# place still does). The Pinned page shows a working copy of its control: a
# checkbox, number box, slider, dropdown, text box, colour button or button.
# Changing the copy changes the real one the way a click on it does, and the
# copy follows the real one when that changes. "Go to" opens the setting on
# its own page; a setting that isn't there right now (a VR one outside VR)
# is listed greyed out.
#
# Kept in user://pinned_settings.json (not in a profile: your pins stay when
# you switch profiles): [{key, name, tab}]. key is the setting's place in
# Settings ("p:Video & Audio/Graphics/Group/H/MaxFPSMode"), or for settings
# that are built by code and have no lasting name, its page and text
# ("t:VR\nHide the beam").

const FILE := "user://pinned_settings.json"
const MAX_PINS := 60
# A page marks what isn't a setting with this meta (set_meta(NO_PIN, true)):
# read-outs, explanations, lists it fills in. No Pin button shows on it or on
# anything inside it. (The Settings Generator's findings and play lists.)
const NO_PIN := "no_pin"
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const PINK := Color(0.96, 0.6, 0.78)

var tc: TabContainer = null
var settings: Control = null # the Settings page (Main/Settings)
var pins := [] # [{key, name, tab}]
var box: VBoxContainer
var _mirrors := [] # [copy, real, kind]
var _syncing := false
var _sync_t := 0.0
var _dirty := true
var _pin_btn: Button = null
var _hover = null # [text, tip, tab title, node] under the pointer
var _hover_t := 0.0
var _tab_entries := [] # the page shown: its settings
var _tab_for := ""
var _tab_at := 0
var _last_mouse := Vector2(-1, -1)
var _saw_toggle := false

static func add_tab(tab_container) -> void:
	if tab_container == null or not is_instance_valid(tab_container) or tab_container.has_node("Pinned"):
		return
	var t = load("res://scripts/ui/settings/PinnedTab.gd").new()
	t.name = "Pinned"
	t.tc = tab_container
	var was: int = tab_container.current_tab
	tab_container.add_child(t)
	tab_container.move_child(t, 0)
	# (with pins, Settings opens on them; without, on the page it always did)
	tab_container.current_tab = 0 if not t.pins.empty() else min(was + 1, tab_container.get_tab_count() - 1)

func _init():
	_load()

func _ready():
	size_flags_horizontal = SIZE_EXPAND_FILL
	var m := MarginContainer.new()
	for k in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		m.add_constant_override(k, 18)
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	add_child(m)
	box = VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_constant_override("separation", 10)
	m.add_child(box)
	connect("visibility_changed", self, "_on_shown")
	var n: Node = tc
	while n != null and not (n is Control and n.name == "Settings"):
		n = n.get_parent()
	settings = n as Control
	_pin_btn = Button.new()
	_pin_btn.name = "PinHere"
	_pin_btn.theme = load("res://uitheme.tres")
	_pin_btn.focus_mode = FOCUS_NONE
	_pin_btn.rect_min_size = Vector2(58, 24)
	_pin_btn.visible = false
	_pin_btn.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	_pin_btn.connect("pressed", self, "_on_pin_here")
	(settings if settings != null else self).call_deferred("add_child", _pin_btn)
	_pin_btn.set_as_toplevel(true)
	_rebuild()

# --- the pins -------------------------------------------------------------------

func _load():
	pins = []
	var f := File.new()
	if not f.file_exists(Globals.p(FILE)) or f.open(Globals.p(FILE), File.READ) != OK:
		return
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or not (parsed.result is Array):
		return
	for e in parsed.result:
		if e is Dictionary and e.get("key") is String and pins.size() < MAX_PINS:
			pins.append({key = String(e.key).left(300), name = String(e.get("name", "")).left(80), tab = String(e.get("tab", "")).left(60)})

func _save():
	var f := File.new()
	if f.open(Globals.p(FILE), File.WRITE) == OK:
		f.store_string(to_json(pins))
		f.close()

func _key_of(entry: Array) -> String:
	var n: Node = entry[3]
	var path := String(tc.get_path_to(n))
	if path.find("@") == -1 and not path.begins_with(".."):
		return "p:" + path
	return "t:%s\n%s" % [entry[2], entry[0]]

func _find_pin(key: String) -> int:
	for i in range(pins.size()):
		if pins[i].key == key:
			return i
	return -1

func is_pinned(entry: Array) -> bool:
	return _find_pin(_key_of(entry)) != -1

func toggle_pin(entry: Array):
	var key := _key_of(entry)
	var i := _find_pin(key)
	if i != -1:
		pins.remove(i)
		Globals.notify(Globals.NOTIFY_INFO, "\"%s\" is no longer pinned." % entry[0], "Pinned settings", 3)
	elif pins.size() >= MAX_PINS:
		Globals.notify(Globals.NOTIFY_WARN, "%d settings can be pinned at most. Unpin one first." % MAX_PINS, "Pinned settings")
		return
	else:
		pins.append({key = key, name = String(entry[0]), tab = String(entry[2])})
		Globals.notify(Globals.NOTIFY_SUCCEED, "\"%s\" is pinned: it is on the Pinned page of Settings now." % entry[0], "Pinned settings", 4)
	_save()
	_dirty = true
	if is_visible_in_tree():
		_rebuild()

# --- finding settings (as the search of the new Settings look does) -------------

static func _has_letter(s: String) -> bool:
	for i in range(s.length()):
		var c := s[i]
		if c.to_upper() != c.to_lower():
			return true
	return false

func _index_node(n: Node, tab: String, seen: Dictionary, is_page: bool, out: Array):
	if n is Control and not is_page and not n.visible:
		return
	if n is Popup:
		return
	if n.has_meta(NO_PIN):
		return # (text that isn't a setting: neither it nor anything in it)
	var text := ""
	if n is CheckBox or n is Label or (n is Button and not (n is OptionButton) and not (n is ColorPickerButton)):
		text = String(n.text).strip_edges()
	if text.length() >= 2 and text.length() <= 70 and not seen.has(text) and _has_letter(text):
		seen[text] = true
		out.append([text, String(n.hint_tooltip) if n is Control else "", tab, n])
	for c in n.get_children():
		_index_node(c, tab, seen, false, out)

func _entries_of(i: int) -> Array:
	var out := []
	var page = tc.get_tab_control(i)
	if page != null and page != self:
		_index_node(page, tc.get_tab_title(i), {}, true, out)
	return out

# the setting a pin is for, as [text, tip, tab title, node], or null when it isn't there now
func _resolve(pin: Dictionary):
	var key: String = pin.key
	if key.begins_with("p:"):
		var n = tc.get_node_or_null(key.substr(2))
		if n == null or not (n is Control):
			return null
		var page: Node = n
		while page != null and page.get_parent() != tc:
			page = page.get_parent()
		if page == null:
			return null
		return [String(n.get("text")) if n.get("text") != null else pin.name, String(n.hint_tooltip), tc.get_tab_title(page.get_index()), n]
	var parts := key.substr(2).split("\n")
	if parts.size() != 2:
		return null
	for i in range(tc.get_tab_count()):
		if tc.get_tab_title(i) != parts[0]:
			continue
		for e in _entries_of(i):
			if e[0] == parts[1]:
				return e
	return null

# --- which controls a setting is changed with -----------------------------------

static func _kind(c) -> String:
	if not (c is Control):
		return ""
	if c is OptionButton:
		return "option"
	if c is ColorPickerButton:
		return "color"
	if c is MenuButton:
		return ""
	if c is CheckBox or c is CheckButton or (c is Button and c.toggle_mode):
		return "toggle"
	if c is Button:
		return "button" if String(c.text).strip_edges() != "" else ""
	if c is SpinBox:
		return "spin"
	if c is HSlider:
		return "slider"
	if c is LineEdit:
		return "line"
	return ""

func _controls_of(n: Control) -> Array:
	if not (n is Label):
		return [n] if _kind(n) != "" else []
	# a name with its control beside it in a row (or one step into the row)
	var out := []
	var par = n.get_parent()
	if not (par is HBoxContainer) and not (par is Control and par.get_child_count() <= 4):
		return out
	for sib in par.get_children():
		if sib == n or not (sib is Control) or not sib.visible:
			continue
		if _kind(sib) != "":
			out.append(sib)
		elif sib is Container and not (sib is SpinBox):
			for inner in sib.get_children():
				if inner is Control and inner.visible and _kind(inner) != "":
					out.append(inner)
		if out.size() >= 4:
			break
	return out

# --- the page -------------------------------------------------------------------

func _lbl(text: String, col: Color = TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap = wrap
	l.add_color_override("font_color", col)
	if wrap:
		l.size_flags_horizontal = SIZE_EXPAND_FILL
	return l

func _small_btn(text: String, method: String, binds: Array, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	b.focus_mode = FOCUS_NONE
	b.rect_min_size = Vector2(74, 28)
	b.hint_tooltip = tip
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	b.connect("pressed", self, method, binds)
	return b

func _on_shown():
	if is_visible_in_tree():
		_rebuild()

func _rebuild():
	if box == null:
		return
	_dirty = false
	_mirrors = []
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()
	box.add_child(_lbl("Pinned settings", PINK))
	box.add_child(_lbl("The settings you use most, together here. To pin one, rest the pointer on any setting on any page and press the \"Pin\" button that shows next to it. What you change here changes the real setting.", DIM, true))
	if pins.empty():
		box.add_child(_lbl("Nothing is pinned yet.", TEXT))
		return
	for i in range(pins.size()):
		box.add_child(_row(pins[i], i))

func _row(pin: Dictionary, i: int) -> Control:
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 10)
	h.rect_min_size = Vector2(0, 34)
	var e = _resolve(pin)
	if e == null:
		h.add_child(_lbl("%s  (on %s: not available right now)" % [pin.name, pin.tab], DIM))
		h.add_child(_small_btn("Unpin", "_unpin", [pin.key], "Take it off this page"))
		return h
	var n: Control = e[3]
	var controls: Array = _controls_of(n)
	if n is Label or controls.empty():
		var name_l := _lbl(String(e[0]))
		name_l.rect_min_size = Vector2(220, 0)
		name_l.hint_tooltip = String(e[1])
		name_l.mouse_filter = MOUSE_FILTER_PASS
		h.add_child(name_l)
	for real in controls:
		var copy := _copy(real)
		if copy != null:
			h.add_child(copy)
	# (right after the setting, not at the far end of the row: the preview window floats over that side)
	var gap := Control.new()
	gap.rect_min_size = Vector2(14, 0)
	h.add_child(gap)
	h.add_child(_small_btn("Go to", "_go", [pin.key], "Open this setting on its own page (%s)" % String(e[2])))
	h.add_child(_small_btn("Unpin", "_unpin", [pin.key], "Take it off this page"))
	var where := _lbl(String(e[2]), DIM)
	where.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(where)
	return h

func _unpin(key: String):
	var i := _find_pin(key)
	if i == -1:
		return
	pins.remove(i)
	_save()
	_rebuild()

func _go(key: String):
	var i := _find_pin(key)
	var e = _resolve(pins[i]) if i != -1 else null
	if e == null:
		return
	var n: Node = e[3]
	var page: Node = n
	while page != null and page.get_parent() != tc:
		page = page.get_parent()
	if page == null:
		return
	var ui = settings.get_node_or_null("NewUI") if settings != null else null
	if ui != null and ui.has_method("_go"):
		ui._go([e[0], e[1], page.get_index(), n]) # (its page, scrolled to it, outlined for a moment)
	else:
		tc.current_tab = page.get_index()

# --- a working copy of a control -------------------------------------------------

func _copy(real: Control) -> Control:
	var kind := _kind(real)
	var c: Control = null
	match kind:
		"toggle":
			var b := CheckBox.new()
			b.text = String(real.text)
			b.pressed = real.pressed
			b.connect("toggled", self, "_c_toggle", [b, real])
			c = b
		"button":
			var b := Button.new()
			b.text = String(real.text)
			b.rect_min_size = Vector2(120, 30)
			b.connect("pressed", self, "_c_press", [real])
			c = b
		"option":
			var o := OptionButton.new()
			o.rect_min_size = Vector2(200, 30)
			o.connect("item_selected", self, "_c_option", [o, real])
			c = o
		"color":
			var p := ColorPickerButton.new()
			p.rect_min_size = Vector2(110, 30)
			p.edit_alpha = real.edit_alpha
			p.color = real.color
			p.connect("color_changed", self, "_c_color", [real])
			c = p
		"spin":
			var s := SpinBox.new()
			_range_like(s, real)
			s.prefix = real.prefix
			s.suffix = real.suffix
			s.rect_min_size = Vector2(120, 30)
			s.connect("value_changed", self, "_c_value", [real])
			c = s
		"slider":
			var s := HSlider.new()
			_range_like(s, real)
			s.rect_min_size = Vector2(220, 26)
			s.size_flags_vertical = SIZE_SHRINK_CENTER
			s.focus_mode = FOCUS_NONE
			s.connect("value_changed", self, "_c_value", [real])
			c = s
		"line":
			var e := LineEdit.new()
			e.text = real.text
			e.placeholder_text = real.placeholder_text
			e.rect_min_size = Vector2(220, 30)
			e.connect("text_changed", self, "_c_text", [real, false])
			e.connect("text_entered", self, "_c_text", [real, true])
			c = e
	if c == null:
		return null
	c.theme = load("res://uitheme.tres")
	c.hint_tooltip = real.hint_tooltip
	if kind != "line":
		c.focus_mode = FOCUS_NONE
	if c is BaseButton:
		c.disabled = real.disabled
	_mirrors.append([c, real, kind])
	_follow(c, real, kind)
	return c

static func _range_like(s: Range, real: Range):
	s.min_value = real.min_value
	s.max_value = real.max_value
	s.step = real.step
	s.allow_greater = real.allow_greater
	s.allow_lesser = real.allow_lesser
	s.rounded = real.rounded
	s.exp_edit = real.exp_edit
	s.value = real.value

# the copy shows what the real one shows
func _follow(c: Control, real: Control, kind: String):
	_syncing = true
	match kind:
		"toggle":
			if c.pressed != real.pressed:
				c.pressed = real.pressed
		"option":
			var same: bool = c.get_item_count() == real.get_item_count()
			if same:
				for i in range(real.get_item_count()):
					if c.get_item_text(i) != real.get_item_text(i):
						same = false
						break
			if not same:
				c.clear()
				for i in range(real.get_item_count()):
					c.add_item(real.get_item_text(i), real.get_item_id(i))
					c.set_item_disabled(i, real.is_item_disabled(i))
			if c.selected != real.selected:
				c.select(real.selected)
		"color":
			if c.color != real.color and not c.get_popup().visible:
				c.color = real.color
		"spin", "slider":
			if c.min_value != real.min_value or c.max_value != real.max_value or c.step != real.step:
				_range_like(c, real)
			if not is_equal_approx(c.value, real.value):
				c.value = real.value
		"line":
			if c.text != real.text and not c.has_focus():
				c.text = real.text
	if c is BaseButton and c.disabled != real.disabled:
		c.disabled = real.disabled
	_syncing = false

func _seen_toggle(_on):
	_saw_toggle = true

# the real checkbox, as a click on it: its state, its "toggled" and its "pressed"
func _c_toggle(on: bool, copy: BaseButton, real: BaseButton):
	if _syncing or not is_instance_valid(real) or real.pressed == on:
		return
	_saw_toggle = false
	real.connect("toggled", self, "_seen_toggle")
	real.pressed = on
	real.disconnect("toggled", self, "_seen_toggle")
	if not _saw_toggle:
		# (this engine version changed the state without saying so)
		if real.has_method("_toggled"):
			real._toggled(on)
		real.emit_signal("toggled", on)
	_c_press(real)

func _c_press(real: BaseButton):
	if _syncing or not is_instance_valid(real):
		return
	if real.has_method("_pressed"):
		real._pressed()
	real.emit_signal("pressed")

func _c_option(i: int, _copy: OptionButton, real: OptionButton):
	if _syncing or not is_instance_valid(real) or i < 0 or i >= real.get_item_count():
		return
	real.select(i)
	real.emit_signal("item_selected", i)

func _c_color(col: Color, real: ColorPickerButton):
	if _syncing or not is_instance_valid(real):
		return
	real.color = col
	real.emit_signal("color_changed", col)

func _c_value(v: float, real: Range):
	if _syncing or not is_instance_valid(real):
		return
	real.value = v # (it says so itself)

func _c_text(t: String, real: LineEdit, entered: bool):
	if _syncing or not is_instance_valid(real):
		return
	real.text = t
	real.emit_signal("text_entered" if entered else "text_changed", t)

# --- the "Pin" button beside the setting under the pointer -------------------------

func _row_rect(n: Control) -> Rect2:
	var par = n.get_parent()
	if par is HBoxContainer and par.rect_size.y <= 64:
		return (par as Control).get_global_rect()
	return n.get_global_rect()

# where the setting's own things end (a checkbox is as wide as its page; its box and text aren't)
func _content_right(n: Control) -> float:
	var par = n.get_parent()
	if par is HBoxContainer and par.rect_size.y <= 64:
		var right: float = n.rect_global_position.x
		for c in par.get_children():
			if c is Control and c.visible:
				var w: float = c.get_combined_minimum_size().x if (c is Label or c is BaseButton) else c.rect_size.x
				right = max(right, c.rect_global_position.x + min(w, c.rect_size.x))
		return right
	return n.rect_global_position.x + min(n.get_combined_minimum_size().x, n.rect_size.x)

func _under(mouse: Vector2):
	var cur: int = tc.current_tab
	if cur < 0 or tc.get_tab_control(cur) == self:
		return null
	var title: String = tc.get_tab_title(cur)
	var now := OS.get_ticks_msec()
	if title != _tab_for or now - _tab_at > 2500:
		_tab_for = title
		_tab_at = now
		_tab_entries = _entries_of(cur)
	var best = null
	var best_area := 1e12
	for e in _tab_entries:
		var n = e[3]
		if not is_instance_valid(n) or not n.is_visible_in_tree():
			continue
		var r: Rect2 = _row_rect(n).grow_individual(2, 2, 2, 2)
		if r.has_point(mouse) and r.get_area() < best_area:
			best = e
			best_area = r.get_area()
	return best

func _process(delta: float):
	# the copies follow the real controls
	if is_visible_in_tree():
		_sync_t += delta
		if _sync_t > 0.25:
			_sync_t = 0.0
			for m in _mirrors:
				if is_instance_valid(m[0]) and is_instance_valid(m[1]):
					_follow(m[0], m[1], m[2])
	if _pin_btn == null or settings == null:
		return
	if not settings.is_visible_in_tree() or not tc.is_visible_in_tree() or tc.get_tab_control(tc.current_tab) == self:
		_pin_btn.visible = false
		_last_mouse = Vector2(-1, -1)
		return
	var mouse: Vector2 = Rhythia.menu_mouse(self)
	if _pin_btn.visible and _pin_btn.get_global_rect().grow(4).has_point(mouse):
		return # (on the button itself: it stays)
	if mouse == _last_mouse:
		return
	_last_mouse = mouse
	var area: Rect2 = tc.get_global_rect()
	var sc: Node = tc.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null:
		area = (sc as Control).get_global_rect()
	var e = _under(mouse) if area.has_point(mouse) else null
	if e == null:
		_pin_btn.visible = false
		_hover = null
		return
	_hover = e
	var r: Rect2 = _row_rect(e[3])
	_pin_btn.text = "Unpin" if is_pinned(e) else "Pin"
	_pin_btn.hint_tooltip = ("Take \"%s\" off the Pinned page" if is_pinned(e) else "Put \"%s\" on the Pinned page of Settings") % e[0]
	_pin_btn.rect_size = _pin_btn.rect_min_size
	# just after the setting (never on it), inside the page
	var x: float = min(_content_right(e[3]) + 12.0, area.end.x - _pin_btn.rect_size.x - 14.0)
	_pin_btn.rect_global_position = Vector2(x, r.position.y + (r.size.y - _pin_btn.rect_size.y) * 0.5)
	_pin_btn.visible = area.has_point(_pin_btn.rect_global_position + _pin_btn.rect_size * 0.5)
	_pin_btn.raise()

func _on_pin_here():
	if _hover != null and is_instance_valid(_hover[3]):
		toggle_pin(_hover)
		_pin_btn.text = "Unpin" if is_pinned(_hover) else "Pin"

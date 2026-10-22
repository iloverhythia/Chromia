extends VBoxContainer

# Settings > Generator: Chromia keeps track of how you play
# (scripts/game/PlayTracker.gd, on this device only) and the Settings
# Generator (scripts/SettingsAdvisor.gd) turns that into settings that fit
# you: what it found, each suggestion with the reason and how sure it is, and
# Apply / Apply all / Undo.
#
# menu2.gd adds it (add_tab).

const Advisor = preload("res://scripts/SettingsAdvisor.gd")
const PT = preload("res://scripts/game/PlayTracker.gd")
const UNDO_FILE := "user://play_tracking/undo.json"

const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)
const CARD := Color(0.11, 0.105, 0.14, 1)
const CONF_COLORS := {"high": Color8(90, 230, 120), "medium": Color8(250, 210, 90), "try": Color8(150, 190, 255)}
const CONF_NAMES := {"high": "sure", "medium": "likely", "try": "worth a try"}

# the settings boxes that copy their value into the game every frame: they
# have to show the new value too, or they'd put the old one back
const CONTROLS := {
	"res://scripts/ui/settings/Sensitivity.gd": ["sensitivity", 1.0],
	"res://scripts/ui/settings/ApproachRate.gd": ["approach_rate", 1.0],
	"res://scripts/ui/settings/SpawnDist.gd": ["spawn_distance", 1.0],
	"res://scripts/ui/settings/Parallax.gd": ["parallax", 1.0],
	"res://scripts/ui/settings/UIParallax.gd": ["ui_parallax", 1.0],
	"res://scripts/ui/settings/GridParallax.gd": ["grid_parallax", 1.0],
	"res://scripts/ui/settings/fov.gd": ["fov", 1.0],
	"res://scripts/ui/settings/FadeLength.gd": ["fade_length", 100.0],
	"res://scripts/ui/settings/CursorScale.gd": ["cursor_scale", 1.0],
}

var f_body: DynamicFont
var f_bold: DynamicFont
var f_title: DynamicFont
var box: VBoxContainer
var summary: Label
var insights: VBoxContainer
var recs_box: VBoxContainer
var undo_btn: Button
var gen_btn: Button
var _recs := []
var _rec_buttons := []

static func add_tab(tab_container) -> void:
	if tab_container == null or not is_instance_valid(tab_container) or tab_container.has_node("Generator"):
		return
	var t = load("res://scripts/ui/settings/GeneratorTab.gd").new()
	t.name = "Generator"
	tab_container.add_child(t)
	var after = tab_container.get_node_or_null("Gameplay")
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
	f_title = _font("res://assets/font/Lato/Lato-Black.ttf", 28)
	var m := MarginContainer.new()
	m.size_flags_horizontal = SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		m.add_constant_override("margin_" + side, 18)
	add_child(m)
	box = VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_constant_override("separation", 10)
	m.add_child(box)

	_label("Settings Generator", f_title, ACCENT)
	_label("Chromia keeps track of how you play every map: which notes you hit, how early your cursor gets to them, whether you miss by being late or by overshooting, which jumps and parts of the grid give you trouble, and which settings you had on. Generate looks at all of it and suggests settings that fit you, with the reason for each. It only touches how the game feels (sensitivity, approach, parallax, FOV...), never your hitbox, hit window or mods. Everything stays on this device.", f_body, DIM, true)

	var track := CheckBox.new()
	track.text = "Track my plays"
	track.pressed = bool(Rhythia.get("track_plays"))
	track.add_font_override("font", f_bold)
	track.add_color_override("font_color", TEXT)
	track.connect("toggled", self, "_on_track")
	box.add_child(track)

	var row := HBoxContainer.new()
	row.add_constant_override("separation", 8)
	box.add_child(row)
	gen_btn = _button(row, "Generate my settings", "_generate")
	undo_btn = _button(row, "Undo last change", "_undo")
	_button(row, "Clear tracked plays", "_clear")
	undo_btn.disabled = not File.new().file_exists(Globals.p(UNDO_FILE))

	summary = _label("", f_bold, TEXT, true)
	insights = VBoxContainer.new()
	box.add_child(insights)
	recs_box = VBoxContainer.new()
	recs_box.add_constant_override("separation", 8)
	box.add_child(recs_box)
	summary.text = "%d plays tracked so far. Press Generate to see what fits you." % PT.list_files().size()

func _label(text: String, f: Font, col: Color, wrap: bool = false, parent: Node = null) -> Label:
	var l := Label.new()
	l.autowrap = wrap
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	(parent if parent != null else box).add_child(l)
	return l

func _button(parent: Node, text: String, method: String, binds: Array = []) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = load("res://uitheme.tres")
	b.add_font_override("font", f_bold)
	b.rect_min_size = Vector2(0, 36)
	b.connect("pressed", self, method, binds)
	parent.add_child(b)
	return b

func _on_track(on: bool):
	Rhythia.track_plays = on
	Rhythia.save_settings()

func _generate():
	gen_btn.disabled = true
	gen_btn.text = "Looking at your plays..."
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	var res: Dictionary = Advisor.analyze()
	gen_btn.disabled = false
	gen_btn.text = "Generate my settings"
	summary.text = res.summary
	for c in insights.get_children():
		c.queue_free()
	for c in recs_box.get_children():
		c.queue_free()
	for t in res.insights:
		_label("• " + t, f_body, TEXT, true, insights)
	_recs = res.recs
	_rec_buttons = []
	if not res.ok:
		return
	if _recs.empty():
		_label("Your settings already fit how you play - nothing to change. Keep playing; Generate again later.", f_bold, CONF_COLORS.high, true, recs_box)
		return
	_label("Suggested for you:", f_bold, ACCENT, false, recs_box)
	for i in range(_recs.size()):
		_rec_card(_recs[i], i)
	if _recs.size() > 1:
		_button(recs_box, "Apply all", "_apply_all")

func _rec_card(r: Dictionary, i: int):
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	card.add_stylebox_override("panel", sb)
	recs_box.add_child(card)
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 12)
	card.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var t := _label("%s:  %s  to  %s" % [r.label, Advisor.fmt(r.key, r.from), Advisor.fmt(r.key, r.to)], f_bold, TEXT, false, top)
	t.size_flags_horizontal = 0
	var conf: String = r.get("conf", "try")
	_label("   (" + CONF_NAMES.get(conf, conf) + ")", f_body, CONF_COLORS.get(conf, TEXT), false, top)
	_label(r.why, f_body, DIM, true, v)
	var b := _button(h, "Apply", "_apply_one", [i])
	b.rect_min_size = Vector2(100, 36)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	_rec_buttons.append(b)

func _apply_one(i: int):
	if i < 0 or i >= _recs.size():
		return
	_apply([_recs[i]])
	if i < _rec_buttons.size() and is_instance_valid(_rec_buttons[i]):
		_rec_buttons[i].text = "Applied"
		_rec_buttons[i].disabled = true

func _apply_all():
	_apply(_recs)
	for b in _rec_buttons:
		if is_instance_valid(b):
			b.text = "Applied"
			b.disabled = true

func _apply(list: Array):
	var undo := {}
	for r in list:
		undo[r.key] = Rhythia.get(r.key)
		Rhythia.set(r.key, r.to)
	_save_undo(undo)
	_sync_controls()
	Rhythia.save_settings()
	Globals.notify(Globals.NOTIFY_SUCCEED, "Applied %d setting%s. Play a few maps with them, then Generate again." % [list.size(), "" if list.size() == 1 else "s"], "Settings Generator")

func _save_undo(undo: Dictionary):
	var f := File.new()
	var dir := Directory.new()
	var path: String = Globals.p(UNDO_FILE)
	if not dir.dir_exists(path.get_base_dir()):
		dir.make_dir_recursive(path.get_base_dir())
	if f.open(path, File.WRITE) == OK:
		f.store_string(var2str(undo))
		f.close()
	undo_btn.disabled = false

func _undo():
	var f := File.new()
	var path: String = Globals.p(UNDO_FILE)
	if f.open(path, File.READ) != OK:
		return
	var undo = str2var(f.get_as_text())
	f.close()
	Directory.new().remove(path)
	undo_btn.disabled = true
	if typeof(undo) != TYPE_DICTIONARY:
		return
	for k in undo:
		Rhythia.set(k, undo[k])
	_sync_controls()
	Rhythia.save_settings()
	Globals.notify(Globals.NOTIFY_SUCCEED, "Your previous settings are back.", "Settings Generator")

func _clear():
	Globals.confirm_prompt.open("Delete all %d tracked plays? The Settings Generator starts learning from zero." % PT.list_files().size(), "Clear tracked plays", [{text = "Cancel"}, {text = "Delete"}])
	var sel = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.close()
	if sel == 1:
		PT.clear_all()
		summary.text = "Tracked plays deleted."
		for c in insights.get_children():
			c.queue_free()
		for c in recs_box.get_children():
			c.queue_free()

# show the new values in the settings boxes (they'd put the old ones back)
func _sync_controls():
	var tabs = get_parent()
	if tabs == null:
		return
	var stack := [tabs]
	while not stack.empty():
		var n = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var sc = n.get_script()
		if n is SpinBox and sc != null and CONTROLS.has(sc.resource_path):
			var d: Array = CONTROLS[sc.resource_path]
			n.value = float(Rhythia.get(d[0])) * d[1]
		elif n is BaseButton and "target" in n and n.has_method("upd") and Advisor.TUNABLE.has(String(n.get("target"))):
			n.upd()

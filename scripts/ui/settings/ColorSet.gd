extends GridContainer

onready var base = $Color

var btns = {}

const FavoriteStar = preload("res://scripts/ui/settings/FavoriteStar.gd")
const FAV_NAME_COLOR = Color(1, 0.756863, 0.960784)

func _is_fav(cs) -> bool:
	return cs != null and Rhythia.favorite_colorsets.has(cs.id)

func upd(_c=null):
	for k in btns.keys():
		if not is_instance_valid(btns[k]): continue
		var v = (Rhythia.selected_colorset != null and k.id == Rhythia.selected_colorset.id)
		btns[k].get_node("Select").disabled = v
		var hi = btns[k].get_node_or_null("SelHi")
		if hi:
			hi.visible = v
			hi.update()
		if v: btns[k].self_modulate = Color(1,1,1)
		else: btns[k].self_modulate = Color(0.5,0.5,0.5)
		var fav = _is_fav(k)
		var star = btns[k].get_node_or_null("Fav")
		if star: star.fav = fav
		var nm = btns[k].get_node_or_null("Name")
		if nm:
			if fav: nm.add_color_override("font_color", FAV_NAME_COLOR)
			else: nm.set("custom_colors/font_color", null)

# The selected colorset's mark: an outline around its tile and a tick badge in
# the top left corner (the star is top right), in the Menu Customizer's accent.
func _draw_selected(hi: Control):
	var accent: Color = load("res://scripts/ui/menu/MenuStyle.gd").get_value("accent")
	accent.a = 1.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(accent.r, accent.g, accent.b, 0.10)
	box.border_color = accent
	box.set_border_width_all(3)
	box.set_corner_radius_all(6)
	box.anti_aliasing = true
	hi.draw_style_box(box, Rect2(Vector2(-3, -3), hi.rect_size + Vector2(6, 6)))
	var c := Vector2(13, 13)
	hi.draw_circle(c, 11, Color(0.08, 0.06, 0.1))
	hi.draw_circle(c, 9.5, accent)
	var dark := Color(0.1, 0.07, 0.12)
	hi.draw_polyline(PoolVector2Array([c + Vector2(-4.5, 0.5), c + Vector2(-1.2, 3.8), c + Vector2(5, -3.5)]), dark, 2.4, true)

# Favorites first (in registry order), then everything else (in registry order).
func _reorder():
	var favs = []
	var rest = []
	for cs in Rhythia.registry_colorset.items:
		if btns.has(cs) and is_instance_valid(btns[cs]) and btns[cs].get_parent() == self:
			if _is_fav(cs): favs.append(btns[cs])
			else: rest.append(btns[cs])
	var idx = 0
	if is_instance_valid(base) and base.get_parent() == self:
		move_child(base, 0)
		idx = 1
	for b in favs + rest:
		move_child(b, idx)
		idx += 1

func _toggle_fav(cs):
	if cs == null: return
	if Rhythia.favorite_colorsets.has(cs.id): Rhythia.favorite_colorsets.erase(cs.id)
	else: Rhythia.favorite_colorsets.append(cs.id)
	Rhythia.save_settings()
	upd()
	_reorder()

func col(): columns = rect_size.x / 100

func _ready():
	for cs in Rhythia.registry_colorset.items:
		add_set(cs, false)
	upd()
	call_deferred("_reorder")
	Rhythia.connect("selected_colorset_changed",self,"upd")
	connect("resized",self,"col")
	col()

func _fill_colors(btn, set):
	var color_grid = btn.get_node("Colors")
	var col_template = btn.get_node("Colors/T")
	var color_count = set.real_colors.size()
	if color_count == 3: color_grid.columns = 3
	elif color_count == 0: color_grid.columns = 1
	else: color_grid.columns = ceil(sqrt(float(color_count)))
	for c in set.real_colors:
		var colrect = col_template.duplicate()
		colrect.color = c
		colrect.visible = true
		color_grid.call_deferred("add_child",colrect)

# Redraws a colorset button after its colors changed (colorset maker).
func refresh_set(set):
	if not btns.has(set):
		add_set(set)
		return
	var btn = btns[set]
	for c in btn.get_node("Colors").get_children():
		if c.name != "T": c.queue_free()
	btn.get_node("Mirror").visible = set.mirror
	_fill_colors(btn, set)

func add_set(cs, update: bool = true):
	if true:
		var set:ColorSet = cs
		var btn = $Color.duplicate()
		btn.get_node("Name").text = set.name
		btn.visible = true
		
		var sel = btn.get_node("Select")
		btn.get_node("Mirror").visible = set.mirror
		sel.hint_tooltip = set.name + "\nby " + set.creator
		_fill_colors(btn, set)
		
#		var even_v = fmod(color_grid.columns,2)
#		var even_h = fmod(ceil(color_count / color_grid.columns),2)
#		color_grid.set("custom_constants/vseparation",even_v+1)
#		color_grid.set("custom_constants/vseparation",even_h+1)
		
		sel.connect("pressed",Rhythia,"select_colorset",[cs])
		var star = FavoriteStar.new()
		star.name = "Fav"
		star.anchor_left = 1.0
		star.anchor_right = 1.0
		star.margin_left = -27
		star.margin_right = -5
		star.margin_top = 5
		star.margin_bottom = 27
		star.fav = _is_fav(cs)
		star.connect("pressed", self, "_toggle_fav", [cs])
		btn.add_child(star)
		# the one in use: an outline in the menu's accent colour and a tick
		var hi = Control.new()
		hi.name = "SelHi"
		hi.anchor_right = 1.0
		hi.anchor_bottom = 1.0
		hi.mouse_filter = MOUSE_FILTER_IGNORE
		hi.visible = false
		hi.connect("draw", self, "_draw_selected", [hi])
		btn.add_child(hi)
		btns[cs] = btn
		call_deferred("add_child",btn)
	if update:
		call_deferred("upd")
		call_deferred("_reorder")

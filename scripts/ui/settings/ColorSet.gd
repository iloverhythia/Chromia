extends Control
# The colorset picker (Settings > Colorsets): a tile for every colorset, the
# favourites first, with a switch to show only the favourites.
#
# The whole grid is drawn by this one control, and only the rows on screen.
# It used to be a tile of a dozen or more controls for every colorset (a
# square for each colour, the name, the star, the frame, a button with a
# moving shine): with a couple of hundred colorsets that was three and a half
# thousand controls made when the menu loaded, and the sixty or so tiles on
# screen were about a thousand separate draws every frame, which a headset
# can't keep up with. Drawn here in passes over all the tiles on screen (their
# squares, then their frames, then their names, then their stars), the same
# picture is a handful of draws.
#
# The hidden "Color" tile of the scene is still where the look comes from (its
# fonts, its picture, its styles), so the Settings looks that restyle the page
# (New Settings UI, the menu's outlines) still reach it.
#
# (Other scripts call add_set / refresh_set / upd.)

onready var base = $Color

var btns = {} # (was: colorset -> its tile. Nothing is kept per colorset now)

const FAV_NAME_COLOR = Color(1, 0.756863, 0.960784)
const STAR_FAV = Color(1, 0.756863, 0.960784)
const STAR_OFF = Color(0.898039, 0.94902, 1, 0.55)
const STAR_OFF_HOVER = Color(0.898039, 0.94902, 1, 0.85)
const TILE := 96.0
const HGAP := 4.0
const VGAP := 42.0 # (the name is written above its tile)
const NAME_H := 34.0
const TOP := 12.0 # (room above the first row: its names reach up, and the switch is right above)
const STAR := Rect2(69, 5, 22, 22) # where the star is in a tile
const CFG := "user://settings.cfg"

var _order := [] # the colorsets shown, in order
var _cols := 1
var _scroll: ScrollContainer = null
var _favs_only := false
var _fav_box: CheckBox = null
var _empty: Label = null
var _under: Control = null # the tiles' backs, drawn behind everything
var _shine: Panel = null # the selected tile's moving shine
var _over: Control = null # what the pointer is on
var _hover := -1
var _hover_star := false
var _first := 0 # the tiles drawn: _first .. _last - 1
var _last := 0
var _seen_top := -1.0e9
var _check := 0.0
var _lines := {} # a name's lines, as they fit over a tile: key -> [[text, width]]
var _star_pts := PoolVector2Array()
var _star_line := PoolVector2Array()
var _star_vp: Viewport = null # the two stars (favourite, not), drawn once into a picture

func _is_fav(cs) -> bool:
	return cs != null and Rhythia.favorite_colorsets.has(cs.id)

func _selected(cs) -> bool:
	return Rhythia.selected_colorset != null and cs.id == Rhythia.selected_colorset.id

func upd(_c = null):
	_place_marks()
	update()

func _toggle_fav(cs):
	if cs == null: return
	if Rhythia.favorite_colorsets.has(cs.id): Rhythia.favorite_colorsets.erase(cs.id)
	else: Rhythia.favorite_colorsets.append(cs.id)
	Rhythia.save_settings()
	_relayout()

# --- the order, and where each tile goes ----------------------------------------------

# Favorites first (in registry order), then everything else (in registry
# order); with "Only show favorites", the favorites alone.
func _sorted() -> Array:
	var favs := []
	var rest := []
	for cs in Rhythia.registry_colorset.items:
		if _is_fav(cs):
			favs.append(cs)
		elif not _favs_only:
			rest.append(cs)
	return favs + rest

func _tile_at(i: int) -> Vector2:
	return Vector2((i % _cols) * (TILE + HGAP), TOP + (i / _cols) * (TILE + VGAP))

func _relayout(_a = null):
	_order = _sorted()
	_cols = int(max(1.0, floor((rect_size.x + HGAP) / (TILE + HGAP))))
	var rows := int(ceil(_order.size() / float(_cols)))
	var h: float = max(0.0, TOP + rows * (TILE + VGAP) - VGAP)
	if _empty != null:
		_empty.visible = _order.empty()
		if _order.empty():
			_empty.text = "No favorites yet. Turn \"Only show favorites\" off and press the star on a colorset to add it." if _favs_only else "No colorsets."
			h = 40.0
	if rect_min_size.y != h:
		rect_min_size.y = h
	_hover = -1
	_show_visible(true)

# where the page's scroll area starts and ends, in this grid's own measure
func _view() -> Array:
	if _scroll == null or not is_instance_valid(_scroll):
		return [-1.0e9, 1.0e9]
	var inv: Transform2D = get_global_transform().affine_inverse()
	var r: Rect2 = _scroll.get_global_rect()
	return [inv.xform(r.position).y, inv.xform(r.end).y]

# which tiles are on screen (and a row above and below): drawn again when that changes
func _show_visible(force = false):
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var step := TILE + VGAP
	var view := _view()
	_seen_top = view[0]
	var first := int(clamp(floor((view[0] - TOP) / step) - 1.0, 0.0, 1.0e6)) * _cols
	var last := int(min(float(_order.size()), (clamp(floor((view[1] - TOP) / step), -1.0, 1.0e6) + 2.0) * _cols))
	first = int(min(first, last))
	if typeof(force) == TYPE_BOOL and force == false and first == _first and last == _last:
		return
	_first = first
	_last = last
	_place_marks()
	update()
	if _under != null:
		_under.update()

func _on_scrolled(_v = null):
	_show_visible()

func _on_shown():
	_show_visible(true)

func _process(delta):
	# (the page moved under the scroll area without the scrollbar saying so: a
	# section above was folded, the window resized)
	_check += delta
	if _check >= 0.25:
		_check = 0.0
		if is_visible_in_tree() and abs(_view()[0] - _seen_top) > 1.0:
			_show_visible()

func _hook_scroll():
	var p = get_parent()
	while p != null and not (p is ScrollContainer):
		p = p.get_parent()
	_scroll = p
	if _scroll != null:
		_scroll.get_v_scrollbar().connect("value_changed", self, "_on_scrolled")
		_scroll.connect("resized", self, "_on_scrolled")
	_show_visible(true)

# --- the switch above the grid ---------------------------------------------------------

func _load_favs_only() -> bool:
	var config = ConfigFile.new()
	if config.load(CFG) != OK:
		return false
	return bool(config.get_value("ui", "colorsets_favorites_only", false))

func _on_favs_only(on: bool):
	_favs_only = on
	var config = ConfigFile.new()
	config.load(CFG)
	config.set_value("ui", "colorsets_favorites_only", on)
	config.save(CFG)
	_relayout()

func _add_fav_box():
	var holder = get_parent()
	if holder == null or holder.has_node("FavOnly"):
		return
	var row := HBoxContainer.new()
	row.name = "FavOnly"
	_fav_box = CheckBox.new()
	_fav_box.text = "Only show favorites"
	_fav_box.hint_tooltip = "Show only the colorsets you starred (the star in a tile's corner)."
	_fav_box.theme = load("res://uitheme.tres")
	_fav_box.focus_mode = FOCUS_NONE
	_fav_box.pressed = _favs_only
	_fav_box.connect("toggled", self, "_on_favs_only")
	row.add_child(_fav_box)
	holder.add_child(row)
	var spacer = holder.get_node_or_null("MarginContainer")
	if spacer != null:
		holder.move_child(row, spacer.get_index())
	row.visible = not bool(holder.get("collapsed"))

# --- setting up --------------------------------------------------------------------------

func _ready():
	mouse_filter = MOUSE_FILTER_PASS
	# a star's shape, in its 22 x 22 corner of a tile
	var c := STAR.size / 2.0
	var r_out: float = min(STAR.size.x, STAR.size.y) * 0.46
	for i in 10:
		var ang: float = -PI / 2.0 + i * PI / 5.0
		_star_pts.append(c + Vector2(cos(ang), sin(ang)) * (r_out if i % 2 == 0 else r_out * 0.45))
	_star_line = PoolVector2Array(_star_pts)
	_star_line.append(_star_pts[0])
	# The stars, as a picture: a star's smooth outline is a draw of its own
	# every time, sixty of them on a page; drawn once here (a favourite's on
	# the left, the other on the right, at twice the size) they are all one.
	_star_vp = Viewport.new()
	_star_vp.size = STAR.size * 2.0 * Vector2(2, 1)
	_star_vp.transparent_bg = true
	_star_vp.usage = Viewport.USAGE_2D
	_star_vp.disable_3d = true
	_star_vp.render_target_v_flip = true
	_star_vp.render_target_update_mode = Viewport.UPDATE_ONCE
	var sheet := Control.new()
	sheet.connect("draw", self, "_draw_star_sheet", [sheet])
	_star_vp.add_child(sheet)
	add_child(_star_vp)
	_star_vp.get_texture().flags = Texture.FLAG_FILTER
	get_tree().create_timer(0.15).connect("timeout", self, "update") # (once the picture is there)
	# the tiles' backs (the scene's tile picture), behind everything else
	_under = Control.new()
	_under.name = "Under"
	_under.show_behind_parent = true
	_under.mouse_filter = MOUSE_FILTER_IGNORE
	_under.connect("draw", self, "_draw_under")
	add_child(_under)
	# the selected tile's moving shine: the scene's own look for it (the tile
	# button's "disabled" style and its shader, calmer: half as strong and
	# slower), on the one tile that shows it
	var sel0: Button = base.get_node("Select")
	_shine = Panel.new()
	_shine.name = "Shine"
	_shine.show_behind_parent = true
	_shine.mouse_filter = MOUSE_FILTER_IGNORE
	_shine.add_stylebox_override("panel", sel0.get_stylebox("disabled"))
	_shine.material = sel0.material
	if _shine.material is ShaderMaterial:
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\n\nvoid fragment() {\n\tvec2 uv = UV + vec2(TIME * -0.12);\n\tCOLOR.rgb = texture(TEXTURE,UV).rgb * (0.88 + (0.12 * sin(length(uv*6.285))));\n}"
		_shine.material.shader = sh
	_shine.rect_size = Vector2(TILE, TILE)
	_shine.visible = false
	add_child(_shine)
	# what the pointer is on, over the grid
	_over = Control.new()
	_over.name = "Over"
	_over.mouse_filter = MOUSE_FILTER_IGNORE
	_over.rect_size = Vector2(TILE, TILE)
	_over.visible = false
	_over.connect("draw", self, "_draw_over")
	add_child(_over)
	_favs_only = _load_favs_only()
	_empty = Label.new()
	_empty.anchor_right = 1.0
	_empty.autowrap = true
	_empty.modulate = Color(1, 1, 1, 0.6)
	_empty.visible = false
	add_child(_empty)
	Rhythia.connect("selected_colorset_changed", self, "upd")
	connect("resized", self, "_relayout")
	connect("visibility_changed", self, "_on_shown")
	connect("mouse_exited", self, "_set_hover", [-1, false])
	call_deferred("_add_fav_box")
	call_deferred("_hook_scroll")
	_relayout()

# the shine and the pointer's mark, on their tiles
func _place_marks():
	if _shine != null:
		var at := -1
		for i in range(_first, _last):
			if _selected(_order[i]):
				at = i
				break
		_shine.visible = at >= 0
		if at >= 0:
			_shine.rect_position = _tile_at(at)
	if _over != null:
		var on: bool = _hover >= _first and _hover < _last
		_over.visible = on
		if on:
			_over.rect_position = _tile_at(_hover)
			_over.update()

# --- drawing -----------------------------------------------------------------------------

func _draw_under():
	var tex: Texture = base.get_node("TextureRect").texture
	if tex == null:
		return
	# (the scene's tile picture at half brightness, as its own shader left it near the edges)
	var dim := Color(0.44, 0.44, 0.44)
	for i in range(_first, _last):
		_under.draw_texture_rect(tex, Rect2(_tile_at(i) + Vector2(3, 3), Vector2(TILE - 6, TILE - 6)), false, dim)

# a name's lines as they fit over a tile (the first two that fit, like the label it was)
func _name_lines(name: String, font: Font) -> Array:
	var key := "%s|%d" % [name, font.get_instance_id()]
	if _lines.has(key):
		return _lines[key]
	var max_lines := int(max(1.0, floor(NAME_H / font.get_height())))
	var out := []
	var line := ""
	for word in name.split(" ", false):
		var tryl: String = word if line == "" else line + " " + word
		if font.get_string_size(tryl).x <= TILE or line == "":
			line = tryl
		else:
			out.append(line)
			line = word
	if line != "":
		out.append(line)
	out = out.slice(0, max_lines - 1) if out.size() > max_lines else out
	var res := []
	for l in out:
		var text: String = l
		while text.length() > 1 and font.get_string_size(text).x > TILE:
			text = text.substr(0, text.length() - 1) # (one word wider than the tile: cut)
		res.append([text, font.get_string_size(text).x])
	if _lines.size() > 2000:
		_lines.clear()
	_lines[key] = res
	return res

# a text's characters, as one pass (their outlines, or the characters themselves)
func _chars(font: Font, at: Vector2, text: String, col: Color, outline: bool):
	var ci := get_canvas_item()
	var x := 0.0
	for k in range(text.length()):
		x += font.draw_char(ci, at + Vector2(x, 0), text.ord_at(k), text.ord_at(k + 1) if k + 1 < text.length() else -1, col, outline)

func _draw():
	if _order.empty() or _last <= _first:
		return
	var name_l: Label = base.get_node("Name")
	var name_font: Font = name_l.get_font("font")
	var name_col: Color = name_l.get_color("font_color")
	var mirror_l: Label = base.get_node("Mirror")
	var mirror_font: Font = mirror_l.get_font("font")
	var mirror_col: Color = mirror_l.get_color("font_color")
	# 1: every tile's colour squares
	for i in range(_first, _last):
		var cs = _order[i]
		var at := _tile_at(i)
		var n: int = cs.real_colors.size()
		if n == 0:
			continue
		var cols: int = 3 if n == 3 else int(ceil(sqrt(float(n))))
		var rows := int(ceil(n / float(cols)))
		var cw: float = (TILE - 10.0 - (cols - 1)) / cols
		var ch: float = (TILE - 9.0 - (rows - 1)) / rows
		for k in range(n):
			var x0: float = round(5.0 + (k % cols) * (cw + 1.0))
			var y0: float = round(5.0 + (k / cols) * (ch + 1.0))
			var x1: float = round(5.0 + (k % cols) * (cw + 1.0) + cw)
			var y1: float = round(5.0 + (k / cols) * (ch + 1.0) + ch)
			draw_rect(Rect2(at + Vector2(x0, y0), Vector2(x1 - x0, y1 - y0)), cs.real_colors[k])
	# 2: their frames (grey; the selected one white)
	for i in range(_first, _last):
		var at := _tile_at(i)
		var col := Color(1, 1, 1) if _selected(_order[i]) else Color(0.5, 0.5, 0.5)
		draw_rect(Rect2(at, Vector2(TILE, 3)), col)
		draw_rect(Rect2(at + Vector2(0, TILE - 3), Vector2(TILE, 3)), col)
		draw_rect(Rect2(at + Vector2(0, 3), Vector2(3, TILE - 6)), col)
		draw_rect(Rect2(at + Vector2(TILE - 3, 3), Vector2(3, TILE - 6)), col)
	# 3: their names above them, and the M of a mirrored one (outlines first, then the letters)
	var texts := [] # [font, where, text, colour]
	var line_h: float = name_font.get_height()
	for i in range(_first, _last):
		var cs = _order[i]
		var at := _tile_at(i)
		var lines: Array = _name_lines(String(cs.name), name_font)
		var top: float = at.y - 2.0 - lines.size() * line_h
		var col: Color = FAV_NAME_COLOR if _is_fav(cs) else name_col
		for j in range(lines.size()):
			texts.append([name_font, Vector2(round(at.x + (TILE - lines[j][1]) / 2.0), round(top + j * line_h + name_font.get_ascent())), lines[j][0], col])
		if cs.mirror:
			var w: float = mirror_font.get_string_size("M").x
			texts.append([mirror_font, Vector2(at.x + TILE - 7.0 - w, at.y + TILE - 6.0 - mirror_font.get_descent()), "M", mirror_col])
	for outline in [true, false]:
		for t in texts:
			var f: Font = t[0]
			if outline and not f.has_outline():
				continue
			_chars(f, t[1], t[2], Color(1, 1, 1) if outline else t[3], outline)
	# 4: their stars
	var stars: Texture = _star_vp.get_texture()
	var cell: Vector2 = STAR.size * 2.0
	for i in range(_first, _last):
		draw_texture_rect_region(stars, Rect2(_tile_at(i) + STAR.position, STAR.size), Rect2(Vector2(0 if _is_fav(_order[i]) else cell.x, 0), cell))
	# 5: the selected one's mark: an outline in the menu's accent colour and a tick
	for i in range(_first, _last):
		if _selected(_order[i]):
			_draw_selected(_tile_at(i))

func _draw_star_sheet(sheet: Control):
	_draw_star(sheet, Vector2.ZERO, true, false, 2.0)
	_draw_star(sheet, Vector2(STAR.size.x * 2.0, 0), false, false, 2.0)

func _draw_star(on: CanvasItem, at: Vector2, fav: bool, hover: bool, k: float = 1.0):
	on.draw_set_transform(at, 0.0, Vector2(k, k))
	if fav:
		on.draw_colored_polygon(_star_pts, STAR_FAV)
		on.draw_polyline(_star_line, Color(0.25, 0.12, 0.25, 0.9), 1.5, true)
	else:
		if hover:
			on.draw_colored_polygon(_star_pts, Color(1, 0.756863, 0.960784, 0.25))
		on.draw_polyline(_star_line, Color(0, 0, 0, 0.45), 3.0, true)
		on.draw_polyline(_star_line, STAR_OFF_HOVER if hover else STAR_OFF, 1.5, true)
	on.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# The selected colorset's mark: an outline around its tile and a tick badge in
# the top left corner (the star is top right), in the Menu Customizer's accent.
func _draw_selected(at: Vector2):
	var accent: Color = load("res://scripts/ui/menu/MenuStyle.gd").get_value("accent")
	accent.a = 1.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(accent.r, accent.g, accent.b, 0.10)
	box.border_color = accent
	box.set_border_width_all(3)
	box.set_corner_radius_all(6)
	box.anti_aliasing = true
	draw_style_box(box, Rect2(at + Vector2(-3, -3), Vector2(TILE, TILE) + Vector2(6, 6)))
	var c := at + Vector2(13, 13)
	draw_circle(c, 11, Color(0.08, 0.06, 0.1))
	draw_circle(c, 9.5, accent)
	var dark := Color(0.1, 0.07, 0.12)
	draw_polyline(PoolVector2Array([c + Vector2(-4.5, 0.5), c + Vector2(-1.2, 3.8), c + Vector2(5, -3.5)]), dark, 2.4, true)

# the tile the pointer is on: a little lighter, its star lit when the pointer is on that
func _draw_over():
	if _hover < 0 or _hover >= _order.size():
		return
	var cs = _order[_hover]
	if not _selected(cs):
		_over.draw_rect(Rect2(Vector2.ZERO, Vector2(TILE, TILE)), Color(0.6, 0.6, 0.6, 0.0941176))
	if _hover_star:
		_draw_star(_over, STAR.position, _is_fav(cs), true)

# --- the pointer ---------------------------------------------------------------------------

# which tile is at a point (-1: none), and whether the point is on its star
func _hit(p: Vector2) -> Array:
	if p.x < 0 or p.y < TOP:
		return [-1, false]
	var col := int(p.x / (TILE + HGAP))
	var row := int((p.y - TOP) / (TILE + VGAP))
	var inside := p - Vector2(col * (TILE + HGAP), TOP + row * (TILE + VGAP))
	if col >= _cols or inside.x > TILE or inside.y > TILE:
		return [-1, false]
	var i := row * _cols + col
	if i >= _order.size():
		return [-1, false]
	return [i, STAR.grow(3).has_point(inside)]

func _set_hover(i: int, star: bool):
	if i == _hover and star == _hover_star:
		return
	_hover = i
	_hover_star = star
	if i >= 0:
		var cs = _order[i]
		hint_tooltip = ("Remove from favorites" if _is_fav(cs) else "Add to favorites (shown first)") if star else String(cs.name) + "\nby " + String(cs.creator)
		mouse_default_cursor_shape = CURSOR_ARROW if (_selected(cs) and not star) else CURSOR_POINTING_HAND
	else:
		hint_tooltip = ""
		mouse_default_cursor_shape = CURSOR_ARROW
	_place_marks()

func _gui_input(ev):
	if ev is InputEventMouseMotion:
		var h := _hit(ev.position)
		_set_hover(h[0], h[1])
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == BUTTON_LEFT:
		var h := _hit(ev.position)
		if h[0] < 0:
			return
		var cs = _order[h[0]]
		if h[1]:
			_toggle_fav(cs)
		elif not _selected(cs):
			Rhythia.select_colorset(cs)
		accept_event()

# --- for the colorset maker ------------------------------------------------------------------

# A colorset's colours changed.
func refresh_set(_set):
	_relayout()

# A colorset that is new in the registry (colorset maker, an import).
func add_set(_cs, _update: bool = true):
	call_deferred("_relayout")

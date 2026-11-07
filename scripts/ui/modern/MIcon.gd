extends Control

# Outlined icons for the Modern UI (ModernUI.gd), drawn as lines in a 24x24
# box scaled to the control: heart, gear, cloud_down, list, sort, bookmark_plus,
# layout, eye, pause, play, star, cloud, layers, clock, users, skull, hand,
# ghost, shuffle, disc, mirror, glasses, search, x, chevron_right, chevron_left,
# plus, check, trophy, user, globe, monitor, keyboard, mouse, volume, image,
# radio, square, sparkles, palette, folder, music.

var icon := "heart"
var color := Color(0.85, 0.85, 0.9)
var stroke := 2.0
var filled := false

static func make(name: String, size: float, col: Color = Color(0.85, 0.85, 0.9), width: float = 2.0) -> Control:
	var c = load("res://scripts/ui/modern/MIcon.gd").new()
	c.icon = name
	c.color = col
	c.stroke = width
	c.rect_min_size = Vector2(size, size)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func set_icon(n: String):
	icon = n
	update()

func set_color(c: Color):
	color = c
	update()

var _s := 1.0
var _o := Vector2()
func _p(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _s

func _w() -> float:
	return stroke * clamp(_s, 0.75, 1.6)

func _line(pts: Array, closed := false):
	var arr := PoolVector2Array()
	for q in pts:
		arr.append(_p(q[0], q[1]))
	if closed and pts.size() > 0:
		arr.append(_p(pts[0][0], pts[0][1]))
	draw_polyline(arr, color, _w(), true)

func _circle(cx: float, cy: float, r: float, fill := false):
	if fill:
		draw_circle(_p(cx, cy), r * _s, color)
	else:
		draw_arc(_p(cx, cy), r * _s, 0, TAU, 32, color, _w(), true)

func _arc(cx: float, cy: float, r: float, a0: float, a1: float):
	draw_arc(_p(cx, cy), r * _s, deg2rad(a0), deg2rad(a1), 24, color, _w(), true)

func _rrect(x: float, y: float, w: float, h: float, r: float):
	var pts := []
	var steps := 5
	for corner in [[x + w - r, y + r, -90], [x + w - r, y + h - r, 0], [x + r, y + h - r, 90], [x + r, y + r, 180]]:
		for i in range(steps + 1):
			var a: float = deg2rad(corner[2] + 90.0 * i / steps)
			pts.append([corner[0] + cos(a) * r, corner[1] + sin(a) * r])
	_line(pts, true)

# the icons are pictures (Lucide icons, assets/images/ui/modern, ISC licence:
# LUCIDE_LICENSE.txt there), drawn smooth at any size; the line drawings below
# are only for a name with no picture
const DIR := "res://assets/images/ui/modern/"
static func tex(name: String) -> Texture:
	# (made once per icon, kept on the Engine: smooth when drawn small)
	if not Engine.has_meta("micon_cache"):
		Engine.set_meta("micon_cache", {})
	var cache: Dictionary = Engine.get_meta("micon_cache")
	if cache.has(name):
		return cache[name]
	var p: String = DIR + name + ".png"
	var t: Texture = null
	if ResourceLoader.exists(p):
		var src = load(p) as Texture
		if src != null:
			var img: Image = src.get_data()
			if img != null:
				img.clear_mipmaps()
				img.convert(Image.FORMAT_RGBA8)
				var it := ImageTexture.new()
				it.create_from_image(img, Texture.FLAG_FILTER | Texture.FLAG_MIPMAPS)
				t = it
	cache[name] = t
	return t

func _draw():
	var t = tex(icon + ("_fill" if filled else ""))
	if t == null and filled:
		t = tex(icon)
	if t != null:
		var side0: float = min(rect_size.x, rect_size.y)
		draw_texture_rect(t, Rect2((rect_size - Vector2(side0, side0)) / 2.0, Vector2(side0, side0)), false, color)
		return
	var side: float = min(rect_size.x, rect_size.y)
	_s = side / 24.0
	_o = (rect_size - Vector2(side, side)) / 2.0
	match icon:
		"heart":
			var pts := []
			for i in range(0, 181, 15):
				var a := deg2rad(180 + i)
				pts.append([8 + cos(a) * 4.5, 9 + sin(a) * 4.5])
			for i in range(0, 181, 15):
				var a := deg2rad(180 + i)
				pts.append([16 + cos(a) * 4.5, 9 + sin(a) * 4.5])
			pts.append([12, 20.5])
			pts.append([3.5, 9])
			if filled:
				var poly := PoolVector2Array()
				for q in pts: poly.append(_p(q[0], q[1]))
				draw_colored_polygon(poly, color)
			_line(pts, true)
		"gear":
			var pts := []
			for i in range(48):
				var a := TAU * i / 48.0
				var tooth := 1.0 if (i % 6) in [0, 1, 2] else 0.0
				var r := 7.0 + tooth * 2.2
				pts.append([12 + cos(a) * r, 12 + sin(a) * r])
			_line(pts, true)
			_circle(12, 12, 3)
		"cloud", "cloud_down":
			_arc(8, 14, 4, 90, 270)
			_arc(12.5, 10, 5.5, 200, 340)
			_arc(17, 14, 4, -90, 90)
			_line([[8, 18], [17, 18]])
			if icon == "cloud_down":
				_line([[12, 11], [12, 21]])
				_line([[9, 18.5], [12, 21.5], [15, 18.5]])
		"list":
			for y in [6, 12, 18]:
				_line([[8, y], [21, y]])
				_circle(4, y, 0.9, true)
		"sort":
			_line([[7, 4], [7, 20]])
			_line([[4, 17], [7, 20], [10, 17]])
			_line([[13, 5], [19, 5]])
			_line([[13, 10], [17.5, 10]])
			_line([[13, 15], [16, 15]])
			_line([[13, 20], [14.5, 20]])
		"bookmark_plus":
			_line([[6, 3], [18, 3], [18, 21], [12, 17], [6, 21]], true)
			_line([[12, 7], [12, 13]])
			_line([[9, 10], [15, 10]])
		"layout":
			_rrect(3, 4, 18, 7, 2)
			_rrect(3, 13, 18, 7, 2)
		"eye":
			var pts := []
			for i in range(0, 361, 15):
				var a := deg2rad(i)
				pts.append([12 + cos(a) * 9.5, 12 + sin(a) * 5.5])
			_line(pts, true)
			_circle(12, 12, 2.8)
		"pause":
			_line([[8, 5], [8, 19]])
			_line([[16, 5], [16, 19]])
		"play":
			_line([[7, 4], [19, 12], [7, 20]], true)
		"star":
			var pts := []
			for i in range(10):
				var a := deg2rad(-90 + 36 * i)
				var r := 9.5 if i % 2 == 0 else 4.2
				pts.append([12 + cos(a) * r, 12.5 + sin(a) * r])
			if filled:
				var poly := PoolVector2Array()
				for q in pts: poly.append(_p(q[0], q[1]))
				draw_colored_polygon(poly, color)
			else:
				_line(pts, true)
		"layers":
			_line([[12, 3], [21, 8], [12, 13], [3, 8]], true)
			_line([[3, 12.5], [12, 17.5], [21, 12.5]])
			_line([[3, 16.5], [12, 21.5], [21, 16.5]])
		"clock":
			_circle(12, 12, 9)
			_line([[12, 7], [12, 12], [15.5, 14]])
		"users":
			_circle(9, 8, 3.5)
			_arc(9, 21, 6.5, 200, 340)
			_arc(16.5, 8, 3, -60, 90)
			_arc(17, 21, 5, 270, 340)
		"user":
			_circle(12, 8, 4)
			_arc(12, 22, 8, 200, 340)
		"skull":
			_arc(12, 11, 8, 150, 390)
			_line([[5.2, 15], [7, 17], [7, 21], [17, 21], [17, 17], [18.8, 15]])
			_circle(9, 11.5, 1.8)
			_circle(15, 11.5, 1.8)
			_line([[10.5, 21], [10.5, 18.5]])
			_line([[13.5, 21], [13.5, 18.5]])
		"hand":
			_line([[7, 13], [7, 6], [9, 5], [9, 11]])
			_line([[9, 6], [9, 4], [11, 3], [11, 11]])
			_line([[11, 5], [13, 4], [13, 11]])
			_line([[13, 6], [15, 6], [15, 12]])
			_line([[7, 13], [5, 11], [4, 13], [8, 19], [10, 21], [15, 21], [17, 17], [17, 10], [15, 10]])
		"ghost":
			_arc(12, 10, 7, 180, 360)
			_line([[5, 10], [5, 21], [7.5, 19], [10, 21], [12, 19], [14, 21], [16.5, 19], [19, 21], [19, 10]])
			_circle(9.5, 10, 0.9, true)
			_circle(14.5, 10, 0.9, true)
		"shuffle":
			_line([[3, 7], [7, 7], [15, 17], [20, 17]])
			_line([[3, 17], [7, 17], [9.5, 14]])
			_line([[12.5, 10], [15, 7], [20, 7]])
			_line([[17.5, 4.5], [20.5, 7], [17.5, 9.5]])
			_line([[17.5, 14.5], [20.5, 17], [17.5, 19.5]])
		"disc":
			_circle(12, 12, 9)
			_circle(12, 12, 3)
			_arc(12, 12, 6, 200, 260)
		"mirror":
			_line([[9, 3], [5, 3], [5, 21], [9, 21]])
			_line([[15, 3], [19, 3], [19, 21], [15, 21]])
			_line([[12, 2], [12, 22]])
		"glasses":
			_line([[2.5, 11], [21.5, 11]])
			_line([[6, 11], [8, 5], [16, 5], [18, 11]])
			_circle(7.5, 16, 3)
			_circle(16.5, 16, 3)
			_line([[10.5, 16], [13.5, 16]])
		"search":
			_circle(10.5, 10.5, 6.5)
			_line([[15.5, 15.5], [21, 21]])
		"x":
			_line([[5, 5], [19, 19]])
			_line([[19, 5], [5, 19]])
		"chevron_right":
			_line([[9, 5], [16, 12], [9, 19]])
		"chevron_left":
			_line([[15, 5], [8, 12], [15, 19]])
		"plus":
			_line([[12, 5], [12, 19]])
			_line([[5, 12], [19, 12]])
		"check":
			_line([[5, 12.5], [10, 17.5], [19.5, 7]])
		"trophy":
			_line([[7, 3], [17, 3], [17, 9], [12, 14], [7, 9]], true)
			_arc(6.5, 6.5, 3, 90, 270)
			_arc(17.5, 6.5, 3, -90, 90)
			_line([[12, 14], [12, 18]])
			_line([[8, 21], [16, 21], [15, 18], [9, 18]], true)
		"globe":
			_circle(12, 12, 9)
			_line([[3, 12], [21, 12]])
			var pts := []
			for i in range(0, 361, 20):
				var a := deg2rad(i)
				pts.append([12 + cos(a) * 4, 12 + sin(a) * 9])
			_line(pts, true)
		"monitor":
			_rrect(3, 4, 18, 12, 2)
			_line([[8, 20], [16, 20]])
			_line([[12, 16], [12, 20]])
		"keyboard":
			_rrect(2.5, 6, 19, 12, 2)
			for x in [6, 9, 12, 15, 18]:
				_circle(x, 10, 0.6, true)
			_line([[7, 14], [17, 14]])
		"mouse":
			_rrect(6, 3, 12, 18, 6)
			_line([[12, 7], [12, 10]])
		"volume":
			_line([[4, 9], [8, 9], [13, 5], [13, 19], [8, 15], [4, 15]], true)
			_arc(13, 12, 4, -50, 50)
			_arc(13, 12, 7.5, -50, 50)
		"image":
			_rrect(3, 4, 18, 16, 2)
			_circle(8.5, 9.5, 1.8)
			_line([[3.5, 18], [10, 12], [14, 16], [17, 13], [20.5, 16.5]])
		"radio":
			_circle(12, 12, 2)
			_arc(12, 12, 6, -50, 50)
			_arc(12, 12, 6, 130, 230)
			_arc(12, 12, 9.5, -50, 50)
			_arc(12, 12, 9.5, 130, 230)
		"square":
			_rrect(4, 4, 16, 16, 2.5)
		"sparkles":
			_line([[12, 3], [13.5, 10.5], [21, 12], [13.5, 13.5], [12, 21], [10.5, 13.5], [3, 12], [10.5, 10.5]], true)
		"palette":
			_arc(12, 12, 9, 40, 330)
			_line([[18.9, 6.3], [17, 9], [17.5, 12], [20.5, 13.5]])
			for q in [[8, 9], [12, 7], [7.5, 13.5]]:
				_circle(q[0], q[1], 1.2, true)
		"folder":
			_line([[3, 6], [9, 6], [11, 8], [21, 8], [21, 19], [3, 19]], true)
		"music":
			_line([[9, 18], [9, 5], [20, 3], [20, 16]])
			_circle(6.5, 18, 2.5)
			_circle(17.5, 16, 2.5)
		"refresh":
			_arc(12, 12, 8, 200, 470)
			_line([[4, 4], [4.2, 9.3], [9.5, 8.5]])
		_:
			_circle(12, 12, 8)

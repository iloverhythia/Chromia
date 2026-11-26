extends Node

# Picture frames (FrameDraw.gd), drawn once for everyone who shows the same one.
#
# A moving frame is a few hundred triangles worked out by script each time it
# is drawn. Every picture used to draw its own, about 30 times a second: with
# the Spectate window open and thirty players in it, that was most of each
# frame's time (three times slower here, and the reason the Spectate menu
# lagged in VR). Now each different frame (its look and colours) is drawn into
# a small picture of its own, and the profile pictures that show it just
# paste that picture: thirty players cost what the handful of different
# frames among them cost.
#
# A frame nobody shows any more stops being drawn after a second and is let
# go after half a minute. They move at up to 30 a second (15 on a Quest, in VR
# and on phones), and only one or two of them are drawn again in any one frame
# of the game, so many different frames on screen take turns.

const FD = preload("res://scripts/ui/FrameDraw.gd")
const SIZE := 192 # px, the cached picture (square)
const KEY := "chromia_frame_cache"
const IDLE_MS := 1000
const DROP_MS := 30000

class Painter extends Control:
	const FD2 = preload("res://scripts/ui/FrameDraw.gd")
	var frame := {}
	func _draw():
		var c := rect_size / 2.0
		FD2.draw(self, c, c.x / FD2.REACH, frame)

var _items := {} # key -> {vp, painter, used, drawn}

static func instance(tree: SceneTree) -> Node:
	if Engine.has_meta(KEY) and is_instance_valid(Engine.get_meta(KEY)):
		return Engine.get_meta(KEY)
	var n = load("res://scripts/ui/FrameCache.gd").new()
	n.name = "FrameCache"
	n.pause_mode = Node.PAUSE_MODE_PROCESS
	Engine.set_meta(KEY, n)
	tree.root.call_deferred("add_child", n)
	return n

static func key_of(fr: Dictionary) -> String:
	return "%s|%s|%s" % [String(fr.get("style", "")), fr.get("color", Color()).to_html(), fr.get("color2", Color()).to_html()]

# the picture of this frame (premultiplied: draw it with a CanvasItemMaterial
# set to BLEND_MODE_PREMULT_ALPHA), kept moving while someone asks for it
func texture_for(fr: Dictionary) -> Texture:
	var k := key_of(fr)
	var it = _items.get(k)
	if it == null:
		var vp := Viewport.new()
		vp.size = Vector2(SIZE, SIZE)
		vp.transparent_bg = true
		vp.usage = Viewport.USAGE_2D
		vp.disable_3d = true
		vp.render_target_v_flip = true
		vp.render_target_clear_mode = Viewport.CLEAR_MODE_ALWAYS
		vp.render_target_update_mode = Viewport.UPDATE_ONCE
		var p := Painter.new()
		p.frame = fr
		p.rect_size = Vector2(SIZE, SIZE)
		vp.add_child(p)
		add_child(vp)
		var tex := vp.get_texture()
		tex.flags = Texture.FLAG_FILTER
		it = {"vp": vp, "painter": p, "used": OS.get_ticks_msec(), "drawn": 0, "tex": tex}
		_items[k] = it
	it.used = OS.get_ticks_msec()
	return it.tex

# (a picture that shows it says so now and then: FrameView)
# -> false when it was let go (nobody showed it for a while): draw it again
func touch(fr: Dictionary) -> bool:
	var it = _items.get(key_of(fr))
	if it != null:
		it.used = OS.get_ticks_msec()
		return true
	return false

func _process(_delta):
	if _items.empty():
		return
	var now := OS.get_ticks_msec()
	var slow: bool = Rhythia.vr or OS.has_feature("quest") or Rhythia.dev == "mobile"
	var step: int = 66 if slow else 33
	# At most one of them is drawn again in a frame of the game (two on a
	# computer), the one that has waited longest: however many different
	# frames are showing, a frame of the game pays for one. (All of them at
	# once, 30 times a second, was the lag this file is here to end.)
	var left: int = 1 if slow else 2
	var due := []
	for k in _items.keys():
		var it: Dictionary = _items[k]
		var idle: int = now - int(it.used)
		if idle > DROP_MS:
			it.vp.queue_free()
			_items.erase(k)
			continue
		if idle > IDLE_MS:
			continue # (nobody looking: it stays as it is)
		if now - int(it.drawn) >= step:
			due.append(it)
	while left > 0 and not due.empty():
		var oldest := 0
		for i in range(1, due.size()):
			if int(due[i].drawn) < int(due[oldest].drawn):
				oldest = i
		var it: Dictionary = due[oldest]
		due.remove(oldest)
		it.drawn = now
		it.painter.update()
		it.vp.render_target_update_mode = Viewport.UPDATE_ONCE
		left -= 1

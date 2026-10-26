extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Heartscape" (HeartscapeScript): on every hit a heart
# bursts out of one of the pads (a short flipbook of frames).

var pads = []
var last_pad = 0
var frames = []

func _init():
	slug = "heartscape"

func space_init():
	var p = space_obj.child("SpawnPads")
	pads = p.kids() if p != null else []
	last_pad = pads.size()

func space_load():
	frames = []
	var h = space_obj.child("Hit")
	if h == null:
		return
	var i = 1
	while true:
		var f = h.child(str(i))
		if f == null:
			break
		f.visible = false
		frames.append(f)
		i += 1

func space_hit(_col):
	if pads.empty() or frames.empty():
		return
	var i = last_pad % pads.size()
	var pad = pads[i]
	last_pad = i + 1
	var s: Vector3 = pad.size
	var at: Vector3 = pad.get_cframe().xform(Vector3(rand() * s.x - s.x / 2, rand() * s.y - s.y / 2, rand() * s.z - s.z / 2))
	_show_frame(0, at)

func _show_frame(i: int, at: Vector3):
	if i >= frames.size():
		return
	var f = frames[i].clone_obj()
	f.visible = true
	f.set_parent_obj(space_obj.child("Hit"))
	var p: Transform = f.get_pivot()
	p.origin = at
	f.pivot_to(p)
	after(0.08, f, "destroy")
	after(0.08, self, "_show_frame", [i + 1, at])

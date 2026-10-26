extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Dojo" (DojoScript): the paper-wall lights take the note
# colour on every hit and a sword slash flashes out of one of the pads.

var pads = []
var last_pad = 0
var frames = []

func _init():
	slug = "dojo"

func space_init():
	var p = space_obj.child("SpawnPads")
	pads = p.kids() if p != null else []
	last_pad = pads.size()

func space_load():
	frames = []
	var h = space_obj.child("Slice")
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

func space_hit(col):
	group_color("light", col)
	if not env_effects or pads.empty() or frames.empty():
		return
	var i = last_pad % pads.size()
	var pad = pads[i]
	last_pad = i + 1
	var s: Vector3 = pad.size
	var at: Vector3 = pad.get_cframe().xform(Vector3(rand() * s.x - s.x / 2, rand() * s.y - s.y / 2, rand() * s.z - s.z / 2))
	_show_frame(0, at, up_vector(pad.get_cframe()))

func _show_frame(i: int, at: Vector3, up: Vector3):
	if i >= frames.size():
		return
	var f = frames[i].clone_obj()
	f.visible = true
	f.set_parent_obj(space_obj.child("Slice"))
	var p: Transform = f.get_pivot()
	p.origin = at
	f.pivot_to(p)
	if i == 0:
		# the first frame slides along the pad's up direction for 0.1 s
		tween(f, {"Pivot": moved(p, up * 10)}, 0.1)
	var hold = 0.14 if i == 0 else 0.04
	after(hold, f, "destroy")
	after(hold, self, "_show_frame", [i + 1, at + (up * 10 if i == 0 else Vector3()), up])

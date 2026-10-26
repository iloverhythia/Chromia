extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Skull" (SkullScript): the reaper's scythe and arm swing
# slowly; its eyes, the scythe's edge and the smoke flash in the note colour on
# every hit. (The original hand animation is private on Roblox, so the arm only swings.)

var scythe
var arm
var cf1 = Transform()
var cf2 = Transform()

func _init():
	slug = "skull"

func space_init():
	scythe = space_obj.at("Dynamic/Scythe")
	arm = space_obj.at("Dynamic/Arm")
	if scythe != null:
		cf1 = scythe.get_pivot()
	if arm != null:
		cf2 = arm.get_pivot()
	for p in ["Dynamic/Eyes/Neon1", "Dynamic/Eyes/Neon2", "Dynamic/Scythe/Neon"]:
		var o = space_obj.at(p)
		if o != null:
			o.set_color(Color(1, 0, 0))

func space_update(_dt):
	var t = now()
	var a = fmod(t / 6.0, 1.0) * PI * 2
	var b = fmod((t + 0.25) / 6.0, 1.0) * PI * 2
	var k1 = 1.0 - (cos(a) + 1) / 2
	var k2 = 1.0 - (cos(b) + 1) / 2
	if scythe != null:
		scythe.pivot_to(cf1 * cfa(deg2rad(-k1 * 15), 0, 0))
	if arm != null:
		arm.pivot_to(cf2 * cfa(deg2rad(-k2 * 15), 0, 0))

func space_hit(col):
	tween(group_obj("smoke"), {"Color": col}, 0.15)
	for p in ["Dynamic/Eyes/Neon1", "Dynamic/Eyes/Neon2", "Dynamic/Scythe/Neon"]:
		var o = space_obj.at(p)
		if o != null:
			tween(o, {"Color": col}, 0.15)

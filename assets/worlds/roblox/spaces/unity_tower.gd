extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Unity Tower" (UnityTowerSpace): floating islands and
# debris drift and sway around the tower, a black hole swirls behind it; the
# tower's neon and the swirl take the note colour on every hit.

var swirl
var swirl_decal
var smoke
var smoke_col = Color(1, 1, 1)
var props = [] # [object, start cframe, factor, is model]
var passed = 0.0

func _init():
	slug = "unity_tower"

func space_init():
	swirl = space_obj.child("BlackHole")
	swirl_decal = swirl.child("Decal") if swirl != null else null
	if swirl_decal != null:
		swirl_decal.set_color(Color8(191, 0, 255))
	smoke = space_obj.at("Islands/Tower/Model/Smoke/BackSprite/Decal")
	if smoke != null:
		smoke_col = smoke.color
	for f in ["Props", "Islands"]:
		var o = space_obj.child(f)
		if o == null:
			continue
		for c in o.kids():
			var ext: Array = c.data.get("p", {}).get("ext", [15, 15, 15])
			var mag = Vector3(ext[0], ext[1], ext[2]).length()
			props.append([c, c.get_pivot(), 15.0 / max(mag, 0.01), true])
	var deb = space_obj.child("Debris")
	if deb != null:
		for c in deb.kids():
			props.append([c, c.get_cframe(), 15.0 / max(c.size.length(), 0.01), false])
	for p in props:
		p[2] = pow(p[2], 0.25) if p[2] > 1 else pow(p[2], 0.2)

func space_load():
	tween(group_obj("neon"), {"Color": Color8(4, 175, 236)}, 0.15)
	if smoke != null:
		smoke.set_color(smoke_col)

func space_update(dt):
	var step = rate_limit("unity", 30, dt)
	if step <= 0:
		return
	passed += step
	if swirl != null:
		swirl.set_cframe(Transform(angles(-fmod(passed * 0.075, 1.0) * PI * 2, 0, 0), swirl.get_position()))
	var t = passed * 0.5
	var i = 0
	for p in props:
		var f: float = p[2]
		var a = fmod(t * 0.15 * f + i * 0.35, 1.0)
		var b = sin(fmod(t * 0.3 * f + i * 0.35, 1.0) * PI * 2) / 2 * f
		var s = sin(a * PI * 2) / 2 * f
		var off = Transform(angles(deg2rad(s * 10), deg2rad(s * 3), deg2rad(s * -5)), Vector3(0, b * 3, 0))
		var r: Transform = p[1] * off
		if p[3]:
			p[0].pivot_to(r)
		else:
			p[0].set_cframe(r)
		i += 1

func space_hit(col):
	if swirl_decal != null:
		tween(swirl_decal, {"Color3": col}, 0.15)
	tween(group_obj("neon"), {"Color": col}, 0.15)
	if smoke != null:
		tween(smoke, {"Color3": col}, 0.15)

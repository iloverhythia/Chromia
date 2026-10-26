extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Squircle Vortex" (SquircleVortex): a tunnel of turning
# squircles; every hit runs the note colour down the tunnel, and the glow at the
# end takes the current colour.

var spin = []
var smoke

func _init():
	slug = "squircle_vortex"

func space_init():
	var s = space_obj.at("Tunnel/WholeThing/ColoredSuaircles")
	spin = s.kids() if s != null else []
	spin.sort_custom(self, "_by_x")
	smoke = space_obj.at("BackSprite/Decal")

func _by_x(a, b):
	return a.get_position().x > b.get_position().x

func space_load():
	for i in range(spin.size()):
		spin[i].set_transparency(1.0 - float(i) / spin.size() * 0.25)
		spin[i].set_color(Color(1, 1, 1))

func space_update(dt):
	for v in spin:
		v.set_cframe(v.get_cframe() * cfa(0, 0, deg2rad(dt * 30)))
	if smoke != null and smoke.color != get_color():
		smoke.set_color(get_color())

func space_hit(col):
	for i in range(spin.size()):
		after(i * 0.016, self, "_flash", [spin[i], col])

func _flash(v, col):
	if is_instance_valid(v):
		tween(v, {"Color": col}, 0.05)

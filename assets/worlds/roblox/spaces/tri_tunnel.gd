extends "res://assets/worlds/roblox/rbx_space.gd"
# Roblox Rhythia space "Tri Tunnel" (TriTunnelSpace): a tunnel of triangles that
# keeps flowing toward you; the triangles flash to the note colour on every hit.

var tunnel

func _init():
	slug = "tri_tunnel"

func space_init():
	tunnel = space_obj.at("Dynamic/Tunnel")
	group_color("tri", Color(1, 1, 1).linear_interpolate(Color(0, 0, 0), 0.5))

func space_update(dt):
	if tunnel == null:
		return
	var p: Transform = tunnel.get_pivot()
	p.origin.x = rmod(p.origin.x + dt * 50, 740)
	tunnel.pivot_to(p)

func space_hit(col):
	tween(group_obj("tri"), {"Color": col.linear_interpolate(Color(0, 0, 0), 0.5)}, 0.15)

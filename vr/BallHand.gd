extends Reference

# The built-in "Ball" VR hand (Settings > VR > Hands): a plain round white
# sphere where your hand is. Made in code; one draw per hand.
#
# build() gives the right hand, in metres with the controller at the origin
# (VRPlayer.gd scales it; a ball is the same for both hands).

const RADIUS := 0.04
# how far in front of the controller the ball reaches (the beam starts there)
const TIP := RADIUS

static func build() -> Mesh:
	var s := SphereMesh.new()
	s.radius = RADIUS
	s.height = RADIUS * 2.0
	s.radial_segments = 32
	s.rings = 16
	var m := SpatialMaterial.new()
	m.albedo_color = Color(1, 1, 1)
	m.roughness = 0.45
	m.rim_enabled = true # (a soft edge, so it reads as round in any light)
	m.rim = 0.35
	m.rim_tint = 0.2
	s.material = m
	return s

extends Reference

# The built-in "Ball" VR hand (Settings > VR > Hands): a plain round white
# sphere where your hand is (unlit: white in any light). Made in code; one draw per hand.
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
	# unlit, so it's white in any scene (lit, the dark spaces turned it grey);
	# a little over 1, so it reaches the scene's full white through its colour
	# grading
	var sh := Shader.new()
	sh.code = """shader_type spatial;
render_mode unshaded;
void fragment() {
	ALBEDO = vec3(mix(0.92, 1.1, clamp(dot(NORMAL, VIEW), 0.0, 1.0)));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	s.material = m
	return s

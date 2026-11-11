extends Reference

# breck's VR hand (player #3 only, Settings > VR > Hands): a snow leopard paw.
# The same rounded paw as the Furry paws (PawHand.gd), in a snow leopard's
# coat: pale smoky grey fur with dark rosettes (broken rings) and solid spots
# on the top of the paw, fading out underneath, and dark charcoal toe beans.
# The rosettes are drawn by the fur's shader from the paw's own shape, so
# they're crisp and stay put on the paw (and mirror on the left hand).

const PawHand = preload("res://vr/PawHand.gd")
const TIP := PawHand.TIP
const PLAYER_NUMBER := 3

const FUR_LIGHT := Color(0.94, 0.93, 0.90)
const FUR_MID := Color(0.79, 0.79, 0.78)
const FUR_DARK := Color(0.58, 0.59, 0.62)
const SPOT := Color(0.17, 0.17, 0.20)
const LINE := Color(0.14, 0.14, 0.17)
const PAD_DARK := Color(0.19, 0.17, 0.20)
const PAD_LIGHT := Color(0.36, 0.32, 0.36)
const PAD_RIM := Color(0.09, 0.08, 0.10)

const FUR_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back;
uniform vec4 col_light : hint_color;
uniform vec4 col_mid : hint_color;
uniform vec4 col_dark : hint_color;
uniform vec4 spot : hint_color;
varying vec3 lp;
void vertex() {
	lp = VERTEX;
}
vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453);
}
void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 l = normalize((INV_CAMERA_MATRIX * vec4(0.35, 0.9, 0.45, 0.0)).xyz);
	vec3 l2 = normalize((INV_CAMERA_MATRIX * vec4(-0.45, -0.55, 0.6, 0.0)).xyz);
	float d = max(dot(n, l), dot(n, l2) * 0.55);
	d -= (1.0 - COLOR.r) * 0.75; // the creases between the toes and at the cuff
	vec3 c = mix(col_mid.rgb, col_light.rgb, smoothstep(0.12, 0.2, d));
	c = mix(col_dark.rgb, c, smoothstep(-0.38, -0.3, d));
	// rosettes: the nearest of scattered points (cells about 2.6 cm across)
	vec3 p = lp * 38.0;
	vec3 ip = floor(p);
	vec3 fp = fract(p);
	float d1 = 8.0;
	vec3 best = vec3(0.0);
	vec3 rel = vec3(0.0);
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 o = vec3(float(x), float(y), float(z));
				vec3 r = o + 0.15 + 0.7 * hash3(ip + o) - fp;
				float dd = dot(r, r);
				if (dd < d1) {
					d1 = dd;
					best = ip + o;
					rel = r;
				}
			}
		}
	}
	d1 = sqrt(d1);
	float h = hash3(best + 17.0).x;
	// most are broken rings, some solid spots, a few left out
	float ring = smoothstep(0.21, 0.25, d1) * (1.0 - smoothstep(0.40, 0.44, d1));
	float a = atan(rel.y, rel.x + rel.z * 0.5) / 6.2832 + h * 3.0;
	ring *= step(0.16, fract(a * 3.0));
	ring = max(ring, (1.0 - smoothstep(0.07, 0.1, d1)) * step(0.6, h)); // a dark centre in some
	float dot_ = 1.0 - smoothstep(0.17, 0.21, d1);
	float m = h < 0.28 ? dot_ : (h < 0.96 ? ring : 0.0);
	// on the top of the paw, fading out underneath (the pads' side)
	m *= smoothstep(-0.014, 0.004, lp.y);
	c = mix(c, spot.rgb, m * 0.88);
	ALBEDO = c;
}
"""

# Only breck: player #3 (online). Before the game knows who you are, the
# hand waits (VRPlayer shows the Furry paws until then).
static func allowed() -> bool:
	var tree = Engine.get_main_loop()
	var lm = tree.root.get_node_or_null("LobbyManager") if tree else null
	return lm != null and int(lm.get("my_player_number")) == PLAYER_NUMBER

static func build() -> ArrayMesh:
	var mesh: ArrayMesh = PawHand.build()
	# outline (surface 0), fur (1), pads (2) and their rims (3): PawHand.build()
	var line: ShaderMaterial = mesh.surface_get_material(0)
	line.set_shader_param("line", LINE)
	var sh := Shader.new()
	sh.code = FUR_SHADER
	var fur := ShaderMaterial.new()
	fur.shader = sh
	fur.set_shader_param("col_light", FUR_LIGHT)
	fur.set_shader_param("col_mid", FUR_MID)
	fur.set_shader_param("col_dark", FUR_DARK)
	fur.set_shader_param("spot", SPOT)
	mesh.surface_set_material(1, fur)
	var pads: ShaderMaterial = mesh.surface_get_material(2)
	pads.set_shader_param("pad_dark", PAD_DARK)
	pads.set_shader_param("pad_light", PAD_LIGHT)
	pads.set_shader_param("shine", 0.7)
	var rims: ShaderMaterial = mesh.surface_get_material(3)
	rims.set_shader_param("pad_dark", PAD_RIM)
	rims.set_shader_param("pad_light", PAD_RIM)
	return mesh

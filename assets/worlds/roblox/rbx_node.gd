extends Spatial
# One object of a converted Roblox space (a part, model, folder, decal, picture,
# particle emitter, light...). Built by rbx_space.gd from the space's data file.
# Keeps the Roblox name and class and offers the few Roblox properties the
# space scripts change (CFrame, Size, Color, Transparency, Color3...).
# All positions are in Roblox studs inside the space's root node.

var space # rbx_space.gd that built this
var rclass = ""
var rname = ""
var data: Dictionary # the node's entry in space.json (used to clone it)

var size = Vector3.ONE
var base_size = Vector3.ONE
var color = Color(1, 1, 1)
var transparency = 0.0
var material_id = 256
var value = null # NumberValue / Color3Value ...
var enabled = true

var geo: Spatial = null # holds the meshes; scaled when Size changes
var part_mesh: MeshInstance = null # the part's own shape (hidden when fully see-through)
var geo_base: Transform = Transform()
var mats = [] # materials this object owns (recoloured with it)
var tinted = true # part colour applies to its mesh
var emitter: CPUParticles = null
var light: Light = null
var beam: MeshInstance = null
var extra = {} # anything a space script wants to remember on the object

# ---------------------------------------------------------------- tree
func kids() -> Array:
	var out = []
	for c in get_children():
		if c.get_script() == get_script():
			out.append(c)
	return out

func desc() -> Array:
	var out = []
	for c in kids():
		out.append(c)
		out += c.desc()
	return out

func child(n: String):
	for c in get_children():
		if c.get_script() == get_script() and c.rname == n:
			return c
	return null

# path like "Dynamic/Tunnel"
func at(path: String):
	var o = self
	for s in path.split("/"):
		if o == null:
			return null
		o = o.child(s)
	return o

func is_a(c: String) -> bool:
	if c == "BasePart":
		return rclass in ["Part", "MeshPart", "UnionOperation", "WedgePart", "CornerWedgePart", "TrussPart"]
	return rclass == c

func is_part() -> bool:
	return is_a("BasePart")

# ---------------------------------------------------------------- transforms
# Transform in the space's Roblox coordinates (studs).
func get_cframe() -> Transform:
	var t = transform
	var p = get_parent()
	while p != null and p != space.rbx_root:
		t = p.transform * t
		p = p.get_parent()
	return t

func set_cframe(t: Transform):
	var p = get_parent()
	if p == null or p == space.rbx_root:
		transform = t
	else:
		transform = p.get_cframe().affine_inverse() * t if p.has_method("get_cframe") else t

func get_position() -> Vector3:
	return get_cframe().origin

func set_position(v: Vector3):
	var t = get_cframe()
	t.origin = v
	set_cframe(t)

func get_pivot() -> Transform:
	return get_cframe()

func pivot_to(t: Transform):
	set_cframe(t)

# ---------------------------------------------------------------- looks
func set_size(v: Vector3):
	size = v
	if geo != null:
		var s = Vector3(
			v.x / base_size.x if base_size.x != 0 else 1.0,
			v.y / base_size.y if base_size.y != 0 else 1.0,
			v.z / base_size.z if base_size.z != 0 else 1.0)
		geo.transform = Transform(Basis().scaled(s), Vector3())
	if emitter != null:
		emitter.emission_box_extents = v / 2
	if is_part() and geo != null:
		for c in kids():
			if c.rclass in ["Decal", "Texture", "SurfaceGui"]:
				c._scale_look(geo.transform)

# pictures on a part stretch with it
func _scale_look(t: Transform):
	if geo != null:
		geo.transform = t
	if rclass == "SurfaceGui" or rclass == "Frame":
		for c in kids():
			c._scale_look(t)

func set_color(c: Color):
	color = c
	if light != null:
		light.light_color = c
	if rclass == "SelectionBox":
		space.set_selbox_color(self, c)
	if rclass == "Trail":
		space.set_trail_color(self, c)
	if rclass == "Beam":
		space.set_beam_color(self, c)
	_apply_look()

func set_transparency(t: float):
	transparency = t
	_apply_look()

func set_enabled(e: bool):
	enabled = e
	if emitter != null:
		emitter.emitting = e
	if light != null:
		light.visible = e
	if beam != null:
		beam.visible = e

func _apply_look():
	for m in mats:
		space.set_mat_look(m, color if tinted else Color(1, 1, 1), transparency, is_part())
	if part_mesh != null:
		# a fully see-through part is not drawn (pictures on it still are)
		part_mesh.visible = transparency < 0.999
	if rclass in ["Decal", "Texture", "ImageLabel", "ImageButton", "TextLabel", "Frame"]:
		visible = transparency < 0.999

# Roblox property names used by the space scripts (and by tweens)
func get_prop(p: String):
	match p:
		"CFrame", "Pivot": return get_cframe()
		"Position": return get_position()
		"Size": return size
		"Color", "Color3", "ImageColor3", "TextColor3": return color
		"Transparency", "ImageTransparency", "TextTransparency": return transparency
		"Value": return value
		"Enabled": return enabled
	return extra.get(p)

func set_prop(p: String, v):
	match p:
		"CFrame", "Pivot": set_cframe(v)
		"Position": set_position(v)
		"Size": set_size(v)
		"Color", "Color3", "ImageColor3", "TextColor3": set_color(v)
		"Transparency", "ImageTransparency", "TextTransparency": set_transparency(v)
		"Value":
			value = v
			if extra.has("on_value"):
				var f: FuncRef = extra.on_value
				if f.is_valid():
					f.call_func(self)
		"Enabled": set_enabled(v)
		_: extra[p] = v

# ---------------------------------------------------------------- particles
# ParticleEmitter.Color = ColorSequence.new(c)
func set_emitter_color(c: Color, c2 = null):
	if emitter == null:
		return
	space.recolor_emitter(self, c, c2 if c2 != null else c)

func emit(n: int):
	if emitter == null:
		return
	space.burst(self, n)

# ---------------------------------------------------------------- copies
func clone_obj():
	return space.clone_node(self)

func set_parent_obj(p):
	var old = get_parent()
	if old == p:
		return
	var t = get_cframe()
	if old != null:
		old.remove_child(self)
	if p != null:
		p.add_child(self)
		set_cframe(t)

func destroy():
	space.forget(self)
	var p = get_parent()
	if p != null:
		p.remove_child(self)
	queue_free()

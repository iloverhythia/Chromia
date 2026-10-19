extends Spatial
# Shared logic for the SS+ particle note effects (ripple / shards / miss).
# NoteManager keeps one hidden, set-up "template" instance of the selected effect
# and duplicate()s it per hit/miss. Duplicates share the template's material, so
# rainbow colouring only has to be updated once per frame (by the template).
# Every spawned copy frees itself when its one-shot particles finish (with a
# time-based fallback, e.g. for renderers where GPU particles never finish).

# ids for the variants of this effect (set by subclasses)
var color_id: String = ""   # tinted with the note colour
var rainbow_id: String = "" # rainbow tint
var white_id: String = ""   # forced white
var use_user_image: bool = true

var active: bool = false
var rainbow: bool = false
var _life: float = 0.0
var _max_life: float = 2.0
var _free_in: int = 0 # frames left before a finished copy is freed

func _ready():
	if not active: set_process(rainbow)

func _process(delta):
	if active:
		_life += delta
		if not $Particles.emitting or _life > _max_life:
			# Hidden now, freed a few frames later. With threaded rendering
			# (rendering/threads/thread_model=2) CPUParticles are updated from the
			# render thread; hiding unhooks them on their next update, so they are
			# never deleted while the render thread may still be using them.
			active = false
			visible = false
			_free_in = 4
	elif _free_in > 0:
		_free_in -= 1
		if _free_in == 0:
			set_process(false)
			queue_free()
	elif rainbow and visible == false:
		# template only: tints the shared material for every live copy
		var mat = $Particles.material_override
		if mat: mat.albedo_color = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.4, 1)

# GPU Particles crash some Windows graphics drivers (and do nothing on the
# GLES2 fallback), so the template swaps them for CPUParticles with the same
# settings. Copies made with duplicate() get the CPU version too.
func _to_cpu_particles():
	var gpu = get_node_or_null("Particles")
	if gpu == null or not (gpu is Particles):
		return
	var cpu := CPUParticles.new()
	cpu.convert_from_particles(gpu)
	cpu.material_override = gpu.material_override
	cpu.one_shot = gpu.one_shot
	cpu.emitting = false
	cpu.transform = gpu.transform
	remove_child(gpu)
	gpu.free()
	cpu.name = "Particles"
	add_child(cpu)

func get_color_mat(parent: Node, col: Color, miss: bool):
	var cache = null
	if miss:
		cache = parent.get("matcache_miss")
	else:
		var spawn = parent.get_node_or_null("Spawn")
		if spawn: cache = spawn.get("matcache_hit")
		if cache == null: cache = parent.get("matcache_hit")
	if not (cache is Dictionary): cache = {}
	# keyed by effect id too, so two effect types never share a material
	var key: String = color_id + col.to_html()
	if cache.has(key):
		return cache[key]
	var mat = $Particles.material_override.duplicate()
	mat.albedo_color = col
	cache[key] = mat
	return mat

func spawn(parent: Node, pos: Vector3, col: Color, id: String, miss: bool):
	if not is_instance_valid(parent):
		queue_free()
		return
	if color_id != "" and id == color_id:
		$Particles.material_override = get_color_mat(parent, col, miss)
	transform.origin = pos
	parent.add_child(self)
	visible = true
	_life = 0.0
	_max_life = $Particles.lifetime / max($Particles.speed_scale, 0.01) * 2.0 + 0.5
	$Particles.emitting = true
	active = true
	set_process(true)

func setup(id: String, miss: bool):
	_to_cpu_particles()
	# own copy of the material so tinting/images never leak into the packed scene
	$Particles.material_override = $Particles.material_override.duplicate()
	if use_user_image:
		var img = Globals.imageLoader.load_if_exists("user://miss" if miss else "user://hit")
		if img: $Particles.material_override.albedo_texture = img
	if white_id != "" and id == white_id:
		$Particles.material_override.albedo_color = Color(1, 1, 1)
	rainbow = (rainbow_id != "" and id == rainbow_id)
	# the hidden template only needs to process for rainbow tinting
	set_process(rainbow)

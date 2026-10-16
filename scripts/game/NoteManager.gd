extends Spatial
class_name NoteManager

signal ms_change
signal timer_update
signal hit
signal miss

export(Material) var note_solid_mat
export(Material) var note_transparent_mat
export(Material) var asq_mat

var approach_rate: float = Rhythia.get("approach_rate")
var hit_window: float = Rhythia.get("hitwindow_ms")
var speed_multi: float = Globals.speed_multi[Rhythia.mod_speed_level]
var ms: float = Rhythia.start_offset - (Rhythia.lead_in_ms * speed_multi)
var notes_loaded: bool = false
var hitsync_ensured: bool = false

var active: bool = false

var _live_send_timer: float = 0.0

var noteNodes: Array = []
var noteCache: Array = []
var noteQueue: Array = []
var colors: Array = Rhythia.selected_colorset.colors
var scoreEffect: Spatial = load("res://assets/notefx/score/score.tscn").instance()
var chaos_rng: RandomNumberGenerator = RandomNumberGenerator.new()
var earthquake_rng: RandomNumberGenerator = RandomNumberGenerator.new()

var matcache_hit: Dictionary = {}
var matcache_miss: Dictionary = {}

const base_position = Vector3(-1, 1, 0)

var prev_ms: float = -100000

var next_ms: float = 0

var last_cursor_position: Vector3 = Vector3(-1, 1, 0)


var fade_in_enabled: bool = true
var fade_in_start: float = 8
var fade_in_end: float = 6

var fade_out_enabled: bool = false
var fade_out_start: float = 3
var fade_out_end: float = 1

var fade_out_base: float = 1


var notes: Array = []
var current_note: int = 0
var note_transform_scale: Vector3

var grid_pushback: float = 0.1
var pushback_defaults: Dictionary = {
	"do_pushback": 4,
	"never": 0.1
}

func linstep(a: float, b: float, x: float):
	if a == b: return float(x >= a)
	return clamp(((x - a) / (b - a)), 0, 1)

func note_reposition(i: int):
	var real_position: Vector2 = notes[i][0]
	var notems: float = notes[i][1]
	var state: int = notes[i][2]
	var col: Color = notes[i][3]
	var chaos_offset: Vector2 = notes[i][4]
	var nt: Transform = notes[i][5]

	var approachSpeed: float = approach_rate / speed_multi

	var current_offset_ms: float = notems - ms
	var current_dist: float = approachSpeed * current_offset_ms / 1000

	if (
		(current_dist <= Rhythia.get("spawn_distance") and current_dist >= (grid_pushback * -1) and sign(approachSpeed) == 1) or
		(current_dist >= -50 and current_dist <= 0.1 and sign(approachSpeed) == -1) or
		sign(approachSpeed) == 0
	) and state == Globals.NSTATE_ACTIVE:







		nt.origin.z = -current_dist


		var spawn_effect_t = 1 - clamp(4 * (Rhythia.spawn_distance - current_dist) / Rhythia.spawn_distance, 0, 1)
		if Rhythia.note_spawn_effect:
			$SpawnEffect.multimesh.set_instance_color(i - current_note, Color(col.r, col.g, col.b, col.a))
			if spawn_effect_t != 0:
				var effect_transform = Transform.IDENTITY
				effect_transform.origin = nt.origin
				effect_transform.basis = effect_transform.basis.scaled(Vector3.ONE * 1 * Rhythia.note_size)
				effect_transform.basis = effect_transform.basis.scaled(Vector3(1 * spawn_effect_t, 0.9 + (0.1 * spawn_effect_t), 1))
				effect_transform.basis = effect_transform.basis.rotated(Vector3(1, 0, 0), deg2rad(90))
				$SpawnEffect.multimesh.set_instance_transform(i - current_note, effect_transform)
			else: $SpawnEffect.multimesh.set_instance_transform(i - current_note, Transform.IDENTITY.scaled(Vector3.ZERO))

		if Rhythia.mod_360 or Rhythia.mod_chaos or Rhythia.mod_earthquake:
			var base_pos = real_position
			var base_z = nt.origin.z
			if Rhythia.mod_360:
				base_pos = Vector2(real_position.x - 1, real_position.y + 1)
				base_z = -current_dist
			var offset = Vector2.ZERO
			if Rhythia.mod_chaos:
				var v = ease(max((current_offset_ms - 250) / 400, 0), 1.5)
				offset += chaos_offset * v
			if Rhythia.mod_earthquake:
				var rcoord = Vector2(earthquake_rng.randf_range(-0.25, 0.25), earthquake_rng.randf_range(-0.25, 0.25))
				offset += rcoord * (current_dist * 0.1)
			nt.origin = Vector3(base_pos.x + offset.x, base_pos.y + offset.y, base_z)

		if Rhythia.mod_strobe:
			if int(ms) % 500 > 250:
				$Notes.visible = false
			else:
				$Notes.visible = true










		nt.basis = nt.basis.rotated(Vector3(1, 0, 0), Rhythia.note_spin_x / 2000)
		nt.basis = nt.basis.rotated(Vector3(0, 1, 0), Rhythia.note_spin_y / 2000)
		nt.basis = nt.basis.rotated(Vector3(0, 0, 1), Rhythia.note_spin_z / 2000)

		var alpha: float = Rhythia.note_opacity
		var fade_in: float = 1
		var fade_out: float = 1

		if fade_in_enabled or fade_out_enabled:
			if fade_in_enabled:
				fade_in = (pow(linstep(fade_in_start, fade_in_end, current_dist), 1.3)) * Rhythia.note_opacity
			if fade_out_enabled:
				fade_out = ((1 - fade_out_base) + (pow(linstep(fade_out_end, fade_out_start, current_dist), 1.3) * fade_out_base)) * Rhythia.note_opacity

			alpha = min(fade_in, fade_out)


		$Notes.multimesh.set_instance_transform(i - current_note, nt)
		$Notes.multimesh.set_instance_color(i - current_note, Color(col.r, col.g, col.b, col.a * alpha))
		if asq:
			var sc = (linstep(0, Rhythia.get("spawn_distance"), current_dist) + 0.6) * 0.4

			var at = Transform()
			at = at.scaled(Vector3(sc, sc, sc))
			at.origin = nt.origin
			if not Rhythia.visual_approach_follow:
				at.origin.z = 0

			$ASq.multimesh.set_instance_transform(i - current_note, at)
			if Rhythia.mod_ghost:
				$ASq.multimesh.set_instance_color(i - current_note, Color(1, 1, 1, 1 * alpha))
			else:
				$ASq.multimesh.set_instance_color(i - current_note, Color(1, 1, 1, pow(linstep(Rhythia.get("spawn_distance"), 0, current_dist), 1.7)))



		return true
	else:
		$Notes.multimesh.set_instance_transform(i - current_note, Transform(Basis(), Vector3(0, 0, 10)))
		$Notes.multimesh.set_instance_color(i - current_note, Color(0, 0, 0, 0))
		if asq:
			$ASq.multimesh.set_instance_transform(i - current_note, Transform(Basis(), Vector3(0, 0, 10)))
			$ASq.multimesh.set_instance_color(i - current_note, Color(0, 0, 0, 0))
		if Rhythia.note_spawn_effect:
			$SpawnEffect.multimesh.set_instance_transform(i - current_note, Transform(Basis(), Vector3(0, 0, 10)))
			$SpawnEffect.multimesh.set_instance_color(i - current_note, Color(0, 0, 0, 0))







		return false

func note_check_collision(i: int):
	if Rhythia.replaying and Rhythia.replay.sv != 1:
		return Rhythia.replay.should_hit(i)

	var cursor_world_pos = $Cursor.global_transform.origin
	var local_cpos = $Notes.to_local(cursor_world_pos)

	var hbs: float = Rhythia.note_hitbox_size / 2
	if hbs == 0.57: hbs = 0.56875

	var target_pos: Vector2 = notes[i][0]

	if Rhythia.mod_360:
		target_pos.x -= 1
		target_pos.y += 1

	return (local_cpos.x <= target_pos.x + hbs and local_cpos.x >= target_pos.x - hbs) and \
		(local_cpos.y <= target_pos.y + hbs and local_cpos.y >= target_pos.y - hbs)

var asq = Rhythia.note_visual_approach
var last_reposition_ms: float = -10000
var out_of_notes: bool = false
func reposition_notes(force: bool = false, rerun_start: int = -1):
	if Rhythia.mod_360:
		$Notes.translation = Vector3(1, -1, 0)
		$Notes.rotation.z = ms * (Rhythia.mod_360_speed * 0.0006)
	else:
		$Notes.rotation.z = 0
		$Notes.translation = Vector3.ZERO

	var rerun_required: bool = false
	$Label.text = ""

	if current_note == notes.size():

		$Notes.multimesh.visible_instance_count = 0
		if asq: $ASq.multimesh.visible_instance_count = 0
		if Rhythia.note_spawn_effect: $SpawnEffect.multimesh.visible_instance_count = 0
		out_of_notes = true
		return false

	var note_passed: bool = false
	var is_first: bool = true






	if last_reposition_ms > ms:

		print("rewind detected")
		for i in range(0, notes.size()):
			if notes[i][1] > ms:
				current_note = max(i - 1, 0)
				break

	last_reposition_ms = ms

	for i in range(max(current_note, rerun_start), notes.size()):
		var notems: float = notes[i][1]
		next_ms = notems
		if force:

			note_reposition(i)
		else:
			if note_reposition(i) == false:

				$Notes.multimesh.visible_instance_count = i - current_note + 1
				if asq: $ASq.multimesh.visible_instance_count = i - current_note + 1
				if Rhythia.note_spawn_effect: $SpawnEffect.multimesh.visible_instance_count = i - current_note
				if ms < notems:

					if notes[i][2] == Globals.NSTATE_ACTIVE:
						return note_passed

		if (i - current_note + 2) > $Notes.multimesh.instance_count:
			rerun_required = true
			$Notes.multimesh.instance_count = min($Notes.multimesh.instance_count + 10, notes.size())
			if asq: $ASq.multimesh.instance_count = $Notes.multimesh.instance_count
			if Rhythia.note_spawn_effect: $SpawnEffect.multimesh.instance_count = $Notes.multimesh.instance_count
			break

		if ms < notems and is_first:
			is_first = false


		elif ms >= notems and notes[i][2] == Globals.NSTATE_ACTIVE:
			var result = Rhythia.visual_mode or note_check_collision(i)

			if not result and (ms > notems + hit_window or pause_state == -1):
				var spectating_now = (Grid != null and Grid.spectating) or get_parent().ending
				if not Rhythia.replaying and Rhythia.record_replays and not spectating_now:
					Rhythia.replay.note_miss(i)
				notes[i][2] = Globals.NSTATE_MISS
				if Rhythia.play_miss_snd and not spectating_now:
					if Rhythia.sfx_2d:
						$Miss2D.play()
					else:
						$Miss.transform = notes[i][5]
						$Miss.play()
				if false:
					var pos: Vector3 = Vector3(
						notes[i][5].origin.x,
						notes[i][5].origin.y,
						0.002
					)

				if not spectating_now:
					emit_signal("miss", notes[i][3])
				prev_ms = notems
			elif result:


				var spectating_now = (Grid != null and Grid.spectating) or get_parent().ending
				if not Rhythia.replaying and Rhythia.record_replays and not spectating_now:
					Rhythia.replay.note_hit(i)
				notes[i][2] = Globals.NSTATE_HIT

				if Rhythia.play_hit_snd and not spectating_now:
					SFXManager.play_hitsfx(notes[i][5])
				var pos: Vector3 = Vector3(
					$Cursor.global_transform.origin.x,
					$Cursor.global_transform.origin.y,
					0.002
				)
				if false and not Rhythia.visual_mode:
					if not Rhythia.hit_effect_at_cursor:
						pos.x = (global_transform * notes[i][5]).origin.x
						pos.y = (global_transform * notes[i][5]).origin.y

				if not spectating_now:
					emit_signal("hit", notes[i][3])
					var score: int = get_parent().hit(notes[i][3])
					if Rhythia.score_popup:
						scoreEffect.duplicate().spawn(get_parent(), pos, notes[i][3], score)

				prev_ms = notems
		elif ms > (notems + hit_window) + 100:


			current_note = i + 1

	$Notes.multimesh.visible_instance_count = notes.size() - current_note
	if asq: $ASq.multimesh.visible_instance_count = notes.size() - current_note
	if Rhythia.note_spawn_effect: $SpawnEffect.multimesh.instance_count = notes.size() - current_note

	if rerun_required: reposition_notes()
	return note_passed

var color_index: int = 0
var note_count: int = 0

func sort_note_nodes(a, b):
	return a.notems < b.notems

func sort_note_queue(a, b):
	if a[2] == b[2]:
		return String(a) < String(b)
	return a[2] < b[2]

func spawn_notes(note_array: Array):
	note_array.sort_custom(self, "sort_note_queue")

	var nscale = 0.45 * Rhythia.note_size * (Rhythia.note_hitbox_size / 1.14)
	note_transform_scale = Vector3(nscale, nscale, nscale)

	next_ms = note_array[0][2]
	for data in note_array:
		if data[2] >= Rhythia.start_offset:
			next_ms = data[2]
			break
	var colorset: Array = Rhythia.selected_colorset.colors
	for i in range(note_array.size()):
		var data: Array = note_array[i]
		if (data[2] >= Rhythia.start_offset):
			var note: Array = [
				Vector2(data[0], -data[1]),

				data[2],

				Globals.NSTATE_ACTIVE,

				colorset[i % colorset.size()],

				Vector2(
					chaos_rng.randf_range(-1, 1),
					chaos_rng.randf_range(-1, 1)
				).normalized() * 2,

				Transform()
			]

			if Rhythia.mod_hardrock: note[0] = ((note[0] - Vector2(1, -1)) * 1.35) + Vector2(1, -1)
			if Rhythia.mod_mirror_x: note[0].x = 2 - note[0].x
			if Rhythia.mod_mirror_y: note[0].y = (-note[0].y) - 2
			note[5] = note[5].scaled(note_transform_scale)
			note[5].origin = Vector3(note[0].x, note[0].y, 4)


			notes.append(note)

	var last_ms = note_array[-1][2]
	var inst_count = max(35, ceil(10000 * (float(notes.size()) / float(last_ms))))
	$Notes.multimesh.instance_count = inst_count
	if asq:
		$ASq.multimesh.instance_count = inst_count

	notes_loaded = true
	call_deferred("reposition_notes", true)

func _on_networked_skip(target_ms: float):
	prev_ms = ms
	if Rhythia.record_replays:
		Rhythia.replay.store_sig(rms, Globals.RS_SKIP)
	ms = target_ms
	emit_signal("ms_change", ms)
	do_note_queue()
	if (ms + Rhythia.music_offset) >= Rhythia.start_offset:
		$Music.play((ms + Rhythia.music_offset) / 1000)
		music_started = true

func _ready():
	var lobby_manager = get_node_or_null("/root/LobbyManager")
	if lobby_manager != null:
		lobby_manager.connect("skip_triggered", self, "_on_networked_skip")
	if Rhythia.do_note_pushback:
		grid_pushback = pushback_defaults.do_pushback
	else:
		grid_pushback = pushback_defaults.never

	if Rhythia.speed_hitwindow:
		hit_window = Rhythia.get("hitwindow_ms") * speed_multi

	if Rhythia.mod_hardrock:
		hit_window = hit_window * 0.8

	$Note.speed_multi = speed_multi
	$Music.pitch_scale = speed_multi * replay_view_speed
	var border_tex = Rhythia.get_selected_border_texture()
	if border_tex != null:
		$Outer.get("material/0").albedo_texture = border_tex
	$Outer.get("material/0").albedo_color = Rhythia.border_color

	if AudioServer.get_bus_effect_count(AudioServer.get_bus_index("Music")) > 0:
		AudioServer.remove_bus_effect(AudioServer.get_bus_index("Music"), 0)
	if Rhythia.retain_song_pitch and not speed_multi == 1.0:
		var shift = AudioEffectPitchShift.new()
		shift.pitch_scale = 1.0 / speed_multi
		AudioServer.add_bus_effect(AudioServer.get_bus_index("Music"), shift)
	$Miss.stream = Rhythia.miss_snd

	$Miss2D.stream = Rhythia.miss_snd

	SFXManager.setup()


	if not Rhythia.replaying and Rhythia.record_replays:
		Rhythia.replay = Replay.new()
		Rhythia.replay.start_recording(Rhythia.selected_song)

	chaos_rng.seed = hash(Rhythia.selected_song.id)
	earthquake_rng.seed = hash(Rhythia.selected_song.id)


	if Rhythia.mod_ghost:
		fade_out_enabled = true
		fade_out_start = ((18.0 / 50) * approach_rate)
		fade_out_end = ((6.0 / 50.0) * approach_rate)

	elif Rhythia.half_ghost:
		fade_out_enabled = true
		fade_out_start = ((12.0 / 50) * approach_rate)
		fade_out_end = ((3.0 / 50.0) * approach_rate)
		fade_out_base = 0.8

	if Rhythia.mod_nearsighted:
		fade_in_enabled = true
		fade_in_start = ((30.0 / 50.0) * approach_rate)
		fade_in_end = ((5.0 / 50.0) * approach_rate)
	else:
		fade_in_enabled = Rhythia.get("fade_length") != 0
		if Rhythia.get("fade_length") != 0:
			fade_in_start = Rhythia.get("spawn_distance")
			fade_in_end = Rhythia.get("spawn_distance") * (1.0 - Rhythia.get("fade_length"))


	$Notes.multimesh = MultiMesh.new()
	$Notes.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	$Notes.multimesh.color_format = MultiMesh.COLOR_FLOAT
	$Notes.multimesh.instance_count = 1
	if asq:
		$ASq.multimesh = MultiMesh.new()
		$ASq.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		$ASq.multimesh.color_format = MultiMesh.COLOR_8BIT
		$ASq.multimesh.mesh = QuadMesh.new()
		$ASq.multimesh.mesh.size = Vector2(3.35, 3.35)
		$ASq.multimesh.mesh.surface_set_material(0, asq_mat)
		$ASq.multimesh.instance_count = 1
	else:
		$ASq.visible = false


	var mesh: Mesh
	if "user://" in Rhythia.selected_mesh.path:
		var m = ObjParse.load_obj(Rhythia.selected_mesh.path)
		if m != null:
			mesh = m
		else:
			mesh = load("res://assets/blocks/rounded.obj")
	else:
		mesh = load(Rhythia.selected_mesh.path)


	var img = Globals.imageLoader.load_if_exists("user://note")
	if img:
		note_solid_mat.set_shader_param("image", img)
		note_transparent_mat.set_shader_param("image", img)
		note_solid_mat.set_shader_param("use_image", true)
		note_transparent_mat.set_shader_param("use_image", true)

	mesh.surface_set_material(0, note_solid_mat)
	if mesh.get_surface_count() > 1:
		mesh.surface_set_material(1, note_transparent_mat)
	if mesh.get_surface_count() > 2:
		mesh.surface_set_material(2, note_solid_mat)

	$Notes.multimesh.mesh = mesh




	yield(get_tree(), "idle_frame")
	$Notes.multimesh.set_instance_color(0, Color(0, 0, 0, 0))
	$Notes.multimesh.set_instance_transform(0, Transform())
	if asq:
		$ASq.multimesh.set_instance_color(0, Color(0, 0, 0, 0))
		$ASq.multimesh.set_instance_transform(0, Transform())
	if Rhythia.note_spawn_effect:
		$SpawnEffect.multimesh.set_instance_transform(0, Transform(Basis(), Vector3(0, 0, 10)))
		$SpawnEffect.multimesh.set_instance_color(0, Color(0, 0, 0, 0))
	$Note.visible = true
	$Note.transform.origin = Vector3(0, 0, -400)
	yield(get_tree(), "idle_frame")
	$Note.visible = false












var music_started: bool = false
const cursor_offset = Vector3(1, -1, 0)
onready var cam: Camera = get_node("../..").get_node("Camera")
var hlpower = (0.1 * Rhythia.get("parallax"))
onready var Grid = get_node("../HUD")

func do_half_lock():
	var cursorpos
	if Grid.spectating and Grid.spectate_cursor != null:
		cursorpos = Grid.spectate_cursor.transform.origin
	else:
		cursorpos = $Cursor.transform.origin
		if Rhythia.follow_drift_cursor:
			cursorpos += $Cursor/Mesh2.transform.origin
	var centeroff = cursorpos - cursor_offset
	var hlm = 0.25
	var uim = Rhythia.get("ui_parallax") * 0.1
	var grm = Rhythia.get("grid_parallax") * 0.1
	cam.transform.origin = Vector3(
		centeroff.x * hlpower * hlm, centeroff.y * hlpower * hlm, 3.75
	)
	Grid.transform.origin = Vector3(
		-centeroff.x * hlm * uim, -centeroff.y * hlm * uim, Grid.transform.origin.z
	)
	transform.origin = Vector3(
		-(centeroff.x * hlm * grm) - 1, -(centeroff.y * hlm * grm) + 1, 0
	)

var sh: Vector2 = Vector2(-0.5, -0.5)
var edgec: float = 0
func do_spin():
	var centeroff = get_node("../..").get_node("SpinPos").global_transform.origin + cursor_offset

	var cx = centeroff.x
	var cy = -centeroff.y
	cx = clamp(cx, (0 + sh.x + edgec), (3 + sh.x - edgec))
	cy = clamp(cy, (0 + sh.y + edgec), (3 + sh.y - edgec))
	centeroff.x = cx - cursor_offset.x
	centeroff.y = -cy - cursor_offset.y

	var hlm = 0.25
	var uim = Rhythia.get("ui_parallax") * 0.1
	var grm = Rhythia.get("grid_parallax") * 0.1
	Grid.transform.origin = Vector3(
		-centeroff.x * hlm * uim, -centeroff.y * hlm * uim, Grid.transform.origin.z
	)
	transform.origin = Vector3(
		-(centeroff.x * hlm * grm) - 1, -(centeroff.y * hlm * grm) + 1, 0
	)

func do_vr_cursor():
	var centeroff = Rhythia.vr_player.primary_ray.get_collision_point() + cursor_offset

	var cx = centeroff.x
	var cy = -centeroff.y
	cx = clamp(cx, (0 + sh.x + edgec), (3 + sh.x - edgec))
	cy = clamp(cy, (0 + sh.y + edgec), (3 + sh.y - edgec))
	centeroff.x = cx - cursor_offset.x
	centeroff.y = -cy - cursor_offset.y

	var hlm = 0.25
	var uim = Rhythia.get("ui_parallax") * 0.1
	var grm = Rhythia.get("grid_parallax") * 0.1
	cam.transform.origin = Vector3(
		centeroff.x * hlpower, centeroff.y * hlpower, 3.735
	)
	Grid.transform.origin = Vector3(
		-centeroff.x * hlm * uim, -centeroff.y * hlm * uim, Grid.transform.origin.z
	)
	transform.origin = Vector3(
		-(centeroff.x * hlm * grm) - 1, -(centeroff.y * hlm * grm) + 1, 0
	)
	get_node("Cursor").transform.origin = centeroff + cursor_offset

func comma_sep(number):
	var string = str(number)
	var mod = string.length() % 3
	var res = ""

	for i in range(0, string.length()):
		if i != 0 and i % 3 == mod:
			res += ","
		res += string[i]

	return res

var spawn_ms_dist: float = ((max(Rhythia.get("spawn_distance") / Rhythia.get("approach_rate"), 0.6) * 1000) + 500)

func do_note_queue():
	pass











var rec_t: float = 0
var rms: float = 0
var rec_interval: float = 12
var pause_state: float = 0
var pause_cooldown: float = 0
var pause_ms: float = 0
var replay_unpause: bool = false
var can_skip: bool = ((next_ms - prev_ms) > 5000) and (next_ms >= max(ms + (3000 * speed_multi), 1100 * speed_multi))
var ms_offset: float = 0

var replay_sig: Array = []
var last_usec = OS.get_ticks_usec()

var viewer_paused: bool = false
var replay_view_speed: float = 1.0

func set_replay_view_speed(v: float):
	replay_view_speed = v
	if Rhythia.replaying:
		$Music.pitch_scale = speed_multi * replay_view_speed

func set_viewer_paused(p: bool):
	viewer_paused = p
	if not Rhythia.replaying: return
	if p:
		$Music.stop()
	elif (ms + Rhythia.music_offset) >= Rhythia.start_offset:
		$Music.play((ms + Rhythia.music_offset) / 1000.0)
		music_started = true

func _first_note_index_after(target_ms: float) -> int:
	for i in range(notes.size()):
		if notes[i][1] > target_ms:
			return i
	return notes.size()

func _resolve_seek_state(target_rms: float) -> Dictionary:
	var speed = speed_multi
	var sim_ms: float = Rhythia.start_offset - (Rhythia.lead_in_ms * speed)
	var sim_rms: float = 0.0
	var paused: bool = false
	var pause_anchor_ms: float = sim_ms
	for t in Rhythia.replay.get_all_triggers():
		var t_rms: float = t[0]
		if t_rms > target_rms:
			break
		if not paused:
			sim_ms += (t_rms - sim_rms) * speed
		sim_rms = t_rms
		match t[1]:
			Globals.RS_PAUSE:
				paused = true
				pause_anchor_ms = sim_ms
			Globals.RS_FINISH_UNPAUSE, Globals.RS_CANCEL_UNPAUSE:
				paused = false
			Globals.RS_SKIP:
				var idx = _first_note_index_after(sim_ms)
				var next_note_ms: float = notes[idx][1] if idx < notes.size() else sim_ms
				sim_ms = next_note_ms - 1000 - (1000 * speed)
	if not paused:
		sim_ms += (target_rms - sim_rms) * speed
	return {"ms": sim_ms, "rms": target_rms, "paused": paused, "pause_ms": pause_anchor_ms}

func seek_to_rms(target_rms: float):
	if not Rhythia.replaying or Rhythia.replay.autoplayer or Rhythia.replay.sv == 1: return
	target_rms = clamp(target_rms, 0, Rhythia.replay.end_ms)
	var state = _resolve_seek_state(target_rms)
	ms = state.ms
	rms = state.rms
	pause_state = -1 if state.paused else 0
	pause_ms = state.pause_ms
	replay_unpause = false
	viewer_paused = true

	current_note = notes.size()
	var found_cutoff: bool = false
	for i in range(notes.size()):
		if notes[i][1] <= ms:
			notes[i][2] = Globals.NSTATE_HIT if Rhythia.replay.should_hit(i) else Globals.NSTATE_MISS
		else:
			notes[i][2] = Globals.NSTATE_ACTIVE
			if not found_cutoff:
				current_note = i
				found_cutoff = true

	Rhythia.replay.reset_signal_cursor_to(rms)
	get_parent()._recompute_score_state(notes, current_note)

	emit_signal("ms_change", ms)
	emit_signal("timer_update", ms, false)
	$Music.stop()
	music_started = false

	last_reposition_ms = -10000
	reposition_notes(true)

func _set_rec_interval(delta: float):
	var newpos = $Cursor.transform.origin
	var diff = last_cursor_position.distance_to(newpos) / delta

	var min_interval = 30
	var max_interval = 144
	match Rhythia.record_limit:
		1:
			min_interval = 60
			max_interval = 240
	if Engine.target_fps != 0:
		max_interval = min(max_interval, Engine.target_fps)
		min_interval = min(min_interval, max_interval)
	var target_interval = min_interval + ((diff / 12) * (max_interval - min_interval))
	var new_interval = rec_interval
	if rec_interval != target_interval:
		match Rhythia.record_mode:
			0:
				new_interval = target_interval
			1:
				if target_interval > rec_interval: new_interval += (target_interval - rec_interval) * (delta / 0.2)
				else: new_interval += (target_interval - rec_interval) * (delta / 2)
			2:
				if target_interval > rec_interval: new_interval += (target_interval - rec_interval) * (delta / 2)
				else: new_interval = target_interval
	rec_interval = clamp(new_interval, min_interval, max_interval)

	last_cursor_position = newpos

func _process(delta: float):
	var u = OS.get_ticks_usec()
	delta = float(u - last_usec) / 1000000.0
	last_usec = u

	if Rhythia.vr: do_vr_cursor()
	elif Rhythia.get("cam_unlock"): do_spin()
	else: do_half_lock()
	_set_rec_interval(delta)

	var lobby_manager = get_node_or_null("/root/LobbyManager")
	if lobby_manager != null and lobby_manager.lobby_active:
		_live_send_timer += delta
		if _live_send_timer >= lobby_manager.LIVE_STATE_SEND_INTERVAL:
			_live_send_timer = 0.0
			var cursor_pos = $Cursor.transform.origin
			var energy_pct = (get_parent().energy / get_parent().max_energy) if get_parent().max_energy > 0 else 0.0
			var lvl_progress_pct = get_parent().lvl_progress / 10.0
			lobby_manager.send_live_state(cursor_pos.x, cursor_pos.y, get_parent().combo, get_parent().combo_level, energy_pct, lvl_progress_pct, ms)

	if active and notes_loaded:
		if not notes_loaded: return
		can_skip = ((next_ms - prev_ms) > 5000) and (next_ms >= max(ms + (3000 * speed_multi), 1100 * speed_multi)) and ($Notes.multimesh.visible_instance_count <= 1)

		$Cursor.can_switch_move_modes = (ms < Rhythia.music_offset)

		if Rhythia.replaying and not Rhythia.replay.autoplayer and Rhythia.replay.sv != 1 and Input.is_action_just_pressed("pause"):
			set_viewer_paused(not viewer_paused)

		if not Rhythia.replaying:
			if Input.is_action_just_released("pause"):
				if pause_state > 0:
					pause_state = -1
					ms = pause_ms
					if Rhythia.record_replays:
						Rhythia.replay.store_sig(rms, Globals.RS_CANCEL_UNPAUSE)
					emit_signal("ms_change", ms)
					$Music.stop()
			elif Input.is_action_just_pressed("pause"):
				if pause_state == 0 and can_skip:
					var in_lobby = lobby_manager != null and lobby_manager.lobby_active
					if in_lobby and not lobby_manager.is_host:
						pass
					elif in_lobby and lobby_manager.is_host:
						var target_ms = next_ms - 1000 - (1000 * speed_multi)
						lobby_manager.trigger_skip(target_ms)
					else:
						prev_ms = ms
						if Rhythia.record_replays:
							Rhythia.replay.store_sig(rms, Globals.RS_SKIP)
						ms = next_ms - 1000 - (1000 * speed_multi)
						emit_signal("ms_change", ms)
						do_note_queue()
				else:
					var in_lobby = lobby_manager != null and lobby_manager.lobby_active
					if in_lobby:
						pass
					elif pause_state == 0 and (ms > (1000 * speed_multi) and ms < get_parent().last_ms) and pause_cooldown == 0 and not Rhythia.disable_pausing:
						print("PAUSED AT MS %.0f" % ms)
						if Rhythia.record_replays:
							Rhythia.replay.store_pause(rms)
						Rhythia.song_end_pause_count += 1
						pause_state = -1
						emit_signal("ms_change", ms)
						pause_ms = ms
						$Music.stop()
						get_parent().combo_level = 1
						get_parent().lvl_progress = 0
						get_parent().update_hud()
					elif pause_state != 0:
						if Rhythia.record_replays:
							Rhythia.replay.store_sig(rms, Globals.RS_START_UNPAUSE)
						pause_state = 1
						ms = pause_ms - (pause_state * (750 * speed_multi))
						emit_signal("ms_change", ms)
						$Music.volume_db = -30
						$Music.play(ms / 1000)
			if Input.is_action_pressed("pause") and pause_state > 0:
				var prev_state = pause_state
				pause_state = max(pause_state - (delta / 0.75), 0)
				$Music.volume_db = min($Music.volume_db + (delta * 30), 0)
				if pause_state == 0:

					if (prev_state != pause_state) and Rhythia.record_replays:
						Rhythia.replay.store_sig(rms, Globals.RS_FINISH_UNPAUSE)
					$Music.volume_db = 0
					pause_state = 0
					pause_cooldown = 1
			elif pause_state == 0:
				pause_cooldown = max(pause_cooldown - delta, 0)
		elif Rhythia.replay.sv != 1 and not viewer_paused:
			var should_pause: bool = false
			var should_giveup: bool = false
			var should_skip: bool = false
			var just_started_unpause: bool = false
			var just_cancelled_unpause: bool = false
			var should_end_unpause: bool = false
			if replay_sig.size() != 0:
				print(replay_sig)
			for s in replay_sig:
				if s[1] == Globals.RS_PAUSE: should_pause = true
				elif s[1] == Globals.RS_GIVEUP: should_giveup = true
				elif s[1] == Globals.RS_SKIP: should_skip = true
				elif s[1] == Globals.RS_START_UNPAUSE:
					just_started_unpause = true
					replay_unpause = true
				elif s[1] == Globals.RS_CANCEL_UNPAUSE:
					just_cancelled_unpause = true
					replay_unpause = false
				elif s[1] == Globals.RS_FINISH_UNPAUSE:
					should_end_unpause = true

			if should_skip:
				var prev_ms = ms
				if Rhythia.record_replays:
					Rhythia.replay.store_sig(rms, Globals.RS_SKIP)
				ms = next_ms - 1000 - (1000 * speed_multi)
				emit_signal("ms_change", ms)
				do_note_queue()
				if (ms + Rhythia.music_offset) >= Rhythia.start_offset:
					$Music.play((ms + Rhythia.music_offset) / 1000)
					music_started = true
			if just_cancelled_unpause:
				pause_state = -1
				ms = pause_ms
				Rhythia.replay.store_sig(rms, Globals.RS_CANCEL_UNPAUSE)
				emit_signal("ms_change", ms)
				$Music.stop()
			elif should_pause:
				print("PAUSED AT MS %.0f" % ms)
				if Rhythia.record_replays:
					Rhythia.replay.store_sig(rms, Globals.RS_PAUSE)
				Rhythia.song_end_pause_count += 1
				pause_state = -1

				emit_signal("ms_change", ms)
				pause_ms = ms
				$Music.stop()
				get_parent().combo_level = 1
				get_parent().lvl_progress = 0
				get_parent().update_hud()
			elif just_started_unpause:


				pause_state = 1
				ms = pause_ms - (pause_state * (750 * speed_multi))
				emit_signal("ms_change", ms)
				$Music.volume_db = -30
				$Music.play((ms + Rhythia.music_offset) / 1000)
			if replay_unpause and pause_state >= 0:
				pause_state = max(pause_state - (delta / 0.75), 0)
				$Music.volume_db = min($Music.volume_db + (delta * 30), 0)
				if should_end_unpause:

					$Music.volume_db = Rhythia.music_volume_db
					pause_state = 0
			if should_giveup: get_parent().end(Globals.END_GIVEUP)

		if not viewer_paused:
			var view_mult: float = replay_view_speed if Rhythia.replaying else 1.0
			rms += delta * 1000 * view_mult
			rec_t += delta
			var unpause_input: bool = Input.is_action_pressed("pause") and not Rhythia.replaying
			if pause_state == 0 or (pause_state > 0 and (unpause_input or replay_unpause)):
				ms += delta * 1000 * speed_multi * view_mult
				emit_signal("ms_change", ms)
				do_note_queue()
				if (ms + Rhythia.music_offset) >= Rhythia.start_offset and not music_started:
					$Music.play((ms + Rhythia.music_offset) / 1000)
					music_started = true

			if Rhythia.replaying:
				replay_sig = Rhythia.replay.get_signals(rms)

			emit_signal("timer_update", ms, can_skip)

			if $Music.playing and not Rhythia.disable_desync:
				var playback_pos: float = $Music.get_playback_position() * 1000.0
				if abs(playback_pos - (ms + Rhythia.music_offset)) > (100 * max(speed_multi * view_mult, 1.0)):
					if Rhythia.desync_alerts:
						Globals.notify(
							Globals.NOTIFY_WARN,
							"Audio was desynced by %.2f ms, correcting." % [playback_pos - (ms + Rhythia.music_offset)],
							"Music Sync Correction"
						)
					$Music.play((ms + Rhythia.music_offset) / 1000.0)

		var rn_res: bool = reposition_notes()
		if not Rhythia.replaying and Rhythia.record_replays:
			var should_write_pos: bool = rn_res
			var ri = 1 / round(max(32, rec_interval))
			if pause_state == -1: ri /= 3
			if rn_res or rec_t >= ri:
				rec_t = 0
				should_write_pos = true
				Rhythia.replay.store_cursor_pos(rms, $Cursor.rpos.x, $Cursor.rpos.y)

		if Rhythia.rainbow_grid:
			$Outer.get("material/0").albedo_color = Color.from_hsv(Rhythia.rainbow_t * 0.1, 0.65, 1)
	elif Grid != null and Grid.spectating and notes_loaded:
		reposition_notes()


func _exit_tree():

	scoreEffect.queue_free()
	for n in noteCache:
		n.queue_free()

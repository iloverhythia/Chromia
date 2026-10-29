extends VBoxContainer

const MapFolders = preload("res://scripts/MapFolders.gd")

signal search_updated
signal reset_filters
signal lock_type

var thread: Thread

var songs: Array = Rhythia.registry_song.get_items()
var btns: Array = []

var search_text: String = ""
var author_search_text: String = ""
var difficulty_filter: Array = Rhythia.last_difficulty_filter
var show_broken_maps: bool = false
var show_online_maps: bool = true
var xp_only_maps: bool = false
var ranked_song_ids: Dictionary = {}
var flip_display: bool = false
var flip_name: bool = false

var cur_map: int = 0
var page_size: int = 10

var favorite: Array = []
var easy: Array = []
var medium: Array = []
var hard: Array = []
var logic: Array = []
var amogus: Array = []
var unknown: Array = []

var disp: Array = []

var folders = MapFolders.get_store()
# song id -> true for the active map folder, or null when showing all maps
var folder_filter = null

var ready: bool = false

var scroll_up: bool = false
var scroll_down: bool = false
var scroll_target: int = 0
var scrolling_to: bool = false

var check_drag: bool = false
var dragged: bool = false
var drag_cur_map: int = 0
var drag_start: Vector2 = Vector2()
var drag_offset: Vector2 = Vector2()

var momentum: float = 0

var size_x: int = 0

func next_index():
	return cur_map + int(floor(((page_size + 1) / 2) * 1.2))

func prev_index():
	return cur_map - int(floor(((page_size + 1) / 2) * 1.2))

var _fav_set: Dictionary = {}
func is_fav(s: Song): return _fav_set.has(s)

# Lowercased search text, worked out once per list rebuild instead of per map.
var _st: String = ""
var _at: String = ""

func search_matches(s: Song):
	return (
		difficulty_filter.has(s.difficulty) and
		(not s.is_online or show_online_maps) and
		(not s.is_broken or show_broken_maps) and
		(_st == "" or s.lname().find(_st) != -1) and
		(_at == "" or s.creator.to_lower().find(_at) != -1) and
		(not xp_only_maps or ranked_song_ids.has(s.id)) and
		(folder_filter == null or folder_filter.has(s.id))
	)

var has_been_pressed = false

func play_song():
	if not Rhythia.selected_song: return
	if has_been_pressed: return
	emit_signal("lock_type")
	has_been_pressed = true
	get_viewport().get_node("Menu").black_fade_target = true
	yield(get_tree().create_timer(0.35), "timeout")
	get_tree().change_scene("res://scenes/loaders/songload.tscn")

var pt = 1
func on_pressed(i, s: Song):
	if dragged:
		dragged = false
		return
	if i < 0: return
	$Press.play()
	scroll_to(i)

	if s != Rhythia.selected_song:
		Rhythia.select_song(s)
	else:
		print(pt)
		if pt < 0.25:

			check_drag = false
			dragged = false
			scrolling_to = false
			momentum = 0
			play_song()
	pt = 0
	get_viewport().get_node("Menu/Main/Maps/Results").visible = true

func switch_to_play_screen():
	size_list()
	if Rhythia.menu_target == "res://scenes/menu/menu.tscn": return
	if xp_only_maps and ranked_song_ids.empty():
		var lobby_manager = get_node_or_null("/root/LobbyManager")
		if lobby_manager != null:
			lobby_manager.list_ranked_maps()
			# wait at most 3 s: with the server down the answer never comes, and
			# waiting on the signal left the map list empty after every song
			var waited := 0.0
			while ranked_song_ids.empty() and waited < 3.0 and is_inside_tree():
				yield(get_tree(), "idle_frame")
				waited += get_process_delta_time()
			if not is_inside_tree():
				return
	if disp.find(Rhythia.registry_song.get_item(Rhythia.selected_song.id)) == -1:
		reset_filters()
	get_viewport().get_node("Menu/Sidebar").press(0, true)
	cur_map = disp.find(Rhythia.registry_song.get_item(Rhythia.selected_song.id))
	load_pg(true)

var was_maximized = OS.window_maximized
var was_fullscreen = OS.window_fullscreen
func _process(delta):
	if check_drag or dragged:
		drag_offset = Rhythia.menu_mouse(self)
		var diff = drag_offset - drag_start
		if abs(diff.y) > 40:
			check_drag = false
			dragged = true
			if cur_map + int(diff.y / 80) < drag_cur_map:
				call_deferred("pg_down")
			elif cur_map + int(diff.y / 80) > drag_cur_map:
				call_deferred("pg_up")

	pt += delta
	if OS.window_maximized != was_maximized or OS.window_fullscreen != was_fullscreen:
		was_maximized = OS.window_maximized
		was_fullscreen = OS.window_fullscreen
		handle_window_resize()

func _physics_process(delta):

	if momentum != 0:
		momentum = lerp(momentum, 0, 0.3)
		if abs(momentum) < 0.3:
			momentum = 0
		else:
			if momentum < 0:
				call_deferred("pg_up")
			else:
				call_deferred("pg_down")

	if scrolling_to:
		if scroll_target < cur_map:
			call_deferred("pg_up")
		elif scroll_target > cur_map:
			call_deferred("pg_down")
		else:
			scrolling_to = false
			if disp[cur_map] != Rhythia.selected_song:
				Rhythia.select_song(disp[cur_map])
	if scroll_down:
		call_deferred("pg_down")
	if scroll_up:
		call_deferred("pg_up")
	tween_length()

func check_drag_on():
	momentum = 0
	dragged = false
	check_drag = true
	drag_start = Rhythia.menu_mouse(self)
	drag_offset = drag_start
	drag_cur_map = cur_map

func check_drag_off():
	check_drag = false
	dragged = false
	momentum = (drag_offset - Rhythia.menu_mouse(self)).y

func select_random():
	if disp.size() == 0: return
	cur_map = randi() % disp.size()
	load_pg(true)

func load_pg(select_cur: bool = false):
	# The list jumps to cur_map now, so an unfinished click-scroll is stale (it
	# would scroll all the way back to the clicked map and select it again).
	scrolling_to = false
	size_list()
	for n in btns: n.queue_free()
	btns.clear()

	if disp.size() == 0: return
	page_size = ((get_parent().rect_size.y) / 90) * 1.5
	if page_size % 2 != 0:
		page_size += 1

	cur_map = clamp(cur_map, 0, disp.size() - 1)
	for i in range(prev_index(), next_index() + 1):
		var btn: Panel = make_song_button(i)
		btn.rect_min_size = Vector2(350, 90)
		btns.append(btn)
		add_child(btn)
		btn.visible = true
		if i == cur_map and select_cur:
			if btn.song != Rhythia.selected_song:
				Rhythia.select_song(btn.song)
				btn.get_node("Select").pressed = true

func append_filtering_favorites(to: Array, from: Array):
	for s in from:
		if not is_fav(s) and search_matches(s):
			to.append(s)

# Sorting thousands of maps with a script compare function is slow, so sort
# text keys with the engine's built-in sort instead.
func _sorted_by_keys(arr: Array, keys: Array, desc: bool) -> Array:
	var by_key := {}
	var sk := []
	for i in range(arr.size()):
		var k: String = keys[i] + "\u0001%08d" % i
		by_key[k] = arr[i]
		sk.append(k)
	sk.sort()
	if desc: sk.invert()
	var out := []
	out.resize(sk.size())
	for i in range(sk.size()):
		out[i] = by_key[sk[i]]
	return out

func _sorted_by_name(arr: Array, desc: bool) -> Array:
	var keys := []
	keys.resize(arr.size())
	for i in range(arr.size()):
		keys[i] = arr[i].lname() + "\u0001" + String(arr[i].id)
	return _sorted_by_keys(arr, keys, desc)

func _sorted_by_stars(arr: Array, desc: bool) -> Array:
	var rated := []
	var unrated := []
	var keys := []
	for s in arr:
		var r: float = s.star_rating_cached()
		if r < 0.0:
			unrated.append(s)
		else:
			rated.append(s)
			keys.append("%012.4f\u0001%s" % [r, s.lname()])
	var out := _sorted_by_keys(rated, keys, desc)
	out.append_array(_sorted_by_name(unrated, false))
	return out

# Most played first (the difficulty arrow flips it); counts from user://stats.json.
func _sorted_by_plays(arr: Array, desc: bool) -> Array:
	var counts: Dictionary = Rhythia.get_lifetime_stats().get("map_plays", {})
	var keys := []
	keys.resize(arr.size())
	for i in range(arr.size()):
		keys[i] = "%08d\u0001%s" % [int(counts.get(String(arr[i].id), 0)), arr[i].lname()]
	# most played first unless the arrow is flipped (names A-Z within a count)
	var out := _sorted_by_keys(arr, keys, not desc)
	return out

func build_list():
	disp = []
	favorite = []
	_fav_set = {}
	_st = search_text.to_lower()
	_at = author_search_text.to_lower()
	folder_filter = folders.active_set()
	for id in Rhythia.favorite_songs:
		var s = Rhythia.registry_song.get_item(id)
		if s and Rhythia.is_favorite(id) and search_matches(s):
			favorite.append(s)
	favorite.sort_custom(self, "sortsong")
	for s in favorite: _fav_set[s] = true
	disp.append_array(favorite)
	if Rhythia.sort_by_plays:
		var played := []
		for bucket in [easy, medium, hard, logic, amogus, unknown]:
			append_filtering_favorites(played, bucket)
		disp.append_array(_sorted_by_plays(played, flip_display))
	elif Rhythia.sort_by_stars:
		var rest := []
		for bucket in [easy, medium, hard, logic, amogus, unknown]:
			append_filtering_favorites(rest, bucket)
		disp.append_array(_sorted_by_stars(rest, flip_display))
	elif flip_display:
		append_filtering_favorites(disp, amogus)
		append_filtering_favorites(disp, logic)
		append_filtering_favorites(disp, hard)
		append_filtering_favorites(disp, medium)
		append_filtering_favorites(disp, easy)
		append_filtering_favorites(disp, unknown)
	else:
		append_filtering_favorites(disp, easy)
		append_filtering_favorites(disp, medium)
		append_filtering_favorites(disp, hard)
		append_filtering_favorites(disp, logic)
		append_filtering_favorites(disp, amogus)
		append_filtering_favorites(disp, unknown)

func reload_to_current_page(_a = null):
	scrolling_to = false
	build_list()
	load_pg()

# Typing in the search boxes waits for a short pause before rebuilding the
# list, so big libraries don't lag on every key press.
const SEARCH_DELAY = 0.15
var _search_timer: SceneTreeTimer = null

func _queue_search():
	if not ready: return
	_search_timer = get_tree().create_timer(SEARCH_DELAY)
	_search_timer.connect("timeout", self, "_run_queued_search", [_search_timer])

func _run_queued_search(t):
	if t != _search_timer or not is_inside_tree(): return
	_search_timer = null
	reload_to_current_page()
	emit_signal("search_updated")

func update_search_text(txt: String):
	search_text = txt
	_queue_search()

func update_author_search_text(txt: String):
	author_search_text = txt
	_queue_search()

func update_search_dfil(dfil: Array):
	difficulty_filter = dfil
	Rhythia.last_difficulty_filter = dfil
	if ready: reload_to_current_page()
	emit_signal("search_updated")

func update_search_showbroken(show: bool):
	show_broken_maps = show
	if ready: reload_to_current_page()

func update_search_showonline(show: bool):
	show_online_maps = show
	if ready: reload_to_current_page()

func update_search_xponly(show: bool):
	xp_only_maps = show
	if ready: reload_to_current_page()

func _on_ranked_maps_received(song_ids: Array):
	ranked_song_ids = {}
	for id in song_ids: ranked_song_ids[id] = true
	if xp_only_maps and ready: reload_to_current_page()

func update_search_flipped(flip: bool):
	flip_display = flip
	if ready: reload_to_current_page()

func update_search_flip_name(flip: bool):
	flip_name = flip
	_sort_buckets()
	if ready: reload_to_current_page()

func sortab(a, b): return a < b

func update_search_sort_stars(_on: bool):
	if ready: reload_to_current_page()

# Maps without a rating (e.g. online maps not downloaded yet) go last.
func sortstars(a: Song, b: Song):
	var sa: float = a.star_rating_cached()
	var sb: float = b.star_rating_cached()
	if (sa < 0.0) != (sb < 0.0):
		return sb < 0.0
	if sa != sb:
		return sa > sb if flip_display else sa < sb
	return a.name.to_lower() < b.name.to_lower()

func sortsongsimple(a: Song, b: Song):
	if flip_name:
		if a.name != b.name: return a.name.to_lower() > b.name.to_lower()
		else: return a.id > b.id
	else:
		if a.name != b.name: return a.name.to_lower() < b.name.to_lower()
		else: return a.id < b.id

func sortsong(a: Song, b: Song):
	var ad = a.difficulty
	var bd = b.difficulty
	if ad == -1: ad = 255
	if bd == -1: bd = 255
	if ad != bd:
		if flip_display: return ad > bd
		else: return ad < bd
	else: return sortsongsimple(a, b)

func reset_filters():
	print("resetting filters")
	emit_signal("reset_filters")
	update_search_dfil([Globals.DIFF_UNKNOWN, Globals.DIFF_EASY, Globals.DIFF_MEDIUM, Globals.DIFF_HARD, Globals.DIFF_LOGIC, Globals.DIFF_AMOGUS])
	update_search_showbroken(false)

	update_search_flipped(false)
	update_search_flip_name(false)
	update_search_xponly(false)
	folders.set_active(-1)

# Groups maps by difficulty. The groups are rebuilt from scratch so maps that
# were removed or re-imported don't linger as duplicates.
func prepare_songs():
	easy = []; medium = []; hard = []; logic = []; amogus = []; unknown = []
	var seen := {}
	for i in range(songs.size()):
		var map: Song = songs[i]
		if seen.has(map): continue
		seen[map] = true
		match map.difficulty:
			Globals.DIFF_EASY: easy.append(map)
			Globals.DIFF_MEDIUM: medium.append(map)
			Globals.DIFF_HARD: hard.append(map)
			Globals.DIFF_LOGIC: logic.append(map)
			Globals.DIFF_AMOGUS: amogus.append(map)
			_: unknown.append(map)
	_sort_buckets()

func _sort_buckets():
	easy = _sorted_by_name(easy, flip_name)
	medium = _sorted_by_name(medium, flip_name)
	hard = _sorted_by_name(hard, flip_name)
	logic = _sorted_by_name(logic, flip_name)
	amogus = _sorted_by_name(amogus, flip_name)
	unknown = _sorted_by_name(unknown, flip_name)

func make_song_button(id: int = -1):
	if id < 0 or id >= disp.size():
		var btn: Panel = $EMPTY.duplicate()
		btn.rect_min_size = Vector2(int(size_x - (page_size / 2) * 10), 0)
		return btn
	var map: Song = disp[id]
	if map == null: return
	var btn: Panel
	match map.difficulty:
		Globals.DIFF_EASY: btn = $EASY.duplicate()
		Globals.DIFF_MEDIUM: btn = $MEDIUM.duplicate()
		Globals.DIFF_HARD: btn = $HARD.duplicate()
		Globals.DIFF_LOGIC: btn = $LOGIC.duplicate()
		Globals.DIFF_AMOGUS: btn = $AMOGUS.duplicate()
		_: btn = $NODIF.duplicate()
	btn.rect_min_size = Vector2(size_x - 50, 0)
	btn.get_node("Label").visible = false
	if map.has_cover:
		btn.get_node("Cover").visible = true
		btn.get_node("Cover").texture = map.get_cover_thumb()
	btn.get_node("Name").visible = true
	if map.name.length() > 55:
		btn.get_node("Name").text = strip_diacritics(map.name)
	else:
		btn.get_node("Name").text = map.name
	btn.song = map
	if map.warning != "" or map.is_broken:
		if map.is_broken: btn.get_node("Name").modulate = Color(1, 0.4, 0.4)
		else: btn.get_node("Name").modulate = Color(1, 1, 0.2)
	var rbtn: Button = btn.get_node("Select")
	if is_fav(map): btn.get_node("F").visible = true
	var fcol = folders.color_for(map.id)
	if fcol != null:
		var strip := ColorRect.new()
		strip.color = fcol
		strip.mouse_filter = MOUSE_FILTER_IGNORE
		strip.anchor_bottom = 1
		strip.margin_left = 6
		strip.margin_right = 12
		strip.margin_top = 6
		strip.margin_bottom = -6
		btn.add_child(strip)
	btn.get_node("Cloud").visible = map.is_online
	rbtn.disabled = false
	rbtn.connect("pressed", self, "on_pressed", [id, map])

	rbtn.action_mode = 1
	rbtn.connect("button_down", self, "check_drag_on")
	rbtn.connect("button_up", self, "check_drag_off")
	rbtn.keep_pressed_outside = true
	if map == Rhythia.selected_song:
		btn.get_node("Select").pressed = true
	return btn

func pg_up():
	if cur_map < 0 or btns.empty(): return
	cur_map -= 1

	$Press.play()
	var out: Panel = btns.pop_back()
	tween_out(out)

	var btn: Panel = make_song_button(prev_index())
	btns.insert(0, btn)
	add_child(btn)
	move_child(btn, 0)
	btn.visible = true
	tween_in(btn)

func pg_down():
	if cur_map >= disp.size() - 1: return
	cur_map += 1

	$Press.play()
	var out: Panel = btns.pop_front()
	tween_out(out)
	var btn: Panel = make_song_button(next_index())
	btns.append(btn)
	add_child(btn)
	btn.visible = true
	tween_in(btn)

func tween_out(p: Panel):
	var tween = get_tree().create_tween()
	tween.tween_property(p, "rect_min_size", Vector2(size_x - (page_size / 2) * 10, 0), 0.2)
	tween.tween_callback(p, "queue_free")

func tween_in(p: Panel):
	var tween = get_tree().create_tween()
	tween.tween_property(p, "rect_min_size", Vector2(size_x - (next_index() - prev_index()) / 2 * 10, 90), 0.2)

# Runs every physics frame: eases each button toward its width. (It used to
# start a new tween per button per frame, thousands a second, many aimed at
# buttons that were already being freed when the list rebuilt.)
func tween_length():
	var mid: int = (next_index() - prev_index()) / 2
	for i in btns.size():
		var b = btns[i]
		if not is_instance_valid(b) or b.is_queued_for_deletion():
			continue
		var target := Vector2(size_x - 15 * abs(mid - i), 90)
		var cur: Vector2 = b.rect_min_size
		if cur.distance_squared_to(target) > 0.25:
			b.rect_min_size = cur.linear_interpolate(target, 0.25)


func _input(ev: InputEvent):
	if is_visible_in_tree() and ev is InputEventMouseButton and ev.is_pressed():
		if (ev.button_index == BUTTON_WHEEL_UP or ev.button_index == BUTTON_WHEEL_DOWN) \
			and (Input.is_key_pressed(KEY_ALT) or not get_global_rect().has_point(Rhythia.menu_mouse(self))):
			return
		if ev.button_index == BUTTON_WHEEL_UP:
			scrolling_to = false
			call_deferred("pg_up")
		elif ev.button_index == BUTTON_WHEEL_DOWN:
			scrolling_to = false
			call_deferred("pg_down")
	if ev is InputEventKey and ev.is_pressed():

		if ev.scancode == KEY_F2:
			print("F2")
			select_random()


func handle_window_resize():

	if ready: size_list()

func firstload():

	get_parent().get_parent().get_parent().get_node("ScrollControl/P").connect("button_down", self, "pg_down_cont")
	get_parent().get_parent().get_parent().get_node("ScrollControl/M").connect("button_down", self, "pg_up_cont")
	get_parent().get_parent().get_parent().get_node("ScrollControl/P").connect("button_up", self, "pg_down_stop")
	get_parent().get_parent().get_parent().get_node("ScrollControl/M").connect("button_up", self, "pg_up_stop")
	_make_top_button(get_parent().get_parent().get_parent().get_node("ScrollControl"))

	get_parent().get_parent().get_node("T/Random").connect("pressed", self, "select_random")
	prepare_songs()
	reload_to_current_page()
	ready = true
	Rhythia.connect("favorite_songs_changed", self, "reload_to_current_page")
	folders.connect("changed", self, "reload_to_current_page")
	Rhythia.connect("download_done", self, "update_clouds")
	Rhythia.connect("thumbs_ready", self, "update_clouds")
	get_viewport().connect("size_changed", self, "handle_window_resize")
	Rhythia.emit_signal("map_list_ready")

func update_clouds():
	for btn in btns:
		if is_instance_valid(btn) and btn.get("song"):
			var map: Song = btn.song
			if btn.has_node("Cloud"):
				btn.get_node("Cloud").visible = btn.song.is_online
			if map.has_cover and btn.has_node("Cover"):
				var cover_node = btn.get_node("Cover")
				cover_node.texture = map.get_cover_thumb()
				cover_node.visible = true


# The empty square above UP (it lines UP up with the filters) is a "back to
# the top" button: same look as UP / DOWN, a small TOP label. It jumps to the
# first map without changing which map is selected.
func _make_top_button(sc: Node):
	var b = sc.get_node_or_null("bump")
	var up = sc.get_node_or_null("M")
	if not (b is Button) or not (up is Button):
		return
	b.modulate = Color(1, 1, 1, 1)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_stylebox_override(st, up.get_stylebox(st))
	b.focus_mode = Control.FOCUS_NONE
	b.hint_tooltip = "Back to the top of the map list"
	var src: Label = up.get_node_or_null("Label")
	if src != null:
		var l: Label = src.duplicate()
		l.text = "TOP"
		l.margin_top = 0
		l.margin_bottom = 0
		var f = src.get_font("font")
		if f is DynamicFont:
			f = f.duplicate()
			f.size = 14
			f.outline_size = 2
			f.extra_spacing_char = 0
			l.add_font_override("font", f)
		b.add_child(l)
	if not b.is_connected("pressed", self, "go_to_top"):
		b.connect("pressed", self, "go_to_top")

func go_to_top():
	if disp.size() == 0:
		return
	scroll_up = false
	scroll_down = false
	momentum = 0
	cur_map = 0
	load_pg()

func pg_up_cont():
	scrolling_to = false
	scroll_up = true

func pg_up_stop():
	scroll_up = false

func pg_down_cont():
	scrolling_to = false
	scroll_down = true

func pg_down_stop():
	scroll_down = false

func scroll_to(i: int):
	if i < 0 or i >= disp.size(): return
	scroll_target = i
	scrolling_to = true

func refresh_songs():
	songs = Rhythia.registry_song.get_items()
	prepare_songs()
	build_list()

func scroll_to_song(id) -> bool:
	var song = Rhythia.registry_song.get_item(id) if Rhythia.registry_song else false
	if not song: return false
	var i = disp.find(song)
	if i == -1:
		refresh_songs()
		song = Rhythia.registry_song.get_item(id) if Rhythia.registry_song else false
		if not song: return false
		i = disp.find(song)
		if i == -1: return false
	cur_map = i
	load_pg(true)
	return true

func _ready():

	randomize()
	if not visible: return
	$EASY.visible = false
	$MEDIUM.visible = false
	$HARD.visible = false
	$LOGIC.visible = false
	$AMOGUS.visible = false
	$NODIF.visible = false
	$EMPTY.visible = false

	difficulty_filter = Rhythia.last_difficulty_filter

	if not Online.is_connected("db_maps_done", self, "refresh_songs"):
		Online.connect("db_maps_done", self, "refresh_songs")
	if not Rhythia.is_connected("local_maps_loaded", self, "refresh_songs"):
		Rhythia.connect("local_maps_loaded", self, "refresh_songs")

	var lobby_manager = get_node_or_null("/root/LobbyManager")
	if lobby_manager != null:
		if not lobby_manager.is_connected("ranked_maps_received", self, "_on_ranked_maps_received"):
			lobby_manager.connect("ranked_maps_received", self, "_on_ranked_maps_received")
		lobby_manager.list_ranked_maps()

	Engine.iterations_per_second = 60
	call_deferred("firstload")

	size_list()

var _stop_loading_covers: bool = false

func _exit_tree():
	_stop_loading_covers = true

func size_list():
	size_x = get_viewport_rect().size.x / 2.8
	$"..".rect_min_size.x = size_x

func _load_covers():
	var allmaps: Array = Rhythia.registry_song.get_items()
	for i in range(allmaps.size()):
		if _stop_loading_covers:
			return
		var song = allmaps[i]
		# Covers are normally all loaded during startup already.
		if song.has_cover and not song.cover_ready():
			var img = song._decode_cover_pixels()
			song._cover_mutex.lock()
			song._decoded_cover_image = img
			song._cover_mutex.unlock()

func strip_diacritics(s: String):








	var pool: PoolByteArray = s.to_utf8()

	var output_bytes: Array = []


	var byte_values_to_remove = [
		128, 129, 130, 131, 132, 133, 134,
		135, 136, 137, 138, 139, 140, 141,
		142, 143, 144, 145, 146, 147, 148,
		149, 150, 151, 152, 153, 154, 155,
		156, 157, 158, 159, 160, 161, 162,
		163, 164, 165, 166, 167, 168, 169,
		170, 171, 172, 173, 174, 175, 176,
		177, 178, 179, 180, 181, 182, 183,
		184, 185, 186, 187, 188, 189, 190,
		191, 128, 129, 130, 131, 132, 133,
		134, 135, 136, 137, 138, 139, 140,
		141, 142, 143, 144, 145, 146, 147,
		148, 149, 150, 151, 152, 153, 154,
		155, 156, 157, 158, 159, 160, 161
	]


	var removed: bool = false
	for i in range(pool.size() - 1, -1, -1):
		if removed:
			removed = false
			continue
		var byte_value = pool[i]
		var prev_byte = -1
		if i != 0:
			prev_byte = pool[i - 1]

		if byte_value in byte_values_to_remove:

			if prev_byte == 204 or prev_byte == 205:
				removed = true
				continue
		output_bytes.insert(0, byte_value)

	return PoolByteArray(output_bytes).get_string_from_utf8()

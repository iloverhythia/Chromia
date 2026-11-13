extends Button

# On the map screen, under Start: when your copy of a ranked map has different
# notes than the ranked version (so its passes don't count), this button puts
# the server's ranked copy in its place. Your old file is kept in
# user://map_backups.

const BACKUP_DIR := "user://map_backups"
const RANKED_MAP_URL := "https://savia.nysr.host/ranked-maps/%s.sspm"

var _hashes := {} # "path|mtime" -> that file's chart hash ("" = couldn't read it)
var _want := {} # song id -> the ranked version's chart hash
var _thread: Thread = null
var _thread_key := ""
var _busy := false

static func attach(screen: Node) -> Node:
	var run = screen.get_node_or_null("RS/H1/Info/Run")
	if run == null:
		return null
	var b = load("res://scripts/ui/menu/RankedCopy.gd").new()
	b.name = "RankedCopy"
	b.theme = run.theme
	var info = run.get_parent()
	info.add_child(b)
	info.move_child(b, run.get_index() + 1)
	return b

func _ready():
	text = "Get the ranked version"
	hint_tooltip = "Your copy of this map has different notes than the ranked version,\nso passes on it don't count. This downloads the ranked version and\nputs it in place of yours (yours is kept in the map_backups folder)."
	rect_min_size = Vector2(0, 34)
	add_color_override("font_color", Color("#ffb44a"))
	add_color_override("font_color_hover", Color("#ffd28a"))
	visible = false
	connect("pressed", self, "_on_pressed")
	Rhythia.connect("selected_song_changed", self, "_on_song_changed")
	var lm = get_node_or_null("/root/LobbyManager")
	if lm != null:
		lm.connect("map_rank_info_received", self, "_on_rank_info")
	set_process(false)

func _exit_tree():
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null

func _on_song_changed(_s = null):
	_refresh()

func _on_rank_info(song_id: String, ranked: bool, _xp: int, content_hash: String):
	if ranked and content_hash != "":
		_want[song_id] = content_hash
	else:
		_want.erase(song_id)
	_refresh()

# a local .sspm file (not a download for watching someone)
func _local_file(song) -> String:
	if song == null or song.is_online:
		return ""
	if not (song.songType == Globals.MAP_SSPM or song.songType == Globals.MAP_SSPM2):
		return ""
	var path := String(song.filePath)
	if path == "" or path.find(".watch_only") != -1 or not File.new().file_exists(path):
		return ""
	return path

func _key(path: String) -> String:
	return "%s|%d" % [path, File.new().get_modified_time(path)]

func _refresh():
	var song = Rhythia.selected_song
	var want := String(_want.get(String(song.id), "")) if song != null else ""
	var path := _local_file(song)
	if _busy:
		return
	if want == "" or path == "":
		visible = false
		return
	var key := _key(path)
	if _hashes.has(key):
		visible = _hashes[key] != "" and _hashes[key] != want
		return
	visible = false
	_start_hash(path, key)

# The notes' fingerprint, from a fresh copy of the file (the map in the list
# may be busy elsewhere, like the star rating), on a thread when there is one.
func _start_hash(path: String, key: String):
	if _thread != null:
		return # (the one running finishes first; _refresh runs again then)
	_thread_key = key
	if not OS.can_use_threads():
		_hashes[key] = _hash_job(path)
		_refresh()
		return
	_thread = Thread.new()
	if _thread.start(self, "_hash_job", path) != OK:
		_thread = null
		_hashes[key] = _hash_job(path)
		_refresh()
		return
	set_process(true)

func _hash_job(path: String) -> String:
	var s = Song.new()
	if s.load_from_sspm(path) is String:
		return ""
	return s.compute_chart_hash()

func _process(_d):
	if _thread == null or _thread.is_alive():
		return
	_hashes[_thread_key] = String(_thread.wait_to_finish())
	_thread = null
	set_process(false)
	_refresh()

func _ask(body: String, title: String, options: Array) -> int:
	Globals.confirm_prompt.s_alert.play()
	Globals.confirm_prompt.open(body, title, options)
	var picked = yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.s_back.play()
	Globals.confirm_prompt.close()
	yield(Globals.confirm_prompt, "done_closing")
	return picked

func _on_pressed():
	var song = Rhythia.selected_song
	var path := _local_file(song)
	var want := String(_want.get(String(song.id), "")) if song != null else ""
	if _busy or path == "" or want == "":
		return
	var picked = yield(_ask("Your copy of \"%s\" has different notes than the ranked version, so passes on it don't count.\n\nDownload the ranked version and use it instead? Your copy is kept in the map_backups folder." % String(song.name),
		"Get the ranked version", [{text = "Cancel"}, {text = "Get it"}]), "completed")
	if picked != 1:
		return
	_busy = true
	disabled = true
	text = "Downloading..."
	var err = yield(_install(song, path, want), "completed")
	_busy = false
	disabled = false
	text = "Get the ranked version"
	if err != "":
		Globals.notify(Globals.NOTIFY_WARN, err, String(song.name))
	_refresh()

# -> "" when it's done, else what went wrong
func _install(song, path: String, want: String) -> String:
	yield(get_tree(), "idle_frame") # (always a function state for the caller)
	var req := HTTPRequest.new()
	req.timeout = 120
	req.use_threads = OS.can_use_threads()
	add_child(req)
	var url: String = Rhythia.pass_url(RANKED_MAP_URL % String(song.id).http_escape())
	if req.request(url) != OK:
		req.queue_free()
		return "Couldn't start the download."
	var res: Array = yield(req, "request_completed")
	req.queue_free()
	var data = res[3]
	if res[0] != HTTPRequest.RESULT_SUCCESS:
		return "The download failed. Try again."
	if res[1] == 404:
		return "The server doesn't have the ranked version of this map."
	if res[1] != 200 or not (data is PoolByteArray) or data.size() < 8:
		return "The download failed (error %d). Try again." % res[1]

	# checked before anything of yours is moved
	var dir := Directory.new()
	dir.make_dir_recursive(Globals.p("user://cache"))
	var tmp: String = Globals.p("user://cache/ranked_copy.sspm")
	if not _write(tmp, data):
		return "Couldn't save the download."
	var check = Song.new()
	if check.load_from_sspm(tmp) is String or check.compute_chart_hash() != want:
		dir.remove(tmp)
		return "The server's copy doesn't match the ranked version either. Tell a ranker."

	# A new file name, not yours: the map list's cache remembers files by name.
	var base := path.get_basename()
	var dest := base + "_ranked.sspm"
	var n := 2
	while dir.file_exists(dest):
		dest = "%s_ranked%d.sspm" % [base, n]
		n += 1
	if dir.copy(tmp, dest) != OK:
		dir.remove(tmp)
		return "Couldn't save the ranked version next to your copy."
	dir.remove(tmp)

	# your copy goes to the backups folder (out of the map list)
	var backups: String = Globals.p(BACKUP_DIR)
	dir.make_dir_recursive(backups)
	var backup := backups.plus_file(path.get_file())
	n = 2
	while dir.file_exists(backup):
		backup = backups.plus_file("%s (%d).sspm" % [path.get_file().get_basename(), n])
		n += 1
	if dir.rename(path, backup) != OK:
		if dir.copy(path, backup) != OK or dir.remove(path) != OK:
			dir.remove(dest)
			return "Couldn't move your copy out of the way, so nothing was changed."

	var reg = Rhythia.registry_song
	reg.check_and_remove_id(String(song.id))
	var added = reg.add_sspm_map(dest)
	var list = Rhythia.menu_node("Main/Maps/MapRegistry/S/VBoxContainer")
	if list != null and list.has_method("refresh_songs"):
		list.refresh_songs()
	if added == null:
		return "The ranked version downloaded but failed to load."
	_hashes[_key(dest)] = want
	Rhythia.select_song(added)
	Globals.notify(Globals.NOTIFY_SUCCEED, "You now have the ranked version. Your old copy is in the map_backups folder.", String(added.name))
	return ""

func _write(path: String, data: PoolByteArray) -> bool:
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		return false
	f.store_buffer(data)
	f.close()
	return true

extends Node

const CACHE_DIR := "user://caches"

var mapdb_apis: Array = [
	"https://cdn.rhythia.net/index.json",
	"https://savvyscripter-gh.github.io/savia_db/index.json",
	"https://savia.nysr.host/ranked-maps/index.json"
]

# The browser version can't read the databases above directly (their hosts
# don't allow it), so it reads copies kept in the web-db branch by
# .github/workflows/web-db.yml, with download links moved to rhythia.com's
# archive where possible.
const WEB_DB_BASE := "https://raw.githubusercontent.com/iloverhythia/savia/web-db/"

func is_web() -> bool:
	return OS.has_feature("JavaScript")

const WEB_DB_CDN := "https://cdn.jsdelivr.net/gh/iloverhythia/savia@web-db/"
const WEB_FULL_URL := "https://iloverhythia.github.io/Chromia/"

func _js_eval(code: String):
	var js = Engine.get_singleton("JavaScript")
	if js == null:
		return null
	return js.eval(code, true)

# True when running inside a page that can't reach other sites (the Claude
# artifact): its page sets window.CHROMIA_EMBEDDED and ships the database
# copies next to itself.
func is_embedded() -> bool:
	return is_web() and bool(_js_eval("!!window.CHROMIA_EMBEDDED"))

# Where to get database api_idx from, in order of preference.
func db_urls(api_idx: int) -> Array:
	if not is_web():
		return [mapdb_apis[api_idx]]
	var name := "db%d.json" % api_idx
	var urls := [WEB_DB_BASE + name, WEB_DB_CDN + name]
	if is_embedded():
		var local = _js_eval("new URL('%s', location.href).href" % name)
		if typeof(local) == TYPE_STRING and local != "":
			urls.append(local)
	return urls

func db_url(api_idx: int) -> String:
	return db_urls(api_idx)[0]

var map_registry: Registry

signal db_maps_done
signal map_downloaded

signal _httpreq_finished

var mapdl_hr: HTTPRequest = HTTPRequest.new()
var mapdl_bs: float = 1
var mapdl_bd: float = 0

signal _mapdl_req
func _on_mapdl_request_completed(result: int, response_code: int, headers: PoolStringArray, body: PoolByteArray):
	emit_signal("_mapdl_req", {result = result, response_code = response_code, headers = headers, body = body})

func cancel():
	mapdl_hr.cancel_request()
	emit_signal("_mapdl_req", {result = -1})

func mapdl_error(id: String, error: String, map: Song):
	if error != "Cancelled" and is_embedded():
		error += " - this page can't download from other sites. Get maps in the full web version: " + WEB_FULL_URL
	print("[MapDB Download] Map %s errored with code %s" % [map.id, error])
	emit_signal("map_downloaded", {id = id, success = false, error = error})

func _process(_d):
	mapdl_bs = mapdl_hr.get_body_size()
	mapdl_bd = mapdl_hr.get_downloaded_bytes()

signal _connection_test
var ctest_hr: HTTPRequest = HTTPRequest.new()
func _on_ctest_request_completed(result: int, response_code: int, headers: PoolStringArray, body: PoolByteArray):
	if result == HTTPRequest.RESULT_SUCCESS:
		emit_signal("_connection_test", true)
	else:
		emit_signal("_connection_test", false)

func test_connection():
	if is_web():
		# the test site doesn't allow browser requests; a failed database
		# download reports the problem instead
		emit_signal("_connection_test", true)
		return
	var res = ctest_hr.request(ProjectSettings.get_setting("application/networking/test_url"))
	if res != OK: emit_signal("_connection_test", false)

func _mapdl_handler(id: String, map: Song):
	print("[MapDB Download] Starting download of map %s" % map.id)
	if not ProjectSettings.get_setting("application/networking/enabled"):
		mapdl_error(id, "Networking is disabled", map); return
	if mapdb_apis.empty():
		mapdl_error(id, "MapDB APIs Invalid", map); return
	print(id)
	if is_web() and map.web_blocked:
		mapdl_error(id, "This map's host doesn't allow downloads from the browser. Get it in the desktop client, or look for it in the Map Browser.", map); return

	call_deferred("test_connection")
	if not yield(self, "_connection_test"):
		mapdl_error(id, "Failed to connect", map); return

	var dir: Directory = Directory.new()
	if dir.file_exists(Globals.p("user://mapdl.sspm.part")):
		dir.remove(Globals.p("user://mapdl.sspm.part"))

	mapdl_hr.download_file = Globals.p("user://mapdl.sspm.part")
	var res = mapdl_hr.request(map.download_url)
	if res != OK:
		if res == ERR_INVALID_PARAMETER: mapdl_error(id, "Invalid Parameter", map)
		elif res == ERR_CANT_CONNECT: mapdl_error(id, "Can't Connect", map)
		else: mapdl_error(id, "Unknown Error (%s)" % res, map)
	else:
		var mapdl_res = yield(self, "_mapdl_req")

		if mapdl_res.result == HTTPRequest.RESULT_CANT_RESOLVE:
			mapdl_error(id, "Can't Resolve", map)
		elif mapdl_res.result == HTTPRequest.RESULT_CANT_CONNECT:
			mapdl_error(id, "Can't Connect", map)
		elif mapdl_res.result == HTTPRequest.RESULT_CONNECTION_ERROR:
			mapdl_error(id, "Connection Error", map)
		elif mapdl_res.result == HTTPRequest.RESULT_SSL_HANDSHAKE_ERROR:
			mapdl_error(id, "SSL Handshake Error", map)
		elif mapdl_res.result == HTTPRequest.RESULT_TIMEOUT:
			mapdl_error(id, "Timeout", map)
		elif mapdl_res.result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
			mapdl_error(id, "Redirect Limit Reached", map)
		elif mapdl_res.result == HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			mapdl_error(id, "Download File Open Error", map)
		elif mapdl_res.result == HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			mapdl_error(id, "Download File Write Error", map)

		if mapdl_res.result == HTTPRequest.RESULT_SUCCESS:
			if mapdl_res.response_code == 200:
				var old_db_id = map.id
				dir.rename(Globals.p("user://mapdl.sspm.part"), Globals.p("user://maps/%s.sspm" % old_db_id))

				map.load_from_sspm(Globals.p("user://maps/%s.sspm" % old_db_id))
				map.id = old_db_id
				map.is_online = false
				if map.songType != Globals.MAP_SSPM2:
					if Input.is_action_pressed("skip_convert"):
						Globals.notify(
							Globals.NOTIFY_WARN,
							"Not converting to SSPMv2 as Ctrl+M was held.",
							"Skip Conversion"
						)
					else:
						map.convert_to_sspm(true)
				map_registry.emit_signal("item_updated", map)
				emit_signal("map_downloaded", {id = id, success = true})
			else:
				var resp = parse_json(mapdl_res.body.get_string_from_utf8())
				if resp: mapdl_error(id, resp.error, map)
				else: mapdl_error(id, "HTTP-%s" % mapdl_res.response_code, map)
		elif mapdl_res.result == -1:
			mapdl_error(id, "Cancelled", map)
		else:
			mapdl_error(id, "Unknown Error", map)


func download_map(map: Song):
	var id = v4()
	call_deferred("_mapdl_handler", id, map)
	return id


signal _dbmap_batch_done
func _dbmap_retry(hr: HTTPRequest, url: String, api_idx: int):
	if hr.request(url) != OK:
		_on_dbmap_request_completed(ERR_CANT_CONNECT, 0, PoolStringArray(), PoolByteArray(), api_idx)

var _dbmap_results: Array = []
var _dbmap_pending: int = 0
var _dbmap_fallbacks: Dictionary = {} # api_idx -> [HTTPRequest, [urls left to try]]
func _on_dbmap_request_completed(result: int, response_code: int, headers: PoolStringArray, body: PoolByteArray, api_idx: int):
	var fb = _dbmap_fallbacks.get(api_idx)
	if fb != null and not fb[1].empty() and (result != HTTPRequest.RESULT_SUCCESS or response_code != 200):
		var next_url: String = fb[1].pop_front()
		print("[MapDB] trying %s" % next_url)
		call_deferred("_dbmap_retry", fb[0], next_url, api_idx)
		return
	_dbmap_results[api_idx] = {result = result, response_code = response_code, headers = headers, body = body}
	_dbmap_pending -= 1
	if _dbmap_pending == 0:
		emit_signal("_dbmap_batch_done")

const weekday = [
	"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
]
const month = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]

func _migrate_legacy_cache_files():
	var dir := Directory.new()
	dir.open(Globals.p("user://"))
	var legacy = Globals.get_files_recursive([Globals.p("user://")], 1, "").files
	for path in legacy:
		var fname = path.get_file()
		if not fname.begins_with(".mapdb_cache_") and not fname.begins_with(".mapdb_updated_"):
			continue
		var dest = path.get_base_dir().plus_file("caches").plus_file(fname)
		if dir.file_exists(dest):
			continue
		dir.rename(path, dest)

# Imports the online map database saved from the last run, so online maps are
# in the list as soon as the menu opens. Returns true if any cache was loaded.
func load_cached_db_maps():
	yield(get_tree(), "idle_frame")
	_migrate_legacy_cache_files()
	var loaded := false
	for api_idx in range(mapdb_apis.size()):
		var cache_file: String = Globals.p(CACHE_DIR.plus_file(".mapdb_cache_%d.json" % api_idx))
		var file := File.new()
		if not file.file_exists(cache_file) or file.open(cache_file, File.READ) != OK:
			continue
		var text := file.get_as_text()
		file.close()
		if yield(_import_netmaps_threaded(text), "completed"):
			loaded = true
	return loaded

func load_db_maps():
	yield(get_tree(), "idle_frame")

	var dir := Directory.new()
	if not dir.dir_exists(Globals.p(CACHE_DIR)):
		dir.make_dir_recursive(Globals.p(CACHE_DIR))
	_migrate_legacy_cache_files()

	if not ProjectSettings.get_setting("application/networking/enabled"):
		emit_signal("db_maps_done")
		return

	if mapdb_apis.empty():
		show_db_error("Map databases are improperly configured.", "Map Database Error")
		yield(self, "error_done")
		emit_signal("db_maps_done")
		return

	call_deferred("test_connection")
	if not yield(self, "_connection_test"):
		Globals.notify(
			Globals.NOTIFY_ERROR,
			"Online maps will not be loaded - failed to connect to map databases.\n\nMake sure your system clock is Synchronized!",
			"No Connection"
		)
		emit_signal("db_maps_done")
		return

	var failed_dbs = 0

	_dbmap_results = []
	_dbmap_results.resize(mapdb_apis.size())
	_dbmap_pending = mapdb_apis.size()
	_dbmap_fallbacks = {}
	var requesters := []
	for api_idx in range(mapdb_apis.size()):
		var urls := db_urls(api_idx)
		var current_api: String = urls.pop_front()

		var file: File = File.new()
		var dict_date = Time.get_datetime_dict_from_unix_time(1373)
		var cache_file = Globals.p(CACHE_DIR.plus_file(".mapdb_cache_%d.json" % api_idx))
		var update_file = Globals.p(CACHE_DIR.plus_file(".mapdb_updated_%d.txt" % api_idx))

		if file.file_exists(cache_file) and file.file_exists(update_file):
			var err = file.open(update_file, File.READ)
			if err == OK:
				dict_date = Time.get_datetime_dict_from_datetime_string(file.get_as_text(), true)
			file.close()

		var hr := HTTPRequest.new()
		add_child(hr)
		hr.use_threads = OS.can_use_threads()
		hr.timeout = 80
		hr.connect("request_completed", self, "_on_dbmap_request_completed", [api_idx])
		requesters.append(hr)
		if not urls.empty():
			_dbmap_fallbacks[api_idx] = [hr, urls]
		var request_headers := PoolStringArray()
		# (browser: no extra headers, the mirror host refuses them; the browser's
		# own cache does the job)
		if not is_web():
			request_headers.append("If-Modified-Since: %s, %02d %s %04d %02d:%02d:%02d GMT" % [
				weekday[dict_date.weekday],
				dict_date.day, month[dict_date.month - 1], dict_date.year,
				dict_date.hour, dict_date.minute, dict_date.second
			])
		var request_error = hr.request(current_api, request_headers)
		if request_error != OK:
			_on_dbmap_request_completed(request_error, 0, PoolStringArray(), PoolByteArray(), api_idx)

	if _dbmap_pending > 0:
		yield(self, "_dbmap_batch_done")

	_dbmap_fallbacks = {}
	for hr in requesters:
		hr.queue_free()

	for api_idx in range(mapdb_apis.size()):
		var current_api = db_url(api_idx)
		var netmaps_res = _dbmap_results[api_idx]
		var file: File = File.new()
		var cache_file = Globals.p(CACHE_DIR.plus_file(".mapdb_cache_%d.json" % api_idx))
		var update_file = Globals.p(CACHE_DIR.plus_file(".mapdb_updated_%d.txt" % api_idx))

		if netmaps_res.result != HTTPRequest.RESULT_SUCCESS:
			print("HTTP Error connecting to %s" % current_api)
			failed_dbs += 1
			continue

		if netmaps_res.response_code == 200:
			print("Cache miss for %s!" % current_api)
			var res = file.open(cache_file, File.WRITE)
			if res == OK:
				file.store_buffer(netmaps_res.body)
			file.close()
			if res == OK:
				res = file.open(update_file, File.WRITE)
				if res == OK:
					file.store_string(Time.get_datetime_string_from_system(true))
				file.close()

			if not yield(_import_netmaps_threaded(netmaps_res.body.get_string_from_utf8()), "completed"):
				print("Map database %s downloaded but JSON is malformed" % current_api)
				failed_dbs += 1

		elif netmaps_res.response_code == 304:
			print("Cache hit for %s!" % current_api)
			var res = file.open(cache_file, File.READ)
			if res == OK:
				var cache_text = file.get_as_text()
				file.close()
				if not yield(_import_netmaps_threaded(cache_text), "completed"):
					dir.remove(cache_file)
					dir.remove(update_file)
		else:
			print("Map database %s download failed. HTTP Code: %s" % [current_api, netmaps_res.response_code])
			failed_dbs += 1

	if failed_dbs >= mapdb_apis.size():
		show_db_error("All map databases failed to download.", "Map Database Error")
		yield(self, "error_done")

	emit_signal("db_maps_done")







func _slugify_id(id: String) -> String:
	var s := id.to_lower()
	var allowed := "abcdefghijklmnopqrstuvwxyz0123456789_-"
	var out := ""
	for i in range(s.length()):
		var c = s[i]
		out += (c if allowed.find(c) != -1 else "_")
	if out == "" or out.begins_with("_"):
		out = "m" + out
	return out

signal _netmaps_imported

# Reading the map database JSON (megabytes) runs on a worker thread, but the
# maps are added to the registry on the main thread, a few ms per frame. Adding
# them from the worker crashed the game: the menu, star ratings and thumbnails
# read the registry's arrays at the same time. Returns true if the JSON was a
# valid map database.
# Time per frame for adding maps: big on the loading screen, small once the menu is up.
var import_budget_usec := 4000
var _imported_hashes := {}
var _imported_registry_id: int = 0

func _import_netmaps_threaded(json_text: String):
	# Reload Content makes a new map registry: everything has to be imported into it again.
	if map_registry != null and map_registry.get_instance_id() != _imported_registry_id:
		_imported_hashes = {}
		_imported_registry_id = map_registry.get_instance_id()
	# The same database text (cache, then an unchanged download) only needs importing once.
	var h := json_text.hash()
	if _imported_hashes.has(h):
		yield(get_tree(), "idle_frame")
		return true
	var nmp = null
	var thread := Thread.new()
	if OS.can_use_threads() and thread.start(self, "_netmaps_parse_worker", json_text) == OK:
		# Wait for this import's own parser: with two imports at once (Reload
		# Content during the background download) the shared signal woke both,
		# and wait_to_finish() then froze the game until the other one was done.
		yield(get_tree(), "idle_frame") # (always yields once: callers wait for "completed")
		while thread.is_alive():
			yield(get_tree(), "idle_frame")
		nmp = thread.wait_to_finish()
	else:
		yield(get_tree(), "idle_frame")
		nmp = parse_json(json_text)
	if not (nmp is Dictionary):
		return false
	yield(_import_netmaps_chunked(nmp), "completed")
	_imported_hashes[h] = true
	return true

func _netmaps_parse_worker(json_text: String):
	var nmp = parse_json(json_text)
	call_deferred("emit_signal", "_netmaps_imported")
	return nmp

func _import_netmaps_chunked(netmaps: Dictionary):
	yield(get_tree(), "idle_frame")
	var dir := Directory.new()
	var known_slugs := {}
	var known_ids := {}
	for existing in map_registry.get_items():
		known_ids[String(existing.id)] = true
		known_slugs[_slugify_id(String(existing.id))] = true
	var failed := 0
	var t_start := OS.get_ticks_msec()
	var t0 := OS.get_ticks_usec()
	for id in netmaps.keys():
		if Rhythia.get("_quitting"):
			return
		if OS.get_ticks_usec() - t0 > import_budget_usec:
			yield(get_tree(), "idle_frame")
			t0 = OS.get_ticks_usec()
		if not (netmaps[id] is Dictionary):
			failed += 1
			continue
		if known_ids.has(String(id)):
			continue
		var slug := _slugify_id(String(id))
		if known_slugs.has(slug):
			continue
		if dir.file_exists(Globals.p("user://maps/%s.sspm" % id)):
			continue
		var song: Song = Song.new()
		var result: Dictionary = song.load_from_db_data(netmaps[id])
		if result.success:
			map_registry.add_item(song)
			known_slugs[slug] = true
		else:
			failed += 1
	print("[MapDB Import] %d entries in %d ms" % [netmaps.size(), OS.get_ticks_msec() - t_start])
	if failed > 0:
		print("[MapDB Import] %d maps skipped (bad data)" % failed)

func _import_netmaps(netmaps: Dictionary):
	# kept for callers that import synchronously
	var dir := Directory.new()
	var known_slugs := {}
	for existing in map_registry.get_items():
		known_slugs[_slugify_id(String(existing.id))] = true
	for id in netmaps.keys():
		if not (netmaps[id] is Dictionary):
			continue
		if known_slugs.has(_slugify_id(String(id))):
			continue
		if dir.file_exists(Globals.p("user://maps/%s.sspm" % id)):
			continue
		var song: Song = Song.new()
		if song.load_from_db_data(netmaps[id]).success:
			map_registry.add_item(song)
			known_slugs[_slugify_id(String(id))] = true

var latest_version_data
signal latest_version
signal update_finished

onready var version_hr: HTTPRequest = HTTPRequest.new()
onready var update_hr: HTTPRequest = HTTPRequest.new()

# Updates only ever come from this repository. It is fixed in code on purpose:
# a project setting could be changed by an override.cfg left behind by
# another game that shares the same user folder.
const UPDATE_REPO := "iloverhythia/Chromia"
# Release asset names, newest first (older releases used "Furria.pck" and "Savia.pck").
const UPDATE_PCK_NAMES := ["Chromia.pck", "Furria.pck", "Savia.pck"]

# The .pck that belongs to the running exe (Chromia.exe -> Chromia.pck; old installs keep Furria.exe -> Furria.pck).
static func local_pck_path() -> String:
	var exe := OS.get_executable_path()
	return exe.get_base_dir().plus_file(exe.get_file().get_basename() + ".pck")

# Builds that update by swapping the .pck next to the executable
# (macOS keeps it inside the .app, phones inside the app package).
static func can_self_update() -> bool:
	return OS.has_feature("Windows") or OS.has_feature("X11") or PackUpdate.supported()

# iOS can't replace its own files: it downloads the game pack into the user
# folder instead (loaded at the next start by scripts/PackUpdate.gd).
const IOS_PCK_NAME := "chromia-ios.pck"
static func updates_by_pack() -> bool:
	return PackUpdate.supported()

# The release files a pack update uses on this platform (iOS / Meta Quest).
static func pack_asset() -> String:
	return "chromia-quest.pck" if OS.has_feature("quest") else IOS_PCK_NAME
static func pack_compat_asset() -> String:
	return "chromia-quest-compat.txt" if OS.has_feature("quest") else "chromia-ios-compat.txt"
static func restart_hint() -> String:
	if OS.has_feature("quest"):
		return "Quit Chromia (Meta button, then Quit) and open it again to use it."
	return "Close Chromia completely (swipe it away in the app switcher) and open it again to use it."
static func app_asset() -> String:
	return "chromia-quest.apk" if OS.has_feature("quest") else "chromia-ios.ipa"

# Update channel (Settings > Update channel): "stable" takes the latest
# release, "test" the newest test build (a GitHub pre-release, built from the
# test branch; it talks to the test server). Switching channels offers the
# other channel's build even when its version looks older.
static func build_channel() -> String:
	return load("res://scripts/BuildChannel.gd").CHANNEL

# Testers: signed in with one of these Discord accounts, a game always takes
# test builds, on every device, and updates to them without asking
# (Savia.do_init, UpdateWatcher.gd). The Update channel button can't switch
# them back.
const TESTER_DISCORD_IDS := ["697113209051545640", "998599880324952114", "1356328388188438721"] # breck, Savvy, vroom

static func is_tester() -> bool:
	var du = Rhythia.get("discord_user")
	return du is Dictionary and TESTER_DISCORD_IDS.has(String(du.get("id", "")))

# the Update channel switch: for anyone who has run a test build once (or
# picked the test channel, or has a tester account), not for everyone
static func shows_channel_switch() -> bool:
	return build_channel() == "test" or is_tester() or bool(Rhythia.get("tried_test_builds")) or String(Rhythia.get("update_channel")) == "test"

static func wanted_channel() -> String:
	if is_tester():
		# testers start on test builds; the Update channel button switches them
		var tc = _saved_channel("tester_channel", Rhythia.get("tester_channel"))
		return String(tc) if tc is String and (tc == "stable" or tc == "test") else "test"
	var c = _saved_channel("update_channel", Rhythia.get("update_channel"))
	return String(c) if c is String and (c == "stable" or c == "test") else build_channel()

# The channel picked with the Update channel button. It's kept in its own file
# (user://update_channel.json, Savia.gd save_update_channel), not in the
# settings: the update check at startup runs before the settings are loaded,
# and settings profiles carry their own copy of every setting (switching
# profile switched builds). Older games only had it in the settings file the
# game starts from (the active profile, else settings.json).
const CHANNEL_FILE := "user://update_channel.json"

static func _saved_channel(key: String, fallback):
	for path in [Globals.p(CHANNEL_FILE), Rhythia.get_startup_settings_path()]:
		var f := File.new()
		if not f.file_exists(path) or f.open(path, File.READ) != OK:
			continue
		var parsed := JSON.parse(f.get_as_text())
		f.close()
		if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
			continue
		var v = parsed.result.get(key, null)
		if v is String and (v == "stable" or v == "test"):
			return v
	return fallback

func check_latest_version():
	if not can_self_update() or not ProjectSettings.get_setting("application/networking/enabled"):
		emit_signal("latest_version", ProjectSettings.get_setting("application/config/version"))
		return

	var github_url = "https://api.github.com/repos/%s/releases/latest" % UPDATE_REPO
	if wanted_channel() == "test":
		github_url = "https://api.github.com/repos/%s/releases?per_page=30" % UPDATE_REPO
	if version_hr.request(github_url) != OK:
		# Couldn't even start the request: answer "no update" instead of never answering.
		call_deferred("emit_signal", "latest_version", ProjectSettings.get_setting("application/config/version"))

func _on_version_request_completed(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		emit_signal("latest_version", ProjectSettings.get_setting("application/config/version"))
		return

	var json = JSON.parse(body.get_string_from_utf8())
	var current: String = ProjectSettings.get_setting("application/config/version")
	var found = json.result if json.error == OK else null
	if typeof(found) == TYPE_ARRAY:
		# the test channel: the newest test build (releases come newest first)
		var pick = null
		for r in found:
			if typeof(r) == TYPE_DICTIONARY and bool(r.get("prerelease", false)) and not bool(r.get("draft", false)):
				pick = r
				break
		found = pick
	if typeof(found) == TYPE_DICTIONARY and found.has("tag_name"):
		latest_version_data = found
		var tag := String(latest_version_data.tag_name)
		# Never "update" to a version that is older than this one (unless
		# switching channel: then the other channel's build is the one wanted).
		var seq: Array = Rhythia.VERSION_SEQUENCE
		if wanted_channel() == build_channel() and seq.has(tag) and seq.has(current) and seq.find(tag) <= seq.find(current):
			tag = current
		# iOS: an update that failed to start on this phone isn't offered again
		if updates_by_pack() and tag == _read_text(PackUpdate.DIR + "/bad_version.txt"):
			tag = current
		emit_signal("latest_version", tag)
	else:
		emit_signal("latest_version", ProjectSettings.get_setting("application/config/version"))

static func _read_text(path: String) -> String:
	var f := File.new()
	if not f.file_exists(path) or f.open(path, File.READ) != OK:
		return ""
	var t := f.get_as_text().strip_edges()
	f.close()
	return t

# "Remind me in a day" on the Update boxes: no update boxes (at startup or in
# the menu) until then. Settings > Check for Updates still works.
const SNOOZE_FILE := "user://update_snooze.json"

func snooze_updates(seconds: int = 86400):
	var f := File.new()
	if f.open(SNOOZE_FILE, File.WRITE) == OK:
		f.store_string(JSON.print({"until": OS.get_unix_time() + seconds}))
		f.close()

func update_snoozed() -> bool:
	var f := File.new()
	if not f.file_exists(SNOOZE_FILE) or f.open(SNOOZE_FILE, File.READ) != OK:
		return false
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return false
	var until := int(parsed.result.get("until", 0))
	# (a clock set far back mustn't hide updates for weeks)
	return until > OS.get_unix_time() and until - OS.get_unix_time() <= 86400 * 2

# manual: Settings > Check for Updates / Update channel (always allowed);
# otherwise the automatic checks, which never undo an update they just made
func attempt_update(manual: bool = false):
	update_blocked_reason = ""
	if not latest_version_data or not latest_version_data.has("assets"):
		emit_signal("update_finished")
		return
	var to := String(latest_version_data.get("tag_name", ""))
	var from := String(ProjectSettings.get_setting("application/config/version"))
	if not manual and _bounces_back(from, to):
		update_installed = false
		update_blocked_reason = "Not updating to %s: this game just updated from it, and going back would start an update loop. Pick a version in Settings > Update channel." % to
		Rhythia.trail("update loop stopped: %s -> %s" % [from, to])
		emit_signal("update_finished")
		return
	_note_update(from, to)

	if updates_by_pack():
		var why = yield(_pack_compatible(), "completed")
		if why != "":
			update_blocked_reason = why
			emit_signal("update_finished")
			return
	var download_url = ""
	var wanted_names: Array = [pack_asset()] if updates_by_pack() else UPDATE_PCK_NAMES
	for wanted in wanted_names:
		for asset in latest_version_data.assets:
			if asset.name == wanted:
				download_url = asset.browser_download_url
				break
		if download_url != "":
			break

	if download_url == "":
		print("No game .pck found in release assets.")
		emit_signal("update_finished")
		return

	var temp_path = local_pck_path() + ".tmp"
	if updates_by_pack():
		var d := Directory.new()
		if not d.dir_exists(PackUpdate.DIR):
			d.make_dir_recursive(PackUpdate.DIR)
		temp_path = PackUpdate.PACK + ".tmp"

	update_hr.download_file = temp_path
	update_hr.request(download_url)

var update_installed: bool = false # the last attempt_update() worked

# Update-loop guard: the last update (from -> to). An automatic update straight
# back to the version just left within a few minutes is stopped (two versions
# that each want the other restarted the game over and over).
const LAST_UPDATE_FILE := "user://last_update.json"
const BOUNCE_WINDOW_S := 15 * 60

static func _note_update(from: String, to: String):
	var f := File.new()
	if f.open(Globals.p(LAST_UPDATE_FILE), File.WRITE) == OK:
		f.store_string(JSON.print({"from": from, "to": to, "at": OS.get_unix_time()}))
		f.close()

static func _bounces_back(from: String, to: String) -> bool:
	var f := File.new()
	var path: String = Globals.p(LAST_UPDATE_FILE)
	if not f.file_exists(path) or f.open(path, File.READ) != OK:
		return false
	var parsed := JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return false
	var last: Dictionary = parsed.result
	if OS.get_unix_time() - int(last.get("at", 0)) >= BOUNCE_WINDOW_S:
		return false
	var lf := String(last.get("from", ""))
	var lt := String(last.get("to", ""))
	# straight back (to -> from), or the same update again: an older version in
	# between undid it (it never got this guard), so it would only loop
	return (lf == to and lt == from) or (lf == from and lt == to)
var update_blocked_reason: String = "" # pack updates: why this one can't be used

# A pack can only replace the game's files, not the app's list of startup
# scripts and script classes: those must match (res://pack_compat.txt, written
# by the release workflow). Returns "" when the latest pack fits this app.
func _pack_compatible():
	yield(get_tree(), "idle_frame")
	update_blocked_reason = ""
	var url := ""
	for asset in latest_version_data.get("assets", []):
		if asset.name == pack_compat_asset():
			url = asset.browser_download_url
	var f := File.new()
	var mine := ""
	if f.open("res://pack_compat.txt", File.READ) == OK:
		mine = f.get_as_text().strip_edges()
		f.close()
	if url == "" or mine == "":
		return "This update can't be installed from inside the app. Install the new %s instead." % app_asset()
	var hr := HTTPRequest.new()
	hr.use_threads = OS.can_use_threads()
	hr.timeout = 20
	add_child(hr)
	if hr.request(url) != OK:
		hr.queue_free()
		return "Couldn't check the update."
	var res = yield(hr, "request_completed")
	hr.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return "Couldn't check the update."
	if res[3].get_string_from_utf8().strip_edges() != mine:
		return "This update changes parts of the app that can only be updated by installing the new %s." % app_asset()
	return ""

func _on_update_request_completed(result, response_code, headers, body):
	update_installed = false
	if updates_by_pack():
		var tmp := PackUpdate.PACK + ".tmp"
		var dir := Directory.new()
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200 or not dir.file_exists(tmp):
			print("Pack download failed.")
			dir.remove(tmp)
			emit_signal("update_finished")
			return
		dir.remove(PackUpdate.PACK)
		if dir.rename(tmp, PackUpdate.PACK) == OK:
			var f := File.new()
			if f.open(PackUpdate.VERSION_FILE, File.WRITE) == OK:
				f.store_string(String(latest_version_data.tag_name))
				f.close()
				update_installed = true
				load("res://scripts/PackGuard.gd").fresh_download()
				print("Pack update downloaded: ", latest_version_data.tag_name)
		emit_signal("update_finished")
		return
	var final_path = local_pck_path()
	var temp_path = final_path + ".tmp"
	var backup_path = final_path + ".old"

	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("Download failed.")
		emit_signal("update_finished")
		return

	var dir = Directory.new()


	if dir.file_exists(backup_path):
		dir.remove(backup_path)


	if dir.file_exists(final_path):
		dir.rename(final_path, backup_path)


	var err = dir.rename(temp_path, final_path)

	if err == OK:
		update_installed = true
		print("Update successful. Restart required.")
	else:
		print("Error swapping files: ", err)
	emit_signal("update_finished")

func _ready():
	add_child(ctest_hr)
	ctest_hr.use_threads = OS.can_use_threads()
	ctest_hr.timeout = 5
	ctest_hr.connect("request_completed", self, "_on_ctest_request_completed")

	add_child(mapdl_hr)
	mapdl_hr.use_threads = false
	mapdl_hr.timeout = 0
	mapdl_hr.connect("request_completed", self, "_on_mapdl_request_completed")

	add_child(version_hr)
	version_hr.use_threads = OS.can_use_threads()
	version_hr.timeout = 5
	version_hr.connect("request_completed", self, "_on_version_request_completed")

	add_child(update_hr)
	update_hr.use_threads = OS.can_use_threads()
	update_hr.timeout = 0
	update_hr.connect("request_completed", self, "_on_update_request_completed")

	pause_mode = PAUSE_MODE_PROCESS

signal error_done
func show_db_error(body: String, title: String):

	Globals.confirm_prompt.s_alert.play()
	Globals.confirm_prompt.open(body, title, [{text = "OK"}])
	yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.s_back.play()
	Globals.confirm_prompt.close()
	yield(Globals.confirm_prompt, "done_closing")
	emit_signal("error_done")

const MODULO_8_BIT = 256

static func getRandomInt():

	randomize()

	return randi() % MODULO_8_BIT

static func uuidbin():

	return [
	getRandomInt(), getRandomInt(), getRandomInt(), getRandomInt(),
	getRandomInt(), getRandomInt(), ((getRandomInt()) & 15) | 64, getRandomInt(),
	((getRandomInt()) & 63) | 128, getRandomInt(), getRandomInt(), getRandomInt(),
	getRandomInt(), getRandomInt(), getRandomInt(), getRandomInt(),
		]

static func v4():

	var b = uuidbin()

	return "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x" % [

	b[0], b[1], b[2], b[3],

	b[4], b[5],

	b[6], b[7],

	b[8], b[9],

	b[10], b[11], b[12], b[13], b[14], b[15]
		]

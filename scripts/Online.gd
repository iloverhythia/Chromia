extends Node

const CACHE_DIR := "user://caches"

var mapdb_apis: Array = [
	"https://cdn.rhythia.net/index.json",
	"https://savvyscripter-gh.github.io/savia_db/index.json",
	"https://savia.nysr.host/ranked-maps/index.json"
]

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
	var res = ctest_hr.request(ProjectSettings.get_setting("application/networking/test_url"))
	if res != OK: emit_signal("_connection_test", false)

func _mapdl_handler(id: String, map: Song):
	print("[MapDB Download] Starting download of map %s" % map.id)
	if not ProjectSettings.get_setting("application/networking/enabled"):
		mapdl_error(id, "Networking is disabled", map); return
	if mapdb_apis.empty():
		mapdl_error(id, "MapDB APIs Invalid", map); return
	print(id)

	if not OS.has_feature("HTML5"):
		call_deferred("test_connection")
	if not OS.has_feature("HTML5") and not yield(self, "_connection_test"):
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
var _dbmap_results: Array = []
var _dbmap_pending: int = 0
func _on_dbmap_request_completed(result: int, response_code: int, headers: PoolStringArray, body: PoolByteArray, api_idx: int):
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

	if not OS.has_feature("HTML5"):
		call_deferred("test_connection")
	if not OS.has_feature("HTML5") and not yield(self, "_connection_test"):
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
	var requesters := []
	for api_idx in range(mapdb_apis.size()):
		var current_api = mapdb_apis[api_idx]

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
		hr.use_threads = not OS.has_feature("HTML5")
		hr.timeout = 80
		hr.connect("request_completed", self, "_on_dbmap_request_completed", [api_idx])
		requesters.append(hr)
		var request_headers := PoolStringArray()
		if not OS.has_feature("HTML5"):
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

	for hr in requesters:
		hr.queue_free()

	for api_idx in range(mapdb_apis.size()):
		var current_api = mapdb_apis[api_idx]
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

			var nmp = parse_json(netmaps_res.body.get_string_from_utf8())
			if not (nmp is Dictionary):
				print("Map database %s downloaded but JSON is malformed" % current_api)
				failed_dbs += 1
			else:
				yield(_import_netmaps(nmp), "completed")

		elif netmaps_res.response_code == 304:
			print("Cache hit for %s!" % current_api)
			var res = file.open(cache_file, File.READ)
			if res == OK:
				var nmp = parse_json(file.get_as_text())
				if not (nmp is Dictionary):
					dir.remove(cache_file)
					dir.remove(update_file)
				else:
					yield(_import_netmaps(nmp), "completed")
			file.close()
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

func _import_netmaps(netmaps: Dictionary):
	yield(get_tree(), "idle_frame")
	var dir := Directory.new()
	var i = 0
	var interval = max(1, floor(float(netmaps.size()) / 100))





	var known_slugs := {}
	for existing in map_registry.get_items():
		known_slugs[_slugify_id(String(existing.id))] = true
	for id in netmaps.keys():
		var local_path = Globals.p("user://maps/%s.sspm" % id)
		if dir.file_exists(local_path):
			continue
		if map_registry.idx_id.has(id):
			continue
		if known_slugs.has(_slugify_id(id)):
			continue

		var song: Song = Song.new()
		var result: Dictionary = song.load_from_db_data(netmaps[id])

		if result.success:
			map_registry.add_item(song)
			known_slugs[_slugify_id(id)] = true
		else:
			print("[MapDB Import] Map %s errored with code %s" % [id, result.error])






		i += 1
		if fmod(i, interval) == 0:
			yield(get_tree(), "idle_frame")

var latest_version_data
signal latest_version
signal update_finished

onready var version_hr: HTTPRequest = HTTPRequest.new()
onready var update_hr: HTTPRequest = HTTPRequest.new()

func check_latest_version():
	if not OS.has_feature("Windows") or not ProjectSettings.get_setting("application/networking/enabled"):
		emit_signal("latest_version", ProjectSettings.get_setting("application/config/version"))
		return

	var repo = ProjectSettings.get_setting("application/networking/github_repo")
	var github_url = "https://api.github.com/repos/%s/releases/latest" % repo
	version_hr.request(github_url)

func _on_version_request_completed(result, response_code, headers, body):
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		emit_signal("latest_version", ProjectSettings.get_setting("application/config/version"))
		return

	var json = JSON.parse(body.get_string_from_utf8())
	if json.error == OK:
		latest_version_data = json.result
		emit_signal("latest_version", latest_version_data.tag_name)

func attempt_update():
	if not latest_version_data or not latest_version_data.has("assets"):
		emit_signal("update_finished")
		return

	var download_url = ""
	for asset in latest_version_data.assets:
		if asset.name == "Savia.pck":
			download_url = asset.browser_download_url
			break

	if download_url == "":
		print("Savia.pck not found in release assets.")
		emit_signal("update_finished")
		return

	var exec_dir = OS.get_executable_path().get_base_dir()
	var final_path = exec_dir.plus_file("Savia.pck")
	var temp_path = exec_dir.plus_file("Savia.pck.tmp")

	update_hr.download_file = temp_path
	update_hr.request(download_url)

func _on_update_request_completed(result, response_code, headers, body):
	var exec_dir = OS.get_executable_path().get_base_dir()
	var final_path = exec_dir.plus_file("Savia.pck")
	var temp_path = exec_dir.plus_file("Savia.pck.tmp")
	var backup_path = exec_dir.plus_file("Savia.pck.old")

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
		print("Update successful. Restart required.")
	else:
		print("Error swapping files: ", err)
	emit_signal("update_finished")

func _ready():
	add_child(ctest_hr)
	ctest_hr.use_threads = not OS.has_feature("HTML5")
	ctest_hr.timeout = 5
	ctest_hr.connect("request_completed", self, "_on_ctest_request_completed")

	add_child(mapdl_hr)
	mapdl_hr.use_threads = false
	mapdl_hr.timeout = 0
	mapdl_hr.connect("request_completed", self, "_on_mapdl_request_completed")

	add_child(version_hr)
	version_hr.use_threads = not OS.has_feature("HTML5")
	version_hr.timeout = 5
	version_hr.connect("request_completed", self, "_on_version_request_completed")

	add_child(update_hr)
	update_hr.use_threads = not OS.has_feature("HTML5")
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

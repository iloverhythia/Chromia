extends Node

# Old Savia / Furria installs on Windows: their exe (Savia.exe, Furria.exe)
# runs Chromia's game files (the last Savia release ships Chromia as
# Savia.pck). This installs the real Chromia (Chromia.exe, Chromia.pck and
# its DLLs) in a "Chromia" folder next to the old exe, then the game hands
# over to it. Both read the same data folder (user://, "SoundSpacePlus"),
# so it's the same player, maps and settings.
#
# Installed in its own folder: the running old exe has the DLLs next to it
# open, so they couldn't be replaced. If anything fails, the game just runs
# on in the old exe (it is Chromia already) and tries again next start.

signal progress(text)
signal done(exe_path) # "" when it didn't work out

const ZIP_URL := "https://github.com/iloverhythia/Chromia/releases/latest/download/chromia-windows.zip"
const OLD_NAMES := ["savia", "furria"]

static func should_run() -> bool:
	if not OS.has_feature("Windows") or OS.has_feature("editor"):
		return false
	return OLD_NAMES.has(OS.get_executable_path().get_file().get_basename().to_lower())

static func install_dir() -> String:
	return OS.get_executable_path().get_base_dir().plus_file("Chromia")

static func chromia_exe() -> String:
	return install_dir().plus_file("Chromia.exe")

static func installed() -> bool:
	var f := File.new()
	return f.file_exists(chromia_exe()) and f.file_exists(install_dir().plus_file("Chromia.pck"))

var _http: HTTPRequest
var _timer: Timer
var _zip := ""

func start():
	if installed():
		call_deferred("emit_signal", "done", chromia_exe())
		return
	var dir := Directory.new()
	if dir.make_dir_recursive(install_dir()) != OK:
		call_deferred("_fail", "can't create " + install_dir())
		return
	_zip = install_dir().plus_file("chromia-windows.zip")
	_http = HTTPRequest.new()
	_http.use_threads = true
	_http.download_file = _zip
	add_child(_http)
	_http.connect("request_completed", self, "_downloaded")
	_timer = Timer.new()
	_timer.wait_time = 0.5
	add_child(_timer)
	_timer.connect("timeout", self, "_tick")
	_timer.start()
	if _http.request(ZIP_URL) != OK:
		call_deferred("_fail", "couldn't start the download")

func _tick():
	var got: int = _http.get_downloaded_bytes()
	var total: int = _http.get_body_size()
	if total > 0:
		emit_signal("progress", "Installing Chromia: downloading %d / %d MB" % [got / 1048576, total / 1048576])
	else:
		emit_signal("progress", "Installing Chromia: downloading %d MB" % (got / 1048576))

func _downloaded(result, code, _headers, _body):
	if _timer != null:
		_timer.stop()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_fail("download failed (%d, HTTP %d)" % [result, code])
		return
	emit_signal("progress", "Installing Chromia: unpacking")
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	# Godot 3 can't open zip files: Windows' own tools unpack it
	var out := []
	var cmd: String = "Expand-Archive -LiteralPath '%s' -DestinationPath '%s' -Force" % [_zip.replace("'", "''"), install_dir().replace("'", "''")]
	OS.execute("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", cmd], true, out, true)
	if not installed():
		out = []
		OS.execute("tar.exe", ["-xf", _zip, "-C", install_dir()], true, out, true)
	Directory.new().remove(_zip)
	if installed():
		print("[chromia install] installed in ", install_dir())
		emit_signal("done", chromia_exe())
	else:
		_fail("couldn't unpack: " + PoolStringArray(out).join(" ").substr(0, 300))

func _fail(why: String):
	print("[chromia install] not installed: ", why)
	if _zip != "":
		Directory.new().remove(_zip)
	emit_signal("done", "")

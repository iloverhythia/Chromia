extends Reference

# iPhone native helpers in ChromiaPicker.framework (ios/picker/ChromiaPicker.m,
# put into the .ipa by the release workflow). The game talks to it through
# files in Documents/.chromia_picker: it writes a request, then loads the
# library with GDNative, whose init function reads it.
# Only an installed .ipa brings (or updates) the framework; in-app updates can't.

const FRAMEWORK := "Frameworks/ChromiaPicker.framework/ChromiaPicker"

static func available() -> bool:
	if not OS.has_feature("iOS") or not ClassDB.class_exists("GDNative"):
		return false
	return File.new().file_exists(OS.get_executable_path().get_base_dir().plus_file(FRAMEWORK))

static func dir() -> String:
	return OS.get_user_data_dir().plus_file(".chromia_picker")

# Writes `text` to `file` in dir() and runs the library's init.
static func send(file: String, text: String) -> bool:
	if not available():
		return false
	var d := Directory.new()
	d.make_dir_recursive(dir())
	var f := File.new()
	if f.open(dir().plus_file(file), File.WRITE) != OK:
		return false
	f.store_string(text)
	f.close()
	var cfg := ConfigFile.new()
	cfg.set_value("entry", "iOS", OS.get_executable_path().get_base_dir().plus_file(FRAMEWORK))
	cfg.set_value("dependencies", "iOS", [])
	# every initialize() runs the library's init, which reads the request
	cfg.set_value("general", "load_once", false)
	var lib = ClassDB.instance("GDNativeLibrary")
	lib.config_file = cfg
	var g = ClassDB.instance("GDNative")
	g.library = lib
	var ok: bool = g.initialize()
	# keep them (unloading the library while its window is open would crash)
	var keep: Array = Engine.get_meta("ios_native_keep") if Engine.has_meta("ios_native_keep") else []
	keep.append(g)
	keep.append(lib)
	Engine.set_meta("ios_native_keep", keep)
	if not ok:
		d.remove(dir().plus_file(file))
	return ok

# Refresh rate (0 = leave) and touch delay in seconds (-1 = leave).
# Returns what the app reported, or "" when this app can't do it yet.
static func tune(fps: int, touch_delay: float) -> String:
	var ok_path := dir().plus_file("tune_ok.txt")
	Directory.new().remove(ok_path)
	if not send("tune.txt", "%d\n%s\n" % [fps, str(touch_delay)]):
		return ""
	var f := File.new()
	if f.file_exists(ok_path) and f.open(ok_path, File.READ) == OK:
		var t := f.get_as_text().strip_edges()
		f.close()
		return t if t != "" else "ok"
	return ""

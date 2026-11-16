extends Reference

# Anti-cheat info sent with a ranked pass (Savia.report_map_completion):
#  - dlls: every DLL loaded into Chromia (Windows: tasklist /m on this process;
#    Linux: the libraries in /proc/self/maps), so injected ones show up for
#    admins
#  - cheat_tools: Cheat Engine, if it is running (only the matching process
#    names are sent, never your other programs) or its DLLs are in Chromia
#
# Linux: the programs come from /proc (each one's name and command line), so
# Cheat Engine run through Wine or Proton is found by its .exe name, and so are
# Linux's own memory editors (Cheat Engine's ceserver, scanmem / GameConqueror,
# PINCE). A program attached to Chromia as a debugger (how those read and write
# a game's memory) is named in the DLL list for admins, and counts when it's
# one of them. The Windows build running in Wine / Proton also looks through
# Linux's /proc (as Z:/proc): Wine's own tasklist only sees programs in the
# same Wine prefix. macOS: ps.
# The server refuses ranked passes while Cheat Engine is found and logs it
# for admins. Scans run on a thread (tasklist takes a moment), each time the
# menu opens (menu2.gd) and when a score is sent, and the two are combined.
#
# Never while a song plays. It used to run at every song's start: about two
# seconds in, when tasklist goes through Chromia's own DLLs, the whole game
# stood still for 0.2 to 0.6 s on some PCs. A map whose first note comes
# early had that note pop in late, right in front of you, or not show at all.

signal done

const CE_PROCESSES := ["cheatengine", "cheat engine", "dbk64", "dbk32", "cetrainer",
	"ceserver", "scanmem", "gameconqueror", "pince"] # (the last four: Linux)
# what Cheat Engine puts into a game it attaches to (speedhack, debugger...)
const CE_DLLS := ["speedhack-", "vehdebug-", "allochook-", "luaclient-", "winhook-", "dbk64", "dbk32", "libspeedhack", "libceserver"]
const KEY := "chromia_process_scan"

var _thread: Thread = null
var busy := false
var result := {}      # the latest scan
var song_tools := []  # Cheat Engine finds since the song started

static func instance() -> Reference:
	if not Engine.has_meta(KEY):
		Engine.set_meta(KEY, load("res://scripts/ProcessScan.gd").new())
	return Engine.get_meta(KEY)

static func supported() -> bool:
	return OS.get_name() in ["Windows", "X11", "OSX"] and not OS.has_feature("JavaScript")

# a new song: its finds start from what the scan before it saw (the menu's).
# No scan now: see above.
static func song_started():
	var s = instance()
	s.song_tools = []
	for t in s.result.get("cheat_tools", []):
		s.song_tools.append(t)

# the menu is open: the scan for the songs that follow (a stall here isn't seen)
static func menu_opened():
	if supported():
		instance().start()

func start():
	if busy or not supported():
		return
	busy = true
	_thread = Thread.new()
	if _thread.start(self, "_scan", null, Thread.PRIORITY_LOW) != OK:
		busy = false
		_thread = null

func _scan(_u):
	var out := {"os": OS.get_name(), "dlls": [], "cheat_tools": [], "programs": []}
	if OS.get_name() == "X11":
		_scan_proc("/proc", out, true)
		call_deferred("_finished", out)
		return
	if OS.get_name() == "OSX":
		_scan_ps(out)
		call_deferred("_finished", out)
		return
	_scan_windows(out)
	# the Windows build in Wine / Proton: Linux's programs too
	if Directory.new().dir_exists("Z:/proc/self"):
		out["os"] = "Windows (Wine)"
		_scan_proc("Z:/proc", out, false)
	call_deferred("_finished", out)

func _scan_windows(out: Dictionary):
	var lines := []
	# DLLs in this process: "Chromia.exe","1234","a.dll,b.dll,..."
	OS.execute("tasklist", ["/m", "/fi", "PID eq %d" % OS.get_process_id(), "/fo", "csv", "/nh"], true, lines)
	var dlls := []
	for chunk in lines:
		for line in String(chunk).split("\n"):
			var parts := _csv(line)
			if parts.size() >= 3:
				for d in parts[2].split(","):
					d = d.strip_edges()
					if d != "" and d != "N/A" and not dlls.has(d):
						dlls.append(d)
	dlls.sort()
	out.dlls = dlls.slice(0, 399) if dlls.size() > 400 else dlls
	for d in dlls:
		var low: String = d.to_lower()
		for k in CE_DLLS:
			if low.find(k) != -1:
				out.cheat_tools.append("dll:" + d)
	# running programs: only Cheat Engine's names are kept
	lines = []
	OS.execute("tasklist", ["/fo", "csv", "/nh"], true, lines)
	for chunk in lines:
		for line in String(chunk).split("\n"):
			var parts := _csv(line)
			if parts.size() >= 1:
				_note_program(out, String(parts[0]))
				var low := String(parts[0]).to_lower()
				for k in CE_PROCESSES:
					if low.find(k) != -1 and not out.cheat_tools.has(parts[0]):
						out.cheat_tools.append(parts[0])

# a running program's name (only the name), for when the server asks
static func _note_program(out: Dictionary, nm: String):
	nm = nm.strip_edges().left(80)
	if nm != "" and out.programs.size() < 400 and not out.programs.has(nm):
		out.programs.append(nm)

static func _tool_in(text: String) -> bool:
	var low := text.to_lower()
	for k in CE_PROCESSES:
		if low.find(k) != -1:
			return true
	return false

# a /proc text file (their size reads as 0, so line by line)
static func _proc_text(path: String, max_lines: int = 400) -> PoolStringArray:
	var out := PoolStringArray()
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return out
	while not f.eof_reached() and out.size() < max_lines:
		out.append(f.get_line())
	f.close()
	return out

# a program's command line (its parts are split by zero bytes), the start of it
static func _cmdline(path: String) -> String:
	var f := File.new()
	if f.open(path, File.READ) != OK:
		return ""
	var b: PoolByteArray = f.get_buffer(300)
	f.close()
	for i in range(b.size()):
		if b[i] == 0:
			b[i] = 32
	return b.get_string_from_utf8()

# Linux (root "/proc"), or Linux seen from Wine ("Z:/proc"): running programs,
# and (own: this is the Linux build itself) the libraries in Chromia and
# whatever is attached to it
func _scan_proc(root: String, out: Dictionary, own: bool):
	var d := Directory.new()
	if d.open(root) == OK:
		d.list_dir_begin(true, true)
		var n := d.get_next()
		while n != "":
			if n.is_valid_integer():
				var comm: String = ""
				var c := _proc_text(root.plus_file(n).plus_file("comm"), 1)
				if c.size() > 0:
					comm = c[0].strip_edges()
				var cmd: String = _cmdline(root.plus_file(n).plus_file("cmdline"))
				_note_program(out, comm if comm != "" else cmd.get_file())
				if _tool_in(comm) or _tool_in(cmd):
					var nm: String = comm if comm != "" else cmd.get_file().left(60)
					if not out.cheat_tools.has(nm):
						out.cheat_tools.append(nm)
			n = d.get_next()
		d.list_dir_end()
	if not own:
		return
	# the libraries loaded into Chromia
	var libs := []
	for line in _proc_text(root.plus_file("self/maps"), 20000):
		var at: int = String(line).find("/")
		if at == -1:
			continue
		var lib: String = String(line).substr(at).get_file()
		if lib != "" and lib.find(".so") != -1 and not libs.has(lib):
			libs.append(lib)
	var pre := OS.get_environment("LD_PRELOAD")
	if pre != "":
		libs.append("LD_PRELOAD: " + pre.left(200))
	# something attached to Chromia as a debugger: named for admins, and a
	# cheat tool when it's one
	for line in _proc_text(root.plus_file("self/status"), 60):
		if String(line).begins_with("TracerPid:"):
			var tp: String = String(line).substr(10).strip_edges()
			if tp != "" and tp != "0":
				var tc := _proc_text(root.plus_file(tp).plus_file("comm"), 1)
				var tname: String = tc[0].strip_edges() if tc.size() > 0 else "pid " + tp
				libs.append("attached: " + tname)
				if _tool_in(tname) and not out.cheat_tools.has(tname):
					out.cheat_tools.append(tname)
	libs.sort()
	out.dlls = libs.slice(0, 399) if libs.size() > 400 else libs
	for l in libs:
		var low: String = String(l).to_lower()
		for k in CE_DLLS:
			if low.find(k) != -1 and not out.cheat_tools.has("dll:" + l):
				out.cheat_tools.append("dll:" + l)

# macOS: the running programs' names (ps)
func _scan_ps(out: Dictionary):
	var lines := []
	OS.execute("ps", ["-axo", "comm="], true, lines)
	for chunk in lines:
		for line in String(chunk).split("\n"):
			var nm: String = String(line).strip_edges().get_file()
			_note_program(out, nm)
			if nm != "" and _tool_in(nm) and not out.cheat_tools.has(nm):
				out.cheat_tools.append(nm)

static func _csv(line: String) -> Array:
	var out := []
	var cur := ""
	var q := false
	for i in range(line.length()):
		var c := line[i]
		if c == "\"":
			q = not q
		elif c == "," and not q:
			out.append(cur)
			cur = ""
		elif c != "\r":
			cur += c
	if cur != "" or out.size() > 0:
		out.append(cur)
	return out

func _finished(out: Dictionary):
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	result = out
	for t in out.get("cheat_tools", []):
		if not song_tools.has(t):
			song_tools.append(t)
	if not out.get("cheat_tools", []).empty():
		Globals.notify(Globals.NOTIFY_WARN, "Cheat Engine is open. Ranked scores aren't accepted while it runs: close it and restart Chromia.", "Cheat Engine")
	busy = false
	emit_signal("done")

# the latest scan's program names (sent only when the server asks)
func programs() -> Dictionary:
	var p: Array = result.get("programs", []).duplicate()
	p.sort()
	return {"os": OS.get_name(), "programs": p}

# for the score: this song's finds plus the latest DLL list
func env() -> Dictionary:
	return {"os": OS.get_name(), "dlls": result.get("dlls", []), "cheat_tools": song_tools.duplicate()}

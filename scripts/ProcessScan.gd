extends Reference

# Anti-cheat info sent with a ranked pass (Savia.report_map_completion):
#  - dlls: every DLL loaded into Chromia (Windows: tasklist /m on this process),
#    so injected ones show up for admins
#  - cheat_tools: Cheat Engine, if it is running (only the matching process
#    names are sent, never your other programs) or its DLLs are in Chromia
# The server refuses ranked passes while Cheat Engine is found and logs it
# for admins. Scans run on a thread (tasklist takes a moment), when a song
# starts (Game.gd) and when its score is sent, and the two are combined.

signal done

const CE_PROCESSES := ["cheatengine", "cheat engine", "dbk64", "dbk32", "cetrainer"]
# what Cheat Engine puts into a game it attaches to (speedhack, debugger...)
const CE_DLLS := ["speedhack-", "vehdebug-", "allochook-", "luaclient-", "winhook-", "dbk64", "dbk32"]
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
	return OS.get_name() == "Windows" and not OS.has_feature("JavaScript")

# a new song: forget the last one's finds and scan
static func song_started():
	var s = instance()
	s.song_tools = []
	s.start()

func start():
	if busy or not supported():
		return
	busy = true
	_thread = Thread.new()
	if _thread.start(self, "_scan", null, Thread.PRIORITY_LOW) != OK:
		busy = false
		_thread = null

func _scan(_u):
	var out := {"os": OS.get_name(), "dlls": [], "cheat_tools": []}
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
				var low := String(parts[0]).to_lower()
				for k in CE_PROCESSES:
					if low.find(k) != -1 and not out.cheat_tools.has(parts[0]):
						out.cheat_tools.append(parts[0])
	call_deferred("_finished", out)

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

# for the score: this song's finds plus the latest DLL list
func env() -> Dictionary:
	return {"os": OS.get_name(), "dlls": result.get("dlls", []), "cheat_tools": song_tools.duplicate()}

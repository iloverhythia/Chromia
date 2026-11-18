extends Node

# What Windows itself wrote down about the end of the last session, for the
# crash report (Rhythia.how_it_ended). A crash report only says what the game
# was doing last; it can't tell a crash from the game being ended from
# outside (the PC shut down with the game open, Task Manager), and for a real
# crash it can't say where. Windows keeps both in its Application log: a
# crash is an "Application Error" record with the module it happened in (the
# graphics driver, the engine, a library) and the kind of fault; a freeze the
# player closed is an "Application Hang". No record at that time: the game
# didn't crash.
#
# Read once, at the start after a session that didn't close normally, with
# Windows' own wevtutil on a thread. Only the game's own records are looked
# at, and only the module's file name, the fault's code and offset leave
# this file (no paths, no computer name).

signal done

const WINDOW_BEFORE := 20        # s before the game was last seen alive
const WINDOW_AFTER := 3600       # s after (a frozen game is closed later)
const CODES := {
	"c0000005": "access violation",
	"c0000409": "stack buffer overrun",
	"c00000fd": "stack overflow",
	"c000001d": "illegal instruction",
	"c0000094": "division by zero",
	"c0000374": "heap corruption",
	"c0000006": "a file couldn't be read from the disk",
	"c0000017": "out of memory",
	"e06d7363": "C++ exception",
	"40000015": "fatal exit",
}

var _thread: Thread = null
var _alive_unix := 0
var _exe := ""

static func supported() -> bool:
	return OS.get_name() == "Windows"

func look(alive_unix: int):
	_alive_unix = alive_unix
	_exe = OS.get_executable_path().get_file()
	_thread = Thread.new()
	if not OS.can_use_threads() or _thread.start(self, "_work", null, Thread.PRIORITY_LOW) != OK:
		_thread = null
		_finish("")

func _work(_u):
	var out := []
	var code: int = OS.execute("wevtutil", ["qe", "Application", "/c:40", "/rd:true", "/f:xml",
		"/q:*[System[Provider[@Name='Application Error'] or Provider[@Name='Application Hang']]]"], true, out)
	var xml := PoolStringArray(out).join("")
	# (no wevtutil, as under Wine, or the log can't be read: nothing to say)
	var text := "" if code != 0 and xml.find("<Event") == -1 else parse(xml, _exe, _alive_unix, OS.get_unix_time())
	call_deferred("_finish", text)

func _finish(text: String):
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	Rhythia.set_last_session_fault(text)
	emit_signal("done")
	queue_free()

# "2026-11-17T12:06:50.1234567Z" -> unix time (UTC), -1 when it isn't one
static func when(stamp: String) -> int:
	var re := RegEx.new()
	re.compile("^(\\d{4})-(\\d\\d)-(\\d\\d)T(\\d\\d):(\\d\\d):(\\d\\d)")
	var m := re.search(stamp)
	if m == null:
		return -1
	return OS.get_unix_time_from_datetime({year = int(m.get_string(1)), month = int(m.get_string(2)), day = int(m.get_string(3)),
		hour = int(m.get_string(4)), minute = int(m.get_string(5)), second = int(m.get_string(6))})

# xml: wevtutil's records, newest first. -> one line for the report
static func parse(xml: String, exe: String, alive_unix: int, now_unix: int) -> String:
	var name_re := RegEx.new()
	name_re.compile("<Provider\\s+Name=['\"]([^'\"]+)['\"]")
	var time_re := RegEx.new()
	time_re.compile("<TimeCreated\\s+SystemTime=['\"]([^'\"]+)['\"]")
	var data_re := RegEx.new()
	data_re.compile("<Data(?:\\s[^>]*)?(?:/>|>([^<]*)</Data>)")
	var best := {}
	for ev in xml.split("<Event ", false):
		var pm := name_re.search(ev)
		var tm := time_re.search(ev)
		if pm == null or tm == null:
			continue
		if not (pm.get_string(1) in ["Application Error", "Application Hang"]):
			continue
		var at: int = when(tm.get_string(1))
		if at < alive_unix - WINDOW_BEFORE or at > min(now_unix, alive_unix + WINDOW_AFTER):
			continue
		var data := []
		for d in data_re.search_all(ev):
			data.append(d.get_string(1).strip_edges())
		if data.empty() or data[0].to_lower() != exe.to_lower():
			continue # (another program's)
		# (the first one after the game was last seen: records come newest first)
		if best.empty() or at < int(best.at):
			best = {"at": at, "hang": pm.get_string(1) == "Application Hang", "data": data}
	if best.empty():
		return "Windows has no record of the game crashing or freezing then: most likely it was ended from outside (the PC shut down, restarted or signed out with the game open, Task Manager, power lost)."
	var after: int = max(0, int(best.at) - alive_unix)
	if best.hang:
		return "Windows recorded that the game had stopped responding (frozen, then closed), %d s after it was last seen running." % after
	var data: Array = best.data
	var module: String = String(data[3]).get_file() if data.size() > 3 and String(data[3]) != "" else "?"
	var code: String = String(data[6]).to_lower().trim_prefix("0x") if data.size() > 6 else ""
	var offset: String = String(data[7]) if data.size() > 7 else ""
	return "Windows recorded a crash of the game %d s after it was last seen running: in %s%s%s." % [after, module,
		(", %s (0x%s)" % [CODES[code], code]) if CODES.has(code) else ((", fault 0x%s" % code) if code != "" else ""),
		(", offset %s" % offset) if offset != "" else ""]

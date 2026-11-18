extends Node

# "Send this session's log" (Settings > Crash Reports): what the game did this
# session (Rhythia.session_report: the trail and the engine log's last lines)
# goes to the developers the way a crash report does (scripts/CrashSend.gd,
# same address, marked as a session log; the server's bot posts it in the
# crash log channel). For problems that aren't crashes, and for headsets and
# phones, where copying a log and pasting it somewhere is awkward.
# The account id and the computer's user name are cut out first.

const LINES := 400

static func send(tree: SceneTree):
	if tree.root.has_node("SessionSend"):
		return
	var n: Node = load("res://scripts/SessionSend.gd").new()
	n.name = "SessionSend"
	tree.root.add_child(n)

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	var CS = load("res://scripts/CrashSend.gd")
	var http := HTTPRequest.new()
	http.timeout = 25
	add_child(http)
	http.connect("request_completed", self, "_on_done")
	var body := JSON.print({
		client_id = Rhythia.cid,
		version = String(ProjectSettings.get_setting("application/config/version")),
		platform = OS.get_name(),
		model = OS.get_model_name(),
		kind = "session",
		report = CS.scrub(Rhythia.session_report(LINES)),
	})
	var url: String = CS.URL
	if OS.is_debug_build() and OS.get_environment("CHROMIA_CRASH_URL") != "":
		url = OS.get_environment("CHROMIA_CRASH_URL") # (tests: a server on this computer)
	if Rhythia.cid == "" or http.request(url, ["Content-Type: application/json"], true, HTTPClient.METHOD_POST, body) != OK:
		_end(false, "It couldn't be sent: no connection.")

func _on_done(result: int, code: int, _headers, body: PoolByteArray):
	if result != HTTPRequest.RESULT_SUCCESS:
		_end(false, "It couldn't be sent: no connection to the server.")
	elif code == 429:
		_end(false, "It wasn't sent: one was sent a moment ago (wait a minute), or too many today.")
	elif code != 200:
		_end(false, "It couldn't be sent (the server answered %d)." % code)
	else:
		var p = JSON.parse(body.get_string_from_utf8())
		var posted: bool = p.error == OK and p.result is Dictionary and bool(p.result.get("sent", false))
		_end(posted, "This session's log was sent to the developers." if posted else "The server took it but isn't posting logs anywhere right now.")

func _end(ok: bool, what: String):
	Rhythia.trail("session log: " + what)
	Globals.notify(Globals.NOTIFY_SUCCEED if ok else Globals.NOTIFY_WARN, what, "Session log", 6)
	queue_free()

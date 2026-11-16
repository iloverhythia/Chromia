extends Node

# A crash report sent by itself. When the last session didn't close normally
# (Rhythia.last_session_crashed), its report (Rhythia.crash_report: the last
# lines of the trail and of the engine's log) goes to the server once, at this
# start; the server's Discord bot posts it in the channel the owner picked in
# the admin panel (savia_web: src/crashlogs.js). With no channel picked the
# server drops it. Settings > Crash Reports has the switch (on by default).
#
# Not from the browser version: closing its tab looks like a crash there.
# Your account id and your computer's user name are cut out of the text
# before it leaves (the server cuts the id out again).

const URL := "https://chromia.lol/savia-crash-log"
const LINES := 300
const WAIT_S := 90.0

var _t := 0.0
var _http: HTTPRequest = null

static func wanted() -> bool:
	return Rhythia.last_session_crashed and not OS.has_feature("JavaScript") and Rhythia.crash_log_state == 0

func _ready():
	pause_mode = PAUSE_MODE_PROCESS

# what leaves the device: no account id, no user name in file paths
static func scrub(text: String) -> String:
	var out := text
	if Rhythia.cid != "":
		out = out.replace(Rhythia.cid, "[account id]")
	for key in ["USERNAME", "USER", "LOGNAME"]:
		var name := OS.get_environment(key)
		if name.length() >= 3:
			for sep in ["/", "\\"]:
				out = out.replace(sep + name + sep, sep + "[user]" + sep)
	return out

func _process(delta: float):
	_t += delta
	if _t > WAIT_S:
		_end(3, "not sent: the game wasn't ready in time")
		return
	# (the settings say whether to send; the account id says whose it is)
	if not Rhythia._settings_read or Rhythia.cid == "" or _t < 3.0:
		return
	set_process(false)
	if not Rhythia.send_crash_logs:
		_end(2, "not sent: turned off in Settings")
		return
	_http = HTTPRequest.new()
	_http.timeout = 25
	add_child(_http)
	_http.connect("request_completed", self, "_on_done")
	var body := JSON.print({
		client_id = Rhythia.cid,
		version = String(ProjectSettings.get_setting("application/config/version")),
		platform = OS.get_name(),
		model = OS.get_model_name(),
		report = scrub(Rhythia.crash_report(LINES)),
	})
	var url := URL
	if OS.is_debug_build() and OS.get_environment("CHROMIA_CRASH_URL") != "":
		url = OS.get_environment("CHROMIA_CRASH_URL") # (tests: a server on this computer)
	if _http.request(url, ["Content-Type: application/json"], true, HTTPClient.METHOD_POST, body) != OK:
		_end(3, "not sent: no connection")

func _on_done(result: int, code: int, _headers, body: PoolByteArray):
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_end(3, "not sent (%d / %d)" % [result, code])
		return
	var p = JSON.parse(body.get_string_from_utf8())
	var posted: bool = p.error == OK and p.result is Dictionary and bool(p.result.get("sent", false))
	_end(1 if posted else 2, "sent to the developers" if posted else "taken by the server, which isn't posting crash logs anywhere")

# state: 1 sent and posted, 2 not sent on purpose, 3 couldn't be sent
func _end(state: int, what: String):
	Rhythia.crash_log_state = state
	Rhythia.trail("last session's crash report: " + what)
	set_process(false)
	queue_free()

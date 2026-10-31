extends Node

# Slow frames while playing a map go to the trail (logs/trail.txt), with what
# was going on, so a stutter can be traced: how long the frame took, the
# scripts' share of it, draw calls, objects, and the web requests running.
# At most MAX_LOGGED a song (a slow PC isn't flooded).

const SLOW_SEC := 0.05
const MAX_LOGGED := 40

var _logged := 0
var _skip := 30 # (the first frames of a song are slow anyway)

func _ready():
	pause_mode = PAUSE_MODE_PROCESS

func _process(delta):
	if _skip > 0:
		_skip -= 1
		return
	if delta < SLOW_SEC or _logged >= MAX_LOGGED or get_tree().paused:
		return
	_logged += 1
	var http := 0
	for n in [get_node_or_null("/root/LobbyManager"), get_node_or_null("/root/Rhythia"), get_node_or_null("/root/Online")]:
		if n != null:
			for c in n.get_children():
				if c is HTTPRequest and c.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
					http += 1
	Rhythia.trail("hitch %d ms (scripts %.1f ms, physics %.1f ms, draw calls %d, objects %d, web requests %d, fps %d)" % [
		int(delta * 1000.0),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		int(Performance.get_monitor(Performance.RENDER_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		http,
		int(Performance.get_monitor(Performance.TIME_FPS)),
	])

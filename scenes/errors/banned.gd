extends Node

const RECHECK_INTERVAL_SEC = 10.0
var _recheck_timer: Timer

func _ready():
	_recheck_timer = Timer.new()
	_recheck_timer.wait_time = RECHECK_INTERVAL_SEC
	_recheck_timer.autostart = true
	_recheck_timer.connect("timeout", self, "_recheck_live_ban")
	add_child(_recheck_timer)

func _recheck_live_ban():
	if Rhythia.cid == "":
		return
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_recheck_completed", [http_request])
	var error = http_request.request(Rhythia.LIVE_BAN_STATUS_URL + "?client_id=" + Rhythia.cid.http_escape())
	if error != OK:
		http_request.queue_free()

func _on_recheck_completed(result, response_code, headers, body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		return
	var json_result = JSON.parse(body.get_string_from_utf8())
	if json_result.error != OK or typeof(json_result.result) != TYPE_DICTIONARY:
		return
	if not bool(json_result.result.get("banned", false)):
		get_tree().change_scene("res://scenes/init.tscn")

func _process(delta):
	var viewport_size = get_viewport().size
	$TextureRect.rect_min_size = Vector2(viewport_size.x, viewport_size.y)

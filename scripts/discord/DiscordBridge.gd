extends Node

# Rich Presence without the native Discord Game SDK (loading the SDK crashed
# the game on startup). Offers the small part of the SDK API the game uses and
# sends the activity to the Discord app over its local IPC pipe
# (scripts/discord/DiscordIPC.gd). If Discord isn't running nothing happens.

const DiscordIPC = preload("res://scripts/discord/DiscordIPC.gd")

enum ActivityType { Playing = 0, Streaming = 1, Listening = 2, Watching = 3 }
enum Result { Ok = 0, InternalError = 4 }

class ActivityAssets:
	var large_image := ""
	var large_text := ""
	var small_image := ""
	var small_text := ""
	func set_large_image(v: String) -> void: large_image = v
	func set_large_text(v: String) -> void: large_text = v
	func set_small_image(v: String) -> void: small_image = v
	func set_small_text(v: String) -> void: small_text = v

class Activity:
	var type := 0
	var details := ""
	var state := ""
	var name := ""
	var assets := ActivityAssets.new()
	func set_type(v) -> void: type = int(v)
	func set_details(v: String) -> void: details = v
	func set_state(v: String) -> void: state = v
	func set_name(v: String) -> void: name = v
	func get_assets() -> ActivityAssets: return assets

# What update_activity returns: callers may `yield(..., "result")` and read `.result`.
class Request:
	signal result(res)

class ActivityManager:
	var bridge
	func update_activity(activity) -> Request:
		return bridge._update_activity(activity)

var activity_manager := ActivityManager.new()
var _ipc = DiscordIPC.new()
var _pending: Array = []

func _ready():
	activity_manager.bridge = self
	pause_mode = PAUSE_MODE_PROCESS

func _enabled() -> bool:
	return ProjectSettings.get_setting("application/config/discord_rpc") and OS.has_feature("Windows")

func _update_activity(activity) -> Request:
	var req := Request.new()
	if _enabled():
		var assets: Dictionary = {}
		if activity.assets.large_image != "": assets["large_image"] = activity.assets.large_image
		if activity.assets.large_text != "": assets["large_text"] = activity.assets.large_text
		if activity.assets.small_image != "": assets["small_image"] = activity.assets.small_image
		if activity.assets.small_text != "": assets["small_text"] = activity.assets.small_text
		_ipc.request_activity(activity.details, activity.state, assets, [])
	# Emit next frame so `yield(update_activity(...), "result")` works.
	_pending.append(req)
	return req

func _process(_delta):
	if _pending.empty():
		return
	var done := _pending
	_pending = []
	for req in done:
		req.emit_signal("result", {"result": Result.Ok})

func _exit_tree():
	_ipc.shutdown()

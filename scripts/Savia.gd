extends Node

onready var rootg = get_tree().root

const GA4_ID = "G-H6RLXT8E8D"
const GA4_SECRET = "fxYeJ1F0SICwsncb0TBh1w"

const BANNED_LIST_URL = "https://raw.githubusercontent.com/SavvyScripter-GH/SavvyAssets/main/banned_players.json"
var banned_clients: Array = []

var heartbeat_timer: Timer
var cid: String = ""
var dev = "pc"

const CLIENT_DB_DIR := "user://savia"
const CLIENT_DB_PATH := "user://savia/.db"

func _read_client_db() -> Dictionary:
	var file := File.new()
	if file.open(Globals.p(CLIENT_DB_PATH), File.READ) != OK:
		return {}
	var raw := file.get_as_text()
	file.close()
	var decoded := Marshalls.base64_to_utf8(raw)
	if decoded == "":
		return {}
	var parsed = JSON.parse(decoded)
	if parsed.error != OK or typeof(parsed.result) != TYPE_DICTIONARY:
		return {}
	return parsed.result

func _write_client_db(data: Dictionary):
	var dir := Directory.new()
	dir.make_dir_recursive(Globals.p(CLIENT_DB_DIR))
	var file := File.new()
	if file.open(Globals.p(CLIENT_DB_PATH), File.WRITE) == OK:
		file.store_string(Marshalls.utf8_to_base64(JSON.print(data)))
		file.close()

func _ensure_client_id() -> String:
	var db := _read_client_db()
	if db.has("client_id") and String(db.client_id) != "":
		return String(db.client_id)

	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	var legacy_id := String(config.get_value("internal", "client_id", ""))
	var new_id := legacy_id if legacy_id != "" else _generate_simple_id()

	db["client_id"] = new_id
	_write_client_db(db)
	return new_id

func set_client_id():

	var client_id = _ensure_client_id()
	Rhythia.cid = client_id
	cid = client_id

	if OS.has_feature("HTML5"):
		if OS.has_touchscreen_ui_hint():
			dev = "mobile"
		else:
			dev = "web"
	elif OS.has_feature("Android"):
		dev = "android"
	else:
		dev = "pc"

	Rhythia.dev = dev

func device(input):
	if input == "web" and Rhythia.dev == "mobile": return true
	return Rhythia.dev == input

func apply_rotated_client_id(new_id: String):
	if new_id == "" or new_id == cid:
		return
	var db = _read_client_db()
	db["client_id"] = new_id
	_write_client_db(db)
	cid = new_id
	Globals.notify(Globals.NOTIFY_WARN, "Your account ID was rotated by an admin. Please restart Savia.", "Account Updated")

func load_keybinds():
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") != OK or not config.has_section("keybinds"):
		return
	for action in config.get_section_keys("keybinds"):
		if not InputMap.has_action(action):
			continue
		var scancode = int(config.get_value("keybinds", action))
		InputMap.action_erase_events(action)
		var event = InputEventKey.new()
		event.scancode = scancode
		InputMap.action_add_event(action, event)

var jp: int = 0
var sp: int = 0
var in_map: bool = false
var discord_user: Dictionary = {}
var discord_login_error: String = ""
signal discord_login_changed()
signal jp_changed(awarded)
signal sp_changed(awarded)
signal leaderboard_received(entries)
signal leaderboard_sp_received(entries)

func load_profile():
	var config = ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return
	jp = int(config.get_value("profile", "jp", 0))
	sp = int(config.get_value("profile", "sp", 0))
	var discord_id = String(config.get_value("profile", "discord_id", ""))
	if discord_id != "":
		discord_user = {
			"id": discord_id,
			"username": String(config.get_value("profile", "discord_username", "")),
			"display_name": String(config.get_value("profile", "discord_display_name", "")),
			"avatar_url": String(config.get_value("profile", "discord_avatar_url", "")),
		}

func save_jp():
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("profile", "jp", jp)
	config.set_value("profile", "sp", sp)
	config.save("user://settings.cfg")

const REPORT_COMPLETION_URL = "https://savia.nysr.host/savia-report-completion"
const PLAYER_XP_URL = "https://savia.nysr.host/savia-player-xp"
const LEADERBOARD_URL = "https://savia.nysr.host/savia-leaderboard"
const LEADERBOARD_SP_URL = "https://savia.nysr.host/savia-leaderboard-sp"
const UPLOAD_REPLAY_URL = "https://savia.nysr.host/savia-upload-replay"

func upload_replay_for_pass(song_id: String, replay_id: String):
	if cid == "" or song_id == "" or replay_id == "":
		return
	var replay_path = Globals.p("user://replays/%s.sspre" % replay_id)
	var file = File.new()
	if file.open(replay_path, File.READ) != OK:
		return
	var bytes = file.get_buffer(file.get_len())
	file.close()
	var b64 = Marshalls.raw_to_base64(bytes)

	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_replay_upload_completed", [http_request])
	var url = "%s?client_id=%s&song_id=%s" % [UPLOAD_REPLAY_URL, cid.http_escape(), song_id.http_escape()]
	var error = http_request.request(url, ["Content-Type: text/plain"], true, HTTPClient.METHOD_POST, b64)
	if error != OK:
		http_request.queue_free()

func _on_replay_upload_completed(_result, _response_code, _headers, _body, http_request: HTTPRequest):
	http_request.queue_free()

func fetch_leaderboard():
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_leaderboard_received", [http_request])
	var error = http_request.request(LEADERBOARD_URL)
	if error != OK:
		http_request.queue_free()

func _on_leaderboard_received(result, response_code, headers, body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		emit_signal("leaderboard_received", [])
		return
	var json_result = JSON.parse(body.get_string_from_utf8())
	if json_result.error != OK or typeof(json_result.result) != TYPE_DICTIONARY:
		emit_signal("leaderboard_received", [])
		return
	emit_signal("leaderboard_received", json_result.result.get("entries", []))

func fetch_leaderboard_sp():
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_leaderboard_sp_received", [http_request])
	var error = http_request.request(LEADERBOARD_SP_URL)
	if error != OK:
		http_request.queue_free()

func _on_leaderboard_sp_received(result, response_code, headers, body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		emit_signal("leaderboard_sp_received", [])
		return
	var json_result = JSON.parse(body.get_string_from_utf8())
	if json_result.error != OK or typeof(json_result.result) != TYPE_DICTIONARY:
		emit_signal("leaderboard_sp_received", [])
		return
	emit_signal("leaderboard_sp_received", json_result.result.get("entries", []))

func check_player_xp():
	if cid == "":
		return
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_player_xp_received", [http_request])
	var error = http_request.request(PLAYER_XP_URL + "?client_id=" + cid.http_escape())
	if error != OK:
		http_request.queue_free()

func _on_player_xp_received(result, response_code, headers, body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		return
	var json_result = JSON.parse(body.get_string_from_utf8())
	if json_result.error != OK or typeof(json_result.result) != TYPE_DICTIONARY:
		return
	jp = int(json_result.result.get("xp", jp))
	sp = int(json_result.result.get("sp", sp))
	save_jp()

func current_speed_multiplier() -> float:
	if mod_speed_level >= 0 and mod_speed_level < Globals.speed_multi.size():
		return Globals.speed_multi[mod_speed_level]
	return 1.0

func current_xp_speed_multiplier() -> float:
	return pow(current_speed_multiplier(), 2)

func _get_active_mods_dict() -> Dictionary:
	return {
		"nofail": mod_nofail,
		"extra_energy": mod_extra_energy,
		"no_regen": mod_no_regen,
		"speed_level": mod_speed_level,
		"mirror_x": mod_mirror_x,
		"mirror_y": mod_mirror_y,
		"nearsighted": mod_nearsighted,
		"ghost": mod_ghost,
		"half_ghost": half_ghost,
		"sudden_death": mod_sudden_death,
		"chaos": mod_chaos,
		"earthquake": mod_earthquake,
		"360": mod_360,
		"360_speed": mod_360_speed,
		"strobe": mod_strobe,
		"hardrock": mod_hardrock,
		"spin": cam_unlock,
		"note_pushback": do_note_pushback,
		"retain_pitch": retain_song_pitch,
		"speed_hitwindow": speed_hitwindow,
		"autoplay": (replay != null and replay.autoplayer),
		"paused": song_end_pause_count > 0,
		"start_offset": start_offset,
		"hitbox_size": note_hitbox_size,
		"health_model": health_model,
	}

var _xp_eligibility_song_id: String = ""

func check_xp_eligibility_notice(song_id: String):
	if replaying or song_id == "":
		return
	var lobby_manager = get_node_or_null("/root/LobbyManager")
	if lobby_manager == null:
		return
	_xp_eligibility_song_id = song_id
	if not lobby_manager.is_connected("map_rank_info_received", self, "_on_xp_eligibility_rank_info"):
		lobby_manager.connect("map_rank_info_received", self, "_on_xp_eligibility_rank_info")
	lobby_manager.get_map_rank(song_id)

func _on_xp_eligibility_rank_info(song_id: String, ranked: bool, xp: int, content_hash: String):
	if song_id != _xp_eligibility_song_id or selected_song == null or String(selected_song.id) != song_id:
		return
	_xp_eligibility_song_id = ""
	if not ranked:
		return
	var reasons := PoolStringArray()
	if content_hash != "" and content_hash != selected_song.compute_chart_hash():
		reasons.append("map doesn't match the ranked version")
	if not (is_equal_approx(hitwindow_ms, 55.0) or is_equal_approx(hitwindow_ms, 58.0)):
		reasons.append("hitwindow isn't a ranked value (55ms/58ms)")
	if not is_equal_approx(note_hitbox_size, 1.14):
		reasons.append("hitbox size isn't the default (1.14)")
	if health_model != Globals.HP_SOUNDSPACE:
		reasons.append("health model isn't Default (Sound Space)")
	if mod_nofail:
		reasons.append("NoFail is on")
	if mod_extra_energy:
		reasons.append("Extra Energy is on")
	if replay != null and replay.autoplayer:
		reasons.append("Autoplay is on")
	if start_offset != 0:
		reasons.append("not starting from 0:00")
	if reasons.size() > 0:
		Globals.notify(Globals.NOTIFY_WARN, "Won't count for XP — %s" % reasons.join(", "), "XP Not Valid")
	else:
		var scaled_xp = int(round(xp * current_xp_speed_multiplier()))
		Globals.notify(Globals.NOTIFY_INFO, "This map is ranked for %d XP." % scaled_xp, "XP Valid")

var _hwid_computed: bool = false
var _cached_hwid: String = ""
func get_hardware_id() -> String:
	if _hwid_computed:
		return _cached_hwid
	_hwid_computed = true
	var raw := ""
	if OS.has_feature("Windows"):
		var output = []
		var exit_code = OS.execute("reg", ["query", "HKLM\\SOFTWARE\\Microsoft\\Cryptography", "/v", "MachineGuid"], true, output)
		if exit_code == 0 and output.size() > 0:
			var regex = RegEx.new()
			regex.compile("[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
			var m = regex.search(str(output[0]))
			if m:
				raw = m.get_string()
	if raw == "":
		raw = OS.get_unique_id()
	_cached_hwid = raw.sha256_text() if raw != "" else ""
	return _cached_hwid

func report_map_completion(song_id: String):
	if cid == "" or song_id == "":
		return
	var content_hash = selected_song.compute_chart_hash() if selected_song != null else ""
	var replay_id_snapshot = replay.id if replay != null else ""
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_report_completion_received", [http_request, song_id, replay_id_snapshot])
	var mods_json = JSON.print(_get_active_mods_dict())
	var url = "%s?client_id=%s&song_id=%s&speed=%s&content_hash=%s&misses=%s&note_count=%s&hitwindow=%s&mods=%s&hwid=%s" % [
		REPORT_COMPLETION_URL, cid.http_escape(), song_id.http_escape(), str(current_speed_multiplier()), content_hash.http_escape(),
		str(song_end_misses), str(song_end_total_notes), str(hitwindow_ms), mods_json.http_escape(), get_hardware_id().http_escape()
	]
	var error = http_request.request(url)
	if error != OK:
		http_request.queue_free()

const XP_REJECT_REASONS := {
	"hash_mismatch": "your copy of the map doesn't match the ranked version",
	"invalid_hitwindow": "hitwindow isn't a ranked value (55ms/58ms)",
	"invalid_hitbox_size": "hitbox size isn't the default (1.14)",
	"invalid_health_model": "health model isn't Default (Sound Space)",
	"nofail_or_autoplay": "NoFail/Autoplay disqualifies a pass",
	"extra_energy": "Extra Energy disqualifies a pass",
	"paused": "pausing disqualifies a pass",
	"nonzero_start_offset": "you didn't start from the beginning",
	"debounced": "you already scored this map recently",
}

func _on_report_completion_received(result, response_code, headers, body, http_request: HTTPRequest, song_id: String, replay_id_snapshot: String):
	http_request.queue_free()
	if response_code != 200:
		Globals.notify(Globals.NOTIFY_ERROR, "Couldn't reach the server to submit your score.", "Score Not Submitted")
		return
	var json_result = JSON.parse(body.get_string_from_utf8())
	if json_result.error != OK or typeof(json_result.result) != TYPE_DICTIONARY:
		Globals.notify(Globals.NOTIFY_ERROR, "Couldn't reach the server to submit your score.", "Score Not Submitted")
		return
	var data = json_result.result
	var before = jp
	var before_sp = sp
	var awarded = int(data.get("awarded", 0))
	var sp_awarded = int(data.get("sp_awarded", 0))
	jp = int(data.get("total_xp", jp))
	sp = int(data.get("total_sp", sp))
	save_jp()
	if awarded > 0:
		emit_signal("jp_changed", awarded)
		var msg = "+%d XP (%d → %d)" % [awarded, before, jp]
		if sp_awarded > 0:
			emit_signal("sp_changed", sp_awarded)
			msg += "\n+%d SP (%d → %d)" % [sp_awarded, before_sp, sp]
		else:
			msg += "\nSP unchanged (%d) — not a new best on this map" % sp
		Globals.notify(Globals.NOTIFY_SUCCEED, msg, "Score Submitted")
		if record_replays:
			upload_replay_for_pass(song_id, replay_id_snapshot)
	elif data.has("reason"):
		var reason_text = XP_REJECT_REASONS.get(String(data.reason), String(data.reason))
		Globals.notify(Globals.NOTIFY_WARN, "No XP awarded — %s" % reason_text, "Score Not Submitted")

func _save_discord_profile():
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("profile", "discord_id", discord_user.get("id", ""))
	config.set_value("profile", "discord_username", discord_user.get("username", ""))
	config.set_value("profile", "discord_display_name", discord_user.get("display_name", ""))
	config.set_value("profile", "discord_avatar_url", discord_user.get("avatar_url", ""))
	config.save("user://settings.cfg")

const DISCORD_LOGIN_START_URL = "https://savia.nysr.host/savia-discord-login-start"
const DISCORD_LOGIN_POLL_URL = "https://savia.nysr.host/savia-discord-login-poll"
const DISCORD_LINK_URL = "https://savia.nysr.host/savia-discord-link"
const DISCORD_UNLINK_URL = "https://savia.nysr.host/savia-discord-unlink"
const DISCORD_LOGIN_POLL_INTERVAL_SEC = 2.0
const DISCORD_LOGIN_TIMEOUT_SEC = 180.0
var _discord_login_timer: Timer = null
var _discord_login_elapsed: float = 0.0

func check_discord_link():
	if cid == "" or discord_user.has("id"):
		return
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_discord_link_checked", [http_request])
	var error = http_request.request(DISCORD_LINK_URL + "?client_id=" + cid.http_escape())
	if error != OK:
		http_request.queue_free()

func _on_discord_link_checked(result, response_code, headers, body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		return
	var json_result = JSON.parse(body.get_string_from_utf8())
	if json_result.error != OK or typeof(json_result.result) != TYPE_DICTIONARY:
		return
	var data = json_result.result
	if bool(data.get("linked", false)) and typeof(data.get("discord_user")) == TYPE_DICTIONARY:
		_apply_discord_user(data.discord_user)

func _apply_discord_user(du: Dictionary):
	discord_user = {
		"id": String(du.get("id", "")),
		"username": String(du.get("username", "")),
		"display_name": String(du.get("global_name", du.get("display_name", ""))),
		"avatar_url": String(du.get("avatar_url", "")),
	}
	_save_discord_profile()
	emit_signal("discord_login_changed")

func unlink_discord():
	if cid == "" or not discord_user.has("id"):
		return
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_discord_unlink_received", [http_request])
	var error = http_request.request(DISCORD_UNLINK_URL + "?client_id=" + cid.http_escape())
	if error != OK:
		http_request.queue_free()

func _on_discord_unlink_received(_result, response_code, _headers, _body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		Globals.notify(Globals.NOTIFY_ERROR, "Couldn't reach the server to unlink your Discord account.", "Unlink Failed")
		return
	discord_user = {}
	var config = ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("profile", "discord_id", "")
	config.set_value("profile", "discord_username", "")
	config.set_value("profile", "discord_display_name", "")
	config.set_value("profile", "discord_avatar_url", "")
	config.save("user://settings.cfg")
	emit_signal("discord_login_changed")

func start_discord_login():
	if cid == "":
		return
	discord_login_error = ""
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_discord_login_start_received", [http_request])
	var error = http_request.request(DISCORD_LOGIN_START_URL + "?client_id=" + cid.http_escape())
	if error != OK:
		discord_login_error = "Couldn't reach the server."
		emit_signal("discord_login_changed")
		http_request.queue_free()

func _on_discord_login_start_received(result, response_code, headers, body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		discord_login_error = "Couldn't reach the server."
		emit_signal("discord_login_changed")
		return
	var json_result = JSON.parse(body.get_string_from_utf8())
	if json_result.error != OK or typeof(json_result.result) != TYPE_DICTIONARY or json_result.result.has("error"):
		discord_login_error = "Discord login isn't set up on the server yet."
		emit_signal("discord_login_changed")
		return
	OS.shell_open(String(json_result.result.get("url", "")))
	_discord_login_elapsed = 0.0
	if _discord_login_timer == null:
		_discord_login_timer = Timer.new()
		_discord_login_timer.wait_time = DISCORD_LOGIN_POLL_INTERVAL_SEC
		_discord_login_timer.connect("timeout", self, "_poll_discord_login")
		add_child(_discord_login_timer)
	_discord_login_timer.start()
	emit_signal("discord_login_changed")

func _poll_discord_login():
	_discord_login_elapsed += DISCORD_LOGIN_POLL_INTERVAL_SEC
	if _discord_login_elapsed > DISCORD_LOGIN_TIMEOUT_SEC:
		_discord_login_timer.stop()
		discord_login_error = "Login timed out — try again."
		emit_signal("discord_login_changed")
		return
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_discord_login_poll_received", [http_request])
	var error = http_request.request(DISCORD_LOGIN_POLL_URL + "?client_id=" + cid.http_escape())
	if error != OK:
		http_request.queue_free()

func _on_discord_login_poll_received(result, response_code, headers, body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		return
	var json_result = JSON.parse(body.get_string_from_utf8())
	if json_result.error != OK or typeof(json_result.result) != TYPE_DICTIONARY:
		return
	var data = json_result.result
	var status = String(data.get("status", "pending"))
	if status == "complete" and typeof(data.get("discord_user")) == TYPE_DICTIONARY:
		if _discord_login_timer != null:
			_discord_login_timer.stop()
		_apply_discord_user(data.discord_user)
	elif status == "error":
		if _discord_login_timer != null:
			_discord_login_timer.stop()
		discord_login_error = String(data.get("error", "Discord login failed."))
		emit_signal("discord_login_changed")

func _on_heartbeat_timeout(cid: String):
	send_analytics_event("session_heartbeat", {}, cid)

func fetch_banned_list():
	var http_request = HTTPRequest.new()
	add_child(http_request)

	http_request.connect("request_completed", self, "_on_request_completed")

	var error = http_request.request(BANNED_LIST_URL)
	if error != OK:
		print("An error occurred while initiating the HTTP request.")

func _on_request_completed(result, response_code, headers, body):
	get_child(get_child_count() - 1).queue_free()

	if response_code == 200:
		var raw_text = body.get_string_from_utf8()

		var json_result = JSON.parse(raw_text)

		if json_result.error == OK:
			if typeof(json_result.result) == TYPE_ARRAY:
				banned_clients = json_result.result

			else:
				print("Error: Fetched data is not an array format.")
		else:
			print("JSON Parsing failed: ", json_result.error_string)
	else:
		print("Failed to reach GitHub server. HTTP Status Code: ", response_code)

func is_client_banned(client_id: String) -> bool:

	return banned_clients.has(client_id)

const LIVE_BAN_STATUS_URL = "https://savia.nysr.host/savia-live-ban-status"
const LIVE_BAN_POLL_INTERVAL_SEC = 30.0
var _live_ban_timer: Timer

func check_live_ban():
	if cid == "":
		return
	var http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.connect("request_completed", self, "_on_live_ban_status_received", [http_request])
	var error = http_request.request(LIVE_BAN_STATUS_URL + "?client_id=" + cid.http_escape())
	if error != OK:
		print("[live_ban] request failed to start, error ", error)
		http_request.queue_free()

func _on_live_ban_status_received(result, response_code, headers, body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		print("[live_ban] status check failed, HTTP ", response_code)
		return
	var json_result = JSON.parse(body.get_string_from_utf8())
	if json_result.error != OK or typeof(json_result.result) != TYPE_DICTIONARY:
		print("[live_ban] status response wasn't valid JSON: ", json_result.error_string)
		return
	print("[live_ban] status check OK, banned=", json_result.result.get("banned", false))
	if bool(json_result.result.get("banned", false)):
		get_tree().change_scene("res://scenes/errors/banned.tscn")

func start_live_ban_poll():
	if _live_ban_timer != null:
		return
	_live_ban_timer = Timer.new()
	_live_ban_timer.wait_time = LIVE_BAN_POLL_INTERVAL_SEC
	_live_ban_timer.autostart = true
	_live_ban_timer.connect("timeout", self, "check_live_ban")
	add_child(_live_ban_timer)

func check_for_update_log():
	var config = ConfigFile.new()
	config.load("user://settings.cfg")

	var client_id = _ensure_client_id()
	Rhythia.cid = client_id

	send_analytics_event("app_launch", {
		"client_id": Rhythia.cid,
		"version": ProjectSettings.get_setting("application/config/version"),
		"platform": OS.get_name()
		},
		client_id
	)
	start_heartbeat(client_id)

	var current_version = ProjectSettings.get_setting("application/config/version")
	var last_seen_version = config.get_value("internal", "last_version", "0.0.0")

	if _is_testing_version(current_version):
		return

	if current_version != last_seen_version:
		send_analytics_event("app_update", {}, client_id)
		_notify_latest_update(current_version)
		config.set_value("internal", "last_version", current_version)
		config.save("user://settings.cfg")

func _is_testing_version(v: String) -> bool:
	return v.findn("-testin") != -1

func send_analytics_event(event_name: String, other_payload: Dictionary, cid: String):
	var url = "https://savia.nysr.host/ga-collect"

	var payload = {
		"client_id": cid,
		"events": [{
			"name": event_name,
			"params": other_payload
		}]
	}

	var http = HTTPRequest.new()
	add_child(http)
	http.request(url, ["Content-Type: application/json"], false, HTTPClient.METHOD_POST, JSON.print(payload))
	yield(http, "request_completed")
	http.queue_free()

func start_heartbeat(cid: String):
	if heartbeat_timer: return
	heartbeat_timer = Timer.new()
	heartbeat_timer.wait_time = 60
	heartbeat_timer.autostart = true
	heartbeat_timer.connect(
	"timeout",
	self,
	"send_analytics_event",
	[
		"session_heartbeat",
		{
			"client_id": Rhythia.cid,
			"version": ProjectSettings.get_setting("application/config/version"),
			"platform": OS.get_name()
		},
		cid
	]
)
	add_child(heartbeat_timer)

func _generate_simple_id() -> String:
	randomize()
	var chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	var id = ""
	for i in range(16): id += chars[randi() % chars.length()]
	return id

const VERSION_SEQUENCE = [
	"may23-2026-e", "may23-2026-f", "may23-2026-g", "may23-2026-h",
	"may24-2026-a", "may24-2026-b", "may24-2026-c", "may24-2026-d",
	"may24-2026-e", "may29-2026-a", "may29-2026-b", "may31-2026-a",
	"june2-2026-a", "june2-2026-b", "june2-2026-c", "june3-2026-a",
	"july6-2026-a", "july13-2026-online-testing", "july14-2026-online-testing-2",
	"july14-2026-online-testing-3", "july15-2026-a", "july18-2026-a",
	"july18-2026-b", "july19-2026-a", "july23-2026-a", "july23-2026-b",
	"july24-2026-a", "july24-2026-b", "july25-2026-a", "july25-2026-b",
	"july25-2026-c", "july26-2026-a", "july27-2026-a", "sep27-2026-web-a",
	"sep27-2026-web-b"
]


const VERSION_NOTES = {
	"LEGACY": "- Added Update Notifications\n- Added 360 mod (duuhh)\n- Added arcw\n- Added Strobe mod!\n- Added Nyo to testers\n- Added Vanfi to testers\n- Added Dylan Jarvis to patreon (joke)\n- Fixed Online maps (partially)\n- Brrecken's gay!",
	"may24-2026-d": "- Fixed Online maps",
	"may24-2026-e": "- Backend Changes",
	"may29-2026-a": "- Added Nullight to testers\n- Added Alt volume wheel\n- Added Elizondo the Third to testers\n- Updated notification system logic\n- Updated Skip info\n- Re-enabled VR for testing",
	"may29-2026-b": "- VR testing",
	"may31-2026-a": "- Timer turns red 1 second before pause\n- Other small changes!",
	"june2-2026-a": "- Updated S rank to be 99% accuracy",
	"june2-2026-b": "- Bug fix",
	"june2-2026-c": "- Fixed 99% accuracy for SS rank(I changed wrong one oopsies)",
	"june3-2026-a": "- Fixed client from saying it's out of date",
	"july6-2026-a": "- Updated update log\n- Updated date",
	"july13-2026-online-testing": "- Unreleased testing build",
	"july14-2026-online-testing-2": "- Added Versus\n- Added Spectating\n- Updated loading details to show total map load count",
	"july14-2026-online-testing-3": "- Added map sharing through hosts\n(you can host any map now)\n- Updated Spectating(kinda)",
	"july15-2026-a": "- Reverted spectating to an old version ",
	"july18-2026-a": "- Added Borderless Windowed\n- Added Replay viewer\n- Added Cursor Face Velocity\n- Added yellow highlight in versus\n- Added XP\n- Added keybinds\n- Added collapsing to colorsets\n- Added Discord connection\n- Fixed Alt volume slider anywhere\n- Fixed Speed mods updating in real time for lobbies\n- Fixed scrolling on the start time slider",
	"july18-2026-b": "- Quick fix for spectating",
	"july19-2026-a": "- Quick fix for map loading",
	"july23-2026-a": "- Added RHM importing\n- Added RHS importing",
	"july23-2026-b": "- Added dedicated update log page!\n- Added a filter to show maps that award XP\n- Fixed XP\n- Fixed Start time\n- Fixed Discord presence\n- Sorted user folder",
	"july24-2026-a": "- Added verification for Ranked passes",
	"july24-2026-b": "- Fixed intro playing for SSQE playtest\n- Backend fixes",
	"july25-2026-a": "- Added XP notifications\n- Added lead-in time\n- Added ability to download ranked maps in-game\n- Added online settings tab\n- Added ability to unlink Discord\n- Fixed Custom speed\n- Fixed hashing issues\n- Fixed some compatibility issues with multiple mods at once",
	"july25-2026-b": "- Fixed Discord Rich Presence",
	"july25-2026-c": "- Added XP recommendations for maps",
	"july26-2026-a": "- Added gif support for cursors and backgrounds\n- Added saving for hit sounds and miss sounds\n- Added a new leaderboard (SP)",
	"july27-2026-a": "- Added death slowdown\n- Added custom borders\n- Added PB display for ranked maps\n- Updated the logo(credits to y.nag)",
	"august6-2026-a": "- Added Play timestamps\n- Updated filters to save\n- ",
	"sep27-2026-web-a": "- Web release",
	"sep27-2026-web-b": "- Web 2",
}

func _notify_latest_update(current_ver: String):
	var notes = String(VERSION_NOTES.get(current_ver, ""))
	if notes == "":
		return
	Globals.notify(
		Globals.NOTIFY_INFO,
		notes,
		"What's New in " + current_ver,
		15
	)

func get_update_log_text() -> String:
	var entries = []
	for i in range(VERSION_SEQUENCE.size() - 1, -1, -1):
		var v = VERSION_SEQUENCE[i]
		if VERSION_NOTES.has(v):
			entries.append("[%s]\n%s" % [v, VERSION_NOTES[v]])
	entries.append("[Legacy Updates]\n" + VERSION_NOTES["LEGACY"])
	return "\n\n".join(entries)


signal mods_changed
signal speed_mod_changed
signal selected_song_changed
signal selected_space_changed
signal selected_colorset_changed
signal selected_mesh_changed
signal selected_hit_sound_changed
signal selected_miss_sound_changed
signal init_stage_reached
signal init_stage_num
signal vr_status_checked
signal map_list_ready
signal local_maps_loaded
signal volume_changed
signal favorite_songs_changed
signal menu_music_state_changed
signal download_start
signal download_done



var user_pack_dir: String = Globals.p("user://packs")
var user_mod_dir: String = Globals.p("user://mods")
var user_vmap_dir: String = Globals.p("user://vmaps")
var user_map_dir: String = Globals.p("user://maps")
var user_best_dir: String = Globals.p("user://bests")
var user_colorset_dir: String = Globals.p("user://colorsets")
var user_friend_dir: String = Globals.p("user://friend")
var user_mesh_dir: String = Globals.p("user://meshes")
var user_profiles_dir: String = Globals.p("user://profiles")


var installed_dlc: Array = ["ssp_basegame"]
var installed_mods: Array = []
var installed_packs: Array = []


var registry_colorset: Registry
var registry_song: Registry
var registry_world: Registry
var registry_mesh: Registry
var registry_effect: Registry
var registry_hit_sound: Registry
var registry_miss_sound: Registry
var registry_border: Registry

var selected_space: BackgroundWorld
var selected_colorset: ColorSet
var selected_song: Song
var selected_mesh: NoteMesh
var selected_hit_sound: NamedSound
var selected_miss_sound: NamedSound
var selected_border: Border
var border_color: Color = Color(1, 1, 1, 0.588235)
signal hit_sounds_changed
signal miss_sounds_changed
signal selected_border_changed
signal borders_changed

func select_colorset(set: ColorSet):
	if set:
		selected_colorset = set
		emit_signal("selected_colorset_changed", set)
func select_hit_sound(snd: NamedSound):
	if snd:
		selected_hit_sound = snd
		refresh_active_sound_streams()
		emit_signal("selected_hit_sound_changed", snd)
func select_miss_sound(snd: NamedSound):
	if snd:
		selected_miss_sound = snd
		refresh_active_sound_streams()
		emit_signal("selected_miss_sound_changed", snd)
func select_world(world: BackgroundWorld):
	if world:
		selected_space = world
		emit_signal("selected_space_changed", world)
func select_mesh(mesh: NoteMesh):
	selected_mesh = mesh
	emit_signal("selected_mesh_changed", mesh)
func select_border(b: Border):
	if b:
		selected_border = b
		emit_signal("selected_border_changed", b)
func select_song(song: Song):
	if song.is_online:
		emit_signal("download_start")
		get_tree().paused = true

		print("[Online Map] Starting download")
		var id: String = Online.download_map(song)

		print("[Online Map] Waiting for download to finish")
		var result: Dictionary = yield(Online, "map_downloaded")
		while result.id != id:
			print("[Online Map] Wrong download: %s != %s" % [result.id, id])
			result = yield(Online, "map_downloaded")
		print("[Online Map] Download finished")

		get_tree().paused = false
		if result.success:
			emit_signal("download_done")
			selected_song = song
			emit_signal("selected_song_changed", song)
		elif result.error == "010-100":
			emit_signal("download_done")
		else:
			Globals.confirm_prompt.s_alert.play()
			Globals.confirm_prompt.open(
				"Failed to download map.\nError code: %s" % result.error,
				"Error",
				[{text = "OK"}]
			)
			yield(Globals.confirm_prompt, "option_selected")
			Globals.confirm_prompt.s_back.play()
			Globals.confirm_prompt.close()
			yield(Globals.confirm_prompt, "done_closing")
			emit_signal("download_done")
	else:
		selected_song = song
		emit_signal("selected_song_changed", song)



var just_ended_song: bool = false
var song_end_type: int = Globals.END_FAIL
var song_end_misses: int
var song_end_hits: int
var song_end_total_notes: int
var song_end_position: float
var song_end_pause_count: int
var song_end_accuracy_str: String
var song_end_time_str: String
var song_end_length: float
var song_end_combo: int

var replay: Replay
var replay_path: String = ""
var was_replay: bool = false
var replaying: bool = false


var load_target_frame_time: float = 1.0 / 40.0
var rainbow_t: float = 0
var note_spin_t: float = 0
var alert: String = ""
var should_ask_about_replays: bool = true
var do_archive_convert: bool = false
var conmgr_transit = null
var errornum: int = 0
var errorstr: String = ""
var first_init_done = false
var loaded_world = null
var was_map_screen_centered: bool = true
var menu_target: String = ProjectSettings.get_setting("application/config/default_menu_target")
var is_init: bool = true


var was_auto_play_switch: bool = true
var last_search_str: String = ""
var last_author_search_str: String = ""
var last_search_incl_broken: bool = false
var last_search_incl_online: bool = true
var last_search_xp_only: bool = false
var last_search_flip_sort: bool = false
var last_search_flip_name_sort: bool = false
var last_page_num: int = 0

var _online_maps_fetched: bool = false
func ensure_online_maps_loaded():
	if _online_maps_fetched:
		return
	_online_maps_fetched = true
	Online.load_db_maps()
var last_difficulty_filter: Array = [
	Globals.DIFF_UNKNOWN,
	Globals.DIFF_EASY,
	Globals.DIFF_MEDIUM,
	Globals.DIFF_HARD,
	Globals.DIFF_LOGIC,
	Globals.DIFF_AMOGUS
]


var vr: bool = false
var fake_vr: bool = false
var vr_available: bool = false
var vr_interface: ARVRInterface
var vr_left_handed: bool = false
var vr_controller_type: int = Globals.VR_GENERIC
var _vr_check_thread: Thread = null


var queue_active: bool = false
var queue_pos: int = 0
var song_queue: Array = []
var just_ended_queue: bool = false
var queue_end_type: int = Globals.END_FAIL
var queue_end_misses: int
var queue_end_hits: int
var queue_end_total_notes: int
var queue_end_position: float
var queue_end_pause_count: int
var queue_end_accuracy_str: String
var queue_end_time_str: String
var queue_end_length: float
var queue_end_combo: int



var miss_snd: AudioStream
var hit_snd: AudioStream
var fail_snd: AudioStream
var pb_snd: AudioStream
var menu_bgm: AudioStream

var normal_pb_sound
var def_miss_snd: AudioStream
var def_hit_snd: AudioStream
var def_fail_snd: AudioStream
var def_pb_snd: AudioStream
var def_menu_bgm: AudioStream


var fail_asp: AudioStreamPlayer = AudioStreamPlayer.new()


var ignore_controller_detection: bool = false


var expand_hud_onhr: bool = false

var _vr_checked: bool = false

func ensure_vr_checked():
	if _vr_checked or _vr_check_thread:
		return
	_vr_check_thread = Thread.new()
	_vr_check_thread.start(self, "_check_vr_availability")

func _check_vr_availability(_userdata = null):
	var interface = ARVRServer.find_interface("OpenVR")
	if interface:
		vr_interface = interface
		vr_available = true
	call_deferred("_finish_vr_check")

func _finish_vr_check():
	if _vr_check_thread:
		_vr_check_thread.wait_to_finish()
		_vr_check_thread = null
	_vr_checked = true
	emit_signal("vr_status_checked")


func start_vr():

	if vr:
		print("VR already active")
		return

	print("VR START")
	vr = true



	var viewport = get_viewport()
	viewport.hdr = false
	OS.vsync_enabled = false
	Engine.target_fps = 720


	if Input.is_key_pressed(KEY_SHIFT):
		print("Enabling fake VR")
		OS.window_maximized = true
		fake_vr = true


		var ev = InputEventKey.new()
		ev.scancode = KEY_F
		InputMap.action_add_event("vr_switch_hands", ev)

		ev = InputEventMouseButton.new()
		ev.button_index = BUTTON_LEFT
		InputMap.action_add_event("vr_click", ev)
	else:

		if not vr_interface.initialize():
			print("Failed to initialize VR!")
			return

		viewport.arvr = true

		setup_controller_bindings()
	if not OS.has_feature("HTML5"):
		var vr_player: VRPlayer

		var vr_av = load("res://vr/VRPlayer.tscn").instance()
		rootg.add_child(vr_av)
		vr_av.name = "VRPlayer"
		vr_player = vr_av

		menu_target = "res://vr/vrmenu.tscn"
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")

func setup_controller_bindings():

	var ev = InputEventJoypadButton.new()
	ev.button_index = JOY_OCULUS_MENU
	InputMap.action_add_event("vr_switch_hands", ev)

	ev = InputEventJoypadButton.new()
	ev.button_index = JOY_OPENVR_MENU
	InputMap.action_add_event("vr_switch_hands", ev)


	ev = InputEventJoypadButton.new()
	ev.button_index = JOY_VR_GRIP
	InputMap.action_add_event("give_up", ev)

	ev = InputEventJoypadMotion.new()
	ev.axis = JOY_VR_ANALOG_GRIP
	InputMap.action_add_event("give_up", ev)


	ev = InputEventJoypadButton.new()
	ev.button_index = JOY_VR_PAD
	InputMap.action_add_event("pause", ev)

	ev = InputEventJoypadButton.new()
	ev.button_index = JOY_OCULUS_BY
	InputMap.action_add_event("pause", ev)

	ev = InputEventJoypadMotion.new()
	ev.axis = 2
	InputMap.action_add_event("vr_click", ev)
	ev = InputEventJoypadMotion.new()
	ev.axis = 4
	InputMap.action_add_event("vr_click", ev)
	print(JOY_VR_ANALOG_TRIGGER)

	ev = InputEventJoypadButton.new()
	ev.button_index = 15
	InputMap.action_add_event("vr_click", ev)



func prepare_queue():
	record_replays = false
	queue_active = true
	just_ended_queue = false
	queue_pos = 0

	queue_end_type = Globals.END_FAIL
	queue_end_misses = 0
	queue_end_hits = 0
	queue_end_total_notes = 0
	queue_end_position = 0
	queue_end_pause_count = 0
	queue_end_length = 0
	queue_end_combo = 0
	for s in song_queue:
		queue_end_length += s.last_ms

func get_next():
	queue_pos += 1
	print(queue_pos)

	queue_end_type = song_end_type
	queue_end_misses += song_end_misses
	queue_end_hits += song_end_hits
	queue_end_total_notes += song_end_total_notes
	queue_end_position += clamp(song_end_position, 0, selected_song.last_ms)
	queue_end_pause_count += song_end_pause_count

	queue_end_combo += song_end_combo

	if song_end_type == Globals.END_GIVEUP or queue_pos == song_queue.size():
		print("all done!")
		just_ended_queue = true
		queue_active = false
		return null

	return song_queue[queue_pos]


func _ready():
	fail_asp.bus = "OtherSound"
	call_deferred("add_child", fail_asp)
	pause_mode = PAUSE_MODE_PROCESS
	Globals.connect("console_sent", self, "_console")

	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear2db(0.5))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear2db(0.5))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("HitSound"), linear2db(0.3))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("MissSound"), linear2db(0.6))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("FailSound"), linear2db(0.6))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("PBSound"), linear2db(0.6))

func set_borderless_windowed(enabled: bool):
	OS.window_borderless = enabled
	if enabled:
		OS.window_fullscreen = false
		OS.window_maximized = false
		OS.window_position = Vector2.ZERO
		OS.window_size = OS.get_screen_size() + Vector2(1, 1)
	else:
		var restored_size = Vector2(
			ProjectSettings.get_setting("display/window/size/width"),
			ProjectSettings.get_setting("display/window/size/height")
		)
		OS.window_size = restored_size
		OS.window_position = (OS.get_screen_size() - restored_size) / 2

func _process(delta):

	rainbow_t = fmod(rainbow_t + (delta * 0.5), 10)

	note_spin_t = fmod(note_spin_t + (delta * 0.5), 360)

	if Input.is_action_just_pressed("fullscreen"):
		OS.window_fullscreen = not OS.window_fullscreen
	if Input.is_action_just_pressed("quit_game"):
		get_tree().quit()
	if _post_death_retry_armed and Input.is_action_just_pressed("retry"):
		_post_death_retry_armed = false
		get_tree().change_scene("res://scenes/loaders/songload.tscn")
	if is_instance_valid(volume_canvas):
		if volume_fade_timer > 0:
			volume_fade_timer -= delta
			volume_label.modulate.a = lerp(volume_label.modulate.a, 1.0, 15 * delta)
		else:
			volume_label.modulate.a = lerp(volume_label.modulate.a, 0.0, 5 * delta)

var volume_canvas: CanvasLayer
var volume_label: Label
var volume_percent: float = 1.0
var volume_fade_timer: float = 0.0

func _input(event):
	if Input.is_key_pressed(KEY_ALT):
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == BUTTON_WHEEL_UP:
				_change_volume(0.05)
				get_tree().set_input_as_handled()
			elif event.button_index == BUTTON_WHEEL_DOWN:
				_change_volume(-0.05)
				get_tree().set_input_as_handled()

	if event is InputEventKey and event.pressed and not event.echo and event.scancode == KEY_D and event.control and event.alt and event.shift:
		_advertise_game()

func _advertise_game():
	var Discord
	if OS.has_feature("HTML5"):
		return
	else:
		if not ProjectSettings.get_setting("application/config/discord_rpc"):
			return
		var activity = Discord.Activity.new()
		activity.set_type(Discord.ActivityType.Playing)
		activity.set_details("Join us Now")
		activity.set_state("discord.gg/Hs2E5w5N68")
		var assets = activity.get_assets()
		assets.set_large_image("icon-bg")
		Discord.activity_manager.update_activity(activity)

func _change_volume(amount: float):
	if not is_instance_valid(volume_canvas):
		_spawn_volume_ui()
	volume_percent = stepify(clamp(volume_percent + amount, 0.0, 1.0), 0.05)

	AudioServer.set_bus_volume_db(0, linear2db(volume_percent))

	volume_label.text = "Volume: %d%%" % round(volume_percent * 100)
	volume_fade_timer = 2.0

func _spawn_volume_ui():
	volume_canvas = CanvasLayer.new()
	volume_canvas.layer = 100

	volume_label = Label.new()
	volume_label.text = "Volume: 100%"

	volume_label.anchor_left = 1.0
	volume_label.anchor_top = 1.0
	volume_label.anchor_right = 1.0
	volume_label.anchor_bottom = 1.0

	volume_label.margin_left = -150
	volume_label.margin_top = -50
	volume_label.margin_right = -20
	volume_label.margin_bottom = -20

	volume_label.align = Label.ALIGN_RIGHT
	volume_label.valign = Label.VALIGN_BOTTOM

	volume_label.add_color_override("font_color_shadow", Color(0, 0, 0, 1))
	volume_label.add_constant_override("shadow_offset_x", 2)
	volume_label.add_constant_override("shadow_offset_y", 2)

	volume_label.modulate.a = 0.0

	volume_canvas.add_child(volume_label)
	add_child(volume_canvas)

	volume_percent = stepify(clamp(db2linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))), 0.0, 1.0), 0.05)


var desync_alerts: bool = false
var disable_desync: bool = false
func _console(cmd: String, args: String):
	match cmd:
		"queue":
			var ids = args.split(" ", false)
			if ids.size() == 0:
				if song_queue.size() == 0:
					console_cmd_error("Must specify at least 1 map id")
					return
				else:
					Globals.notify(Globals.NOTIFY_SUCCEED, "reactivated queue")
					prepare_queue()
					return
			else:
				var maps = []
				for id in ids:
					var song = registry_song.get_item(id)
					if song: maps.append(song)
					else: Globals.notify(Globals.NOTIFY_ERROR, "No song found with id %s" % [id], "Error")
				if maps.size() == 0:
					console_cmd_error("No valid maps specified")
					return
				select_song(maps[0])
				song_queue = maps
				prepare_queue()
				Globals.notify(Globals.NOTIFY_SUCCEED, "queue OK")
		"play":
			get_tree().change_scene("res://scenes/loaders/songload.tscn")
		"desyncalerts":
			Globals.notify(Globals.NOTIFY_SUCCEED, "Enabled desync alerts", "Success")
			desync_alerts = true
		"disablesync":
			Globals.notify(Globals.NOTIFY_SUCCEED, "Disabled desync checks", "Success")
			disable_desync = true


func console_cmd_error(body: String):
	Globals.confirm_prompt.s_alert.play()
	Globals.confirm_prompt.open(body, "Error", [{text = "OK"}])
	yield(Globals.confirm_prompt, "option_selected")
	Globals.confirm_prompt.s_back.play()
	Globals.confirm_prompt.close()
func update_rpc_song():
	if not ProjectSettings.get_setting("application/config/discord_rpc") or selected_song == null: return
	var txt = ""
	var mods = []
	if mod_nofail: mods.append("Nofail")
	if mod_speed_level != Globals.SPEED_NORMAL:
		match mod_speed_level:
			Globals.SPEED_MMM: mods.append("Speed---")
			Globals.SPEED_MM: mods.append("Speed--")
			Globals.SPEED_M: mods.append("Speed-")
			Globals.SPEED_P: mods.append("Speed+")
			Globals.SPEED_PP: mods.append("Speed++")
			Globals.SPEED_PPP: mods.append("Speed+++")
			Globals.SPEED_PPPP: mods.append("Speed++++")
			Globals.SPEED_CUSTOM: mods.append("Speed %s%%" % [Globals.speed_multi[Globals.SPEED_CUSTOM] * 100])
	if mod_sudden_death: mods.append("SuddenDeath")
	if mod_extra_energy: mods.append("Energy+")
	if mod_no_regen: mods.append("NoRegen")
	if mod_mirror_x or mod_mirror_y:
		var mirrorst = "Mirror"
		if Rhythia.mod_mirror_x: mirrorst += "X"
		if Rhythia.mod_mirror_y: mirrorst += "Y"
		mods.append(mirrorst)
	if mod_ghost: mods.append("Ghost")
	if mod_nearsighted: mods.append("Nearsight")
	if mod_hardrock: mods.append("Hard Rock")
	if mod_360: mods.append(("360x%s" % Rhythia.mod_360_speed))
	if mod_strobe: mods.append(("Strobe!!!"))
	if replay.autoplayer: mods.append("Auto")

	if mods.size() == 0: txt = "No modifiers!!"
	else:
		for i in range(mods.size()):
			if i != 0: txt += ", "
			txt += mods[i]

	if not OS.has_feature("HTML5"):
		var activity = Discord.Activity.new()
		activity.set_type(Discord.ActivityType.Playing)
		activity.set_state(txt)
		activity.set_details(selected_song.name)

		var assets = activity.get_assets()
		assets.set_large_image("icon-bg")

		Discord.activity_manager.update_activity(activity)

func get_stream_with_default(path: String, default: AudioStream) -> AudioStream:
	path = Globals.p(path)
	var file: File = File.new()
	if file.file_exists(path + ".ogg"): path += ".ogg"
	elif file.file_exists(path + ".mp3"): path += ".mp3"
	elif file.file_exists(path + ".wav"): path += ".wav"
	if file.file_exists(path):
		if not path.begins_with("res://"):
			var stream = Globals.audioLoader.load_file(path)
			if stream and stream is AudioStream: return stream
		else:
			var mf: AudioStream = load(path) as AudioStream
			if mf is AudioStream:
				if mf is AudioStreamOGGVorbis or mf is AudioStreamMP3: mf.loop = false
				elif mf is AudioStreamSample: mf.loop_mode = AudioStreamSample.LOOP_DISABLED
				return mf
	return default



var mod_extra_energy: bool = false setget set_mod_extra_energy
var mod_no_regen: bool = false setget set_mod_no_regen
var mod_speed_level: int = Globals.SPEED_NORMAL setget set_mod_speed_level
var mod_nofail: bool = false setget set_mod_nofail
var mod_mirror_x: bool = false setget set_mod_mirror_x
var mod_mirror_y: bool = false setget set_mod_mirror_y
var mod_nearsighted: bool = false setget set_mod_nearsighted
var mod_ghost: bool = false setget set_mod_ghost
var mod_sudden_death: bool = false setget set_mod_sudden_death
var mod_chaos: bool = false setget set_mod_chaos
var mod_earthquake: bool = false setget set_mod_earthquake
var mod_360: bool = false setget set_mod_360
var mod_360_speed: float = 1 setget _set_mod_360_speed
var mod_strobe: bool = false setget _set_mod_strobe
var mod_hardrock: bool = false setget set_mod_hardrock

var start_offset: float = 0 setget _set_start_offset
var note_hitbox_size: float = 1.14 setget _set_hitbox_size
var hitwindow_ms: float = 55 setget _set_hitwindow
var custom_speed: float = 1 setget _set_custom_speed

var health_model: int = Globals.HP_SOUNDSPACE setget _set_health_model
var grade_system: int = Globals.GRADE_SSP setget _set_grade_system
var visual_mode: bool = false setget set_visual_mode
var invert_mouse: bool = false setget set_invert_mouse
var disable_pausing: bool = false
var speed_hitwindow: bool = true
var restart_on_death: bool = false
var death_slowdown_enabled: bool = false
const DEATH_SLOWDOWN_DURATION_SEC: float = 1.5

var _post_death_retry_armed: bool = false

func arm_post_death_quick_restart():
	_post_death_retry_armed = true

func disarm_post_death_quick_restart():
	_post_death_retry_armed = false


func set_mod_extra_energy(v: bool):
	if v:
		mod_sudden_death = false
		mod_nofail = false
	mod_extra_energy = v; emit_signal("mods_changed")
func set_mod_no_regen(v: bool):
	if v:
		mod_sudden_death = false
		mod_nofail = false
	mod_no_regen = v; emit_signal("mods_changed")
func set_mod_speed_level(v: int):
	mod_speed_level = v; emit_signal("mods_changed"); emit_signal("speed_mod_changed")
func set_mod_nofail(v: bool):
	if v:
		mod_extra_energy = false
		mod_no_regen = false
		mod_sudden_death = false
	else:
		visual_mode = false
	mod_nofail = v; emit_signal("mods_changed")
func set_mod_mirror_x(v: bool):
	mod_mirror_x = v; emit_signal("mods_changed")
func set_mod_mirror_y(v: bool):
	mod_mirror_y = v; emit_signal("mods_changed")
func set_mod_nearsighted(v: bool):
	mod_nearsighted = v; emit_signal("mods_changed")
func set_mod_ghost(v: bool):
	mod_ghost = v; emit_signal("mods_changed")
func set_mod_sudden_death(v: bool):
	if v:
		mod_extra_energy = false
		mod_no_regen = false
		mod_nofail = false
	mod_sudden_death = v; emit_signal("mods_changed")

func set_mod_chaos(v: bool):
	mod_chaos = v; emit_signal("mods_changed")
func set_mod_earthquake(v: bool):
	mod_earthquake = v; emit_signal("mods_changed")
func set_mod_360(v: bool):
	mod_360 = v; emit_signal("mods_changed")
func _set_mod_360_speed(v: float):
	mod_360_speed = v; emit_signal("mods_changed")
func _set_mod_strobe(v: bool):
	mod_strobe = v; emit_signal("mods_changed")
func set_mod_hardrock(v: bool):
	mod_hardrock = v; emit_signal("mods_changed")

func _set_start_offset(v: float):
	start_offset = v; emit_signal("mods_changed")
func _set_hitbox_size(v: float):
	note_hitbox_size = v; emit_signal("mods_changed")
func _set_hitwindow(v: float):
	hitwindow_ms = v; emit_signal("mods_changed")
func _set_custom_speed(v: float):

	custom_speed = v
	Globals.speed_multi[Globals.SPEED_CUSTOM] = v
	emit_signal("mods_changed")
	emit_signal("speed_mod_changed")

func set_visual_mode(v: bool):
	if v:
		set_mod_nofail(true)
	visual_mode = v; emit_signal("mods_changed")
func set_invert_mouse(v: bool):
	invert_mouse = v; emit_signal("mods_changed")
func _set_health_model(v: int):
	health_model = v; emit_signal("mods_changed")
func _set_grade_system(v: int):
	grade_system = v; emit_signal("mods_changed")

const CACHE_FILE_PATH = "user://caches/map_cache.json"

func load_cache_from_disk() -> Dictionary:
	var file = File.new()
	if file.file_exists(CACHE_FILE_PATH):
		file.open(CACHE_FILE_PATH, File.READ)
		var json_result = JSON.parse(file.get_as_text())
		file.close()

		if json_result.error == OK and typeof(json_result.result) == TYPE_DICTIONARY:
			return json_result.result

	return {}

func save_cache_to_disk(cache_dict: Dictionary) -> void:
	var file = File.new()
	file.open(CACHE_FILE_PATH, File.WRITE)
	file.store_string(to_json(cache_dict))
	file.close()
	print("Map cache saved to disk.")

var approach_rate: float = 40 setget , get_approach_rate
func get_approach_rate():
	if replaying and replay.settings.has("approach_rate"): return replay.settings.get("approach_rate")
	return approach_rate
var spawn_distance: float = 40 setget , get_spawn_distance
func get_spawn_distance():
	if replaying and replay.settings.has("spawn_distance"): return replay.settings.get("spawn_distance")
	return spawn_distance
var lead_in_ms: float = 3000 setget _set_lead_in_ms
func _set_lead_in_ms(v: float):
	lead_in_ms = v

const LOBBY_LEAD_IN_MS: float = 3000.0
var _lobby_lead_in_backup: float = -1
func apply_lobby_lead_in():
	if _lobby_lead_in_backup < 0:
		_lobby_lead_in_backup = lead_in_ms
	lead_in_ms = LOBBY_LEAD_IN_MS
func restore_lobby_lead_in():
	if _lobby_lead_in_backup >= 0:
		lead_in_ms = _lobby_lead_in_backup
		_lobby_lead_in_backup = -1
var mute_global_chat: bool = false
var mute_lobby_chat: bool = false
var do_note_pushback: bool = true
var half_ghost: bool = false
var note_spawn_effect: bool = false
var note_size: float = 1
var note_spin_x: float = 0
var note_spin_y: float = 0
var note_spin_z: float = 0


var note_opacity: float = 1
var fade_length: float = 0.5 setget , get_fade_length
func get_fade_length():
	if replaying and replay.settings.has("fade_length"): return replay.settings.get("fade_length")
	return fade_length

var show_hit_effect: bool = false
var hit_effect_at_cursor: bool = false

var show_miss_effect: bool = false


var hlm_converted: bool = false
var sensitivity: float = 0.5
var parallax: float = 6.5 setget , get_parallax
func get_parallax():
	if replaying and replay.settings.has("parallax"): return replay.settings.get("parallax")
	return parallax
var ui_parallax: float = 1.63 setget , get_ui_parallax
func get_ui_parallax():
	if replaying and replay.settings.has("ui_parallax"): return replay.settings.get("ui_parallax")
	return ui_parallax
var grid_parallax: float = 0 setget , get_grid_parallax
func get_grid_parallax():
	if replaying and replay.settings.has("grid_parallax"): return replay.settings.get("grid_parallax")
	return grid_parallax
var fov: float = 70 setget , get_fov
func get_fov():
	if replaying and replay.settings.has("fov"): return replay.settings.get("fov")
	return fov
var hit_fov: bool = false
var hit_fov_additive: bool = true
var hit_fov_exponential: bool = false
var hit_fov_amplifier: float = 2
var hit_fov_decay: float = 20
var camera_mode: int = Globals.CAMERA_HALF_LOCK
var cam_unlock: bool = false setget , get_cam_unlock
func get_cam_unlock():
	if replaying and replay.settings.has("cam_unlock"): return replay.settings.get("cam_unlock")
	return cam_unlock
var lock_mouse: bool = true
var absolute_mode: bool = false
var absolute_scale: float = 1
var edge_drift: float = 0
var disable_intro: bool = false


var record_replays: bool = false
var alt_cam: bool = false
var record_limit: int = 0
var record_mode: int = 1
var resolution: int = 3


var cursor_color_type: int = Globals.CURSOR_CUSTOM_COLOR
var cursor_color: Color = Color(1, 1, 1)

var cursor_trail: bool = false
var trail_mode_scale: bool = true
var trail_mode_opacity: bool = true
var smart_trail: bool = false
var trail_detail: int = 10
var trail_time: float = 0.15
var cursor_scale: float = 1
var enable_drift_cursor: bool = true
var follow_drift_cursor: bool = false
var cursor_spin: float = 0
var cursor_face_velocity: bool = false


var display_true_combo: bool = true
var show_config: bool = true
var enable_grid: bool = false
var enable_border: bool = true
var show_hp_bar: bool = true
var show_timer: bool = true
var show_left_panel: bool = true
var show_right_panel: bool = true
var show_cursor: bool = true
var show_accuracy_bar: bool = true
var show_letter_grade: bool = true
var show_fc_grade: bool = true
var attach_hp_to_grid: bool = false
var attach_timer_to_grid: bool = false
var simple_hud: bool = false
var faraway_hud: bool = true
var rainbow_grid: bool = false
var rainbow_hud: bool = false
var friend_position: int = Globals.FRIEND_BEHIND_GRID
var note_visual_approach: bool = false
var visual_approach_follow: bool = false
var billboard_score: bool = false
var score_popup: bool = false
var mirror_buttons: bool = false


var panel_bg: Color = Color("#9b000000")
var panel_text: Color = Color("#ffffff")

var unpause_fill_color: Color = Color("#80fff3")
var unpause_empty_color: Color = Color("#68ff00")
var how_to_quit: Color = Color("#ffdb00")

var combo_fill_color: Color = Color("#7bfff3")
var combo_empty_color: Color = Color("#b94b4b4b")

var acc_fill_color: Color = Color("#8cff00")
var acc_empty_color: Color = Color("#b08f8f8f")

var energy_fill_color: Color = Color("#3aa515")
var energy_empty_color: Color = Color("#af942121")

var giveup_text: Color = Color("#ffffff")
var giveup_fill_color: Color = Color("#ff8f2c")
var giveup_fill_color_end_skip: Color = Color("#81ff75")

var timer_text: Color = Color("#ffffff")
var timer_text_done: Color = Color("#77ff77")
var timer_text_canskip: Color = Color("#b3ffff")

var timer_fg: Color = Color("#ffffff")
var timer_bg: Color = Color("#af8f8f8f")
var timer_fg_done: Color = Color("#25bf00")
var timer_bg_done: Color = Color("#af008f00")
var timer_fg_canskip: Color = Color("#b3ffff")
var timer_bg_canskip: Color = Color("#b0638f8f")

var miss_flash_color: Color = Color("#ff0000")
var pause_used_color: Color = Color("#ff66ff")

var miss_text_color: Color = Color("#ffffff")
var pause_text_color: Color = Color("#ffffff")
var score_text_color: Color = Color("#ffffff")

var pause_ui_opacity: float = 0.75

var grade_ss_saturation: float = 0.4
var grade_ss_value: float = 1
var grade_ss_shine: float = 1

var grade_s_color: Color = Color("#91fffa")
var grade_s_shine: float = 0.5

var grade_a_color: Color = Color("#91ff92")
var grade_b_color: Color = Color("#e7ffc0")
var grade_c_color: Color = Color("#fcf7b3")
var grade_d_color: Color = Color("#fcd0b3")
var grade_f_color: Color = Color("#ff8282")



var auto_preview_song: bool = true
var play_hit_snd: bool = true
var play_miss_snd: bool = true
var sfx_2d: bool = false
var music_offset: float = 0
var play_menu_music: bool = true setget _set_menu_music
var music_volume_db: float = 0 setget _set_music_volume
func _set_menu_music(v: bool):
	play_menu_music = v; emit_signal("menu_music_state_changed")
func _set_music_volume(v: float):
	music_volume_db = v; emit_signal("volume_changed")


var disable_bg_effects: bool = false
var show_warnings: bool = true
var auto_maximize: bool = false




var glow: float = 0
var bloom: float = 0
var vhs_shader: bool = false


var render_scale: float = 1
var ensure_hitsync: bool = false
var hitsync_offset: float = 0
var retain_song_pitch: bool = false
var show_stats: bool = false
var hit_pitch: bool = false
var hit_pitch_min: float = 0.9
var hit_pitch_max: float = 1.15

var language: int = 0



var favorite_songs: Array = []
func save_favorites():
	if not single_map_mode:
		var file: File = File.new()
		file.open(Globals.p("user://favorites.txt"), File.WRITE)
		var txt: String = ""
		for s in favorite_songs:
			if s != favorite_songs[0]: txt += "\n"
			txt += s
		file.store_line(txt)
		file.close()
func is_favorite(id: String):
	return not single_map_mode and favorite_songs.has(id)
func add_favorite(id: String):
	if not single_map_mode and not favorite_songs.has(id):
		favorite_songs.append(id)
		emit_signal("favorite_songs_changed")
		save_favorites()
func remove_favorite(id: String):
	if not single_map_mode and favorite_songs.has(id):
		favorite_songs.remove(favorite_songs.find(id))
		emit_signal("favorite_songs_changed")
		save_favorites()
func _load_covers():
	var allmaps: Array = Rhythia.registry_song.get_items()
	for i in range(allmaps.size()):
		allmaps[i]._get_cover()



func do_pb_check_and_set() -> bool:
	if mod_nofail or was_replay or start_offset != 0 or just_ended_queue or OS.has_feature("debug"): return false
	var has_passed: bool = song_end_type == Globals.END_PASS
	var pb: Dictionary = {}
	pb.position = song_end_position
	pb.length = song_end_length
	pb.hit_notes = song_end_hits
	pb.total_notes = song_end_total_notes
	pb.pauses = song_end_pause_count
	pb.has_passed = song_end_type == Globals.END_PASS
	pb.max_combo = song_end_combo
	pb.ts = OS.get_unix_time()
	return selected_song.set_pb_if_better(generate_pb_str(true), pb)
func get_best():
	return selected_song.get_pb(generate_pb_str(true))

func generate_pb_str(for_pb: bool = false):
	var pts: Array = []
	match mod_speed_level:
		Globals.SPEED_MMM: pts.append("s:---")
		Globals.SPEED_MM: pts.append("s:--")
		Globals.SPEED_M: pts.append("s:-")
		Globals.SPEED_NORMAL: pts.append("s:=")
		Globals.SPEED_P: pts.append("s:+")
		Globals.SPEED_PP: pts.append("s:++")
		Globals.SPEED_PPP: pts.append("s:+++")
		Globals.SPEED_PPPP: pts.append("s:++++")
		Globals.SPEED_CUSTOM: pts.append("s:c%.2f" % Globals.speed_multi[Globals.SPEED_CUSTOM])
	match health_model:
		Globals.HP_OLD: pts.append("hp_old")
		Globals.HP_SOUNDSPACE: pass
	pts.append("hitw:%s" % String(floor(hitwindow_ms)))
	var hb = note_hitbox_size
	pts.append("hbox:%.02f" % note_hitbox_size)
	pts.append("ar:%d" % sign(approach_rate))
	if not for_pb and start_offset != 0: pts.append("so:%f" % start_offset)
	if music_volume_db <= -50: pts.append("silent")

	if mod_sudden_death: pts.append("m_sd")
	if mod_extra_energy: pts.append("m_morehp")
	if mod_no_regen: pts.append("m_noregen")
	if mod_mirror_x: pts.append("m_mirror_x")
	if mod_mirror_y: pts.append("m_mirror_y")
	if mod_nearsighted: pts.append("m_nsight")
	if mod_ghost: pts.append("m_ghost")
	if mod_sudden_death: pts.append("m_sd")
	if mod_chaos: pts.append("m_chaos")
	if invert_mouse: pts.append("m_im")
	if mod_earthquake: pts.append("m_earthquake")
	if mod_360: pts.append("m_360")
	if mod_strobe: pts.append("m_strobe")
	if mod_hardrock: pts.append("m_hardrock")
	if mod_nofail: pts.append("m_nofail")

	pts.sort()

	var s: String = ""
	for i in range(pts.size()):
		if i != 0: s += ";"
		s += pts[i]

	return s


func parse_pb_str(txt: String):
	var data: Dictionary = {}
	var pts: Array = txt.split(";", false)
	data.health_model = Globals.HP_SOUNDSPACE

	data.start_offset = 0
	data.mod_sudden_death = false
	data.mod_extra_energy = false
	data.mod_no_regen = false
	data.mod_mirror_x = false
	data.mod_mirror_y = false
	data.mod_nearsighted = false
	data.mod_ghost = false
	data.mod_chaos = false
	data.invert_mouse = false
	data.mod_earthquake = false
	data.mod_hardrock = false
	data.mod_nofail = false

	for s in pts:
		if s.begins_with("s:c"):
			data.mod_speed_level = Globals.SPEED_CUSTOM
			data.custom_speed = float(s.substr(3))
		elif s.begins_with("hitw:"):
			data.hitwindow_ms = float(s.substr(5))
		elif s.begins_with("so:"):
			data.start_offset = float(s.substr(3))
		elif s.begins_with("hbox:"):
			data.note_hitbox_size = float(s.substr(5))
		else:
			match s:
				"s:---": data.mod_speed_level = Globals.SPEED_MMM
				"s:--": data.mod_speed_level = Globals.SPEED_MM
				"s:-": data.mod_speed_level = Globals.SPEED_M
				"s:=": data.mod_speed_level = Globals.SPEED_NORMAL
				"s:+": data.mod_speed_level = Globals.SPEED_P
				"s:++": data.mod_speed_level = Globals.SPEED_PP
				"s:+++": data.mod_speed_level = Globals.SPEED_PPP
				"s:++++": data.mod_speed_level = Globals.SPEED_PPPP
				"hp_old": data.health_model = Globals.HP_OLD
				"m_sd": data.mod_sudden_death = true
				"m_morehp": data.mod_extra_energy = true
				"m_noregen": data.mod_no_regen = true
				"m_mirror_x": data.mod_mirror_x = true
				"m_mirror_y": data.mod_mirror_y = true
				"m_nsight": data.mod_nearsighted = true
				"m_ghost": data.mod_ghost = true
				"m_chaos": data.mod_chaos = true
				"m_im": data.invert_mouse = true
				"m_earthquake": data.mod_earthquake = true
				"m_strobe": data.mod_strobe = true
				"m_hardrock": data.mod_hardrock = true
				"m_nofail": data.mod_nofail = true
	return data
var prev_state: Dictionary = {}
func save_current_state(): prev_state = parse_pb_str(generate_pb_str())
func restore_prev_state(): for k in prev_state.keys(): set(k, prev_state.get(k))
func apply_state(state: Dictionary): for k in state.keys(): set(k, state.get(k))


var personal_bests: Dictionary = {}
func convert_song_pbs(song: Song):
	for pb in personal_bests.get(song.id, []):
		mod_extra_energy = pb.mod_extra_energy
		mod_no_regen = pb.mod_no_regen
		mod_speed_level = pb.mod_speed_level
		var npb = {
			"position": pb.position,
			"length": pb.length,
			"hit_notes": pb.hit_notes,
			"total_notes": pb.total_notes,
			"pauses": pb.pauses,
			"has_passed": pb.has_passed
		}
		song.set_pb_if_better(generate_pb_str(true), npb)
func load_pbs():
	var file: File = File.new()
	if file.file_exists(Globals.p("user://pb.json")):
		file.open(Globals.p("user://pb.json"), File.READ)
		personal_bests = parse_json(file.get_as_text())
		file.close()
	elif file.file_exists(Globals.p("user://pb")):
		file.open(Globals.p("user://pb"), File.READ)
		var ver: int = file.get_16()
		var x: int = file.get_16()
		while not file.eof_reached():
			if x == 16384 or file.eof_reached():
				file.close()
				return
			var songid: String
			if ver == 2: songid = file.get_pascal_string()
			else: songid = file.get_line()
			personal_bests[songid] = []
			x = file.get_16()
			while x == 69:
				var pb = {}
				pb.has_passed = bool(file.get_8())
				pb.mod_extra_energy = bool(file.get_8())
				pb.mod_no_regen = bool(file.get_8())
				pb.mod_speed_level = file.get_8()
				pb.position = file.get_64()
				pb.length = file.get_64()
				pb.hit_notes = file.get_32()
				pb.total_notes = file.get_32()
				pb.pauses = file.get_16()
				personal_bests[songid].append(pb)
				x = file.get_16()
		file.close()


func is_lacunella_enabled():
	var cdat = File.new()
	if cdat.file_exists("user://lacunella.dat"):
		cdat.open("user://lacunella.dat", File.READ)
		var ctxt = cdat.get_as_text()
		if ctxt.to_upper() == "MEOW": return true
	return false


func memory_lacu():
	var cdata = File.new()
	if cdata.file_exists("user://memory.dat"):
		cdata.open("user://memory.dat", File.READ)
		var ctxt = cdata.get_as_text()
		if ctxt.to_upper() == "DYAMO": return true
	return false


func scol(c: Color) -> String:
	return c.to_html(c.a != 1)
func lcol(data: Dictionary, target: String) -> void:
	if data.has(target) and Color(data[target]):
		set(target, Color(data[target]))


const current_sf_version = 48
func load_saved_settings(saveFile: String = Globals.p("user://settings.json")):
	if Input.is_key_pressed(KEY_CONTROL) and Input.is_key_pressed(KEY_L):
		print("force settings read error")
		return -1
	var file: File = File.new()

	if file.file_exists(saveFile):
		var err = file.open(saveFile, File.READ)
		if err != OK:
			print("file.open failed"); return -2
		var decode = JSON.parse(file.get_as_text())
		file.close()

		if decode.error:
			print("!!! Error on line " + str(decode.error_line) + ": " + decode.error_string)
			return ((-100) - decode.error)

		var data: Dictionary = decode.result

		if data.has("hlm_converted"):
			hlm_converted = data.hlm_converted
		if data.has("approach_rate"):
			approach_rate = data.approach_rate
		if data.has("sensitivity"):
			sensitivity = data.sensitivity
		if data.has("play_hit_snd"):
			play_hit_snd = data.play_hit_snd
		if data.has("play_miss_snd"):
			play_miss_snd = data.play_miss_snd
		if data.has("auto_preview_song"):
			auto_preview_song = data.auto_preview_song
		if data.has("disable_bg_effects"):
			disable_bg_effects = data.disable_bg_effects
		if data.has("render_scale"):
			render_scale = data.render_scale
		if data.has("vsync_enabled"):
			OS.vsync_enabled = data.vsync_enabled


		OS.vsync_via_compositor = false
		if data.has("window_fullscreen"):
			OS.window_fullscreen = data.window_fullscreen
		if data.has("selected_colorset"):
			var cset = registry_colorset.get_item(data.selected_colorset)
			if cset: select_colorset(cset)
		if data.has("selected_hit_sound_id"):
			var hs = registry_hit_sound.get_item(data.selected_hit_sound_id)
			if hs: select_hit_sound(hs)
		if data.has("selected_miss_sound_id"):
			var ms = registry_miss_sound.get_item(data.selected_miss_sound_id)
			if ms: select_miss_sound(ms)
		if data.has("selected_border_id"):
			var bd = registry_border.get_item(data.selected_border_id)
			if bd: select_border(bd)
		if data.has("cam_unlock"):
			cam_unlock = data.cam_unlock
		if data.has("show_config"):
			show_config = data.show_config
		if data.has("enable_grid"):
			enable_grid = data.enable_grid
		if data.has("cursor_scale"):
			cursor_scale = data.cursor_scale
		if data.has("note_size"):
			note_size = data.note_size
		if data.has("note_spin_x"):
			note_spin_x = data.note_spin_x
		if data.has("note_spin_y"):
			note_spin_y = data.note_spin_y
		if data.has("note_spin_z"):
			note_spin_z = data.note_spin_z
		if data.has("note_opacity"):
			note_opacity = data.note_opacity
		if data.has("edge_drift"):
			edge_drift = dser_float(data.edge_drift)
		if data.has("enable_drift_cursor"):
			enable_drift_cursor = data.enable_drift_cursor
		if data.has("follow_drift_cursor"):
			follow_drift_cursor = data.follow_drift_cursor
		if data.has("hitwindow_ms"):
			hitwindow_ms = data.hitwindow_ms
		if data.has("speed_hitwindow"):
			speed_hitwindow = data.speed_hitwindow
		if data.has("restart_on_death"):
			restart_on_death = data.restart_on_death
		if data.has("death_slowdown_enabled"):
			death_slowdown_enabled = data.death_slowdown_enabled
		if data.has("cursor_spin"):
			cursor_spin = data.cursor_spin
		if data.has("selected_space"):
			var world = registry_world.get_item(data.selected_space)
			if world:
				select_world(world)
		if data.has("enable_border"):
			enable_border = data.enable_border
		if data.has("selected_mesh"):
			var mesh = registry_mesh.get_item(data.selected_mesh)
			if mesh:
				select_mesh(mesh)
		if data.has("play_menu_music"):
			play_menu_music = data.play_menu_music
		if data.has("disable_pausing"):
			disable_pausing = data.disable_pausing
		if data.has("note_hitbox_size"):
			note_hitbox_size = data.note_hitbox_size
		if data.has("lead_in_ms"):
			lead_in_ms = data.lead_in_ms
		if data.has("mute_global_chat"):
			mute_global_chat = data.mute_global_chat
		if data.has("mute_lobby_chat"):
			mute_lobby_chat = data.mute_lobby_chat
		if data.has("spawn_distance"):
			spawn_distance = data.spawn_distance
		if data.has("custom_speed"):
			set("custom_speed", data.custom_speed)
		if data.has("note_spawn_effect"):
			note_spawn_effect = data.note_spawn_effect
		if data.has("display_true_combo"):
			display_true_combo = data.display_true_combo

		if data.has("parallax"):
			parallax = data.parallax
		if data.has("ui_parallax"):
			ui_parallax = data.ui_parallax
		if data.has("grid_parallax"):
			grid_parallax = data.grid_parallax

		if data.has("fov"):
			fov = data.fov
		if data.has("hit_fov"):
			hit_fov = data.hit_fov
		if data.has("hit_fov_additive"):
			hit_fov_additive = data.hit_fov_additive
		if data.has("hit_fov_exponential"):
			hit_fov_exponential = data.hit_fov_exponential
		if data.has("hit_fov_amplifier"):
			hit_fov_amplifier = data.hit_fov_amplifier
		if data.has("hit_fov_decay"):
			hit_fov_decay = data.hit_fov_decay
		if data.has("fade_length"):
			fade_length = data.fade_length
		if data.has("show_hit_effect"):
			show_hit_effect = data.show_hit_effect
		if data.has("lock_mouse"):
			lock_mouse = data.lock_mouse
		if data.has("absolute_mode"):
			absolute_mode = data.absolute_mode
		if data.has("absolute_scale"):
			absolute_scale = data.absolute_scale
		if data.has("cursor_trail"):
			cursor_trail = data.cursor_trail
		if data.has("trail_mode_scale"):
			trail_mode_scale = data.trail_mode_scale
		if data.has("trail_mode_opacity"):
			trail_mode_opacity = data.trail_mode_opacity
		if data.has("trail_detail"):
			trail_detail = data.trail_detail
		if data.has("trail_time"):
			trail_time = data.trail_time
		if data.has("friend_position"):
			friend_position = data.friend_position
		if data.has("show_hp_bar"):
			show_hp_bar = data.show_hp_bar
		if data.has("show_timer"):
			show_timer = data.show_timer
		if data.has("show_left_panel"):
			show_left_panel = data.show_left_panel
		if data.has("show_right_panel"):
			show_right_panel = data.show_right_panel
		if data.has("attach_hp_to_grid"):
			attach_hp_to_grid = data.attach_hp_to_grid
		if data.has("attach_timer_to_grid"):
			attach_timer_to_grid = data.attach_timer_to_grid
		if data.has("rainbow_grid"):
			rainbow_grid = data.rainbow_grid
		if data.has("rainbow_hud"):
			rainbow_hud = data.rainbow_hud

		if data.has("hit_effect_at_cursor"):
			hit_effect_at_cursor = data.hit_effect_at_cursor
		if data.has("show_warnings"):
			show_warnings = data.show_warnings
		if data.has("record_replays"):
			should_ask_about_replays = false
			record_replays = data.record_replays
		if data.has("alt_cam"):
			alt_cam = data.alt_cam
		if data.has("record_mode"):
			record_mode = data.record_mode
		if data.has("resolution"):
			resolution = data.resolution
		if data.has("record_limit"):
			record_limit = data.record_limit
		if data.has("show_accuracy_bar"):
			show_accuracy_bar = data.show_accuracy_bar
		if data.has("show_letter_grade"):
			show_letter_grade = data.show_letter_grade
		if data.has("show_fc_grade"):
			show_fc_grade = data.show_fc_grade
		if data.has("simple_hud"):
			simple_hud = data.simple_hud
		if data.has("faraway_hud"):
			faraway_hud = data.faraway_hud
		if data.has("music_offset"):
			music_offset = data.music_offset
		if data.has("auto_maximize"):
			auto_maximize = data.auto_maximize
			if auto_maximize: OS.window_maximized = true
		if data.has("window_fullscreen"):
			OS.window_fullscreen = data.window_fullscreen
		if data.has("window_borderless"):
			set_borderless_windowed(data.window_borderless)
		if data.has("cursor_face_velocity"):
			cursor_face_velocity = data.cursor_face_velocity
		if data.has("note_visual_approach"):
			note_visual_approach = data.note_visual_approach
		if data.has("visual_approach_follow"):
			visual_approach_follow = data.visual_approach_follow
		if data.has("score_popup"):
			score_popup = data.score_popup
		if data.has("billboard_score"):
			billboard_score = data.billboard_score
		if data.has("mirror_buttons"):
			mirror_buttons = data.mirror_buttons
		if data.has("smart_trail"):
			smart_trail = data.smart_trail
		if data.has("sfx_2d"):
			sfx_2d = data.sfx_2d

		if data.has("pause_ui_opacity"):
			pause_ui_opacity = data.pause_ui_opacity
		if data.has("grade_ss_saturation"):
			grade_ss_saturation = data.grade_ss_saturation
		if data.has("grade_ss_value"):
			grade_ss_value = data.grade_ss_value
		if data.has("grade_ss_shine"):
			grade_ss_shine = data.grade_ss_shine
		if data.has("grade_s_shine"):
			grade_s_shine = data.grade_s_shine

		if data.has("cursor_color_type"):
			cursor_color_type = data.cursor_color_type
		elif data.has("rainbow_cursor"):
			cursor_color_type = Globals.CURSOR_RAINBOW

		if data.has("target_fps"):
			Engine.target_fps = data.target_fps
		if data.has("disable_intro"):
			disable_intro = data.disable_intro
		if data.has("ignore_controller_detection"):
			ignore_controller_detection = data.ignore_controller_detection
		if data.has("expand_hud_onhr"):
			expand_hud_onhr = data.expand_hud_onhr

		if data.has("master_volume"):
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), dser_float(data.master_volume))
		if data.has("music_volume"):
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), dser_float(data.music_volume))
		if data.has("hit_volume"):
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("HitSound"), dser_float(data.hit_volume))
		if data.has("miss_volume"):
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("MissSound"), dser_float(data.miss_volume))
		if data.has("fail_volume"):
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("FailSound"), dser_float(data.fail_volume))
		if data.has("pb_volume"):
			AudioServer.set_bus_volume_db(AudioServer.get_bus_index("PBSound"), dser_float(data.pb_volume))

		if data.has("ensure_hitsync"):
			ensure_hitsync = data.ensure_hitsync
		if data.has("retain_song_pitch"):
			retain_song_pitch = data.retain_song_pitch
		if data.has("do_note_pushback"):
			do_note_pushback = data.do_note_pushback
		if data.has("show_stats"):
			show_stats = data.show_stats
		if data.has("hit_pitch"):
			hit_pitch = data.hit_pitch
		if data.has("hit_pitch_min"):
			hit_pitch_min = data.hit_pitch_min
		if data.has("hit_pitch_max"):
			hit_pitch_max = data.hit_pitch_max
		if data.has("half_ghost"):
			half_ghost = data.half_ghost

		if data.has("language"):
			language = data.language
			Globals.apply_language_locale(language)



		if data.has("last_search_incl_online"):
			last_search_incl_online = data.last_search_incl_online
		if data.has("last_search_incl_broken"):
			last_search_incl_broken = data.last_search_incl_broken
		if data.has("last_search_xp_only"):
			last_search_xp_only = data.last_search_xp_only

		lcol(data, "grade_s_color")
		lcol(data, "panel_bg")
		lcol(data, "panel_text")
		lcol(data, "unpause_fill_color")
		lcol(data, "unpause_empty_color")
		lcol(data, "how_to_quit")
		lcol(data, "combo_fill_color")
		lcol(data, "combo_empty_color")
		lcol(data, "acc_fill_color")
		lcol(data, "acc_empty_color")
		lcol(data, "energy_fill_color")
		lcol(data, "energy_empty_color")
		lcol(data, "giveup_text")
		lcol(data, "giveup_fill_color")
		lcol(data, "giveup_fill_color_end_skip")
		lcol(data, "timer_text")
		lcol(data, "timer_text_done")
		lcol(data, "timer_text_canskip")
		lcol(data, "timer_fg")
		lcol(data, "timer_bg")
		lcol(data, "timer_fg_done")
		lcol(data, "timer_bg_done")
		lcol(data, "timer_fg_canskip")
		lcol(data, "timer_bg_canskip")
		lcol(data, "miss_flash_color")
		lcol(data, "pause_used_color")
		lcol(data, "miss_text_color")
		lcol(data, "pause_text_color")
		lcol(data, "score_text_color")
		lcol(data, "grade_a_color")
		lcol(data, "grade_b_color")
		lcol(data, "grade_c_color")
		lcol(data, "grade_d_color")
		lcol(data, "grade_f_color")
		lcol(data, "cursor_color")
		lcol(data, "border_color")

		if data.has("glow"):
			glow = data.glow
		if data.has("bloom"):
			bloom = data.bloom
		if data.has("vhs_shader"):
			vhs_shader = data.vhs_shader


	elif file.file_exists(Globals.p("user://settings")):
		var err = file.open(Globals.p("user://settings"), File.READ)
		if err != OK:
			print("file.open failed"); return 1
		var sv: int = file.get_16()
		if sv <= 3 or sv > current_sf_version:
			print("invalid file version"); return 2
		approach_rate = file.get_float()
		sensitivity = file.get_float()
		play_hit_snd = bool(file.get_8())
		play_miss_snd = bool(file.get_8())
		if sv >= 4: auto_preview_song = bool(file.get_8())
		if file.get_8() != 0:
			print("integ 1"); return 3
		OS.vsync_enabled = bool(file.get_8())
		OS.vsync_via_compositor = bool(file.get_8()) and false
		OS.window_fullscreen = bool(file.get_8())

		var cset = registry_colorset.get_item(file.get_line())
		if cset: select_colorset(cset)

		if sv >= 5:
			parallax = file.get_float()
		if sv >= 6:
			cam_unlock = bool(file.get_8())

		if sv >= 17:
			if file.get_8() != 215:
				print("integ 2"); return 4

		if sv >= 7:
			show_config = bool(file.get_8())
			enable_grid = false
		if sv >= 8:
			cursor_scale = file.get_float()

		if sv >= 17:
			if file.get_8() != 43:
				print("integ 3"); return 5

		if sv >= 9:
			edge_drift = file.get_float()
			enable_drift_cursor = bool(file.get_8())
		if sv >= 10:
			hitwindow_ms = file.get_float()

		if sv >= 17:
			if file.get_8() != 117:
				print("integ 4"); return 6

		if sv >= 11:
			cursor_spin = file.get_float()
		if sv >= 12:
			music_volume_db = file.get_float()
		if sv >= 13:
			var world = registry_world.get_item(file.get_line())
			if world:
				select_world(world)

		if sv >= 17:
			if file.get_8() != 89:
				print("integ 5"); return 7

		if sv >= 14:
			enable_border = bool(file.get_8())
		if sv >= 15:
			var mesh = registry_mesh.get_item(file.get_line())
			if mesh:
				select_mesh(mesh)
		if sv >= 16:
			play_menu_music = bool(file.get_8())

		if sv >= 17:
			if file.get_8() != 12:
				print("integ 6"); return 8

		if sv >= 18:
			disable_pausing = bool(file.get_8())
			note_hitbox_size = float(str(file.get_float()))
		if sv >= 19:
			spawn_distance = file.get_float()
		if sv >= 20:
			set("custom_speed", file.get_float())
			note_spawn_effect = bool(file.get_8())
		if sv >= 21:
			display_true_combo = bool(file.get_8())
		if sv >= 22:

			file.get_8()
		if sv >= 23:
			if file.get_8() != 147:
				print("integ 7"); return 9

			ui_parallax = file.get_float()

		if sv >= 24:
			grid_parallax = file.get_float()
		else:

			grid_parallax = 0
			ui_parallax = 0

		if sv >= 25:
			fade_length = file.get_float()

		if sv < 26 and String(note_hitbox_size) == "1.27":

			print("0.13 :laugh:")
			note_hitbox_size = 1.14

		if sv >= 27:
			show_hit_effect = false
		if sv >= 28:
			if file.get_8() != 6:
				print("integ 8"); return 10

			lock_mouse = bool(file.get_8())
			if bool(file.get_8()):
				cursor_color_type = Globals.CURSOR_RAINBOW
			cursor_trail = bool(file.get_8())
		if sv >= 29:
			trail_detail = file.get_32()
			trail_time = file.get_real()
		if sv >= 30:
			friend_position = file.get_8()
			show_hp_bar = bool(file.get_8())
			show_timer = bool(file.get_8())
			show_left_panel = bool(file.get_8())
			show_right_panel = bool(file.get_8())
			attach_hp_to_grid = bool(file.get_8())
			attach_timer_to_grid = bool(file.get_8())
			rainbow_grid = bool(file.get_8())
			rainbow_hud = bool(file.get_8())
			var had_smart_trail = bool(file.get_8())
			if sv >= 32:
				smart_trail = had_smart_trail
			else:

				alert = "The behavior of the Smart Trail setting has been significantly changed, so it has been turned off. See its description in Settings for the new behavior."
				save_settings()
		if sv >= 31:
			var eff = false
			if eff:
				pass

			if file.get_8() != 192:
				print("integ 9"); return 11

			hit_effect_at_cursor = false
		if sv >= 33:
			show_warnings = bool(file.get_8())
		if sv >= 34:
			should_ask_about_replays = false
			record_replays = bool(file.get_8())
		if sv >= 35:
			alt_cam = bool(file.get_8())
		if sv >= 36:
			show_accuracy_bar = bool(file.get_8())
			show_letter_grade = bool(file.get_8())
			simple_hud = bool(file.get_8())
		if sv >= 37:
			faraway_hud = bool(file.get_8())
		if sv >= 38:
			if sv >= 41:
				music_offset = float(file.get_float())
			else:
				music_offset = float(file.get_32())
		if sv >= 39:
			var eff = registry_effect.get_item(file.get_line())
			if false:
				pass
			show_miss_effect = false
		if sv >= 40:
			auto_maximize = bool(file.get_8())
		if sv >= 42:
			note_visual_approach = bool(file.get_8())
		if sv >= 43:
			score_popup = bool(file.get_8())
			billboard_score = bool(file.get_8())
			if (OS.has_feature("Android")): mirror_buttons = bool(file.get_8())
		if sv >= 44:
			fov = float(file.get_32())
			hit_fov = bool(file.get_8())
			hit_fov_additive = bool(file.get_8())
			hit_fov_amplifier = float(file.get_32())
			hit_fov_decay = float(file.get_32())
		if sv >= 45:
			hit_fov_exponential = bool(file.get_8())
		if sv >= 46:
			ensure_hitsync = bool(file.get_8())
		if sv >= 47:
			trail_mode_scale = bool(file.get_8())
			trail_mode_opacity = bool(file.get_8())
		if sv >= 48:
			ignore_controller_detection = bool(file.get_8())
		if sv >= 49:
			expand_hud_onhr = bool(file.get_8())
		if sv >= 50:
			last_search_incl_online = bool(file.get8())
		file.close()
		save_settings()
	return 0

func ser_float(n: float):
	if is_nan(n):
		return "nan"
	elif is_inf(n):
		return "+inf" if sign(n) > 0 else "-inf"
	else:
		return n

func dser_float(s):
	if typeof(s) == TYPE_STRING:
		if "inf" in s:
			return INF * (1 if s[0] == "+" else -1)
		else:
			return NAN
	else:
		return s

func save_settings(saveFile: String = Globals.p("user://settings.json")):
	var dir = Directory.new()
	var folder_path = "user://"
	if not dir.dir_exists(folder_path):
		dir.make_dir_recursive(folder_path)
		print("Created profiles directory")

	var file: File = File.new()
	var err: int = file.open(Globals.p(saveFile), File.WRITE)
	if err == OK:
		var data = {
			hlm_converted = hlm_converted,
			disable_pausing = disable_pausing,
			approach_rate = approach_rate,
			sensitivity = sensitivity,
			play_hit_snd = play_hit_snd,
			play_miss_snd = play_miss_snd,
			auto_preview_song = auto_preview_song,
			disable_bg_effects = disable_bg_effects,
			render_scale = render_scale,
			vsync_enabled = OS.vsync_enabled,

			window_fullscreen = OS.window_fullscreen,
			window_borderless = OS.window_borderless,
			selected_colorset = selected_colorset.id,
			selected_hit_sound_id = (selected_hit_sound.id if selected_hit_sound else "default"),
			selected_miss_sound_id = (selected_miss_sound.id if selected_miss_sound else "default"),
			selected_border_id = (selected_border.id if selected_border else "default"),
			selected_space = selected_space.id,
			selected_mesh = selected_mesh.id,
			parallax = parallax,
			fov = fov,
			hit_fov = hit_fov,
			hit_fov_additive = hit_fov_additive,
			hit_fov_amplifier = hit_fov_amplifier,
			hit_fov_exponential = hit_fov_exponential,
			hit_fov_decay = hit_fov_decay,
			trail_mode_scale = trail_mode_scale,
			trail_mode_opacity = trail_mode_opacity,
			cam_unlock = cam_unlock,
			show_config = show_config,
			enable_grid = false,
			cursor_scale = cursor_scale,
			enable_drift_cursor = enable_drift_cursor,
			follow_drift_cursor = follow_drift_cursor,
			hitwindow_ms = hitwindow_ms,
			speed_hitwindow = speed_hitwindow,
			restart_on_death = restart_on_death,
			death_slowdown_enabled = death_slowdown_enabled,
			cursor_spin = cursor_spin,
			note_size = note_size,
			note_opacity = note_opacity,
			note_spin_x = note_spin_x,
			note_spin_y = note_spin_y,
			note_spin_z = note_spin_z,
			enable_border = enable_border,
			play_menu_music = play_menu_music,
			note_hitbox_size = note_hitbox_size,
			lead_in_ms = lead_in_ms,
			mute_global_chat = mute_global_chat,
			mute_lobby_chat = mute_lobby_chat,
			spawn_distance = spawn_distance,
			custom_speed = custom_speed,
			display_true_combo = display_true_combo,
			cursor_face_velocity = cursor_face_velocity,
			ui_parallax = ui_parallax,
			grid_parallax = grid_parallax,
			fade_length = fade_length,
			show_hit_effect = false,
			lock_mouse = lock_mouse,
			absolute_mode = absolute_mode,
			absolute_scale = absolute_scale,
			cursor_trail = cursor_trail,
			trail_detail = trail_detail,
			trail_time = trail_time,
			friend_position = friend_position,
			show_hp_bar = show_hp_bar,
			show_timer = show_timer,
			show_left_panel = show_left_panel,
			show_right_panel = show_right_panel,
			attach_hp_to_grid = attach_hp_to_grid,
			attach_timer_to_grid = attach_timer_to_grid,
			rainbow_grid = rainbow_grid,
			rainbow_hud = rainbow_hud,
			smart_trail = smart_trail,
			hit_effect_at_cursor = false,
			show_warnings = show_warnings,
			record_replays = record_replays,
			alt_cam = alt_cam,
			record_mode = record_mode,
			resolution = resolution,
			record_limit = record_limit,
			show_accuracy_bar = show_accuracy_bar,
			show_letter_grade = show_letter_grade,
			show_fc_grade = show_fc_grade,
			simple_hud = simple_hud,
			faraway_hud = faraway_hud,
			music_offset = music_offset,
			auto_maximize = auto_maximize,
			note_visual_approach = note_visual_approach,
			visual_approach_follow = visual_approach_follow,
			score_popup = score_popup,
			billboard_score = billboard_score,
			mirror_buttons = mirror_buttons,
			sfx_2d = sfx_2d,
			cursor_color_type = cursor_color_type,
			half_ghost = half_ghost,
			note_spawn_effect = note_spawn_effect,
			target_fps = Engine.target_fps,
			disable_intro = disable_intro,
			ignore_controller_detection = ignore_controller_detection,
			expand_hud_onhr = expand_hud_onhr,
			last_search_incl_online = last_search_incl_online,
			last_search_incl_broken = last_search_incl_broken,
			last_search_xp_only = last_search_xp_only,

			master_volume = ser_float(clamp(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), -80, 1000000)),
			music_volume = ser_float(clamp(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), -80, 1000000)),
			hit_volume = ser_float(clamp(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("HitSound")), -80, 1000000)),
			miss_volume = ser_float(clamp(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("MissSound")), -80, 1000000)),
			fail_volume = ser_float(clamp(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("FailSound")), -80, 1000000)),
			pb_volume = ser_float(clamp(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("PBSound")), -80, 1000000)),

			cursor_color = scol(cursor_color),
			border_color = scol(border_color),
			panel_bg = scol(panel_bg),
			panel_text = scol(panel_text),
			unpause_fill_color = scol(unpause_fill_color),
			unpause_empty_color = scol(unpause_empty_color),
			how_to_quit = scol(how_to_quit),
			combo_fill_color = scol(combo_fill_color),
			combo_empty_color = scol(combo_empty_color),
			acc_fill_color = scol(acc_fill_color),
			acc_empty_color = scol(acc_empty_color),
			energy_fill_color = scol(energy_fill_color),
			energy_empty_color = scol(energy_empty_color),
			giveup_text = scol(giveup_text),
			giveup_fill_color = scol(giveup_fill_color),
			giveup_fill_color_end_skip = scol(giveup_fill_color_end_skip),
			timer_text = scol(timer_text),
			timer_text_done = scol(timer_text_done),
			timer_text_canskip = scol(timer_text_canskip),
			timer_fg = scol(timer_fg),
			timer_bg = scol(timer_bg),
			timer_fg_done = scol(timer_fg_done),
			timer_bg_done = scol(timer_bg_done),
			timer_fg_canskip = scol(timer_fg_canskip),
			timer_bg_canskip = scol(timer_bg_canskip),
			miss_flash_color = scol(miss_flash_color),
			pause_used_color = scol(pause_used_color),
			miss_text_color = scol(miss_text_color),
			pause_text_color = scol(pause_text_color),
			score_text_color = scol(score_text_color),
			pause_ui_opacity = pause_ui_opacity,
			grade_ss_saturation = grade_ss_saturation,
			grade_ss_value = grade_ss_value,
			grade_ss_shine = grade_ss_shine,
			grade_s_color = scol(grade_s_color),
			grade_s_shine = grade_s_shine,
			grade_a_color = scol(grade_a_color),
			grade_b_color = scol(grade_b_color),
			grade_c_color = scol(grade_c_color),
			grade_d_color = scol(grade_d_color),
			grade_f_color = scol(grade_f_color),

			edge_drift = ser_float(edge_drift),
			ensure_hitsync = ensure_hitsync,
			retain_song_pitch = retain_song_pitch,
			do_note_pushback = do_note_pushback,
			show_stats = show_stats,
			hit_pitch = hit_pitch,
			hit_pitch_min = hit_pitch_min,
			hit_pitch_max = hit_pitch_max,
			language = language,
			glow = glow,
			bloom = bloom,
			vhs_shader = vhs_shader,
		}

		file.store_string(JSON.print(data, "\t"))

		file.close()
		return "OK"
	else:
		print("error code %s" % err)
		return err


func register_colorsets():
	registry_colorset.add_item(ColorSet.new(
	[
		Color("#e95f5f"), Color("#ffb2b2"), Color("#e88d5f"), Color("#ffcdb2"), Color("#e8ba5f"), Color("#ffe8b2"),
		Color("#e8e85f"), Color("#faffb2"), Color("#bae85f"), Color("#dfffb2"), Color("#8de85f"), Color("#c4ffb2"),
		Color("#5fe85f"), Color("#b2ffbb"), Color("#5fe88d"), Color("#b2ffd6"), Color("#5fe8ba"), Color("#b2fff1"),
		Color("#5fe8e8"), Color("#b2f1ff"), Color("#5fbae8"), Color("#b2d6ff"), Color("#5f8de8"), Color("#b2bbff"),
		Color("#5f5fe8"), Color("#c4b2ff"), Color("#8d5fe8"), Color("#dfb2ff"), Color("#ba5fe8"), Color("#fab2ff"),
		Color("#e85fe8"), Color("#ffb2e8"), Color("#e85fa4"), Color("#ffb2cd"), Color("#e85f8d"), Color("#ffb2b2")
	],
		"ssp_rainbowfreeze2", "rainbow freeze 2", "tony bologna"
	))
	registry_colorset.add_item(ColorSet.new(
		[Color("#00ffed"), Color("#ff8ff9")],
		"ssp_cottoncandy", "Cotton Candy", ""
	))
	registry_colorset.add_item(ColorSet.new(
		[Color("#ffb3e1"), Color("#ffffff")],
		"ssp_brecken", "Brecken's Choice", "BrRecken"
	))
	registry_colorset.add_item(ColorSet.new(
		[Color("#ffcc4d"), Color("#ff7892"), Color("#e5dd80")],
		"ssp_veggiestraws", "Veggie Straws", "Chedski"
	))
	registry_colorset.add_item(ColorSet.new(
		[Color("#fc94f2"), Color("#96fc94")],
		"ssp_everybodyvotes", "Everybody Votes Channel", "Chedski"
	))
	registry_colorset.add_item(ColorSet.new(
		[Color("#fc4441"), Color("#4151fc")],
		"ssp_redblue", "Red & Blue", "Chedski"
	))
	registry_colorset.add_item(ColorSet.new(
		[Color("#5BCEFA"), Color("#F5A9B8"), Color("#FFFFFF")],
		"ssp_pastel", "Pastel", "Chedski"
	))
	registry_colorset.add_item(ColorSet.new(
		[
			Color("#e95f5f"), Color("#e88d5f"), Color("#e8ba5f"), Color("#e8e85f"),
			Color("#bae85f"), Color("#8de85f"), Color("#5fe85f"), Color("#5fe88d"),
			Color("#5fe8ba"), Color("#5fe8e8"), Color("#5fbae8"), Color("#5f8de8"),
			Color("#5f5fe8"), Color("#8d5fe8"), Color("#ba5fe8"), Color("#e85fe8"),
			Color("#e85fa4"), Color("#e85f8d"),
		],
		"ssp_hue", "Hue Wheel", "Chedski"
	))
	registry_colorset.add_item(ColorSet.new(
		[
			Color("#e95f5f"), Color("#e8765f"), Color("#e88d5f"), Color("#e8a45f"),
			Color("#e8ba5f"), Color("#e8d15f"), Color("#e8e85f"), Color("#d1e85f"),
			Color("#bae85f"), Color("#a4e85f"), Color("#8de85f"), Color("#76e85f"),
			Color("#5fe85f"), Color("#5fe876"), Color("#5fe88d"), Color("#5fe8a4"),
			Color("#5fe8ba"), Color("#5fe8d1"), Color("#5fe8e8"), Color("#5fd1e8"),
			Color("#5fbae8"), Color("#5fa4e8"), Color("#5f8de8"), Color("#5f76e8"),
			Color("#5f5fe8"), Color("#765fe8"), Color("#8d5fe8"), Color("#a45fe8"),
			Color("#ba5fe8"), Color("#d15fe8"), Color("#e85fe8"), Color("#e85fd1"),
			Color("#e85fa4"), Color("#e85f8d"), Color("#e85f8d"), Color("#e85f76"),
		],
		"ssp_hue_ultra", "Hue Wheel Ultra", "Chedski"
	))
	registry_colorset.add_item(ColorSet.new(
		[Color("#ffffff")],
		"ssp_soul", "SOUL", "Chedski"
	))
	registry_colorset.add_item(ColorSet.new(
		[Color("#9a5ef9")],
		"ssp_purple", "purple!!!", "Chedski"
	))
	registry_colorset.add_item(ColorSet.new(
		[Color("#000000"), Color("#381e42")],
		"ssp_vortex", "Vortex", "pyrule"
	))
	registry_colorset.add_item(ColorSet.new(
		[Color("#008cff"), Color("#ed3434"), Color("#10bd0d"), Color("#ffb300")],
		"ssp_wii", "Wii Players", "balt"
	))

func register_worlds():

	registry_world.add_item(BackgroundWorld.new(
		"ssp_space_tunnel", "Neon Corners",
		"res://assets/worlds/neon_tunnel/space_tunnel.tscn", "Chedski",
		"res://assets/worlds/neon_tunnel/space_tunnel.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"ssp_void", "VOID",
		"res://assets/worlds/void/void.tscn", "Chedski",
		"res://assets/worlds/void/void.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"ssp_rainbow_road", "Rainbow Road",
		"res://assets/worlds/space/rainbow_road.tscn", "Chedski",
		"res://assets/worlds/space/rainbow_road.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"ssp_classic", "Beyond",
		"res://assets/worlds/classic/classic.tscn", "Chedski",
		"res://assets/worlds/classic/classic.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"ssp_reality_dismissed", "Reality Dismissed",
		"res://assets/worlds/reality_dismissed/reality_dismissed.tscn", "pyrule",
		"res://assets/worlds/custom/custom.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"ssp_reality_dismissed_dark", "Reality Dismissed (Dark)",
		"res://assets/worlds/reality_dismissed/reality_dismissed_dark.tscn", "pyrule",
		"res://assets/worlds/custom/custom.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"ssp_vaporwave", "v a p o r w a v e",
		"res://assets/worlds/vaporwave/vaporwave.tscn", "balt",
		"res://assets/worlds/vaporwave/vaporwave.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"ssp_grid", "The Grid",
		"res://assets/worlds/grid/grid.tscn", "hi",
		"res://assets/worlds/custom/custom.png"
	))













	registry_world.add_item(BackgroundWorld.new(
		"ssp_custombg", "Custom Background",
		"res://assets/worlds/custom/custombg.tscn", "Someone",
		"res://assets/worlds/custom/custom.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"ssp_custom", "Modworld",
		"res://assets/worlds/custom/custom.tscn", "Someone",
		"res://assets/worlds/custom/custom.png"
	))

func _probe_audio_base(base: String) -> String:
	var file := File.new()
	var p := Globals.p(base)
	if file.file_exists(p + ".ogg") or file.file_exists(p + ".mp3") or file.file_exists(p + ".wav"):
		return base
	return ""

func _find_audio_ext(base: String) -> String:
	var file := File.new()
	var p := Globals.p(base)
	if file.file_exists(p + ".ogg"): return "ogg"
	if file.file_exists(p + ".mp3"): return "mp3"
	if file.file_exists(p + ".wav"): return "wav"
	return ""

func _sound_registry(kind: String) -> Registry:
	return registry_hit_sound if kind == "hit" else registry_miss_sound

func _sound_dir(kind: String) -> String:
	return "user://hitsounds" if kind == "hit" else "user://misssounds"

func _sound_folder(kind: String, slug: String) -> String:
	return _sound_dir(kind).plus_file(slug)

func _save_sound_meta(kind: String, slug: String, snd_name: String):
	var file := File.new()
	if file.open(Globals.p(_sound_folder(kind, slug).plus_file("meta.json")), File.WRITE) == OK:
		file.store_string(JSON.print({"name": snd_name}))
		file.close()

func _slugify_name(s: String) -> String:
	var out := ""
	var lower: String = s.to_lower()
	for i in range(lower.length()):
		var c = lower[i]
		if "0123456789abcdefghijklmnopqrstuvwxyz".find(c) != -1:
			out += c
		elif out != "" and out[out.length() - 1] != "_":
			out += "_"
	out = out.trim_suffix("_")
	if out == "":
		out = "sound"
	return out

func _unique_sound_slug(kind: String, base: String) -> String:
	var slug := base
	var n := 2
	var reg := _sound_registry(kind)
	while reg.idx_id.has(slug):
		slug = "%s_%d" % [base, n]
		n += 1
	return slug

func _remove_dir_recursive_p(path: String):
	var dir := Directory.new()
	if dir.open(path) != OK:
		return
	dir.list_dir_begin(true, true)
	var f := dir.get_next()
	while f != "":
		var full := path.plus_file(f)
		if dir.current_is_dir():
			_remove_dir_recursive_p(full)
		else:
			dir.remove(full)
		f = dir.get_next()
	dir.list_dir_end()
	dir.remove(path)

func _migrate_legacy_soundsets(kind: String):
	var legacy_dir := "user://soundsets"
	var dir := Directory.new()
	if not dir.dir_exists(Globals.p(legacy_dir)):
		return
	dir.open(Globals.p(legacy_dir))
	dir.list_dir_begin(true, true)
	var slug := dir.get_next()
	while slug != "":
		if dir.current_is_dir():
			_migrate_legacy_slug(kind, legacy_dir.plus_file(slug), slug)
		slug = dir.get_next()
	dir.list_dir_end()

func _migrate_legacy_slug(kind: String, legacy_folder: String, slug: String):
	var dest_folder := _sound_folder(kind, slug)
	if Directory.new().dir_exists(Globals.p(dest_folder)):
		return
	var legacy_base := legacy_folder.plus_file("hit" if kind == "hit" else "miss")
	var ext := _find_audio_ext(legacy_base)
	if ext == "":
		return
	var snd_name := slug
	var meta_path := legacy_folder.plus_file("meta.json")
	var file := File.new()
	if file.file_exists(Globals.p(meta_path)):
		file.open(Globals.p(meta_path), File.READ)
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
			snd_name = String(parsed.result.get("name", slug))
	var dir := Directory.new()
	dir.make_dir_recursive(Globals.p(dest_folder))
	dir.copy(Globals.p(legacy_base + "." + ext), Globals.p(dest_folder.plus_file("sound." + ext)))
	_save_sound_meta(kind, slug, snd_name)

func register_named_sounds(kind: String):
	var reg := _sound_registry(kind)
	reg.add_item(NamedSound.new("default", "Default", ""))
	var folder := _sound_dir(kind)
	var dir := Directory.new()
	if not dir.dir_exists(Globals.p(folder)):
		dir.make_dir_recursive(Globals.p(folder))
	_migrate_legacy_soundsets(kind)
	if dir.open(Globals.p(folder)) == OK:
		dir.list_dir_begin(true, true)
		var f := dir.get_next()
		while f != "":
			if dir.current_is_dir():
				_load_named_sound_folder(kind, f)
			f = dir.get_next()
		dir.list_dir_end()

func _load_named_sound_folder(kind: String, slug: String):
	var folder := _sound_folder(kind, slug)
	var snd_name := slug
	var meta_path := folder.plus_file("meta.json")
	var file := File.new()
	if file.file_exists(Globals.p(meta_path)):
		file.open(Globals.p(meta_path), File.READ)
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
			snd_name = String(parsed.result.get("name", slug))
	var path := _probe_audio_base(folder.plus_file("sound"))
	if path == "":
		return
	_sound_registry(kind).add_item(NamedSound.new(slug, snd_name, "You", path))

const BORDER_DIR := "user://borders"

func register_borders():
	registry_border.add_item(Border.new("default", "Default", ""))
	var dir := Directory.new()
	if not dir.dir_exists(Globals.p(BORDER_DIR)):
		dir.make_dir_recursive(Globals.p(BORDER_DIR))
	if dir.open(Globals.p(BORDER_DIR)) == OK:
		dir.list_dir_begin(true, true)
		var f := dir.get_next()
		while f != "":
			if dir.current_is_dir():
				_load_border_folder(f)
			f = dir.get_next()
		dir.list_dir_end()

func _load_border_folder(slug: String):
	var folder := BORDER_DIR.plus_file(slug)
	var border_name := slug
	var meta_path := folder.plus_file("meta.json")
	var file := File.new()
	if file.file_exists(Globals.p(meta_path)):
		file.open(Globals.p(meta_path), File.READ)
		var parsed = JSON.parse(file.get_as_text())
		file.close()
		if parsed.error == OK and typeof(parsed.result) == TYPE_DICTIONARY:
			border_name = String(parsed.result.get("name", slug))
	if Globals.imageLoader.load_if_exists(folder.plus_file("border")) == null:
		return
	registry_border.add_item(Border.new(slug, border_name, "You", folder.plus_file("border")))

func _unique_border_slug(base: String) -> String:
	var slug := base
	var n := 2
	while registry_border.idx_id.has(slug):
		slug = "%s_%d" % [base, n]
		n += 1
	return slug

func _save_border_meta(slug: String, border_name: String):
	var file := File.new()
	if file.open(Globals.p(BORDER_DIR.plus_file(slug).plus_file("meta.json")), File.WRITE) == OK:
		file.store_string(JSON.print({"name": border_name}))
		file.close()

func create_border_from_file(border_name: String, src_path: String) -> Border:
	if src_path == "":
		return null
	var slug := _unique_border_slug(_slugify_name(border_name))
	var folder := BORDER_DIR.plus_file(slug)
	var dir := Directory.new()
	dir.make_dir_recursive(Globals.p(folder))
	var path := ""
	if dir.copy(src_path, Globals.p(folder.plus_file("border.%s" % src_path.get_extension().to_lower()))) == OK:
		path = folder.plus_file("border")
	if path == "":
		return null
	_save_border_meta(slug, border_name)
	var b := Border.new(slug, border_name, "You", path)
	registry_border.add_item(b)
	emit_signal("borders_changed")
	return b

func get_selected_border_texture() -> Texture:
	if selected_border == null or selected_border.path == "":
		return null
	return Globals.imageLoader.load_if_exists(selected_border.path)

func create_named_sound_from_file(kind: String, snd_name: String, src_path: String) -> NamedSound:
	if src_path == "":
		return null
	var slug := _unique_sound_slug(kind, _slugify_name(snd_name))
	var folder := _sound_folder(kind, slug)
	var dir := Directory.new()
	dir.make_dir_recursive(Globals.p(folder))
	var path := ""
	if dir.copy(src_path, Globals.p(folder.plus_file("sound.%s" % src_path.get_extension().to_lower()))) == OK:
		path = folder.plus_file("sound")
	if path == "":
		return null
	_save_sound_meta(kind, slug, snd_name)
	var snd := NamedSound.new(slug, snd_name, "You", path)
	_sound_registry(kind).add_item(snd)
	emit_signal("hit_sounds_changed" if kind == "hit" else "miss_sounds_changed")
	return snd

func rename_named_sound(kind: String, snd: NamedSound, new_name: String):
	if snd == null or snd.id == "default":
		return
	snd.name = new_name
	_save_sound_meta(kind, snd.id, new_name)
	emit_signal("hit_sounds_changed" if kind == "hit" else "miss_sounds_changed")

func delete_named_sound(kind: String, snd: NamedSound):
	if snd == null or snd.id == "default":
		return
	var reg := _sound_registry(kind)
	var was_selected := (selected_hit_sound == snd) if kind == "hit" else (selected_miss_sound == snd)
	reg.check_and_remove_id(snd.id)
	_remove_dir_recursive_p(Globals.p(_sound_folder(kind, snd.id)))
	if was_selected:
		if kind == "hit": select_hit_sound(reg.get_item("default"))
		else: select_miss_sound(reg.get_item("default"))
	emit_signal("hit_sounds_changed" if kind == "hit" else "miss_sounds_changed")

func refresh_active_sound_streams():
	var hit_path := "user://hit"
	var miss_path := "user://miss"
	if selected_hit_sound and selected_hit_sound.path != "":
		hit_path = selected_hit_sound.path
	if selected_miss_sound and selected_miss_sound.path != "":
		miss_path = selected_miss_sound.path
	hit_snd = get_stream_with_default(hit_path, def_hit_snd)
	miss_snd = get_stream_with_default(miss_path, def_miss_snd)
	Globals.error_sound = miss_snd

func register_meshes():
	registry_mesh.add_item(NoteMesh.new(
		"ssp_rounded", "Rounded",
		"res://assets/blocks/rounded.obj", "Chedski"
	))
	registry_mesh.add_item(NoteMesh.new(
		"ssp_square", "Square",
		"res://assets/blocks/default.obj", "Chedski"
	))
	registry_mesh.add_item(NoteMesh.new(
		"ssp_circle", "Circle",
		"res://assets/blocks/circle.obj", "Chedski"
	))
	registry_mesh.add_item(NoteMesh.new(
		"ssp_block", "Block",
		"res://assets/blocks/cube.obj", "Chedski"
	))
	registry_mesh.add_item(NoteMesh.new(
		"ssp_plane", "Front of Block",
		"res://assets/blocks/plane.obj", "Chedski"
	))
	registry_mesh.add_item(NoteMesh.new(
		"ssp_realplane", "Plane",
		"res://assets/blocks/quad.tres", "Chedski"
	))
	var dir = Directory.new()
	if dir.open(user_mesh_dir) == OK:
		dir.list_dir_begin(true, false)
		var mesh_name: String = dir.get_next()
		while mesh_name != "":
			if not dir.current_is_dir() and mesh_name.get_extension() == "obj":
				registry_mesh.add_item(NoteMesh.new(
					"ugc_" + mesh_name.get_file().to_lower().replace(" ", "_"),
					mesh_name.get_basename() + " (custom)",
					user_mesh_dir.plus_file(mesh_name), "???"
				))
			mesh_name = dir.get_next()
func register_effects():
	registry_effect.add_item(NoteEffect.new(
		"ssp_shards", "Shards (note color)", "res://assets/notefx/shards/shards.tscn", "Chedski"
	))
	registry_effect.add_item(NoteEffect.new(
		"ssp_shards_r", "Shards (rainbow)", "res://assets/notefx/shards/shards.tscn", "Chedski"
	))
	registry_effect.add_item(NoteEffect.new(
		"ssp_shards_w", "Shards (no color)", "res://assets/notefx/shards/shards.tscn", "Chedski"
	))

	registry_effect.add_item(NoteEffect.new(
		"ssp_miss", "Miss* (red)", "res://assets/notefx/miss/miss.tscn", "Chedski"
	))
	registry_effect.add_item(NoteEffect.new(
		"ssp_miss_n", "Miss* (note color)", "res://assets/notefx/miss/miss.tscn", "Chedski"
	))
	registry_effect.add_item(NoteEffect.new(
		"ssp_miss_r", "Miss* (rainbow)", "res://assets/notefx/miss/miss.tscn", "Chedski"
	))
	registry_effect.add_item(NoteEffect.new(
		"ssp_miss_w", "Miss* (no color)", "res://assets/notefx/miss/miss.tscn", "Chedski"
	))


signal colors_done
func load_color_txt(path: String = "", id: String = ""):
	if path == "" and id == "":
		yield(get_tree(), "idle_frame")
		load_color_folder()
		return

	var regex: RegEx = RegEx.new()
	regex.compile("#?([a-zA-Z\\d]{2})([a-zA-Z\\d]{2})([a-zA-Z\\d]{2})([a-zA-Z\\d]{2})?")

	var cfname: String = "colors.txt (1 per line)"
	if id != "colorsfile":
		cfname = path.get_file().get_basename()
	var cf: ColorSet

	if registry_colorset.idx_id.has(id):
		cf = registry_colorset.get_item(id)
	else:
		cf = ColorSet.new([], id, cfname, " ")
		registry_colorset.add_item(cf)

	var file: File = File.new()
	if file.file_exists(Globals.p(path)):
		var err: int = file.open(Globals.p(path), File.READ)
		if err == OK:
			var ctxt: String = file.get_as_text()
			file.close()
			var split: Array = ctxt.split("\n", false)
			var colarr: Array = []
			var mirror = false
			for st in split:
				if st.strip_edges().is_valid_html_color():
					colarr.append(Color(st.strip_edges()))
				elif st.to_lower() == "m":
					mirror = true
			cf.mirror = mirror

			if colarr.size() == 0:
				print("no valid colors found")
				colarr = [Color("#ffffff")]

			cf.colors = colarr
			return
		else: print("couldnt open %s because error %s" % [path, err])
	else: print("no colors.txt")
	cf.colors = [Color("#ffffff")]
func load_color_folder():
	var a = OS.get_ticks_usec()
	print("(re)load custom colorsets")

	var dir: Directory = Directory.new()
	if dir.dir_exists(user_colorset_dir):
		var files = Globals.get_files_recursive([user_colorset_dir], 5)
		var i = 0
		for n in files.files:
			var b = OS.get_ticks_usec()
			load_color_txt(n, "custom_" + n.get_file().to_lower().md5_text())
			i += 1
			if fmod(i, 4) == 0: yield(get_tree(), "idle_frame")
			n = dir.get_next()
			print("set %s took %s usec" % [i, Globals.comma_sep(OS.get_ticks_usec() - b)])
	print("colorsets took %s usec" % [Globals.comma_sep(OS.get_ticks_usec() - a)])
	emit_signal("colors_done")

var single_map_mode: bool = false
var single_map_mode_sspm: bool = false
var single_map_mode_txt: bool = false
var single_map_mode_path: String
var single_map_mode_audio_path: String

var _map_registry_thread: Thread = null

func populate_map_registry_deferred(args: Array):
	var mapreg: Array = args[0]
	var convert_pb_format: bool = args[1]
	var file: File = File.new()
	var dir: Directory = Directory.new()
	var err: int

	if not dir.dir_exists(Globals.p("user://caches")):
		dir.make_dir_recursive(Globals.p("user://caches"))
	var real_user_dir = OS.get_user_data_dir()
	var legacy_cache_path = real_user_dir.plus_file("map_cache.json")
	var migrated_cache_path = real_user_dir.plus_file("caches").plus_file("map_cache.json")
	if dir.file_exists(legacy_cache_path) and not dir.file_exists(migrated_cache_path):
		dir.rename(legacy_cache_path, migrated_cache_path)

	call_deferred("emit_signal", "init_stage_reached", "Register content 1/4\nImport Rhythia maps\nLocating files")
	dir.change_dir(user_map_dir)

	var cache_version: int = 2
	var caches: Dictionary = {}
	err = file.open(Globals.p(CACHE_FILE_PATH), File.READ)
	if err == OK:
		var res = JSON.parse(file.get_as_text())
		if (res.error != OK):
			print("Error reading cache: %s" % res.error_string)
		elif typeof(res.result) == TYPE_DICTIONARY:
			caches = res.result
			if caches.get("_v", 1) != cache_version:
				caches = {}
				print("Cache version mismatch (got %s expected %s)" % [caches.get("_v", 1), cache_version])
		else:
			print("Invalid cache")

	var map_search_folders = [user_map_dir]
	err = file.open(Globals.p("user://map_folders.txt"), File.READ)
	if err == OK:
		var txt = file.get_as_text()
		var list = txt.split("\n", false)
		map_search_folders.append_array(list)

	var smaps: Array = Globals.get_files_recursive(map_search_folders, 5, "sspm", "", -1).files

	var load_start = OS.get_ticks_usec()
	var from_file = 0
	var from_cache = 0
	var debug_map_load_times = OS.has_feature("debug")

	call_deferred("emit_signal", "init_stage_reached", "Register content 1/5\nImport Rhythia maps\n0 / %s" % smaps.size())
	var progress_last_emit_usec = OS.get_ticks_usec()

	for i in range(smaps.size()):
		var map_load_start_usec = OS.get_ticks_usec() if debug_map_load_times else 0

		if caches.has(smaps[i]):
			if registry_song.add_sspm_cached_map(smaps[i], caches.get(smaps[i])):
				from_cache += 1
			else:
				print("Failed loading a map from cache: ", smaps[i])
				from_file += 1
				registry_song.add_sspm_map(smaps[i])
		else:
			from_file += 1
			registry_song.add_sspm_map(smaps[i])

		if debug_map_load_times:
			var map_load_ms = (OS.get_ticks_usec() - map_load_start_usec) / 1000.0
			if map_load_ms > 5.0:
				pass


		if OS.get_ticks_usec() - progress_last_emit_usec > 80000:
			progress_last_emit_usec = OS.get_ticks_usec()
			call_deferred("emit_signal", "init_stage_reached", "Register content 1/5\nImport Rhythia maps\n%d / %s" % [i + 1, smaps.size()])

	var load_end = OS.get_ticks_usec()
	var load_time = load_end - load_start
	print("Loaded %s/%s maps from cache of %s" % [from_cache, from_cache + from_file, caches.size()])
	print("Took %s usec" % Globals.comma_sep(load_time))

	call_deferred("emit_signal", "init_stage_reached", "Register content 2/5\nCache Rhythia maps")
	err = file.open(Globals.p(CACHE_FILE_PATH), File.WRITE)
	if err == OK:
		file.store_string(JSON.print(registry_song.make_sspm_cache(cache_version)))
		file.flush()

	call_deferred("emit_signal", "local_maps_loaded")

	for i in range(mapreg.size()):
		var amr: Array = mapreg[i]
		call_deferred("emit_signal", "init_stage_reached", "Register content 3/5\nLoad map registry %d/%d\n%s" % [i, mapreg.size(), amr[0]])
		registry_song.load_registry_file(amr[1], Globals.REGISTRY_MAP, amr[0])

	var vmap_search_folders = [user_vmap_dir]
	err = file.open(Globals.p("user://vmap_folders.txt"), File.READ)
	if err == OK:
		var txt = file.get_as_text()
		var list = txt.split("\n", false)
		vmap_search_folders.append_array(list)

	call_deferred("emit_signal", "init_stage_reached", "Register content 4/5\nImport Vulnus maps\nLocating files")

	var vmaps: Array = Globals.get_files_recursive(vmap_search_folders, 6, "", "meta.json", -1).folders

	for i in range(vmaps.size()):
		registry_song.add_vulnus_map(vmaps[i])

	call_deferred("emit_signal", "init_stage_reached", "Register content 5/5\nLoad online maps")
	if last_search_incl_online:
		_online_maps_fetched = true
		Online.load_db_maps()

	if convert_pb_format:
		hitwindow_ms = 55
		note_hitbox_size = 1.14

		call_deferred("emit_signal", "init_stage_reached", "Upgrading personal best data\nReading legacy data")
		load_pbs()

		var allmaps: Array = registry_song.get_items()

		call_deferred("emit_signal", "init_stage_reached", "Upgrading personal best data\nConverting data\n0%")
		for i in range(allmaps.size()):
			convert_song_pbs(allmaps[i])

	call_deferred("emit_signal", "local_maps_loaded")


func do_init(_ud = null):
	set_client_id()
	load_keybinds()
	load_profile()
	check_discord_link()
	check_player_xp()
	installed_packs = []
	yield(get_tree().create_timer(0.05), "timeout")
	fetch_banned_list()
	var lp: bool = false
	var file: File = File.new()
	var dir: Directory = Directory.new()

	emit_signal("init_stage_reached", "Check arguments")
	yield(get_tree(), "idle_frame")

	if Globals.cmdline.has("m"): Globals.cmdline.map = Globals.cmdline.m
	if Globals.cmdline.has("t"): Globals.cmdline.txt = Globals.cmdline.t
	if Globals.cmdline.has("a"): Globals.cmdline.audio = Globals.cmdline.a

	if Globals.cmdline.has("map"):
		if Globals.cmdline.has("txt"):
			errorstr = "--txt cannot be used with --map"
			get_tree().change_scene("res://scenes/errors/cmdline.tscn")
			return
		elif Globals.cmdline.has("audio"):
			errorstr = "--audio cannot be used with --map"
			get_tree().change_scene("res://scenes/errors/cmdline.tscn")
			return
		elif Globals.cmdline.map == "" or Globals.cmdline.map.is_valid_filename():
			errorstr = "--map must be a valid path (ie. --map=~/Desktop/map.sspm)"
			get_tree().change_scene("res://scenes/errors/cmdline.tscn")
			return
		else:
			single_map_mode = true
			single_map_mode_sspm = true
			single_map_mode_path = Globals.cmdline.map
			if not file.file_exists(single_map_mode_path):
				errorstr = "--map: file '%s' does not exist" % single_map_mode_path
				get_tree().change_scene("res://scenes/errors/cmdline.tscn")
				return

	elif Globals.cmdline.has("txt") or Globals.cmdline.has("audio"):
		if not (Globals.cmdline.has("txt") and Globals.cmdline.has("audio")):
			if Globals.cmdline.has("txt"):
				errorstr = "--txt must be used with --audio"
			else:
				errorstr = "--audio must be used with --txt"
			get_tree().change_scene("res://scenes/errors/cmdline.tscn")
			return
		elif Globals.cmdline.txt == "" or Globals.cmdline.txt.is_valid_filename():
			errorstr = "--txt must be a valid path (ie. --txt=~/Desktop/map.txt)"
			get_tree().change_scene("res://scenes/errors/cmdline.tscn")
			return
		elif Globals.cmdline.audio == "" or Globals.cmdline.txt.is_valid_filename():
			errorstr = "--audio must be a valid path (ie. --txt=~/Desktop/audio.txt)"
			get_tree().change_scene("res://scenes/errors/cmdline.tscn")
			return
		else:
			single_map_mode = true
			single_map_mode_txt = true
			single_map_mode_path = Globals.cmdline.txt
			single_map_mode_audio_path = Globals.cmdline.audio


	if OS.has_feature("Windows"):
		emit_signal("init_stage_reached", "Check for updates")
		emit_signal("init_stage_num", -1)
		yield(get_tree(), "idle_frame")
		Online.check_latest_version()
		var latest_version = yield(Online, "latest_version")
		if ProjectSettings.get_setting("application/config/version") != latest_version:
			var sel = 1
			if not Online.latest_version_data.body.begins_with("-a"):

				Globals.confirm_prompt.open("loud sound = gone\nYou are on an outdated version of the game! Would you like to automatically update?", "Outdated", [{text = "Ignore", wait = 0}, {text = "Update", wait = 1}])
				sel = yield(Globals.confirm_prompt, "option_selected")

				Globals.confirm_prompt.close()
				yield(Globals.confirm_prompt, "done_closing")
			if bool(sel):
				emit_signal("init_stage_reached", "Updating the game")
				Online.attempt_update()
				yield(Online, "update_finished")
				get_tree().call_deferred("quit", 1)
				OS.execute(OS.get_executable_path(), [], false)
				return
		var rdir = Directory.new()
		rdir.open(OS.get_executable_path().get_base_dir())
		if rdir.file_exists("Savia.pck.old"):
			rdir.remove("Savia.pck.old")


	emit_signal("init_stage_reached", "Init filesystem")
	emit_signal("init_stage_num", -1)
	yield(get_tree(), "idle_frame")
	if OS.has_feature("Android"): OS.request_permissions()
	var user_dir = Globals.p("user://")
	if user_dir == "RETRY":
		yield(get_tree().create_timer(7), "timeout")
		user_dir = Globals.p("user://")
	var err: int = dir.open(user_dir)


	if Input.is_key_pressed(KEY_CONTROL) and Input.is_key_pressed(KEY_U):
		err = -1

	if err != OK:
		Globals.errornum = err
		get_tree().change_scene("res://scenes/errors/userfolder.tscn")
		return


	var convert_pb_format: bool = false
	if not first_init_done:
		if not dir.dir_exists(user_mod_dir): dir.make_dir(user_mod_dir)
		if not dir.dir_exists(user_pack_dir): dir.make_dir(user_pack_dir)
		if not dir.dir_exists(user_vmap_dir): dir.make_dir(user_vmap_dir)
		if not dir.dir_exists(user_map_dir): dir.make_dir(user_map_dir)
		if not dir.dir_exists(user_colorset_dir): dir.make_dir(user_colorset_dir)
		if not dir.dir_exists(user_friend_dir): dir.make_dir(user_friend_dir)
		if not dir.dir_exists(user_mesh_dir): dir.make_dir(user_mesh_dir)
		if not dir.file_exists(user_mesh_dir.plus_file("readme.txt")):
			file.open(user_mesh_dir.plus_file("readme.txt"), File.WRITE)
			file.store_line("The second material is transparent, everything else is opaque.")
			file.store_line("The default blender cube is about the right size for a mesh.")
			file.store_line("In blender, the mesh should face towards the positive Y direction.")
			file.close()
		if not dir.dir_exists(Globals.p("user://replays")): dir.make_dir(Globals.p("user://replays"))
		if not dir.dir_exists(user_best_dir):
			convert_pb_format = true
			dir.make_dir(user_best_dir)
		err = file.open(Globals.p("user://install_path.txt"), File.WRITE)
		if err == OK:
			file.store_string(OS.get_executable_path())
		if not dir.dir_exists(user_profiles_dir): dir.make_dir(user_profiles_dir)


	emit_signal("init_stage_reached", "Init registries")
	if lp: yield(get_tree(), "idle_frame")
	registry_colorset = Registry.new()
	registry_song = Registry.new()
	registry_world = Registry.new()
	registry_mesh = Registry.new()
	registry_effect = Registry.new()
	registry_hit_sound = Registry.new()
	registry_miss_sound = Registry.new()
	registry_border = Registry.new()

	Online.map_registry = registry_song

	register_colorsets()
	register_effects()
	register_meshes()
	register_worlds()
	register_named_sounds("hit")
	register_named_sounds("miss")
	register_borders()


	emit_signal("init_stage_reached", "Load user colorsets")
	emit_signal("init_stage_num", 0)
	load_color_txt()
	yield(self, "colors_done")


	var mapreg: Array = []
	emit_signal("init_stage_reached", "Loading content 1/3\nBuilt-in & DLC")
	yield(get_tree(), "idle_frame")
	if first_init_done:
		mapreg.append(["built-in", "res://assets/songs/built_in_maps.sspmr"])
		if installed_dlc.has("ssp_testcontent"): mapreg.append(["test maps", "res://test_assets/test_maps.sspmr"])
	else:
		print("loaded ssp_content DLC")
		mapreg.append(["built-in", "res://assets/songs/built_in_maps.sspmr"])
		installed_dlc.append("ssp_content")
		if OS.has_feature("editor") or ProjectSettings.load_resource_pack("res://testcontent.pck"):
			print("loaded ssp_testcontent DLC")
			mapreg.append(["test maps", "res://test_assets/test_maps.sspmr"])
			installed_dlc.append("ssp_testcontent")

	var n
	if not first_init_done:
		if not OS.has_feature("debug"):
			emit_signal("init_stage_reached", "Loading content 2/3\nMods")
			yield(get_tree(), "idle_frame")
			dir.change_dir(user_mod_dir)
			dir.list_dir_begin(true)
			n = dir.get_next()
			while n:
				if ProjectSettings.load_resource_pack(user_mod_dir + "/" + n):
					installed_mods.append(n.get_file().replace(n.get_extension(), ""))
				n = dir.get_next()
			dir.list_dir_end()
		else:
			Globals.notify(
				Globals.NOTIFY_INFO,
				"This is a development environment, mods will not be loaded.",
				"Not loading mods"
			)
	emit_signal("init_stage_num", 1)

	emit_signal("init_stage_reached", "Loading content 3/3\nContent packs")
	yield(get_tree(), "idle_frame")
	dir.change_dir(user_pack_dir)
	dir.list_dir_begin(true)
	n = dir.get_next()
	while n:
		installed_packs.append([n.get_file(), user_pack_dir + "/" + n])
		if dir.file_exists(n + "/pack.sspmr"): mapreg.append([n.get_file(), user_pack_dir + "/" + n + "/pack.sspmr"])
		n = dir.get_next()
	dir.list_dir_end()

	emit_signal("init_stage_reached", "Register content")
	yield(get_tree(), "idle_frame")
	var lt: float = OS.get_ticks_msec()

	if single_map_mode:
		emit_signal("init_stage_num", 2)
		var song: Song = Song.new()
		if single_map_mode_sspm:
			var result = song.load_from_sspm(single_map_mode_path)
			if result != song:
				errorstr = "song load failed with message '%s'" % result
				get_tree().change_scene("res://scenes/errors/cmdline.tscn")
				return
		elif single_map_mode_txt:
			song.id = "__smm"
			song.name = single_map_mode_path.get_file()
			song.song = single_map_mode_audio_path.get_file()
			var result = song.setup_from_file(single_map_mode_path, single_map_mode_audio_path)
			if result != song:
				errorstr = "song load failed with message '%s'" % result
				get_tree().change_scene("res://scenes/errors/cmdline.tscn")
				return
		Rhythia.selected_song = song
	else:
		var cache_version: int = 2
		var caches: Dictionary = {}
		var cache_read_start = OS.get_ticks_usec()
		err = file.open(Globals.p("user://map_cache.json"), File.READ)
		if err == OK:
			var cache_text = file.get_as_text()
			var cache_read_end = OS.get_ticks_usec()
			print("Cache file read took %s usec (%s bytes)" % [Globals.comma_sep(cache_read_end - cache_read_start), cache_text.length()])
			var res = JSON.parse(cache_text)
			print("Cache JSON.parse took %s usec" % Globals.comma_sep(OS.get_ticks_usec() - cache_read_end))
			if (res.error != OK):
				print("Error reading cache: %s" % res.error_string)
			elif typeof(res.result) == TYPE_DICTIONARY:
				caches = res.result
				if caches.get("_v", 1) != cache_version:
					caches = {}
					print("Cache version mismatch (got %s expected %s)" % [caches.get("_v", 1), cache_version])
			else:
				print("Invalid cache")

		var smaps: Array = []
		emit_signal("init_stage_reached", "Register content 1/4\nImport Rhythia maps\nLocating files")
		yield(get_tree(), "idle_frame")
		var sd: Array = []
		dir.change_dir(user_map_dir)
		var li = 0

		var map_search_folders = [user_map_dir]
		err = file.open(Globals.p("user://map_folders.txt"), File.READ)
		if err == OK:
			var txt = file.get_as_text()
			var list = txt.split("\n", false)
			map_search_folders.append_array(list)

		var scan_start = OS.get_ticks_usec()
		Globals.get_files_recursive(map_search_folders, 5, "sspm", "", 90)
		smaps = yield(Globals, "recurse_result").files
		print("Locating files took %s usec (%s files)" % [Globals.comma_sep(OS.get_ticks_usec() - scan_start), smaps.size()])
		emit_signal("init_stage_num", 2)

		var load_start = OS.get_ticks_usec()
		var from_file = 0
		var from_cache = 0
		for i in range(smaps.size()):
			if (OS.get_ticks_msec() - lt) >= load_target_frame_time * 1000:
				lt = OS.get_ticks_msec()
				emit_signal("init_stage_reached", "Register content 1/5\nImport Rhythia maps\n%d / %s" % [i + 1, smaps.size()])
				yield(get_tree(), "idle_frame")

			var single_map_start = OS.get_ticks_usec()
			if caches.has(smaps[i]):
				if registry_song.add_sspm_cached_map(smaps[i], caches.get(smaps[i])):
					from_cache += 1
				else:
					print("Failed loading a map from cache")
					from_file += 1
					registry_song.add_sspm_map(smaps[i])
			else:
				from_file += 1
				registry_song.add_sspm_map(smaps[i])
			var single_map_usec = OS.get_ticks_usec() - single_map_start
			if single_map_usec > 1000000:
				print("SLOW MAP LOAD (%s usec): %s" % [Globals.comma_sep(single_map_usec), smaps[i]])
		var load_end = OS.get_ticks_usec()
		var load_time = load_end - load_start

		print("Loaded %s/%s maps from cache of %s" % [from_cache, from_cache + from_file, caches.size()])
		print("Took %s usec" % Globals.comma_sep(load_time))


		emit_signal("init_stage_reached", "Register content 2/5\nCache Rhythia maps")
		yield(get_tree(), "idle_frame")
		var cache_write_start = OS.get_ticks_usec()
		var cache_dict = registry_song.make_sspm_cache(cache_version)
		print("Cache dict has %s entries" % cache_dict.size())
		var cache_json = JSON.print(cache_dict)
		print("Cache JSON string length: %s chars" % cache_json.length())
		err = file.open(Globals.p("user://map_cache.json"), File.WRITE)
		if err == OK:
			file.store_string(cache_json)
			print("File length after store_string: %s" % file.get_len())
			file.flush()
			file.close()
		print("Cache write took %s usec" % Globals.comma_sep(OS.get_ticks_usec() - cache_write_start))

		for i in range(mapreg.size()):
			var amr: Array = mapreg[i]
			emit_signal("init_stage_reached", "Register content 3/5\nLoad map registry\nImport Rhythia maps\n%d/%d\n%s" % [i, mapreg.size(), amr[0]])
			yield(get_tree(), "idle_frame")
			registry_song.load_registry_file(amr[1], Globals.REGISTRY_MAP, amr[0])

		emit_signal("init_stage_num", 3)

		var vmaps: Array = []

		var vmap_search_folders = [user_vmap_dir]
		err = file.open(Globals.p("user://vmap_folders.txt"), File.READ)
		if err == OK:
			var txt = file.get_as_text()
			var list = txt.split("\n", false)
			vmap_search_folders.append_array(list)

		emit_signal("init_stage_reached", "Register content 4/5\nImport Vulnus maps\nLocating files")
		yield(get_tree(), "idle_frame")

		Globals.get_files_recursive(vmap_search_folders, 6, "", "meta.json", 70)
		vmaps = yield(Globals, "recurse_result").folders

		for i in range(vmaps.size()):
			if (OS.get_ticks_msec() - lt) >= load_target_frame_time * 1000:
				lt = OS.get_ticks_msec()
				emit_signal("init_stage_reached", "Register content 4/5\nImport Vulnus maps\n%.0f%%" % (
					100 * (float(i) / float(vmaps.size()))
				))
				yield(get_tree(), "idle_frame")

			registry_song.add_vulnus_map(vmaps[i])


		emit_signal("init_stage_reached", "Register content 5/5\nLoad online maps")
		yield(get_tree(), "idle_frame")

		if last_search_incl_online:
			_online_maps_fetched = true
			Online.load_db_maps()
			yield(Online, "db_maps_done")

	emit_signal("init_stage_num", 4)


	emit_signal("init_stage_reached", "Init default assets")
	yield(get_tree(), "idle_frame")

	emit_signal("init_stage_reached", "Init default assets 1/6")
	if lp: yield(get_tree(), "idle_frame")
	selected_colorset = registry_colorset.get_item("ssp_cottoncandy")
	selected_space = registry_world.get_item("ssp_space_tunnel")
	selected_mesh = registry_mesh.get_item("ssp_rounded")
	selected_hit_sound = registry_hit_sound.get_item("default")
	selected_miss_sound = registry_miss_sound.get_item("default")
	selected_border = registry_border.get_item("default")

	assert(selected_colorset)
	assert(selected_space)
	assert(selected_mesh)

	emit_signal("init_stage_reached", "Init default assets 2/6")
	if lp: yield(get_tree(), "idle_frame")
	def_miss_snd = load("res://assets/sfx/miss.wav")

	emit_signal("init_stage_reached", "Init default assets 3/6")
	if lp: yield(get_tree(), "idle_frame")
	def_hit_snd = load("res://assets/sfx/hit.wav")

	emit_signal("init_stage_reached", "Init default assets 4/6")
	if lp: yield(get_tree(), "idle_frame")
	def_fail_snd = load("res://assets/sfx/fail.wav")

	emit_signal("init_stage_reached", "Init default assets 5/6")
	if lp: yield(get_tree(), "idle_frame")
	def_pb_snd = load("res://assets/sfx/new_best.wav")
	normal_pb_sound = def_pb_snd

	emit_signal("init_stage_reached", "Init default assets 6/6")
	if lp: yield(get_tree(), "idle_frame")
	def_menu_bgm = load("res://assets/sfx/music/menu_loop.ogg")

	emit_signal("init_stage_reached", "Check Banned")
	yield(get_tree(), "idle_frame")
	print(cid)
	if is_client_banned(cid):
		get_tree().change_scene("res://scenes/errors/banned.tscn")
		return
	check_live_ban()
	start_live_ban_poll()

	emit_signal("init_stage_reached", "Read user settings")
	yield(get_tree(), "idle_frame")
	var result = load_saved_settings()
	if result != 0:
		errornum = result

		get_tree().change_scene("res://scenes/errors/settings.tscn")
		return


	if not hlm_converted:
		parallax *= (0.35 / 0.25)
		ui_parallax *= (0.35 / 0.25)
		grid_parallax *= (0.35 / 0.25)
		hlm_converted = true
		save_settings()


	emit_signal("init_stage_reached", "Load custom assets")
	yield(get_tree(), "idle_frame")

	emit_signal("init_stage_reached", "Load asset replacement 1/5\nmiss")
	if lp: yield(get_tree(), "idle_frame")
	emit_signal("init_stage_reached", "Load asset replacement 2/5\nhit")
	if lp: yield(get_tree(), "idle_frame")
	refresh_active_sound_streams()

	emit_signal("init_stage_reached", "Load asset replacement 3/5\nfail")
	if lp: yield(get_tree(), "idle_frame")
	fail_snd = get_stream_with_default("user://fail", def_fail_snd)

	emit_signal("init_stage_reached", "Load asset replacement 4/5\nnew_best")
	if lp: yield(get_tree(), "idle_frame")
	pb_snd = get_stream_with_default("user://new_best", def_pb_snd)

	emit_signal("init_stage_reached", "Load asset replacement 5/5\nmenu")
	if lp: yield(get_tree(), "idle_frame")
	menu_bgm = get_stream_with_default("user://menu", def_menu_bgm)

	fail_asp.stream = fail_snd
	Globals.error_sound = miss_snd


	if not first_init_done:

		emit_signal("init_stage_reached", "Read favorite songs")
		yield(get_tree(), "idle_frame")
		if file.file_exists(Globals.p("user://favorites.txt")):
			file.open(Globals.p("user://favorites.txt"), File.READ)
			var txt = file.get_as_text()
			file.close()
			favorite_songs = txt.split("\n", false)

	dir.change_dir("res://")
	first_init_done = true
	do_archive_convert = false

	var alert_snd_played: bool = false
	if alert != "":
		emit_signal("init_stage_reached", "Alert prompt")
		if not alert_snd_played: Globals.confirm_prompt.s_alert.play()
		alert_snd_played = true
		Globals.confirm_prompt.open(alert, "Alert", [{text = "OK", wait = 2}])
		yield(Globals.confirm_prompt, "option_selected")
		Globals.confirm_prompt.s_next.play()
		Globals.confirm_prompt.close()
		yield(Globals.confirm_prompt, "done_closing")
	if should_ask_about_replays and not OS.has_feature("Android"):
		emit_signal("init_stage_reached", "Setup")
		if not alert_snd_played: Globals.confirm_prompt.s_alert.play()
		alert_snd_played = true
		record_replays = true
		record_limit = 0

		save_settings()
		Globals.confirm_prompt.s_next.play()
		Globals.confirm_prompt.close()
		yield(Globals.confirm_prompt, "done_closing")
	if _map_registry_thread:
		emit_signal("init_stage_reached", "Register content\nFinishing map import")
		_map_registry_thread.wait_to_finish()

	is_init = false
	check_for_update_log()
	emit_signal("init_stage_reached", "Waiting for menu", true)

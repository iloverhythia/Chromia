extends Node

onready var rootg = get_tree().root

# (analytics go through the server, savia.nysr.host/ga-collect: no keys in the game)

const BANNED_LIST_URL = "https://raw.githubusercontent.com/SavvyScripter-GH/SavvyAssets/main/banned_players.json"
var banned_clients: Array = []

var heartbeat_timer: Timer
var cid: String = ""
var dev = "pc"
const MOBILE_UI_SIZE := Vector2(1024, 860)
const MOBILE_MIN_UI_WIDTH := 1500.0

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

	detect_device()

func detect_device():
	if OS.has_feature("quest"):
		dev = "pc" # Meta Quest app: the menus are used with the controller pointer, like a mouse
	elif OS.has_feature("Android") or OS.has_feature("iOS") or is_touch_web():
		dev = "mobile" # phones and tablets: tap controls, pause buttons
	else:
		dev = "pc"
	Rhythia.dev = dev
	if dev == "mobile":
		apply_mobile_layout()
		var touch = load("res://scripts/ui/TouchIndicator.gd").new()
		touch.name = "TouchIndicator"
		call_deferred("add_child", touch)

# Phones: the menus are laid out for a screen tall enough for the song panel
# (800-860 px with all its lines) plus the part the system covers (the iPhone home bar), then
# scaled to the screen. 2D stretch keeps drawing at the screen's full
# resolution, so text and the game stay sharp.
var _mobile_layout_h: float = -1.0
func apply_mobile_layout():
	var h: float = MOBILE_UI_SIZE.y
	var win := OS.get_window_size()
	var safe := OS.get_window_safe_area()
	if win.y > 0 and safe.size.y > 0 and safe.size.y < win.y:
		h = min(h * win.y / safe.size.y, MOBILE_UI_SIZE.y * 1.25)
	# squarer screens (iPads are 4:3): the menus need about a phone's width
	# (1500+ at this height), so make everything a bit smaller instead of
	# cutting their right side off
	if win.x > 0 and win.y > 0:
		h = max(h, MOBILE_MIN_UI_WIDTH * win.y / win.x)
	if abs(h - _mobile_layout_h) < 1.0:
		return
	_mobile_layout_h = h
	get_tree().set_screen_stretch(SceneTree.STRETCH_MODE_2D, SceneTree.STRETCH_ASPECT_EXPAND, Vector2(MOBILE_UI_SIZE.x, h))
	if not get_tree().root.is_connected("size_changed", self, "apply_mobile_layout"):
		# the safe area can be known only once the window is up, and changes when the phone turns
		get_tree().root.connect("size_changed", self, "apply_mobile_layout", [], CONNECT_DEFERRED)

# --- Phones: touch delay and refresh rate ------------------------------------
# No Touch Delay: every finger movement is handled as it comes (not merged per
# frame) and, on iPhone, Godot's 0.15 s hold on each new touch is removed.
# 120 Hz: the game draws at the screen's highest refresh rate (ProMotion).
# The iPhone parts need the native helper (scripts/IosNative.gd) from an
# installed .ipa; mobile_tuning_status says what applied.
var mobile_tuning_status: String = ""

func _set_mobile_no_delay(v: bool):
	mobile_no_delay = v
	if is_inside_tree():
		call_deferred("apply_mobile_tuning")

func _set_mobile_high_hz(v: bool):
	mobile_high_hz = v
	if is_inside_tree():
		call_deferred("apply_mobile_tuning")

var _tuned_once := false
func apply_mobile_tuning():
	if dev != "mobile":
		return
	Input.use_accumulated_input = not mobile_no_delay
	if mobile_high_hz and Engine.target_fps > 0 and Engine.target_fps < 120:
		Engine.target_fps = 0 # an FPS limit under 120 would hold it back
	if not OS.has_feature("iOS"):
		mobile_tuning_status = ""
		return
	# only touch what's on, or what was turned off after being on
	if not mobile_no_delay and not mobile_high_hz and not _tuned_once:
		return
	_tuned_once = true
	var fps := 120 if mobile_high_hz else 60
	var delay := 0.0 if mobile_no_delay else 0.15
	mobile_tuning_status = load("res://scripts/IosNative.gd").tune(fps, delay)
	print("[mobile tuning] ", mobile_tuning_status if mobile_tuning_status != "" else "native helper not in this app")

# Browser on a phone or tablet (touch is the main input).
func is_touch_web() -> bool:
	if not OS.has_feature("JavaScript"):
		return false
	var js = Engine.get_singleton("JavaScript")
	if js == null:
		return false
	return bool(js.eval("!!(window.matchMedia && matchMedia('(pointer: coarse)').matches && navigator.maxTouchPoints > 0)", true))

func device(input):
	return Rhythia.dev == input

func apply_rotated_client_id(new_id: String):
	if new_id == "" or new_id == cid:
		return
	var db = _read_client_db()
	db["client_id"] = new_id
	_write_client_db(db)
	cid = new_id
	Globals.notify(Globals.NOTIFY_WARN, "Your account ID was rotated by an admin. Please restart Chromia.", "Account Updated")

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
		"hard_mode": mod_hard_mode,
		"flashlight": mod_flashlight,
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
	if not show_xp_notifications:
		return
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
	# On Windows this is the registry MachineGuid (Godot reads it directly; the
	# old "reg query" child process got flagged by antivirus).
	var raw := String(OS.get_unique_id()).strip_edges()
	_cached_hwid = raw.sha256_text() if raw != "" else ""
	return _cached_hwid

# Offline RP (see RhythiaPoints.gd). Counts passes played the ranked way:
# same rules as XP, minus the server-only checks.
func award_offline_rp():
	if replaying or selected_song == null or song_end_type != Globals.END_PASS:
		return
	if mod_nofail or mod_extra_energy or start_offset != 0 or song_end_pause_count > 0:
		return
	if replay != null and replay.autoplayer:
		return
	if not (is_equal_approx(hitwindow_ms, 55.0) or is_equal_approx(hitwindow_ms, 58.0)):
		return
	if not is_equal_approx(note_hitbox_size, 1.14) or health_model != Globals.HP_SOUNDSPACE:
		return
	var stars: float = selected_song.get_star_rating()
	if stars <= 0.0:
		return
	var acc: float = float(song_end_hits) / max(float(song_end_total_notes), 1.0)
	var store = preload("res://scripts/RhythiaPoints.gd").get_store()
	var res: Dictionary = store.record(String(selected_song.id), String(selected_song.name), stars, current_speed_multiplier(), acc, song_end_misses)
	if res.best and show_xp_notifications:
		Globals.notify(Globals.NOTIFY_INFO, "%d RP (+%d total)" % [int(round(res.rp)), int(round(res.gained))], "New best RP")

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
		if show_xp_notifications:
			Globals.notify(Globals.NOTIFY_SUCCEED, msg, "Score Submitted")
		if record_replays:
			upload_replay_for_pass(song_id, replay_id_snapshot)
	elif data.has("reason"):
		var reason_text = XP_REJECT_REASONS.get(Globals.s(data.reason), Globals.s(data.reason))
		if show_xp_notifications:
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
# VR: logging in in the headset's browser or on the computer
# (DiscordLoginPanel.gd) takes longer
const DISCORD_LOGIN_TIMEOUT_VR_SEC = 600.0
var _discord_login_timer: Timer = null
var _discord_login_elapsed: float = 0.0
var discord_login_url: String = ""

func _discord_login_timeout() -> float:
	return DISCORD_LOGIN_TIMEOUT_VR_SEC if (vr or OS.has_feature("quest")) else DISCORD_LOGIN_TIMEOUT_SEC

# seconds left to finish logging in (0 if not logging in)
func discord_login_left() -> float:
	if _discord_login_timer == null or _discord_login_timer.is_stopped():
		return 0.0
	return max(0.0, _discord_login_timeout() - _discord_login_elapsed)

func cancel_discord_login():
	if _discord_login_timer != null:
		_discord_login_timer.stop()
	discord_login_error = ""
	emit_signal("discord_login_changed")

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
		"id": Globals.s(du.get("id", "")),
		"username": Globals.s(du.get("username", "")),
		"display_name": Globals.s(du.get("global_name", du.get("display_name", ""))),
		"avatar_url": Globals.s(du.get("avatar_url", "")),
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
		Globals.notify(Globals.NOTIFY_ERROR, "Couldn't reach the server to sign out.", "Sign Out Failed")
		emit_signal("discord_login_changed") # (the buttons wait for this)

func _on_discord_unlink_received(_result, response_code, _headers, _body, http_request: HTTPRequest):
	http_request.queue_free()
	if response_code != 200:
		Globals.notify(Globals.NOTIFY_ERROR, "Couldn't reach the server to sign out of Discord.", "Sign Out Failed")
		emit_signal("discord_login_changed") # (the buttons wait for this)
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
	discord_login_url = String(json_result.result.get("url", ""))
	if vr or OS.has_feature("quest"):
		# in the headset: a panel with the steps (the Quest's browser opens
		# from its button, over the game); PC VR opens the page on the computer
		load("res://scripts/ui/settings/DiscordLoginPanel.gd").show_for(discord_login_url)
		if not OS.has_feature("quest"):
			OS.shell_open(discord_login_url)
	else:
		OS.shell_open(discord_login_url)
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
	if _discord_login_elapsed > _discord_login_timeout():
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
	var status = Globals.s(data.get("status", "pending"))
	if status == "complete" and typeof(data.get("discord_user")) == TYPE_DICTIONARY:
		if _discord_login_timer != null:
			_discord_login_timer.stop()
		_apply_discord_user(data.discord_user)
	elif status == "error":
		if _discord_login_timer != null:
			_discord_login_timer.stop()
		discord_login_error = Globals.s(data.get("error", "Discord login failed."))
		emit_signal("discord_login_changed")

func _on_heartbeat_timeout(cid: String):
	send_analytics_event("session_heartbeat", {}, cid)

func fetch_banned_list():
	var http_request = HTTPRequest.new()
	add_child(http_request)

	http_request.connect("request_completed", self, "_on_request_completed", [http_request])

	var error = http_request.request(BANNED_LIST_URL)
	if error != OK:
		print("An error occurred while initiating the HTTP request.")

func _on_request_completed(result, response_code, headers, body, http_request: HTTPRequest = null):
	# (this used to free whatever node was added last, e.g. the live ban timer)
	if is_instance_valid(http_request):
		http_request.queue_free()

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
		# Reload first so changes made since the start of this function aren't lost.
		config = ConfigFile.new()
		config.load("user://settings.cfg")
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
	http.use_threads = OS.can_use_threads() # connecting/TLS off the main thread (this runs as a song starts)
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
	"sep27-2026-web-b", "oct16-2026-a", "oct16-2026-b", "oct17-2026-a", "oct17-2026-b", "oct17-2026-c", "oct17-2026-d", "oct17-2026-e", "oct17-2026-f", "oct17-2026-g", "oct18-2026-a", "oct18-2026-b", "oct18-2026-c", "oct18-2026-d", "oct18-2026-e", "oct18-2026-f", "oct18-2026-g", "oct18-2026-h", "oct18-2026-i", "oct18-2026-j", "oct18-2026-k", "oct18-2026-l", "oct18-2026-m", "oct18-2026-n", "oct18-2026-o", "oct18-2026-p", "oct18-2026-q", "oct18-2026-r", "oct18-2026-s", "oct18-2026-t", "oct18-2026-u", "oct18-2026-v", "oct18-2026-w", "oct18-2026-x", "oct18-2026-y", "oct18-2026-z", "oct19-2026-a", "oct19-2026-b", "oct19-2026-c", "oct19-2026-d", "oct19-2026-e", "oct19-2026-f", "oct19-2026-g", "oct19-2026-h", "oct19-2026-i", "oct19-2026-j", "oct19-2026-k", "oct19-2026-l", "oct19-2026-m", "oct19-2026-n", "oct19-2026-o", "oct19-2026-p", "oct19-2026-q", "oct19-2026-r", "oct19-2026-s", "oct20-2026-a", "oct20-2026-b", "oct20-2026-c", "oct20-2026-d", "oct20-2026-e", "oct20-2026-f", "oct20-2026-g", "oct20-2026-h", "oct20-2026-i", "oct20-2026-j", "oct20-2026-k", "oct20-2026-l", "oct20-2026-m", "oct20-2026-n", "oct20-2026-o", "oct20-2026-p", "oct20-2026-q", "oct20-2026-r", "oct20-2026-s", "oct20-2026-t", "oct20-2026-u", "oct20-2026-v", "oct20-2026-w", "oct20-2026-x", "oct20-2026-y", "oct21-2026-a", "oct21-2026-b", "oct21-2026-c", "oct21-2026-d", "oct21-2026-e", "oct21-2026-f", "oct21-2026-g", "oct21-2026-h", "oct21-2026-i", "oct21-2026-j", "oct21-2026-k", "oct21-2026-l", "oct21-2026-m", "oct21-2026-n", "oct21-2026-o", "oct21-2026-p", "oct22-2026-a", "oct22-2026-b", "oct22-2026-c", "oct22-2026-d", "oct22-2026-e", "oct22-2026-f", "oct22-2026-g", "oct22-2026-h", "oct22-2026-i", "oct22-2026-j", "oct22-2026-k", "oct22-2026-l", "oct22-2026-m", "oct22-2026-n", "oct22-2026-o", "oct22-2026-p", "oct22-2026-q", "oct22-2026-r", "oct22-2026-s", "oct22-2026-t", "oct23-2026-a", "oct23-2026-b", "oct23-2026-c", "oct23-2026-d", "oct23-2026-e", "oct23-2026-f", "oct23-2026-g", "oct23-2026-h", "oct24-2026-a", "oct24-2026-b", "oct24-2026-c", "oct24-2026-d", "oct24-2026-e", "oct25-2026-a", "oct26-2026-a", "oct26-2026-b", "oct26-2026-c", "oct26-2026-d", "oct26-2026-e", "oct26-2026-f", "oct27-2026-a", "oct27-2026-b", "oct27-2026-c", "oct27-2026-d", "oct27-2026-e", "oct27-2026-f"
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
	"oct16-2026-a": "- Desktop release (web-only code removed)\n- Removed GUI scale setting\n- Maps load instantly",
	"oct16-2026-b": "- Smooth map loading (maps import in the background)\n- Fixed pixelated/blurry resolution\n- Auto-updates now come from iloverhythia/savia",
	"oct17-2026-a": "- Added a Stats page\n- Added Half Ghost Strength (Notes settings)\n- Added Hide Replay UI (Replays settings, F1 toggles it in replays)\n- Mouse pointer is visible in replays so you can use the replay bar\n- Added a setting to turn off XP notifications (Online settings)\n- GIF cursors and backgrounds no longer lag (decoded once and cached)",
	"oct17-2026-b": "- Fixed changing the cursor/background/sounds getting stuck on \"waiting for file dialog\"\n- Online maps are in the list as soon as the menu opens",
	"oct17-2026-c": "- Savia is now Furria! New name and icon\n- Map covers load during startup, so the map list is complete when the menu opens\n- Auto-updates only come from Furria's releases and never downgrade",
	"oct17-2026-d": "- Added star ratings (shown next to the note count)\n- The profile you select is remembered after restarting, and settings changes save into it\n- Fixed Disable Intro Cutscene\n- Discord Rich Presence now shows Furria",
	"oct17-2026-e": "- Fixed the game crashing on startup (Discord Rich Presence turned off for now)",
	"oct17-2026-f": "- Discord Rich Presence is back (rewritten so it can't crash the game)\n- New \"stars\" filter: sort maps by star rating\n- The profile you had selected is now remembered after restarting",
	"oct17-2026-g": "- Map Folders: create, name and color folders and add maps to them (button next to random map)\n- 12 new backgrounds from Rhythia\n- Colorsets have their own settings tab, with a colorset maker\n- Trail Opacity setting\n- New Hit FOV mode: Instant\n- Max FPS mode (Video settings) and faster gameplay code for higher FPS\n- Choosing a cursor/file now opens the real Windows file browser\n- Star ratings are calculated in the background so huge map libraries load fast and can't crash on startup",
	"oct18-2026-a": "- Map covers are cached: each cover is processed once, then loads instantly on every launch (and big libraries use far less memory)\n- The map cache is only rewritten when your maps change\n- Higher FPS: the in-game HUD redraws at most 240 times a second and no longer uses anti-aliasing, Max FPS mode also turns off HDR\n- Importing broken or unusual map files no longer crashes the game",
	"oct18-2026-b": "- Fixed crashes when importing .sspm maps: they're now copied as-is instead of being re-encoded\n- Map files are saved to a temporary file first, so an import can never leave a map with missing notes\n- Maps whose notes went missing from an earlier failed import are marked with a warning; drag the map in again to fix it\n- Map warnings now actually show on the map screen",
	"oct18-2026-c": "- New experimental setting: Wave Menu (Settings > Replays & Misc > Experimental) replaces the dark menu background with animated topographic waves",
	"oct18-2026-d": "- Wave Menu: slower waves, and light text gets black outlines so it stays readable\n- Much faster map list with big libraries (sorting, searching and filtering)\n- Search waits until you stop typing for a moment instead of rebuilding the list on every key\n- The map list no longer stalls on covers that haven't been cached yet; they appear a moment later\n- Fixed re-imported or deleted maps sometimes leaving a duplicate in the list",
	"oct18-2026-e": "- Discord status in the menu now says \"Idle while listening to furry ASMR\"\n- Updates now come from the renamed iloverhythia/Furria repository",
	"oct18-2026-f": "- Profile and Online are now full pages in the left sidebar\n- Profile page shows your Savia profile picture, rank, stats, top play and top 10 plays from savia.nysr.host (connect Discord to link it)",
	"oct18-2026-g": "- New menu music: Change It Up (a bit quieter than the old song)\n- Wave Menu option: use your colorset's colors (Settings > Replays & Misc > Experimental)",
	"oct18-2026-h": "- Online page: three columns (lobby controls | players | chats) that fill the window\n- Admin tools are now an Admin tab on the Online page\n- Rank button moved next to Favorite / Add to folder on the selected map\n- Wave Menu colorset mode now fades through every color in your colorset\n- Much faster startup with big map libraries (finding map files was ~40x slower than needed)",
	"oct18-2026-i": "- Rank Map button is now in the top-right corner, and only shows while a map is open",
	"oct18-2026-j": "- Huge startup speedup for big map libraries: some maps had junk data that took ~1 second each to read and bloated the map cache to 100+ MB\n- Duplicate and broken map files are remembered, so they're no longer re-read on every launch\n- The map cache is only saved when something changed\n- Fixed star ratings being recalculated every launch",
	"oct18-2026-k": "- The stars filter no longer shows rating progress next to its name",
	"oct19-2026-b": "- Updates come from the renamed iloverhythia/Chromia repository",
	"oct19-2026-c": "- Hit and miss effects are back (Notes tab)\n- New Note Builder tab: build your own note shape\n- Favorite colorsets (star them in Colorsets)\n- Cursor trail gradient (World & Cursor)\n- New Background Editor tab: place images/videos on screen\n- Map screen: History of your previous attempts\n- Stats moved to a tab in the Profile panel\n- Language moved to a Settings tab",
	"oct19-2026-r": "- Click the Filters heading to collapse / expand the filters (remembered)",
	"oct19-2026-s": "- New Map Browser page in the sidebar: browse rhythia.com maps (difficulty, search, sort, ranked/unranked) and download them right into the game, no restart",
	"oct20-2026-a": "- Map Browser: removed the ranked filter and ranked badges (rhythia.com's ranked maps aren't Chromia's), it shows all maps",
	"oct20-2026-b": "- Fixed antivirus (Bitdefender) threat warnings: the game no longer runs hidden PowerShell / reg.exe (file pickers use the in-game browser now) and the Map Browser no longer writes hidden temp files\n- Map Browser: you can download a map even if you have one with the same name (different versions are kept side by side), no more 20 star cap on Any / Expert, stalled downloads time out instead of hanging, big maps no longer time out after 2 minutes",
	"oct20-2026-c": "- The file browser has a preview pane: click a file to see images / GIFs, play videos, or play audio before picking it\n- Typing the letter O in a text box no longer jumps to Settings",
	"oct20-2026-d": "- NEW: Map Editor in the sidebar, an in-game map editor based on Sound Space Quantum Editor: the 3x3 grid with Q W E / A S D / Z X C keys, quantum placement, track with beat lines, BPM / offset / BPM tapper, metronome and hitsounds, undo / redo, copy / paste, flip / rotate, SSQE map data copy / paste\n- Save puts the map straight into your map list; Playtest plays it in the game and brings you back to the editor\n- Edit any map from its Actions menu (Edit in Map Editor); BPM is guessed from its notes",
	"oct20-2026-e": "- Map Editor redone to look like Sound Space Quantum Editor (same layout: track on top, OPTIONS / TIMING / PATTERNS and SNAPPING / GRAPHICS / EXPORT tabs, timeline, playback speed, SFX / Music) in Chromia's colours\n- The middle of the editor is now the game itself: your note mesh, colorset, approach rate, fades, note size, border, cursor and background world, from the game's camera (turn it off in GRAPHICS > Game View for the flat grid)\n- New editor options: snap to grid, quantum offsets, numpad keys, jump on paste, pause on seek, SFX offset, rotate / scale by any amount, export .sspm, replace song, save as, star rating",
	"oct20-2026-f": "- Map Editor uses the game's font\n- 2D view like Sound Space Quantum Editor's (GRAPHICS > turn off 3D Mode): frame, grey grid, rounded notes fading in, approach squares, note size, grid zoom, smooth autoplay cursor\n- The grid no longer moves with parallax in the editor\n- Editor and content manager backgrounds are see-through, so menu backgrounds like waves show properly\n- PATTERNS tab like SSQE+: flips, rotate / scale with arrows, apply on paste, paste reversed, clamp in bounds, store / clear nodes and Draw Bezier with Divisor",
	"oct20-2026-g": "- Map Editor: the game view now covers the whole screen, so the menu background no longer peeks out at the edges\n- Fixed the modifiers ending up off-centre (over the History list) after restarting the game: they re-centre whenever the things around them change size",
	"oct20-2026-y": "- NEW (phones): touch indicator, a ring under each finger in menus and songs, fading out when you lift it. Turn it on/off in Settings > Gameplay > Touch Indicator (a picture named \"touch\" in Chromia's folder replaces the ring)",
	"oct21-2026-a": "- NEW (phones): the touch indicator is fully customizable. Settings > Gameplay > Customize Touch Indicator: 8 shapes (ring, filled circle, dot, ring with dot, square, diamond, crosshair, your own picture), size, outline width, outline and fill colours, opacity, fade out time, grow and pop animations, tap ripples, a trail behind moving fingers, rainbow colours, show it in menus and/or songs, presets, and a live preview",
	"oct21-2026-p": "- Modifiers are Sound Space style tiles now: rounded tiles with an icon and a name in a magenta frame, 2 pages with arrows and a 1/2 counter, glowing cyan when on. Page 1: No-Fail, Ghost, Sudden Death, Extra Energy and every speed (new ---- and ++++ tiles too); page 2: No Regen, Hard Mode, Hard Rock, Strobe, Mirror X/Y, Earthquake, Chaos, Visual Mode, Invert Mouse, 360 and Flashlight. Tap the speed that's on to go back to normal speed. Custom speed, HP model, grade system and 360 speed are under the tiles",
	"oct22-2026-a": "- The Sound Space style modifier tiles only show with Sound Space Mode on. With it off the modifiers are the normal checkboxes and speed buttons again",
	"oct22-2026-b": "- While you're in the menu the game checks for a new version every few minutes and pops up an Update box by itself (Later skips that version until you restart)\n- Sound Space Mode's background matches the video: floor and ceiling fade into the fog, same grid size, line brightness and colours\n- Sound Space Mode: see-through side panels like the video, red health background and the skin's grey progress bar",
	"oct22-2026-c": "- Sound Space Mode score popups look like the video: the points show under the grid at the note's spot in light grey for a moment, then fade. Turn them on or off in Settings > Replays & Misc > Experimental (Sound Space Mode: score popups)\n- Sound Space Mode: the health bar sits on the bottom bracket line and drains from the right, showing red, like the video\n- The Grid background is now the Sound Space room from the video",
	"oct22-2026-d": "- Sound Space Mode menus, like classic Sound Space (only with Sound Space Mode on; nothing added or taken away):\n  - a main menu in place of the sidebar: the logo and big pixel words for every page (Play, Settings, Credits, Content Manager, Update Log, Profile, Online, Map Browser, Map Editor, Quit...). Esc or the red BACK on a page comes back to it\n  - the maps as a 3x3 grid of tiles with a page counter and arrows: EASY, MEDIUM, HARD, LOGIC? and the white Tasukete tile filter the maps, then the maps coloured by difficulty with their stars. Your Discord name and picture on top (tap it to log in), search, BACK and REPLAY (watch a replay file)\n  - tapping a map opens its screen: the modifiers in a magenta frame, cover, mapper, difficulty, length, Start From, Favorite? and Hide, your best, PLAY and VS, and your top runs\n  - every other page in Sound Space's look: black, neon frames, coloured outlined buttons, red value boxes and pixel-font titles\n- Sound Space Mode: health bar and song progress bar height and width can be changed in Settings > Replays & Misc > Experimental\n- The normal modifier list is back when Sound Space Mode is off",
	"oct22-2026-e": "- Fixed: with auto retry on, Sound Space Mode's display settings stayed on only for the first try; after dying once your own settings came back mid-session. They now stay on for every retry and come back when you leave the song\n- Sound Space Mode main menu shows the Chromia logo\n- Sound Space Mode menus' text is sharp on phones and big screens (made at the screen's real size instead of stretched)",
	"oct22-2026-f": "- Sound Space Mode menus move and sound like Sound Space's (sounds taken from it): the main menu fades in and its words slide in one after another with a tick; buttons and tiles grow a little with a tick when you point at them and click when picked; pages and the map screen swing in with a swoosh; map tiles pop in and slide when you turn the page\n- Sound Space Mode map grid: the { } tile (maps without a difficulty) is back in white, and Tasukete uses Chromia's dark colour\n- Long map names no longer stick out of their tiles",
	"oct22-2026-g": "- Sound Space Mode menus move like Sound Space's camera: the screen always drifts and leans toward your cursor / finger, and opening something whips the camera around (PLAY throws the main menu to the right and the maps swing in from the left; pages swing in from the right; BACK turns back). No more pop-in / grow effects; hovering still ticks",
	"oct22-2026-h": "- Sound Space Mode map screen: the difficulty squares sit right after \"Difficulty:\"; Tasukete maps get a black cover frame and a black Tasukete square",
	"oct22-2026-i": "- Sound Space Mode: no more camera lean / whip on the menus. Opening a map works like Sound Space: a LOADING box with a spinning orange ring over the grid (tap it to cancel; online maps download meanwhile), then the map's screen fades in; Hide fades back to the grid",
	"oct22-2026-j": "- Sound Space Mode menu switching animations, like Sound Space's camera turning between panels: the screen you leave leans and slides off to the side while the new one slides in from the other side and settles (going into something comes from the right, BACK from the left). The screens stay still otherwise",
	"oct22-2026-k": "- Sound Space Mode: the speed icons show at the bottom while playing again (they were pushed off the HUD), as Sound Space's modifier tiles; without Sound Space Mode they're the normal icons",
	"oct22-2026-l": "- New experimental setting \"Sound Space Mode: gameplay only\" (Settings > Replays & Misc > Experimental): Sound Space Mode only changes the songs, and the menus (sidebar, map list, modifiers, pages) stay Chromia's",
	"oct22-2026-m": "- NEW: Settings Generator (Settings > Generator). Chromia now keeps track of how you play every map (on this device only, turn it off with Track my plays): every note you hit or miss, how early your cursor gets there, whether you miss by being late, overshooting, being just off or aiming elsewhere, which jump speeds and parts of the grid you miss most, and the settings you had on. Generate my settings shows what it found and suggests settings that fit you, each with the reason and how sure it is: from your own history (plays compared on maps of the same difficulty, allowing for you improving) and from how you miss (e.g. overshooting -> lower sensitivity, late on fast jumps -> earlier notes). Apply one or all, Undo puts your old settings back. It only changes how the game feels (sensitivity, approach, parallax, FOV, fade, cursor scale, spin), never hitbox, hit window or mods",
	"oct22-2026-n": "- Touch indicator trail: smooth and much lighter (one tapered ribbon instead of hundreds of circles; only new points when your finger moves), so it no longer lags the game\n- Cursor trail on phones: drawn over the grid like the cursor (phones hid it behind the grid), and it no longer piles up while the cursor stands still\n- No Touch Delay: less delay. The cursor is put one frame ahead of your finger along the way it moves (back on the exact spot as soon as you stop), and iOS no longer holds the first touch back (also without the native helper)",
	"oct22-2026-o": "- Fixed: the game could crash on phones right after failing with auto retry on. Retrying now goes through the song loader like starting a song from the menu (the crash log also shows more of the song start now)\n- Crash logs only show after a crash: closing the app from the phone's app switcher no longer counts as one. New experimental setting (Settings > Replays & Misc > Experimental, off by default): Always show crash logs, which shows the last session's log at every start\n- Phones: Load Replay button next to Map Folders in the map list, to watch a replay (.sspre) from your replays folder or anywhere on the phone\n- VR fixed (it couldn't start: the menu and songs failed to load in VR). The menu screen, the controller pointer and clicking work, the pointer dot sits where you point (it was drawn off to the side), the sidebar stays open while you point at it, the map list scrolls with the controller, songs play with the controller ray as the cursor, and Sound Space Mode works in VR. If SteamVR isn't running, Start VR tells you instead of breaking the menu",
	"oct22-2026-p": "- VR: the game recenters to you. Resetting the boundary / Reset view on a Meta Quest (or SteamVR's reset) now puts the game at your eye height and in front of where you're facing: the menu screen straight ahead, the grid straight ahead in songs, whatever your real height. It also does this once when VR starts (it used to sit too low for most people)\n- VR: the crash log now shows each click and each map you open, to find the crash when clicking a map (send the crash log if it happens again)",
	"oct22-2026-q": "- VR recentering follows where you look: look down when you reset the boundary / view and the menu screen (or the grid in a song) moves down in front of you and tilts to face you; look up and it goes up. It stays that way between the menu and songs\n- VR: recenter any time with A / X, and smaller view resets are noticed too\n- Crash reports now include the game engine's own error messages from the session that crashed (send them when it happens: they show what broke)\n- The engine log is now also kept on phones",
	"oct22-2026-r": "- NEW: Meta Quest app (chromia-quest.apk). Sideload it (SideQuest or adb install) and Chromia runs on the headset by itself, no PC: it starts straight in VR, with the controller as the pointer and cursor. It updates itself: new versions download when it starts and load the next time you open it\n- VR keyboard: a keyboard pops up on the VR menu screen whenever you select a text box (search, names, settings...). Point and pull the trigger to type; Shift for capitals and symbols, Done to close it. Also in PC VR\n- VR: boxes and messages (update boxes, confirmations, the file picker, notifications, crash reports) now show on the VR menu screen; you couldn't see them in the headset before\n- VR: the controller buttons work from either controller",
	"oct22-2026-s": "- NEW: Meta Horizon Store version (chromia-quest-store.apk), ready to upload to the store: it lists the headsets it runs on (Quest 2, Pro, 3, 3S), runs in landscape, needs Android 10+, asks for no storage permissions and leaves updates to the store\n- The sideload Quest app gets the same fixes",
	"oct23-2026-b": "- The Update Log shows the notes of the last few versions again",
	"oct27-2026-f": "- Profiles (in the game and on the website) show when a player was last online again, or Online now\n- The server behind Savia was rebuilt: safer sign-in, fairer ranked scoring, faster leaderboards, and no lost data if it crashes",
	"oct27-2026-e": "- NEW: the menu music is now 7 Hodgy Beats songs played in a random order: Change It Up, Alright, April Fools, Blame It, Claustroflowbic, Cudda Been and Memorex Cds. When one ends the next starts, every song plays once before any repeats, and the same song never plays twice in a row. All of them are as loud as the old menu song\n- A custom menu song (menu.ogg / .mp3 / .wav in the game folder) still replaces them and loops",
	"oct27-2026-d": "- NEW: Sign out of Discord: a Sign out button on the Profile page, in the multiplayer panel (where Connect Discord was) and in Settings (it was called Unlink Discord). If the server can not be reached it says so instead of getting stuck\n- NEW (VR): Settings > VR > Pointer > Lock the pointer to the grid in songs (off by default): the beam ends on the cursor and never goes past the edges of the grid",
	"oct27-2026-c": "- Meta Quest: the release build retries the Android tools download (it failed once and oct27-2026-a came out without the Quest app; oct27-2026-b and later have it)",
	"oct27-2026-b": "- VR: Connect Discord no longer shows a QR code (a phone cannot see inside the headset, sorry). On the Meta Quest it shows the steps and an Open Discord login button: the headset browser opens over the game, log in and press Authorize, then come back to Chromia and it links by itself. On PC VR / Link the page opens on your computer",
	"oct27-2026-a": "- FIX (VR): Connect Discord works in the headset: it shows a QR code on the menu screen, scan it with your phone and log in there, and the game links by itself (it waits up to 10 minutes). On the Meta Quest there is also a button to open the page in the headset browser, and the game checks again as soon as you come back; on PC VR / Link the page opens on the computer too\n- NEW (VR): Settings > VR > Pointer: beam thickness, colour (and see-through-ness), and a rainbow pointer\n- Crash reports are more useful: the background star rater no longer writes a line per map (it pushed out what happened before a crash)\n- Removed old unused analytics keys from the game code",
	"oct26-2026-f": "- VR: the Furry paws are now cartoon paws: no fuzz, clean cel-shaded cream with a bold outline, round toe bumps, and glossy pink toe beans and main pad with darker rims. They are also much lighter for the headset to draw (4 draws per hand instead of 6)",
	"oct26-2026-e": "- FIX (VR, Meta Quest): the game crashed as soon as VR started (in oct26-2026-d): the foveated rendering setting was handed to the headset the wrong way. It is set correctly now, a moment after VR starts\n- VR: the Furry paws are cuter and look like real paws: one soft plush mitten with four toe bumps melting into it (no more stuck-together balls), shorter softer fur, a slimmer cuff, bigger toe beans and main pad on the palm, the back of the paw up so you see the toes, and the beam starts at the toes",
	"oct26-2026-d": "- VR performance: Meta Quest foveated rendering is on (Settings > VR > Graphics: Off / Low / Medium / High, Medium by default): the edges of each eye are drawn at lower resolution, where the lenses blur them anyway\n- VR performance: glow (bloom) is off on the Quest unless you turn it on (it is a full-screen effect drawn for each eye); on PC VR it stays, in its cheaper form. SSAO, screen reflections and depth of field are always off in VR\n- VR performance: the menu screen is redrawn every frame only while you use it, and every other frame otherwise; the menu pillars are plain meshes; the song HUD panels no longer use 4x multisampling or a 3D pass\n- NEW (VR): Settings > VR > Graphics: refresh rate (72 / 80 / 90 / 120 Hz on the Quest), render resolution (applies the next time VR starts), glow, and Simple background in songs (the plain VOID background, the fastest)\n- VR hitboxes work like on PC: the cursor goes exactly where the beam meets the grid, worked out from the controller each frame (it used to be a frame late), with the same edge limits as PC. The grid and notes no longer slide with the PC parallax settings. VR replays now record the cursor\n- NEW (VR): Aim sensitivity (Settings > VR > In songs): how far the cursor moves for how far you turn the controller; the beam bends to end on the cursor\n- NEW (VR): Haptics: a short buzz on each hit and a stronger one on a miss, with a strength slider and a switch for misses\n- NEW (VR): Hands: pick Default, Furry paws (fluffy cream paws with pink toe beans) or Custom (your own vr_hand.obj in the user folder: the right hand in metres, controller at the middle, pointing along -Z)",
	"oct26-2026-c": "- VR: the map filters show on the menu screen again: broken / online / ranked, sorting (difficulty, name, stars, most played), the difficulty buttons and map folders. They were hidden in VR",
	"oct26-2026-b": "- VR: clicks on the menu screen land where you point. Before, every click landed further right and lower than the pointer, so the right and bottom of the menu could not be clicked at all\n- VR: the menu is laid out bigger (like a 1600x900 window), so all of it fits on the screen: every settings tab, the whole map list and its buttons\n- VR: resize the menu screen from the icon in its bottom right corner: point at it, hold the trigger and drag to make the screen bigger or smaller, or tap it for size buttons (screen size, and text and button size: smaller fits more). Also in Settings > VR\n- VR: the thumbstick scrolls settings pages and other lists while you point at them (it used to change the number box or slider under the pointer instead). Either hand's thumbstick works\n- VR: failing or restarting a map no longer recenters you (loading made it look like a boundary reset)\n- VR: hold the recenter button (A / X) for a second to recenter; a short press does nothing. Resetting the view on the headset still recenters right away\n- NEW (VR): Settings > VR > In songs > Grid distance: how far away the grid is where the notes come from (default 2.25 m). Closer fills more of your view, like a wider FOV\n- NEW: Settings > Transfer: move your settings and custom content (colorsets, meshes, cursors, sounds, borders, backgrounds, profiles, keybinds, VR settings) to another device with a code. Generate a code on one device, enter it on the other (same Wi-Fi, both with the game open). Or save it all to a file and load that. Maps, replays and scores stay. Your old settings are kept as the profile 'before transfer'\n- The background picker also works on the VR menu screen",
	"oct26-2026-a": "- The background picker (Settings) fits on every screen: it opens a scrollable grid with each background's picture and name, grouped into Chromia, Rhythia and Rhythia (Roblox). Before, the list ran off the bottom of the screen on phones\n- Drag to scroll; tap a background to pick it",
	"oct25-2026-a": "- NEW: 44 backgrounds from Roblox Rhythia (the 'Spaces' pack), under Rhythia (Roblox) in the background list:\n  Default, Halloween, Holo Dream, Vaporwave, Conspiracy, Inverted Conspiracy, Christmas, The Speaker, Valentines, Easter, Palm Trees, Skull, Pumpkin Kingdom, Tronic, Tri Tunnel, The Flower, Squircle, Squircle Vortex, Cubic, Rift, Beyond Reality, Phantom Seas, World Cracks, Unity Tower, Summer, Hell, Cat Shades, Legacy, Shooting Stars, Torii, Calm Night, Arcade, Sound Invaders, Dojo, Heartscape, Admin Panel, Lucky, Cosmic Pyramid, and the Red / Green / Blue / Gray / Black / White screens\n- Each one has its original models, textures, skies, lighting, fog, water, particles and lights\n- Their animations work like in Roblox: things react to your hits in the note colour (ghosts and bats, lightning on the ghost ship, flashing lamps, waves, shooting stars, invaders being shot down...), and some pulse with the music\n- The biggest ones (Phantom Seas, Easter, Rift, Christmas) are detailed scenes and need a decent graphics card",
	"oct24-2026-e": "- Maps that were left out of your map list now load:\n  - maps with the same map id as another map (e.g. another difficulty or a conversion) get their own id, so both show; only an exact copy of a map you already have is left out\n  - maps marked as needing mods (they load with a warning)\n  - maps in folders more than 5 levels deep (now 12)\n  - .SSPM files with a capitalised extension\n  - maps with a difficulty value Chromia did not know (they show as unknown instead of being hidden)\n  - files that could not be read once are tried again after each update\n- Any map file that still cannot be loaded gets a message, with the list and why in logs/map_report.txt (Settings > Open User Folder)",
	"oct24-2026-d": "- Settings Generator no longer pushes a setting higher and higher (or lower and lower) each time you press Generate\n- After you apply a suggestion it leaves that setting alone until you have played 3 maps with it, then compares it with what you had before\n- It looks at how your older settings went before suggesting anything: no going further in a direction where you already did worse, and it only keeps going if your last step there really helped (it tells you why when it holds back)\n- \"Try this\" ideas follow the same rule, with an even higher bar",
	"oct24-2026-c": "- Settings Generator: fixed \"Not enough plays with your settings now (0 plays and 0 notes)\" showing when it had plenty of plays\n- Small tweaks no longer reset it: plays within about 10% of your settings count as the same settings\n- A history note (\"no clear difference yet\") no longer switches off the checks on how you play now, so it gives more real suggestions\n- New: skipping or leaving notes in quick runs more than elsewhere -> a higher approach rate (notes further apart)\n- Distance advice needs to see that you are really late on notes that showed up late\n- \"Try this\" ideas only for values you have not really played yet (tiny tweaks do not count), in the direction your misses point, then fade-in once those are tried\n- Faster Generate with lots of plays (it looks at your newest 150,000 notes)",
	"oct24-2026-b": "- Settings Generator fixed: it said \"0 notes\" and never suggested anything when you play with mods or half ghost on (those plays were left out). Mods are now ignored (only the speed counts), so all your plays count\n- New check: when almost all your misses are being late and notes are readable only briefly, it suggests more distance (or less fade-in)\n- Older plays count however you aimed, and the sensitivity check no longer reads them as all overshoots\n- The waiting message says how many plays and notes it has with your settings and how many more maps it needs",
	"oct24-2026-a": "- Settings Generator only says your settings fit when it really checked them: with too few plays on your current settings it now says so (and how many more it needs) instead of \"your settings already fit\"\n- Fixed misses being counted as \"just off\" when you never set off for the note (you were still on the note before, next to it). That gave wrong FOV / cursor size advice\n- Sensitivity advice only counts jumps you set off for in time (being late because you set off late is reading, not aim)\n- Plays remember if you played with a mouse, touch or VR, and only plays aimed the same way are compared. In VR it no longer suggests sensitivity, FOV, cursor or parallax (they don't apply)\n- \"Try this\" ideas are shown apart from real suggestions, and Apply all only applies the real ones",
	"oct23-2026-h": "- VR menu: a big screen curved around you (100 degrees of your view, 1.6 m away, every part just as far) instead of the small flat one, drawn sharper (1920x1080)\n- Scroll the map list and other lists with the thumbstick while you point at them\n- Settings > VR > Menu screen: size (50 to 150 degrees), distance (1 to 3 m) and curved or flat",
	"oct23-2026-g": "- Settings Generator suggests more than sensitivity, from how you play with your settings now (no need to have tried other values first):\n  - Fade-in: late on notes that appeared late while a long fade-in hides them -> less fade-in (same speed and spacing)\n  - Camera / grid parallax (touch): hitting outer notes on their inner side because the view moves with the cursor -> less parallax\n  - Cursor size: missing notes by a hair with a big cursor -> smaller; losing a tiny cursor -> bigger\n  - FOV (mouse): missing by a hair -> a lower FOV for a bigger grid on screen\n- Sensitivity advice no longer counts near misses as overshoots, or late misses on notes that showed up too late (those are about distance)\n- Up to 5 suggestions, and the \"try this for a few maps\" ones never clash with a real suggestion",
	"oct23-2026-f": "- Replays show the touch indicator: plays on phones now record your fingers (when you touch, lift and where you move), and watching the replay shows them with your touch indicator style, on computers too. Jumping around in the replay puts the fingers where they were then. Older replays have no finger data, and replays with it still open in older versions",
	"oct23-2026-e": "- Fixed a crash at the start of songs on iPhone with the Custom Background (often after failing and auto retrying): the background is now made into a still sky image once when the song starts, instead of redrawing a 4096x2048 picture every frame. It looks the same and runs much faster",
	"oct23-2026-d": "- Fixed the game closing as soon as it opened in oct23-2026-c (a typo in the update notes broke the game's main script)\n- Every release now starts the game and checks it reaches the menu before it is published",
	"oct23-2026-c": "- Settings Generator rebuilt: every tracked play now remembers the settings and mods it was played with, so advice is about the settings you really used on each map (old plays still count)\n- It compares your plays fairly, allowing for how hard each map is and for you getting better, and only suggests a change when the difference is clear (it says how sure it is)\n- New approach rate and distance advice: how long notes are on screen, your reaction time to new notes, late misses on notes that appeared too late, and leaving notes early in quick runs\n- If you just changed a setting it waits for a few maps before judging it\n- Better note tracking: tells apart late, overshot, left early for the next note, skipped and just off\n- Suggestions can change more than one setting at once and show a list of your plays by settings",
	"oct23-2026-a": "- NEW (VR, Meta Quest app and PC VR): Settings > VR\n  - Controller grip: change the pointer's tilt, turn and roll and move it left / right, up / down and forward / back on your hand, so it points where feels natural. The beam moves as you change it; the left hand gets the mirror image. Reset grip puts it back\n  - Controller buttons: pick which button clicks, pauses, gives up, retries, recenters and switches hands (Trigger, Grip, A / X, B / Y, Thumbstick press or Menu, up to two each). Reset buttons puts them back",
	"oct22-2026-t": "- Privacy policy: iloverhythia.github.io/Chromia/privacy.html (what the game stores and sends, and how to have your online data removed)\n- Replays now store a hashed device ID instead of the raw one",
	"oct21-2026-o": "- Sound Space Mode no longer changes your camera (half-lock / spin, camera, HUD and grid parallax, faraway HUD)",
	"oct21-2026-n": "- Sound Space Mode also sets your display settings to classic Sound Space's while a song plays, and puts yours back after: its camera (Half-lock faraway, camera parallax 10, measured from a recording), FOV 75, no cursor trail, buffer cursor, spin, hit/miss/spawn effects, approach squares, note spin, glow, bloom or VHS, and all HUD parts on in their normal places. Your notes keep your own mesh and colors, and your settings are never saved with Sound Space's (even if the game closes during a song)",
	"oct21-2026-m": "- Sound Space Mode matches classic Sound Space more closely (measured from a recording): floor and ceiling grid fading into the dark, the time on the top bracket line with the progress line under it, the health line on the bottom bracket line, wider side panels with bigger text, the multiplier box filling clockwise from the top-right corner and flashing orange when you reach x8, the grey square cursor with a thin white edge, and grey hit points in a normal font. It no longer changes your note mesh (or your colors)",
	"oct21-2026-l": "- Sound Space Mode now looks like the classic Roblox Sound Space: a dark navy grid tunnel, corner brackets with the time and a thin progress line at the top and the green health line at the bottom, dark side panels in the pixel font (multiplier box that fills up, COMBO, accuracy; score, Misses, Notes), hollow square notes, the grey square cursor, and the points of each hit popping up under the grid",
	"oct21-2026-k": "- NEW (Settings > Replays & Misc > Experimental): Sound Space Mode. Songs look like the original Sound Space (from the SSLookalike skin): grey side panels with your hits and misses, a thin green health bar under the grid and a white progress bar over it, corner brackets around the grid, the grey square cursor, rounded notes, the Void background, a grey circle where you miss a note, and Sound Space's hit, miss and fail sounds. Your own settings stay as they are for when it's off",
	"oct21-2026-j": "- Map Browser: .rhm maps download now (most new maps on rhythia.com are .rhm; they failed with \"isn't a working map\"). They're converted and added to your maps like the others\n- Importing .rhm files works on every platform (it only worked on Windows: phones, Mac and Linux couldn't open them)",
	"oct21-2026-i": "- Map Editor: Detect From Notes (TIMING > OPEN BPM SETUP). Works out the BPM and offset from where the notes are, including tempo changes (each one becomes a timing point). Uses the selected notes, or the notes between Start and End (all of them when both are 0). Shows how many notes fit and other tempos that fit too; x2 and /2 change it, Apply adds the timing points (undo works)",
	"oct21-2026-h": "- iPad (and other squarer screens): the menus were cut off on the right (map filters, scroll buttons, settings tabs and buttons) next to the sidebar. Everything is a little smaller there now so it all fits",
	"oct21-2026-g": "- Phones: two new settings under Settings > Gameplay > Touch Indicator.\n- No Touch Delay: every finger movement is used as it comes instead of once per frame, and on iPhone the 0.15 s hold the game engine put on each new touch is gone.\n- 120 Hz: the game draws at your screen's highest refresh rate (120 Hz on ProMotion iPhones and iPads), for smoother movement and less delay; an FPS limit under 120 is lifted when you turn it on.\n- iPhone: both need this version's chromia-ios.ipa installed once (in-app updates can't add them)",
	"oct21-2026-f": "- iPhone: Phone files button in the file browser. It opens the phone's own file picker right inside Chromia (iCloud Drive, On My iPhone, Downloads and other apps' folders) instead of sending you to the Files app; the file you pick is copied into Chromia and opened. When saving, Save to phone lets you put the file anywhere on your phone. Needs this version's chromia-ios.ipa installed once (in-app updates can't add it)",
	"oct21-2026-e": "- Phones: a new file browser made for touch, instead of the tiny desktop one. Big rows you scroll with your finger, a Back button, the folder you're in shown as Chromia › maps › ..., file sizes, and big Open / Save / Cancel buttons. Tap a folder to go in, tap a file to select it and tap it again (or Open) to open it. Saving has the name box at the top so the keyboard doesn't cover it, and asks before replacing a file. Show all files lists files of every type. iPhone: Files app button at the top; Android: Places (Chromia, Downloads, phone storage)",
	"oct21-2026-d": "- Phones: the file picker's bottom buttons (Open / Save, Cancel, Open Files app) are much bigger and easier to tap",
	"oct21-2026-c": "- iOS: fixed auto-updates putting you back on an old version. A downloaded update was thrown away whenever one start didn't reach the menu (for example closing the app while it was loading or downloading), and the game went back to the version of the installed .ipa. Now only an update that fails to start 3 times in a row is removed, you're told when that happens, and that version isn't offered again\n- If you're on an old version now, open Chromia and accept the update once more",
	"oct21-2026-b": "- NEW: the Map Editor is now Sound Space Quantum Editor Plus, ported 1:1 into Chromia (in Chromia's own buttons and colours). The same screen: the track with the waveform, beat ticks, timing points and labels; the 3x3 grid with quantum snapping, approach squares, grid numbers / letters, the autoplay cursor and 3D Mode; the timeline with bookmarks; OPTIONS (numpad, separate click tools, jump on paste, pause on seek, old quantum divisor, extra objects), TIMING (export / SFX / music offsets, BPM SETUP with timing points, DETECT BPM, IMPORT INI, metronome, bookmarks), PATTERNS (flips, rotate, scale, stored nodes and bezier, paste options), PLAYTEST (your camera, note size, sensitivity, parallax, FOV, approach, hit window, play from start / here), SNAPPING, GRAPHICS and EXPORT (save, save as .txt + .ini, SSPM / Rhythia RHM / Rewrite PHXM export, replace audio ID, calculate SR). Windows: BPM Setup (add / update / delete / move points, paste osu! / ADOFAI / Clone Hero timings, BPM tapper, detect BPM), Bookmarks, BPM Tapper, Export. Extra objects (beats, mines, glides, lyrics, fevers, note easing), stored patterns on 0-9, undo / redo, copy / paste between maps, and all of SSQE's keybinds. LOAD MAP opens .txt (+ .ini), .sspm, .osu and .rhm maps. Phones get SSQE+'s touch buttons (undo, redo, select all, copy, cut, paste, delete, save). The auto mapper comes in a later update",
	"oct20-2026-x": "- NEW: Settings > Video & Audio > Menu Music Lyrics: how loud the singing is in the menu music (song previews and the menu song). At 0% it plays as an instrumental (works best on songs mixed in stereo; the bass is kept)",
	"oct20-2026-w": "- The app icon is the Chromia ring again, now with room around it so the rounded corners don't cut it off (and on iPhone it now really replaces the old icon: reinstall chromia-ios.ipa to see it)",
	"oct20-2026-v": "- NEW: picking files on Windows, Linux and macOS uses your computer's own file manager again. It used to get stuck on \"waiting for file dialog\" (it never opened); fixed, and the game leaves fullscreen while it's open so it can't hide behind the game\n- iPhone: the file browser has an \"Open Files app\" button that opens Chromia's folder in the Files app (On My iPhone > Chromia), to copy maps and pictures in\n- NEW: a new app icon",
	"oct20-2026-u": "- iPhone/phones: songs and menus now load on the main thread (loading on a second thread while the game runs is a known cause of random crashes on phones), aimed at the crash when playing the same map again\n- FIX: going back to the menu could clear a map's notes while the star rating was reading them on another thread\n- NEW: Settings > Crash Reports keeps the last 5 crash reports, to copy and send any time (also without internet at the moment of the crash)",
	"oct20-2026-t": "- NEW (iOS): automatic updates. When a new version is out, the game downloads it at startup; close Chromia completely and open it again to use it. (Install this version's chromia-ios.ipa once; after that it updates itself)\n- iPhone/phones: the song panel fits on screen (it was cut off at the bottom), including the space under the iPhone home bar\n- iPhone/phones: sharper graphics: the game draws at the screen's full resolution, and glow/HDR effects are on like on PC\n- iPhone/phones: the renderer runs on one thread (the multi-threaded one is experimental and was the likely cause of the crash when starting a song)",
	"oct20-2026-s": "- Crash reports now cover the first moments of a song in detail (each frame, the background in use, when the music starts), to find the iPhone crash when starting a song",
	"oct20-2026-r": "- NEW: crash reports. If Chromia closes unexpectedly, the next launch shows what it was doing last, with a Copy report button to send to the developer\n- FIX (phones): if holding Give Up ended a song while your finger was still down, Give Up stayed held into the next screen and song",
	"oct20-2026-q": "- FIX: on phones (iPhones especially) the song panel was cut off at the bottom and the cover slid under the sidebar. Phones now get the full 720-tall layout the menus are built for, scaled to the screen",
	"oct20-2026-p": "- FIX (the real one): opening your Profile after linking Discord closed the game. Players without an avatar on the leaderboard made the search for you hit an error; fixed\n- The same kind of mistake (reading an empty value from the server or a saved file) is fixed in 80+ other places: online lobbies, Discord login, the map browser, leaderboards and the editor",
	"oct20-2026-o": "- FIX: the Profile page could still close the game on iOS while loading the leaderboard. It now downloads on a background thread like every other part of the game\n- The Profile page's crash report is more detailed (drawing, connecting, reading the reply), in case anything is left",
	"oct20-2026-n": "- FIX: opening your Profile after linking Discord could close the game on iOS. Avatars are now always fetched as a small still PNG, and the round avatar is cut out of the picture itself instead of using a custom shader\n- If the Profile page ever closes the game again, the next launch says exactly which step it was on",
	"oct20-2026-m": "- FIX: iOS \"Menu failed to load\": the iOS engine can't play .webm videos, and the scripts that mention that video type couldn't even start there. They now check first, so the menu loads (on iOS, .webm backgrounds are skipped; .ogv still works)\n- The \"Menu failed to load\" screen now names the file that broke, and error screens say Chromia instead of Furria",
	"oct20-2026-l": "- FIX: iOS (and Android) got \"Menu failed to load\": a few textures were saved in a GPU format that only some devices read; they now load everywhere\n- Release downloads are now simply named chromia-windows.zip, chromia-linux.zip, chromia-macos.zip, chromia-android.apk, chromia-ios.ipa and chromia-web.zip",
	"oct20-2026-k": "- NEW: Chromia for Linux, macOS, Android and iOS! Every release now comes for Windows, Linux, macOS, Android, iOS and the browser\n- Linux updates itself like the Windows version; on macOS, Android and iOS, Check for Updates opens the download page\n- Android and iOS use the phone-friendly layout and touch controls",
	"oct20-2026-j": "- Phones and tablets (browser version): bigger UI that fits the screen, tap a sidebar icon to open it, drag to scroll lists, drag anywhere to move the cursor, tap the top-left to pause and hold the bottom-left to give up\n- Phones: the first tap goes fullscreen in landscape (where the browser allows it), and holding the phone upright shows a reminder to turn it\n- Browser version: an Import button for map files, the Fullscreen setting, and the on-screen keyboard for text boxes\n- Browser version: map lists now also load through a second copy (jsDelivr) if the first can't be reached",
	"oct20-2026-i": "- Browser version: the online map lists now load (from copies the browser is allowed to read)\n- Browser version: most online maps download straight from rhythia.com's archive; maps from hosts that block browsers say so instead of failing silently",
	"oct20-2026-h": "- NEW: Chromia in the browser! Every release now also comes as a web version (Chromia-<version>-web.zip, and on GitHub Pages)\n- In the browser, picking files opens your browser's file chooser and saving a file downloads it\n- Startup no longer depends on background threads (needed for the browser)",
	"oct19-2026-q": "- The level bar in the Profile tab no longer has a background",
	"oct19-2026-p": "- Levels and Prestige (like BeatLeader): earn experience from every play, even fails; level 100 lets you Prestige. See the bar in the Profile tab\n- Time played shown in the Profile tab, and how often/how long you played each map on the map screen\n- New map list sort: most played (Filters, under stars)\n- Experimental: Random Colorset - a random colorset every time you start a map (your own one comes back in the menu)",
	"oct19-2026-o": "- Colorset Maker: add as many colors as you want (they wrap into rows)\n- Mesh Builder: give meshes a name, save as many as you want (New mesh), edit any saved one (Edit on its card in the Meshes tab) and delete them\n- Meshes tab: Rename any other mesh\n- Custom BG Color (World & Cursor): a solid color for the Custom Background world, or a tint over your image",
	"oct19-2026-n": "- Fixed starting a map freezing (Not Responding) while star ratings were being worked out in the background: maps now only wait if that exact map is being read, and giant maps (100k+ notes) are no longer star-rated\n- Fixed the Modifiers block being off-center / overlapping Best Attempt when the game first opens",
	"oct19-2026-m": "- The Update Log shows the notes for the last few updates again",
	"oct19-2026-l": "- Big bug sweep:\n- Settings changed right before quitting are saved again (they were lost on Windows)\n- Fixed hangs: broken map files at song start, bad values in settings.json at startup, cut-off replay files, short replays, the map list staying empty after a song with the server down\n- Star ratings are 10-50x faster on big/spam maps, and colorsets load in a blink instead of seconds\n- Online maps no longer disappear after Reload Content\n- Music stays in sync after unpausing when you use a music offset\n- Hit/miss effects in 360 mode show at the right spot; Exponential hit FOV no longer goes crazy\n- Replays: pause works with one press; failed replay files no longer spam errors\n- Random map no longer scrolls back to the last clicked map; menu loads faster (stats aren't rebuilt every time)\n- Meshes tab: imports from the meshes folder aren't deleted, .OBJ files load, builder picture updates; Max FPS mode really removes the cap\n- Lobby: no more stuck Connecting/Uploading, notes read safely when a match starts\n- Lots of smaller fixes",
	"oct19-2026-k": "- Meshes tab: the Favorite tab is now the Mesh Builder, and starred meshes are shown first in the list\n- Long mesh names end in ... instead of being cut off on both sides",
	"oct19-2026-j": "- New Meshes tab (replaces the Note Builder tab): every note mesh as a 3D picture, search, favorites, click to use one\n- Build opens the Note Builder right inside the Meshes tab\n- Import .obj meshes from the Meshes tab\n- Custom .obj meshes without a .mtl file now actually load in game (they used to fall back to Rounded), and meshes exported facing the wrong way are no longer invisible",
	"oct19-2026-i": "- Faster map loading: custom images (background, note, cursor...) are only decoded once instead of every song, and colorsets are no longer re-read every time a map starts\n- Hit/miss effects are stored as CPU particles (no more GPU particle shader being built and thrown away at every song start, which could crash)\n- The log shows how long each step of starting a map takes",
	"oct19-2026-h": "- Fixed lag while playing with Rainbow HUD + Attach Timer to Grid (an error every frame)\n- Loading a map no longer writes hundreds of colorset lines to the log",
	"oct19-2026-g": "- Fixed maps taking forever to load: starting a map waited for a background star rating to finish (minutes on huge maps). Star ratings no longer hold anything up",
	"oct19-2026-f": "- Fixed a crash when starting a map: a hidden leftover debug screen in the HUD loaded the song a second time and read its notes while the star rater could be reading them too (it is gone now, and also stops wasting FPS)\n- Star ratings pause as soon as a map starts loading\n- The log now shows every step of starting a map, so any remaining crash can be pinned down",
	"oct19-2026-e": "- Clicking a map no longer freezes/crashes the game while its star rating is worked out: it now happens in the background (the stars show as ... for a moment)\n- Maps whose star rating crashed the game are never rated again\n- The game log (godot.log) is now written right away, so crash logs show what happened",
	"oct19-2026-d": "- Fixed the game crashing while loading in (online maps were added to the map list from a background thread)\n- Online maps load much faster at startup\n- Hit/miss effects use CPU particles (GPU particles crash some graphics drivers)\n- Experimental: Realistic Autoplay (autoplay moves like a person)\n- Bigger Start button and score History\n- Stats tab matches the rest of the Profile panel\n- Fixed the Chromia logo being cut off",
	"oct19-2026-a": "- Fixed crashes/hangs when quitting the game (also when quitting during loading)\n- Fixed crashes from clicking Random Map or the sidebar very fast\n- Fixed a crash when star ratings were being calculated for a map you selected\n- Song previews wait until you stop on a map, so fast clicking stays smooth",
	"oct18-2026-z": "- Added Waves Classic: the earlier Waves background with the map cover in the sky",
	"oct18-2026-y": "- Official Chromia logo for the game icon\n- Discord status shows the Chromia logo",
	"oct18-2026-x": "- Furria is now Chromia! New name and logo\n- All 12 Rhythia backgrounds rebuilt from Rhythia's original files\n- New Hard Mode mod: smaller notes with a smaller hitbox\n- New Flashlight mod: only a circle around your cursor is visible\n- Strobe and Chaos no longer speed up with the speed mod",
	"oct18-2026-w": "- Better FPS in-game: hidden HUD panels aren't redrawn, the timer only redraws when it changes, faster note updates",
	"oct18-2026-v": "- Each map shows its RP (for the speed you picked) and your best RP on it",
	"oct18-2026-u": "- Star ratings now use the exact SSQE+ / Rhythia formula (all maps get re-rated once)",
	"oct18-2026-t": "- New offline RP (Rhythia Points): earned from passes, works while servers are down\n- RP total and your top 10 RP plays in the Profile tab",
	"oct18-2026-s": "- Map folders show up as filters under stars\n- The Grid background has its own preview picture",
	"oct18-2026-r": "- Map list scrolling is back to how it was\n- Modifier checkboxes sit between the slowest and fastest speed buttons",
	"oct18-2026-q": "- Smooth map list scrolling at the top and bottom of the list\n- Modifier checkboxes line up with the speed buttons",
	"oct18-2026-p": "- Fixed scrolling getting stuck near the top or bottom of the map list\n- Every modifier row is centered under the title",
	"oct18-2026-o": "- Modifiers are properly centered under the title",
	"oct18-2026-n": "- Fixed the map list leaving a gap at the bottom with short lists\n- Modifiers are now centered",
	"oct18-2026-m": "- New <<<< speed modifier (0.69x)\n- Map list no longer leaves a big empty gap above the first map",
	"oct18-2026-l": "- Rank Map button moved to the top bar, left of Search (only shows while a map is open)\n- New Check for Updates button at the top of Settings",
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
signal selected_hit_effect_changed
signal selected_miss_effect_changed
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
var favorite_colorsets: Array = [] # colorset ids, shown first in the colorset picker
var favorite_meshes: Array = [] # note mesh ids starred in the Meshes tab
# Custom Background world: solid color without an image, tint with one (white = no change)
var custombg_color: Color = Color(1, 1, 1)
var selected_song: Song
var selected_mesh: NoteMesh
var selected_hit_sound: NamedSound
var selected_miss_sound: NamedSound
var selected_hit_effect: NoteEffect
var selected_miss_effect: NoteEffect
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
func select_hit_effect(effect: NoteEffect):
	if effect:
		selected_hit_effect = effect
		emit_signal("selected_hit_effect_changed", effect)
func select_miss_effect(effect: NoteEffect):
	if effect:
		selected_miss_effect = effect
		emit_signal("selected_miss_effect_changed", effect)
func select_world(world: BackgroundWorld):
	if world:
		selected_space = world
		emit_signal("selected_space_changed", world)
func select_mesh(mesh: NoteMesh):
	if mesh == null:
		return # never leave the game without a note mesh
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
			var err_text: String = str(result.error)
			var options := [{text = "OK"}]
			if Online.is_embedded():
				options.append({text = "Open full version"})
			Globals.confirm_prompt.open(
				("Failed to download map.\n%s" if err_text.length() > 24 else "Failed to download map.\nError code: %s") % err_text,
				"Error",
				options
			)
			var picked = yield(Globals.confirm_prompt, "option_selected")
			if picked == 1:
				OS.shell_open(Online.WEB_FULL_URL)
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

const STAR_CACHE_FILE = "user://caches/star_ratings.json"
const STAR_CACHE_VERSION = 3
const STAR_CURRENT_FILE = "user://caches/star_rating_current.txt"
var _star_progress: int = 0
var _star_total: int = 0
var _star_done: bool = true
var _star_paused: bool = false # set while playing so gameplay isn't slowed
var _star_thread: Thread
var _star_cache: Dictionary = {}
signal star_ratings_updated

# Rates maps one by one in the background after the menu is open.
# Progress is saved every 100 maps, and the map being rated is written to a
# marker file first: if the game ever crashes on a map, that map is skipped
# on the next launch instead of crashing again.
func _star_rating_worker(songs: Array):
	var f := File.new()
	for i in range(songs.size()):
		while (_star_paused or in_map) and not _star_quit:
			OS.delay_msec(200)
		if _star_quit:
			break
		var song = songs[i]
		var id := String(song.id)
		if f.open(Globals.p(STAR_CURRENT_FILE), File.WRITE) == OK:
			f.store_string(id)
			f.close()
		# (only maps that take a while are logged, and progress every 200 maps:
		# a line per map filled the crash report and pushed out what happened)
		var t0 := OS.get_ticks_msec()
		_rate_one(song)
		var took: int = OS.get_ticks_msec() - t0
		if took > 250:
			trail("star rated %s (%d ms)" % [id, took])
		if (i + 1) % 200 == 0:
			trail("star rating: %d / %d maps" % [i + 1, songs.size()])
		_star_cache[id] = [song._star_rating, _star_cache_key(song)]
		_star_progress = i + 1
		if _star_progress % 100 == 0:
			_save_star_cache(_star_cache)
	_save_star_cache(_star_cache)
	Directory.new().remove(Globals.p(STAR_CURRENT_FILE))
	_star_done = true
	call_deferred("_star_rating_finished")

var _star_quit: bool = false

# Kept separate so a bad map only aborts this call, not the whole loop.
func _rate_one(song):
	song.get_star_rating()

func _star_rating_finished():
	# _star_done: not a newer rater (started by Reload Content) that is still running
	if _star_done and _star_thread and _star_thread.is_active():
		_star_thread.wait_to_finish()
		_star_thread = null
	print("[stars] rated %d maps" % _star_progress)
	emit_signal("star_ratings_updated")

var _thumb_running: bool = false
var _quitting: bool = false
var star_mutex := Mutex.new() # (old global lock, no longer used for note reads)

# Per-map note lock: two threads must never read the SAME map's notes at once,
# but reading different maps is fine. The old single lock made starting a song
# wait for whatever map the background star rater was reading (minutes for a
# 750k-note map). Now a song start only waits if the rater is on that same map.
var _notes_busy := {}
var _notes_busy_mutex := Mutex.new()
func lock_song_notes(song):
	if song == null:
		return
	while true:
		_notes_busy_mutex.lock()
		if not _notes_busy.has(song):
			_notes_busy[song] = true
			_notes_busy_mutex.unlock()
			return
		_notes_busy_mutex.unlock()
		OS.delay_msec(2)
func unlock_song_notes(song):
	if song == null:
		return
	_notes_busy_mutex.lock()
	_notes_busy.erase(song)
	_notes_busy_mutex.unlock()

# Maps with this many notes or more aren't star-rated (reading/rating them takes minutes).
const STAR_MAX_NOTES = 100000

# Song start timing for the log: "[start +123ms] step". Reset when a song starts loading.
var _start_t0: int = 0
func start_log(msg: String, reset: bool = false):
	if reset or _start_t0 == 0:
		_start_t0 = OS.get_ticks_msec()
	print("[start +%dms] %s" % [OS.get_ticks_msec() - _start_t0, msg])
	trail("song start +%dms: %s" % [OS.get_ticks_msec() - _start_t0, msg])

# Star rating for a map you click that isn't rated yet: worked out on its own
# thread so the menu never freezes (big maps take seconds in GDScript), then
# star_rating_ready is emitted. A marker file names the map while it's being
# rated; if the game dies there, that map is never rated again (see startup).
const STAR_CLICK_FILE = "user://caches/star_rating_click.txt"
signal star_rating_ready(song)
var _star_req_thread: Thread = null
var _star_req_pending = null

func request_star_rating(song):
	if song == null or _quitting or _star_paused or in_map or song.star_rating_known():
		return
	if song.is_online and (song.filePath == null or song.filePath == "" or not File.new().file_exists(song.filePath)):
		return
	if _star_req_thread != null:
		_star_req_pending = song
		return
	var f := File.new()
	if f.open(Globals.p(STAR_CLICK_FILE), File.WRITE) == OK:
		f.store_string(String(song.id))
		f.close()
	_star_req_thread = Thread.new()
	if not OS.can_use_threads() or _star_req_thread.start(self, "_star_req_worker", song, Thread.PRIORITY_LOW) != OK:
		_star_req_thread = null

func _star_req_worker(song):
	trail("star rating %s (clicked)" % String(song.id))
	_rate_one(song)
	trail("star rated %s (clicked)" % String(song.id))
	call_deferred("_star_req_done", song)

func _star_req_done(song):
	if _star_req_thread != null and _star_req_thread.is_active():
		_star_req_thread.wait_to_finish()
	_star_req_thread = null
	Directory.new().remove(Globals.p(STAR_CLICK_FILE))
	if _quitting:
		return
	emit_signal("star_rating_ready", song)
	if _star_req_pending != null:
		var next = _star_req_pending
		_star_req_pending = null
		request_star_rating(next)

func _notification(what):
	if what == MainLoop.NOTIFICATION_WM_QUIT_REQUEST:
		quit_game()
	elif what == MainLoop.NOTIFICATION_APP_PAUSED:
		# phones: the app went to the background; the system may close it
		# from there without telling us, which isn't a crash
		trail("app paused (in background)")
		_set_session_state("paused")
	elif what == MainLoop.NOTIFICATION_APP_RESUMED:
		_set_session_state("running")
		trail("app resumed")
		# back from logging in to Discord in the browser: check right away
		if _discord_login_timer != null and not _discord_login_timer.is_stopped():
			call_deferred("_poll_discord_login")
	elif dev == "mobile" and what == MainLoop.NOTIFICATION_WM_FOCUS_OUT:
		# phones: the app switcher / swiping the app away. It can be closed
		# from there without going to the background first: not a crash
		trail("app lost focus")
		_set_session_state("paused")
	elif dev == "mobile" and what == MainLoop.NOTIFICATION_WM_FOCUS_IN:
		_set_session_state("running")
		trail("app focused")

# --- Crash trail ----------------------------------------------------------------
# A short record of what the game is doing (screens, songs starting and ending,
# a heartbeat while playing), written to user://logs/trail.txt and flushed every
# line so it survives a crash. If the last session didn't close normally, the
# menu shows its last lines with a "Copy report" button.
const TRAIL_FILE := "user://logs/trail.txt"
const TRAIL_PREV_FILE := "user://logs/trail_prev.txt"
const SESSION_FILE := "user://logs/session_state.txt"
var last_session_crashed: bool = false
var last_session_trail: String = ""
var crash_report_shown: bool = false
var _pending_update_notice: String = "" # iOS: an update was downloaded at startup
var _trail_file: File = null
var _trail_mutex := Mutex.new()
var _trail_lines: int = 0
var _heartbeat: Timer = null

func _set_session_state(state: String):
	var f := File.new()
	if f.open(Globals.p(SESSION_FILE), File.WRITE) == OK:
		f.store_string(state)
		f.close()

func _trail_start():
	var d := Directory.new()
	var logs := Globals.p("user://logs")
	if not d.dir_exists(logs):
		d.make_dir_recursive(logs)
	var f := File.new()
	var state := ""
	if f.open(Globals.p(SESSION_FILE), File.READ) == OK:
		state = f.get_as_text().strip_edges()
		f.close()
	if f.file_exists(Globals.p(TRAIL_FILE)):
		if f.open(Globals.p(TRAIL_FILE), File.READ) == OK:
			last_session_trail = f.get_as_text()
			f.close()
		d.remove(Globals.p(TRAIL_PREV_FILE))
		d.rename(Globals.p(TRAIL_FILE), Globals.p(TRAIL_PREV_FILE))
	last_session_crashed = state == "running" and last_session_trail.strip_edges() != ""
	last_session_engine_log = _previous_engine_log(40)
	if last_session_crashed:
		_save_crash_report()
	_set_session_state("running")
	_trail_file = File.new()
	if _trail_file.open(Globals.p(TRAIL_FILE), File.WRITE) != OK:
		_trail_file = null
	trail("started %s on %s %s" % [ProjectSettings.get_setting("application/config/version"), OS.get_name(), OS.get_model_name()])
	_heartbeat = Timer.new()
	_heartbeat.wait_time = 10
	_heartbeat.pause_mode = PAUSE_MODE_PROCESS
	_heartbeat.connect("timeout", self, "_on_heartbeat")
	add_child(_heartbeat)
	_heartbeat.start()

func _on_heartbeat():
	if in_map:
		var sp = get_tree().current_scene.find_node("Spawn", true, false) if get_tree().current_scene else null
		trail("playing %s at %s ms" % [selected_song.id if selected_song else "?", int(sp.ms) if sp != null and "ms" in sp else -1])

# Safe from any thread.
func trail(msg: String):
	if _trail_file == null:
		return
	_trail_mutex.lock()
	if _trail_lines > 4000: # keep the file small on long sessions
		_trail_file.close()
		_trail_file.open(Globals.p(TRAIL_FILE), File.WRITE)
		_trail_lines = 0
	_trail_lines += 1
	_trail_file.store_line("[%7.1fs | objs %d | vram %d MB] %s" % [
		OS.get_ticks_msec() / 1000.0,
		Performance.get_monitor(Performance.OBJECT_COUNT),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576),
		msg])
	_trail_file.flush()
	_trail_mutex.unlock()

# Writes a line after each of the next `n` frames is drawn (song start uses it:
# tells a crash while drawing apart from one in game code).
var _trail_frames_left: int = 0
func trail_frames(n: int):
	_trail_frames_left = n
	if not VisualServer.is_connected("frame_post_draw", self, "_on_trail_frame_drawn"):
		VisualServer.connect("frame_post_draw", self, "_on_trail_frame_drawn")

func _on_trail_frame_drawn():
	if _trail_frames_left <= 0:
		return
	_trail_frames_left -= 1
	trail("frame drawn")

func _trail_close(how: String):
	trail(how)
	_set_session_state("closed")

# Crash reports are kept (newest 5) in user://logs/crashes, so they can be sent
# later (Settings > Crash Reports), e.g. when there was no internet.
const CRASH_DIR := "user://logs/crashes"
func _save_crash_report():
	var d := Directory.new()
	var dir := Globals.p(CRASH_DIR)
	if not d.dir_exists(dir):
		d.make_dir_recursive(dir)
	var f := File.new()
	if f.open(dir.plus_file("crash_%d.txt" % OS.get_unix_time()), File.WRITE) == OK:
		f.store_string(crash_report(120))
		f.close()
	var all := saved_crash_reports()
	for i in range(5, all.size()):
		d.remove(all[i])

# Paths of the saved crash reports, newest first.
func saved_crash_reports() -> Array:
	var out := []
	var d := Directory.new()
	if d.open(Globals.p(CRASH_DIR)) != OK:
		return out
	d.list_dir_begin(true, true)
	var n := d.get_next()
	while n != "":
		if n.begins_with("crash_") and n.ends_with(".txt"):
			out.append(Globals.p(CRASH_DIR).plus_file(n))
		n = d.get_next()
	d.list_dir_end()
	out.sort()
	out.invert()
	return out

func crash_report(lines: int = 60) -> String:
	var all := last_session_trail.strip_edges().split("\n")
	var tail := []
	for i in range(max(0, all.size() - lines), all.size()):
		tail.append(all[i])
	var out := "Chromia crash report (%s, %s %s)\n%s" % [
		ProjectSettings.get_setting("application/config/version"), OS.get_name(), OS.get_model_name(),
		PoolStringArray(tail).join("\n")]
	if last_session_engine_log != "":
		out += "\n--- engine log (last lines) ---\n" + last_session_engine_log
	return out

# The engine's own log of the last session (errors and warnings from Godot,
# which the trail doesn't have). Godot keeps the current one as godot.log and
# renames the previous ones to godot<date>.log when it starts.
var last_session_engine_log: String = ""
func _previous_engine_log(lines: int) -> String:
	var d := Directory.new()
	var logs := Globals.p("user://logs")
	if d.open(logs) != OK:
		return ""
	var newest := ""
	d.list_dir_begin(true, true)
	var fn := d.get_next()
	while fn != "":
		if fn.begins_with("godot") and fn.ends_with(".log") and fn != "godot.log" and fn > newest:
			newest = fn
		fn = d.get_next()
	d.list_dir_end()
	if newest == "":
		return ""
	var f := File.new()
	if f.open(logs.plus_file(newest), File.READ) != OK:
		return ""
	var all := f.get_as_text().strip_edges().split("\n")
	f.close()
	var keep := []
	for i in range(all.size() - 1, -1, -1):
		var l := String(all[i]).strip_edges()
		if l == "" or l.find("getaddrinfo") != -1 or l.find("_resolve_hostname") != -1 or l.find("TLS handshake") != -1 or l.find("_do_handshake") != -1:
			continue
		keep.push_front(l)
		if keep.size() >= lines:
			break
	return PoolStringArray(keep).join("\n")

# The one way the game closes (quit buttons, the quit key, the window's X).
# Background work (map import, star ratings, thumbnails) is told to stop and
# given a moment to finish (settings already save as they change), then the process exits
# directly. Letting the engine tear everything down while those threads (or
# a Discord status update) are still running is what crashed or hung on quit.
func quit_game():
	if _quitting:
		return
	_quitting = true
	print("[quit] closing")
	_trail_close("quit")
	# OS.kill below skips _exit_tree, which is where the settings page saves:
	# without this, settings changed before quitting were lost.
	if first_init_done:
		load("res://scripts/game/SoundSpaceMode.gd").end_song() # your settings, not Sound Space Mode's
		save_settings()
	_star_quit = true
	_thumb_quit = true
	var deadline := OS.get_ticks_msec() + 1500
	while OS.get_ticks_msec() < deadline and (not _star_done or _thumb_running or (not _sspm_import_done and _sspm_import_progress > 0)):
		OS.delay_msec(10)
	if _star_done and _star_thread and _star_thread.is_active():
		_star_thread.wait_to_finish()
		_star_thread = null
	if not _thumb_running and _thumb_thread and _thumb_thread.is_active():
		_thumb_thread.wait_to_finish()
		_thumb_thread = null
	# Quitting while a map is still being rated isn't a crash: remove the
	# markers, or that map would be skipped as "crashed the rater" forever.
	var markers := Directory.new()
	markers.remove(Globals.p(STAR_CURRENT_FILE))
	markers.remove(Globals.p(STAR_CLICK_FILE))
	if OS.has_feature("Windows"):
		OS.kill(OS.get_process_id())
	get_tree().quit()

func _exit_tree():
	_star_quit = true
	_thumb_quit = true
	if _thumb_thread and _thumb_thread.is_active():
		_thumb_thread.wait_to_finish()
	if _star_thread and _star_thread.is_active():
		_star_thread.wait_to_finish()

# Built from data already in memory (no disk access), so checking thousands
# of maps at startup is instant. A changed map almost always changes its note
# count or length.
func _star_cache_key(song) -> String:
	var path: String = String(song.filePath) if song.filePath != null else ""
	return "%d:%s:%d:%d" % [STAR_CACHE_VERSION, path.get_file(), int(song.note_count), int(song.last_ms)]

func _load_star_cache() -> Dictionary:
	var f := File.new()
	if f.open(Globals.p(STAR_CACHE_FILE), File.READ) != OK:
		return {}
	var text := f.get_as_text()
	f.close()
	# Older versions could save "nan" for a broken rating, which made the whole
	# file unreadable (so every map was re-rated each launch).
	var res := JSON.parse(text.replace("nan", "-1").replace("inf", "-1"))
	return res.result if res.error == OK and res.result is Dictionary else {}

func _save_star_cache(cache: Dictionary):
	Directory.new().make_dir_recursive(Globals.p(STAR_CACHE_FILE).get_base_dir())
	var f := File.new()
	if f.open(Globals.p(STAR_CACHE_FILE), File.WRITE) == OK:
		f.store_string(to_json(cache))
		f.close()

var sort_by_stars: bool = false
var sort_by_plays: bool = false # map list: most played first
var random_colorset: bool = false # experimental: a random colorset every time a map starts
var _colorset_before_random = null

# Experimental "Random Colorset": just for this play; your own pick comes back
# in the menu (menuload.gd), so it's never saved over.
func pick_random_colorset():
	if not random_colorset or replaying or registry_colorset == null:
		return
	var sets: Array = registry_colorset.get_items()
	var ok := []
	for c in sets:
		if c is ColorSet and c.colors.size() > 0:
			ok.append(c)
	if ok.empty():
		return
	if _colorset_before_random == null:
		_colorset_before_random = selected_colorset
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	selected_colorset = ok[rng.randi_range(0, ok.size() - 1)]
	print("[colorset] random: ", selected_colorset.name)

func restore_colorset_after_random():
	if _colorset_before_random != null:
		selected_colorset = _colorset_before_random
		_colorset_before_random = null

var _cover_preload_progress: int = 0
var _cover_preload_done: bool = false

# Only the most recently shown thumbnails stay in memory.
const THUMB_MEMORY_LIMIT = 300
var _thumb_lru: Array = []
func touch_thumb(song):
	var i = _thumb_lru.find(song)
	if i != -1:
		if i == _thumb_lru.size() - 1:
			return
		_thumb_lru.remove(i)
	_thumb_lru.append(song)
	while _thumb_lru.size() > THUMB_MEMORY_LIMIT:
		var old = _thumb_lru.pop_front()
		old._thumb = null

# Builds missing cover thumbnails after the menu is up, one map at a time,
# paused while playing. Already-built ones are skipped instantly. Maps shown
# in the list that still lack one are moved to the front of the queue.
var _thumb_thread: Thread
var _thumb_quit: bool = false
var _thumb_priority: Array = []
var _thumb_mutex := Mutex.new()
signal thumbs_ready

func request_thumb(song):
	_thumb_mutex.lock()
	if _thumb_priority.find(song) == -1:
		_thumb_priority.append(song)
	_thumb_mutex.unlock()
	if _thumb_thread == null or not _thumb_thread.is_active():
		_start_thumb_builder(false)

func _pop_priority_thumb():
	_thumb_mutex.lock()
	var s = _thumb_priority.pop_front() if not _thumb_priority.empty() else null
	_thumb_mutex.unlock()
	return s
# The builder thread checks the list through this (the menu adds to it at the same time).
func _has_priority_thumbs() -> bool:
	_thumb_mutex.lock()
	var r := not _thumb_priority.empty()
	_thumb_mutex.unlock()
	return r
func _start_thumb_builder(full: bool = true):
	if _thumb_thread != null and _thumb_thread.is_active():
		return
	var list: Array = []
	if full:
		for song in registry_song.get_items():
			if song.has_cover and not song.is_online:
				list.append(song)
	if list.empty() and _thumb_priority.empty():
		return
	_thumb_thread = Thread.new()
	if not OS.can_use_threads() or _thumb_thread.start(self, "_thumb_builder_worker", list, Thread.PRIORITY_LOW) != OK:
		_thumb_thread = null

func _thumb_builder_worker(list: Array):
	_thumb_running = true
	# One folder listing instead of checking each thumbnail file separately.
	var have := {}
	var d := Directory.new()
	if d.open(Globals.p(Song.THUMB_DIR)) == OK:
		d.list_dir_begin(true, true)
		var fn := d.get_next()
		while fn != "":
			have[fn] = true
			fn = d.get_next()
		d.list_dir_end()
	var built := 0
	var i := 0
	while i < list.size() or _has_priority_thumbs():
		while in_map and not _thumb_quit:
			OS.delay_msec(200)
		if _thumb_quit:
			break
		var wanted = _pop_priority_thumb()
		if wanted != null:
			if wanted.build_thumb_file(false) != null:
				built += 1
			call_deferred("emit_signal", "thumbs_ready")
			continue
		if not have.has(list[i]._thumb_path().get_file()):
			if list[i].build_thumb_file(false) != null:
				built += 1
		i += 1
	_thumb_running = false
	call_deferred("_thumb_builder_finished", built)

func _thumb_builder_finished(built: int):
	if _thumb_thread and _thumb_thread.is_active():
		_thumb_thread.wait_to_finish()
		_thumb_thread = null
	print("[covers] built %d new cover thumbnails" % built)
	# Requests that arrived while the builder was finishing.
	if not _thumb_priority.empty():
		_start_thumb_builder(false)
func _decode_covers_worker(songs: Array):
	for i in range(songs.size()):
		var song = songs[i]
		var img = song._decode_cover_pixels()
		song._cover_mutex.lock()
		song._decoded_cover_image = img
		song._cover_mutex.unlock()
		_cover_preload_progress = i + 1
	_cover_preload_done = true

var _sspm_import_progress: int = 0
var _sspm_import_done: bool = false
# Maps loaded from their files this launch (path -> Song, or null if the file
# couldn't be read). Duplicates and broken files aren't in the map list, so
# they're added to the cache from here; otherwise they'd be re-read (and the
# whole cache rewritten) on every launch.
var _loaded_from_file: Dictionary = {}
var map_cache_dirty: bool = false
const MAP_SEARCH_DEPTH := 12 # folders deep in the maps folder(s)
const MAP_REPORT_FILE := "user://logs/map_report.txt"

func _make_full_sspm_cache(v: int) -> Dictionary:
	var cache_dict = registry_song.make_sspm_cache(v)
	for path in _loaded_from_file.keys():
		if not cache_dict.has(path):
			var ls = _loaded_from_file[path]
			cache_dict[path] = ls.make_cache() if ls != null else {"invalid": true, "mtime": File.new().get_modified_time(path),
				"ver": String(ProjectSettings.get_setting("application/config/version")), "why": _skip_reason(path)}
	_loaded_from_file.clear()
	return cache_dict
# A file that couldn't be read last time, unchanged, with this game version
# (an update may read it now, so it's tried again then).
func _known_unreadable(cached, path: String) -> bool:
	return cached is Dictionary and cached.get("invalid", false) \
		and int(cached.get("mtime", 0)) == File.new().get_modified_time(path) \
		and String(cached.get("ver", "")) == String(ProjectSettings.get_setting("application/config/version"))

func _skip_reason(path: String) -> String:
	for e in registry_song.skipped:
		if e[0] == path:
			return e[1]
	return "couldn't be read"

# Map files that aren't in your map list, and why: written to
# logs/map_report.txt, with a message if there are any.
func _report_skipped_maps():
	var list: Array = registry_song.skipped
	if list.empty():
		Directory.new().remove(Globals.p(MAP_REPORT_FILE))
		return
	var f := File.new()
	if f.open(Globals.p(MAP_REPORT_FILE), File.WRITE) == OK:
		f.store_line("Map files Chromia didn't add to your map list (%d):" % list.size())
		for e in list:
			f.store_line("%s\n    %s" % [e[0], e[1]])
		f.close()
	var copies := 0
	for e in list:
		if String(e[1]).begins_with("a copy of"):
			copies += 1
	var unreadable: int = list.size() - copies
	var parts := []
	if unreadable > 0:
		parts.append("%d map file%s couldn't be read" % [unreadable, "" if unreadable == 1 else "s"])
	if copies > 0:
		parts.append("%d %s copies of maps you already have" % [copies, "is a" if copies == 1 else "are"])
	var msg: String = PoolStringArray(parts).join(", and ")
	msg = msg.substr(0, 1).to_upper() + msg.substr(1)
	Globals.call_deferred("notify", Globals.NOTIFY_WARN if unreadable > 0 else Globals.NOTIFY_INFO,
		"%s. The list is in logs/map_report.txt in your user folder (Settings > Open User Folder)." % msg, "Maps")

func _import_sspm_worker(args: Array) -> Array:
	var smaps: Array = args[0]
	var caches: Dictionary = args[1]
	var from_cache = 0
	var from_file = 0
	for i in range(smaps.size()):
		if _quitting:
			break
		_sspm_import_progress = i + 1
		var single_map_start = OS.get_ticks_usec()
		var cached = caches.get(smaps[i])
		if _known_unreadable(cached, smaps[i]):
			from_cache += 1 # known unreadable file (this version), skip it
			registry_song.skipped.append([smaps[i], String(cached.get("why", "couldn't be read"))])
		elif cached != null and not (cached is Dictionary and cached.get("invalid", false)):
			if registry_song.add_sspm_cached_map(smaps[i], cached):
				from_cache += 1
			else:
				print("Failed loading a map from cache")
				from_file += 1
				registry_song.add_sspm_map(smaps[i])
		else:
			from_file += 1
			_loaded_from_file[smaps[i]] = registry_song.add_sspm_map(smaps[i])
		var single_map_usec = OS.get_ticks_usec() - single_map_start
		if single_map_usec > 1000000:
			print("SLOW MAP LOAD (%s usec): %s" % [Globals.comma_sep(single_map_usec), smaps[i]])
	_sspm_import_done = true
	return [from_cache, from_file]
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
var vr_player = null # VRPlayer (vr/VRPlayer.tscn), made by start_vr
# VR controller grip (Settings > VR): the pointer's angle in degrees (x tilt up /
# down, y left / right, z roll) and offset in cm, for the right hand; the left
# hand is mirrored
var vr_grip_rot := Vector3.ZERO
var vr_grip_pos := Vector3.ZERO
# the VR menu screen (vr/MenuPointer.gd, Settings > VR)
var vr_menu_size: float = 100.0    # degrees of your view it spans
var vr_menu_distance: float = 1.6  # metres away
var vr_menu_curve: bool = true     # curved around you
var vr_menu_ui: float = 100.0      # % size of the menu's text and buttons on the screen
# how far the note grid (where the notes come from) is from you in songs, in metres
var vr_grid_distance: float = 2.25
# VR aim: how far the cursor moves for how far you turn the controller (1 =
# exactly where you point)
var vr_sensitivity: float = 1.0
# controller rumble on hits (0..1) and on misses
var vr_haptics: float = 0.5
var vr_haptic_miss: bool = true
# the hands: "default" (box), "paw" (built-in furry paw), "custom" (vr_hand.obj)
var vr_hand: String = "default"
# VR graphics (vr/VRPlayer.gd apply_xr_settings): Meta Quest foveated rendering
# 0 off .. 3 high, display refresh rate (0 = the headset's own), render
# resolution (applies when VR starts) and glow (-1 = off on Quest, on on PC)
var vr_foveation: int = 2
var vr_refresh: float = 0.0
var vr_render_scale: float = 1.0
var vr_glow: int = -1
var vr_simple_bg: bool = false # VR songs on the plain VOID background
# the pointer beam (vr/Pointer.gd): thickness (x the default), colour, rainbow
var vr_beam_width: float = 1.0
var vr_beam_color: Color = Color(0, 1, 1, 0.63)
var vr_beam_rainbow: bool = false
# in songs the beam ends on the cursor (kept inside the grid) instead of
# going on past the grid's edges
var vr_lock_beam: bool = false
var vr_xr_config = null # the OpenXR plugin's settings object (Quest)
# VR controller buttons (Settings > VR): action -> up to two button numbers
var vr_binds := {}
const VR_BUTTONS := [["Trigger", 15], ["Grip", 2], ["A / X", 7], ["B / Y", 1], ["Thumbstick press", 14], ["Menu", 3]]
const VR_ACTIONS := [["vr_click", "Click / select"], ["pause", "Pause"], ["give_up", "Give up (hold)"], ["retry", "Retry"], ["vr_recenter", "Recenter"], ["vr_switch_hands", "Switch hands"]]
const VR_DEFAULT_BINDS := {"vr_click": [15], "pause": [14, 1], "give_up": [2], "retry": [], "vr_recenter": [7], "vr_switch_hands": [3]}
var vr_menu = null   # the menu screen in VR (vrmenu.tscn PointerScreen)


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

# The menu music: these songs play one after another in a random order
# (scripts/ui/menu/buttons/PlaySong.gd). Every song plays once before any
# repeats, and a new round never starts with the song that just played. The
# order carries on when you come back to the menu after a song. A custom menu
# song (user://menu.ogg / .mp3 / .wav) replaces the list and loops, as before.
const MENU_PLAYLIST = [
	"res://assets/sfx/music/menu/change_it_up.ogg",
	"res://assets/sfx/music/menu/alright.ogg",
	"res://assets/sfx/music/menu/april_fools.ogg",
	"res://assets/sfx/music/menu/blame_it.ogg",
	"res://assets/sfx/music/menu/claustroflowbic.ogg",
	"res://assets/sfx/music/menu/cudda_been.ogg",
	"res://assets/sfx/music/menu/memorex_cds.ogg",
]
var _menu_bag: Array = []
var _menu_last: String = ""
var _menu_seeded: bool = false

func next_menu_track() -> AudioStream:
	if _menu_bag.empty():
		if not _menu_seeded:
			randomize()
			_menu_seeded = true
		_menu_bag = MENU_PLAYLIST.duplicate()
		_menu_bag.shuffle()
		if _menu_bag.size() > 1 and _menu_bag[0] == _menu_last:
			_menu_bag.push_back(_menu_bag.pop_front())
	var path: String = _menu_bag.pop_front()
	_menu_last = path
	var s = load(path)
	if s is AudioStreamOGGVorbis or s is AudioStreamMP3:
		s.loop = false # the next song follows instead
	return s


var fail_asp: AudioStreamPlayer = AudioStreamPlayer.new()


var ignore_controller_detection: bool = false


var expand_hud_onhr: bool = false

var _vr_checked: bool = false

func ensure_vr_checked():
	if _vr_checked or _vr_check_thread:
		return
	if not OS.can_use_threads():
		_vr_checked = true # no VR in a browser
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
	var viewport = get_viewport()
	if OS.has_feature("quest"):
		vr_interface = ARVRServer.find_interface("OpenXR")
	if Input.is_key_pressed(KEY_SHIFT) and not OS.has_feature("quest"):
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

		if OS.has_feature("quest"):
			# the OpenXR plugin's settings: render resolution has to be set
			# before it starts, the rest (foveation, refresh rate) after
			var cfg_path0 := "res://addons/godot-openxr/config/OpenXRConfig.gdns"
			if ResourceLoader.exists(cfg_path0):
				vr_xr_config = load(cfg_path0).new()
				if vr_xr_config and vr_xr_config.has_method("set_render_target_size_multiplier"):
					vr_xr_config.set_render_target_size_multiplier(clamp(vr_render_scale, 0.5, 1.5))
		if vr_interface == null or not vr_interface.initialize():
			print("Failed to initialize VR!")
			Globals.notify(Globals.NOTIFY_ERROR, "Couldn't start VR. Make sure SteamVR is running and your headset is on, then try again.", "VR")
			return

		viewport.arvr = true
		if OS.has_feature("quest"):
			# the headset's colour space (the plugin's own config tells it)
			var cfg = vr_xr_config
			if cfg and cfg.has_method("keep_3d_linear"):
				viewport.keep_3d_linear = cfg.keep_3d_linear()

		setup_controller_bindings()
	vr = true
	trail("VR started (%s)" % ("fake" if fake_vr else vr_interface.get_name() if vr_interface else "?"))
	viewport.hdr = false
	OS.vsync_enabled = false
	# the headset paces the frames (a cap would only hold it back)
	Engine.target_fps = 0 if OS.has_feature("quest") else 720
	var vr_av = load("res://vr/VRPlayer.tscn").instance()
	rootg.add_child(vr_av)
	vr_av.name = "VRPlayer"
	vr_player = vr_av

	menu_target = "res://vr/vrmenu.tscn"
	get_tree().change_scene("res://scenes/loaders/menuload.tscn")

# The menu (menu2.tscn): at /root/Menu, or in VR on the floating screen
# (vrmenu.tscn). path is inside it ("Main/Maps/..."); "" gives the menu.
func menu_node(path: String = "") -> Node:
	var r = get_tree().root
	var m = r.get_node_or_null("Menu")
	if m == null:
		m = r.get_node_or_null("VRMenuHolder/PointerScreen/Viewport/Menu")
	if m == null or path == "":
		return m
	return m.get_node_or_null(path)

# Mouse position for menu code. In VR the menu is on its own screen and the
# window's mouse means nothing there: use where the controller points.
func menu_mouse(ci: CanvasItem) -> Vector2:
	if vr and is_instance_valid(vr_menu) and ci.get_viewport() != get_tree().root:
		return vr_menu.last_screen_pos
	return ci.get_global_mouse_position()

func setup_controller_bindings():
	apply_vr_binds()

func vr_bind(action: String) -> Array:
	var out := []
	for b in vr_binds.get(action, VR_DEFAULT_BINDS.get(action, [])):
		if int(b) >= 0 and not out.has(int(b)):
			out.append(int(b))
	return out

# Puts the VR controller buttons (vr_binds) into the input actions. Only the
# events added here (any controller, device -1) are replaced; keyboard, mouse
# and normal gamepad bindings stay.
func apply_vr_binds():
	for a in VR_ACTIONS:
		var action: String = a[0]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for ev in InputMap.get_action_list(action):
			if (ev is InputEventJoypadButton or ev is InputEventJoypadMotion) and ev.device == -1:
				InputMap.action_erase_event(action, ev)
		for b in vr_bind(action):
			var e := InputEventJoypadButton.new()
			e.device = -1 # any controller
			e.button_index = b
			InputMap.action_add_event(action, e)
			# trigger and grip also as their analog axes (a half pull counts)
			if b == JOY_VR_TRIGGER or b == JOY_VR_GRIP:
				var m := InputEventJoypadMotion.new()
				m.device = -1
				m.axis = JOY_VR_ANALOG_TRIGGER if b == JOY_VR_TRIGGER else JOY_VR_ANALOG_GRIP
				m.axis_value = 1.0
				InputMap.action_add_event(action, m)

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


# Writes how long each loading step took to the log (logs/godot.log), so slow
# startups can be tracked down.
var _stage_name: String = ""
var _stage_start: int = 0
func _log_stage(name, _extra = null):
	var now := OS.get_ticks_msec()
	var first_line := String(name).split("\n")[0]
	if first_line == _stage_name:
		return
	if _stage_name != "":
		print("[startup] %s: %d ms" % [_stage_name, now - _stage_start])
	_stage_name = first_line
	_stage_start = now

func _ready():
	detect_device()
	_trail_start()
	# iOS: a downloaded update got this far; don't throw it away if this start is cut short
	if PackUpdate.loaded_version != "":
		load("res://scripts/PackGuard.gd").started(PackUpdate.loaded_version)
	# Closing the window goes through quit_game() too (see there).
	get_tree().set_auto_accept_quit(false)
	connect("init_stage_reached", self, "_log_stage")
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
		quit_game()
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
	if not ProjectSettings.get_setting("application/config/discord_rpc"):
		return
	var activity = Discord.Activity.new()
	activity.set_type(Discord.ActivityType.Playing)
	activity.set_details("Join us Now")
	activity.set_state("discord.gg/Hs2E5w5N68")
	var assets = activity.get_assets()
	assets.set_large_image(Globals.DISCORD_ICON)
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
			Globals.SPEED_MMMM: mods.append("Speed----")
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
	if mod_hard_mode: mods.append("Hard Mode")
	if mod_flashlight: mods.append("Flashlight")
	if mod_360: mods.append(("360x%s" % Rhythia.mod_360_speed))
	if mod_strobe: mods.append(("Strobe!!!"))
	if replay.autoplayer: mods.append("Auto")

	if mods.size() == 0: txt = "No modifiers!!"
	else:
		for i in range(mods.size()):
			if i != 0: txt += ", "
			txt += mods[i]

	var activity = Discord.Activity.new()
	activity.set_type(Discord.ActivityType.Playing)
	activity.set_state(txt)
	activity.set_details(selected_song.name)

	var assets = activity.get_assets()
	assets.set_large_image(Globals.DISCORD_ICON)

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
# Hard Mode: notes are drawn smaller and their hitbox shrinks by the same amount.
const HARD_MODE_SCALE = 0.75
var mod_hard_mode: bool = false setget set_mod_hard_mode
# Flashlight: everything is dark except a circle around the cursor.
var mod_flashlight: bool = false setget set_mod_flashlight

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
func set_mod_hard_mode(v: bool):
	mod_hard_mode = v; emit_signal("mods_changed")
func set_mod_flashlight(v: bool):
	mod_flashlight = v; emit_signal("mods_changed")

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

var show_hit_effect: bool = true
var hit_effect_at_cursor: bool = true

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
var hit_fov_instant: bool = false
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
# Experimental: animated contour-line background in the menu.
signal wave_menu_changed
var wave_menu: bool = false setget _set_wave_menu
func _set_wave_menu(v: bool):
	wave_menu = v
	emit_signal("wave_menu_changed", v)
# Wave Menu option: colour the waves with the selected colorset.
signal wave_menu_colorset_changed
var wave_menu_colorset: bool = false setget _set_wave_menu_colorset
func _set_wave_menu_colorset(v: bool):
	wave_menu_colorset = v
	emit_signal("wave_menu_colorset_changed", v)


var record_replays: bool = false
var alt_cam: bool = false
var hide_replay_ui: bool = false
var show_xp_notifications: bool = true
var half_ghost_strength: float = 0.8
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
var trail_opacity: float = 1.0
# Trail gradient: list of [offset 0..1, color html]; sampled by scripts/game/TrailGradient.gd
var trail_gradient_enabled: bool = false
var trail_gradient: Array = [[0.0, "ffffffff"], [1.0, "ffc3a6cc"]] # Godot html = aarrggbb
var max_fps_mode: bool = false
# Experimental: autoplay moves the cursor like a person (scripts/cursordance/Human.gd)
var realistic_autoplay: bool = false

# Max FPS mode: uncapped frame rate, VSync off and no MSAA (anti-aliasing).
func apply_max_fps_mode():
	var vp = get_viewport()
	if max_fps_mode:
		Engine.target_fps = 0
		OS.vsync_enabled = false
		if vp:
			vp.msaa = Viewport.MSAA_DISABLED
			vp.hdr = false # HDR framebuffers cost GPU time
	elif vp:
		vp.msaa = int(ProjectSettings.get_setting("rendering/quality/filters/msaa"))
		vp.hdr = bool(ProjectSettings.get_setting("rendering/quality/depth/hdr"))
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
# Menu music vocals, 0..1 (0 = instrumental): scripts/ui/menu/MenuVocals.gd
var menu_lyric_volume: float = 1.0
# Phones: rings under the fingers (scripts/ui/TouchIndicator.gd)
var show_touch_indicator: bool = true
# Phones: Settings > "No Touch Delay" and "120 Hz" (apply_mobile_tuning)
var sound_space_mode: bool = false # Experimental: songs look like the original Sound Space
var track_plays: bool = true # PlayTracker: how you play, for the Settings Generator (stays on this device)
var ss_gameplay_only: bool = false # Sound Space Mode only for songs: the menus stay Chromia's
var always_show_crash_log: bool = false # Experimental: show the last session's log at every start, not only after a crash
# the Sound Space Mode menus (main menu, map grid, page look, modifier tiles)
func ss_menus_on() -> bool:
	return sound_space_mode and not ss_gameplay_only
var ss_score_popups: bool = true # Sound Space Mode: points pop up under the grid on each hit
var ss_health_y: float = 0.0     # Sound Space Mode: health bar moved up (+) / down (-)
var ss_health_w: float = 100.0   # Sound Space Mode: health bar width, %
var ss_progress_y: float = 0.0   # Sound Space Mode: song progress bar moved up (+) / down (-)
var ss_progress_w: float = 100.0 # Sound Space Mode: song progress bar width, %
var mobile_no_delay: bool = false setget _set_mobile_no_delay
var mobile_high_hz: bool = false setget _set_mobile_high_hz
# its look (shape, colours, trail...), only the changed keys of TouchIndicator.DEFAULTS
var touch_style: Dictionary = {}
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



# ---- Lifetime stats (shown on the Stats page) ----
const STATS_FILE = "user://stats.json"
var lifetime_stats: Dictionary = {}
var _lifetime_stats_loaded: bool = false

func _default_lifetime_stats() -> Dictionary:
	return {
		"plays": 0, "passes": 0, "fails": 0, "give_ups": 0,
		"notes_hit": 0, "notes_missed": 0, "play_time_ms": 0,
		"best_combo": 0, "first_play_ts": 0, "last_play_ts": 0,
		"map_plays": {}, "map_time": {},
	}

func get_lifetime_stats() -> Dictionary:
	if not _lifetime_stats_loaded:
		_lifetime_stats_loaded = true
		lifetime_stats = _default_lifetime_stats()
		var file := File.new()
		if file.open(Globals.p(STATS_FILE), File.READ) == OK:
			var parsed = parse_json(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				for k in parsed.keys():
					lifetime_stats[k] = parsed[k]
	return lifetime_stats

func _save_lifetime_stats():
	var file := File.new()
	if file.open(Globals.p(STATS_FILE), File.WRITE) == OK:
		file.store_string(to_json(lifetime_stats))
		file.close()

# Called by the game when a play ends (not for replays or autoplay).
func record_play_stats():
	if single_map_mode or selected_song == null:
		return
	var st := get_lifetime_stats()
	var now := OS.get_unix_time()
	st.plays = int(st.plays) + 1
	match song_end_type:
		Globals.END_PASS: st.passes = int(st.passes) + 1
		Globals.END_GIVEUP: st.give_ups = int(st.give_ups) + 1
		_: st.fails = int(st.fails) + 1
	st.notes_hit = int(st.notes_hit) + int(song_end_hits)
	st.notes_missed = int(st.notes_missed) + int(song_end_misses)
	var play_ms := int(max(0, song_end_position - start_offset) / max(Globals.speed_multi[mod_speed_level], 0.01))
	st.play_time_ms = int(st.play_time_ms) + play_ms
	st.best_combo = max(int(st.best_combo), int(song_end_combo))
	if int(st.first_play_ts) == 0:
		st.first_play_ts = now
	st.last_play_ts = now
	var id := String(selected_song.id)
	var counts: Dictionary = st.map_plays
	counts[id] = int(counts.get(id, 0)) + 1
	if not (st.get("map_time") is Dictionary):
		st.map_time = {}
	st.map_time[id] = int(st.map_time.get(id, 0)) + play_ms
	_save_lifetime_stats()
	_award_level_exp(play_ms)

# Level system (scripts/PlayerLevel.gd): experience for every play, even fails.
func _award_level_exp(play_ms: int):
	var store = preload("res://scripts/PlayerLevel.gd").get_store()
	var hits := float(song_end_hits)
	var total := hits + float(song_end_misses)
	var acc: float = hits / total if total > 0 else 0.0
	var stars: float = max(selected_song.star_rating_cached(), 0.0) if selected_song != null else 0.0
	var gained: int = store.exp_for_play(play_ms / 1000.0, stars, acc, song_end_type == Globals.END_PASS)
	if gained <= 0:
		return
	var res: Dictionary = store.add_exp(gained)
	if not show_xp_notifications:
		return
	if res.levels_up > 0:
		var txt: String = "You're now level %d!" % res.level
		if store.can_prestige():
			txt += "\nYou can Prestige in the Profile tab."
		Globals.notify(Globals.NOTIFY_INFO, txt, "Level up! (+%d EXP)" % gained)
	else:
		Globals.notify(Globals.NOTIFY_INFO, "%d / %d to level %d" % [store.cur_exp, store.required(), store.level + 1], "+%d EXP" % gained, 3)

# Summary of personal bests across all maps (from user://bests).
func get_pb_summary() -> Dictionary:
	var out := {"maps_played": 0, "maps_passed": 0, "full_combos": 0, "avg_best_accuracy": 0.0}
	var dir := Directory.new()
	if dir.open(user_best_dir) != OK:
		return out
	var acc_total := 0.0
	dir.list_dir_begin(true, true)
	var fn := dir.get_next()
	while fn != "":
		if not dir.current_is_dir():
			var best := _read_best_file(user_best_dir.plus_file(fn))
			if not best.empty():
				out.maps_played += 1
				if best.passed:
					out.maps_passed += 1
					acc_total += best.accuracy
					if best.fc:
						out.full_combos += 1
		fn = dir.get_next()
	dir.list_dir_end()
	if out.maps_passed > 0:
		out.avg_best_accuracy = acc_total / out.maps_passed
	return out

func _read_best_file(path: String) -> Dictionary:
	var file := File.new()
	if file.open(path, File.READ) != OK:
		return {}
	if file.get_buffer(5) != PoolByteArray([83, 83, 43, 112, 66]):
		file.close()
		return {}
	var sv: int = file.get_16()
	var amt: int = file.get_64()
	var result := {"passed": false, "fc": false, "accuracy": 0.0}
	for i in range(amt):
		if file.eof_reached():
			break
		file.get_line()
		var passed = bool(file.get_8())
		file.get_16()
		var hit: int = file.get_32()
		var total: int = file.get_32()
		file.get_32()
		file.get_32()
		if sv >= 3: file.get_16()
		if sv >= 4: file.get_64()
		if passed and total > 0:
			result.passed = true
			var acc := float(hit) / float(total)
			result.accuracy = max(result.accuracy, acc)
			if hit >= total:
				result.fc = true
	file.close()
	return result

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
		Globals.SPEED_MMMM: pts.append("s:----")
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
	if mod_hard_mode: pts.append("m_hardmode")
	if mod_flashlight: pts.append("m_flashlight")
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
	data.mod_hard_mode = false
	data.mod_flashlight = false
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
				"s:----": data.mod_speed_level = Globals.SPEED_MMMM
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
				"m_hardmode": data.mod_hard_mode = true
				"m_flashlight": data.mod_flashlight = true
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

		if typeof(decode.result) != TYPE_DICTIONARY:
			print("!!! settings file is not a JSON object")
			return -3
		var data: Dictionary = decode.result
		# A value of an unexpected type (hand-edited file, another version) stopped
		# the loading at that line, which also left the loading screen stuck.
		# Such values are left out so every other setting still loads.
		for k in data.keys():
			var vt := typeof(data[k])
			if vt == TYPE_NIL:
				data.erase(k)
				continue
			var is_num := vt == TYPE_BOOL or vt == TYPE_INT or vt == TYPE_REAL
			var ct := typeof(get(k)) if not k in ["vsync_enabled", "window_fullscreen", "window_borderless", "target_fps"] else TYPE_BOOL
			if (ct == TYPE_BOOL or ct == TYPE_INT or ct == TYPE_REAL) and not is_num and not (k == "edge_drift" and vt == TYPE_STRING):
				print("[settings] ignoring %s (unexpected value %s)" % [k, data[k]])
				data.erase(k)
			elif ct == TYPE_COLOR and vt != TYPE_STRING:
				print("[settings] ignoring %s (unexpected value %s)" % [k, data[k]])
				data.erase(k)
			elif k.ends_with("_volume") and not is_num and vt != TYPE_STRING:
				data.erase(k)

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
		if data.has("hit_fov_instant"):
			hit_fov_instant = bool(data.hit_fov_instant)
		if data.has("hit_fov_amplifier"):
			hit_fov_amplifier = data.hit_fov_amplifier
		if data.has("hit_fov_decay"):
			hit_fov_decay = data.hit_fov_decay
		if data.has("fade_length"):
			fade_length = data.fade_length
		# older Chromia builds always saved the hit effect settings as false; only trust them once re-added
		if data.has("show_hit_effect") and data.has("hit_effects_v2"):
			show_hit_effect = bool(data.show_hit_effect)
		if data.has("hit_effect_at_cursor") and data.has("hit_effects_v2"):
			hit_effect_at_cursor = bool(data.hit_effect_at_cursor)
		if data.has("show_miss_effect") and data.has("hit_effects_v2"):
			show_miss_effect = bool(data.show_miss_effect)
		if data.has("selected_hit_effect") and registry_effect:
			var hit_eff = registry_effect.get_item(Globals.s(data.selected_hit_effect))
			if hit_eff: select_hit_effect(hit_eff)
		if data.has("selected_miss_effect") and registry_effect:
			var miss_eff = registry_effect.get_item(Globals.s(data.selected_miss_effect))
			if miss_eff: select_miss_effect(miss_eff)
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
		if data.has("trail_opacity"):
			trail_opacity = clamp(float(data.trail_opacity), 0.0, 1.0)
		if data.has("trail_gradient_enabled"):
			trail_gradient_enabled = bool(data.trail_gradient_enabled)
		if data.has("trail_gradient") and typeof(data.trail_gradient) == TYPE_ARRAY:
			trail_gradient = data.trail_gradient
		if data.has("custombg_color") and typeof(data.custombg_color) == TYPE_STRING and data.custombg_color.is_valid_html_color():
			custombg_color = Color(data.custombg_color)
		if data.has("favorite_meshes") and typeof(data.favorite_meshes) == TYPE_ARRAY:
			favorite_meshes = []
			for fav_mesh in data.favorite_meshes:
				favorite_meshes.append(str(fav_mesh))
		if data.has("favorite_colorsets") and typeof(data.favorite_colorsets) == TYPE_ARRAY:
			favorite_colorsets = []
			for fav_id in data.favorite_colorsets:
				favorite_colorsets.append(str(fav_id))
		if data.has("realistic_autoplay"):
			realistic_autoplay = bool(data.realistic_autoplay)
		if data.has("max_fps_mode"):
			max_fps_mode = bool(data.max_fps_mode)
			if max_fps_mode: call_deferred("apply_max_fps_mode")
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

		if data.has("show_warnings"):
			show_warnings = data.show_warnings
		if data.has("record_replays"):
			should_ask_about_replays = false
			record_replays = data.record_replays
		if data.has("alt_cam"):
			alt_cam = data.alt_cam
		if data.has("hide_replay_ui"):
			hide_replay_ui = bool(data.hide_replay_ui)
		if data.has("sort_by_stars"):
			sort_by_stars = bool(data.sort_by_stars)
		if data.has("sort_by_plays"):
			sort_by_plays = bool(data.sort_by_plays)
		if data.has("random_colorset"):
			random_colorset = bool(data.random_colorset)
		if data.has("show_xp_notifications"):
			show_xp_notifications = bool(data.show_xp_notifications)
		if data.has("half_ghost_strength"):
			half_ghost_strength = clamp(float(data.half_ghost_strength), 0.1, 1.0)
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
		if data.has("wave_menu"):
			self.wave_menu = bool(data.wave_menu)
		if data.has("wave_menu_colorset"):
			self.wave_menu_colorset = bool(data.wave_menu_colorset)
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
		if data.has("show_touch_indicator"):
			show_touch_indicator = bool(data.show_touch_indicator)
		if data.has("sound_space_mode"):
			sound_space_mode = bool(data.sound_space_mode)
		if data.has("track_plays"):
			track_plays = bool(data.track_plays)
		if data.has("ss_gameplay_only"):
			ss_gameplay_only = bool(data.ss_gameplay_only)
		if data.has("always_show_crash_log"):
			always_show_crash_log = bool(data.always_show_crash_log)
		if data.has("ss_score_popups"):
			ss_score_popups = bool(data.ss_score_popups)
		for k in ["ss_health_y", "ss_health_w", "ss_progress_y", "ss_progress_w"]:
			if data.has(k):
				set(k, float(data[k]))
		if data.has("mobile_no_delay"):
			mobile_no_delay = bool(data.mobile_no_delay)
		if data.has("mobile_high_hz"):
			mobile_high_hz = bool(data.mobile_high_hz)
		if data.has("touch_style") and data.touch_style is Dictionary:
			touch_style = data.touch_style
		if data.has("vr_grip_rot") and data.vr_grip_rot is Array and data.vr_grip_rot.size() == 3:
			vr_grip_rot = Vector3(float(data.vr_grip_rot[0]), float(data.vr_grip_rot[1]), float(data.vr_grip_rot[2]))
		if data.has("vr_grip_pos") and data.vr_grip_pos is Array and data.vr_grip_pos.size() == 3:
			vr_grip_pos = Vector3(float(data.vr_grip_pos[0]), float(data.vr_grip_pos[1]), float(data.vr_grip_pos[2]))
		if data.has("vr_menu_size"):
			vr_menu_size = clamp(float(data.vr_menu_size), 40.0, 160.0)
		if data.has("vr_menu_distance"):
			vr_menu_distance = clamp(float(data.vr_menu_distance), 0.8, 4.0)
		if data.has("vr_menu_curve"):
			vr_menu_curve = bool(data.vr_menu_curve)
		if data.has("vr_menu_ui"):
			vr_menu_ui = clamp(float(data.vr_menu_ui), 60.0, 140.0)
		if data.has("vr_grid_distance"):
			vr_grid_distance = clamp(float(data.vr_grid_distance), 0.75, 5.0)
		if data.has("vr_sensitivity"):
			vr_sensitivity = clamp(float(data.vr_sensitivity), 0.25, 4.0)
		if data.has("vr_haptics"):
			vr_haptics = clamp(float(data.vr_haptics), 0.0, 1.0)
		if data.has("vr_haptic_miss"):
			vr_haptic_miss = bool(data.vr_haptic_miss)
		if data.has("vr_hand") and ["default", "paw", "custom"].has(str(data.vr_hand)):
			vr_hand = str(data.vr_hand)
		if data.has("vr_foveation"):
			vr_foveation = int(clamp(int(data.vr_foveation), 0, 3))
		if data.has("vr_refresh"):
			vr_refresh = clamp(float(data.vr_refresh), 0.0, 144.0)
		if data.has("vr_render_scale"):
			vr_render_scale = clamp(float(data.vr_render_scale), 0.5, 1.5)
		if data.has("vr_glow"):
			vr_glow = int(clamp(int(data.vr_glow), -1, 1))
		if data.has("vr_simple_bg"):
			vr_simple_bg = bool(data.vr_simple_bg)
		if data.has("vr_beam_width"):
			vr_beam_width = clamp(float(data.vr_beam_width), 0.2, 4.0)
		if data.has("vr_beam_color") and data.vr_beam_color is String:
			vr_beam_color = Color(data.vr_beam_color)
		if data.has("vr_beam_rainbow"):
			vr_beam_rainbow = bool(data.vr_beam_rainbow)
		if data.has("vr_lock_beam"):
			vr_lock_beam = bool(data.vr_lock_beam)
		if data.has("vr_binds") and data.vr_binds is Dictionary:
			vr_binds = data.vr_binds
		if data.has("menu_lyric_volume"):
			menu_lyric_volume = clamp(float(data.menu_lyric_volume), 0.0, 1.0)
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
			last_search_incl_online = bool(file.get_8())
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

# The profile picked in Settings > Select Profile. It is the source of truth:
# the game starts with it and every settings save is written back into it.
# Stored in its own file (just the profile's file name) because several
# parts of the game rewrite settings.cfg and could drop it.
const ACTIVE_PROFILE_FILE = "user://active_profile.txt"
const PROFILES_DIR = "user://profiles"

func get_active_profile_path() -> String:
	var name := ""
	var f := File.new()
	if f.open(Globals.p(ACTIVE_PROFILE_FILE), File.READ) == OK:
		name = f.get_as_text().strip_edges()
		f.close()
	else:
		# Older versions kept the full path in settings.cfg.
		var config = ConfigFile.new()
		if config.load("user://settings.cfg") == OK:
			name = String(config.get_value("profile", "active_profile_path", "")).replace("\\", "/").get_file()
	if name == "":
		return ""
	var path: String = Globals.p(PROFILES_DIR).plus_file(name)
	if not f.file_exists(path):
		return ""
	return path

func set_active_profile_path(path: String):
	var f := File.new()
	if f.open(Globals.p(ACTIVE_PROFILE_FILE), File.WRITE) == OK:
		f.store_string(path.replace("\\", "/").get_file())
		f.close()

# The settings file to read when the game starts.
func get_startup_settings_path() -> String:
	var active := get_active_profile_path()
	return active if active != "" else Globals.p("user://settings.json")

func save_settings(saveFile: String = Globals.p("user://settings.json")):
	var result = _write_settings_file(saveFile)
	if result is String and saveFile == Globals.p("user://settings.json"):
		var active := get_active_profile_path()
		if active != "" and active != saveFile:
			_write_settings_file(active)
	return result

func _write_settings_file(saveFile: String):
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
			vsync_enabled = OS.vsync_enabled,

			window_fullscreen = OS.window_fullscreen,
			window_borderless = OS.window_borderless,
			selected_colorset = (_colorset_before_random.id if _colorset_before_random != null else selected_colorset.id),
			selected_hit_sound_id = (selected_hit_sound.id if selected_hit_sound else "default"),
			selected_miss_sound_id = (selected_miss_sound.id if selected_miss_sound else "default"),
			selected_border_id = (selected_border.id if selected_border else "default"),
			selected_space = selected_space.id,
			selected_mesh = selected_mesh.id,
			parallax = parallax,
			fov = fov,
			hit_fov = hit_fov,
			hit_fov_additive = hit_fov_additive,
			hit_fov_instant = hit_fov_instant,
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
			show_hit_effect = show_hit_effect,
			show_miss_effect = show_miss_effect,
			hit_effects_v2 = true,
			selected_hit_effect = (selected_hit_effect.id if selected_hit_effect else "ssp_ripple"),
			selected_miss_effect = (selected_miss_effect.id if selected_miss_effect else "ssp_miss"),
			lock_mouse = lock_mouse,
			absolute_mode = absolute_mode,
			absolute_scale = absolute_scale,
			cursor_trail = cursor_trail,
			trail_detail = trail_detail,
			trail_time = trail_time,
			trail_opacity = trail_opacity,
			trail_gradient_enabled = trail_gradient_enabled,
			trail_gradient = trail_gradient,
			favorite_colorsets = favorite_colorsets,
			favorite_meshes = favorite_meshes,
			custombg_color = custombg_color.to_html(false),
			max_fps_mode = max_fps_mode,
			realistic_autoplay = realistic_autoplay,
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
			hit_effect_at_cursor = hit_effect_at_cursor,
			show_warnings = show_warnings,
			record_replays = record_replays,
			alt_cam = alt_cam,
			hide_replay_ui = hide_replay_ui,
			sort_by_stars = sort_by_stars,
			sort_by_plays = sort_by_plays,
			random_colorset = random_colorset,
			show_xp_notifications = show_xp_notifications,
			half_ghost_strength = half_ghost_strength,
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
			wave_menu = wave_menu,
			wave_menu_colorset = wave_menu_colorset,
			ignore_controller_detection = ignore_controller_detection,
			expand_hud_onhr = expand_hud_onhr,
			last_search_incl_online = last_search_incl_online,
			menu_lyric_volume = menu_lyric_volume,
			show_touch_indicator = show_touch_indicator,
			sound_space_mode = sound_space_mode,
			ss_gameplay_only = ss_gameplay_only,
			always_show_crash_log = always_show_crash_log,
			track_plays = track_plays,
			ss_score_popups = ss_score_popups,
			ss_health_y = ss_health_y,
			ss_health_w = ss_health_w,
			ss_progress_y = ss_progress_y,
			ss_progress_w = ss_progress_w,
			mobile_no_delay = mobile_no_delay,
			mobile_high_hz = mobile_high_hz,
			touch_style = touch_style,
			vr_grip_rot = [vr_grip_rot.x, vr_grip_rot.y, vr_grip_rot.z],
			vr_grip_pos = [vr_grip_pos.x, vr_grip_pos.y, vr_grip_pos.z],
			vr_menu_size = vr_menu_size,
			vr_menu_distance = vr_menu_distance,
			vr_menu_curve = vr_menu_curve,
			vr_menu_ui = vr_menu_ui,
			vr_grid_distance = vr_grid_distance,
			vr_sensitivity = vr_sensitivity,
			vr_haptics = vr_haptics,
			vr_haptic_miss = vr_haptic_miss,
			vr_hand = vr_hand,
			vr_foveation = vr_foveation,
			vr_refresh = vr_refresh,
			vr_render_scale = vr_render_scale,
			vr_glow = vr_glow,
			vr_simple_bg = vr_simple_bg,
			vr_beam_width = vr_beam_width,
			vr_beam_color = vr_beam_color.to_html(true),
			vr_beam_rainbow = vr_beam_rainbow,
			vr_lock_beam = vr_lock_beam,
			vr_binds = vr_binds,
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
		"res://assets/worlds/soundspace/tunnel.tscn", "hi", # the Sound Space room (same as Sound Space Mode)
		"res://assets/worlds/grid/grid.png"
	))
	# Backgrounds recreated from Rhythia's (Godot 4 C#) spaces
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_void", "Void (Rhythia)",
		"res://assets/worlds/rhythia_spaces/void.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/void.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_solid", "Solid (Rhythia)",
		"res://assets/worlds/rhythia_spaces/solid.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/solid.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_grid", "Grid (Rhythia)",
		"res://assets/worlds/rhythia_spaces/grid.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/grid.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_tunnel", "Tunnel (Rhythia)",
		"res://assets/worlds/rhythia_spaces/tunnel.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/tunnel.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_circular_tunnel", "Circular Tunnel (Rhythia)",
		"res://assets/worlds/rhythia_spaces/circular_tunnel.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/circular_tunnel.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_tri_tunnel", "Tri Tunnel (Rhythia)",
		"res://assets/worlds/rhythia_spaces/tri_tunnel.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/tri_tunnel.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_galaxy", "Galaxy (Rhythia)",
		"res://assets/worlds/rhythia_spaces/galaxy.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/galaxy.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_squircles", "Squircles (Rhythia)",
		"res://assets/worlds/rhythia_spaces/squircles.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/squircles.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_vortex", "Vortex (Rhythia)",
		"res://assets/worlds/rhythia_spaces/vortex.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/vortex.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_waves", "Waves (Rhythia)",
		"res://assets/worlds/rhythia_spaces/waves.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/waves.png"
	))
	# The earlier Waves, with the map cover hanging in the sky over the water.
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_waves_classic", "Waves Classic",
		"res://assets/worlds/rhythia_spaces/waves_classic.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/waves.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_conspiracy", "Conspiracy (Rhythia)",
		"res://assets/worlds/rhythia_spaces/conspiracy.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/conspiracy.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"furria_space_relic", "Relic (Rhythia)",
		"res://assets/worlds/rhythia_spaces/relic.tscn", "Rhythia",
		"res://assets/worlds/rhythia_spaces/relic.png"
	))
	# Backgrounds converted from Roblox Rhythia's spaces
	registry_world.add_item(BackgroundWorld.new(
		"roblox_default", "Default",
		"res://assets/worlds/roblox/default/default.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/default/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_halloween", "Halloween",
		"res://assets/worlds/roblox/halloween/halloween.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/halloween/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_holo_dream", "Holo Dream",
		"res://assets/worlds/roblox/holo_dream/holo_dream.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/holo_dream/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_vaporwave", "Vaporwave",
		"res://assets/worlds/roblox/vaporwave/vaporwave.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/vaporwave/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_conspiracy", "Conspiracy",
		"res://assets/worlds/roblox/conspiracy/conspiracy.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/conspiracy/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_christmas", "Christmas",
		"res://assets/worlds/roblox/christmas/christmas.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/christmas/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_the_speaker", "The Speaker",
		"res://assets/worlds/roblox/the_speaker/the_speaker.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/the_speaker/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_valentines", "Valentines",
		"res://assets/worlds/roblox/valentines/valentines.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/valentines/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_easter", "Easter",
		"res://assets/worlds/roblox/easter/easter.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/easter/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_palm_trees", "Palm Trees",
		"res://assets/worlds/roblox/palm_trees/palm_trees.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/palm_trees/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_skull", "Skull",
		"res://assets/worlds/roblox/skull/skull.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/skull/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_pumpkin_kingdom", "Pumpkin Kingdom",
		"res://assets/worlds/roblox/pumpkin_kingdom/pumpkin_kingdom.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/pumpkin_kingdom/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_tronic", "Tronic",
		"res://assets/worlds/roblox/tronic/tronic.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/tronic/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_tri_tunnel", "Tri Tunnel",
		"res://assets/worlds/roblox/tri_tunnel/tri_tunnel.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/tri_tunnel/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_the_flower", "The Flower",
		"res://assets/worlds/roblox/the_flower/the_flower.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/the_flower/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_squircle", "Squircle",
		"res://assets/worlds/roblox/squircle/squircle.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/squircle/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_cubic", "Cubic",
		"res://assets/worlds/roblox/cubic/cubic.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/cubic/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_rift", "Rift",
		"res://assets/worlds/roblox/rift/rift.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/rift/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_beyond_reality", "Beyond Reality",
		"res://assets/worlds/roblox/beyond_reality/beyond_reality.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/beyond_reality/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_phantom_seas", "Phantom Seas",
		"res://assets/worlds/roblox/phantom_seas/phantom_seas.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/phantom_seas/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_inverted_conspiracy", "Inverted Conspiracy",
		"res://assets/worlds/roblox/inverted_conspiracy/inverted_conspiracy.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/inverted_conspiracy/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_red_screen", "Red Screen",
		"res://assets/worlds/roblox/red_screen/red_screen.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/red_screen/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_green_screen", "Green Screen",
		"res://assets/worlds/roblox/green_screen/green_screen.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/green_screen/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_blue_screen", "Blue Screen",
		"res://assets/worlds/roblox/blue_screen/blue_screen.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/blue_screen/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_gray_screen", "Gray Screen",
		"res://assets/worlds/roblox/gray_screen/gray_screen.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/gray_screen/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_world_cracks", "World Cracks",
		"res://assets/worlds/roblox/world_cracks/world_cracks.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/world_cracks/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_unity_tower", "Unity Tower",
		"res://assets/worlds/roblox/unity_tower/unity_tower.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/unity_tower/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_summer", "Summer",
		"res://assets/worlds/roblox/summer/summer.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/summer/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_hell", "Hell",
		"res://assets/worlds/roblox/hell/hell.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/hell/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_cat_shades", "Cat Shades",
		"res://assets/worlds/roblox/cat_shades/cat_shades.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/cat_shades/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_squircle_vortex", "Squircle Vortex",
		"res://assets/worlds/roblox/squircle_vortex/squircle_vortex.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/squircle_vortex/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_legacy", "Legacy",
		"res://assets/worlds/roblox/legacy/legacy.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/legacy/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_shooting_stars", "Shooting Stars",
		"res://assets/worlds/roblox/shooting_stars/shooting_stars.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/shooting_stars/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_torii", "Torii",
		"res://assets/worlds/roblox/torii/torii.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/torii/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_calm_night", "Calm Night",
		"res://assets/worlds/roblox/calm_night/calm_night.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/calm_night/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_arcade", "Arcade",
		"res://assets/worlds/roblox/arcade/arcade.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/arcade/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_sound_invaders", "Sound Invaders",
		"res://assets/worlds/roblox/sound_invaders/sound_invaders.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/sound_invaders/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_dojo", "Dojo",
		"res://assets/worlds/roblox/dojo/dojo.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/dojo/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_heartscape", "Heartscape",
		"res://assets/worlds/roblox/heartscape/heartscape.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/heartscape/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_admin_panel", "Admin Panel",
		"res://assets/worlds/roblox/admin_panel/admin_panel.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/admin_panel/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_lucky", "Lucky",
		"res://assets/worlds/roblox/lucky/lucky.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/lucky/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_cosmic_pyramid", "Cosmic Pyramid",
		"res://assets/worlds/roblox/cosmic_pyramid/cosmic_pyramid.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/cosmic_pyramid/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_black_screen", "Black Screen",
		"res://assets/worlds/roblox/black_screen/black_screen.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/black_screen/cover.png"
	))
	registry_world.add_item(BackgroundWorld.new(
		"roblox_white_screen", "White Screen",
		"res://assets/worlds/roblox/white_screen/white_screen.tscn", "Rhythia (Roblox)",
		"res://assets/worlds/roblox/white_screen/cover.png"
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
	load("res://scripts/ui/settings/NoteBuilderMesh.gd").register(registry_mesh)
	var dir = Directory.new()
	if dir.open(user_mesh_dir) == OK:
		dir.list_dir_begin(true, false)
		var mesh_name: String = dir.get_next()
		while mesh_name != "":
			if not dir.current_is_dir() and mesh_name.get_extension().to_lower() == "obj":
				registry_mesh.add_item(NoteMesh.new(
					"ugc_" + mesh_name.get_file().to_lower().replace(" ", "_"),
					mesh_name.get_basename() + " (custom)",
					user_mesh_dir.plus_file(mesh_name), "???"
				))
			mesh_name = dir.get_next()
	load("res://scripts/ui/settings/MeshesTab.gd").apply_name_overrides(registry_mesh) # names given in the Meshes tab
func register_effects():
	registry_effect.add_item(NoteEffect.new(
		"ssp_ripple", "Ripple* (no color)", "res://assets/notefx/ripple/ripple.tscn", "Chedski"
	))
	registry_effect.add_item(NoteEffect.new(
		"ssp_ripple_n", "Ripple* (note color)", "res://assets/notefx/ripple/ripple.tscn", "Chedski"
	))
	registry_effect.add_item(NoteEffect.new(
		"ssp_ripple_r", "Ripple* (rainbow)", "res://assets/notefx/ripple/ripple.tscn", "Chedski"
	))

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
		# Give the screen a frame every ~10 ms of work (not every 4 files:
		# hundreds of colorsets waited ~100 frames on every startup).
		var slice := OS.get_ticks_msec()
		for n in files.files:
			load_color_txt(n, "custom_" + n.get_file().to_lower().md5_text())
			if OS.get_ticks_msec() - slice > 10:
				yield(get_tree(), "idle_frame")
				slice = OS.get_ticks_msec()
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

	var smaps: Array = Globals.get_files_recursive(map_search_folders, MAP_SEARCH_DEPTH, "sspm", "", -1).files
	smaps.sort()

	var load_start = OS.get_ticks_usec()
	var from_file = 0
	var from_cache = 0
	registry_song.skipped = []
	var debug_map_load_times = OS.has_feature("debug")

	call_deferred("emit_signal", "init_stage_reached", "Register content 1/5\nImport Rhythia maps\n0 / %s" % smaps.size())
	var progress_last_emit_usec = OS.get_ticks_usec()

	for i in range(smaps.size()):
		var map_load_start_usec = OS.get_ticks_usec() if debug_map_load_times else 0

		var cached = caches.get(smaps[i])
		if _known_unreadable(cached, smaps[i]):
			from_cache += 1 # known unreadable file (this version), skip it
			registry_song.skipped.append([smaps[i], String(cached.get("why", "couldn't be read"))])
		elif cached != null and not (cached is Dictionary and cached.get("invalid", false)):
			if registry_song.add_sspm_cached_map(smaps[i], cached):
				from_cache += 1
			else:
				print("Failed loading a map from cache: ", smaps[i])
				from_file += 1
				registry_song.add_sspm_map(smaps[i])
		else:
			from_file += 1
			_loaded_from_file[smaps[i]] = registry_song.add_sspm_map(smaps[i])

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
	call_deferred("_report_skipped_maps")

	call_deferred("emit_signal", "init_stage_reached", "Register content 2/5\nCache Rhythia maps")
	err = file.open(Globals.p(CACHE_FILE_PATH), File.WRITE)
	if err == OK:
		file.store_string(JSON.print(_make_full_sspm_cache(cache_version)))
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
	# Started on a thread (Globals, and init.gd for Reload Content), but it adds
	# nodes, timers and keybinds to the running game, which is only safe on the
	# main thread: continue there.
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		call_deferred("do_init")
		return
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


	if Online.can_self_update():
		emit_signal("init_stage_reached", "Check for updates")
		emit_signal("init_stage_num", -1)
		yield(get_tree(), "idle_frame")
		Online.check_latest_version()
		var latest_version = yield(Online, "latest_version")
		if ProjectSettings.get_setting("application/config/version") != latest_version:
			var sel = 1
			if not String(Online.latest_version_data.get("body", "")).begins_with("-a") and not OS.has_feature("quest"):

				Globals.confirm_prompt.open("loud sound = gone\nYou are on an outdated version of the game! Would you like to automatically update?", "Outdated", [{text = "Ignore", wait = 0}, {text = "Update", wait = 1}])
				sel = yield(Globals.confirm_prompt, "option_selected")

				Globals.confirm_prompt.close()
				yield(Globals.confirm_prompt, "done_closing")
			if bool(sel):
				emit_signal("init_stage_reached", "Updating the game")
				Online.attempt_update()
				yield(Online, "update_finished")
				if Online.updates_by_pack():
					# iOS can't restart itself: the new version loads next time
					if Online.update_installed:
						_pending_update_notice = latest_version
					elif Online.update_blocked_reason != "":
						Globals.call_deferred("notify", Globals.NOTIFY_WARN, Online.update_blocked_reason, "Update needs a reinstall")
				else:
					get_tree().call_deferred("quit", 1)
					OS.execute(OS.get_executable_path(), [], false)
					return
		var rdir = Directory.new()
		if rdir.file_exists(Online.local_pck_path() + ".old"):
			rdir.remove(Online.local_pck_path() + ".old")


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
		Globals.get_files_recursive(map_search_folders, MAP_SEARCH_DEPTH, "sspm", "", 90)
		smaps = yield(Globals, "recurse_result").files
		smaps.sort() # (the same order every launch: a map with a taken id always gets the same new one)
		print("Locating files took %s usec (%s files)" % [Globals.comma_sep(OS.get_ticks_usec() - scan_start), smaps.size()])
		emit_signal("init_stage_num", 2)

		var load_start = OS.get_ticks_usec()
		var from_file = 0
		var from_cache = 0
		registry_song.skipped = []
		# Import on a worker thread so the loading screen stays smooth.
		_sspm_import_progress = 0
		_sspm_import_done = false
		var import_thread := Thread.new()
		var counts: Array
		if OS.can_use_threads() and import_thread.start(self, "_import_sspm_worker", [smaps, caches]) == OK:
			while not _sspm_import_done:
				emit_signal("init_stage_reached", "Register content 1/5\nImport Rhythia maps\n%d / %s" % [_sspm_import_progress, smaps.size()])
				yield(get_tree(), "idle_frame")
			counts = import_thread.wait_to_finish()
		else:
			counts = _import_sspm_worker([smaps, caches])
		from_cache = counts[0]
		from_file = counts[1]
		var load_end = OS.get_ticks_usec()
		var load_time = load_end - load_start

		print("Loaded %s/%s maps from cache of %s" % [from_cache, from_cache + from_file, caches.size()])
		print("Took %s usec" % Globals.comma_sep(load_time))
		_report_skipped_maps()


		# Only rewrite the map cache when maps were added, changed or removed.
		if from_file > 0 or caches.size() != from_cache + 1 or map_cache_dirty:
			map_cache_dirty = false
			emit_signal("init_stage_reached", "Register content 2/5\nCache Rhythia maps")
			yield(get_tree(), "idle_frame")
			var cache_write_start = OS.get_ticks_usec()
			var cache_dict = _make_full_sspm_cache(cache_version)
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
			# Online maps from the last run's saved database load right away; the
			# download then checks for new maps in the background (only the very
			# first launch, with nothing saved yet, waits for it).
			_online_maps_fetched = true
			Online.import_budget_usec = 100000 # loading screen: import quickly
			var had_cache = yield(Online.load_cached_db_maps(), "completed")
			Online.import_budget_usec = 4000
			Online.load_db_maps()
			if not had_cache:
				yield(Online, "db_maps_done")

		# Cover thumbnails are cached on disk and load on demand (see
		# Song.get_cover_thumb); missing ones are built in the background.
		_start_thumb_builder()

		# Star ratings: cached ones are applied now; new/changed maps are
		# rated in the background once the menu is open.
		emit_signal("init_stage_reached", "Loading star ratings")
		yield(get_tree(), "idle_frame")
		if _star_thread != null and _star_thread.is_active():
			# Reload Content while the background rater is still going: stop it
			# (it stops after its current map) before its cache is replaced.
			_star_quit = true
			_star_thread.wait_to_finish()
			_star_thread = null
			_star_quit = _quitting
		_star_cache = _load_star_cache()
		var f_cur := File.new()
		if f_cur.open(Globals.p(STAR_CURRENT_FILE), File.READ) == OK:
			# The game closed while rating this map last time; skip it.
			var bad_id := f_cur.get_as_text().strip_edges()
			f_cur.close()
			var bad_song = registry_song.get_item(bad_id) if registry_song.idx_id.has(bad_id) else null
			if bad_song:
				print("[stars] skipping map that failed last time: ", bad_id)
				_star_cache[bad_id] = [-2.0, _star_cache_key(bad_song)]
			Directory.new().remove(Globals.p(STAR_CURRENT_FILE))
		if f_cur.open(Globals.p(STAR_CLICK_FILE), File.READ) == OK:
			# The game closed while rating a map you clicked; never rate it again.
			var bad_click := f_cur.get_as_text().strip_edges()
			f_cur.close()
			var bad_click_song = registry_song.get_item(bad_click) if registry_song.idx_id.has(bad_click) else null
			if bad_click_song:
				print("[stars] skipping clicked map that failed last time: ", bad_click)
				_star_cache[bad_click] = [-2.0, _star_cache_key(bad_click_song)]
			Directory.new().remove(Globals.p(STAR_CLICK_FILE))
		var star_songs: Array = []
		var star_slice := OS.get_ticks_msec()
		for song in registry_song.get_items():
			if OS.get_ticks_msec() - star_slice > 15:
				yield(get_tree(), "idle_frame")
				star_slice = OS.get_ticks_msec()
			if song.is_online:
				continue
			var key := _star_cache_key(song)
			var cached = _star_cache.get(String(song.id))
			if cached is Array and cached.size() == 2 and String(cached[1]) == key:
				song._star_rating = float(cached[0])
			else:
				star_songs.append(song)
		if star_songs.size() > 0 and (_star_thread == null or not _star_thread.is_active()):
			_star_progress = 0
			_star_total = star_songs.size()
			_star_done = false
			_star_thread = Thread.new()
			if not OS.can_use_threads() or _star_thread.start(self, "_star_rating_worker", star_songs, Thread.PRIORITY_LOW) != OK:
				_star_thread = null
				_star_done = true

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
	selected_hit_effect = registry_effect.get_item("ssp_ripple")
	selected_miss_effect = registry_effect.get_item("ssp_miss")
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
	def_menu_bgm = load(MENU_PLAYLIST[0])

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
	var result = load_saved_settings(get_startup_settings_path())
	call_deferred("apply_mobile_tuning")
	load("res://scripts/game/SoundSpaceMode.gd").recover()
	if typeof(result) != TYPE_INT:
		# load_saved_settings stopped on an error part-way (null): keep the
		# settings read so far instead of getting stuck on this screen
		result = 0
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

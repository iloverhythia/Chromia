extends Node

signal lobby_created(code)
signal lobby_joined(code)
signal lobby_closed()
signal lobby_state_changed()
signal game_started()
signal lobby_error(reason)
signal skip_triggered(target_ms)
signal live_state_received(peer_id, x, y, combo, combo_level, score, hits, misses, total_notes, energy_pct, lvl_progress_pct, chart_ms)
signal player_failed(peer_id)
signal player_settings_received(peer_id)
signal player_missing_map(peer_id)
signal map_download_started(song_id)
signal map_download_progress(song_id, bytes_received, total_bytes)
signal map_upload_progress(song_id, bytes_sent, total_bytes)
signal map_download_complete(song_id)
signal round_ended
signal all_players_loaded()
signal chat_message_received(peer_id, name, text, ts)
signal global_chat_message_received(client_id, name, text, ts)
signal announcement_received(text, from_name, ts)
signal public_lobbies_received(lobbies)
signal admin_all_lobbies_received(lobbies)
signal admin_bans_received(bans)
signal admin_live_bans_received(bans)
signal admin_player_tags_received(tags)
signal admin_rankers_received(rankers)
signal admin_map_ranks_received(ranks)
signal ranker_status_received(is_ranker)
signal map_rank_info_received(song_id, ranked, xp, content_hash)
signal my_map_stats_received(song_id, has_passed, best_xp, best_sp)
signal set_map_rank_result(ok, song_id, xp)
signal map_publish_status_received(song_id, published)
signal map_publish_progress(song_id, bytes_sent, total_bytes)
signal map_publish_complete(song_id)
signal ranked_maps_received(song_ids)
# the Spectate tab
signal online_players_received(list, you)
signal spectate_denied(reason)
signal watch_ended(text)
signal presence_support_changed(supported)
signal watchers_changed(count, names)
signal unpublished_ranked_maps_received(song_ids)

var _live_state_cache: Dictionary = {}

const CHAT_HISTORY_MAX: int = 200
var lobby_chat_history: Array = []
var global_chat_history: Array = []

const SERVER_URL: String = "wss://savia.nysr.host/savia-ws"
const LIVE_STATE_SEND_INTERVAL: float = 0.0167
const SPECTATE_DELAY_SEC: float = 3.0

var _announcement_canvas: CanvasLayer
var _announcement_bar: PanelContainer
var _announcement_label: Label
var _announcement_fade_timer: float = 0.0
const ANNOUNCEMENT_DISPLAY_SEC: float = 8.0
var _pending_announcement: Dictionary = {}
var _was_in_map: bool = false

var is_host: bool = false
var lobby_active: bool = false
var lobby_code: String = ""
var player_name: String = "Player"
var local_peer_id: int = -1

var lobby_state: Dictionary = {
	"song_id": "",
	"song_name": "",
	"started": false,
	"host_name": "",
	"mods": {}
}
var players: Array = []

var _client: WebSocketClient = WebSocketClient.new()
var _connecting_intent: String = ""
var _pending_name: String = ""
var _pending_code: String = ""
var _pending_is_public: bool = true
var _pending_send_after_connect: Array = []

const _SETTINGS_PATH: String = "user://settings.cfg"
var _admin_key: String = ""

func has_admin_key() -> bool:
	return _admin_key != ""

func set_admin_key(key: String):
	_admin_key = key
	var config = ConfigFile.new()
	config.load(_SETTINGS_PATH)
	config.set_value("admin", "key", key)
	config.save(_SETTINGS_PATH)

const _MAP_CHUNK_SIZE: int = 64 * 1024

var _map_upload_active: bool = false
var _map_upload_song_id: String = ""
var _map_upload_b64: String = ""
var _map_upload_pos: int = 0

var _map_publish_active: bool = false
var _map_publish_song_id: String = ""
var _map_publish_b64: String = ""
var _map_publish_pos: int = 0
var _map_publish_last_progress_msec: int = 0

var _map_download_song_id: String = ""
var _map_download_chunks: Array = []
var _map_download_total_bytes: int = 0
var _map_download_chars_received: int = 0

func _ready():
	_client.connect("connection_established", self, "_on_connected")
	_client.connect("connection_closed", self, "_on_closed")
	_client.connect("connection_error", self, "_on_conn_error")
	_client.connect("data_received", self, "_on_data")
	Rhythia.connect("mods_changed", self, "_on_local_mods_changed")
	set_process(true)

	var config = ConfigFile.new()
	if config.load(_SETTINGS_PATH) == OK:
		player_name = config.get_value("multiplayer", "player_name", player_name)
		_admin_key = config.get_value("admin", "key", "")

func _save_player_name():
	var config = ConfigFile.new()
	config.load(_SETTINGS_PATH)
	config.set_value("multiplayer", "player_name", player_name)
	config.save(_SETTINGS_PATH)

func _process(_delta):
	if _client.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_client.poll()
	_process_map_upload_step()
	_process_map_publish_step()
	_presence_tick(_delta)

	if _announcement_fade_timer > 0:
		_announcement_fade_timer -= _delta
		_announcement_bar.modulate.a = clamp(_announcement_fade_timer, 0.0, 1.0)
		if _announcement_fade_timer <= 0:
			_announcement_canvas.visible = false

	if _was_in_map and not Rhythia.in_map and not _pending_announcement.empty():
		_show_announcement_banner(_pending_announcement.text, _pending_announcement.from_name)
		_pending_announcement = {}
	_was_in_map = Rhythia.in_map

func _build_announcement_banner():
	_announcement_canvas = CanvasLayer.new()
	_announcement_canvas.layer = 150
	_announcement_canvas.pause_mode = PAUSE_MODE_PROCESS
	_announcement_canvas.visible = false
	add_child(_announcement_canvas)

	_announcement_bar = PanelContainer.new()
	_announcement_bar.pause_mode = PAUSE_MODE_PROCESS
	_announcement_bar.anchor_right = 1.0
	var style = StyleBoxFlat.new()
	style.bg_color = Color("#00b8ff")
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	_announcement_bar.add_stylebox_override("panel", style)
	_announcement_canvas.add_child(_announcement_bar)

	_announcement_label = Label.new()
	_announcement_label.align = Label.ALIGN_CENTER
	_announcement_label.autowrap = true
	_announcement_label.add_color_override("font_color", Color.white)
	_announcement_label.add_color_override("font_color_shadow", Color(0, 0, 0, 0.6))
	_announcement_label.add_constant_override("shadow_offset_x", 1)
	_announcement_label.add_constant_override("shadow_offset_y", 1)
	_announcement_bar.add_child(_announcement_label)

func _show_announcement_banner(text: String, from_name: String):
	if not is_instance_valid(_announcement_canvas):
		_build_announcement_banner()
	_announcement_label.text = "%s: %s" % [from_name, text]
	_announcement_canvas.visible = true
	_announcement_bar.modulate.a = 1.0
	_announcement_fade_timer = ANNOUNCEMENT_DISPLAY_SEC


func create_lobby(name: String = "Host", is_public: bool = true) -> bool:
	close_lobby()
	player_name = name
	_pending_name = name
	_pending_is_public = is_public
	_connecting_intent = "create"
	return _connect_or_send_intent()

func join_lobby(code: String, name: String) -> bool:
	close_lobby()
	player_name = name
	_pending_name = name
	_pending_code = code
	_connecting_intent = "join"
	return _connect_or_send_intent()

func _ensure_connected_then_send(payload: Dictionary):
	if _client.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		_send(payload)
		return
	_pending_send_after_connect.append(payload)
	# While the server can't be reached, keep only the newest requests
	# instead of piling up one per click.
	if _pending_send_after_connect.size() > 32:
		_pending_send_after_connect = _pending_send_after_connect.slice(_pending_send_after_connect.size() - 32, _pending_send_after_connect.size() - 1)
	if _client.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_connecting_intent = "generic"
		_connect_socket()

func list_public_lobbies():
	_ensure_connected_then_send({"type": "list_public_lobbies"})

func unsubscribe_public_lobbies():
	if _client.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		_send({"type": "unsubscribe_public_lobbies"})

func send_chat_message(text: String):
	text = text.strip_edges()
	if text == "" or not lobby_active:
		return
	_send({"type": "chat_message", "text": text.substr(0, 300)})

func send_global_chat_message(text: String):
	text = text.strip_edges()
	if text == "":
		return
	_ensure_connected_then_send({"type": "global_chat_message", "text": text.substr(0, 300), "client_id": Rhythia.cid, "name": player_name})

func admin_send_announcement(text: String):
	text = text.strip_edges()
	if not has_admin_key() or text == "":
		return
	_ensure_connected_then_send({"type": "admin_send_announcement", "admin_key": _admin_key, "text": text.substr(0, 300), "name": player_name})

func admin_list_all_lobbies():
	if not has_admin_key():
		return
	_ensure_connected_then_send({"type": "admin_list_all_lobbies", "admin_key": _admin_key})

func admin_ban_user(client_id: String, scopes: Array = ["multiplayer"], reason: String = ""):
	if not has_admin_key() or client_id == "" or scopes.size() == 0:
		return
	_ensure_connected_then_send({"type": "admin_ban_user", "admin_key": _admin_key, "client_id": client_id, "scopes": scopes, "reason": reason})


func admin_unban_user(client_id: String, scopes: Array = []):
	if not has_admin_key() or client_id == "":
		return
	_ensure_connected_then_send({"type": "admin_unban_user", "admin_key": _admin_key, "client_id": client_id, "scopes": scopes})

func admin_list_bans():
	if not has_admin_key():
		return
	_ensure_connected_then_send({"type": "admin_list_bans", "admin_key": _admin_key})

func admin_live_ban_user(client_id: String, reason: String = ""):
	if not has_admin_key() or client_id == "":
		return
	_ensure_connected_then_send({"type": "admin_live_ban_user", "admin_key": _admin_key, "client_id": client_id, "reason": reason})

func admin_live_unban_user(client_id: String):
	if not has_admin_key() or client_id == "":
		return
	_ensure_connected_then_send({"type": "admin_live_unban_user", "admin_key": _admin_key, "client_id": client_id})

func admin_list_live_bans():
	if not has_admin_key():
		return
	_ensure_connected_then_send({"type": "admin_list_live_bans", "admin_key": _admin_key})

func admin_set_player_tag(client_id: String, text: String, color: String):
	if not has_admin_key() or client_id == "" or text == "" or color == "":
		return
	_ensure_connected_then_send({"type": "admin_set_player_tag", "admin_key": _admin_key, "client_id": client_id, "text": text, "color": color})

func admin_remove_player_tag(client_id: String):
	if not has_admin_key() or client_id == "":
		return
	_ensure_connected_then_send({"type": "admin_remove_player_tag", "admin_key": _admin_key, "client_id": client_id})

func admin_list_player_tags():
	if not has_admin_key():
		return
	_ensure_connected_then_send({"type": "admin_list_player_tags", "admin_key": _admin_key})

func admin_add_ranker(client_id: String):
	if not has_admin_key() or client_id == "":
		return
	_ensure_connected_then_send({"type": "admin_add_ranker", "admin_key": _admin_key, "client_id": client_id})

func admin_remove_ranker(client_id: String):
	if not has_admin_key() or client_id == "":
		return
	_ensure_connected_then_send({"type": "admin_remove_ranker", "admin_key": _admin_key, "client_id": client_id})

func admin_list_rankers():
	if not has_admin_key():
		return
	_ensure_connected_then_send({"type": "admin_list_rankers", "admin_key": _admin_key})

func admin_list_map_ranks():
	if not has_admin_key():
		return
	_ensure_connected_then_send({"type": "admin_list_map_ranks", "admin_key": _admin_key})

func admin_remove_map_rank(song_id: String):
	if not has_admin_key() or song_id == "":
		return
	_ensure_connected_then_send({"type": "admin_remove_map_rank", "admin_key": _admin_key, "song_id": song_id})

func check_ranker_status():
	if Rhythia.cid == "":
		return
	_ensure_connected_then_send({"type": "check_ranker_status", "client_id": Rhythia.cid})

func set_map_rank(song_id: String, song_name: String, xp: int, content_hash: String):
	if Rhythia.cid == "" or song_id == "":
		return
	_ensure_connected_then_send({"type": "set_map_rank", "client_id": Rhythia.cid, "song_id": song_id, "song_name": song_name, "xp": xp, "content_hash": content_hash})

func get_map_rank(song_id: String):
	if song_id == "":
		return
	_ensure_connected_then_send({"type": "get_map_rank", "song_id": song_id})

func get_my_map_stats(song_id: String):
	if song_id == "" or Rhythia.cid == "":
		return
	_ensure_connected_then_send({"type": "get_my_map_stats", "client_id": Rhythia.cid, "song_id": song_id})

func list_ranked_maps():
	_ensure_connected_then_send({"type": "list_ranked_maps"})

func list_unpublished_ranked_maps():
	_ensure_connected_then_send({"type": "list_unpublished_ranked_maps", "client_id": Rhythia.cid})

func close_lobby():
	if _client.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		if lobby_active:
			_send({"type": "leave_lobby"})
		# (servers with the Spectate tab keep the connection: it says you're online)
		if presence_supported != 1:
			_client.disconnect_from_host()
	if watch_mode:
		_finish_watch_locally()

	var was_active = lobby_active
	lobby_active = false
	is_host = false
	lobby_code = ""
	local_peer_id = -1
	players = []
	lobby_spectators = []
	lobby_state = {"song_id": "", "song_name": "", "started": false, "host_name": ""}
	_map_readiness_checked_song_id = ""
	_last_scrolled_song_id = ""
	lobby_chat_history = []
	player_view_settings = {}
	_spectate_load_target = -1
	if was_active:
		emit_signal("lobby_closed")

func set_player_name(name: String):
	player_name = name
	_save_player_name()

	if lobby_active:
		var msg = {"type": "set_player_name", "name": name}
		msg.merge(_discord_identity_fields())
		_send(msg)
		var msg2 = {"type": "set_name", "name": name}
		msg2.merge(_discord_identity_fields())
		_send(msg2)

const _SET_SONG_DEBOUNCE_SEC: float = 0.6
var _pending_lobby_song = null
var _set_song_debounce_running: bool = false

func set_lobby_song(song):
	if not lobby_active or not is_host or song == null:
		return
	_pending_lobby_song = song
	if _set_song_debounce_running:
		return
	_set_song_debounce_running = true
	var t = get_tree().create_timer(_SET_SONG_DEBOUNCE_SEC)
	t.connect("timeout", self, "_flush_pending_lobby_song")

func _flush_pending_lobby_song():
	_set_song_debounce_running = false
	var song = _pending_lobby_song
	_pending_lobby_song = null
	if song == null or not lobby_active or not is_host:
		return
	var song_id = song.id if song.has_method("get") and song.get("id") != null else ""
	var song_name = song.name if song.has_method("get") and song.get("name") != null else ""
	_send({"type": "set_song", "song_id": song_id, "song_name": song_name})

func update_player_stats(score: int, hits: int, misses: int, total_notes: int):
	if not broadcasting():
		return
	_send({"type": "update_stats", "score": score, "hits": hits, "misses": misses, "total_notes": total_notes})

func start_game():
	print("[furria] start_game() called, lobby_active=", lobby_active, " is_host=", is_host)
	if lobby_active and is_host:
		_send({"type": "start_game"})
		print("[furria] start_game message sent")

func trigger_skip(target_ms: float):
	if not lobby_active:
		return
	_send({"type": "player_skip", "target_ms": target_ms})

func reset_lobby_round():
	if lobby_active and is_host:
		_send({"type": "reset_round"})

func transfer_host(target_peer_id: int):
	if not lobby_active or not is_host or target_peer_id == local_peer_id:
		return
	_send({"type": "transfer_host", "peer_id": target_peer_id})


var _last_connect_try: int = -100000
func _connect_socket() -> bool:
	# Background requests (map info etc.) retry at most every 2 s while the
	# server is unreachable; joining/creating a lobby always tries right away.
	var now := OS.get_ticks_msec()
	if _connecting_intent == "generic" and now - _last_connect_try < 2000:
		return false
	_last_connect_try = now
	var err = _client.connect_to_url(SERVER_URL)
	if err != OK:
		if _connecting_intent == "create" or _connecting_intent == "join":
			emit_signal("lobby_error", "Could not connect to server")
		return false
	return true

func _discord_identity_fields() -> Dictionary:
	if not Rhythia.discord_user.has("id"):
		return {}
	return {
		"discord_id": Rhythia.discord_user.get("id", ""),
		"discord_username": Rhythia.discord_user.get("username", ""),
		"discord_display_name": Rhythia.discord_user.get("display_name", ""),
	}

# Creating / joining: servers with the Spectate tab keep the connection open,
# so the request goes out on it; otherwise (or while it's still connecting)
# it goes out once connected.
func _connect_or_send_intent() -> bool:
	if presence_supported != 1:
		return _connect_socket() # (as before: close_lobby just disconnected)
	var st = _client.get_connection_status()
	if st == NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		_send_lobby_intent()
		return true
	if st == NetworkedMultiplayerPeer.CONNECTION_CONNECTING:
		return true # (_on_connected sends it)
	return _connect_socket()

func _send_lobby_intent():
	if _connecting_intent == "create":
		var msg = {"type": "create_lobby", "name": _pending_name, "client_id": Rhythia.cid, "is_public": _pending_is_public}
		msg.merge(_discord_identity_fields())
		_send(msg)
	elif _connecting_intent == "join":
		var msg = {"type": "join_lobby", "code": _pending_code, "name": _pending_name, "client_id": Rhythia.cid}
		msg.merge(_discord_identity_fields())
		_send(msg)
	_connecting_intent = "generic"

func _on_connected(_proto = ""):
	_send_lobby_intent()
	_send({"type": "hello"})
	if presence_supported == 1:
		_send_presence(true)
		if _online_subscribed:
			_send({"type": "subscribe_online"})
	# Requests queued while connecting (map rank, my stats...) go out for every
	# intent; after a lobby connect they used to wait until the next reconnect.
	if not _pending_send_after_connect.empty():
		var queued = _pending_send_after_connect
		_pending_send_after_connect = []
		for msg in queued:
			_send(msg)

func _on_closed(was_clean: bool = false):
	if lobby_active and not was_clean:
		emit_signal("lobby_error", "Disconnected from the server — the lobby may no longer exist.")
	close_lobby()

func _on_conn_error():
	var was_joining = _connecting_intent == "create" or _connecting_intent == "join"
	if was_joining:
		emit_signal("lobby_error", "Could not reach server")
	close_lobby()
	if was_joining:
		emit_signal("lobby_state_changed") # the lobby panel kept saying "Connecting..."

func _on_data():
	var pkt = _client.get_peer(1).get_packet()
	var parsed = JSON.parse(pkt.get_string_from_utf8())
	if parsed.error == OK and parsed.result is Dictionary:
		_handle_message(parsed.result)

func _send(payload: Dictionary) -> int:
	if not payload.has("version"):
		payload["version"] = String(ProjectSettings.get_setting("application/config/version"))
	if _client.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		return _client.get_peer(1).put_packet(JSON.print(payload).to_utf8())
	return ERR_UNAVAILABLE

func _collect_current_mods() -> Dictionary:
	return {
		"nofail": Rhythia.mod_nofail,
		"speed_level": Rhythia.mod_speed_level,
		"speed_custom": Globals.speed_multi[Globals.SPEED_CUSTOM] if Rhythia.mod_speed_level == Globals.SPEED_CUSTOM else 1.0,
		"sudden_death": Rhythia.mod_sudden_death,
		"extra_energy": Rhythia.mod_extra_energy,
		"no_regen": Rhythia.mod_no_regen,
		"mirror_x": Rhythia.mod_mirror_x,
		"mirror_y": Rhythia.mod_mirror_y,
		"ghost": Rhythia.mod_ghost,
		"nearsighted": Rhythia.mod_nearsighted,
		"hardrock": Rhythia.mod_hardrock,
		"hard_mode": Rhythia.mod_hard_mode,
		"flashlight": Rhythia.mod_flashlight,
		"mod_360": Rhythia.mod_360,
		"mod_360_speed": Rhythia.mod_360_speed,
		"strobe": Rhythia.mod_strobe,
		"start_offset": Rhythia.start_offset,
	}

func set_lobby_mods(mods: Dictionary):
	if not lobby_active or not is_host:
		return
	_send({"type": "set_mods", "mods": mods})

func push_current_mods():
	if not lobby_active or not is_host:
		return
	set_lobby_mods(_collect_current_mods())

const _SET_MODS_DEBOUNCE_SEC: float = 0.2
var _mods_push_debounce_running: bool = false

func _on_local_mods_changed():
	if not lobby_active or not is_host or _mods_push_debounce_running:
		return
	_mods_push_debounce_running = true
	var t = get_tree().create_timer(_SET_MODS_DEBOUNCE_SEC)
	t.connect("timeout", self, "_flush_mods_push")

func _flush_mods_push():
	_mods_push_debounce_running = false
	push_current_mods()

func _apply_mods_locally(mods: Dictionary):
	if mods.empty():
		return
	Rhythia.mod_nofail = mods.get("nofail", Rhythia.mod_nofail)
	Rhythia.mod_speed_level = mods.get("speed_level", Rhythia.mod_speed_level)
	if Rhythia.mod_speed_level == Globals.SPEED_CUSTOM:
		Rhythia.custom_speed = mods.get("speed_custom", 1.0)
	Rhythia.mod_sudden_death = mods.get("sudden_death", Rhythia.mod_sudden_death)
	Rhythia.mod_extra_energy = mods.get("extra_energy", Rhythia.mod_extra_energy)
	Rhythia.mod_no_regen = mods.get("no_regen", Rhythia.mod_no_regen)
	Rhythia.mod_mirror_x = mods.get("mirror_x", Rhythia.mod_mirror_x)
	Rhythia.mod_mirror_y = mods.get("mirror_y", Rhythia.mod_mirror_y)
	Rhythia.mod_ghost = mods.get("ghost", Rhythia.mod_ghost)
	Rhythia.mod_nearsighted = mods.get("nearsighted", Rhythia.mod_nearsighted)
	Rhythia.mod_hardrock = mods.get("hardrock", Rhythia.mod_hardrock)
	Rhythia.mod_hard_mode = mods.get("hard_mode", Rhythia.mod_hard_mode)
	Rhythia.mod_flashlight = mods.get("flashlight", Rhythia.mod_flashlight)
	Rhythia.mod_360 = mods.get("mod_360", Rhythia.mod_360)
	Rhythia.mod_360_speed = mods.get("mod_360_speed", Rhythia.mod_360_speed)
	Rhythia.mod_strobe = mods.get("strobe", Rhythia.mod_strobe)
	Rhythia.start_offset = mods.get("start_offset", Rhythia.start_offset)

	if Rhythia.has_signal("mods_changed"):
		Rhythia.emit_signal("mods_changed")

func send_live_state(x: float, y: float, combo: int, combo_level: int, energy_pct: float, lvl_progress_pct: float, chart_ms: float, vr_pose = null, paused: bool = false):
	if not broadcasting():
		return
	var msg := {
		"type": "update_live_state", "x": x, "y": y, "combo": combo, "combo_level": combo_level,
		"energy_pct": energy_pct, "lvl_progress_pct": lvl_progress_pct, "ms": chart_ms,
	}
	if vr_pose is Array:
		msg["vr"] = vr_pose # in VR: head and hands, for spectators
	if paused:
		msg["paused"] = true # (paused or counting back in: spectators show Paused and wait)
	_send(msg)
func notify_passed():
	if not broadcasting():
		return
	_send({"type": "player_passed"})

func notify_failed():
	if not broadcasting():
		return

	for p in players:
		if int(p.get("peer_id", -1)) == local_peer_id:
			p["failed"] = true
	_send({"type": "player_failed"})

func report_missing_map():
	if not lobby_active:
		return
	_send({"type": "missing_map"})

func report_spectate_target(target_peer_id: int):
	if not lobby_active:
		return
	_send({"type": "set_spectate_target", "target_peer_id": target_peer_id})

# --- spectating with the watched player's settings (SpectateSettings.gd) -------
# peer id -> the display settings that player sent ({} if they sent none, e.g.
# an older game)
var player_view_settings: Dictionary = {}
var _spectate_load_target: int = -1

# Your display settings, for anyone who watches you (sent when a round starts).
func send_view_settings():
	if not broadcasting():
		return
	upload_cursor_picture()
	upload_spectate_assets()
	_send({"type": "set_view_settings", "settings": load("res://scripts/SpectateSettings.gd").collect()})

# Your cursor picture to the server once (it keeps it by the file's hash), so
# spectators watching with your settings see your cursor.
const CURSOR_URL := "https://savia.nysr.host/savia-cursor"
var _cursor_sent: String = ""
# your own border picture and note mesh, for spectators (sent once each; the
# server keeps them by hash: savia_web src/spectateassets.js)
const SPECTATE_ASSET_URL := "https://savia.nysr.host/savia-spectate-asset"
var _assets_sent := {} # kind -> sha256 sent

func upload_spectate_assets():
	var spec = load("res://scripts/SpectateSettings.gd")
	# backgrounds: pictures, videos and the layout (each file once)
	for a in spec.own_background_assets():
		for u in a.uploads:
			_upload_asset_file(u[0], u[1], u[2])
	for kind in ["border", "mesh"]:
		var file: String = spec.own_border_file() if kind == "border" else spec.own_mesh_file()
		if file == "":
			continue
		var f := File.new()
		var sha: String = f.get_sha256(file)
		if sha == "" or _assets_sent.get(kind, "") == sha or f.open(file, File.READ) != OK:
			continue
		var data: PoolByteArray = f.get_buffer(f.get_len())
		f.close()
		_assets_sent[kind] = sha
		var http := HTTPRequest.new()
		add_child(http)
		http.connect("request_completed", self, "_on_asset_uploaded", [http, kind])
		var url: String = "%s/%s?client_id=%s" % [SPECTATE_ASSET_URL, kind, String(Rhythia._ensure_client_id()).http_escape()]
		if http.request_raw(url, ["Content-Type: application/octet-stream"], true, HTTPClient.METHOD_POST, data) != OK:
			http.queue_free()
			_assets_sent.erase(kind)

func _on_asset_uploaded(result, code, _headers, _body, http, kind):
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_assets_sent.erase(kind) # (tried again next song)

# one background file (sent once per hash a session)
func _upload_asset_file(kind: String, file: String, sha: String):
	var key := "%s:%s" % [kind, sha]
	if sha == "" or _assets_sent.has(key):
		return
	var f := File.new()
	if f.open(file, File.READ) != OK:
		return
	var data: PoolByteArray = f.get_buffer(f.get_len())
	f.close()
	_assets_sent[key] = sha
	var http := HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", self, "_on_asset_uploaded", [http, key])
	var url: String = "%s/%s?client_id=%s" % [SPECTATE_ASSET_URL, kind, String(Rhythia._ensure_client_id()).http_escape()]
	if http.request_raw(url, ["Content-Type: application/octet-stream"], true, HTTPClient.METHOD_POST, data) != OK:
		http.queue_free()
		_assets_sent.erase(key)

# Watching someone: their border picture / mesh downloaded into the cache
# (tried a few times: they may still be uploading it). The first load of a
# watch waits for them a moment (spectate_assets_ready).
var _asset_downloads := {} # "sha.ext" -> tries left
var _asset_cache_tidied := false

func fetch_spectate_assets(settings):
	if not (settings is Dictionary):
		return
	var spec = load("res://scripts/SpectateSettings.gd")
	_tidy_asset_cache()
	var wanted := []
	for pair in [["border", "border_image", "png"], ["mesh", "mesh_file", "obj"]]:
		wanted.append([pair[0], String(settings.get(pair[1], "")).to_lower(), pair[2]])
	for k in ["custombg_image", "panobg_image"]:
		var v: String = String(settings.get(k, "")).to_lower()
		if v.find(".") == 64:
			wanted.append(["media", v.left(64), v.right(65)])
	var lv: String = String(settings.get("bg_layers", "")).to_lower()
	if lv != "none" and lv != "":
		wanted.append(["bglayers", lv, "json"])
		_queue_layout_media(spec.cached_asset(lv, "json")) # (a layout already here: its files)
	for w in wanted:
		_queue_asset_download(w[0], w[1], w[2])

func _queue_asset_download(kind: String, sha: String, ext: String):
	var spec = load("res://scripts/SpectateSettings.gd")
	if sha.length() != 64 or not sha.is_valid_hex_number() or ext == "" or spec.cached_asset(sha, ext) != "":
		return
	var key: String = "%s.%s" % [sha, ext]
	if _asset_downloads.has(key):
		return
	_asset_downloads[key] = 4
	_download_asset(kind, sha, ext)

# a downloaded Background Editor layout: the files it names
func _queue_layout_media(layout_path: String):
	if layout_path == "":
		return
	var f := File.new()
	if f.open(layout_path, File.READ) != OK:
		return
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error != OK or not (parsed.result is Dictionary) or not (parsed.result.get("layers", null) is Array):
		return
	for l in parsed.result.layers:
		var fname: String = String(l.get("file", "")) if l is Dictionary else ""
		if fname.find(".") == 64:
			_queue_asset_download("media", fname.left(64).to_lower(), fname.right(65).to_lower())

func _download_asset(kind: String, sha: String, ext: String):
	var spec = load("res://scripts/SpectateSettings.gd")
	var dir_path: String = Globals.p(spec.ASSET_CACHE)
	Directory.new().make_dir_recursive(dir_path)
	var http := HTTPRequest.new()
	http.download_file = dir_path.plus_file("%s.%s.part" % [sha, ext])
	add_child(http)
	http.connect("request_completed", self, "_on_asset_downloaded", [http, kind, sha, ext])
	if http.request("%s/%s/%s.%s" % [SPECTATE_ASSET_URL, kind, sha, ext]) != OK:
		http.queue_free()
		_asset_downloads.erase("%s.%s" % [sha, ext])

func _on_asset_downloaded(result, code, _headers, _body, http, kind, sha, ext):
	http.queue_free()
	var key: String = "%s.%s" % [sha, ext]
	var dir_path: String = Globals.p(load("res://scripts/SpectateSettings.gd").ASSET_CACHE)
	var part: String = dir_path.plus_file(key + ".part")
	var d := Directory.new()
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and File.new().get_sha256(part) == sha:
		d.rename(part, dir_path.plus_file(key))
		if kind == "bglayers":
			_queue_layout_media(dir_path.plus_file(key)) # (before this one counts as done)
		_asset_downloads.erase(key)
		_assets_arrived()
		return
	d.remove(part)
	var left: int = int(_asset_downloads.get(key, 0)) - 1
	if left <= 0:
		_asset_downloads.erase(key)
		_assets_arrived() # (given up: load without it)
		return
	_asset_downloads[key] = left
	yield(get_tree().create_timer(1.5), "timeout")
	_download_asset(kind, sha, ext)

func spectate_assets_ready() -> bool:
	return _asset_downloads.empty()

# the first load of a watch was waiting for them
func _assets_arrived():
	if _watch_wait_t > 0.0 and watch_mode and spectate_assets_ready() and has_player_settings(_spectate_load_target):
		_watch_wait_t = 0.0
		_scene_transition_now()

# old downloads (a week) go, so the cache doesn't grow forever
func _tidy_asset_cache():
	if _asset_cache_tidied:
		return
	_asset_cache_tidied = true
	var dir_path: String = Globals.p(load("res://scripts/SpectateSettings.gd").ASSET_CACHE)
	var d := Directory.new()
	if d.open(dir_path) != OK:
		return
	var f := File.new()
	var now := OS.get_unix_time()
	d.list_dir_begin(true, true)
	var n := d.get_next()
	while n != "":
		var p: String = dir_path.plus_file(n)
		if not d.current_is_dir() and (n.ends_with(".part") or now - f.get_modified_time(p) > 7 * 86400):
			d.remove(p)
		n = d.get_next()
	d.list_dir_end()

func upload_cursor_picture():
	var pic: String = load("res://scripts/SpectateSettings.gd").own_cursor_file()
	if pic == "":
		return
	var f := File.new()
	var sha: String = f.get_sha256(pic)
	if sha == "" or sha == _cursor_sent or f.open(pic, File.READ) != OK:
		return
	var data: PoolByteArray = f.get_buffer(f.get_len())
	f.close()
	if data.size() > 2 * 1024 * 1024:
		return
	_cursor_sent = sha
	var http := HTTPRequest.new()
	add_child(http)
	http.connect("request_completed", self, "_on_cursor_uploaded", [http])
	var url: String = "%s?client_id=%s" % [CURSOR_URL, String(Rhythia._ensure_client_id()).http_escape()]
	if http.request_raw(url, ["Content-Type: application/octet-stream"], true, HTTPClient.METHOD_POST, data) != OK:
		http.queue_free()
		_cursor_sent = ""

func _on_cursor_uploaded(result, code, _headers, _body, http):
	http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		_cursor_sent = "" # (tried again next song)

# Playing alone: your display settings go to the server at the start of the
# song, so whoever starts watching from the Spectate tab sees it your way
# right away (servers with the Spectate tab only; a lobby uses the above).
func send_solo_view_settings():
	if lobby_active or presence_supported != 1 or not _connected() or not Rhythia.allow_spectators:
		return
	upload_cursor_picture()
	upload_spectate_assets()
	_send({"type": "set_view_settings", "settings": load("res://scripts/SpectateSettings.gd").collect()})

func request_player_settings(peer_id: int):
	if lobby_active and peer_id > 0 and peer_id != local_peer_id:
		if watch_mode and player_view_settings.has(peer_id):
			return # (the server sent them with the start)
		_send({"type": "get_player_settings", "peer_id": peer_id})

func has_player_settings(peer_id: int) -> bool:
	var s = player_view_settings.get(peer_id, {})
	return s is Dictionary and not s.empty()

# The next song load goes straight into spectating (a late join, or switching
# between their settings and yours): songload keeps the settings put on for it.
func spectate_load_pending() -> bool:
	return _late_join_pending

func consume_spectate_target() -> int:
	var t = _spectate_load_target
	_spectate_load_target = -1
	return t

# Builds the song scene again, spectating peer_id (the settings to watch with
# are already on). Most settings are read when the scene is built.
func reload_into_spectate(peer_id: int):
	if not lobby_active or not bool(lobby_state.get("started", false)):
		return
	_late_join_pending = true
	_spectate_load_target = peer_id
	get_tree().paused = false
	_scene_transition_now()

func request_map(song_id: String):
	if not lobby_active or song_id == "":
		return
	_send({"type": "request_map", "song_id": song_id})

func report_round_loaded():
	if not lobby_active:
		return
	_send({"type": "player_loaded_round"})

var _map_readiness_checked_song_id: String = ""

var _late_join_pending: bool = false

func consume_late_join_pending() -> bool:
	var was_pending = _late_join_pending
	_late_join_pending = false
	return was_pending

func _check_map_readiness():
	var song_id = String(lobby_state.get("song_id", ""))
	if song_id == "" or song_id == _map_readiness_checked_song_id or is_host:
		return
	_map_readiness_checked_song_id = song_id
	var song = Rhythia.registry_song.get_item(song_id, Globals.SEARCH_ID) if Rhythia.registry_song else false
	if song:
		_send({"type": "map_ready", "song_id": song_id})
		if _late_join_pending:
			if watch_mode and _watch_first_load and load("res://scripts/SpectateSettings.gd").prefer_theirs() and has_player_settings(_spectate_load_target) and not spectate_assets_ready():
				_watch_wait_t = 4.0 # their border / mesh are downloading: load once they're here
				return
			if watch_mode and _watch_first_load and load("res://scripts/SpectateSettings.gd").prefer_theirs() and not has_player_settings(_spectate_load_target):
				# Spectate tab: their settings are on the way (they send them
				# when someone starts watching); load once with them
				request_player_settings(_spectate_load_target)
				_watch_wait_t = 2.5
				return
			request_player_settings(get_first_place_peer_id())
			_scene_transition_now()
	else:
		report_missing_map()
		request_map(song_id)

var _last_scrolled_song_id: String = ""
func _try_scroll_map_list(song_id: String):
	if is_host or song_id == "" or song_id == _last_scrolled_song_id:
		return
	var map_list = Rhythia.menu_node("Main/Maps/MapRegistry/S/VBoxContainer")
	if map_list == null or not map_list.has_method("scroll_to_song"):
		return

	if map_list.scroll_to_song(song_id):
		_last_scrolled_song_id = song_id

func _start_map_upload(song_id: String):
	print("[furria] _start_map_upload(", song_id, ") is_host=", is_host, " active=", _map_upload_active)
	if _map_upload_active:
		print("[furria] upload aborted: already have one in flight for ", _map_upload_song_id)
		return
	if not is_host and watchers_count <= 0:
		print("[furria] upload aborted: this client isn't the host (server shouldn't have asked)")
		return
	var song = Rhythia.registry_song.get_item(song_id, Globals.SEARCH_ID) if Rhythia.registry_song else false
	if not song or not ("filePath" in song):
		print("[furria] upload aborted: song not found in local registry for id ", song_id)
		return
	var f = File.new()
	var open_err = f.open(song.filePath, File.READ)
	if open_err != OK:
		print("[furria] upload aborted: couldn't open ", song.filePath, " (error ", open_err, ")")
		return
	var bytes = f.get_buffer(f.get_len())
	f.close()
	print("[furria] uploading ", song.filePath, " — ", bytes.size(), " bytes")
	_map_upload_b64 = Marshalls.raw_to_base64(bytes)
	_map_upload_song_id = song_id
	_map_upload_pos = 0
	_map_upload_active = true
	_map_upload_last_progress_msec = OS.get_ticks_msec()
	var start_err = _send({"type": "upload_map_start", "song_id": song_id, "total_bytes": bytes.size()})
	if start_err != OK:
		push_error("[furria] upload_map_start failed to send: %s" % start_err)
		_abort_map_upload("Failed to start uploading the map to the server.")

const _MAP_UPLOAD_STALL_TIMEOUT_MSEC: int = 15000
var _map_upload_last_progress_msec: int = 0
var _map_upload_next_attempt_msec: int = 0

const _MAP_CHUNK_RETRY_COOLDOWN_MSEC: int = 50

func _process_map_upload_step():
	if not _map_upload_active:
		return
	if OS.get_ticks_msec() < _map_upload_next_attempt_msec:
		return
	var done = _map_upload_pos >= _map_upload_b64.length()
	var payload: Dictionary
	if done:
		payload = {"type": "upload_map_end", "song_id": _map_upload_song_id}
	else:
		var chunk_end = min(_map_upload_pos + _MAP_CHUNK_SIZE, _map_upload_b64.length())
		var chunk = _map_upload_b64.substr(_map_upload_pos, chunk_end - _map_upload_pos)
		payload = {"type": "upload_map_chunk", "song_id": _map_upload_song_id, "chunk": chunk}

	var send_err = _send(payload)
	if send_err != OK:
		_map_upload_next_attempt_msec = OS.get_ticks_msec() + _MAP_CHUNK_RETRY_COOLDOWN_MSEC
		if OS.get_ticks_msec() - _map_upload_last_progress_msec < _MAP_UPLOAD_STALL_TIMEOUT_MSEC:
			return
		push_error("[furria] map upload stalled (%s), giving up: %s" % [payload.type, send_err])
		_abort_map_upload("Failed to upload the map to the server.")
		return

	_map_upload_last_progress_msec = OS.get_ticks_msec()
	if done:
		_map_upload_active = false
		_map_upload_song_id = ""
		_map_upload_b64 = ""
		return
	_map_upload_pos = payload.chunk.length() + _map_upload_pos
	emit_signal("map_upload_progress", _map_upload_song_id, int(_map_upload_pos * 0.75), int(_map_upload_b64.length() * 0.75))

func _abort_map_upload(reason: String):
	var song_id = _map_upload_song_id
	_map_upload_active = false
	_map_upload_song_id = ""
	_map_upload_b64 = ""
	if song_id != "":
		_send({"type": "cancel_map_upload", "song_id": song_id})
	emit_signal("lobby_error", reason)

var _map_publish_start_sent: bool = false
var _map_publish_meta: Dictionary = {}
var _publish_queue: Array = []

func publish_map_to_server(song_id: String):
	if song_id == "":
		return
	if _map_publish_active:
		if not _publish_queue.has(song_id):
			_publish_queue.append(song_id)
		return
	_start_map_publish(song_id)

func _advance_publish_queue():
	if _publish_queue.size() == 0:
		return
	_start_map_publish(_publish_queue.pop_front())

func _start_map_publish(song_id: String):
	var song = Rhythia.registry_song.get_item(song_id, Globals.SEARCH_ID) if Rhythia.registry_song else false
	if not song or not ("filePath" in song):
		emit_signal("lobby_error", "Couldn't find that map locally to publish it.")
		_advance_publish_queue()
		return
	var f = File.new()
	if f.open(song.filePath, File.READ) != OK:
		emit_signal("lobby_error", "Couldn't open the map file to publish it.")
		_advance_publish_queue()
		return
	var bytes = f.get_buffer(f.get_len())
	f.close()
	_map_publish_b64 = Marshalls.raw_to_base64(bytes)
	_map_publish_song_id = song_id
	_map_publish_pos = 0
	_map_publish_active = true
	_map_publish_start_sent = false
	_map_publish_meta = {"total_bytes": bytes.size(), "name": song.name, "creator": song.creator, "difficulty": song.difficulty}
	_map_publish_last_progress_msec = OS.get_ticks_msec()
	if _client.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_DISCONNECTED:
		_connecting_intent = "generic"
		_last_connect_try = -100000 # publishing isn't rate-limited
		_connect_socket()

var _map_publish_next_attempt_msec: int = 0

func _process_map_publish_step():
	if not _map_publish_active:
		return
	if _client.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		# Server unreachable, or the connection dropped mid-upload: give up with
		# an error instead of staying on "Uploading..." (and blocking every later
		# upload) until the game is restarted.
		if _map_publish_start_sent or OS.get_ticks_msec() - _map_publish_last_progress_msec >= 30000:
			_abort_map_publish("Couldn't reach the server to upload the map.")
		return
	if OS.get_ticks_msec() < _map_publish_next_attempt_msec:
		return

	if not _map_publish_start_sent:
		var start_err = _send({
			"type": "publish_map_start", "song_id": _map_publish_song_id,
			"total_bytes": _map_publish_meta.total_bytes, "client_id": Rhythia.cid,
			"name": _map_publish_meta.name, "creator": _map_publish_meta.creator, "difficulty": _map_publish_meta.difficulty,
		})
		if start_err != OK:
			_map_publish_next_attempt_msec = OS.get_ticks_msec() + _MAP_CHUNK_RETRY_COOLDOWN_MSEC
			if OS.get_ticks_msec() - _map_publish_last_progress_msec < 15000:
				return
			_abort_map_publish("Failed to start publishing the map to the server.")
			return
		_map_publish_start_sent = true
		_map_publish_last_progress_msec = OS.get_ticks_msec()
		return

	var done = _map_publish_pos >= _map_publish_b64.length()
	var payload: Dictionary
	if done:
		payload = {"type": "upload_map_end", "song_id": _map_publish_song_id}
	else:
		var chunk_end = min(_map_publish_pos + _MAP_CHUNK_SIZE, _map_publish_b64.length())
		var chunk = _map_publish_b64.substr(_map_publish_pos, chunk_end - _map_publish_pos)
		payload = {"type": "upload_map_chunk", "song_id": _map_publish_song_id, "chunk": chunk}

	var send_err = _send(payload)
	if send_err != OK:
		_map_publish_next_attempt_msec = OS.get_ticks_msec() + _MAP_CHUNK_RETRY_COOLDOWN_MSEC
		if OS.get_ticks_msec() - _map_publish_last_progress_msec < 15000:
			return
		_abort_map_publish("Failed to publish the map to the server.")
		return

	_map_publish_last_progress_msec = OS.get_ticks_msec()
	if done:
		var finished_id = _map_publish_song_id
		_map_publish_active = false
		_map_publish_song_id = ""
		_map_publish_b64 = ""
		emit_signal("map_publish_complete", finished_id)
		_advance_publish_queue()
		return
	_map_publish_pos = payload.chunk.length() + _map_publish_pos
	emit_signal("map_publish_progress", _map_publish_song_id, _map_publish_pos, _map_publish_b64.length())

func _abort_map_publish(reason: String):
	var song_id = _map_publish_song_id
	_map_publish_active = false
	_map_publish_song_id = ""
	_map_publish_b64 = ""
	if song_id != "":
		_send({"type": "cancel_map_upload", "song_id": song_id})
	emit_signal("lobby_error", reason)
	_advance_publish_queue()

func get_map_publish_status(song_id: String):
	if song_id == "":
		return
	_ensure_connected_then_send({"type": "get_map_publish_status", "song_id": song_id})

func _finish_map_download(song_id: String):
	var full_b64 = PoolStringArray(_map_download_chunks).join("")
	_map_download_chunks = []
	_map_download_song_id = ""
	var bytes = Marshalls.base64_to_raw(full_b64)
	print("[furria] map_download_end ", song_id, " — decoded ", bytes.size(), " of ", _map_download_total_bytes, " declared bytes")
	if bytes.size() == 0:
		if watch_mode:
			end_watch("Their map didn't download.")
			return
		emit_signal("lobby_error", "Received an empty map download.")
		return
	if _map_download_total_bytes > 0 and bytes.size() < _map_download_total_bytes * 0.95:
		push_error("[furria] map download size mismatch: got %d, expected %d" % [bytes.size(), _map_download_total_bytes])
		if watch_mode:
			end_watch("Their map didn't download completely.")
			return
		emit_signal("lobby_error", "The map download was incomplete — try again.")
		return
	var dir = Directory.new()
	dir.make_dir_recursive("user://maps")
	var path = "user://maps/%s.sspm" % song_id
	var f = File.new()
	if f.open(path, File.WRITE) != OK:
		emit_signal("lobby_error", "Couldn't save the downloaded map.")
		return
	f.store_buffer(bytes)
	f.close()

	if Rhythia.registry_song:
		Rhythia.registry_song.check_and_remove_id(song_id)
	var song = Rhythia.registry_song.add_sspm_map(path) if Rhythia.registry_song else null
	print("[furria] add_sspm_map(", path, ") -> ", "OK" if song else "FAILED")
	if song:
		emit_signal("map_download_complete", song_id)

		if lobby_active and String(lobby_state.get("song_id", "")) == song_id:
			_send({"type": "map_ready", "song_id": song_id})
			_try_scroll_map_list(song_id)
			if _late_join_pending:
				_scene_transition_now()
	else:
		emit_signal("lobby_error", "Downloaded map failed to import.")

func all_players_ready() -> bool:
	for p in players:
		if not bool(p.get("map_ready", false)):
			return false
	return true

# Who to spectate: the best of those still playing (not you, not failed, not
# done, not joined late, not spectating someone themselves). If nobody is
# still playing, the best of those who didn't fail.
func get_first_place_peer_id() -> int:
	var candidates = []
	for p in players:
		var pid = int(p.get("peer_id", -1))
		if pid == local_peer_id or bool(p.get("failed", false)):
			continue
		if bool(p.get("finished", false)) or bool(p.get("late_join", false)) or int(p.get("spectate_target", -1)) != -1:
			continue
		candidates.append(p)
	if candidates.size() == 0:
		for p in players:
			if int(p.get("peer_id", -1)) != local_peer_id and not bool(p.get("failed", false)):
				candidates.append(p)
	if candidates.size() == 0:
		return -1
	candidates.sort_custom(self, "_sort_players_for_first")
	return int(candidates[0].get("peer_id", -1))

func _sort_players_for_first(a, b) -> bool:
	var acc_a = float(a.get("accuracy", 0.0))
	var acc_b = float(b.get("accuracy", 0.0))
	if acc_a != acc_b:
		return acc_a > acc_b
	var score_a = int(a.get("score", 0))
	var score_b = int(b.get("score", 0))
	if score_a != score_b:
		return score_a > score_b
	return String(a.get("name", "")) < String(b.get("name", ""))


# The name set on the website (savia_web profile.js): the server sends it when
# the game connects and again when it changes. It's the name in lobbies, chat
# and the menu; with none set, your Discord name comes back.
func _apply_server_name(msg: Dictionary):
	var custom := Globals.s(msg.get("custom_name", "")).strip_edges()
	var before := Globals.s(Rhythia.website_name)
	if custom == before:
		return
	Rhythia.website_name = custom
	if custom != "":
		player_name = custom
		_save_player_name()
	elif player_name == before:
		# the website name was taken away: your Discord name again
		var du = Rhythia.discord_user if typeof(Rhythia.discord_user) == TYPE_DICTIONARY else {}
		var nm := Globals.s(du.get("display_name", ""))
		player_name = nm if nm != "" else Globals.s(du.get("username", "Player"))
		_save_player_name()
	Rhythia.emit_signal("discord_login_changed") # (the menu shows names again)

func _handle_message(msg: Dictionary):
	match Globals.s(msg.get("type", "")):
		"auth_ok", "display_name_changed":
			if msg.get("player_number") != null:
				my_player_number = int(msg.get("player_number")) # (the Profile page falls back to it)
			_apply_server_name(msg)
		"lobby_created":
			lobby_code = Globals.s(msg.get("code", ""))
			local_peer_id = int(msg.get("peer_id", -1))
			is_host = true
			lobby_active = true

			if Rhythia.selected_song != null:
				set_lobby_song(Rhythia.selected_song)
			push_current_mods()
			emit_signal("lobby_created", lobby_code)
			emit_signal("lobby_state_changed")
		"lobby_joined":
			lobby_code = Globals.s(msg.get("code", ""))
			local_peer_id = int(msg.get("peer_id", -1))
			is_host = false
			lobby_active = true
			_late_join_pending = bool(msg.get("started", false))
			if bool(msg.get("watch", false)):
				# from the Spectate tab: watching one player (in their lobby, or
				# a watch room the server makes around a solo player)
				watch_mode = true
				watch_target_name = Globals.s(msg.get("target_name", ""))
				_spectate_load_target = int(msg.get("target_peer", -1))
				_watch_first_load = true
			emit_signal("lobby_joined", lobby_code)
			emit_signal("lobby_state_changed")
		"lobby_state":
			if not lobby_active:
				return # (a lobby you just left)
			lobby_state = msg.get("state", lobby_state)
			players = msg.get("players", players)
			var specs = msg.get("spectators", [])
			lobby_spectators = specs if specs is Array else []

			for p in players:
				if int(p.get("peer_id", -1)) == local_peer_id:
					is_host = bool(p.get("is_host", is_host))

			if not is_host:
				_apply_mods_locally(lobby_state.get("mods", {}))
			_check_map_readiness()
			_try_scroll_map_list(String(lobby_state.get("song_id", "")))
			emit_signal("lobby_state_changed")
		"game_started":
			lobby_state = msg.get("state", lobby_state)
			print("[furria] applying mods before transition: ", lobby_state.get("mods", {}))
			if not is_host:
				_apply_mods_locally(lobby_state.get("mods", {}))
			Rhythia.apply_lobby_lead_in()
			print("[furria] Rhythia.mod_speed_level after apply: ", Rhythia.mod_speed_level)
			var t = get_tree().create_timer(0.4)
			t.connect("timeout", self, "_scene_transition_now")
			emit_signal("game_started")
		"skip_triggered":
			emit_signal("skip_triggered", float(msg.get("target_ms", 0)))
		"error":
			var reason := Globals.s(msg.get("reason", "Unknown error"))
			if reason.find("Unknown message type") != -1 or reason.find("hello") != -1 or reason.find("presence") != -1:
				# an older server without the Spectate tab: nothing to show
				if reason.find("hello") != -1 or reason.find("presence") != -1:
					_set_presence_supported(0)
				return
			if watch_mode and not lobby_active:
				_finish_watch_locally()
			emit_signal("lobby_error", reason)
			if not lobby_active:
				close_lobby()
				emit_signal("lobby_state_changed") # e.g. a failed join: the panel kept saying "Joining lobby..."
		"player_settings":
			var sp = int(msg.get("peer_id", -1))
			var ss = msg.get("settings", null)
			player_view_settings[sp] = ss if ss is Dictionary else {}
			fetch_spectate_assets(player_view_settings[sp])
			emit_signal("player_settings_received", sp)
			if _watch_wait_t > 0.0 and watch_mode and sp == _spectate_load_target and has_player_settings(sp):
				if spectate_assets_ready():
					_watch_wait_t = 0.0
					_scene_transition_now()
				else:
					_watch_wait_t = max(_watch_wait_t, 4.0) # (their border / mesh downloading)
		"live_state":
			var peer_id = int(msg.get("peer_id", -1))
			_live_state_cache[peer_id] = msg
			emit_signal("live_state_received",
				peer_id, float(msg.get("x", 0)), float(msg.get("y", 0)), int(msg.get("combo", 0)), int(msg.get("combo_level", 1)),
				int(msg.get("score", 0)), int(msg.get("hits", 0)), int(msg.get("misses", 0)), int(msg.get("total_notes", 0)),
				float(msg.get("energy_pct", 0.0)), float(msg.get("lvl_progress_pct", 0.0)), float(msg.get("ms", 0.0)))
		"player_failed":
			var fp = int(msg.get("peer_id", -1))
			for p in players:
				if int(p.get("peer_id", -1)) == fp:
					p["failed"] = true
			emit_signal("player_failed", fp)
		"player_missing_map":
			var mmp = int(msg.get("peer_id", -1))
			for p in players:
				if int(p.get("peer_id", -1)) == mmp:
					p["missing_map"] = true
			emit_signal("player_missing_map", mmp)
		"request_map_upload":
			var upload_song_id = Globals.s(msg.get("song_id", ""))
			print("[furria] received request_map_upload for ", upload_song_id)
			if upload_song_id != "":
				_start_map_upload(upload_song_id)
		"map_download_start":
			_map_download_song_id = Globals.s(msg.get("song_id", ""))
			_map_download_chunks = []
			_map_download_chars_received = 0
			_map_download_total_bytes = int(msg.get("total_bytes", 0))
			print("[furria] map_download_start ", _map_download_song_id, " (", _map_download_total_bytes, " bytes)")
			emit_signal("map_download_started", _map_download_song_id)
			emit_signal("map_download_progress", _map_download_song_id, 0, _map_download_total_bytes)
		"map_download_chunk":
			if Globals.s(msg.get("song_id", "")) == _map_download_song_id:
				var chunk_str = Globals.s(msg.get("chunk", ""))
				_map_download_chunks.append(chunk_str)
				_map_download_chars_received += chunk_str.length()
				var approx_bytes = int(_map_download_chars_received * 0.75)
				emit_signal("map_download_progress", _map_download_song_id, approx_bytes, _map_download_total_bytes)
		"map_download_end":
			var dl_song_id = Globals.s(msg.get("song_id", ""))
			if dl_song_id == _map_download_song_id and dl_song_id != "":
				_finish_map_download(dl_song_id)
		"map_unavailable":
			print("[furria] map_unavailable: ", Globals.s(msg.get("reason", "")))
			if watch_mode:
				end_watch("Couldn't get their map: " + Globals.s(msg.get("reason", "it isn't available.")))
				return
			emit_signal("lobby_error", Globals.s(msg.get("reason", "That map isn't available.")))
		"server_hello":
			var feats = msg.get("features", [])
			_set_presence_supported(1 if (feats is Array and feats.has("presence")) else 0)
		"online_players":
			var lst = msg.get("players", [])
			online_players = lst if lst is Array else []
			my_player_number = int(msg.get("you", -1)) if msg.get("you") != null else -1
			i_am_staff = bool(msg.get("you_staff", false))
			emit_signal("online_players_received", online_players, my_player_number)
			_check_follow(online_players)
		"spectate_denied":
			if watch_mode and not lobby_active:
				_finish_watch_locally()
			emit_signal("spectate_denied", Globals.s(msg.get("reason", "You can't watch them right now.")))
		"watch_ended":
			if Globals.s(msg.get("reason", "")) == "disabled":
				follow_number = -1 # (they don't want spectators: no following either)
			end_watch(Globals.s(msg.get("text", "They stopped playing.")))
		"watchers_changed":
			var was := watchers_count
			watchers_count = int(msg.get("count", 0))
			var nm = msg.get("names", [])
			watcher_names = nm if nm is Array else []
			if watchers_count > 0 and was == 0 and Rhythia.in_map:
				send_view_settings() # so they see it your way
				var game = get_tree().current_scene.find_node("Game", true, false) if get_tree().current_scene else null
				if game != null and game.has_method("_sync_lobby_stats"):
					game._sync_lobby_stats()
			if watchers_count > was and not watcher_names.empty():
				pass # (no pop-up: the Spectators list in the top left shows who's watching)
			emit_signal("watchers_changed", watchers_count, watcher_names)
		"round_ended":
			if watch_mode:
				end_watch("The round ended.")
				return
			emit_signal("round_ended")
		"all_players_loaded":
			emit_signal("all_players_loaded")
		"lobby_closed":
			if watch_mode:
				end_watch("The lobby closed.")
				return
			close_lobby()
		"chat_message":
			var lm_peer_id = int(msg.get("peer_id", -1))
			var lm_name = Globals.s(msg.get("name", ""))
			var lm_text = Globals.s(msg.get("text", ""))
			var lm_ts = float(msg.get("ts", 0))
			lobby_chat_history.append({peer_id = lm_peer_id, name = lm_name, text = lm_text, ts = lm_ts})
			if lobby_chat_history.size() > CHAT_HISTORY_MAX:
				lobby_chat_history.pop_front()
			emit_signal("chat_message_received", lm_peer_id, lm_name, lm_text, lm_ts)
		"global_chat_message":
			var gm_client_id = Globals.s(msg.get("client_id", ""))
			var gm_name = Globals.s(msg.get("name", ""))
			var gm_text = Globals.s(msg.get("text", ""))
			var gm_ts = float(msg.get("ts", 0))
			global_chat_history.append({client_id = gm_client_id, name = gm_name, text = gm_text, ts = gm_ts})
			if global_chat_history.size() > CHAT_HISTORY_MAX:
				global_chat_history.pop_front()
			emit_signal("global_chat_message_received", gm_client_id, gm_name, gm_text, gm_ts)
		"announcement":
			var announce_text = Globals.s(msg.get("text", ""))
			var announce_from = Globals.s(msg.get("from_name", ""))
			emit_signal("announcement_received", announce_text, announce_from, float(msg.get("ts", 0)))
			if Rhythia.in_map:
				_pending_announcement = {"text": announce_text, "from_name": announce_from}
			else:
				_show_announcement_banner(announce_text, announce_from)
		"public_lobbies":
			emit_signal("public_lobbies_received", msg.get("lobbies", []))
		"admin_all_lobbies":
			emit_signal("admin_all_lobbies_received", msg.get("lobbies", []))
		"admin_bans":
			emit_signal("admin_bans_received", msg.get("bans", []))
		"admin_live_bans":
			emit_signal("admin_live_bans_received", msg.get("bans", []))
		"admin_player_tags":
			emit_signal("admin_player_tags_received", msg.get("tags", []))
		"admin_rankers":
			emit_signal("admin_rankers_received", msg.get("rankers", []))
		"admin_map_ranks":
			emit_signal("admin_map_ranks_received", msg.get("ranks", []))
		"ranker_status":
			emit_signal("ranker_status_received", bool(msg.get("is_ranker", false)))
		"map_rank_info":
			emit_signal("map_rank_info_received", Globals.s(msg.get("song_id", "")), bool(msg.get("ranked", false)), int(msg.get("xp", 0)), Globals.s(msg.get("content_hash", "")))
		"my_map_stats":
			emit_signal("my_map_stats_received", Globals.s(msg.get("song_id", "")), bool(msg.get("has_passed", false)), int(msg.get("best_xp", 0)), int(msg.get("best_sp", 0)))
		"client_id_rotated":
			Rhythia.apply_rotated_client_id(Globals.s(msg.get("new_client_id", "")))
		"ranked_maps":
			emit_signal("ranked_maps_received", msg.get("song_ids", []))
		"unpublished_ranked_maps":
			emit_signal("unpublished_ranked_maps_received", msg.get("song_ids", []))
		"set_map_rank_ok":
			emit_signal("set_map_rank_result", true, Globals.s(msg.get("song_id", "")), int(msg.get("xp", 0)))
		"rank_denied":
			emit_signal("set_map_rank_result", false, "", 0)
		"map_publish_status":
			emit_signal("map_publish_status_received", Globals.s(msg.get("song_id", "")), bool(msg.get("published", false)))
		"admin_ban_ok", "admin_unban_ok":
			admin_list_bans()
		"admin_denied":
			emit_signal("lobby_error", "Admin action denied — check your admin key.")

func _scene_transition_now():
	if not lobby_active:
		return
	if _late_join_pending and (_spectate_load_target == -1 or _watch_first_load):
		_watch_first_load = false
		var spec = load("res://scripts/SpectateSettings.gd")
		var first = _spectate_load_target if (watch_mode and _spectate_load_target != -1) else get_first_place_peer_id()
		if spec.prefer_theirs() and first != -1 and has_player_settings(first):
			spec.apply(player_view_settings[first], first)
	if lobby_state.has("song_id") and lobby_state.song_id != "":
		var song = Rhythia.registry_song.get_item(lobby_state.song_id, Globals.SEARCH_ID) if Rhythia.registry_song else null
		var _n_notes: int = -1
		if song:
			Rhythia.lock_song_notes(song) # the star rater may be reading this map's notes
			var got = song.read_notes()
			Rhythia.unlock_song_notes(song)
			_n_notes = got.size() if got is Array else 0
		if song and _n_notes == 0:
			print("[furria] cached song ", lobby_state.song_id, " has 0 notes — treating as missing, re-requesting")
			if song.note_count <= 0:
				_send({"type": "report_corrupt_map", "song_id": lobby_state.song_id})
			if Rhythia.registry_song:
				Rhythia.registry_song.check_and_remove_id(lobby_state.song_id)
			song = null
		if song:
			Rhythia.selected_song = song
			Rhythia.emit_signal("selected_song_changed", song)
		else:
			emit_signal("lobby_error", "You don't have this map — downloading it now...")
			report_missing_map()
			request_map(lobby_state.song_id)
			return
	get_tree().change_scene("res://scenes/loaders/songload.tscn")


# --- Online, and the Spectate tab --------------------------------------------------
# Servers from Savia server 2.1 on keep a list of who's online and what they
# play, and let anyone watch anyone (in a lobby or not). The game says hello
# when it connects; a server that answers with server_hello gets a lasting
# connection and your presence (menu / playing what, spectators allowed),
# re-sent whenever it changes. Older servers just see the hello and nothing
# changes for them.
#
# Watching from the Spectate tab looks to the rest of the game like a late
# join into a lobby (lobby_joined with watch): the spectate code in HUD.gd
# works as it is. watch_mode marks it; the menu loading (menuload.gd) ends
# it, and the server saying it ended brings you back to the menu, with your
# own mods back.
#
# When someone watches you outside a lobby (watchers_count > 0), the game
# sends your live state, stats and display settings as it does in a lobby.

var presence_supported: int = -1 # -1 not known yet, 0 no, 1 yes
var online_players: Array = []
var my_player_number: int = -1
var watch_mode: bool = false
var i_am_staff: bool = false # Owner / Administrator: may watch players with spectators off (Spectate anyway)
var lobby_spectators: Array = [] # lobby_state.spectators: {peer_id, name, target}
var watch_target_name: String = ""
var watchers_count: int = 0
var watcher_names: Array = []
var _watch_first_load: bool = false
var _watch_wait_t: float = 0.0
var reopen_spectate_tab: bool = false # the menu opens on the Spectate tab after watching
var _watch_mods_backup = null
var _online_subscribed: bool = false
var _presence_sent: String = ""
var _presence_t: float = 0.0
var _presence_hello_t: float = -1.0
var _presence_retry_t: float = 3.0 # the first connect, a moment after the game starts
var _presence_failures: int = 0

# sending your play to whoever watches you (in a lobby, or watched alone)
func broadcasting() -> bool:
	if lobby_active:
		return not watch_mode
	return watchers_count > 0

func _set_presence_supported(v: int):
	if presence_supported == v:
		return
	presence_supported = v
	if v == 1:
		_presence_failures = 0
		_send_presence(true)
		if _online_subscribed:
			_send({"type": "subscribe_online"})
	emit_signal("presence_support_changed", v == 1)

func _connected() -> bool:
	return _client.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_CONNECTED

func _presence_tick(delta: float):
	if Rhythia == null or String(Rhythia.cid) == "":
		return
	if _connected():
		if presence_supported == -1:
			if _presence_hello_t < 0.0:
				_presence_hello_t = 0.0
			_presence_hello_t += delta
			if _presence_hello_t > 8.0:
				_set_presence_supported(0) # no answer: an older server
		_presence_t += delta
		if _presence_t >= 1.0:
			_presence_t = 0.0
			_send_presence(false)
		if _watch_wait_t > 0.0:
			_watch_wait_t -= delta
			if _watch_wait_t <= 0.0 and watch_mode:
				_scene_transition_now() # (their settings didn't come: yours)
		return
	_presence_hello_t = -1.0
	_presence_sent = ""
	if presence_supported == 0:
		return # an older server: connects only when needed, as before
	if _client.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_CONNECTING:
		return
	_presence_retry_t -= delta
	if _presence_retry_t <= 0.0:
		# reconnect: soon at first, then less often while the server is down
		_presence_failures += 1
		_presence_retry_t = min(10.0 * _presence_failures, 120.0)
		_connecting_intent = "generic"
		_last_connect_try = -100000
		_connect_socket()

func _presence_name() -> String:
	var n := ""
	if Rhythia.discord_user is Dictionary:
		n = String(Rhythia.discord_user.get("display_name", ""))
		if n == "" or n == "Null":
			n = String(Rhythia.discord_user.get("username", ""))
	if n == "" and player_name != "Player":
		n = player_name
	return n.substr(0, 32)

func _presence_device() -> String:
	if Rhythia.vr:
		return "quest" if OS.has_feature("quest") else "vr"
	if OS.has_feature("JavaScript"):
		return "web"
	if OS.has_feature("Android") or OS.has_feature("iOS"):
		return "mobile"
	return "pc"

func _presence_now() -> Dictionary:
	var spectating_someone := watch_mode
	var game = null
	if Rhythia.in_map and get_tree().current_scene != null:
		game = get_tree().current_scene.find_node("Game", true, false)
		var hud = game.get_node_or_null("HUD") if game != null else null
		if hud != null and bool(hud.get("spectating")):
			spectating_someone = true
	var playing: bool = Rhythia.in_map and not Rhythia.replaying and not spectating_someone and Rhythia.selected_song != null
	var p := {
		"type": "presence", "client_id": Rhythia.cid, "name": _presence_name(),
		"status": "playing" if playing else "menu",
		"allow_spectate": bool(Rhythia.allow_spectators),
		"device": _presence_device(),
	}
	if playing:
		var s = Rhythia.selected_song
		p["song_id"] = String(s.id).substr(0, 200)
		p["song_name"] = String(s.name).substr(0, 200)
		p["song_creator"] = String(s.get("creator") if s.get("creator") != null else "").substr(0, 100)
		var d = s.get("difficulty")
		p["difficulty"] = clamp(float(d), -1.0, 100.0) if d != null else -1.0
		p["mods"] = _collect_current_mods()
	return p

func _send_presence(force: bool):
	if presence_supported != 1 or not _connected():
		return
	var p := _presence_now()
	var key := JSON.print(p)
	if key == _presence_sent and not force:
		return
	_presence_sent = key
	_send(p)

# right away (a setting changed, a song started)
func update_presence():
	_send_presence(false)

# Following: after a watch ends (they finished, failed or left the map) you
# watch them again as soon as they start playing, while you're in the menu.
# It stops when you leave (Stop watching), when you play a map yourself, when
# they turn spectators off, or after FOLLOW_GIVE_UP_MSEC without them playing.
var follow_number: int = -1
var _follow_ended_at: int = 0
var _follow_last_seen: int = 0
var _follow_tried_at: int = 0
const FOLLOW_GIVE_UP_MSEC := 15 * 60 * 1000

func _check_follow(list: Array):
	if follow_number <= 0 or watch_mode or lobby_active:
		return
	var now := OS.get_ticks_msec()
	if Rhythia.in_map:
		# (right after a watch ends the game is still on its way back to the menu)
		if now - _follow_ended_at > 8000:
			follow_number = -1 # you're playing yourself
		return
	if now - _follow_last_seen > FOLLOW_GIVE_UP_MSEC:
		follow_number = -1
		return
	if now - _follow_tried_at < 3000:
		return
	for p in list:
		if not (p is Dictionary) or int(p.get("number", -1)) != follow_number:
			continue
		if Globals.s(p.get("status", "")) != "playing":
			_follow_last_seen = now
			return
		# a song they started after the last watch ended (not the one that just ended)
		var since_ms: int = int(p.get("since_s", 0)) * 1000
		if since_ms > now - _follow_ended_at:
			return
		var can: bool = bool(p.get("can_spectate", false)) or (i_am_staff and bool(p.get("can_spectate_staff", false)))
		if not can:
			return
		_follow_tried_at = now
		Globals.notify(Globals.NOTIFY_INFO, "%s is playing again: watching." % Globals.s(p.get("name", "They")), "Spectating")
		spectate_player(follow_number)
		return

func subscribe_online():
	_online_subscribed = true
	if presence_supported == 1 and _connected():
		_send({"type": "subscribe_online"})
	elif not _connected():
		_presence_retry_t = 0.0

func unsubscribe_online():
	_online_subscribed = false
	if _connected():
		_send({"type": "unsubscribe_online"})

func spectate_player(number: int) -> bool:
	if lobby_active and not watch_mode:
		emit_signal("spectate_denied", "Leave your lobby first.")
		return false
	if presence_supported != 1 or not _connected():
		emit_signal("spectate_denied", "Not connected to the server.")
		return false
	if _watch_mods_backup == null:
		_watch_mods_backup = _collect_current_mods()
	if follow_number != number:
		follow_number = number
	_follow_last_seen = OS.get_ticks_msec()
	_send({"type": "spectate_player", "number": number, "name": _presence_name() if _presence_name() != "" else player_name, "client_id": Rhythia.cid})
	return true

# you leave (back to the menu)
func stop_watching():
	follow_number = -1 # (you left: no following)
	if not watch_mode:
		return
	if _connected():
		_send({"type": "stop_watching"})
	_finish_watch_locally()

# the server ended it (they finished, failed, left, turned spectators off)
func end_watch(text: String):
	if not watch_mode:
		return
	var in_song: bool = Rhythia.in_map
	if _connected():
		_send({"type": "stop_watching"}) # (out of their lobby, if it was one)
	_finish_watch_locally()
	_follow_ended_at = OS.get_ticks_msec()
	_follow_last_seen = _follow_ended_at
	if follow_number > 0:
		subscribe_online() # (to see when they play again)
		text += " You'll watch them again when they play."
	Globals.notify(Globals.NOTIFY_INFO, text, "Spectating")
	if in_song:
		get_tree().paused = false
		get_tree().change_scene("res://scenes/loaders/menuload.tscn")

func _finish_watch_locally():
	if watch_mode:
		reopen_spectate_tab = true
	watch_mode = false
	_watch_wait_t = 0.0
	_watch_first_load = false
	watch_target_name = ""
	_late_join_pending = false
	# leave the lobby state without dropping the connection
	lobby_active = false
	is_host = false
	lobby_code = ""
	local_peer_id = -1
	players = []
	lobby_spectators = []
	lobby_state = {"song_id": "", "song_name": "", "started": false, "host_name": ""}
	_map_readiness_checked_song_id = ""
	lobby_chat_history = []
	player_view_settings = {}
	_spectate_load_target = -1
	if _watch_mods_backup is Dictionary:
		_apply_mods_locally(_watch_mods_backup)
	_watch_mods_backup = null
	emit_signal("lobby_state_changed")

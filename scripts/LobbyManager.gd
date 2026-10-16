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
	return _connect_socket()

func join_lobby(code: String, name: String) -> bool:
	close_lobby()
	player_name = name
	_pending_name = name
	_pending_code = code
	_connecting_intent = "join"
	return _connect_socket()

func _ensure_connected_then_send(payload: Dictionary):
	if _client.get_connection_status() == NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
		_send(payload)
		return
	_pending_send_after_connect.append(payload)
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
		_client.disconnect_from_host()

	var was_active = lobby_active
	lobby_active = false
	is_host = false
	lobby_code = ""
	local_peer_id = -1
	players = []
	lobby_state = {"song_id": "", "song_name": "", "started": false, "host_name": ""}
	_map_readiness_checked_song_id = ""
	_last_scrolled_song_id = ""
	lobby_chat_history = []
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
	if not lobby_active:
		return
	_send({"type": "update_stats", "score": score, "hits": hits, "misses": misses, "total_notes": total_notes})

func start_game():
	print("[savia] start_game() called, lobby_active=", lobby_active, " is_host=", is_host)
	if lobby_active and is_host:
		_send({"type": "start_game"})
		print("[savia] start_game message sent")

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


func _connect_socket() -> bool:
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

func _on_connected(_proto = ""):
	if _connecting_intent == "create":
		var msg = {"type": "create_lobby", "name": _pending_name, "client_id": Rhythia.cid, "is_public": _pending_is_public}
		msg.merge(_discord_identity_fields())
		_send(msg)
	elif _connecting_intent == "join":
		var msg = {"type": "join_lobby", "code": _pending_code, "name": _pending_name, "client_id": Rhythia.cid}
		msg.merge(_discord_identity_fields())
		_send(msg)
	elif _connecting_intent == "generic" and not _pending_send_after_connect.empty():
		var queued = _pending_send_after_connect
		_pending_send_after_connect = []
		for msg in queued:
			_send(msg)

func _on_closed(was_clean: bool = false):
	if lobby_active and not was_clean:
		emit_signal("lobby_error", "Disconnected from the server — the lobby may no longer exist.")
	close_lobby()

func _on_conn_error():
	if _connecting_intent == "create" or _connecting_intent == "join":
		emit_signal("lobby_error", "Could not reach server")
	close_lobby()

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
	Rhythia.mod_360 = mods.get("mod_360", Rhythia.mod_360)
	Rhythia.mod_360_speed = mods.get("mod_360_speed", Rhythia.mod_360_speed)
	Rhythia.mod_strobe = mods.get("strobe", Rhythia.mod_strobe)
	Rhythia.start_offset = mods.get("start_offset", Rhythia.start_offset)

	if Rhythia.has_signal("mods_changed"):
		Rhythia.emit_signal("mods_changed")

func send_live_state(x: float, y: float, combo: int, combo_level: int, energy_pct: float, lvl_progress_pct: float, chart_ms: float):
	if not lobby_active:
		return
	_send({
		"type": "update_live_state", "x": x, "y": y, "combo": combo, "combo_level": combo_level,
		"energy_pct": energy_pct, "lvl_progress_pct": lvl_progress_pct, "ms": chart_ms,
	})
func notify_passed():
	if not lobby_active:
		return
	_send({"type": "player_passed"})

func notify_failed():
	if not lobby_active:
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
			_scene_transition_now()
	else:
		report_missing_map()
		request_map(song_id)

var _last_scrolled_song_id: String = ""
func _try_scroll_map_list(song_id: String):
	if is_host or song_id == "" or song_id == _last_scrolled_song_id:
		return
	var map_list = get_tree().get_root().get_node_or_null("Menu/Main/Maps/MapRegistry/S/VBoxContainer")
	if map_list == null or not map_list.has_method("scroll_to_song"):
		return

	if map_list.scroll_to_song(song_id):
		_last_scrolled_song_id = song_id

func _start_map_upload(song_id: String):
	print("[savia] _start_map_upload(", song_id, ") is_host=", is_host, " active=", _map_upload_active)
	if _map_upload_active:
		print("[savia] upload aborted: already have one in flight for ", _map_upload_song_id)
		return
	if not is_host:
		print("[savia] upload aborted: this client isn't the host (server shouldn't have asked)")
		return
	var song = Rhythia.registry_song.get_item(song_id, Globals.SEARCH_ID) if Rhythia.registry_song else false
	if not song or not ("filePath" in song):
		print("[savia] upload aborted: song not found in local registry for id ", song_id)
		return
	var f = File.new()
	var open_err = f.open(song.filePath, File.READ)
	if open_err != OK:
		print("[savia] upload aborted: couldn't open ", song.filePath, " (error ", open_err, ")")
		return
	var bytes = f.get_buffer(f.get_len())
	f.close()
	print("[savia] uploading ", song.filePath, " — ", bytes.size(), " bytes")
	_map_upload_b64 = Marshalls.raw_to_base64(bytes)
	_map_upload_song_id = song_id
	_map_upload_pos = 0
	_map_upload_active = true
	_map_upload_last_progress_msec = OS.get_ticks_msec()
	var start_err = _send({"type": "upload_map_start", "song_id": song_id, "total_bytes": bytes.size()})
	if start_err != OK:
		push_error("[savia] upload_map_start failed to send: %s" % start_err)
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
		push_error("[savia] map upload stalled (%s), giving up: %s" % [payload.type, send_err])
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
		_connect_socket()

var _map_publish_next_attempt_msec: int = 0

func _process_map_publish_step():
	if not _map_publish_active:
		return
	if _client.get_connection_status() != NetworkedMultiplayerPeer.CONNECTION_CONNECTED:
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
	print("[savia] map_download_end ", song_id, " — decoded ", bytes.size(), " of ", _map_download_total_bytes, " declared bytes")
	if bytes.size() == 0:
		emit_signal("lobby_error", "Received an empty map download.")
		return
	if _map_download_total_bytes > 0 and bytes.size() < _map_download_total_bytes * 0.95:
		push_error("[savia] map download size mismatch: got %d, expected %d" % [bytes.size(), _map_download_total_bytes])
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
	print("[savia] add_sspm_map(", path, ") -> ", "OK" if song else "FAILED")
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

func get_first_place_peer_id() -> int:
	var candidates = []
	for p in players:
		if not bool(p.get("failed", false)):
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


func _handle_message(msg: Dictionary):
	match String(msg.get("type", "")):
		"lobby_created":
			lobby_code = String(msg.get("code", ""))
			local_peer_id = int(msg.get("peer_id", -1))
			is_host = true
			lobby_active = true

			if Rhythia.selected_song != null:
				set_lobby_song(Rhythia.selected_song)
			push_current_mods()
			emit_signal("lobby_created", lobby_code)
			emit_signal("lobby_state_changed")
		"lobby_joined":
			lobby_code = String(msg.get("code", ""))
			local_peer_id = int(msg.get("peer_id", -1))
			is_host = false
			lobby_active = true
			_late_join_pending = bool(msg.get("started", false))
			emit_signal("lobby_joined", lobby_code)
			emit_signal("lobby_state_changed")
		"lobby_state":
			lobby_state = msg.get("state", lobby_state)
			players = msg.get("players", players)

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
			print("[savia] applying mods before transition: ", lobby_state.get("mods", {}))
			if not is_host:
				_apply_mods_locally(lobby_state.get("mods", {}))
			Rhythia.apply_lobby_lead_in()
			print("[savia] Rhythia.mod_speed_level after apply: ", Rhythia.mod_speed_level)
			var t = get_tree().create_timer(0.4)
			t.connect("timeout", self, "_scene_transition_now")
			emit_signal("game_started")
		"skip_triggered":
			emit_signal("skip_triggered", float(msg.get("target_ms", 0)))
		"error":
			emit_signal("lobby_error", String(msg.get("reason", "Unknown error")))
			if not lobby_active:
				close_lobby()
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
			var upload_song_id = String(msg.get("song_id", ""))
			print("[savia] received request_map_upload for ", upload_song_id)
			if upload_song_id != "":
				_start_map_upload(upload_song_id)
		"map_download_start":
			_map_download_song_id = String(msg.get("song_id", ""))
			_map_download_chunks = []
			_map_download_chars_received = 0
			_map_download_total_bytes = int(msg.get("total_bytes", 0))
			print("[savia] map_download_start ", _map_download_song_id, " (", _map_download_total_bytes, " bytes)")
			emit_signal("map_download_started", _map_download_song_id)
			emit_signal("map_download_progress", _map_download_song_id, 0, _map_download_total_bytes)
		"map_download_chunk":
			if String(msg.get("song_id", "")) == _map_download_song_id:
				var chunk_str = String(msg.get("chunk", ""))
				_map_download_chunks.append(chunk_str)
				_map_download_chars_received += chunk_str.length()
				var approx_bytes = int(_map_download_chars_received * 0.75)
				emit_signal("map_download_progress", _map_download_song_id, approx_bytes, _map_download_total_bytes)
		"map_download_end":
			var dl_song_id = String(msg.get("song_id", ""))
			if dl_song_id == _map_download_song_id and dl_song_id != "":
				_finish_map_download(dl_song_id)
		"map_unavailable":
			print("[savia] map_unavailable: ", String(msg.get("reason", "")))
			emit_signal("lobby_error", String(msg.get("reason", "That map isn't available.")))
		"round_ended":
			emit_signal("round_ended")
		"all_players_loaded":
			emit_signal("all_players_loaded")
		"lobby_closed":
			close_lobby()
		"chat_message":
			var lm_peer_id = int(msg.get("peer_id", -1))
			var lm_name = String(msg.get("name", ""))
			var lm_text = String(msg.get("text", ""))
			var lm_ts = float(msg.get("ts", 0))
			lobby_chat_history.append({peer_id = lm_peer_id, name = lm_name, text = lm_text, ts = lm_ts})
			if lobby_chat_history.size() > CHAT_HISTORY_MAX:
				lobby_chat_history.pop_front()
			emit_signal("chat_message_received", lm_peer_id, lm_name, lm_text, lm_ts)
		"global_chat_message":
			var gm_client_id = String(msg.get("client_id", ""))
			var gm_name = String(msg.get("name", ""))
			var gm_text = String(msg.get("text", ""))
			var gm_ts = float(msg.get("ts", 0))
			global_chat_history.append({client_id = gm_client_id, name = gm_name, text = gm_text, ts = gm_ts})
			if global_chat_history.size() > CHAT_HISTORY_MAX:
				global_chat_history.pop_front()
			emit_signal("global_chat_message_received", gm_client_id, gm_name, gm_text, gm_ts)
		"announcement":
			var announce_text = String(msg.get("text", ""))
			var announce_from = String(msg.get("from_name", ""))
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
			emit_signal("map_rank_info_received", String(msg.get("song_id", "")), bool(msg.get("ranked", false)), int(msg.get("xp", 0)), String(msg.get("content_hash", "")))
		"my_map_stats":
			emit_signal("my_map_stats_received", String(msg.get("song_id", "")), bool(msg.get("has_passed", false)), int(msg.get("best_xp", 0)), int(msg.get("best_sp", 0)))
		"client_id_rotated":
			Rhythia.apply_rotated_client_id(String(msg.get("new_client_id", "")))
		"ranked_maps":
			emit_signal("ranked_maps_received", msg.get("song_ids", []))
		"unpublished_ranked_maps":
			emit_signal("unpublished_ranked_maps_received", msg.get("song_ids", []))
		"set_map_rank_ok":
			emit_signal("set_map_rank_result", true, String(msg.get("song_id", "")), int(msg.get("xp", 0)))
		"rank_denied":
			emit_signal("set_map_rank_result", false, "", 0)
		"map_publish_status":
			emit_signal("map_publish_status_received", String(msg.get("song_id", "")), bool(msg.get("published", false)))
		"admin_ban_ok", "admin_unban_ok":
			admin_list_bans()
		"admin_denied":
			emit_signal("lobby_error", "Admin action denied — check your admin key.")

func _scene_transition_now():
	if not lobby_active:
		return
	if lobby_state.has("song_id") and lobby_state.song_id != "":
		var song = Rhythia.registry_song.get_item(lobby_state.song_id, Globals.SEARCH_ID) if Rhythia.registry_song else null
		if song and song.read_notes().size() == 0:
			print("[savia] cached song ", lobby_state.song_id, " has 0 notes — treating as missing, re-requesting")
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

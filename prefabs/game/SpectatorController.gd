
extends Node

var spectating: bool = false
var target_peer_id: int = -1
var ghost_cursor: Node2D = null

func _get_lobby_manager():
	return get_node_or_null("/root/LobbyManager")

func enter_spectate_mode():
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null or not lobby_manager.lobby_active:
		return
	spectating = true

	var spawn = get_tree().get_root().find_node("Spawn", true, false)
	if spawn != null:
		spawn.set_process_input(false)
		spawn.set_process_unhandled_input(false)

	_pick_new_target()
	if not lobby_manager.is_connected("live_state_received", self, "_on_live_state"):
		lobby_manager.connect("live_state_received", self, "_on_live_state")
	if not lobby_manager.is_connected("lobby_state_changed", self, "_on_lobby_state_changed_while_spectating"):
		lobby_manager.connect("lobby_state_changed", self, "_on_lobby_state_changed_while_spectating")

	_create_ghost_cursor()
	_create_spectate_banner()

func _pick_new_target():
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	target_peer_id = lobby_manager.get_first_place_peer_id()
	_update_spectate_banner_name()

func _on_lobby_state_changed_while_spectating():
	if not spectating:
		return
	var lobby_manager = _get_lobby_manager()
	if lobby_manager == null:
		return
	var current_target_failed = false
	for p in lobby_manager.players:
		if int(p.get("peer_id", -1)) == target_peer_id and bool(p.get("failed", false)):
			current_target_failed = true
	var new_first = lobby_manager.get_first_place_peer_id()
	if current_target_failed or new_first != target_peer_id:
		if new_first != -1 and new_first != target_peer_id:
			target_peer_id = new_first
			_update_spectate_banner_name()

func _on_live_state(peer_id, x, y, combo, score, hits, misses, total_notes):
	if not spectating or peer_id != target_peer_id:
		return
	if ghost_cursor != null:
		ghost_cursor.global_position = Vector2(x, y)


	var hud = get_tree().get_root().find_node("HUD", true, false)
	if hud != null:
		if hud.has_method("set_spectated_stats"):
			hud.set_spectated_stats(score, hits, misses, total_notes, combo)

func _create_ghost_cursor():
	if ghost_cursor != null:
		return
	ghost_cursor = Node2D.new()
	ghost_cursor.name = "SpectatorGhostCursor"
	var sprite = Sprite.new()
	var tex = Globals.imageLoader.load_if_exists("user://cursor") if ResourceLoader.exists("user://cursor") else null
	if tex != null:
		sprite.texture = tex
		sprite.modulate = Color(1, 0.85, 0.2, 0.85)
	ghost_cursor.add_child(sprite)
	get_tree().get_root().add_child(ghost_cursor)

var _spectate_banner: Label = null
func _create_spectate_banner():
	if _spectate_banner != null:
		return
	var canvas = CanvasLayer.new()
	canvas.layer = 20
	get_tree().get_root().add_child(canvas)
	_spectate_banner = Label.new()
	_spectate_banner.rect_position = Vector2(16, 16)
	_spectate_banner.add_font_override("font", load("res://assets/font/Lato/Lato-Bold.ttf"))
	_spectate_banner.add_color_override("font_color", Color(1, 0.85, 0.2))
	canvas.add_child(_spectate_banner)
	_update_spectate_banner_name()

func _update_spectate_banner_name():
	if _spectate_banner == null:
		return
	var lobby_manager = _get_lobby_manager()
	var name_text = "Player"
	if lobby_manager != null:
		for p in lobby_manager.players:
			if int(p.get("peer_id", -1)) == target_peer_id:
				name_text = String(p.get("name", "Player"))
	_spectate_banner.text = "👁 SPECTATING: %s" % name_text

func exit_spectate_mode():
	spectating = false
	target_peer_id = -1
	if ghost_cursor != null:
		ghost_cursor.queue_free()
		ghost_cursor = null
	if _spectate_banner != null:
		_spectate_banner.get_parent().queue_free()
		_spectate_banner = null

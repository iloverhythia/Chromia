extends Reference

# Banned from chat (the server says so: LobbyManager.chat_banned): the chat
# boxes go grey with "You're banned from chat" (and how long is left, for a
# ban with an end), and their Send buttons too.
# Used by the Spectate window's global chat and the lobby chat.

const GREY := Color(0.55, 0.55, 0.58, 1.0)

static func apply(input: LineEdit, send: Button, banned: bool):
	if input != null and is_instance_valid(input):
		if not input.has_meta("chat_placeholder"):
			input.set_meta("chat_placeholder", input.placeholder_text)
		input.editable = not banned
		input.placeholder_text = _banned_text() if banned else String(input.get_meta("chat_placeholder"))
		input.modulate = GREY if banned else Color(1, 1, 1, 1)
		if banned:
			input.text = ""
			if input.has_focus():
				input.release_focus()
	if send != null and is_instance_valid(send):
		send.disabled = banned
		send.modulate = GREY if banned else Color(1, 1, 1, 1)
		send.mouse_default_cursor_shape = Control.CURSOR_ARROW if banned else Control.CURSOR_POINTING_HAND

# "You're banned from chat (2h 13m left)"
static func _banned_text() -> String:
	var lm = Engine.get_main_loop().root.get_node_or_null("LobbyManager")
	var left: String = String(lm.chat_ban_left_text()) if lm != null and lm.has_method("chat_ban_left_text") else ""
	return ("You're banned from chat (%s left)" % left) if left != "" else "You're banned from chat"

static func banned() -> bool:
	var lm = Engine.get_main_loop().root.get_node_or_null("LobbyManager")
	return lm != null and bool(lm.get("chat_banned"))

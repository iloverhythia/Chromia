extends Node

# Chat commands for the global chat (Spectate page) and lobby chat:
#   /share (your selected map), /share <map name>,
#   /share map | settings | colorset | mesh | cursor | hitsound
#   /profile <name or #number>   /report <name or #number>   /help
# A share uploads the file to the Content Browser and sends a link in the
# chat ([[share:kind:id:song id:name]]); anyone can click it to get it.

const CB := "res://scripts/ui/menu/ContentBrowser.gd"
const KINDS := {"map": "map", "maps": "map", "song": "map", "settings": "profile", "setting": "profile", "profile": "profile",
		"colorset": "colorset", "colors": "colorset", "colours": "colorset", "mesh": "mesh", "cursor": "cursor",
		"hitsound": "hitsound", "sound": "hitsound", "skin": "skin", "look": "skin"}
const NOUN := {"map": "Map", "profile": "Settings", "colorset": "Colorset", "mesh": "Note mesh", "cursor": "Cursor", "hitsound": "Hit sound", "skin": "Skin"}
const META := "chromia_share:"
const LINK := Color(0.55, 0.85, 1.0)
const HELP := "/share: shares your selected map (/share <name> shares a map by its name)\n/share map | settings | colorset | skin | mesh | cursor | hitsound: shares it as a link\n/profile <name or #number>: their stats\n/report <name or #number>: report a player"

var _send_target: Object
var _send_method := ""
var _kind := ""
var _song_id := ""
var _name := ""

# Runs a command typed in a chat box. Returns true when the text was a command
# (it isn't sent as a message then). send_method(text) sends a message to that
# chat; stats_host has _show_stats(number, name) when it's the Spectate page.
static func handle(host: Node, text: String, send_target: Object, send_method: String) -> bool:
	text = text.strip_edges()
	if not text.begins_with("/") or text.begins_with("//"):
		return false
	var parts := text.substr(1).split(" ", false, 1)
	if parts.empty():
		return false
	var cmd := String(parts[0]).to_lower()
	var arg := String(parts[1]).strip_edges() if parts.size() > 1 else ""
	match cmd:
		"share":
			# /share alone: your selected map; /share <name>: the map called that
			var k: String = KINDS.get(arg.to_lower(), "") if arg != "" else "map"
			if k == "":
				var found = _map_named(arg)
				if found == null:
					_tell("No map called '%s' in your list. /share alone shares your selected map; /share settings, colorset, skin, mesh, cursor or hitsound share those." % arg)
					return true
				Rhythia.selected_song = found
				k = "map"
			var d: Dictionary = load(CB).prepare_share(k)
			if d.has("error"):
				_tell(String(d.error))
				return true
			var up = load("res://scripts/ui/ChatCommands.gd").new()
			up._send_target = send_target
			up._send_method = send_method
			up._kind = k
			up._song_id = String(d.get("song_id", ""))
			up._name = String(d.name)
			host.add_child(up)
			up._upload(String(d.path))
		"profile", "stats":
			var p := _find_player(arg)
			if p.empty():
				return true
			_open_stats(host, int(p.number), String(p.name))
		"report":
			var p := _find_player(arg)
			if p.empty():
				return true
			if int(p.number) == _my_number():
				_tell("That's you.")
				return true
			var w = load("res://scripts/game/SpectateReport.gd").open_for(host, int(p.number), String(p.name), {}, "")
			if w is CanvasLayer:
				w.layer = 99 # (above the Spectate window)
		"help", "commands", "?":
			_tell(HELP)
		_:
			_tell("Unknown command /%s. Commands:\n%s" % [cmd, HELP])
	return true

# a map in your list by its name (exact first, then the first that contains it)
static func _map_named(arg: String):
	var low := arg.to_lower()
	var part = null
	for s in Rhythia.registry_song.get_items():
		if s == null or s.is_broken:
			continue
		var nm := String(s.name).to_lower()
		if nm == low:
			return s
		if part == null and nm.find(low) != -1:
			part = s
	return part

static func _tell(text: String):
	Globals.notify(Globals.NOTIFY_INFO, text, "Chat")

static func _my_number() -> int:
	var lm = Engine.get_main_loop().root.get_node_or_null("LobbyManager")
	return int(lm.my_player_number) if lm != null else -1

# a player by name (or the start of one) or #number, from who is online
static func _find_player(arg: String) -> Dictionary:
	arg = arg.strip_edges()
	if arg.begins_with("@"):
		arg = arg.substr(1)
	if arg == "":
		_tell("Whose? Type their name or #number after the command.")
		return {}
	var lm = Engine.get_main_loop().root.get_node_or_null("LobbyManager")
	var online: Array = lm.online_players if lm != null and lm.online_players is Array else []
	var num := -1
	if arg.begins_with("#") and arg.substr(1).is_valid_integer():
		num = int(arg.substr(1))
	elif arg.is_valid_integer():
		num = int(arg)
	if num > 0:
		for p in online:
			if p is Dictionary and int(p.get("number", -1)) == num:
				return {"number": num, "name": Globals.s(p.get("name", "Player #%d" % num))}
		return {"number": num, "name": "Player #%d" % num}
	var low := arg.to_lower()
	var starts := []
	for p in online:
		if not (p is Dictionary):
			continue
		var nm := Globals.s(p.get("name", ""))
		if nm.to_lower() == low:
			return {"number": int(p.get("number", -1)), "name": nm}
		if nm.to_lower().begins_with(low):
			starts.append({"number": int(p.get("number", -1)), "name": nm})
	if starts.size() == 1:
		return starts[0]
	if starts.size() > 1:
		_tell("More than one player starts with '%s'. Type more of the name, or their #number." % arg)
	else:
		_tell("Nobody online is called '%s'. Try their #number." % arg)
	return {}

# their stats card: the Spectate page has it
static func _open_stats(host: Node, number: int, nm: String):
	if number <= 0:
		_tell("That player has no player number.")
		return
	var page = host if host.has_method("_show_stats") else null
	if page == null:
		var sb = Rhythia.menu_node("Sidebar")
		if sb != null and sb.get("spectate") != null:
			page = sb.spectate
			if page.has_method("open") and not page.is_open():
				page.open()
	if page != null and page.has_method("_show_stats"):
		page._show_stats(number, nm)
	else:
		OS.shell_open("https://savia.nysr.host/profile?id=%d" % number)

# ------------------------------------------------------------------ sharing

func _upload(path: String):
	var f := File.new()
	if f.open(path, File.READ) != OK:
		_tell("Couldn't open that file.")
		queue_free()
		return
	var data := f.get_buffer(f.get_len())
	f.close()
	var r := HTTPRequest.new()
	r.timeout = 300
	r.use_threads = OS.can_use_threads()
	add_child(r)
	r.connect("request_completed", self, "_on_uploaded")
	var cid := String(Rhythia.cid) if Rhythia.get("cid") != null else ""
	var url := "%s/upload/%s?client_id=%s&name=%s" % [load(CB).API, _kind, cid.http_escape(), _name.http_escape()]
	if r.request_raw(url, ["Content-Type: application/octet-stream"], true, HTTPClient.METHOD_POST, data) != OK:
		_tell("Couldn't reach the server.")
		queue_free()
	elif data.size() > 1024 * 1024:
		_tell("Uploading %s to share it..." % NOUN.get(_kind, "it").to_lower())

func _on_uploaded(result: int, code: int, _h, body: PoolByteArray):
	queue_free()
	var p = JSON.parse(body.get_string_from_utf8()) if result == HTTPRequest.RESULT_SUCCESS else null
	if p == null or p.error != OK or not (p.result is Dictionary):
		_tell("Couldn't share it (HTTP %d). Try again in a moment." % code)
		return
	var d: Dictionary = p.result
	var item = d.get("item")
	if not bool(d.get("ok", false)) or not (item is Dictionary) or Globals.s(item.get("id", "")) == "":
		_tell("Couldn't share it: %s." % Globals.s(d.get("error", "unknown error")))
		return
	var nm := _name.replace("]]", "").replace("\n", " ").strip_edges()
	var token := "[[share:%s:%s:%s:%s]]" % [_kind, Globals.s(item.id), _song_id.replace(":", "_").left(80), nm.left(60)]
	if is_instance_valid(_send_target) and _send_target.has_method(_send_method):
		_send_target.call(_send_method, token)

# ------------------------------------------------------------------ links in chat

# a share link's parts, or {} when the token isn't one
static func parse(token: String) -> Dictionary:
	if not (token.begins_with("[[share:") and token.ends_with("]]")):
		return {}
	var parts := token.substr(8, token.length() - 10).split(":", true, 3)
	if parts.size() < 4:
		return {}
	var k := String(parts[0])
	if not NOUN.has(k):
		return {}
	var id := String(parts[1])
	if id == "" or id.length() > 64:
		return {}
	for ch in id:
		if not (ch == "-" or ch == "_" or (ch >= "0" and ch <= "9") or (ch.to_lower() >= "a" and ch.to_lower() <= "z")):
			return {}
	return {"kind": k, "id": id, "song_id": String(parts[2]), "name": String(parts[3])}

# Adds chat text to a label: share links as clickable links, emoji as pictures.
static func add_text(rtl: RichTextLabel, text: String, size_px: int = 18):
	var emoji = load("res://scripts/ui/Emoji.gd")
	var from := 0
	while true:
		var a := text.find("[[share:", from)
		if a == -1:
			break
		var b := text.find("]]", a)
		if b == -1:
			break
		var d := parse(text.substr(a, b + 2 - a))
		if d.empty():
			emoji.add_text(rtl, text.substr(from, b + 2 - from), size_px)
			from = b + 2
			continue
		if a > from:
			emoji.add_text(rtl, text.substr(from, a - from), size_px)
		_hook(rtl)
		rtl.push_meta(META + to_json(d))
		rtl.push_color(LINK)
		rtl.push_underline()
		# a map: just its name in blue (click it to download and play it)
		if d.kind == "map":
			rtl.add_text(d.name if d.name != "" else "a map")
		else:
			rtl.add_text("[%s: %s - click to get]" % [NOUN[d.kind], d.name if d.name != "" else "(no name)"])
		rtl.pop()
		rtl.pop()
		rtl.pop()
		from = b + 2
	if from < text.length():
		emoji.add_text(rtl, text.substr(from), size_px)

# the text with share links as words (notices, plain labels)
static func plain(text: String) -> String:
	var from := 0
	while true:
		var a := text.find("[[share:", from)
		if a == -1:
			break
		var b := text.find("]]", a)
		if b == -1:
			break
		var d := parse(text.substr(a, b + 2 - a))
		if d.empty():
			from = b + 2
			continue
		var w := String(d.name) if d.kind == "map" else "[%s: %s]" % [NOUN[d.kind], d.name]
		text = text.substr(0, a) + w + text.substr(b + 2)
		from = a + w.length()
	return text

static func _hook(rtl: RichTextLabel):
	if rtl.has_meta("_share_links"):
		return
	rtl.set_meta("_share_links", true)
	rtl.meta_underlined = false # (links underline themselves; reactions don't)
	var h = load("res://scripts/ui/ChatCommands.gd").new()
	h.name = "ShareLinks"
	rtl.add_child(h)
	rtl.connect("meta_clicked", h, "_on_meta")
	rtl.connect("meta_hover_started", h, "_on_hover", [rtl, true])
	rtl.connect("meta_hover_ended", h, "_on_hover", [rtl, false])

func _on_hover(meta, rtl: RichTextLabel, on: bool):
	if String(meta).begins_with(META):
		rtl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if on else Control.CURSOR_ARROW

var _busy := {}
func _on_meta(meta):
	var m := String(meta)
	if not m.begins_with(META):
		return
	var j = JSON.parse(m.substr(META.length()))
	if j.error != OK or not (j.result is Dictionary):
		return
	var d: Dictionary = j.result
	var k := String(d.get("kind", ""))
	var id := String(d.get("id", ""))
	if not NOUN.has(k) or id == "" or _busy.has(id):
		return
	# a map you have already: just picked
	if k == "map" and String(d.get("song_id", "")) != "" and Rhythia.registry_song != null:
		var s = Rhythia.registry_song.get_song_loose(String(d.song_id))
		if s and not s.is_online:
			_open_map(s)
			Globals.notify(Globals.NOTIFY_SUCCEED, "'%s' is ready to play (you have it already)." % String(s.name), "Map")
			return
	_busy[id] = true
	var r := HTTPRequest.new()
	r.timeout = 180
	r.use_threads = OS.can_use_threads()
	add_child(r)
	r.connect("request_completed", self, "_on_got", [r, d])
	if r.request("%s/file/%s" % [load(CB).API, id.http_escape()]) != OK:
		r.queue_free()
		_busy.erase(id)
	else:
		Globals.notify(Globals.NOTIFY_INFO, "Downloading %s..." % String(d.get("name", "")), "Chat")

func _on_got(result: int, code: int, _h, body: PoolByteArray, r: HTTPRequest, d: Dictionary):
	r.queue_free()
	_busy.erase(String(d.id))
	var k := String(d.kind)
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or body.empty():
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't download it (it may have been deleted).", "Chat")
		return
	var cb = load(CB)
	Directory.new().make_dir_recursive(Globals.p(cb.DOWNLOAD_DIR))
	var ext: String = cb.EXT.get(k, "bin")
	if k == "hitsound":
		var head := body.subarray(0, min(3, body.size() - 1)).get_string_from_ascii()
		ext = "ogg" if head.begins_with("Ogg") else ("wav" if head.begins_with("RIF") else "mp3")
	var path: String = Globals.p(cb.DOWNLOAD_DIR).plus_file("%s.%s" % [cb._safe_name(String(d.get("name", ""))), ext])
	var f := File.new()
	if f.open(path, File.WRITE) != OK:
		Globals.notify(Globals.NOTIFY_WARN, "Couldn't save the download.", "Chat")
		return
	f.store_buffer(body)
	f.close()
	var got = cb.install(get_tree(), k, path, String(d.get("name", "")))
	if k == "map":
		if got != null and got is Object:
			_open_map(got)
		else:
			Globals.notify(Globals.NOTIFY_WARN, "The map downloaded but couldn't be added to your list.", "Map")

# a shared map: picked and shown on its screen in the menu, ready to play
# (watching someone or in a map: just picked; it's there in the menu after)
func _open_map(song):
	Rhythia.select_song(song)
	var sb = Rhythia.menu_node("Sidebar")
	if sb == null or Rhythia.in_map:
		return
	if sb.get("spectate") != null and sb.spectate.has_method("is_open") and sb.spectate.is_open():
		sb.spectate.close()
	sb.press(0, true)
	var list = Rhythia.menu_node("Main/Maps/MapRegistry/S/VBoxContainer")
	if list != null and list.has_method("scroll_to_song"):
		list.scroll_to_song(String(song.id))
	var res = Rhythia.menu_node("Main/Maps/Results")
	if res != null:
		res.visible = true

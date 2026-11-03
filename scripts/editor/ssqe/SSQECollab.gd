extends Node
# Mapping together in the map editor: Chromia's port of SSQE+'s collab
# (Web Editor/js/collab.js), over the Chromia server's connection and Chromia
# accounts instead of SSQE+'s Supabase project (savia_web server/src/collab.js
# relays the messages between the people in a room).
#
# COLLABORATE on the editor's start screen lists who's online; an invite pops
# up for the other person (unless they turned invites off in the editor's
# Settings > Other). When they accept, the one who invited (the host) opens
# the map to work on: its song goes to everyone in pieces, every editor opens
# the same map, and from then on it's live: notes added, moved and deleted,
# timing points, bookmarks and the extra objects. Each person has a colour:
# you see where the others are in the song (a line on the track and the
# timeline), their mouse over the grid, and the notes they placed in their
# colour. The host can invite more people (up to 5) from the bar at the bottom.
#
# Notes are kept in step as changes: each side sends what's been added and
# removed since what all last agreed on, so people editing at once don't
# overwrite each other, and nobody's selection is touched by what the others
# do. The host sends a fingerprint of the notes every few seconds; if
# someone's doesn't match twice running, the host sends them the whole map.

const SSQEMap = preload("res://scripts/editor/ssqe/SSQEMap.gd")
const F = preload("res://scripts/editor/ssqe/SSQEFormats.gd")
const SSQESettings = preload("res://scripts/editor/ssqe/SSQESettings.gd")

const MAX_PEOPLE := 5
const CHUNK := 48 * 1024 # song bytes a piece (base64 about 64 KB: well inside a message)
const TICK := 0.033
const PART := 4000 # notes a snapshot part
const COLORS := [Color8(255, 160, 0), Color8(0, 200, 255), Color8(130, 255, 90), Color8(255, 90, 200), Color8(255, 230, 60)]
const TEXT := Color(0.898039, 0.94902, 1, 1)
const DIM := Color(0.62, 0.6, 0.68, 1)
const ACCENT := Color(1, 0.756863, 0.960784)

var page # EditorPage
var lm # LobbyManager
var s = null # the session (null: not mapping with anyone)
var invites := {} # number -> {state: "sent" / "declined", at}
var _acc := 0.0
var _host_room := ""
var _moving := false # (being moved to or from the root for a playtest: not a leave)

# UI
var layer: CanvasLayer
var overlay: Control
var bar: PanelContainer
var bar_label: Label
var invite_btn: Button
var waiting: ColorRect
var waiting_label: Label
var popup: PanelContainer
var popup_label: Label
var _popup_invite = null # {room, from, name, at}
var list_panel: PanelContainer
var list_box: VBoxContainer
var f_reg: DynamicFont
var f_bold: DynamicFont
var f_title: DynamicFont
var _shown := {} # number -> Vector2 (their mouse, eased)

func _ready():
	pause_mode = PAUSE_MODE_PROCESS
	lm = get_node_or_null("/root/LobbyManager")
	if lm and lm.has_signal("collab_event"):
		lm.connect("collab_event", self, "_on_event")
	_build_ui()

# the editor went away (another scene, the game closing) while mapping
# together: out of the room, or the server would keep you in it and nobody
# could invite you again (a playtest isn't this: keep_for_playtest)
func _exit_tree():
	if _moving or s == null:
		return
	_send_server({"type": "collab_leave"})
	s = null

# ================================================================== a playtest

# EditorPage.playtest: the game's scene is about to replace the editor's. The
# session stays (here, under the root) and keeps taking in the others' changes
# to the map; back in the editor, the map that opens is brought up to date.
func keep_for_playtest():
	if s == null:
		return
	s.away = true
	s.back_at = 0
	page = null
	popup.visible = false
	list_panel.visible = false
	move_to(get_tree().root, "KeptCollab")
	_refresh_ui()
	overlay.update()

# EditorPage._ready, back from the playtest
func adopt(new_page):
	page = new_page
	move_to(new_page, "Collab")
	if s:
		s.back_at = OS.get_ticks_msec()
	_refresh_ui()

func move_to(parent: Node, new_name: String):
	_moving = true
	if get_parent():
		get_parent().remove_child(self)
	name = new_name
	parent.add_child(self)
	_moving = false

func _come_back(ed):
	var old = s.map
	s.away = false
	if old != null and ed.map != old:
		# the map as it was saved for the playtest, plus what the others did meanwhile
		var map = ed.map
		map.notes.items = old.notes.items.duplicate()
		map.notes.sort()
		map.notes.set_selected([])
		s.map = map
		s.extra = ""
		_apply_extra(extra_of(old))
		ed.on_map_changed()
		_index_all()
		s.version = -1
	if s.role == "guest":
		send({"k": "resync"}, s.host)
	_toast("Back to mapping together")
	_refresh_ui()

# ================================================================== helpers

func me() -> int:
	return int(lm.my_player_number) if lm else -1

func active() -> bool:
	return s != null

func _ed():
	return page.ed if page else null

func _toast(text: String, kind := "info"):
	var ed = _ed()
	if ed and ed.is_visible_in_tree() and ed.has_method("toast"):
		ed.toast(text.to_upper(), kind)
	else:
		Globals.notify(Globals.NOTIFY_WARN if kind == "warn" else Globals.NOTIFY_INFO, text, "Map Together")

func _message(text: String):
	Globals.notify(Globals.NOTIFY_INFO, text, "Map Together")

func _send_server(payload: Dictionary):
	if lm:
		lm.collab_send(payload)

# to everyone in the room (or one person)
func send(d: Dictionary, to := -1):
	var m := {"type": "collab_send", "d": d}
	if to > 0:
		m["to"] = to
	_send_server(m)

static func _r3(v: float) -> String:
	return "%.3f" % (round(v * 1000.0) / 1000.0)

static func key_of(n) -> String:
	var v := Vector3(n.x, n.y, n.ms)
	var e: int = (1 + n.style * 64 + n.direction) if n.enable_easing else 0
	if n._ck_v == v and n._ck_e == e and n._ck != "":
		return n._ck
	var k := "%s|%s|%d" % [_r3(n.x), _r3(n.y), int(round(n.ms))]
	if n.enable_easing:
		k += "|%d|%d" % [n.style, n.direction]
	n._ck = k
	n._ck_h = k.hash()
	n._ck_v = v
	n._ck_e = e
	return k

static func note_of(k: String):
	var p := k.split("|")
	if p.size() < 3:
		return null
	var easing := p.size() >= 5
	return SSQEMap.note(float(p[0]), float(p[1]), int(p[2]), easing, int(p[3]) if easing else 0, int(p[4]) if easing else 0)

static func count_keys(items: Array) -> Dictionary:
	var m := {}
	for n in items:
		var k := key_of(n)
		m[k] = int(m.get(k, 0)) + 1
	return m

# a fingerprint of the notes, the same whatever order they're in
static func hash_notes(items: Array) -> int:
	var h := items.size()
	for n in items:
		key_of(n)
		h = (h + n._ck_h) & 0x7fffffff
	return h

static func extra_of(map) -> String:
	var t := []
	for p in map.timing_points:
		t.append([p.bpm, p.ms])
	var b := []
	for x in map.bookmarks:
		b.append([x.text, x.ms, x.end_ms])
	var v := []
	for o in map.vfx_objects.items:
		v.append("%d|%s" % [o.id, o.to_text()])
	var sp := []
	for o in map.special_objects.items:
		sp.append("%d|%s" % [o.id, o.to_text()])
	return to_json({"t": t, "b": b, "v": v, "s": sp, "o": int(map.props.get("exportOffset", 0))})

# ================================================================== invites

func can_collab() -> bool:
	if lm == null or not lm.collab_supported:
		_message("Mapping together needs the updated Chromia server (connect to the internet and try again in a moment).")
		return false
	if me() <= 0:
		_message("Go online first (the game connects by itself; give it a moment).")
		return false
	return true

func people() -> int:
	return 1 + (s.peers.size() if s else 0)

func _waiting_invites() -> int:
	var n := 0
	for k in invites:
		if invites[k].state == "sent" and OS.get_ticks_msec() - int(invites[k].at) < INVITE_SHOWN_MS:
			n += 1
	return n

func full() -> bool:
	return people() + _waiting_invites() >= MAX_PEOPLE

func invite(number: int, name: String):
	if not can_collab():
		return
	if s and s.role != "host":
		_message("Only %s, who started this, can invite people." % s.host_name)
		return
	if full():
		_message("%d people is the most that can map together." % MAX_PEOPLE)
		return
	invites[number] = {"state": "sent", "at": OS.get_ticks_msec(), "name": name}
	_send_server({"type": "collab_invite", "number": number})
	_fill_list()

const INVITE_SHOWN_MS := 35000 # (the invite pops up for 30 seconds, then counts as a no)

func invite_state(number: int) -> String:
	if not invites.has(number):
		return ""
	if invites[number].state == "sent" and OS.get_ticks_msec() - int(invites[number].at) > INVITE_SHOWN_MS:
		return ""
	return String(invites[number].state)

# an invite nobody answered (their game didn't show it, or is too old to):
# Invite again, instead of "Invited" for good
func _expire_invites():
	var changed := false
	for k in invites.keys():
		if invites[k].state == "sent" and OS.get_ticks_msec() - int(invites[k].at) > INVITE_SHOWN_MS:
			invites.erase(k)
			changed = true
	if changed:
		_fill_list()

func _on_event(msg: Dictionary):
	# (the server says who you are: a game that hasn't had the online list doesn't know)
	if lm and int(msg.get("you", -1)) > 0 and int(lm.my_player_number) <= 0:
		lm.my_player_number = int(msg.get("you", -1))
	var t := Globals.s(msg.get("type", ""))
	match t:
		"collab_invited":
			_on_invited(msg)
		"collab_reply":
			_on_reply(msg)
		"collab_room":
			_host_room = Globals.s(msg.get("room", ""))
			if s:
				_on_room(msg)
		"collab_msg":
			if s and msg.get("d") is Dictionary:
				var d: Dictionary = msg.d
				d["f"] = int(msg.get("from", -1))
				d["nm"] = Globals.s(msg.get("name", "Someone"))
				_receive(d)
		"collab_left":
			if s:
				var who := int(msg.get("from", -1))
				if s.peers.has(who):
					_toast("%s left" % Globals.s(msg.get("name", "Someone")), "warn")
				_drop_peer(who)
		"collab_ended":
			if s:
				leave(true)
				_toast("%s ended mapping together. The map stays with you." % Globals.s(msg.get("name", "The host")), "warn")
		"collab_error":
			_message(Globals.s(msg.get("text", "Something went wrong.")))
			# (said yes to an invite that had run out: not waiting for that host)
			if s and s.role == "guest" and s.phase == "wait" and s.peers.empty():
				leave(true)

func _on_invited(msg: Dictionary):
	var room := Globals.s(msg.get("room", ""))
	var from := int(msg.get("from", -1))
	var name := Globals.s(msg.get("name", "Someone"))
	var st: Dictionary = page.ed.s if page and page.ed else SSQESettings.load_settings()
	var allow := bool(st.get("allowCollabInvites", true))
	if not allow or s != null or Rhythia.in_map:
		# (busy: mapping with someone already; the server leaves that to the game)
		_send_server({"type": "collab_reply", "room": room, "accept": false, "busy": s != null})
		return
	_popup_invite = {"room": room, "from": from, "name": name, "at": OS.get_ticks_msec()}
	popup_label.text = "%s wants to map with you in the map editor." % name
	popup.visible = true

func _answer(accept: bool):
	popup.visible = false
	var inv = _popup_invite
	_popup_invite = null
	if inv == null:
		return
	accept = accept and s == null
	_send_server({"type": "collab_reply", "room": inv.room, "accept": accept})
	if accept:
		_start("guest", inv.room, inv.from, inv.name)

func _on_reply(msg: Dictionary):
	var from := int(msg.get("from", -1))
	var name := Globals.s(msg.get("name", "Someone"))
	if bool(msg.get("accept", false)):
		invites.erase(from)
		if s == null:
			_start("host", _host_room, me(), String(lm.player_name))
			_message("%s accepted! Now open the map to work on together (CREATE NEW MAP, LOAD MAP, or one of your maps). Its song and notes go to everyone." % name)
		else:
			_toast("%s accepted - joining" % name)
	else:
		if invites.has(from):
			invites[from].state = "declined"
		_toast(("%s is already mapping with someone" if bool(msg.get("busy", false)) else "%s said no") % name, "warn")
	_fill_list()

# ================================================================== a session

func _start(role: String, room: String, host_number: int, host_name: String):
	s = {
		"role": role, "room": room, "host": host_number, "host_name": host_name,
		"phase": "song" if role == "host" else "wait",
		"peers": {}, "order": [], # number -> peer; colours by order in the room (host first)
		"song": null, "song_bytes": PoolByteArray(), "song_meta": null, "early": {}, "outbox": [],
		"map": null, "synced": {}, "version": -1, "extra": "", "last_p": "", "last_sel": "",
		"last_send": 0, "last_sum": 0, "last_local": 0, "last_extra": 0, "last_full": 0, "misses": 0,
		"got_snap": role == "host", "snap": null, "last_chunk": 0, "asked_meta": 0,
		"known": {}, "cur": {}, "by_key": {}, "hsum": 0, "items_hash": 0, "scan_i": 0, "dirty": {}, "last_d": 0,
	}
	page.call("_ensure_built")
	var sb = Rhythia.menu_node("Sidebar")
	if sb and sb.has_method("press_page"):
		sb.press_page(page)
	# the host's map is the one open now, or the next one they open; a guest's
	# own map is put away (saved) for the one that's coming
	if role == "guest":
		if page.project != null and page.has_method("close_project"):
			page.close_project()
		send({"k": "hi"})
	_refresh_ui()

func _color_of(number: int) -> Color:
	var i: int = s.order.find(number) if s else -1
	return COLORS[i % COLORS.size()] if i >= 0 else COLORS[(int(abs(number)) + 1) % COLORS.size()]

func _peer(number: int, name: String) -> Dictionary:
	if not s.peers.has(number):
		s.peers[number] = {"number": number, "name": name, "other": null, "heard": OS.get_ticks_msec(), "sel": []}
		_refresh_ui()
	var p: Dictionary = s.peers[number]
	if name != "":
		p.name = name
	p.heard = OS.get_ticks_msec()
	return p

func _on_room(msg: Dictionary):
	var order := []
	var names := {}
	for m in msg.get("members", []):
		if m is Dictionary:
			order.append(int(m.get("number", -1)))
			names[int(m.get("number", -1))] = Globals.s(m.get("name", ""))
	s.order = order
	for n in order:
		if n != me():
			_peer(n, names[n])
	for n in s.peers.keys():
		if not (n in order):
			_drop_peer(n)
	_recolor()
	_refresh_ui()

func _recolor():
	if s == null or s.map == null:
		return
	for n in s.map.notes.items:
		if n.has_meta("by"):
			var by := int(n.get_meta("by"))
			n.by_color = _color_of(by) if by != me() else null

func _drop_peer(number: int):
	if s and s.peers.has(number):
		s.peers.erase(number)
		_shown.erase(number)
		_refresh_ui()

func leave(quiet := false):
	if s == null:
		return
	if not quiet:
		_send_server({"type": "collab_leave"})
	if s.map:
		for n in s.map.notes.items:
			n.by_color = null
	s = null
	invites.clear()
	_shown.clear()
	_refresh_ui()
	# (the overlay only redraws while mapping together: cleared now, or the
	# others' last lines and names stayed on the screen)
	overlay.update()

func _confirm_leave():
	if s == null:
		return
	var host: bool = s.role == "host"
	var ed = _ed()
	var text: String = "End mapping together for everyone? The map stays with all of you." if host else "Leave mapping together? The map stays with you."
	if ed and ed.dialogs:
		ed.dialogs.confirm(text, self, "_leave_answer")
	else:
		leave()

func _leave_answer(answer: String):
	if answer == "yes":
		leave()

# ------------------------------------------------------------------ the song

# the host has opened the map to work on: its song goes to everyone
func _bind_map():
	var ed = _ed()
	if ed == null or ed.map == null or page.project == null:
		return
	var path: String = page.project.audio_path()
	var f := File.new()
	if path == "" or f.open(path, File.READ) != OK:
		_toast("This map has no song stored - open one that has its song", "warn")
		return
	s.song_bytes = f.get_buffer(f.get_len())
	f.close()
	s.map = ed.map
	_attach()
	s.song_meta = {"k": "song", "name": path.get_file(), "size": s.song_bytes.size(),
		"n": int(ceil(float(s.song_bytes.size()) / CHUNK)), "title": String(page.project.title)}
	s.phase = "mapping"
	_send_song(-1)
	_refresh_ui()

func _send_song(to: int):
	if s == null or s.song_meta == null:
		return
	var meta: Dictionary = s.song_meta.duplicate()
	send(meta, to)
	for i in range(int(meta.n)):
		s.outbox.append([i, to])

func _send_chunk(i: int, to: int):
	var b: PoolByteArray = s.song_bytes.subarray(i * CHUNK, min((i + 1) * CHUNK, s.song_bytes.size()) - 1)
	send({"k": "chunk", "i": i, "d": Marshalls.raw_to_base64(b)}, to)

func _song_arrived():
	var g: Dictionary = s.song
	s.phase = "opening"
	var bytes := PoolByteArray()
	for part in g.parts:
		bytes.append_array(Marshalls.base64_to_raw(String(part)))
	var m = SSQEMap.new()
	var title := String(g.get("title", ""))
	if title == "":
		title = "Map with %s" % s.host_name
	var res = page._create_from(m, title, bytes, PoolByteArray(), true)
	if res == null or s == null:
		leave()
		return
	s.map = _ed().map
	_attach()
	s.phase = "mapping"
	send({"k": "ready"}, s.host)
	_refresh_ui()

# ------------------------------------------------------------------ applying the others' changes

func _attach():
	s.synced = count_keys(s.map.notes.items)
	_index_all()
	s.version = s.map.version
	s.extra = extra_of(s.map)

# ------------------------------------------------------------------ keeping track of the notes
# What the notes are, kept up to date as they change, instead of being worked
# out again from every note many times a second (on a big map that was most
# of the lag). s.known: note -> its key; s.cur: key -> how many; s.by_key:
# key -> the notes; s.hsum: their keys' hashes added up (the fingerprint);
# s.dirty: the keys whose count changed since the last change went out.
const SCAN := 100 # notes looked at again each tick, in case one changed some other way

func _index_all():
	var known := {}
	var cur := {}
	var by_key := {}
	var hs := 0
	for n in s.map.notes.items:
		var k := key_of(n)
		known[n] = k
		cur[k] = int(cur.get(k, 0)) + 1
		if by_key.has(k):
			by_key[k].append(n)
		else:
			by_key[k] = [n]
		hs = (hs + int(n._ck_h)) & 0x7fffffff
	s.known = known
	s.cur = cur
	s.by_key = by_key
	s.hsum = hs
	s.items_hash = s.map.notes.items.hash()
	s.scan_i = 0
	var dirty := {}
	for k in cur:
		dirty[k] = true
	for k in s.synced:
		dirty[k] = true
	s.dirty = dirty

func _track_add(n):
	var k := key_of(n)
	s.known[n] = k
	s.cur[k] = int(s.cur.get(k, 0)) + 1
	if s.by_key.has(k):
		s.by_key[k].append(n)
	else:
		s.by_key[k] = [n]
	s.hsum = (int(s.hsum) + int(n._ck_h)) & 0x7fffffff
	s.dirty[k] = true

func _track_remove(n):
	var k: String = s.known[n]
	s.known.erase(n)
	var c := int(s.cur.get(k, 0)) - 1
	if c > 0:
		s.cur[k] = c
	else:
		s.cur.erase(k)
	if s.by_key.has(k):
		var l: Array = s.by_key[k]
		l.erase(n)
		if l.empty():
			s.by_key.erase(k)
	s.hsum = (int(s.hsum) - int(k.hash())) & 0x7fffffff
	s.dirty[k] = true

# a note that may have been moved where it is (dragging moves them in place)
func _retrack(n):
	if s.known.has(n) and key_of(n) != s.known[n]:
		_track_remove(n)
		_track_add(n)

# this side's notes: what was added, removed or moved since the last look
func _check_local():
	var notes = s.map.notes
	var items: Array = notes.items
	var now := OS.get_ticks_msec()
	var h := items.hash() # (native: cheap; the same while nothing's added, removed or reordered)
	if h != int(s.items_hash):
		s.items_hash = h
		# quick: an edit's new notes are selected, and the ones it took away were
		# selected before it (placing, deleting, moving, pasting, undo)
		for n in notes.selected:
			if not s.known.has(n):
				_track_add(n)
		for n in s.get("prev_sel", []):
			if s.known.has(n) and items.find(n) == -1:
				_track_remove(n)
		if items.size() != s.known.size():
			_full_check(items)
		else:
			s.unverified = true # (looked at properly soon, in case it was something else)
	if s.get("unverified", false) and now - int(s.get("last_verify", 0)) > 1500:
		_full_check(items)
	for n in notes.selected:
		_retrack(n)
	s.prev_sel = notes.selected.duplicate()
	var cnt := items.size()
	for _i in range(min(SCAN, cnt)):
		if int(s.scan_i) >= cnt:
			s.scan_i = 0
		_retrack(items[int(s.scan_i)])
		s.scan_i = int(s.scan_i) + 1

# every note: which are new here and which have gone
func _full_check(items: Array):
	s.unverified = false
	s.last_verify = OS.get_ticks_msec()
	var added := false
	for n in items:
		if not s.known.has(n):
			_track_add(n)
			added = true
	if items.size() != s.known.size():
		var here := {}
		for n in items:
			here[n] = true
		for n in s.known.keys():
			if not here.has(n):
				_track_remove(n)

func _notes_hash() -> int:
	return (s.known.size() + int(s.hsum)) & 0x7fffffff

# of `free`, the note closest to n (taken out of free), or null
static func _closest(free: Array, n):
	var bi := -1
	var bd := INF
	for i in range(free.size()):
		var m = free[i]
		var d: float = abs(m.ms - n.ms) / 100.0 + Vector2(m.x - n.x, m.y - n.y).length()
		if d < bd:
			bd = d
			bi = i
	if bi < 0:
		return null
	var o = free[bi]
	free.remove(bi)
	return o

func _after_remote_change():
	var ed = _ed()
	if ed:
		ed.on_map_changed()
	s.version = s.map.version

func _apply_snapshot(parts: Array):
	var map = s.map
	var first: Dictionary = parts[0]
	var sel := {}
	for n in map.notes.selected:
		sel[key_of(n)] = true
	# what was done here and not sent yet: kept, on top of it
	var cur := count_keys(map.notes.items)
	var mine_add := []
	var mine_del := []
	for k in cur:
		for _q in range(int(s.synced.get(k, 0)), int(cur[k])):
			mine_add.append(k)
	for k in s.synced:
		for _q in range(int(cur.get(k, 0)), int(s.synced[k])):
			mine_del.append(k)
	# the notes already here that are in it stay the same notes (undo, selection)
	var pool := {}
	for n in map.notes.items:
		var k := key_of(n)
		if not pool.has(k):
			pool[k] = []
		pool[k].append(n)
	var authors: Array = first.get("authors", [])
	var items := []
	for part in parts:
		var keys: Array = String(part.get("notes", "")).split(",", false)
		var bi := String(part.get("bi", ""))
		for i in range(keys.size()):
			var k: String = keys[i]
			var n = pool[k].pop_front() if pool.has(k) and not pool[k].empty() else note_of(k)
			if n == null:
				continue
			var c: String = bi.substr(i, 1) if i < bi.length() else "."
			if c != "." and c != "":
				var ai := ord(c) - 48
				if ai >= 0 and ai < authors.size():
					var by := int(authors[ai])
					n.set_meta("by", by)
					n.by_color = _color_of(by) if by != me() else null
			items.append(n)
	var agreed := count_keys(items)
	for k in mine_del:
		for j in range(items.size()):
			if key_of(items[j]) == k:
				items.remove(j)
				break
	for k in mine_add:
		var n2 = pool[k].pop_front() if pool.has(k) and not pool[k].empty() else note_of(k)
		if n2:
			items.append(n2)
	map.notes.items = items
	map.notes.sort()
	var keep := []
	for n in map.notes.items:
		if sel.has(key_of(n)):
			keep.append(n)
	map.notes.set_selected(keep)
	_apply_extra(String(first.get("extra", "")))
	s.synced = agreed
	_index_all() # (and what was done here goes out next tick, on top of it)
	s.got_snap = true
	_after_remote_change()
	# (this side's own changes go out next tick, on top of it)
	s.version = -1

func _apply_diff(adds: Array, removes: Array, peer: Dictionary):
	var map = s.map
	var items: Array = map.notes.items
	for n in map.notes.selected:
		_retrack(n) # (where this side's own notes are now, before taking theirs)
	var gone := {}
	for k in removes:
		if s.by_key.has(k):
			for n in s.by_key[k]:
				if not gone.has(n):
					gone[n] = true
					break
	var col := _color_of(int(peer.number))
	var added := []
	for k in adds:
		var n = note_of(String(k))
		if n:
			n.set_meta("by", int(peer.number))
			n.by_color = col
			added.append(n)
	var was_sel: Array = map.notes.selected
	var lost := []
	if not gone.empty():
		if gone.size() > 32:
			var keep := []
			for n in items:
				if not gone.has(n):
					keep.append(n)
			map.notes.items = keep
		else:
			for n in gone:
				items.erase(n) # (native: quicker than going through every note here)
		for n in was_sel:
			if gone.has(n):
				lost.append(n)
		for n in gone:
			_track_remove(n)
	map.notes.insert_sorted(added) # (where they go, in order: no sorting the whole map)
	for n in added:
		_track_add(n)
	# notes someone else moved that were selected here: still selected, where they went
	var sel := []
	for n in was_sel:
		if not gone.has(n):
			sel.append(n)
	if not lost.empty() and added.size() >= lost.size():
		var free := added.duplicate()
		for n in lost:
			var to = _closest(free, n)
			if to != null:
				sel.append(to)
	map.notes.set_selected(sel)
	# (stored bezier nodes are this side's own: the notes as you stored them,
	# whatever the others do to the map: SSQEMap.ObjList.bezier_nodes)
	# what all agree on now, so these don't go straight back
	for k in removes:
		var c := int(s.synced.get(k, 0))
		if c > 1:
			s.synced[k] = c - 1
		else:
			s.synced.erase(k)
	for k in adds:
		s.synced[k] = int(s.synced.get(k, 0)) + 1
	s.items_hash = map.notes.items.hash()
	_after_remote_change()

func _apply_extra(x: String):
	if x == "" or x == s.extra:
		return
	var p := JSON.parse(x)
	if p.error != OK or not (p.result is Dictionary):
		return
	var j: Dictionary = p.result
	var map = s.map
	var point = [map.selected_point.bpm, map.selected_point.ms] if map.selected_point else null
	var tps := []
	for t in j.get("t", []):
		if t is Array and t.size() >= 2:
			tps.append(SSQEMap.timing_point(float(t[0]), int(float(t[1]))))
	map.timing_points = tps
	var bms := []
	for b in j.get("b", []):
		if b is Array and b.size() >= 3:
			bms.append(SSQEMap.bookmark(Globals.s(b[0]), int(float(b[1])), int(float(b[2]))))
	map.bookmarks = bms
	for pair in [["v", map.vfx_objects], ["s", map.special_objects]]:
		var list = pair[1]
		var was_sel := {}
		for o in list.selected:
			was_sel["%d|%s" % [o.id, o.to_text()]] = true
		list.items = []
		for str_o in j.get(pair[0], []):
			var objs: Array = F.read_objects(SSQEMap.ss(str_o))
			var o = SSQEMap.parse_object(-1, objs[0]) if not objs.empty() else null
			if o:
				list.add(o)
		list.sort()
		var keep := []
		for o in list.items:
			if was_sel.has("%d|%s" % [o.id, o.to_text()]):
				keep.append(o)
		list.set_selected(keep)
	# (taken as it is: reading it the usual way moves every note by the change,
	# and the notes have come already moved)
	map.props.exportOffset = int(j.get("o", 0))
	map.sort_timings()
	map.sort_bookmarks()
	map.selected_point = null
	if point:
		for t in map.timing_points:
			if t.bpm == point[0] and t.ms == point[1]:
				map.selected_point = t
	s.extra = extra_of(map)
	_after_remote_change()

# ------------------------------------------------------------------ the whole map, from the host

func _send_snapshot(to: int):
	var items: Array = s.map.notes.items
	var parts: int = int(max(1, ceil(float(items.size()) / PART)))
	var snap := str(OS.get_ticks_msec()) + str(randi() % 100000)
	# who placed each note: a list of people, and each note's placer's place in it
	var authors := [me()]
	var at := {me(): 0}
	for n in items:
		if n.has_meta("by") and not at.has(int(n.get_meta("by"))) and authors.size() < 70:
			at[int(n.get_meta("by"))] = authors.size()
			authors.append(int(n.get_meta("by")))
	for q in range(parts):
		var keys := PoolStringArray()
		var bi := ""
		for i in range(q * PART, min((q + 1) * PART, items.size())):
			var n = items[i]
			keys.append(key_of(n))
			var by: int = int(n.get_meta("by")) if n.has_meta("by") else me()
			bi += char(48 + int(at.get(by, 0)))
		var d := {"k": "snap", "snap": snap, "part": q, "parts": parts, "notes": keys.join(","), "bi": bi}
		if q == 0:
			d["extra"] = extra_of(s.map)
			d["authors"] = authors
		send(d, to)

# ================================================================== receiving

func _receive(p: Dictionary):
	if s == null:
		return
	var from := int(p.get("f", -1))
	if from == me() or from <= 0:
		return
	var peer := _peer(from, String(p.get("nm", "")))
	match String(p.get("k", "")):
		"hi":
			if s.role == "host" and s.song_meta != null:
				_send_song(from)
		"song":
			if s.role != "guest" or s.song != null:
				return
			var n := int(p.get("n", 0))
			s.song = {"n": n, "parts": [], "got": 0, "title": String(p.get("title", "")), "name": String(p.get("name", ""))}
			s.song.parts.resize(n)
			s.phase = "receiving"
			s.last_chunk = OS.get_ticks_msec()
			for i in s.early:
				if int(i) < n and s.song.parts[int(i)] == null:
					s.song.parts[int(i)] = s.early[i]
					s.song.got += 1
			s.early = {}
			if s.song.got == n:
				_song_arrived()
		"chunk":
			if s.role != "guest" or s.phase == "mapping" or s.phase == "opening":
				return
			var i := int(p.get("i", -1))
			if s.song == null:
				s.early[i] = String(p.get("d", ""))
				if OS.get_ticks_msec() - int(s.asked_meta) > 2000:
					s.asked_meta = OS.get_ticks_msec()
					send({"k": "hi"}, s.host)
				return
			if i < 0 or i >= s.song.n or s.song.parts[i] != null:
				return
			s.song.parts[i] = String(p.get("d", ""))
			s.song.got += 1
			s.last_chunk = OS.get_ticks_msec()
			_refresh_ui()
			if s.song.got == s.song.n:
				_song_arrived()
		"need":
			if s.role == "host":
				for i in p.get("i", []):
					s.outbox.append([int(i), from])
		"ready":
			if s.role == "host" and s.map:
				_send_snapshot(from)
				_toast("%s joined" % peer.name)
		"snap":
			if s.map == null:
				return
			if s.snap == null or s.snap.id != String(p.get("snap", "")):
				s.snap = {"id": String(p.get("snap", "")), "parts": [], "got": 0}
				s.snap.parts.resize(int(p.get("parts", 1)))
			var q := int(p.get("part", 0))
			if q >= 0 and q < s.snap.parts.size() and s.snap.parts[q] == null:
				s.snap.parts[q] = p
				s.snap.got += 1
			if s.snap.got == s.snap.parts.size():
				var ps: Array = s.snap.parts
				s.snap = null
				_apply_snapshot(ps)
		"d":
			if s.map:
				_apply_diff(p.get("a", []), p.get("r", []), peer)
		"x":
			if s.map:
				_apply_extra(String(p.get("x", "")))
		"p":
			peer.other = p
			peer.other["at"] = OS.get_ticks_msec()
		"sum":
			if s.role == "guest" and s.map and s.phase == "mapping" and s.got_snap:
				if int(p.get("h", 0)) != _notes_hash() and OS.get_ticks_msec() - int(s.last_local) > 1500:
					s.misses += 1
					if s.misses >= 2:
						send({"k": "resync"}, s.host)
						s.misses = 0
				else:
					s.misses = 0
		"resync":
			if s.role == "host" and s.map:
				_send_snapshot(from)

# ================================================================== sending this side's changes

func _process(delta):
	if not invites.empty():
		_expire_invites()
	if s == null:
		if popup.visible and _popup_invite != null and OS.get_ticks_msec() - int(_popup_invite.at) > 30000:
			_answer(false) # (not answered: a no)
		return
	_acc += delta
	if _acc < TICK:
		return
	_acc = 0.0
	_tick()
	if s != null:
		_refresh_ui()
	overlay.update()

func _tick():
	var ed = _ed()
	var now := OS.get_ticks_msec()
	# the song going out, a few pieces a tick
	for _i in range(3):
		if s.outbox.empty():
			break
		var o: Array = s.outbox.pop_front()
		_send_chunk(int(o[0]), int(o[1]))
	# playtesting: the others' changes still come in (to s.map); back in the
	# editor, once the map has opened again, carry on with it
	if s.get("away", false):
		if page != null and page.project != null and ed and ed.map:
			_come_back(ed)
		elif page != null and int(s.back_at) > 0 and now - int(s.back_at) > 15000:
			leave()
			_toast("Mapping together ended: the map didn't open again after the playtest", "warn")
		return
	# the host has opened a map: that's the one
	if s.role == "host" and s.phase == "song" and page.project != null and ed and ed.map:
		_bind_map()
		return
	# back to the start screen, or another map opened: done
	if s.map and (page.project == null or ed == null or ed.map != s.map):
		leave()
		return
	# a guest waiting for a song that's stopped coming: ask again for what's missing
	if s.role == "guest" and s.song and s.phase == "receiving" and now - int(s.last_chunk) > 3000:
		var missing := []
		for i in range(s.song.n):
			if s.song.parts[i] == null:
				missing.append(i)
				if missing.size() >= 40:
					break
		send({"k": "need", "i": missing}, s.host)
		s.last_chunk = now
	if s.map == null or s.phase != "mapping":
		return
	var map = s.map
	if s.role == "guest" and not s.got_snap:
		return
	# the notes: what's been added and removed since all last agreed
	_check_local()
	if not s.dirty.empty() and now - int(s.get("last_d", 0)) >= 50:
		s.last_d = now
		var a := []
		var r := []
		for k in s.dirty:
			var c := int(s.cur.get(k, 0))
			var y := int(s.synced.get(k, 0))
			for _q in range(y, c):
				a.append(k)
			for _q in range(c, y):
				r.append(k)
			if c > 0:
				s.synced[k] = c
			else:
				s.synced.erase(k)
		s.dirty = {}
		if not a.empty() or not r.empty():
			send({"k": "d", "a": a, "r": r})
			s.last_local = now
			var mine := {}
			for k in a:
				mine[k] = true
			for k in mine:
				for n in s.by_key.get(k, []):
					if not n.has_meta("by"):
						n.set_meta("by", me())
	# timing points, bookmarks and extra objects (looked at after an edit here)
	if map.version != s.version or now - int(s.last_full) > 2000:
		s.version = map.version
		s.last_full = now
		var x := extra_of(map)
		if x != s.extra:
			s.extra = x
			send({"k": "x", "x": x})
			s.last_local = now
	# where this side is: the song position, playing, the mouse over the grid
	var p := {"k": "p", "t": int(map.current_time), "pl": 1 if ed.playing else 0}
	var g: Rect2 = ed.grid.get_global_rect() if ed.grid else Rect2()
	var mp: Vector2 = ed.get_global_mouse_position()
	if g.size.x > 0:
		var gx: float = (mp.x - g.position.x) / g.size.x
		var gy: float = (mp.y - g.position.y) / g.size.y
		if gx > -0.25 and gx < 1.25 and gy > -0.25 and gy < 1.25:
			p["gx"] = stepify(gx, 0.001)
			p["gy"] = stepify(gy, 0.001)
	p["b"] = 1 if Input.is_mouse_button_pressed(BUTTON_LEFT) else 0
	var sig := "%s,%s,%s,%s,%s" % [p.t, p.pl, p.get("gx", ""), p.get("gy", ""), p.b]
	if (sig != s.last_p and now - int(s.last_send) >= 33) or now - int(s.last_send) > 2000:
		send(p)
		s.last_p = sig
		s.last_send = now
	# the host: a fingerprint every 3 seconds, so a lost change gets put right
	if s.role == "host" and now - int(s.last_sum) > 3000:
		s.last_sum = now
		send({"k": "sum", "h": _notes_hash()})
	# someone not heard from for 3 minutes has gone
	for n in s.peers.keys():
		if now - int(s.peers[n].heard) > 180000:
			_drop_peer(n)

func peer_time(p: Dictionary) -> float:
	var o = p.other
	if o == null:
		return -1.0
	var t := float(o.get("t", 0))
	if int(o.get("pl", 0)) == 1:
		var ed = _ed()
		t += (OS.get_ticks_msec() - int(o.at)) * (ed.tempo() if ed and ed.has_method("tempo") else 1.0)
	return t

# ================================================================== the UI

func _font(path: String, size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load(path)
	f.size = size
	f.use_filter = true
	f.add_fallback(load("res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf"))
	return f

func _flat(bg: Color, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

func _btn(text: String, method: String, args := []) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_font_override("font", f_bold)
	b.add_stylebox_override("normal", _flat(Color(0.1, 0.095, 0.125, 1), Color(1, 1, 1, 0.12), 1))
	b.add_stylebox_override("hover", _flat(Color(0.16, 0.15, 0.2, 1), Color(1, 1, 1, 0.2), 1))
	b.add_stylebox_override("pressed", _flat(Color(0.2, 0.17, 0.25, 1), ACCENT, 1))
	b.add_stylebox_override("disabled", _flat(Color(0.07, 0.065, 0.09, 1)))
	b.add_color_override("font_color", TEXT)
	b.add_color_override("font_color_disabled", DIM)
	b.connect("pressed", self, method, args)
	return b

func _label(text: String, f: Font, col := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_font_override("font", f)
	l.add_color_override("font_color", col)
	return l

func _build_ui():
	f_reg = _font("res://assets/font/Lato/Lato-Regular.ttf", 15)
	f_bold = _font("res://assets/font/Lato/Lato-Bold.ttf", 15)
	f_title = _font("res://assets/font/Lato/Lato-Black.ttf", 22)
	layer = CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	overlay = Control.new()
	overlay.anchor_right = 1
	overlay.anchor_bottom = 1
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.connect("draw", self, "_draw_overlay")
	layer.add_child(overlay)

	# a guest, before the map opens
	waiting = ColorRect.new()
	waiting.color = Color(0.03, 0.025, 0.05, 0.85)
	waiting.anchor_right = 1
	waiting.anchor_bottom = 1
	waiting.visible = false
	layer.add_child(waiting)
	var wc := CenterContainer.new()
	wc.anchor_right = 1
	wc.anchor_bottom = 1
	waiting.add_child(wc)
	var wv := VBoxContainer.new()
	wv.add_constant_override("separation", 14)
	wc.add_child(wv)
	waiting_label = _label("", f_title)
	waiting_label.align = Label.ALIGN_CENTER
	wv.add_child(waiting_label)
	var wl := _btn("Leave", "leave")
	wv.add_child(wl)

	# the bar in the editor: who with, INVITE (the host) and LEAVE
	bar = PanelContainer.new()
	bar.add_stylebox_override("panel", _flat(Color(0, 0, 0, 0.75), Color(1, 0.63, 0, 0.6), 2))
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1
	bar.anchor_bottom = 1
	bar.visible = false
	layer.add_child(bar)
	var bh := HBoxContainer.new()
	bh.add_constant_override("separation", 10)
	bar.add_child(bh)
	bar_label = _label("", f_bold)
	bar_label.rect_min_size = Vector2(360, 0)
	bar_label.clip_text = true
	bar_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bh.add_child(bar_label)
	invite_btn = _btn("INVITE", "open_list")
	bh.add_child(invite_btn)
	bh.add_child(_btn("LEAVE", "_confirm_leave"))

	# an invite for you
	popup = PanelContainer.new()
	popup.add_stylebox_override("panel", _flat(Color(0.08, 0.075, 0.11, 0.97), ACCENT, 1))
	# (top centre: the notifications stack up in the top right corner)
	popup.anchor_left = 0.5
	popup.anchor_right = 0.5
	popup.margin_left = -210
	popup.margin_right = 210
	popup.margin_top = 16
	popup.visible = false
	layer.add_child(popup)
	var pv := VBoxContainer.new()
	pv.add_constant_override("separation", 10)
	popup.add_child(pv)
	pv.add_child(_label("Map together?", f_title, ACCENT))
	popup_label = _label("", f_reg)
	popup_label.autowrap = true
	popup_label.rect_min_size = Vector2(380, 0)
	pv.add_child(popup_label)
	var ph := HBoxContainer.new()
	ph.alignment = BoxContainer.ALIGN_END
	ph.add_constant_override("separation", 8)
	pv.add_child(ph)
	ph.add_child(_btn("Decline", "_answer", [false]))
	ph.add_child(_btn("Accept", "_answer", [true]))

	# who's online, to invite
	list_panel = PanelContainer.new()
	list_panel.add_stylebox_override("panel", _flat(Color(0.07, 0.065, 0.1, 0.98), Color(1, 1, 1, 0.15), 1))
	list_panel.anchor_left = 0.5
	list_panel.anchor_right = 0.5
	list_panel.anchor_top = 0.5
	list_panel.anchor_bottom = 0.5
	list_panel.margin_left = -280
	list_panel.margin_right = 280
	list_panel.margin_top = -260
	list_panel.margin_bottom = 260
	list_panel.visible = false
	layer.add_child(list_panel)
	var lv := VBoxContainer.new()
	lv.add_constant_override("separation", 10)
	list_panel.add_child(lv)
	var lh := HBoxContainer.new()
	lv.add_child(lh)
	var lt := _label("Map together", f_title)
	lt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(lt)
	lh.add_child(_btn("Close", "close_list"))
	lv.add_child(_label("Invite someone who's online. Up to %d people can map together." % MAX_PEOPLE, f_reg, DIM))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.scroll_horizontal_enabled = false
	lv.add_child(sc)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_constant_override("separation", 6)
	sc.add_child(list_box)
	if lm and lm.has_signal("online_players_received"):
		lm.connect("online_players_received", self, "_on_online")

func open_list():
	if not can_collab():
		return
	if lm.has_method("subscribe_online"):
		lm.subscribe_online()
	list_panel.visible = true
	_fill_list()

func close_list():
	list_panel.visible = false

func _on_online(_list, _you):
	if list_panel.visible:
		_fill_list()

func _fill_list():
	if list_box == null or not list_panel.visible:
		return
	for c in list_box.get_children():
		c.queue_free()
	var shown := 0
	for p in (lm.online_players if lm else []):
		if not (p is Dictionary):
			continue
		var n := int(p.get("number", -1))
		if n <= 0 or n == me() or (s and s.peers.has(n)):
			continue
		var row := HBoxContainer.new()
		row.add_constant_override("separation", 8)
		var name := Globals.s(p.get("name", "Player #%d" % n))
		var l := _label("%s  #%d" % [name, n], f_bold)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.clip_text = true
		row.add_child(l)
		var st := invite_state(n)
		var b := _btn("Invited" if st == "sent" else ("Said no" if st == "declined" else "Invite"), "invite", [n, name])
		b.disabled = st == "sent" or full()
		row.add_child(b)
		list_box.add_child(row)
		shown += 1
	if shown == 0:
		list_box.add_child(_label("Nobody else is online right now.", f_reg, DIM))

func _refresh_ui():
	var on: bool = s != null
	var ed = _ed()
	var editor_shown: bool = page != null and page.is_visible_in_tree() and ed != null and ed.visible
	bar.visible = on and editor_shown and s.phase == "mapping"
	waiting.visible = on and s.role == "guest" and s.phase != "mapping" and page != null and page.is_visible_in_tree()
	if on:
		var names := []
		for n in s.peers:
			names.append(s.peers[n].name)
		bar_label.text = ("MAPPING WITH " + PoolStringArray(names).join(", ").to_upper()) if not names.empty() else ("WAITING FOR THEM TO JOIN" if s.role == "host" else "CONNECTING...")
		invite_btn.visible = s.role == "host"
		match s.phase:
			"wait":
				waiting_label.text = "Mapping with %s.\n\nWaiting for %s to choose the map..." % [s.host_name, s.host_name]
			"receiving", "opening":
				var pct: int = int(100.0 * s.song.got / max(1, s.song.n)) if s.song else 0
				waiting_label.text = "Mapping with %s.\n\nGetting the song... %d%%" % [s.host_name, pct]
		if bar.margin_left != -330: # (once: setting them again every tick laid the bar out again)
			bar.margin_left = -330
			bar.margin_right = 330
			bar.margin_top = -118
			bar.margin_bottom = -70

# the others: a line on the track and the timeline where they are, and their mouse over the grid
func _draw_overlay():
	if s == null or s.map == null or s.phase != "mapping":
		return
	var ed = _ed()
	if ed == null or not ed.is_visible_in_tree() or ed.map != s.map:
		return
	var now := OS.get_ticks_msec()
	var tr: Rect2 = ed.track.get_global_rect()
	var th: float = tr.size.y / 2.0
	var cursor_x: float = tr.position.x + tr.size.x * float(ed.s.cursorPos) / 100.0
	var ms_to_px: float = ed.ms_to_px()
	var cur: float = ed.current_time()
	var total: float = max(ed.total_time(), 1.0)
	var g: Rect2 = ed.grid.get_global_rect() if ed.grid else Rect2()
	var px_to_ms: float = ed.px_to_ms()
	var view_from: float = cur - (cursor_x - tr.position.x) * px_to_ms
	var view_to: float = cur + (tr.end.x - cursor_x) * px_to_ms
	var row := 0
	for n in s.peers:
		var p: Dictionary = s.peers[n]
		if p.other == null:
			continue
		var col := _color_of(n)
		var t := peer_time(p)
		var label := "%s  %s" % [p.name, _time_text(t)]
		# on the track: a line where they are, or (in another part of the song)
		# an arrow at the edge pointing their way, with where they are
		var x: float = cursor_x + (t - cur) * ms_to_px
		var ay: float = tr.position.y + 14 + row * 18
		if x >= tr.position.x and x <= tr.end.x:
			overlay.draw_line(Vector2(x, tr.position.y), Vector2(x, tr.position.y + th), col, 2.0)
			overlay.draw_string(f_bold, Vector2(x + 4, tr.position.y + th - 6), p.name, col)
		elif x < tr.position.x:
			var ax: float = tr.position.x + 4
			overlay.draw_colored_polygon(PoolVector2Array([Vector2(ax, ay), Vector2(ax + 9, ay - 6), Vector2(ax + 9, ay + 6)]), col)
			overlay.draw_string(f_bold, Vector2(ax + 13, ay + 5), label, col)
		else:
			var ax2: float = tr.end.x - 4
			var w: float = f_bold.get_string_size(label).x
			overlay.draw_colored_polygon(PoolVector2Array([Vector2(ax2, ay), Vector2(ax2 - 9, ay - 6), Vector2(ax2 - 9, ay + 6)]), col)
			overlay.draw_string(f_bold, Vector2(ax2 - 13 - w, ay + 5), label, col)
		# on the timeline: a marker on the song's bar, with their name
		if ed.timeline and ed.timeline.has_method("line_rect"):
			var lr: Rect2 = ed.timeline.line_rect()
			var lp: Vector2 = ed.timeline.get_global_transform().xform(lr.position)
			var tx: float = lp.x + lr.size.x * clamp(t / total, 0.0, 1.0)
			var ty: float = lp.y + lr.size.y / 2.0
			overlay.draw_line(Vector2(tx, ty - 9), Vector2(tx, ty + 9), col, 3.0)
			overlay.draw_colored_polygon(PoolVector2Array([Vector2(tx, ty - 9), Vector2(tx - 6, ty - 17), Vector2(tx + 6, ty - 17)]), col)
			overlay.draw_string(f_bold, Vector2(tx - f_bold.get_string_size(p.name).x / 2.0, ty - 21 - row * 16), p.name, col)
		row += 1
		# their mouse, while they're in the part of the song on this screen
		var o: Dictionary = p.other
		if o.has("gx") and g.size.x > 0 and now - int(o.at) < 10000 and t >= view_from and t <= view_to:
			var target := g.position + Vector2(float(o.gx) * g.size.x, float(o.gy) * g.size.y)
			var at: Vector2 = _shown[n].linear_interpolate(target, 0.5) if _shown.has(n) else target
			_shown[n] = at
			_draw_cursor(at, col, p.name, int(o.get("b", 0)) != 0)
		else:
			_shown.erase(n)

static func _time_text(ms: float) -> String:
	var sec := int(max(ms, 0.0) / 1000.0)
	return "%d:%02d" % [sec / 60, sec % 60]

func _draw_cursor(at: Vector2, col: Color, name: String, down: bool):
	var k := 1.0
	var c := 22.0 * k
	if down:
		overlay.draw_circle(at, 14 * k, Color(col.r, col.g, col.b, 0.4))
	var pts := PoolVector2Array([at, at + Vector2(0, c), at + Vector2(c * 0.28, c * 0.75), at + Vector2(c * 0.48, c * 1.15),
		at + Vector2(c * 0.62, c * 1.08), at + Vector2(c * 0.43, c * 0.7), at + Vector2(c * 0.75, c * 0.7)])
	overlay.draw_colored_polygon(pts, col)
	var outline := pts
	outline.append(at)
	overlay.draw_polyline(outline, Color(0, 0, 0), 1.5, true)
	overlay.draw_string(f_bold, at + Vector2(c * 0.8, c * 1.2), name, col)

extends ReferenceRect

# Full-page Profile tab (left sidebar). Left: your profile from the Savia site
# (avatar, rank, stats, top play and top 10 plays). Right: the existing
# profile/leaderboard panel, moved here by menu2.gd (see get_slot()).

const SITE = "https://savia.nysr.host"
const API = SITE + "/savia-public/api"

var _theme: Theme = preload("res://uitheme.tres")

var avatar_rect: TextureRect
var name_label: Label
var tag_label: Label
var rank_label: Label
var stats_label: Label
var status_label: Label
var top_play_box: VBoxContainer
var plays_box: VBoxContainer
var slot: Control
var _loading: bool = false
var _loaded_once: bool = false

func get_slot() -> Control:
	return slot

func _big_font(size: int) -> DynamicFont:
	var f := DynamicFont.new()
	f.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	f.size = size
	return f

func _label(text: String, size: int = 0, color: Color = Color(0.9, 0.95, 1)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme = _theme
	l.autowrap = true
	if size > 0:
		l.add_font_override("font", _big_font(size))
	l.add_color_override("font_color", color)
	return l

func _panel_style(alpha: float = 0.55) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.04, 0.07, alpha)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	return sb

func _ready():
	var root := HBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.margin_left = 70
	root.margin_right = -24
	root.margin_top = 24
	root.margin_bottom = -60
	root.add_constant_override("separation", 20)
	add_child(root)

	# --- Left: profile card ---
	var card := PanelContainer.new()
	card.add_stylebox_override("panel", _panel_style())
	card.size_flags_horizontal = SIZE_EXPAND_FILL
	card.size_flags_stretch_ratio = 1.3
	root.add_child(card)

	var scroll := ScrollContainer.new()
	scroll.scroll_horizontal_enabled = false
	card.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_constant_override("separation", 10)
	scroll.add_child(v)

	var head := HBoxContainer.new()
	head.add_constant_override("separation", 18)
	v.add_child(head)

	avatar_rect = TextureRect.new()
	avatar_rect.rect_min_size = Vector2(128, 128)
	avatar_rect.expand = true
	avatar_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	head.add_child(avatar_rect)

	var names := VBoxContainer.new()
	names.size_flags_horizontal = SIZE_EXPAND_FILL
	names.alignment = BoxContainer.ALIGN_CENTER
	head.add_child(names)
	name_label = _label("Your Profile", 34)
	names.add_child(name_label)
	tag_label = _label("", 16)
	tag_label.visible = false
	names.add_child(tag_label)
	rank_label = _label("", 20, Color(1, 0.75, 0.85))
	names.add_child(rank_label)

	var refresh := Button.new()
	refresh.text = "Refresh"
	refresh.theme = _theme
	refresh.rect_min_size = Vector2(90, 32)
	refresh.size_flags_vertical = SIZE_SHRINK_CENTER
	refresh.connect("pressed", self, "load_profile")
	head.add_child(refresh)

	# signs out of Discord (unlinks it from this game); shown while signed in
	signout_button = Button.new()
	signout_button.text = "Sign out"
	signout_button.theme = _theme
	signout_button.rect_min_size = Vector2(90, 32)
	signout_button.size_flags_vertical = SIZE_SHRINK_CENTER
	signout_button.connect("pressed", self, "_on_sign_out")
	head.add_child(signout_button)
	if not Rhythia.is_connected("discord_login_changed", self, "_on_discord_changed"):
		Rhythia.connect("discord_login_changed", self, "_on_discord_changed")
	_on_discord_changed()

	status_label = _label("", 0, Color(0.8, 0.8, 0.85))
	v.add_child(status_label)
	stats_label = _label("", 18)
	v.add_child(stats_label)

	v.add_child(HSeparator.new())
	v.add_child(_label("Top Play", 22, Color(1, 0.6, 0.75)))
	top_play_box = VBoxContainer.new()
	v.add_child(top_play_box)

	v.add_child(HSeparator.new())
	v.add_child(_label("Top 10 Plays", 22))
	plays_box = VBoxContainer.new()
	plays_box.add_constant_override("separation", 4)
	v.add_child(plays_box)

	# --- Right: slot for the existing profile/leaderboard panel ---
	slot = Control.new()
	slot.size_flags_horizontal = SIZE_EXPAND_FILL
	slot.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(slot)

	connect("visibility_changed", self, "_on_visibility_changed")
	_report_last_crash()

# --- Crash breadcrumbs --------------------------------------------------------
# Each step of loading the profile is written to a file before it runs and
# cleared when loading finishes. If the game closes in between, the next launch
# says which step it was, so a crash can be reported exactly.
const CRUMB_FILE := "user://caches/profile_step.txt"

func _crumb(step: String):
	var d := Directory.new()
	if not d.dir_exists(Globals.p(CRUMB_FILE.get_base_dir())):
		d.make_dir_recursive(Globals.p(CRUMB_FILE.get_base_dir()))
	var f := File.new()
	if f.open(Globals.p(CRUMB_FILE), File.WRITE) == OK:
		f.store_string(step)
		f.close()

func _crumbs_done():
	var d := Directory.new()
	d.remove(Globals.p(CRUMB_FILE))

func _report_last_crash():
	var f := File.new()
	if not f.file_exists(Globals.p(CRUMB_FILE)) or f.open(Globals.p(CRUMB_FILE), File.READ) != OK:
		return
	var step := f.get_as_text().strip_edges()
	f.close()
	_crumbs_done()
	if step != "":
		Globals.call_deferred("notify", Globals.NOTIFY_WARN,
			"Chromia closed last time while the profile page was %s. Please send this message to the developer." % step,
			"Profile page crashed")

func _on_visibility_changed():
	if is_visible_in_tree() and not _loaded_once:
		_loaded_once = true
		# the page's first frames are drawn before anything is downloaded,
		# so a crash report can tell drawing and downloading apart
		_crumb("being drawn for the first time")
		for _i in range(3):
			yield(get_tree(), "idle_frame")
		_crumbs_done()
		load_profile()

# --- Networking -------------------------------------------------------------

func _http_get(url: String):
	yield(get_tree(), "idle_frame")
	var what := url.get_file().split("?")[0]
	_crumb("connecting to the server (%s)" % what)
	var r := HTTPRequest.new()
	r.timeout = 20
	# like every other download in the game (on iOS a main-thread download
	# from this page closed the game)
	r.use_threads = OS.can_use_threads()
	add_child(r)
	if r.request(url) != OK:
		r.queue_free()
		return null
	var res = yield(r, "request_completed")
	_crumb("reading the server's reply (%s, result %d, HTTP %d, %d bytes)" % [what, res[0], res[1], res[3].size()])
	r.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		return null
	return res[3]

func _get_json(url: String):
	var body = yield(_http_get(url), "completed")
	if body == null:
		return null
	_crumb("reading the downloaded data (%d bytes)" % body.size())
	var p := JSON.parse(body.get_string_from_utf8())
	return p.result if p.error == OK else null

func _matches_me(e: Dictionary, discord_id: String, names: Array) -> bool:
	if discord_id != "" and Globals.s(e.get("avatar_url", "")).find(discord_id) != -1:
		return true
	var n := Globals.s(e.get("name", "")).strip_edges().to_lower()
	return n != "" and names.has(n)

func load_profile():
	if _loading:
		return
	_loading = true
	status_label.text = "Loading your profile…"
	var discord_id := String(Rhythia.discord_user.get("id", ""))
	var names := []
	for n in [Rhythia.website_name, Rhythia.discord_user.get("username", ""), Rhythia.discord_user.get("display_name", "")]:
		if String(n) != "": names.append(String(n).strip_edges().to_lower())
	var lm = get_node_or_null("/root/LobbyManager")
	if lm != null and String(lm.player_name) != "" and String(lm.player_name) != "Player":
		names.append(String(lm.player_name).strip_edges().to_lower())

	var number = null
	for kind in ["sp", "xp"]:
		_crumb("loading the %s leaderboard" % kind)
		var lb = yield(_get_json(API + "/leaderboard/%s?limit=5000" % kind), "completed")
		_crumb("looking for you on the %s leaderboard" % kind)
		if lb is Dictionary:
			for e in lb.get("entries", []):
				if e is Dictionary and _matches_me(e, discord_id, names):
					number = e.get("number")
					break
		if number != null:
			break

	# not found by Discord or name (a name or picture changed on the website):
	# this game's own player number, from the server
	if number == null and lm != null and int(lm.my_player_number) > 0:
		number = int(lm.my_player_number)

	if number == null:
		_loading = false
		name_label.text = String(Rhythia.website_name) if String(Rhythia.website_name) != "" else String(Rhythia.discord_user.get("display_name", Rhythia.discord_user.get("username", "Your Profile")))
		if discord_id == "":
			status_label.text = "Connect Discord on the right (Profile tab) so we can find you on the Chromia leaderboard."
		else:
			status_label.text = "You're not on the Chromia leaderboard yet. Pass a ranked map while online to show up."
		var du_avatar := String(Rhythia.discord_user.get("avatar_url", ""))
		if du_avatar != "":
			_load_avatar(du_avatar)
		else:
			_crumbs_done()
		return

	_crumb("loading your profile")
	var profile = yield(_get_json(API + "/player/%s" % String(number).http_escape()), "completed")
	var av := ""
	if profile is Dictionary:
		_crumb("showing your profile")
		_show_profile(profile)
		av = Globals.s(profile.get("avatar_url", ""))
	_crumb("loading your scores")
	var scores = yield(_get_json(API + "/player/%s/scores" % String(number).http_escape()), "completed")
	if scores is Dictionary:
		_crumb("showing your scores")
		_show_scores(scores.get("scores", []))
	status_label.text = ""
	_loading = false
	if av != "":
		_load_avatar(SITE + av if av.begins_with("/") else av)
	else:
		_crumbs_done()

# Discord's CDN can send animated GIF/WebP avatars at any size; always ask
# for a small still PNG.
static func _small_png_avatar(url: String) -> String:
	if url.find("cdn.discordapp.com") == -1 and url.find("media.discordapp.net") == -1:
		return url
	var base := url.split("?")[0]
	var ext := base.get_extension().to_lower()
	if ext in ["gif", "webp", "jpg", "jpeg", "png"]:
		base = base.get_basename() + ".png"
	return base + "?size=128"

func _load_avatar(url: String):
	url = _small_png_avatar(url)
	_crumb("downloading your avatar (%s)" % url)
	var body = yield(_http_get(url), "completed")
	if body == null:
		_crumbs_done()
		return
	var format: String = Globals.imageLoader.get_format(body)
	# still images only: decoding animations here isn't worth the risk
	if not format in ["png", "jpg"]:
		_crumbs_done()
		return
	_crumb("decoding your avatar (%s, %d bytes)" % [format, body.size()])
	var img: Image = Globals.imageLoader.load_buffer_image(body)
	if img == null or img.is_empty() or img.get_width() > 4096 or img.get_height() > 4096:
		_crumbs_done()
		return
	_crumb("preparing your avatar (%dx%d)" % [img.get_width(), img.get_height()])
	if img.get_width() != 128 or img.get_height() != 128:
		img.resize(128, 128, Image.INTERPOLATE_BILINEAR)
	img.convert(Image.FORMAT_RGBA8)
	_round_mask(img)
	var tex := ImageTexture.new()
	tex.create_from_image(img, Texture.FLAG_FILTER)
	_crumb("drawing your avatar")
	avatar_rect.texture = tex
	yield(get_tree(), "idle_frame")
	yield(get_tree(), "idle_frame")
	_crumbs_done()

# Cuts the avatar into a circle with a soft edge (instead of a custom shader).
static func _round_mask(img: Image):
	var w := img.get_width()
	var h := img.get_height()
	var c := Vector2(w, h) * 0.5
	var r: float = min(w, h) * 0.5
	img.lock()
	for y in range(h):
		for x in range(w):
			var d: float = Vector2(x + 0.5, y + 0.5).distance_to(c) / r
			if d > 0.96:
				var px := img.get_pixel(x, y)
				px.a *= clamp((1.0 - d) / 0.04, 0.0, 1.0)
				img.set_pixel(x, y, px)
	img.unlock()

# --- Display ----------------------------------------------------------------

func _fmt(n) -> String:
	return Globals.comma_sep(int(n))

func _show_profile(p: Dictionary):
	name_label.text = Globals.s(p.get("name", "Player"))
	var tag = p.get("tag")
	if tag is Dictionary and Globals.s(tag.get("text", "")) != "":
		tag_label.text = Globals.s(tag.text)
		tag_label.visible = true
		var c := Globals.s(tag.get("color", ""))
		if c.is_valid_html_color():
			tag_label.add_color_override("font_color", Color(c))
	else:
		tag_label.visible = false
	rank_label.text = "#%s SP   •   #%s XP%s" % [Globals.s(p.get("sp_rank", "-")), Globals.s(p.get("xp_rank", "-")), "   •   ranker" if p.get("is_ranker", false) else ""]
	stats_label.text = "%s SP     %s XP\n%s passes on %s maps%s" % [
		_fmt(p.get("sp", 0)), _fmt(p.get("xp", 0)),
		_fmt(p.get("pass_count", 0)), _fmt(p.get("map_count", 0)),
		_last_online(p)
	]

# "Online now", or when they were last online (the server sends it rounded
# to 5 minutes; nothing for players who had their activity data deleted)
func _last_online(p: Dictionary) -> String:
	if p.get("online", false):
		return "\nOnline now"
	var ls = p.get("last_seen")
	if ls == null or float(ls) <= 0:
		return ""
	var sec = int(OS.get_unix_time() - float(ls) / 1000.0)
	var t = "just now"
	if sec >= 300:
		var n = 0
		var unit = ""
		if sec < 3600:
			n = sec / 60
			unit = "minute"
		elif sec < 86400:
			n = sec / 3600
			unit = "hour"
		elif sec < 30 * 86400:
			n = sec / 86400
			unit = "day"
		elif sec < 365 * 86400:
			n = sec / (30 * 86400)
			unit = "month"
		else:
			n = sec / (365 * 86400)
			unit = "year"
		t = "%d %s%s ago" % [n, unit, "" if n == 1 else "s"]
	return "\nLast online " + t

func _play_line(s: Dictionary) -> String:
	var acc := float(s.get("accuracy", 0)) * 100.0
	return "%s SP  •  %.2f%%  •  %sx  •  %s miss%s" % [
		_fmt(s.get("sp_final", 0)), acc, String(stepify(float(s.get("speed", 1)), 0.01)),
		Globals.s(s.get("misses", 0)), "" if int(s.get("misses", 0)) == 1 else "es"
	]

func _show_scores(scores: Array):
	for c in top_play_box.get_children(): c.queue_free()
	for c in plays_box.get_children(): c.queue_free()
	var sorted := []
	for s in scores:
		if s is Dictionary: sorted.append(s)
	sorted.sort_custom(self, "_by_sp")
	if sorted.empty():
		top_play_box.add_child(_label("No plays yet."))
		return
	var best: Dictionary = sorted[0]
	var card := PanelContainer.new()
	card.add_stylebox_override("panel", _panel_style(0.75))
	var cv := VBoxContainer.new()
	card.add_child(cv)
	cv.add_child(_label(Globals.s(best.get("song_name", best.get("song_id", "?"))), 22))
	cv.add_child(_label(_play_line(best), 18, Color(1, 0.8, 0.9)))
	cv.add_child(_label("%s XP  •  %s notes" % [_fmt(best.get("xp_awarded", 0)), _fmt(best.get("note_count", 0))], 0, Color(0.75, 0.75, 0.8)))
	top_play_box.add_child(card)
	for i in range(min(10, sorted.size())):
		var s: Dictionary = sorted[i]
		var row := HBoxContainer.new()
		row.add_constant_override("separation", 10)
		var rank := _label("#%d" % (i + 1), 0, Color(0.7, 0.7, 0.75))
		rank.rect_min_size = Vector2(36, 0)
		rank.autowrap = false
		row.add_child(rank)
		var nm := _label(Globals.s(s.get("song_name", s.get("song_id", "?"))))
		nm.size_flags_horizontal = SIZE_EXPAND_FILL
		nm.autowrap = false
		nm.clip_text = true
		row.add_child(nm)
		var val := _label(_play_line(s), 0, Color(1, 0.8, 0.9))
		val.autowrap = false
		row.add_child(val)
		plays_box.add_child(row)

func _by_sp(a, b):
	return float(a.get("sp_final", 0)) > float(b.get("sp_final", 0))

var signout_button: Button

func _on_discord_changed():
	if signout_button == null or not is_instance_valid(signout_button):
		return
	var linked: bool = Rhythia.discord_user.has("username") and String(Rhythia.discord_user.username) != ""
	signout_button.visible = linked
	signout_button.disabled = false

func _on_sign_out():
	signout_button.disabled = true
	Rhythia.unlink_discord()
	yield(Rhythia, "discord_login_changed")
	load_profile()

extends Control

# The Chromia Upgrade Tree's minigames (its Games button). Each one unlocks
# when you've bought enough upgrades (and stays unlocked), and pays chrome
# coins worth some seconds of your coin rate, so they're worth playing at any
# point of the tree. Kept in the tree's save (furry_tree.json, "mini").
#
# - Chromia Merge: drag a Chromia logo onto one just like it and they merge
#   into the next logo. It never ends: every level is a new logo (its colour,
#   rings, orbiting dots, spikes and name come from its level). Logos on the
#   board make chrome coins all the time, more the higher they are. Its
#   Upgrades (paid in chrome coins, priced in seconds of your coin rate like
#   the games' prizes): faster and better new logos, a bigger board, more
#   income and merge rewards, auto-merging and lucky merges.
# - Note Rush: hit the notes on the grid before they fade, 30 seconds.
# - Lucky Wheel: a free spin every 10 minutes (coins, or a new feature).
# - Memory Match: find the 8 pairs; the fewer tries, the bigger the prize.

const GAMES = [
	["merge", "Chromia Merge", "Merge two Chromia logos that are the same into the next one, forever. Every logo on the board makes chrome coins.", 10],
	["rush", "Note Rush", "Hit the notes on the grid before they fade. 30 seconds, as many as you can.", 40],
	["wheel", "Lucky Wheel", "A free spin every 10 minutes: chrome coins, or a new feature.", 120],
	["match", "Memory Match", "Turn the cards over and find the 8 pairs. The fewer tries, the bigger the prize.", 300],
]
const LOGO = preload("res://assets/images/branding/icon.png")

var tr # ChromiaUpgradeTree
var _menu: Control
var _game: Control = null
var _title: Label
var _sub: Label

func _ready():
	anchor_right = 1.0
	anchor_bottom = 1.0
	margin_top = 69
	mouse_filter = MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.03, 0.985)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	_title = Label.new()
	_title.add_font_override("font", tr._font(24))
	_title.add_color_override("font_color", Color(1, 0.756863, 0.960784))
	_title.rect_position = Vector2(24, 14)
	add_child(_title)
	_sub = Label.new()
	_sub.add_font_override("font", tr._font(14))
	_sub.add_color_override("font_color", Color(1, 1, 1, 0.55))
	_sub.rect_position = Vector2(25, 46)
	_sub.autowrap = true
	_sub.anchor_right = 1.0
	_sub.margin_right = -140
	add_child(_sub)
	var back := Button.new()
	back.text = "Back"
	back.theme = preload("res://uitheme.tres")
	back.anchor_left = 1.0
	back.anchor_right = 1.0
	back.margin_left = -110
	back.margin_right = -24
	back.margin_top = 14
	back.margin_bottom = 50
	back.connect("pressed", self, "back")
	add_child(back)
	_show_menu()

func state() -> Dictionary:
	if not (tr._mini is Dictionary):
		tr._mini = {}
	return tr._mini

func bought() -> int:
	return int(max(int(tr.stats.get("bought", 0)), int(tr._bought_count)))

func unlocked(i: int) -> bool:
	var st := state()
	var un = st.get("unlocked", [])
	if not (un is Array):
		un = []
	var id: String = GAMES[i][0]
	if un.has(id):
		return true
	if bought() >= int(GAMES[i][3]):
		un.append(id)
		st["unlocked"] = un
		return true
	return false

# chrome coins worth `seconds` of your coin rate (at least 10 coins a second's worth)
func reward(seconds_l: float) -> float:
	var rate_l: float = max(tr._rate_l, 1.0)
	var got_l: float = rate_l + seconds_l
	tr._earn(got_l)
	tr._refresh_ui()
	return got_l

func back():
	if _game != null:
		_game.queue_free()
		_game = null
		_show_menu()
	else:
		visible = false

func _show_menu():
	_title.text = "Games"
	_sub.text = "Unlocked by buying upgrades (%d bought). They pay chrome coins, worth seconds to hours of your coin rate." % bought()
	if _menu != null:
		_menu.queue_free()
	_menu = VBoxContainer.new()
	_menu.anchor_right = 1.0
	_menu.margin_left = 24
	_menu.margin_right = -24
	_menu.margin_top = 84
	_menu.add_constant_override("separation", 10)
	add_child(_menu)
	for i in GAMES.size():
		var g: Array = GAMES[i]
		var row := Button.new()
		row.theme = preload("res://uitheme.tres")
		row.rect_min_size = Vector2(0, 64)
		row.clip_text = true
		var ok := unlocked(i)
		row.disabled = not ok
		row.align = Button.ALIGN_LEFT
		row.text = "   %s    —    %s" % [g[1], g[2]] if ok else "   %s    —    unlocks at %d upgrades bought (%d / %d)" % [g[1], g[3], min(bought(), g[3]), g[3]]
		row.add_font_override("font", tr._font(16))
		row.connect("pressed", self, "_open", [i])
		_menu.add_child(row)

func _open(i: int):
	if _menu != null:
		_menu.queue_free()
		_menu = null
	var g: Array = GAMES[i]
	_title.text = g[1]
	_sub.text = g[2]
	var cls = {"merge": MergeGame, "rush": RushGame, "wheel": WheelGame, "match": MatchGame}[g[0]]
	_game = cls.new()
	_game.games = self
	_game.anchor_right = 1.0
	_game.anchor_bottom = 1.0
	_game.margin_top = 84
	add_child(_game)

# --- a Chromia logo of any level ------------------------------------------------
# Level 1 is the logo as it is; every level after it changes its colour and
# adds rings, orbiting dots or spikes, so no two levels look the same.

const ADJ = ["Polished", "Neon", "Prismatic", "Mirrored", "Gleaming", "Holo", "Iridescent", "Radiant",
	"Glossy", "Liquid", "Cosmic", "Electric", "Shimmering", "Crystal", "Molten", "Silver", "Platinum",
	"Hyper", "Mega", "Sparkly", "Stellar", "Lucid", "Vivid", "Astral", "Quantum", "Eternal"]

static func logo_name(level: int) -> String:
	if level <= 1:
		return "Chromia"
	var a: String = ADJ[(level - 2) % ADJ.size()]
	var cycle := (level - 2) / ADJ.size()
	return "%s Chromia%s" % [a, "" if cycle == 0 else " " + str(cycle + 1)]

static func logo_color(level: int) -> Color:
	if level <= 1:
		return Color(1, 1, 1)
	return Color.from_hsv(fmod((level - 1) * 0.618034, 1.0), 0.55, 1.0)

# (one font per size, kept: made new for every logo every frame was slow)
static func _level_font(size: int) -> DynamicFont:
	var root: Viewport = Engine.get_main_loop().root
	var cache = root.get_meta("tree_minigame_fonts") if root.has_meta("tree_minigame_fonts") else {}
	if cache.has(size):
		return cache[size]
	var font := DynamicFont.new()
	font.font_data = load("res://assets/font/Lato/Lato-Bold.ttf")
	font.size = size
	font.outline_size = 2
	font.outline_color = Color(0, 0, 0, 0.85)
	cache[size] = font
	root.set_meta("tree_minigame_fonts", cache)
	return font

static func draw_logo(ci: CanvasItem, center: Vector2, size: float, level: int, t: float, show_level: bool = true):
	var col := logo_color(level)
	var r := size * 0.5
	var lv: int = int(max(1, level))
	# a glow that gets bigger every 5 levels
	var glow: float = min(0.5, 0.06 * ((lv - 1) / 5))
	if glow > 0:
		ci.draw_circle(center, r * (1.0 + glow), Color(col.r, col.g, col.b, 0.18))
	# spikes from level 8 on, a few more every 8 levels
	var spikes := ((lv - 1) / 8) * 3
	if spikes > 0:
		var pts := PoolVector2Array()
		var rot: float = t * 0.4 * (1 if lv % 2 == 0 else -1)
		for k in range(spikes * 2):
			var a: float = rot + PI * k / spikes
			var rr: float = r * (1.25 if k % 2 == 0 else 0.95)
			pts.append(center + Vector2(cos(a), sin(a)) * rr)
		ci.draw_colored_polygon(pts, Color(col.r * 0.8, col.g * 0.8, col.b * 0.8, 0.55))
	# rings: one more every 4 levels (up to 4, then they get thicker)
	var rings := (lv - 1) / 4
	for k in range(min(rings, 4)):
		var rr: float = r * (1.05 + 0.1 * k)
		ci.draw_arc(center, rr, 0, TAU, 40, Color(col.r, col.g, col.b, 0.7 - 0.12 * k), max(1.0, size * 0.025) * (1 + rings / 4), true)
	# the logo itself, tinted
	var s := r * 1.5
	ci.draw_texture_rect(LOGO, Rect2(center - Vector2(s, s) / 2, Vector2(s, s)), false, col)
	# orbiting dots: one more each level, 1 to 4, round and round
	var dots := (lv - 1) % 4 + (1 if lv > 1 else 0)
	for k in range(dots):
		var a: float = t * (1.5 + 0.1 * (lv % 7)) + TAU * k / max(1, dots)
		ci.draw_circle(center + Vector2(cos(a), sin(a)) * r * 0.92, max(1.5, size * 0.045), Color(1, 1, 1, 0.9))
	if show_level and size >= 34:
		var font: DynamicFont = _level_font(int(clamp(size * 0.22, 10, 22)))
		var txt := str(level)
		var ts := font.get_string_size(txt)
		ci.draw_string(font, center + Vector2(r * 0.95 - ts.x, r * 0.95), txt, Color(1, 1, 1))

# --- Chromia Merge ------------------------------------------------------------------

class MergeGame extends Control:
	var N := 5 # (the board's side: 5, bigger with the Bigger board upgrade)
	var games
	var board := []
	var best := 1
	# upgrades: [id, name, most levels, first price (seconds of coin rate), price x per level]
	const UPS := [
		["speed", "Faster logos", 12, 30.0, 2.2],
		["start", "Better new logos", 6, 120.0, 3.5],
		["board", "Bigger board", 2, 600.0, 12.0],
		["income", "Logo income", 25, 45.0, 1.9],
		["reward", "Merge rewards", 20, 40.0, 1.9],
		["auto", "Auto-merge", 10, 300.0, 2.4],
		["lucky", "Lucky merges", 6, 240.0, 3.0],
	]
	var up := {}
	var _up_box: VBoxContainer
	var _up_btns := {}
	var _auto_t := 0.0
	var _drag := -1
	var _drag_pos := Vector2()
	var _spawn_t := 0.0
	var _earn_t := 0.0
	var _t := 0.0
	var _msg := ""
	var _msg_t := 0.0
	var _font: DynamicFont
	var _font_small: DynamicFont
	var _pops := [] # [cell, time] merges, for a flash

	func _ready():
		mouse_filter = MOUSE_FILTER_STOP
		var st: Dictionary = games.state()
		var m = st.get("merge", {})
		if not (m is Dictionary):
			m = {}
		var u = m.get("up", {})
		for e in UPS:
			up[e[0]] = int(clamp(int(u.get(e[0], 0)) if u is Dictionary and (typeof(u.get(e[0])) == TYPE_REAL or typeof(u.get(e[0])) == TYPE_INT) else 0, 0, e[2]))
		N = 5 + int(up.board)
		var b = m.get("board", [])
		board = []
		for i in range(N * N):
			board.append(int(b[i]) if b is Array and i < b.size() and (typeof(b[i]) == TYPE_REAL or typeof(b[i]) == TYPE_INT) else 0)
		best = int(max(1, int(m.get("best", 1))))
		_font = games.tr._font(18)
		_font_small = games.tr._font(14)
		var bnew := Button.new()
		bnew.text = "New logo"
		bnew.theme = preload("res://uitheme.tres")
		bnew.rect_position = Vector2(24, 0)
		bnew.rect_size = Vector2(140, 38)
		bnew.connect("pressed", self, "_spawn")
		add_child(bnew)
		var bsort := Button.new()
		bsort.text = "Tidy up"
		bsort.theme = preload("res://uitheme.tres")
		bsort.rect_position = Vector2(176, 0)
		bsort.rect_size = Vector2(120, 38)
		bsort.hint_tooltip = "Puts the logos in order, highest first"
		bsort.connect("pressed", self, "_tidy")
		add_child(bsort)
		_build_upgrades()
		set_process(true)

	func _save():
		games.state()["merge"] = {"board": board, "best": best, "up": up.duplicate()}

	func spawn_level() -> int:
		# (new logos get better as you go, so it never stalls; Better new logos:
		# higher still, never as high as your best)
		var lv := int(max(1, best - 6)) + int(up.get("start", 0))
		return int(clamp(lv, 1, max(1, best - 1)))

	func spawn_every() -> float:
		return 3.0 * pow(0.85, int(up.get("speed", 0)))

	func auto_every() -> float:
		return 6.0 * pow(0.8, int(up.get("auto", 0)) - 1) if int(up.get("auto", 0)) > 0 else 0.0

	# --- upgrades (the panel on the right) ---
	const PANEL_W := 330.0

	func _price_l(e: Array) -> float:
		var secs: float = float(e[3]) * pow(float(e[4]), int(up.get(e[0], 0)))
		return max(games.tr._rate_l, 1.0) + games.tr.lg(secs)

	func _up_text(e: Array) -> String:
		var lv := int(up.get(e[0], 0))
		var what := ""
		match e[0]:
			"speed": what = "a new logo every %ss" % str(stepify(spawn_every(), 0.01))
			"start": what = "new logos +%d levels" % lv
			"board": what = "%dx%d board" % [N, N]
			"income": what = "logos make x%s coins" % str(stepify(pow(1.5, lv), 0.1))
			"reward": what = "merges pay x%s" % str(stepify(pow(2.0, lv), 1))
			"auto": what = ("merges a pair every %ss" % str(stepify(auto_every(), 0.1))) if lv > 0 else "merges pairs for you"
			"lucky": what = "%d%% of merges jump 2 levels" % (lv * 4)
		var head := "%s  %d/%d" % [e[1], lv, e[2]]
		if lv >= int(e[2]):
			return "%s\n%s  (maxed)" % [head, what]
		return "%s\n%s\n%s chrome coins" % [head, what, games.tr.fmtl(_price_l(e))]

	func _build_upgrades():
		_up_box = VBoxContainer.new()
		_up_box.anchor_left = 1.0
		_up_box.anchor_right = 1.0
		_up_box.margin_left = -PANEL_W - 24
		_up_box.margin_right = -24
		_up_box.margin_top = 54
		_up_box.add_constant_override("separation", 6)
		add_child(_up_box)
		var t := Label.new()
		t.text = "Upgrades"
		t.add_font_override("font", _font)
		t.add_color_override("font_color", Color(1, 0.756863, 0.960784))
		_up_box.add_child(t)
		for e in UPS:
			var b := Button.new()
			b.theme = preload("res://uitheme.tres")
			b.rect_min_size = Vector2(PANEL_W, 62)
			b.clip_text = true
			b.connect("pressed", self, "_buy", [e[0]])
			_up_box.add_child(b)
			# (a label inside: a button's own text is one line)
			var l := Label.new()
			l.name = "L"
			l.anchor_right = 1.0
			l.anchor_bottom = 1.0
			l.margin_left = 10
			l.margin_right = -8
			l.valign = Label.VALIGN_CENTER
			l.clip_text = true
			l.mouse_filter = MOUSE_FILTER_IGNORE
			l.add_font_override("font", _font_small)
			l.add_color_override("font_color", Color(0.06, 0.04, 0.08))
			b.add_child(l)
			_up_btns[e[0]] = b
		_refresh_upgrades()

	func _refresh_upgrades():
		for e in UPS:
			var b: Button = _up_btns[e[0]]
			var lv := int(up.get(e[0], 0))
			b.get_node("L").text = _up_text(e)
			b.disabled = lv >= int(e[2]) or games.tr.coins_l < _price_l(e)
			b.get_node("L").modulate.a = 0.55 if b.disabled else 1.0

	func _buy(id: String):
		for e in UPS:
			if e[0] != id:
				continue
			if int(up.get(id, 0)) >= int(e[2]):
				return
			var cost := _price_l(e)
			if games.tr.coins_l < cost:
				_say("Not enough chrome coins yet.")
				return
			games.tr.coins_l = games.tr.lsub(games.tr.coins_l, cost)
			up[id] = int(up.get(id, 0)) + 1
			if id == "board":
				_grow_board(5 + int(up.board))
			_say("%s: level %d" % [e[1], int(up[id])])
			_save()
			games.tr._refresh_ui()
			_refresh_upgrades()
			update()
			return

	# a bigger board: the logos keep their places (row, column)
	func _grow_board(n: int):
		var nb := []
		for i in range(n * n):
			nb.append(0)
		for i in board.size():
			var r: int = int(i) / N
			var c: int = int(i) % N
			if r < n and c < n:
				nb[r * n + c] = board[i]
		board = nb
		N = n

	# Auto-merge: the lowest pair of the same logo merges by itself
	func _auto_merge():
		var seen := {}
		var pick := []
		for i in board.size():
			var v: int = board[i]
			if v <= 0:
				continue
			if seen.has(v):
				if pick.empty() or v < board[pick[0]]:
					pick = [seen[v], i]
			else:
				seen[v] = i
		if not pick.empty():
			_drop(pick[1], pick[0])

	func _spawn():
		var empty := []
		for i in board.size():
			if board[i] == 0:
				empty.append(i)
		if empty.empty():
			_say("The board is full: merge some logos.")
			return
		board[empty[randi() % empty.size()]] = spawn_level()
		_save()
		update()

	func _tidy():
		var vals := []
		for v in board:
			if v > 0:
				vals.append(v)
		vals.sort()
		vals.invert()
		for i in board.size():
			board[i] = vals[i] if i < vals.size() else 0
		_save()
		update()

	func _say(t: String):
		_msg = t
		_msg_t = 3.0

	# the board's place on screen: square, as big as fits
	func _geo() -> Array:
		var top := 54.0
		var w: float = rect_size.x - PANEL_W - 24
		var avail := Vector2(w - 48, rect_size.y - top - 70)
		var s: float = max(120.0, min(avail.x, avail.y))
		var cell := s / N
		var origin := Vector2((w - s) / 2, top)
		return [origin, cell]

	func _cell_at(p: Vector2) -> int:
		var g := _geo()
		var q: Vector2 = (p - g[0]) / g[1]
		if q.x < 0 or q.y < 0 or q.x >= N or q.y >= N:
			return -1
		return int(q.y) * N + int(q.x)

	func _gui_input(ev):
		if ev is InputEventMouseButton and ev.button_index == BUTTON_LEFT:
			if ev.pressed:
				var c := _cell_at(ev.position)
				if c >= 0 and board[c] > 0:
					_drag = c
					_drag_pos = ev.position
			elif _drag >= 0:
				var to := _cell_at(ev.position)
				_drop(_drag, to)
				_drag = -1
			update()
			accept_event()
		elif ev is InputEventMouseMotion and _drag >= 0:
			_drag_pos = ev.position
			update()

	func _drop(from: int, to: int):
		if to < 0 or to == from:
			return
		var a: int = board[from]
		var b: int = board[to]
		if b == a:
			var lv := a + 1
			# Lucky merges: now and then two levels up
			var lucky: bool = randf() < 0.04 * int(up.get("lucky", 0))
			if lucky:
				lv += 1
			board[to] = lv
			board[from] = 0
			_pops.append([to, _t])
			var got_l: float = games.reward(games.tr.lg(2.0) + (lv - 1) * games.tr.lg(1.6) + int(up.get("reward", 0)) * games.tr.lg(2.0))
			if lucky:
				_say("Lucky! Two levels up: %d, %s   (+%s)" % [lv, games.logo_name(lv), games.tr.fmtl(got_l)])
				if lv > best:
					best = lv
				_save()
				return
			if lv > best:
				best = lv
				_say("New logo! Level %d: %s   (+%s chrome coins)" % [lv, games.logo_name(lv), games.tr.fmtl(got_l)])
			else:
				_say("Level %d: %s   (+%s)" % [lv, games.logo_name(lv), games.tr.fmtl(got_l)])
		elif b == 0:
			board[to] = a
			board[from] = 0
		else:
			board[to] = a
			board[from] = b
		_save()

	func _process(delta):
		if not is_visible_in_tree():
			return
		_t += delta
		_msg_t -= delta
		# a new logo every 3 seconds while there's room
		_spawn_t += delta
		if _spawn_t >= spawn_every():
			_spawn_t = 0.0
			if board.has(0):
				_spawn()
		if int(up.get("auto", 0)) > 0:
			_auto_t += delta
			if _auto_t >= auto_every() and _drag < 0:
				_auto_t = 0.0
				_auto_merge()
		# every logo makes coins: level L is worth 1.6^(L-1) twentieths of a second a second
		_earn_t += delta
		if _earn_t >= 1.0:
			_earn_t = 0.0
			var tot: float = -1.0e18 # (nothing yet: the tree's LZERO)
			for v in board:
				if v > 0:
					tot = games.tr.ladd(tot, games.tr.lg(0.05) + (v - 1) * games.tr.lg(1.6))
			if tot > -1.0e17:
				games.reward(tot + int(up.get("income", 0)) * games.tr.lg(1.5))
			_refresh_upgrades() # (what you can afford now)
		update()

	func _draw():
		var g := _geo()
		var o: Vector2 = g[0]
		var cell: float = g[1]
		draw_rect(Rect2(o - Vector2(6, 6), Vector2(cell * N + 12, cell * N + 12)), Color(1, 1, 1, 0.05))
		for i in range(N * N):
			var p := o + Vector2(i % N, i / N) * cell
			draw_rect(Rect2(p + Vector2(3, 3), Vector2(cell - 6, cell - 6)), Color(0.1, 0.08, 0.13), true)
			draw_rect(Rect2(p + Vector2(3, 3), Vector2(cell - 6, cell - 6)), Color(1, 1, 1, 0.08), false)
			if board[i] > 0 and i != _drag:
				games.draw_logo(self, p + Vector2(cell, cell) / 2, cell * 0.7, board[i], _t)
		for pop in _pops.duplicate():
			var age: float = _t - pop[1]
			if age > 0.4:
				_pops.erase(pop)
				continue
			var p := o + Vector2(pop[0] % N, pop[0] / N) * cell + Vector2(cell, cell) / 2
			draw_arc(p, cell * (0.35 + age), 0, TAU, 32, Color(1, 1, 1, 1.0 - age / 0.4), 3, true)
		if _drag >= 0:
			games.draw_logo(self, _drag_pos, cell * 0.8, board[_drag], _t)
		var info := "Best: level %d, %s    ·    new logos: level %d" % [best, games.logo_name(best), spawn_level()]
		draw_string(_font_small, Vector2(312, 24), info, Color(1, 1, 1, 0.6))
		if _msg_t > 0:
			var ts := _font.get_string_size(_msg)
			draw_string(_font, Vector2((rect_size.x - ts.x) / 2, o.y + cell * N + 40), _msg, Color(1, 0.86, 0.98, clamp(_msg_t, 0, 1)))

# --- Note Rush -------------------------------------------------------------------------

class RushGame extends Control:
	const ROUND_S := 30.0
	const LIFE := 1.1
	var games
	var _playing := false
	var _t := 0.0
	var _left := 0.0
	var _next := 0.0
	var _notes := [] # [cell 0..8, born]
	var _hits := 0
	var _combo := 0
	var _misses := 0
	var _font: DynamicFont
	var _font_big: DynamicFont
	var _btn: Button
	var _result := ""

	func _ready():
		mouse_filter = MOUSE_FILTER_STOP
		_font = games.tr._font(16)
		_font_big = games.tr._font(30)
		_btn = Button.new()
		_btn.text = "Start"
		_btn.theme = preload("res://uitheme.tres")
		_btn.rect_position = Vector2(24, 0)
		_btn.rect_size = Vector2(140, 38)
		_btn.connect("pressed", self, "_start")
		add_child(_btn)
		set_process(true)

	func _start():
		_playing = true
		_left = ROUND_S
		_notes = []
		_hits = 0
		_combo = 0
		_misses = 0
		_next = 0.3
		_result = ""
		_btn.visible = false

	func _geo() -> Array:
		var top := 54.0
		var s: float = max(120.0, min(rect_size.x - 48, rect_size.y - top - 60))
		return [Vector2((rect_size.x - s) / 2, top), s / 3.0]

	func _gui_input(ev):
		if not _playing or not (ev is InputEventMouseButton) or not ev.pressed or ev.button_index != BUTTON_LEFT:
			return
		var g := _geo()
		var q: Vector2 = (ev.position - g[0]) / g[1]
		if q.x < 0 or q.y < 0 or q.x >= 3 or q.y >= 3:
			return
		var c := int(q.y) * 3 + int(q.x)
		for n in _notes:
			if n[0] == c:
				_notes.erase(n)
				_hits += 1
				_combo += 1
				return
		_combo = 0 # (clicked an empty square)
		accept_event()

	func _process(delta):
		_t += delta
		if _playing:
			_left -= delta
			_next -= delta
			# faster as the round goes on
			if _next <= 0.0:
				var free := []
				for c in range(9):
					var used := false
					for n in _notes:
						if n[0] == c:
							used = true
					if not used:
						free.append(c)
				if not free.empty():
					_notes.append([free[randi() % free.size()], _t])
				_next = lerp(0.7, 0.32, 1.0 - _left / ROUND_S)
			for n in _notes.duplicate():
				if _t - n[1] > LIFE:
					_notes.erase(n)
					_misses += 1
					_combo = 0
			if _left <= 0.0:
				_playing = false
				var st: Dictionary = games.state()
				var best := int(st.get("rush_best", 0))
				var got_l: float = games.reward(games.tr.lg(max(1.0, _hits * 4.0)))
				if _hits > best:
					st["rush_best"] = _hits
				_result = "%d hits, %d missed  ·  +%s chrome coins%s" % [_hits, _misses, games.tr.fmtl(got_l), "  ·  new best!" if _hits > best else ""]
				_btn.text = "Again"
				_btn.visible = true
		update()

	func _draw():
		var g := _geo()
		var o: Vector2 = g[0]
		var cell: float = g[1]
		for i in range(4):
			draw_line(o + Vector2(i * cell, 0), o + Vector2(i * cell, cell * 3), Color(1, 1, 1, 0.25), 2)
			draw_line(o + Vector2(0, i * cell), o + Vector2(cell * 3, i * cell), Color(1, 1, 1, 0.25), 2)
		for n in _notes:
			var k: float = clamp((_t - n[1]) / LIFE, 0, 1)
			var p := o + Vector2(n[0] % 3, n[0] / 3) * cell + Vector2(cell, cell) / 2
			var col: Color = games.logo_color(2 + n[0])
			var s: float = cell * 0.78
			draw_rect(Rect2(p - Vector2(s, s) / 2, Vector2(s, s)), Color(col.r, col.g, col.b, 0.9 - 0.6 * k), false, 5)
			var a: float = s * (1.0 - k)
			draw_rect(Rect2(p - Vector2(a, a) / 2, Vector2(a, a)), Color(1, 1, 1, 0.25), false, 2)
		var info := "Time %.1f    Hits %d    Combo %d    Best %d" % [max(_left, 0.0), _hits, _combo, int(games.state().get("rush_best", 0))]
		draw_string(_font, Vector2(180, 24), info, Color(1, 1, 1, 0.7))
		if _result != "":
			var ts := _font.get_string_size(_result)
			draw_string(_font, Vector2((rect_size.x - ts.x) / 2, o.y + cell * 3 + 34), _result, Color(1, 0.86, 0.98))

# --- Lucky Wheel -----------------------------------------------------------------------

class WheelGame extends Control:
	const COOLDOWN := 600
	# [label, seconds of your coin rate (0: a feature)]
	const SLICES = [["1 min", 60.0], ["5 min", 300.0], ["A feature", 0.0], ["15 min", 900.0],
		["2 min", 120.0], ["1 hour", 3600.0], ["10 min", 600.0], ["JACKPOT 6 h", 21600.0]]
	var games
	var _font: DynamicFont
	var _font_small: DynamicFont
	var _btn: Button
	var _angle := 0.0
	var _spin := 0.0 # left to turn
	var _speed := 0.0
	var _result := ""

	func _ready():
		mouse_filter = MOUSE_FILTER_STOP
		_font = games.tr._font(18)
		_font_small = games.tr._font(13)
		_btn = Button.new()
		_btn.theme = preload("res://uitheme.tres")
		_btn.rect_position = Vector2(24, 0)
		_btn.rect_size = Vector2(160, 38)
		_btn.connect("pressed", self, "_go")
		add_child(_btn)
		set_process(true)

	func _wait_s() -> int:
		var last := int(games.state().get("wheel_t", 0))
		return int(max(0, last + COOLDOWN - OS.get_unix_time()))

	func _go():
		if _wait_s() > 0 or _spin > 0.0:
			return
		games.state()["wheel_t"] = OS.get_unix_time()
		_spin = TAU * (4 + randf() * 2)
		_speed = _spin * 1.6
		_result = ""

	func _process(delta):
		if _spin > 0.0:
			var step: float = min(_spin, max(0.6, _speed) * delta)
			_speed = max(0.6, _speed - _speed * 0.75 * delta)
			_angle = fmod(_angle + step, TAU)
			_spin -= step
			if _spin <= 0.0:
				_land()
		var w := _wait_s()
		_btn.disabled = w > 0 or _spin > 0.0
		_btn.text = "Spin!" if w == 0 else "Next spin %d:%02d" % [w / 60, w % 60]
		update()

	func _land():
		var n := SLICES.size()
		# the pointer is at the top: which slice is under it
		var a: float = fmod(TAU - _angle + PI / n + TAU * 10.0, TAU)
		var i := int(a / (TAU / n)) % n
		var s: Array = SLICES[i]
		if float(s[1]) <= 0.0:
			var got: Array = games.tr._discover(1)
			games.tr._recalc()
			games.tr._refresh_ui()
			_result = "A new feature: %s" % games.tr.feat_name(got[0]) if not got.empty() else "Every feature is found already: +1 hour of coins"
			if got.empty():
				games.reward(games.tr.lg(3600.0))
		else:
			var got_l: float = games.reward(games.tr.lg(float(s[1])))
			_result = "%s of coins: +%s chrome coins" % [s[0], games.tr.fmtl(got_l)]

	func _draw():
		var r: float = max(60.0, min(rect_size.x - 80, rect_size.y - 140) / 2.0)
		var c := Vector2(rect_size.x / 2, 60 + r)
		var n := SLICES.size()
		for i in range(n):
			var a0: float = _angle + TAU * i / n - PI / 2 - PI / n
			var pts := PoolVector2Array([c])
			for k in range(17):
				var a: float = a0 + (TAU / n) * k / 16.0
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			var col: Color = games.logo_color(2 + i * 3)
			if i == n - 1:
				col = Color(1, 0.82, 0.35)
			draw_colored_polygon(pts, Color(col.r * 0.55, col.g * 0.55, col.b * 0.55))
			var mid: float = a0 + PI / n
			var txt: String = SLICES[i][0]
			var ts := _font_small.get_string_size(txt)
			draw_string(_font_small, c + Vector2(cos(mid), sin(mid)) * r * 0.62 - ts / 2 + Vector2(0, ts.y * 0.7), txt, Color(1, 1, 1))
		draw_arc(c, r, 0, TAU, 64, Color(1, 1, 1, 0.5), 3, true)
		games.draw_logo(self, c, r * 0.36, 1, 0.0, false)
		draw_colored_polygon(PoolVector2Array([c + Vector2(-12, -r - 16), c + Vector2(12, -r - 16), c + Vector2(0, -r + 6)]), Color(1, 0.76, 0.96))
		if _result != "":
			var ts := _font.get_string_size(_result)
			draw_string(_font, Vector2((rect_size.x - ts.x) / 2, c.y + r + 34), _result, Color(1, 0.86, 0.98))

# --- Memory Match ----------------------------------------------------------------------

class MatchGame extends Control:
	var games
	var cards := [] # level of each card
	var open := [] # card indexes face up now (not matched yet)
	var done := {} # matched cards
	var tries := 0
	var _hide_t := 0.0
	var _font: DynamicFont
	var _btn: Button
	var _result := ""
	var _t := 0.0

	func _ready():
		mouse_filter = MOUSE_FILTER_STOP
		_font = games.tr._font(17)
		_btn = Button.new()
		_btn.text = "New game"
		_btn.theme = preload("res://uitheme.tres")
		_btn.rect_position = Vector2(24, 0)
		_btn.rect_size = Vector2(140, 38)
		_btn.connect("pressed", self, "_deal")
		add_child(_btn)
		_deal()
		set_process(true)

	func _deal():
		cards = []
		var base := randi() % 20
		for i in range(8):
			cards.append(2 + base + i * 3)
			cards.append(2 + base + i * 3)
		cards.shuffle()
		open = []
		done = {}
		tries = 0
		_result = ""

	func _geo() -> Array:
		var top := 54.0
		var s: float = max(160.0, min(rect_size.x - 48, rect_size.y - top - 60))
		return [Vector2((rect_size.x - s) / 2, top), s / 4.0]

	func _gui_input(ev):
		if not (ev is InputEventMouseButton) or not ev.pressed or ev.button_index != BUTTON_LEFT:
			return
		if _hide_t > 0.0 or _result != "":
			return
		var g := _geo()
		var q: Vector2 = (ev.position - g[0]) / g[1]
		if q.x < 0 or q.y < 0 or q.x >= 4 or q.y >= 4:
			return
		var i := int(q.y) * 4 + int(q.x)
		if done.has(i) or open.has(i):
			return
		open.append(i)
		if open.size() == 2:
			tries += 1
			if cards[open[0]] == cards[open[1]]:
				done[open[0]] = true
				done[open[1]] = true
				open = []
				if done.size() == cards.size():
					_win()
			else:
				_hide_t = 0.8
		accept_event()

	func _win():
		var st: Dictionary = games.state()
		var best := int(st.get("match_best", 0))
		var secs: float = max(60.0, 1800.0 - (tries - 8) * 90.0)
		var got_l: float = games.reward(games.tr.lg(secs))
		var new_best := best == 0 or tries < best
		if new_best:
			st["match_best"] = tries
		_result = "All pairs in %d tries  ·  +%s chrome coins%s" % [tries, games.tr.fmtl(got_l), "  ·  new best!" if new_best else ""]

	func _process(delta):
		_t += delta
		if _hide_t > 0.0:
			_hide_t -= delta
			if _hide_t <= 0.0:
				open = []
		update()

	func _draw():
		var g := _geo()
		var o: Vector2 = g[0]
		var cell: float = g[1]
		for i in range(16):
			var p := o + Vector2(i % 4, i / 4) * cell
			var r := Rect2(p + Vector2(5, 5), Vector2(cell - 10, cell - 10))
			var up: bool = done.has(i) or open.has(i)
			draw_rect(r, Color(0.16, 0.12, 0.2) if up else Color(0.32, 0.23, 0.35))
			draw_rect(r, Color(1, 1, 1, 0.12), false)
			if up:
				games.draw_logo(self, r.position + r.size / 2, cell * 0.62, cards[i], _t, false)
			else:
				games.draw_logo(self, r.position + r.size / 2, cell * 0.36, 1, 0.0, false)
		var info := "Tries %d    Pairs %d / 8    Best %s" % [tries, done.size() / 2, str(games.state().get("match_best", "-"))]
		draw_string(_font, Vector2(180, 24), info, Color(1, 1, 1, 0.7))
		if _result != "":
			var ts := _font.get_string_size(_result)
			draw_string(_font, Vector2((rect_size.x - ts.x) / 2, o.y + cell * 4 + 34), _result, Color(1, 0.86, 0.98))

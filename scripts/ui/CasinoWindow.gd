extends PanelContainer

# The casino in the game: the Discord bot's /casino as a window (the chat's
# /casino opens it: ChatCommands.gd). The same chips, games, daily bonus,
# gifts and leaderboard as the Discord server's /casino: they're your linked
# Discord account's (the server's casino.js gameApi; LobbyManager.casino_send
# and casino_update). Without a linked Discord it says so.
#
# Pages: the casino (your chips, the daily bonus, the ten games, Leaderboard,
# Give chips, How it works), a game's table (what it pays, your bet with
# half / double / max / a typed one, the buttons that play it and what
# happened), a game with steps in progress (blackjack, mines, higher or lower,
# video poker), the leaderboard, giving chips, the rules.

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")
const CARD_FONT := "res://assets/font/Noto_Sans_JP/NotoSansJP-Medium.otf" # (has ♠ ♥ ♦ ♣)
const GOLD := Color("#f2c14e")
const WIN := Color("#4caf7d")
const LOSE := Color("#d9534f")
const RED_SUIT := Color("#e0505a")

var S
var lm
var _state := {} # the server's: bal, daily_ready, daily_next, streak, bet, list, current...
var _page := "hub" # hub, table, current, top, give, help
var _game := "" # the table's game
var _result = null # the last round of a game played in one go
var _current = null # a game with steps (in progress, or just over)
var _board = null
var _help := ""
var _note := "" # a line from the server: what the daily bonus gave, a gift...
var _error := ""
var _chips: Label
var _body: VBoxContainer
var _msg: Label
var _bet_box: LineEdit
var _f_card: DynamicFont
var _f_big: DynamicFont

static func open(host: Node):
	if host == null or not is_instance_valid(host) or not host.is_inside_tree():
		return null
	var tree = host.get_tree()
	var old = tree.root.find_node("CasinoLayer", true, false)
	if old != null:
		old.queue_free()
	var layer := CanvasLayer.new()
	layer.layer = 110
	layer.name = "CasinoLayer"
	# (on the screen the chat is on: in VR the menu screen)
	host.get_viewport().add_child(layer)
	var dim := ColorRect.new()
	dim.add_to_group("wheel_blocker") # (the map list behind it does not scroll: Savia.wheel_blocked)
	dim.color = Color(0, 0, 0, 0.55)
	dim.anchor_right = 1
	dim.anchor_bottom = 1
	layer.add_child(dim)
	var w = load("res://scripts/ui/CasinoWindow.gd").new()
	w.name = "Casino"
	layer.add_child(w)
	dim.connect("gui_input", w, "_on_dim")
	return w

func _init():
	S = OnlineStyle.new()
	_f_card = DynamicFont.new()
	_f_card.font_data = load(CARD_FONT)
	_f_card.size = 22
	_f_big = DynamicFont.new()
	_f_big.font_data = load(CARD_FONT)
	_f_big.size = 34
	add_stylebox_override("panel", OnlineStyle.flat(S.WINDOW_BG, 6, Color(1, 1, 1, 0.1), 1, 20, 16))
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 10)
	add_child(v)
	var head := HBoxContainer.new()
	head.add_constant_override("separation", 10)
	v.add_child(head)
	var t: Label = S.heading("Casino")
	head.add_child(t)
	_chips = S.label("", S.f_bold, GOLD)
	_chips.size_flags_horizontal = SIZE_EXPAND_FILL
	_chips.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(_chips)
	var x := Button.new()
	x.text = "Close"
	S.button(x, false, true)
	x.connect("pressed", self, "close")
	head.add_child(x)
	_msg = S.label("", S.f_regular, S.DIM, true)
	_msg.visible = false
	v.add_child(_msg)
	var sc := ScrollContainer.new()
	sc.scroll_horizontal_enabled = false
	sc.size_flags_vertical = SIZE_EXPAND_FILL
	S.scroll(sc)
	v.add_child(sc)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = SIZE_EXPAND_FILL
	_body.add_constant_override("separation", 10)
	sc.add_child(_body)

func _ready():
	lm = get_node_or_null("/root/LobbyManager")
	if lm != null and lm.has_signal("casino_update"):
		lm.connect("casino_update", self, "_on_update")
		lm.casino_send("state")
	get_viewport().connect("size_changed", self, "_place")
	call_deferred("_place")
	_body.add_child(S.label("Opening the casino...", S.f_regular, S.DIM))

func _place():
	var vp := get_viewport_rect().size
	rect_size = Vector2(min(720.0, vp.x - 40.0), min(680.0, vp.y - 50.0))
	rect_position = ((vp - rect_size) / 2.0).floor()

func _on_dim(ev):
	if ev is InputEventMouseButton and ev.pressed:
		close()

func _input(ev):
	if ev is InputEventKey and ev.pressed and ev.scancode == KEY_ESCAPE:
		close()
		get_tree().set_input_as_handled()

func close():
	var layer = get_parent()
	if layer is CanvasLayer:
		layer.queue_free()
	else:
		queue_free()

# --- the server's answers ---------------------------------------------------------------

func _on_update(msg: Dictionary):
	var st = msg.get("state")
	if st is Dictionary:
		_state = st
	_error = "" if msg.get("ok", false) else Globals.s(msg.get("error", ""))
	_note = Globals.s(msg.get("note", "")) if msg.get("note") is String else ""
	var op := Globals.s(msg.get("op", ""))
	if msg.get("result") is Dictionary:
		_result = msg.result
		_page = "table"
	if msg.get("current") is Dictionary:
		_current = msg.current
		_page = "current"
	elif op == "step" and not msg.get("ok", false):
		_current = null
		_page = "table" if _game != "" else "hub"
	if msg.get("board") is Dictionary:
		_board = msg.board
		_page = "top"
	if msg.get("help") is String:
		_help = msg.help
		_page = "help"
	# (a game with steps left open, here or on Discord: back to it)
	if op == "state" and _state.get("current") is Dictionary and not bool(_state.current.get("done", false)):
		_current = _state.current
		_game = Globals.s(_current.get("game", ""))
		_page = "current"
	_render()

func _send(op: String, payload: Dictionary = {}):
	if lm != null:
		lm.casino_send(op, payload)

# --- drawing ----------------------------------------------------------------------------

static func _fmt(n) -> String:
	return Globals.comma_sep(int(n))

static func _chips_text(n) -> String:
	return "%s %s" % [_fmt(n), "chip" if int(n) == 1 else "chips"]

static func _x(m) -> String:
	return "x%.2f" % (floor(float(m) * 100.0 + 0.000001) / 100.0)

func _clear():
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()

func _render():
	_clear()
	if not bool(_state.get("linked", true)) or (_state.empty() and _error != ""):
		_chips.text = ""
		_msg.visible = false
		var l = S.label(_error if _error != "" else "Link Discord (Profile) to play the casino.", S.f_bold, S.TEXT, true)
		_body.add_child(l)
		_body.add_child(S.label("Your chips are your Discord account's: the same as the Discord server's /casino.", S.f_regular, S.DIM, true))
		return
	_chips.text = "%s" % _chips_text(_state.get("bal", 0))
	var line := _error if _error != "" else _note
	_msg.text = line
	_msg.visible = line != ""
	_msg.add_color_override("font_color", LOSE if _error != "" else WIN)
	match _page:
		"table": _draw_table()
		"current": _draw_current()
		"top": _draw_top()
		"give": _draw_give()
		"help": _draw_help()
		_: _draw_hub()

func _row(sep: int = 6) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_constant_override("separation", sep)
	_body.add_child(h)
	return h

func _btn(parent: Control, text: String, method: String, binds: Array = [], accent: bool = false, disabled: bool = false) -> Button:
	var b: Button = S.make_button(text, self, method, binds, accent, true)
	b.rect_min_size.y = 40
	b.disabled = disabled
	b.focus_mode = Control.FOCUS_NONE
	parent.add_child(b)
	return b

func _text(t: String, col = null, f: Font = null) -> Label:
	var l = S.label(t, f if f != null else S.f_regular, col if col is Color else S.TEXT, true)
	_body.add_child(l)
	return l

func _back_row():
	var h := _row()
	_btn(h, "Games", "_go_hub")

# the casino's first page
func _draw_hub():
	var place = _state.get("place")
	_text("Your chips: %s%s" % [_chips_text(_state.get("bal", 0)), ("  ·  #%d on the leaderboard" % int(place)) if place != null else ""], S.TEXT, S.f_bold)
	if int(_state.get("games", 0)) > 0:
		_text("Games played: %s  ·  biggest win: %s" % [_fmt(_state.games), _chips_text(_state.get("best", 0))], S.DIM)
	var dh := _row(10)
	if bool(_state.get("daily_ready", false)):
		_btn(dh, "Collect your daily bonus", "_daily", [], true)
	else:
		var left: int = int(max(0, int(_state.get("daily_next", 0)) - int(_state.get("now", 0))))
		var hrs: int = left / 3600000
		var mins: int = (left % 3600000) / 60000
		var b = _btn(dh, "Daily bonus in %dh %dm" % [hrs, mins], "_daily")
		b.hint_tooltip = "Comes back 20 hours after the last one"
	if int(_state.get("streak", 0)) > 1:
		var st = S.label("%d days in a row" % int(_state.streak), S.f_small, S.DIM)
		st.size_flags_vertical = SIZE_SHRINK_CENTER
		dh.add_child(st)
	if _state.get("current") is Dictionary and not bool(_state.current.get("done", false)):
		var ch := _row()
		_btn(ch, "Back to your %s game" % _game_name(Globals.s(_state.current.get("game", ""))), "_resume", [], true)
	_text("Pick a game. Chips are play money: they can't be bought or cashed in.", S.DIM)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_constant_override("hseparation", 8)
	grid.add_constant_override("vseparation", 8)
	_body.add_child(grid)
	for g in _state.get("list", []):
		if not (g is Dictionary):
			continue
		# (a button with the name over what it is: a Button's own text is one line)
		var b := Button.new()
		S.button(b, false, true)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.rect_min_size = Vector2(0, 62)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.connect("pressed", self, "_pick", [Globals.s(g.get("id", ""))])
		var lv := VBoxContainer.new()
		lv.anchor_right = 1
		lv.anchor_bottom = 1
		lv.margin_left = 12
		lv.margin_right = -8
		lv.alignment = BoxContainer.ALIGN_CENTER
		lv.add_constant_override("separation", 0)
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(lv)
		var nl = S.label(Globals.s(g.get("name", "")), S.f_bold, S.TEXT)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(nl)
		var wl = S.label(Globals.s(g.get("what", "")), S.f_small, S.DIM)
		wl.clip_text = true
		wl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_child(wl)
		grid.add_child(b)
	var more := _row(8)
	_btn(more, "Leaderboard", "_top", ["bal"])
	_btn(more, "Give chips", "_go_give")
	_btn(more, "How it works", "_help_page")

func _game_info(id: String) -> Dictionary:
	for g in _state.get("list", []):
		if g is Dictionary and Globals.s(g.get("id", "")) == id:
			return g
	return {}

func _game_name(id: String) -> String:
	return Globals.s(_game_info(id).get("name", id))

# a game's table: what it pays, the bet, the buttons that play it, what happened
func _draw_table():
	var info := _game_info(_game)
	_text(Globals.s(info.get("name", "")), S.ACCENT, S.f_head)
	_text(Globals.s(info.get("pays", "")), S.DIM)
	if _result is Dictionary and Globals.s(_result.get("game", "")) == _game:
		_draw_result(_result)
	var b := _row(6)
	var bl = S.label("Bet: %s" % _chips_text(_state.get("bet", 0)), S.f_bold, GOLD)
	bl.size_flags_vertical = SIZE_SHRINK_CENTER
	b.add_child(bl)
	_btn(b, "½", "_bet", ["half"])
	_btn(b, "×2", "_bet", ["dbl"])
	_btn(b, "Max", "_bet", ["max"])
	_bet_box = LineEdit.new()
	_bet_box.placeholder_text = "Bet"
	_bet_box.rect_min_size = Vector2(90, 40)
	S.field(_bet_box)
	_bet_box.connect("text_entered", self, "_bet_typed")
	b.add_child(_bet_box)
	_btn(b, "Set", "_bet_typed", [""])
	_play_buttons()
	_back_row()

func _play_buttons():
	var again = _result is Dictionary and Globals.s(_result.get("game", "")) == _game
	match _game:
		"slots":
			_btn(_row(), "Spin again" if again else "Spin", "_play", ["slots", ""], true)
		"coinflip":
			var h := _row()
			_btn(h, "Heads", "_play", ["coinflip", "heads"], true)
			_btn(h, "Tails", "_play", ["coinflip", "tails"], true)
		"dice":
			var h := _row()
			_btn(h, "Over 7 (x2.3)", "_play", ["dice", "over"], true)
			_btn(h, "Under 7 (x2.3)", "_play", ["dice", "under"], true)
			_btn(h, "Exactly 7 (x5.8)", "_play", ["dice", "seven"], true)
		"baccarat":
			var h := _row()
			_btn(h, "Player (x2)", "_play", ["baccarat", "player"], true)
			_btn(h, "Banker (x1.95)", "_play", ["baccarat", "banker"], true)
			_btn(h, "Tie (x9)", "_play", ["baccarat", "tie"], true)
		"roulette":
			var h := _row()
			_btn(h, "Red", "_play", ["roulette", "red"], true)
			_btn(h, "Black", "_play", ["roulette", "black"], true)
			_btn(h, "Odd", "_play", ["roulette", "odd"])
			_btn(h, "Even", "_play", ["roulette", "even"])
			var h2 := _row()
			_btn(h2, "1-18", "_play", ["roulette", "low"])
			_btn(h2, "19-36", "_play", ["roulette", "high"])
			_btn(h2, "1st 12", "_play", ["roulette", "first"])
			_btn(h2, "2nd 12", "_play", ["roulette", "second"])
			_btn(h2, "3rd 12", "_play", ["roulette", "third"])
			var h3 := _row()
			var nb := LineEdit.new()
			nb.placeholder_text = "0 to 36"
			nb.rect_min_size = Vector2(90, 40)
			if _state.get("num") != null:
				nb.text = str(int(_state.num))
			S.field(nb)
			h3.add_child(nb)
			var go = _btn(h3, "Bet on this number (x36)", "_play_number", [nb], true)
			nb.connect("text_entered", self, "_number_entered", [nb])
			go.hint_tooltip = "One number from 0 to 36 pays x36"
		"crash":
			var h := _row()
			for t in [1.5, 2, 3, 5, 10]:
				_btn(h, "Cash out at x%s" % str(t), "_play", ["crash", str(t)], true)
			var h2 := _row()
			var cb := LineEdit.new()
			cb.placeholder_text = "e.g. 2.5"
			cb.rect_min_size = Vector2(90, 40)
			if _state.get("cash") != null:
				cb.text = str(_state.cash)
			S.field(cb)
			h2.add_child(cb)
			_btn(h2, "Cash out at this point", "_play_crash", [cb], true)
		"mines":
			_text("How many of the 20 tiles are mines? (More mines: bigger prizes.)", S.DIM)
			var h := _row()
			for n in [1, 3, 5, 10, 15]:
				_btn(h, "%d %s" % [n, "mine" if n == 1 else "mines"], "_play", ["mines", str(n)], n == int(_state.get("mines", 3)))
		"higherlower":
			_btn(_row(), "Play again" if again else "Start", "_play", ["higherlower", ""], true)
		_:
			_btn(_row(), "Deal again" if again else "Deal", "_play", [_game, ""], true)

# what a game played in one go did
func _draw_result(r: Dictionary):
	var box := PanelContainer.new()
	var pay := int(r.get("pay", 0))
	var stake := int(r.get("stake", 0))
	var col: Color = WIN if pay > stake else (S.DIM if pay == stake else LOSE)
	box.add_stylebox_override("panel", OnlineStyle.flat(S.CARD_BG, 6, col, 2, 16, 12))
	_body.add_child(box)
	var v := VBoxContainer.new()
	v.add_constant_override("separation", 6)
	box.add_child(v)
	match Globals.s(r.get("game", "")):
		"slots":
			var h := HBoxContainer.new()
			h.alignment = BoxContainer.ALIGN_CENTER
			h.add_constant_override("separation", 14)
			v.add_child(h)
			for k in r.get("keys", []):
				var t := TextureRect.new()
				t.texture = load("res://scripts/ui/Emoji.gd")._texture(String(k))
				t.expand = true
				t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				t.rect_min_size = Vector2(56, 56)
				h.add_child(t)
		"dice":
			var h := HBoxContainer.new()
			h.alignment = BoxContainer.ALIGN_CENTER
			h.add_constant_override("separation", 10)
			v.add_child(h)
			for d in r.get("dice", []):
				h.add_child(_tile(str(int(d)), Color(0.95, 0.95, 0.97), Color(0.08, 0.08, 0.1)))
		"roulette":
			var c := Globals.s(r.get("colour", ""))
			var bg := Color("#c0392b") if c == "red" else (Color("#1e8449") if c == "green" else Color("#1c1c22"))
			var h := HBoxContainer.new()
			h.alignment = BoxContainer.ALIGN_CENTER
			v.add_child(h)
			h.add_child(_tile(str(int(r.get("number", 0))), bg, Color(1, 1, 1)))
		"coinflip":
			var l = S.label(Globals.s(r.get("side", "")).to_upper(), _f_big, GOLD)
			l.align = Label.ALIGN_CENTER
			v.add_child(l)
		"crash":
			var l = S.label("Crashed at %s" % _x(r.get("point", 1)), _f_big, WIN if bool(r.get("win", false)) else LOSE)
			l.align = Label.ALIGN_CENTER
			v.add_child(l)
		"baccarat":
			var tot = r.get("totals", [0, 0])
			v.add_child(_hand_row("Player (%d)" % int(tot[0]), r.get("player", [])))
			v.add_child(_hand_row("Banker (%d)" % int(tot[1]), r.get("banker", [])))
	var t = S.label(Globals.s(r.get("text", "")), S.f_regular, S.TEXT, true)
	v.add_child(t)
	v.add_child(S.label(_outcome(pay, stake), S.f_bold, col, true))

static func _outcome(pay: int, stake: int) -> String:
	if pay > stake:
		return "You won %s (%s more than your bet)." % [_chips_text(pay), _chips_text(pay - stake)]
	if pay == stake:
		return "Your %s are back." % _chips_text(stake)
	if pay > 0:
		return "You get %s back of your %s." % [_chips_text(pay), _fmt(stake)]
	return "You lost your %s." % _chips_text(stake)

# a square with a number or a card on it
func _tile(text: String, bg: Color, fg: Color, w: float = 56.0) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_stylebox_override("panel", OnlineStyle.flat(bg, 8, Color(1, 1, 1, 0.25), 1, 10, 8))
	p.rect_min_size = Vector2(w, w * 1.1)
	var l = S.label(text, _f_card, fg)
	l.align = Label.ALIGN_CENTER
	l.valign = Label.VALIGN_CENTER
	p.add_child(l)
	return p

func _card(c) -> Control:
	if not (c is Dictionary):
		return _tile("?", Color(0.25, 0.2, 0.35), Color(1, 1, 1), 48)
	return _tile("%s%s" % [Globals.s(c.get("r", "")), Globals.s(c.get("s", ""))], Color(0.97, 0.96, 0.94), RED_SUIT if bool(c.get("red", false)) else Color(0.08, 0.08, 0.1), 48)

func _hand_row(title: String, cards: Array, hidden: int = 0) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 6)
	var l = S.label(title, S.f_bold, S.TEXT)
	l.rect_min_size.x = 130
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(l)
	for c in cards:
		h.add_child(_card(c))
	for i in hidden:
		h.add_child(_card(null))
	return h

# a game with steps
func _draw_current():
	var c: Dictionary = _current if _current is Dictionary else {}
	if c.empty():
		_draw_hub()
		return
	var done := bool(c.get("done", false))
	_text(_game_name(Globals.s(c.get("game", ""))), S.ACCENT, S.f_head)
	_text("Bet: %s%s" % [_chips_text(c.get("stake", c.get("bet", 0))), "  (doubled)" if bool(c.get("doubled", false)) else ""], GOLD, S.f_bold)
	match Globals.s(c.get("kind", "")):
		"blackjack":
			_body.add_child(_hand_row("Dealer%s" % (("  (%d)" % int(c.dealer_total)) if c.get("dealer_total") != null else ""), c.get("dealer", []), 1 if bool(c.get("dealer_hidden", false)) else 0))
			_body.add_child(_hand_row("You  (%d)" % int(c.get("player_total", 0)), c.get("player", [])))
			if done:
				_text({"blackjack": "Blackjack!", "bust": "Over 21: bust.", "win": "You beat the dealer.", "push": "Same as the dealer.", "lose": "The dealer wins."}.get(Globals.s(c.get("result", "")), ""), S.TEXT, S.f_bold)
			else:
				var h := _row()
				_btn(h, "Hit", "_step", ["hit"], true)
				_btn(h, "Stand", "_step", ["stand"], true)
				_btn(h, "Double", "_step", ["double"], false, not bool(c.get("can_double", false)))
		"mines":
			var open: Array = c.get("open", [])
			var bombs: Array = c.get("bombs", [])
			_text("%d of the %d tiles %s. Prize now %s, next tile %s." % [int(c.get("mines", 3)), int(c.get("tiles", 20)), "is a mine" if int(c.get("mines", 3)) == 1 else "are mines", _x(c.get("mult", 1)), _x(c.get("next_mult", 1))], S.DIM)
			var grid := GridContainer.new()
			grid.columns = 5
			grid.add_constant_override("hseparation", 6)
			grid.add_constant_override("vseparation", 6)
			_body.add_child(grid)
			for t in int(c.get("tiles", 20)):
				var b := Button.new()
				var opened = open.has(float(t)) or open.has(t)
				var bomb = bombs.has(float(t)) or bombs.has(t)
				var hit = int(c.get("hit", -1)) == t
				b.text = "◆" if opened else ("✸" if bomb else "?")
				S.button(b, opened, true)
				if hit:
					b.add_stylebox_override("disabled", OnlineStyle.flat(LOSE, 4))
				elif opened:
					b.add_stylebox_override("disabled", OnlineStyle.flat(WIN.darkened(0.25), 4))
					b.add_color_override("font_color_disabled", Color(1, 1, 1))
				b.rect_min_size = Vector2(64, 52)
				b.disabled = done or opened
				b.focus_mode = Control.FOCUS_NONE
				b.add_font_override("font", _f_card)
				b.connect("pressed", self, "_step", ["p", t])
				grid.add_child(b)
			if not done:
				_btn(_row(), ("Cash out %s" % _chips_text(c.get("cash_value", 0))) if not open.empty() else "Cancel (bet back)", "_step", ["cash"], not open.empty())
			elif Globals.s(c.get("result", "")) == "boom":
				_text("A mine, after %d safe %s." % [open.size(), "tile" if open.size() == 1 else "tiles"], LOSE, S.f_bold)
		"hilo":
			var seen: Array = c.get("seen", [])
			if not seen.empty():
				_body.add_child(_hand_row("Before", seen))
			_body.add_child(_hand_row("Card", [c.get("card")]))
			_text("Right so far: %d  ·  prize %s" % [int(c.get("steps", 0)), _x(c.get("mult", 1))], S.DIM)
			if not done:
				_text("Is the next card higher or lower? (The same card loses.)", S.TEXT)
				var h := _row()
				_btn(h, ("Higher (%s)" % _x(c.hi_mult)) if float(c.get("hi_mult", 0)) > 0 else "Higher", "_step", ["hi"], true, float(c.get("hi_mult", 0)) <= 0)
				_btn(h, ("Lower (%s)" % _x(c.lo_mult)) if float(c.get("lo_mult", 0)) > 0 else "Lower", "_step", ["lo"], true, float(c.get("lo_mult", 0)) <= 0)
				_btn(h, ("Cash out %s" % _chips_text(c.get("cash_value", 0))) if int(c.get("steps", 0)) > 0 else "Cancel (bet back)", "_step", ["cash"])
			elif Globals.s(c.get("result", "")) == "wrong":
				_text("Wrong.", LOSE, S.f_bold)
		"poker":
			var hand: Array = c.get("hand", [])
			var held: Array = c.get("held", [])
			var h := _row(6)
			for k in hand.size():
				var col := VBoxContainer.new()
				col.add_constant_override("separation", 4)
				h.add_child(col)
				col.add_child(_card(hand[k]))
				if not done:
					var hb := Button.new()
					hb.text = "Held" if (k < held.size() and bool(held[k])) else "Hold"
					S.button(hb, k < held.size() and bool(held[k]), true)
					hb.focus_mode = Control.FOCUS_NONE
					hb.rect_min_size = Vector2(48, 36)
					hb.connect("pressed", self, "_step", ["h", k])
					col.add_child(hb)
			var made := Globals.s(c.get("made", ""))
			if done:
				_text(("%s: x%d." % [made, int(c.get("made_pays", 0))]) if made != "" else "Nothing: a pair of jacks or better is needed.", S.TEXT, S.f_bold)
			else:
				_text(("You have: %s. " % made if made != "" else "") + "Hold the cards you like, then Draw: the others are swapped once.", S.DIM)
				_btn(_row(), "Draw", "_step", ["draw"], true)
	if done:
		var pay := int(c.get("pay", 0))
		var stake := int(c.get("stake", 0))
		_text(_outcome(pay, stake), WIN if pay > stake else (S.DIM if pay == stake else LOSE), S.f_bold)
		var h := _row()
		_btn(h, "Play again (%s)" % _fmt(_state.get("bet", 0)), "_play", [Globals.s(c.get("game", "")), str(int(c.get("mines", 3))) if Globals.s(c.get("kind", "")) == "mines" else ""], true)
		_btn(h, "Change bet", "_pick", [Globals.s(c.get("game", ""))])
		_btn(h, "Games", "_go_hub")
	else:
		_back_row()

func _draw_top():
	var by := Globals.s(_board.get("by", "bal")) if _board is Dictionary else "bal"
	var h := _row()
	for k in [["bal", "Most chips"], ["best", "Biggest win"], ["won", "Most won"]]:
		_btn(h, k[1], "_top", [k[0]], k[0] == by)
	var rows: Array = _board.get("rows", []) if _board is Dictionary else []
	if rows.empty():
		_text("Nobody has played yet.", S.DIM)
	for r in rows:
		if not (r is Dictionary):
			continue
		var row = S.card(_body)
		var pl = S.label("#%d" % int(r.get("place", 0)), S.f_bold, GOLD if int(r.get("place", 0)) <= 3 else S.DIM)
		pl.rect_min_size.x = 44
		row.add_child(pl)
		var nm = S.label(Globals.s(r.get("name", "Player")) + ("  (you)" if bool(r.get("you", false)) else ""), S.f_bold, S.ACCENT if bool(r.get("you", false)) else S.TEXT)
		nm.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(nm)
		row.add_child(S.label(_chips_text(r.get("value", 0)), S.f_bold, GOLD))
	_back_row()

func _draw_give():
	_text("Give chips", S.ACCENT, S.f_head)
	_text("You have %s. Chips go from your table to theirs (their linked Discord account's). You need %d games played; up to 100,000 a day, and after giving, the broke top-up waits a day." % [_chips_text(_state.get("bal", 0)), int(_state.get("gift_games", 10))], S.DIM)
	var h := _row()
	var who := LineEdit.new()
	who.placeholder_text = "Their player number"
	who.rect_min_size = Vector2(180, 40)
	S.field(who)
	h.add_child(who)
	var amt := LineEdit.new()
	amt.placeholder_text = "How many (or all)"
	amt.rect_min_size = Vector2(160, 40)
	S.field(amt)
	h.add_child(amt)
	_btn(h, "Give", "_give", [who, amt], true)
	_text("A player's number is on their profile and in the Spectate list.", S.DIM)
	_back_row()

func _draw_help():
	_text("How the casino works", S.ACCENT, S.f_head)
	_text(_help, S.TEXT)
	_back_row()

# --- buttons ----------------------------------------------------------------------------

func _go_hub():
	_page = "hub"
	_result = null
	_send("state")
	_render()

func _resume():
	_current = _state.get("current")
	_game = Globals.s(_current.get("game", "")) if _current is Dictionary else ""
	_page = "current"
	_render()

func _pick(game: String):
	_game = game
	_page = "table"
	_result = null
	_render()

func _daily():
	_send("daily")

func _top(by: String):
	_send("top", {"by": by})

func _go_give():
	_page = "give"
	_render()

func _help_page():
	_send("help")

func _bet(what: String):
	_send("bet", {"bet": what})

func _bet_typed(_t = ""):
	if _bet_box != null and is_instance_valid(_bet_box) and _bet_box.text.strip_edges() != "":
		_send("bet", {"bet": _bet_box.text.strip_edges().substr(0, 16)})

func _play(game: String, choice: String):
	_game = game
	_send("play", {"game": game, "choice": choice})

func _number_entered(_t, box: LineEdit):
	_play_number(box)

func _play_number(box: LineEdit):
	var t := box.text.strip_edges()
	if not t.is_valid_integer() or int(t) < 0 or int(t) > 36:
		_error = "A roulette number goes from 0 to 36."
		_render()
		return
	_play("roulette", "n" + t)

func _play_crash(box: LineEdit):
	_play("crash", box.text.strip_edges().replace(",", ".").substr(0, 16))

func _step(action: String, arg = null):
	var m := {"action": action}
	if arg != null:
		m["arg"] = int(arg)
	_send("step", m)

func _give(who: LineEdit, amt: LineEdit):
	var n := who.text.strip_edges().replace("#", "")
	if not n.is_valid_integer():
		_error = "Type their player number (it's on their profile)."
		_render()
		return
	_send("give", {"to": int(n), "amount": amt.text.strip_edges().substr(0, 16)})

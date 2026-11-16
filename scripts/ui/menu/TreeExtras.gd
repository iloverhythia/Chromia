extends Control

# More to do in the Chromia Upgrade Tree (its "More" button). None of it is a
# minigame; all of it feeds the tree and is kept for good (prestige takes
# none of it). Kept in the tree's save (upgrade_tree.json, "extras").
#
# - Milestones: goals in twelve tracks (coins, upgrades, clicks, combos,
#   features, layers, prestiges, time, research, challenges, notes hit in
#   real maps, daily streak). Each one reached gives its track's bonus, a
#   little coin gain that grows with your coins, and an Insight.
# - Insight: a second currency. A prestige of layer k gives k, a milestone 1,
#   a challenge tier 2, a new day 1, every third map passed 1.
# - Research: nine lines paid for with Insight. A level takes real time (20 s
#   at first, longer every level, 8 hours at most), also while the game is
#   closed. One at a time.
# - Challenges: start a run over with a rule against you and reach its goal.
#   Six of them, ten tiers each, every tier a bonus for good.
# - Stage: playing maps counts. Notes you hit since the tree was last open
#   become chrome coins, maps passed become an Encore (more coins for a few
#   minutes of tree time), and all your notes together a Stage level.
# - Daily streak: a little more coin gain for each day in a row, up to 30.
#
# Bonuses come in two kinds: digits (x10 per digit, what counts early) and
# percent of your digits (1e100 at +1% is 1e101: what still counts late).
# The logic is static and takes the tree (works without this panel being
# made); ChromiaUpgradeTree calls apply() from _recalc, tick() twice a
# second, on_open() and on_prestige().

const PINK = Color(1, 0.756863, 0.960784)
const LILAC = Color(0.764706, 0.65098, 0.8)
const GOLD = Color(1.0, 0.82, 0.35)
const GOOD = Color(0.6, 1.0, 0.7)
const DIMC = Color(1, 1, 1, 0.5)

# id, name, what is counted, the goals, what each gives, how much
const MS = [
	["coins", "Fortune", "digits of all the chrome coins you ever made", [6, 12, 25, 50, 100, 200, 400, 800, 1600, 3200, 6400, 12800], "rate", 0.25],
	["bought", "Collector", "upgrades bought", [10, 50, 250, 1000, 5000, 25000, 100000, 500000, 2500000], "cheap", 0.03],
	["clicks", "Clicker", "clicks", [100, 1000, 10000, 100000, 1000000, 10000000], "click", 0.4],
	["combo", "Combo", "best click combo", [10, 25, 50, 75, 100], "click", 0.3],
	["feats", "Explorer", "features found", [5, 25, 100, 500, 2500, 10000, 40000, 100000, 165000], "rate", 0.3],
	["layer", "Climber", "highest prestige layer reached", [1, 2, 3, 5, 8, 12, 20, 35, 50, 75, 100], "gains", 0.15],
	["prest", "Reborn", "prestiges", [1, 10, 50, 250, 1000, 5000, 25000], "gains", 0.1],
	["time", "Regular", "hours in the tree", [0.25, 1, 5, 24, 100, 500], "offline", 0.05],
	["res", "Scholar", "research levels", [1, 5, 15, 40, 100, 250], "res_speed", 0.05],
	["chal", "Daredevil", "challenge tiers", [1, 5, 10, 20, 30, 45, 60], "rate", 0.5],
	["notes", "Performer", "notes hit in maps", [1000, 10000, 50000, 250000, 1000000, 5000000], "rate", 0.3],
	["streak", "Devoted", "best daily streak", [2, 7, 14, 30, 100], "rate", 0.3],
]
const MS_PCT := 0.001 # every milestone: +0.1% of your coin gain's digits

# id, name, what it does, kind, per level, most levels
const RES = [
	["coin", "Coin Theory", "chrome coin gain", "rate_pct", 0.004, 50],
	["click", "Click Mechanics", "click value", "click_pct", 0.006, 50],
	["bulk", "Bulk Discounts", "upgrade prices", "cheap", 0.02, 25],
	["layer", "Layer Studies", "what every prestige layer gives", "gains", 0.12, 50],
	["auto", "Automation", "auto-clicks a second", "autoclick", 1.0, 30],
	["idle", "Night Shift", "offline earnings", "offline", 0.04, 25],
	["luck", "Fortune", "critical click chance", "crit", 0.01, 20],
	["speed", "Speed Reading", "research speed", "res_speed", 0.08, 25],
	["encore", "Stagecraft", "Encore strength", "encore", 0.1, 20],
]
const RES_BASE_S := 20.0
const RES_GROW := 1.45
const RES_MAX_S := 8.0 * 3600.0

# id, name, the rule, kind of reward, per tier
const CH = [
	["nohands", "No Hands", "Clicks and auto-clicks give nothing.", "click_pct", 0.02],
	["inflation", "Inflation", "Every price has a quarter more digits.", "cheap", 0.04],
	["blackout", "Blackout", "Your features do nothing.", "rate_pct", 0.01],
	["solo", "Solo", "Prestige points and perks do nothing for your coins.", "gains", 0.3],
	["manual", "Manual", "No auto-buying, no auto-clicks, no offline earnings.", "autoclick", 3.0],
	["slow", "Slow Burn", "Coins and clicks are worth a thousand times less.", "rate", 0.5],
]
# digits of chrome coins to earn in the run, per tier
const CH_GOALS = [6, 10, 15, 22, 30, 40, 55, 75, 100, 140]

const ENCORE_PER_PASS := 240.0 # seconds of tree time
const ENCORE_MAX := 3.0 * 3600.0
const NOTE_SECONDS := 0.25 # a note hit in a map: this many seconds of your coin rate
const STREAK_CAP := 30

# --- state --------------------------------------------------------------------

static func state(tr) -> Dictionary:
	var x: Dictionary = tr._extra
	for k in ["ms", "res", "ch", "stage", "streak"]:
		if not (x.get(k) is Dictionary):
			x[k] = {}
	if not (x.get("ins") is float or x.get("ins") is int):
		x["ins"] = 0.0
	if not (x.get("ch_on") is String):
		x["ch_on"] = ""
	if not (x.get("encore") is float or x.get("encore") is int):
		x["encore"] = 0.0
	return x

static func _i(d: Dictionary, k: String) -> int:
	var v = d.get(k, 0)
	return int(v) if (v is float or v is int) else 0

static func ms_count(tr, id: String) -> int:
	return _i(state(tr).ms, id)

static func total_ms(tr) -> int:
	var n := 0
	for m in MS:
		n += ms_count(tr, m[0])
	return n

static func res_level(tr, id: String) -> int:
	return _i(state(tr).res, id)

static func total_res(tr) -> int:
	var n := 0
	for r in RES:
		n += res_level(tr, r[0])
	return n

static func ch_tiers(tr, id: String) -> int:
	return _i(state(tr).ch, id)

static func total_ch(tr) -> int:
	var n := 0
	for c in CH:
		n += ch_tiers(tr, c[0])
	return n

# the challenge being run ("" for none)
static func rule(tr) -> String:
	var r = tr._extra.get("ch_on", "")
	return r if r is String else ""

static func prestiges(tr) -> int:
	var n := 0
	for L in tr.layers:
		n += _i(L, "n")
	return n

static func notes_total() -> int:
	var st: Dictionary = Rhythia.get_lifetime_stats()
	return int(st.get("notes_hit", 0))

static func stage_level() -> int:
	return int(floor(log(1.0 + notes_total() / 2000.0) / log(2.0)))

# what a milestone track counts, right now
static func source(tr, id: String) -> float:
	match id:
		"coins": return max(float(tr.total_l), 0.0)
		"bought": return float(tr.stats.bought)
		"clicks": return float(tr.stats.clicks)
		"combo": return float(tr.stats.best_combo)
		"feats": return float(tr._found_count)
		"layer": return float(tr._highest_reached())
		"prest": return float(prestiges(tr))
		"time": return float(tr.stats.time) / 3600.0
		"res": return float(total_res(tr))
		"chal": return float(total_ch(tr))
		"notes": return float(notes_total())
		"streak": return float(_i(state(tr).streak, "best"))
	return 0.0

# --- the bonuses ------------------------------------------------------------------

static func _add(b: Dictionary, kind: String, v: float, n: int):
	if n <= 0:
		return
	if kind == "cheap":
		b.cheap *= pow(1.0 - v, n)
	else:
		b[kind] += v * n

# everything added up: {rate, rate_pct, click, click_pct, cheap (a factor), gains, autoclick, offline, crit, res_speed, encore}
static func bonuses(tr) -> Dictionary:
	var x := state(tr)
	var b := {rate = 0.0, rate_pct = 0.0, click = 0.0, click_pct = 0.0, cheap = 1.0, gains = 0.0, autoclick = 0.0, offline = 0.0, crit = 0.0, res_speed = 0.0, encore = 0.0}
	for m in MS:
		_add(b, m[4], m[5], ms_count(tr, m[0]))
	b.rate_pct += MS_PCT * total_ms(tr)
	for r in RES:
		_add(b, r[3], r[4], res_level(tr, r[0]))
	for c in CH:
		_add(b, c[3], c[4], ch_tiers(tr, c[0]))
	b.rate += 0.05 * min(_i(x.streak, "n"), STREAK_CAP)
	b.rate_pct += 0.002 * stage_level()
	if encore_left(tr) > 0.0:
		b.rate += 0.5 * (1.0 + b.encore)
	b.cheap = max(b.cheap, 0.2)
	b.crit = min(b.crit, 0.25)
	return b

static func encore_left(tr) -> float:
	return max(0.0, float(state(tr).encore) - float(tr.stats.time))

# The end of the tree's _recalc: the bonuses go on its numbers, then the rule
# of a challenge being run.
static func apply(tr):
	var b := bonuses(tr)
	tr._xb = b
	tr._rate_l += b.rate + b.rate_pct * max(tr._rate_l, 0.0)
	tr._pet_l += b.rate + b.click + (b.rate_pct + b.click_pct) * max(tr._pet_l, 0.0)
	tr._cheap_l += tr.lg(b.cheap)
	for k in range(tr._gain_mult_l.size()):
		tr._gain_mult_l[k] += b.gains
	tr._autoclicks += b.autoclick
	tr._offline += b.offline
	tr._crit_chance = min(tr._crit_chance + b.crit, 0.9)
	tr._x_cost_pow = 1.0
	match rule(tr):
		"nohands":
			tr._pet_l = tr.LZERO
			tr._autoclicks = 0.0
		"inflation":
			tr._x_cost_pow = 1.25
		"manual":
			tr._autoclicks = 0.0
			tr._auto_every = 0.0
			tr._offline = 0.0
		"slow":
			tr._rate_l -= 3.0
			tr._pet_l -= 3.0

# --- things that happen ---------------------------------------------------------------

static func _gain_insight(tr, n: float):
	var x := state(tr)
	x.ins = float(x.ins) + n

# Twice a second: milestones reached, research finished, a challenge won.
# -> a line to show (or "")
static func tick(tr) -> String:
	var x := state(tr)
	var note := ""
	for m in MS:
		var have: int = ms_count(tr, m[0])
		var goals: Array = m[3]
		var v: float = source(tr, m[0])
		var n := have
		while n < goals.size() and v >= float(goals[n]):
			n += 1
		if n > have:
			x.ms[m[0]] = n
			_gain_insight(tr, n - have)
			note = "Milestone: %s %s (%s). +%d Insight." % [m[1], _roman(n), m[2], n - have]
	var run = x.get("run")
	if run is Dictionary and run.has("id") and OS.get_unix_time() >= int(run.get("end", 0)):
		var id := String(run.id)
		x.res[id] = res_level(tr, id) + 1
		x.erase("run")
		note = "Research finished: %s is level %d." % [_res_name(id), res_level(tr, id)]
	var r := rule(tr)
	if r != "":
		var t: int = ch_tiers(tr, r)
		if t >= CH_GOALS.size():
			x.ch_on = ""
		elif float(tr.run_l) >= float(CH_GOALS[t]):
			x.ch[r] = t + 1
			x.ch_on = ""
			_gain_insight(tr, 2.0)
			note = "Challenge won: %s, tier %d. +2 Insight. Its rule is off again." % [_ch_name(r), t + 1]
	return note

static func on_prestige(tr, k: int):
	_gain_insight(tr, float(k))
	# (a challenge is one run: resetting ends it)
	if rule(tr) != "":
		state(tr).ch_on = ""

# The tree is opened: a new day, and what you played since last time.
static func on_open(tr) -> String:
	var x := state(tr)
	var notes := PoolStringArray()
	var today := int(OS.get_unix_time() / 86400)
	var last: int = _i(x.streak, "day")
	if last != today:
		var n: int = _i(x.streak, "n") + 1 if last == today - 1 else 1
		x.streak = {"day": today, "n": n, "best": int(max(n, _i(x.streak, "best")))}
		var got := 1.0 + (1.0 if n % 7 == 0 else 0.0)
		_gain_insight(tr, got)
		if n > 1:
			notes.append("Day %d in a row: +%s%% coin gain, +%d Insight." % [n, str(int(round((pow(10.0, 0.05 * min(n, STREAK_CAP)) - 1.0) * 100.0))), int(got)])
	var st: Dictionary = Rhythia.get_lifetime_stats()
	var hit := int(st.get("notes_hit", 0))
	var passes := int(st.get("passes", 0))
	if x.stage.has("notes"):
		var dn := int(clamp(hit - _i(x.stage, "notes"), 0, 200000))
		var dp := int(clamp(passes - _i(x.stage, "passes"), 0, 200))
		if dn > 0:
			var g: float = max(tr._rate_l, 0.0) + tr.lg(dn * NOTE_SECONDS)
			tr._earn(g)
			var line := "You hit %d notes in maps since last time: +%s chrome coins." % [dn, tr.fmtl(g)]
			if dp > 0:
				x.encore = min(max(float(x.encore), float(tr.stats.time)) + dp * ENCORE_PER_PASS, float(tr.stats.time) + ENCORE_MAX)
				x.stage["third"] = _i(x.stage, "third") + dp
				var ins := int(_i(x.stage, "third") / 3)
				x.stage["third"] = _i(x.stage, "third") % 3
				_gain_insight(tr, float(ins))
				line += " %d map%s passed: Encore for %s%s." % [dp, "" if dp == 1 else "s", _dur(encore_left(tr)), (", +%d Insight" % ins) if ins > 0 else ""]
			notes.append(line)
	x.stage["notes"] = hit
	x.stage["passes"] = passes
	return notes.join("\n")

static func res_time(tr, id: String) -> float:
	var lv: int = res_level(tr, id)
	var speed: float = 1.0 + float(tr._xb.get("res_speed", 0.0)) if tr._xb is Dictionary else 1.0
	return min(RES_BASE_S * pow(RES_GROW, lv), RES_MAX_S) / speed

static func res_cost(tr, id: String) -> float:
	return float(res_level(tr, id) + 1)

static func start_research(tr, id: String) -> bool:
	var x := state(tr)
	var def = _res_def(id)
	if def == null or x.get("run") is Dictionary or res_level(tr, id) >= int(def[5]):
		return false
	var cost := res_cost(tr, id)
	if float(x.ins) + 1e-9 < cost:
		return false
	x.ins = float(x.ins) - cost
	var dur := res_time(tr, id)
	x["run"] = {"id": id, "end": OS.get_unix_time() + int(ceil(dur)), "dur": dur}
	return true

# a run over with the rule on (the tree and your coins start again; layers, points and features stay)
static func start_challenge(tr, id: String) -> bool:
	if _ch_def(id) == null or ch_tiers(tr, id) >= CH_GOALS.size():
		return false
	state(tr).ch_on = id
	tr.stats.run_clicks = 0
	tr._recalc()
	tr._new_tree()
	tr.coins_l = tr._start_l
	tr.run_l = tr.LZERO
	tr._recalc()
	tr._rebuild_buttons()
	tr._recenter()
	tr._refresh_ui()
	tr._save()
	return true

static func stop_challenge(tr):
	state(tr).ch_on = ""
	tr._recalc()
	tr._refresh_ui()

static func _res_def(id: String):
	for r in RES:
		if r[0] == id:
			return r
	return null

static func _ch_def(id: String):
	for c in CH:
		if c[0] == id:
			return c
	return null

static func _res_name(id: String) -> String:
	var d = _res_def(id)
	return String(d[1]) if d != null else id

static func _ch_name(id: String) -> String:
	var d = _ch_def(id)
	return String(d[1]) if d != null else id

static func _roman(n: int) -> String:
	var r := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV"]
	return r[n] if n >= 0 and n < r.size() else str(n)

static func _dur(s: float) -> String:
	var t := int(ceil(s))
	if t < 60:
		return "%d s" % t
	if t < 3600:
		return "%d min %02d s" % [int(t / 60), t % 60]
	return "%d h %02d min" % [int(t / 3600), int(t % 3600 / 60)]

static func _num(v: float) -> String:
	if v >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if v >= 10000.0:
		return "%dK" % int(v / 1000.0)
	if v == floor(v):
		return str(int(v))
	return "%.2f" % v

# what a bonus of a kind reads as
static func reward_text(kind: String, v: float) -> String:
	match kind:
		"rate": return "coin gain x%s" % _x(v)
		"click": return "click value x%s" % _x(v)
		"rate_pct": return "+%s%% of your coin gain's digits" % _pct(v)
		"click_pct": return "+%s%% of your click value's digits" % _pct(v)
		"cheap": return "prices -%s%%" % _pct(v)
		"gains": return "every layer gives x%s" % _x(v)
		"autoclick": return "+%s auto-clicks a second" % _num(v)
		"offline": return "+%s%% offline earnings" % _pct(v)
		"crit": return "+%s%% critical clicks" % _pct(v)
		"res_speed": return "research %s%% faster" % _pct(v)
		"encore": return "Encore %s%% stronger" % _pct(v)
	return ""

static func _x(digits: float) -> String:
	if digits < 3.0:
		return "%.2f" % pow(10.0, digits)
	if digits < 6.0:
		return "%dK" % int(round(pow(10.0, digits - 3.0))) if digits >= 4.0 else "%.1fK" % pow(10.0, digits - 3.0)
	var e := floor(digits)
	return "%.2fe%d" % [pow(10.0, digits - e), int(e)]

static func _cap(t: String) -> String:
	return t.substr(0, 1).to_upper() + t.substr(1)

static func _n(count: int, one: String, many: String) -> String:
	return "%d %s" % [count, one if count == 1 else many]

static func _pct(frac: float) -> String:
	var p := frac * 100.0
	return str(int(round(p))) if abs(p - round(p)) < 0.001 else ("%.1f" % p)

# ===================================================================================
# The panel
# ===================================================================================

var tr # ChromiaUpgradeTree
var _tab := "ms"
var _tabs := {}
var _box: VBoxContainer
var _head: Label
var _live := [] # [Label or ProgressBar, what, id]: what changes without a rebuild
var _t := 0.0
var _sig := ""

func _ready():
	anchor_right = 1.0
	anchor_bottom = 1.0
	margin_top = 69
	mouse_filter = MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.015, 0.03, 0.985)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)
	var v := VBoxContainer.new()
	v.anchor_left = 0.5
	v.anchor_right = 0.5
	v.anchor_bottom = 1.0
	v.margin_left = -500
	v.margin_right = 500
	v.margin_top = 14
	v.margin_bottom = -14
	v.add_constant_override("separation", 10)
	add_child(v)
	var top := HBoxContainer.new()
	top.add_constant_override("separation", 8)
	v.add_child(top)
	for t in [["ms", "Milestones"], ["res", "Research"], ["ch", "Challenges"], ["stage", "Stage & streak"], ["stats", "Statistics"]]:
		var b := _btn(t[1], "_show", [t[0]])
		b.toggle_mode = true
		b.rect_min_size = Vector2(136, 34)
		top.add_child(b)
		_tabs[t[0]] = b
	var sp := Control.new()
	sp.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(sp)
	var back := _btn("Back to the tree", "close")
	back.rect_min_size = Vector2(160, 34)
	top.add_child(back)
	_head = _lbl("", 15, LILAC, true)
	v.add_child(_head)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = SIZE_EXPAND_FILL
	sc.scroll_horizontal_enabled = false
	v.add_child(sc)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = SIZE_EXPAND_FILL
	_box.add_constant_override("separation", 6)
	sc.add_child(_box)
	_show(_tab)

func close():
	visible = false

func _btn(text: String, method: String, binds: Array = []) -> Button:
	var b := Button.new()
	b.text = text
	b.theme = preload("res://uitheme.tres")
	b.focus_mode = FOCUS_NONE
	b.rect_min_size = Vector2(0, 34)
	b.connect("pressed", self, method, binds)
	return b

func _lbl(text: String, size: int, col: Color, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap = wrap
	l.add_font_override("font", tr._font(size))
	l.add_color_override("font_color", col)
	if wrap:
		l.size_flags_horizontal = SIZE_EXPAND_FILL
	return l

# a row: a panel with a column for text on the left and room for a button on the right
func _row() -> Array:
	var p := PanelContainer.new()
	var sb: StyleBoxFlat = tr._sb(Color(1, 1, 1, 0.045), Color(1, 1, 1, 0.1), 1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 9
	sb.content_margin_bottom = 9
	p.add_stylebox_override("panel", sb)
	_box.add_child(p)
	var h := HBoxContainer.new()
	h.add_constant_override("separation", 14)
	p.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_constant_override("separation", 3)
	h.add_child(v)
	return [v, h]

func _bar(part: float) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0001
	b.value = clamp(part, 0.0, 1.0)
	b.percent_visible = false
	b.rect_min_size = Vector2(0, 8)
	b.add_stylebox_override("bg", tr._sb(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 0))
	b.add_stylebox_override("fg", tr._sb(LILAC, Color(0, 0, 0, 0), 0))
	return b

func _show(tab: String):
	_tab = tab
	for k in _tabs:
		_tabs[k].pressed = k == tab
	_rebuild()

func _rebuild():
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	_live = []
	match _tab:
		"ms": _build_ms()
		"res": _build_res()
		"ch": _build_ch()
		"stage": _build_stage()
		"stats": _build_stats()
	_sig = _signature()
	_refresh()

# what a rebuild depends on (a change of it: the rows are made again)
func _signature() -> String:
	var x := state(tr)
	return "%s|%d|%d|%d|%s|%s|%d" % [_tab, total_ms(tr), total_res(tr), total_ch(tr), rule(tr), str(x.get("run") is Dictionary), int(float(x.ins))]

func _process(delta: float):
	if not visible:
		return
	_t += delta
	if _t >= 0.5:
		_t = 0.0
		if _signature() != _sig:
			_rebuild()
		else:
			_refresh()

func _head_text() -> String:
	var b: Dictionary = tr._xb if tr._xb is Dictionary and not tr._xb.empty() else bonuses(tr)
	var parts := PoolStringArray()
	parts.append("Insight: %s" % _num(floor(float(state(tr).ins))))
	parts.append(_n(total_ms(tr), "milestone", "milestones"))
	parts.append(_n(total_res(tr), "research level", "research levels"))
	parts.append(_n(total_ch(tr), "challenge tier", "challenge tiers"))
	var all := PoolStringArray()
	if b.rate > 0.0:
		all.append("coin gain x%s" % _x(b.rate))
	if b.rate_pct > 0.0:
		all.append("+%s%% of its digits" % _pct(b.rate_pct))
	if b.cheap < 1.0:
		all.append("prices -%s%%" % _pct(1.0 - b.cheap))
	if b.gains > 0.0:
		all.append("layers x%s" % _x(b.gains))
	return parts.join("    ") + ("\nAll of it together: " + all.join(", ") + "." if all.size() > 0 else "")

func _refresh():
	_head.text = _head_text()
	for e in _live:
		var n = e[0]
		if not is_instance_valid(n):
			continue
		match e[1]:
			"ms_bar":
				n.value = _ms_part(e[2])
			"ms_text":
				n.text = _ms_progress(e[2])
			"run_bar":
				n.value = _run_part()
			"run_text":
				n.text = _run_text()
			"ch_bar":
				n.value = _ch_part(e[2])
			"ch_text":
				n.text = _ch_progress(e[2])
			"encore":
				n.text = _encore_text()

# --- milestones ---
func _ms_def(id: String):
	for m in MS:
		if m[0] == id:
			return m
	return null

func _ms_part(id: String) -> float:
	var m = _ms_def(id)
	var n: int = ms_count(tr, id)
	if n >= m[3].size():
		return 1.0
	var lo: float = float(m[3][n - 1]) if n > 0 else 0.0
	return (source(tr, id) - lo) / max(float(m[3][n]) - lo, 0.000001)

func _ms_progress(id: String) -> String:
	var m = _ms_def(id)
	var n: int = ms_count(tr, id)
	if n >= m[3].size():
		return "All %d reached." % n
	return "%s / %s %s" % [_num(source(tr, id)), _num(float(m[3][n])), m[2]]

func _build_ms():
	for m in MS:
		var n: int = ms_count(tr, m[0])
		var r := _row()
		var head := HBoxContainer.new()
		r[0].add_child(head)
		var name_l := _lbl("%s %s" % [m[1], _roman(n)] if n > 0 else m[1], 17, PINK)
		name_l.size_flags_horizontal = SIZE_EXPAND_FILL
		head.add_child(name_l)
		head.add_child(_lbl("%d / %d" % [n, m[3].size()], 14, GOOD if n >= m[3].size() else DIMC))
		var pt := _lbl("", 13, Color(1, 1, 1, 0.8))
		r[0].add_child(pt)
		_live.append([pt, "ms_text", m[0]])
		var bar := _bar(0.0)
		r[0].add_child(bar)
		_live.append([bar, "ms_bar", m[0]])
		var now := "So far: %s. " % reward_text(m[4], (1.0 - pow(1.0 - m[5], n)) if m[4] == "cheap" else m[5] * n) if n > 0 else ""
		r[0].add_child(_lbl("%sEach one: %s, +0.1%% of your coin gain's digits, +1 Insight." % [now, reward_text(m[4], m[5])], 13, LILAC, true))

# --- research ---
func _run_part() -> float:
	var run = state(tr).get("run")
	if not (run is Dictionary):
		return 0.0
	var dur: float = max(float(run.get("dur", 1.0)), 1.0)
	return 1.0 - (float(int(run.get("end", 0)) - OS.get_unix_time()) / dur)

func _run_text() -> String:
	var run = state(tr).get("run")
	if not (run is Dictionary):
		return ""
	return "Researching: %s left" % _dur(max(0.0, float(int(run.get("end", 0)) - OS.get_unix_time())))

func _build_res():
	var x := state(tr)
	var run = x.get("run")
	var busy := run is Dictionary
	for d in RES:
		var id: String = d[0]
		var lv: int = res_level(tr, id)
		var maxed: bool = lv >= int(d[5])
		var r := _row()
		var head := HBoxContainer.new()
		r[0].add_child(head)
		var name_l := _lbl(d[1], 17, PINK)
		name_l.size_flags_horizontal = SIZE_EXPAND_FILL
		head.add_child(name_l)
		head.add_child(_lbl("level %d / %d" % [lv, d[5]], 14, GOOD if maxed else DIMC))
		var now := (1.0 - pow(1.0 - d[4], lv)) if d[3] == "cheap" else d[4] * lv
		r[0].add_child(_lbl("%s. Now: %s. Each level: %s." % [_cap(String(d[2])), reward_text(d[3], now) if lv > 0 else "nothing yet", reward_text(d[3], d[4])], 13, LILAC, true))
		if busy and String(run.get("id", "")) == id:
			var rt := _lbl("", 13, GOLD)
			r[0].add_child(rt)
			_live.append([rt, "run_text", id])
			var bar := _bar(0.0)
			r[0].add_child(bar)
			_live.append([bar, "run_bar", id])
		elif not maxed:
			var b := _btn("Research (%s Insight, %s)" % [_num(res_cost(tr, id)), _dur(res_time(tr, id))], "_on_research", [id])
			b.disabled = busy or float(x.ins) + 1e-9 < res_cost(tr, id)
			b.size_flags_vertical = SIZE_SHRINK_CENTER
			b.rect_min_size = Vector2(250, 34)
			b.hint_tooltip = "One research at a time. It goes on while the game is closed." if not busy else "Something is being researched already."
			r[1].add_child(b)

func _on_research(id: String):
	if start_research(tr, id):
		tr._recalc()
		tr._save()
	_rebuild()

# --- challenges ---
func _ch_part(id: String) -> float:
	var t: int = ch_tiers(tr, id)
	if rule(tr) != id or t >= CH_GOALS.size():
		return 0.0
	return max(float(tr.run_l), 0.0) / float(CH_GOALS[t])

func _ch_progress(id: String) -> String:
	var t: int = ch_tiers(tr, id)
	if t >= CH_GOALS.size():
		return "All %d tiers won." % t
	var goal := "1e%d chrome coins earned in the run" % int(CH_GOALS[t])
	if rule(tr) == id:
		return "Running. %s / %s" % [tr.fmtl(tr.run_l), goal]
	return "Tier %d: %s." % [t + 1, goal]

func _build_ch():
	_box.add_child(_lbl("Starting one starts the tree and your coins over (layers, points and features stay) with its rule on, until you have earned the goal in that run. A prestige or \"Give up\" ends it without the reward.", 13, DIMC, true))
	var on := rule(tr)
	for d in CH:
		var id: String = d[0]
		var t: int = ch_tiers(tr, id)
		var r := _row()
		var head := HBoxContainer.new()
		r[0].add_child(head)
		var name_l := _lbl(d[1], 17, GOLD if on == id else PINK)
		name_l.size_flags_horizontal = SIZE_EXPAND_FILL
		head.add_child(name_l)
		head.add_child(_lbl("tier %d / %d" % [t, CH_GOALS.size()], 14, GOOD if t >= CH_GOALS.size() else DIMC))
		r[0].add_child(_lbl(d[2], 13, Color(1, 1, 1, 0.85), true))
		var pt := _lbl("", 13, LILAC)
		r[0].add_child(pt)
		_live.append([pt, "ch_text", id])
		if on == id:
			var bar := _bar(0.0)
			r[0].add_child(bar)
			_live.append([bar, "ch_bar", id])
		var now := (1.0 - pow(1.0 - d[4], t)) if d[3] == "cheap" else d[4] * t
		r[0].add_child(_lbl("%sEach tier: %s, +2 Insight." % ["So far: %s. " % reward_text(d[3], now) if t > 0 else "", reward_text(d[3], d[4])], 13, LILAC, true))
		if on == id:
			var g := _btn("Give up", "_on_give_up")
			g.size_flags_vertical = SIZE_SHRINK_CENTER
			g.rect_min_size = Vector2(120, 34)
			r[1].add_child(g)
		elif t < CH_GOALS.size():
			var b := _btn("Start", "_on_challenge", [id])
			b.disabled = on != ""
			b.size_flags_vertical = SIZE_SHRINK_CENTER
			b.rect_min_size = Vector2(120, 34)
			b.hint_tooltip = "Starts the tree and your coins over with this rule on" if on == "" else "Another challenge is running."
			r[1].add_child(b)

var _confirm := ""
var _confirm_at := 0
func _on_challenge(id: String):
	# (it resets the run: asked twice)
	var now := OS.get_ticks_msec()
	if _confirm != id or now - _confirm_at > 4000:
		_confirm = id
		_confirm_at = now
		_head.text = "Press Start again to begin \"%s\": the tree and your chrome coins start over." % _ch_name(id)
		return
	_confirm = ""
	if start_challenge(tr, id):
		visible = false # (back to the tree, where the run is)
		tr._info_label.text = "Challenge started: %s. %s Goal: 1e%d chrome coins earned in this run." % [_ch_name(id), _ch_def(id)[2], int(CH_GOALS[ch_tiers(tr, id)])]
	_rebuild()

func _on_give_up():
	stop_challenge(tr)
	_rebuild()

# --- stage and streak ---
func _encore_text() -> String:
	var left := encore_left(tr)
	if left <= 0.0:
		return "No Encore right now. Pass a map, then come back: every pass is %s of it." % _dur(ENCORE_PER_PASS)
	var b: Dictionary = bonuses(tr)
	return "Encore: coin gain x%s for another %s of time in the tree." % [_x(0.5 * (1.0 + b.encore)), _dur(left)]

func _build_stage():
	var x := state(tr)
	var st: Dictionary = Rhythia.get_lifetime_stats()
	var r := _row()
	r[0].add_child(_lbl("Stage", 17, PINK))
	r[0].add_child(_lbl("Playing maps feeds the tree. When you open the tree, every note you hit in a map since last time is worth %s seconds of your coin rate, every map you passed adds %s of Encore (up to %s), and every third pass an Insight." % [str(NOTE_SECONDS), _dur(ENCORE_PER_PASS), _dur(ENCORE_MAX)], 13, LILAC, true))
	var lv := stage_level()
	var next := 2000.0 * (pow(2.0, lv + 1) - 1.0)
	r[0].add_child(_lbl("Stage level %d (%s notes hit in all; level %d at %s): +%s%% of your coin gain's digits." % [lv, _num(float(st.get("notes_hit", 0))), lv + 1, _num(next), _pct(0.002 * lv)], 13, Color(1, 1, 1, 0.85), true))
	var e := _lbl("", 13, GOLD, true)
	r[0].add_child(e)
	_live.append([e, "encore", ""])
	var r2 := _row()
	r2[0].add_child(_lbl("Daily streak", 17, PINK))
	var n: int = _i(x.streak, "n")
	r2[0].add_child(_lbl("Open the tree every day: each day in a row is 12%% more coin gain (x%s now, after %d day%s; it stops growing at %d days) and an Insight, two on every seventh day. Missing a day starts it at 1 again. Best: %d days." % [_x(0.05 * min(n, STREAK_CAP)), n, "" if n == 1 else "s", STREAK_CAP, _i(x.streak, "best")], 13, LILAC, true))

# --- statistics ---
func _build_stats():
	var s: Dictionary = tr.stats
	var st: Dictionary = Rhythia.get_lifetime_stats()
	var lines := [
		["Chrome coins made in all", tr.fmtl(tr.total_l)],
		["Chrome coins made this run", tr.fmtl(tr.run_l)],
		["Upgrades bought", _num(float(s.bought))],
		["Upgrades bought for you (auto)", _num(float(s.autos))],
		["Clicks", _num(float(s.clicks))],
		["Critical clicks", _num(float(s.crits))],
		["Best click combo", str(int(s.best_combo))],
		["Time in the tree", _dur(float(s.time))],
		["Prestiges", _num(float(prestiges(tr)))],
		["Highest layer reached", str(tr._highest_reached())],
		["Features found", "%d / %d" % [tr._found_count, tr.FEAT_COUNT]],
		["Milestones", "%d" % total_ms(tr)],
		["Research levels", "%d" % total_res(tr)],
		["Challenge tiers", "%d / %d" % [total_ch(tr), CH.size() * CH_GOALS.size()]],
		["Insight", _num(floor(float(state(tr).ins)))],
		["Notes hit in maps", _num(float(st.get("notes_hit", 0)))],
		["Maps passed", _num(float(st.get("passes", 0)))],
	]
	var r := _row()
	for l in lines:
		var h := HBoxContainer.new()
		r[0].add_child(h)
		var a := _lbl(l[0], 14, LILAC)
		a.size_flags_horizontal = SIZE_EXPAND_FILL
		h.add_child(a)
		h.add_child(_lbl(str(l[1]), 14, Color(1, 1, 1)))

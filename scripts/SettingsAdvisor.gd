extends Reference

# The Settings Generator's brain. It reads the plays PlayTracker saved
# (user://play_tracking) and works out settings that fit how you play.
#
# Two kinds of evidence:
#
# 1. Your own history. Every play is scored against how well you'd be
#    expected to do on that map (from its star rating and speed), and the
#    model also allows for you getting better over time. When you've played
#    with different values of a setting (sensitivity, approach rate, camera
#    parallax...), it compares them on equal terms and tells you which one you
#    really play best with, and how sure it is (weighted least squares, effect
#    vs. its standard error).
#
# 2. How you miss, on your current settings:
#      late       cursor still on its way      -> more sensitivity / earlier notes
#      overshoot  on the note, then off it     -> less sensitivity
#      near       just off (precision)         -> a little less sensitivity
#      off        somewhere else entirely
#    plus how early your cursor gets to notes, which jumps (speed) and which
#    parts of the grid you miss most.
#
# Only "feel" settings are ever changed (never hitbox, hit window or mods), and
# only by a step at a time, so you can try, play, and generate again.

const PT = preload("res://scripts/game/PlayTracker.gd")

const MIN_PLAYS := 3
const MIN_NOTES := 500
const RECENT := 40 # plays used for the miss patterns

# setting -> [label, bucket size for comparing, rounding for suggestions, min, max]
const TUNABLE := {
	"sensitivity": ["Sensitivity", 0.05, 0.01, 0.05, 5.0],
	"approach_rate": ["Approach Rate", 2.0, 0.5, 5.0, 200.0],
	"spawn_distance": ["Approach Distance", 2.0, 0.5, 5.0, 200.0],
	"parallax": ["Camera Parallax", 0.5, 0.1, 0.0, 30.0],
	"ui_parallax": ["HUD Parallax", 0.25, 0.01, 0.0, 10.0],
	"grid_parallax": ["Grid Parallax", 0.25, 0.01, 0.0, 10.0],
	"fov": ["FOV", 5.0, 1.0, 30.0, 120.0],
	"fade_length": ["Fade In Length", 0.1, 0.01, 0.0, 1.0],
	"cursor_scale": ["Cursor Scale", 0.1, 0.05, 0.2, 3.0],
	"cam_unlock": ["Spin (camera follows cursor)", 1.0, 1.0, 0.0, 1.0],
}

# ------------------------------------------------------------------ entry

static func analyze() -> Dictionary:
	var plays: Array = PT.load_plays()
	var out := {"ok": false, "summary": "", "insights": [], "recs": [], "plays": plays.size(), "notes": 0}
	var total := 0
	for p in plays:
		total += int(p.get("notes", 0))
	out.notes = total
	if plays.size() < MIN_PLAYS or total < MIN_NOTES:
		out.summary = "Not enough plays yet: %d / %d plays and %d / %d notes tracked. Play a few more maps (any result counts) and come back." % [plays.size(), MIN_PLAYS, total, MIN_NOTES]
		return out
	out.ok = true
	var cur := _current()
	var recent: Array = plays.slice(max(0, plays.size() - RECENT), plays.size() - 1)
	var st := _row_stats(recent)
	out.summary = _summary(plays, st)
	out.insights = _insights(st)
	# evidence 1: your history
	var proven := {}
	var resid := _residuals(plays)
	for key in TUNABLE:
		var r = _compare(plays, resid, key, cur.get(key))
		if r != null:
			proven[key] = r
	# evidence 2: how you miss (only for settings the history didn't settle)
	var recs := []
	for key in proven:
		if proven[key].has("to"):
			recs.append(proven[key])
	for r in _from_misses(st, cur):
		if not proven.has(r.key):
			recs.append(r)
	# settings your history says are already your best
	for key in proven:
		if not proven[key].has("to") and proven[key].get("keep", false):
			out.insights.append(proven[key].why)
	if recs.empty():
		recs = _experiments(plays, cur)
	out.recs = recs
	return out

static func _current() -> Dictionary:
	var R = Engine.get_main_loop().root.get_node("Rhythia")
	var d := {}
	for k in TUNABLE:
		d[k] = R.get(k)
	d["absolute_mode"] = R.get("absolute_mode")
	return d

# ------------------------------------------------------------------ rows

static func _row_stats(plays: Array) -> Dictionary:
	var s := {
		"n": 0, "hits": 0, "late": 0, "over": 0, "near": 0, "off": 0,
		"arrive": [], "arrive_fast": [], "offx": 0.0, "offy": 0.0,
		"speed_bins": [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0]],
		"cells": {}, "fast_late": 0, "fast_over": 0, "fast_n": 0,
	}
	var speeds := []
	for p in plays:
		for row in p.rows:
			var gap: float = max(float(row[3]), 1.0)
			speeds.append(float(row[4]) / gap * 1000.0)
	speeds.sort()
	var fast_cut: float = speeds[int(speeds.size() * 0.7)] if speeds.size() > 10 else 3.0
	for p in plays:
		for row in p.rows:
			var kind: int = int(row[5])
			var hit := kind == PT.KIND_HIT
			s.n += 1
			var spd: float = float(row[4]) / max(float(row[3]), 1.0) * 1000.0
			var b := 0
			for edge in [1.5, 3.0, 5.0, 8.0]:
				if spd >= edge:
					b += 1
			s.speed_bins[b][0] += 1
			if hit:
				s.speed_bins[b][1] += 1
			var fast: bool = spd >= fast_cut
			if fast:
				s.fast_n += 1
			var cx := int(clamp(round(float(row[1])), -1, 3))
			var cy := int(clamp(round(-float(row[2])), -1, 3))
			var cell := "%d,%d" % [cx, cy]
			if not s.cells.has(cell):
				s.cells[cell] = [0, 0]
			s.cells[cell][0] += 1
			match kind:
				PT.KIND_HIT:
					s.hits += 1
					s.cells[cell][1] += 1
					s.offx += float(row[8])
					s.offy += float(row[9])
					if int(row[6]) >= 0:
						s.arrive.append(int(row[6]))
						if fast:
							s.arrive_fast.append(int(row[6]))
				PT.KIND_LATE:
					s.late += 1
					if fast:
						s.fast_late += 1
				PT.KIND_OVERSHOOT:
					s.over += 1
					if fast:
						s.fast_over += 1
				PT.KIND_NEAR:
					s.near += 1
				_:
					s.off += 1
	if s.hits > 0:
		s.offx /= s.hits
		s.offy /= s.hits
	s.arrive.sort()
	s.arrive_fast.sort()
	s["fast_cut"] = fast_cut
	return s

static func _median(a: Array) -> float:
	if a.empty():
		return -1.0
	return float(a[a.size() / 2])

static func _pct(a: float, b: float) -> float:
	return 100.0 * a / max(b, 1.0)

static func _summary(plays: Array, s: Dictionary) -> String:
	var misses: int = s.n - s.hits
	return "%d plays and %d notes tracked. Last %d plays: %.1f%% of notes hit. Your misses: %d%% late, %d%% overshot, %d%% just off, %d%% elsewhere." % [
		plays.size(), _count_notes(plays), min(plays.size(), RECENT), _pct(s.hits, s.n),
		int(round(_pct(s.late, misses))), int(round(_pct(s.over, misses))),
		int(round(_pct(s.near, misses))), int(round(_pct(s.off, misses)))]

static func _count_notes(plays: Array) -> int:
	var t := 0
	for p in plays:
		t += int(p.get("notes", 0))
	return t

static func _insights(s: Dictionary) -> Array:
	var out := []
	var names := ["slow (under 1.5 cells/s)", "medium (1.5-3)", "fast (3-5)", "very fast (5-8)", "extreme (8+ cells/s)"]
	var worst := -1
	var worst_rate := 2.0
	var lines := []
	for b in range(5):
		var n: int = s.speed_bins[b][0]
		if n < 40:
			continue
		var rate: float = float(s.speed_bins[b][1]) / n
		lines.append("%s %.0f%%" % [names[b].split(" (")[0], rate * 100.0])
		if rate < worst_rate:
			worst_rate = rate
			worst = b
	if not lines.empty():
		out.append("Hit rate by jump speed: " + PoolStringArray(lines).join(", ") + ".")
	if worst >= 0 and worst_rate < 0.97:
		out.append("Your weakest notes are %s jumps." % names[worst])
	var med := _median(s.arrive)
	if med >= 0:
		out.append("Your cursor usually gets to a note %d ms before it arrives (fast jumps: %d ms)." % [int(med), int(max(_median(s.arrive_fast), 0))])
	# grid: weakest cell
	var worst_cell := ""
	var wr := 2.0
	var center_rate := -1.0
	for cell in s.cells:
		var c: Array = s.cells[cell]
		if c[0] < 60:
			continue
		var r: float = float(c[1]) / c[0]
		if cell == "1,1":
			center_rate = r
		if r < wr:
			wr = r
			worst_cell = cell
	if worst_cell != "" and wr < 0.97:
		out.append("You miss most in the %s of the grid (%.0f%% hit there)." % [_cell_name(worst_cell), wr * 100.0])
	var bias := Vector2(s.offx, s.offy)
	if bias.length() >= 0.18:
		var dir := ""
		if abs(bias.y) >= 0.12:
			dir += "low" if bias.y < 0 else "high"
		if abs(bias.x) >= 0.12:
			dir += ("-" if dir != "" else "") + ("left" if bias.x < 0 else "right")
		out.append("When you hit, you tend to be a bit %s of the note's centre." % dir)
	return out

static func _cell_name(cell: String) -> String:
	var p := cell.split(",")
	var x := int(p[0])
	var y := int(p[1])
	if x < 0 or x > 2 or y < 0 or y > 2:
		return "outside of the 3x3"
	var cols := ["left", "middle", "right"]
	var rows := ["top", "middle", "bottom"]
	if x == 1 and y == 1:
		return "centre"
	if x == 1:
		return "%s middle" % rows[y]
	if y == 1:
		return "middle %s" % cols[x]
	return "%s %s corner" % [rows[y], cols[x]]

# ------------------------------------------------------------------ history

# How each play went compared to what you'd be expected to get on that map:
# accuracy ~ a + b * difficulty (stars x speed), fitted on all your plays.
static func _residuals(plays: Array) -> Array:
	var xs := []
	var ys := []
	var ws := []
	var known := []
	for p in plays:
		var st: float = float(p.get("stars", -1.0))
		if st >= 0:
			known.append(st)
	known.sort()
	var fill: float = known[known.size() / 2] if not known.empty() else 5.0
	for p in plays:
		var st: float = float(p.get("stars", -1.0))
		if st < 0:
			st = fill
		xs.append([1.0, st * float(p.get("speed", 1.0))])
		ys.append(float(p.hits) / max(float(p.notes), 1.0))
		ws.append(min(float(p.notes), 2000.0))
	var fit = _wls(xs, ys, ws)
	var out := []
	for i in range(plays.size()):
		var pred: float = fit.beta[0] + fit.beta[1] * xs[i][1] if fit != null else 0.0
		out.append(ys[i] - pred)
	return out

static func _bucket(key: String, v) -> float:
	var step: float = TUNABLE[key][1]
	if typeof(v) == TYPE_BOOL:
		return 1.0 if v else 0.0
	return stepify(float(v), step)

# Compares the values of one setting you've played with. Returns null when
# there isn't enough to compare, else a dict: with "to" for a change, or
# "keep" when your current value is already your best.
static func _compare(plays: Array, resid: Array, key: String, current):
	if current == null:
		return null
	var groups := {}
	for i in range(plays.size()):
		var v = plays[i].settings.get(key)
		if v == null:
			continue
		var b := _bucket(key, v)
		if not groups.has(b):
			groups[b] = {"plays": 0, "notes": 0}
		groups[b].plays += 1
		groups[b].notes += int(plays[i].notes)
	var usable := []
	for b in groups:
		if groups[b].plays >= 3 and groups[b].notes >= 400:
			usable.append(b)
	if usable.size() < 2:
		return null
	usable.sort()
	var cb := _bucket(key, current)
	var ref: float = cb if usable.has(cb) else usable[0]
	var others := []
	for b in usable:
		if b != ref:
			others.append(b)
	# residual ~ b0 + b1 * time + one effect per other value (vs ref)
	var xs := []
	var ys := []
	var ws := []
	var n := plays.size()
	for i in range(n):
		var v = plays[i].settings.get(key)
		if v == null:
			continue
		var b := _bucket(key, v)
		if not usable.has(b):
			continue
		var row := [1.0, float(i) / max(n - 1, 1)]
		for o in others:
			row.append(1.0 if b == o else 0.0)
		xs.append(row)
		ys.append(resid[i])
		ws.append(min(float(plays[i].notes), 2000.0))
	var fit = _wls(xs, ys, ws)
	if fit == null:
		return null
	var best := ref
	var best_eff := 0.0
	var best_se := 0.0
	for j in range(others.size()):
		var eff: float = fit.beta[2 + j]
		if eff > best_eff:
			best_eff = eff
			best = others[j]
			best_se = fit.se[2 + j]
	var label: String = TUNABLE[key][0]
	if best == ref:
		if ref == cb:
			return {"key": key, "keep": true, "why": "%s: your current %s is the best of the values you've played with (%d values compared)." % [label, _fmt(key, current), usable.size()]}
		return null
	var t: float = best_eff / max(best_se, 1e-6)
	if t < 1.5 or best_eff < 0.005:
		return null # no clear difference: leave it to how you miss
	var conf := "high" if t >= 2.5 and best_eff >= 0.01 else "medium"
	var to = _round(key, best)
	return {
		"key": key, "label": label, "from": current, "to": to, "conf": conf, "src": "history",
		"why": "With %s %s you hit %.1f%% more notes than with %s %s, on maps of the same difficulty and allowing for you improving over time (%d plays compared)." % [
			label, _fmt(key, to), best_eff * 100.0, label, _fmt(key, _round(key, ref)), xs.size()],
	}

# ------------------------------------------------------------------ misses

static func _from_misses(s: Dictionary, cur: Dictionary) -> Array:
	var out := []
	var n: float = max(float(s.n), 1.0)
	var late: float = s.late
	var over: float = s.over + 0.5 * s.near
	var miss: float = n - s.hits
	if miss < 10:
		return out
	# sensitivity: overshooting vs arriving late
	if not bool(cur.get("absolute_mode", false)):
		var sens: float = float(cur.sensitivity)
		var share_over: float = over / max(over + late, 1.0)
		if over / n >= 0.01 and over > late * 1.5:
			var f: float = 1.0 - clamp(0.04 + (share_over - 0.6) * 0.25, 0.04, 0.12)
			out.append(_rec("sensitivity", sens, sens * f, "medium" if over / n >= 0.02 else "try",
				"%d%% of your misses are overshoots (you get to the note but go past it) against %d%% late, so a slightly lower sensitivity should help you stop on notes." % [int(round(_pct(s.over, miss))), int(round(_pct(s.late, miss)))]))
		elif late / n >= 0.01 and late > over * 1.5:
			var f2: float = 1.0 + clamp(0.04 + ((1.0 - share_over) - 0.6) * 0.25, 0.04, 0.12)
			out.append(_rec("sensitivity", sens, sens * f2, "medium" if late / n >= 0.02 else "try",
				"%d%% of your misses are late (your cursor is still on its way when the note passes) against %d%% overshoots, so a slightly higher sensitivity should get you there in time." % [int(round(_pct(s.late, miss))), int(round(_pct(s.over, miss)))]))
	# approach: little time to react on fast jumps
	var ar: float = float(cur.approach_rate)
	var dist: float = float(cur.spawn_distance)
	var med_fast := _median(s.arrive_fast)
	if ar > 0 and dist > 0 and s.fast_late >= 6 and float(s.fast_late) / max(s.fast_n, 1) >= 0.03 and med_fast >= 0 and med_fast < 140:
		var vis: float = dist / ar
		var new_ar: float = dist / (vis * 1.15)
		out.append(_rec("approach_rate", ar, new_ar, "medium",
			"On fast jumps your cursor arrives only ~%d ms early and %d%% of them are late misses: notes showing up a little earlier (lower approach rate, same distance) gives you more time to read them." % [int(med_fast), int(round(_pct(s.fast_late, s.fast_n)))]))
	# parallax: edges much worse than the centre
	var center: Array = s.cells.get("1,1", [0, 0])
	var edge_n := 0
	var edge_h := 0
	for cell in s.cells:
		if cell != "1,1":
			edge_n += s.cells[cell][0]
			edge_h += s.cells[cell][1]
	var par: float = float(cur.parallax)
	if center[0] >= 60 and edge_n >= 200 and par >= 2.0:
		var cr: float = float(center[1]) / center[0]
		var er: float = float(edge_h) / edge_n
		if cr - er >= 0.05:
			out.append(_rec("parallax", par, par * 0.7, "try",
				"You hit %.0f%% of centre notes but only %.0f%% of the outer ones; less camera parallax keeps the edges of the grid steadier on screen." % [cr * 100.0, er * 100.0]))
	return out

static func _rec(key: String, from, to, conf: String, why: String) -> Dictionary:
	return {"key": key, "label": TUNABLE[key][0], "from": from, "to": _round(key, to), "conf": conf, "src": "misses", "why": why}

# When nothing stands out: a small, safe experiment so your history can
# compare next time.
static func _experiments(plays: Array, cur: Dictionary) -> Array:
	var tried := {}
	for p in plays:
		var v = p.settings.get("sensitivity")
		if v != null:
			tried[_bucket("sensitivity", v)] = true
	if tried.size() >= 2 or bool(cur.get("absolute_mode", false)):
		return []
	var sens: float = float(cur.sensitivity)
	return [_rec("sensitivity", sens, sens * 0.95, "try",
		"Nothing in how you miss points one way yet. Play about 5 maps with a 5% lower sensitivity; then Generate again and your history will show which one you really play better with.")]

# ------------------------------------------------------------------ helpers

static func _round(key: String, v):
	if key == "cam_unlock":
		return float(v) >= 0.5
	var r: float = TUNABLE[key][2]
	return clamp(stepify(float(v), r), TUNABLE[key][3], TUNABLE[key][4])

static func _fmt(key: String, v) -> String:
	if typeof(v) == TYPE_BOOL:
		return "on" if v else "off"
	if key == "fade_length":
		return "%d%%" % int(round(float(v) * 100.0))
	var r: float = TUNABLE[key][2]
	if r >= 1.0:
		return str(int(round(float(v))))
	return str(stepify(float(v), r))

static func fmt(key: String, v) -> String:
	return _fmt(key, v)

# Weighted least squares: beta = (X'WX)^-1 X'Wy, with standard errors.
static func _wls(xs: Array, ys: Array, ws: Array):
	var n := xs.size()
	if n == 0:
		return null
	var k: int = xs[0].size()
	if n <= k:
		return null
	var a := []
	var bv := []
	for i in range(k):
		var row := []
		for j in range(k):
			row.append(0.0)
		a.append(row)
		bv.append(0.0)
	var wsum := 0.0
	for r in range(n):
		var w: float = ws[r]
		wsum += w
		for i in range(k):
			bv[i] += w * xs[r][i] * ys[r]
			for j in range(k):
				a[i][j] += w * xs[r][i] * xs[r][j]
	var inv = _invert(a)
	if inv == null:
		return null
	var beta := []
	for i in range(k):
		var v := 0.0
		for j in range(k):
			v += inv[i][j] * bv[j]
		beta.append(v)
	# residual variance (weights scaled to the number of plays)
	var sse := 0.0
	for r in range(n):
		var pred := 0.0
		for i in range(k):
			pred += beta[i] * xs[r][i]
		sse += ws[r] * pow(ys[r] - pred, 2)
	var sigma2: float = sse / max(wsum, 1e-9) * float(n) / float(n - k)
	var scale: float = wsum / float(n) # back to per-play units
	var se := []
	for i in range(k):
		se.append(sqrt(max(inv[i][i] * sigma2 * scale, 0.0)))
	return {"beta": beta, "se": se}

static func _invert(m: Array):
	var n := m.size()
	var a := []
	for i in range(n):
		var row: Array = m[i].duplicate()
		for j in range(n):
			row.append(1.0 if i == j else 0.0)
		a.append(row)
	for c in range(n):
		var piv := c
		for r in range(c + 1, n):
			if abs(a[r][c]) > abs(a[piv][c]):
				piv = r
		if abs(a[piv][c]) < 1e-12:
			return null
		var tmp = a[c]
		a[c] = a[piv]
		a[piv] = tmp
		var d: float = a[c][c]
		for j in range(2 * n):
			a[c][j] /= d
		for r in range(n):
			if r != c:
				var f: float = a[r][c]
				if f != 0.0:
					for j in range(2 * n):
						a[r][j] -= f * a[c][j]
	var inv := []
	for i in range(n):
		inv.append(a[i].slice(n, 2 * n - 1))
	return inv

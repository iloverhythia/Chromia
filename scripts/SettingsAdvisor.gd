extends Reference

# The Settings Generator's brain. It reads the plays PlayTracker saved
# (user://play_tracking), each with the settings and mods it was really
# played with, and works out settings that fit how you play.
#
# 1. Your history, note by note. A model of your chance to hit each note:
#      logit P(hit) = how hard the note is (jump speed, jump size, gap,
#                     how many notes come right after, grid edge, the map's
#                     stars and speed) + how much you've improved
#                     + the settings of the play it was in
#    fitted on all your plays (grouped binomial logistic regression, its
#    uncertainty widened for plays that go better or worse as a whole). For
#    each setting you've played with different values of, it asks: on your
#    usual notes, with how you play now, which of those values hits the most?
#    It only picks values you've actually played (or one step past the end),
#    and only when the difference is clearly more than chance.
#    Approach rate and distance are looked at together, as what they do to you:
#    how long a note is on screen before it arrives (distance / approach rate,
#    minus the fade-in) and how far apart notes coming one after another are
#    (approach rate).
#
# 2. How you play with the settings you have now (only plays with those
#    settings; another value's habits don't count for this one):
#      sensitivity  overshooting / sliding off notes vs arriving late, how far
#                   past them you go, how early you get there
#      distance     your reaction time (measured from notes that showed up
#                   after you'd finished the one before) against how long notes
#                   are on screen: late misses on notes that appeared late
#                   -> more distance
#      approach     leaving a note early for the next one / skipping notes in
#                   quick runs -> a higher approach rate with the same time
#                   on screen (notes further apart)
#      fade in      the same late misses while a long fade-in eats into the
#                   time notes are readable -> less fade first
#      parallax     touch (absolute) players: the camera and grid move with the
#                   cursor, so outer notes show up a bit off from where the
#                   finger has to go. Hitting outer notes on their inner side
#                   (measured from where in the hitbox each hit lands) -> less
#                   camera / grid parallax
#      FOV, cursor  missing notes by a hair (just outside the hitbox) -> a
#                   smaller cursor if it's big (it covers the note's edge), or
#                   a lower FOV (a bigger grid on screen) with a mouse;
#                   losing the cursor with a tiny one -> a bigger cursor
#
# Only "feel" settings are ever changed (never hitbox, hit window or mods).

const PT = preload("res://scripts/game/PlayTracker.gd")

const MIN_PLAYS := 3
const MIN_NOTES := 600
const CUR_NOTES := 700   # notes with the current settings to judge how you play with them
const CUR_PLAYS := 3
const RECENT := 40       # newest plays used for "how you play now"
const FADE_SEEN := 0.6   # a note is readable after ~60% of its fade-in

# setting -> [label, bucket size for comparing, rounding for suggestions, min, max, scale]
# scale: "log" (ratios matter), "lin" (can be 0), "bool"
const TUNABLE := {
	"sensitivity": ["Sensitivity", 0.04, 0.01, 0.05, 5.0, "log"],
	"absolute_scale": ["Absolute Scale", 0.04, 0.01, 0.2, 4.0, "log"],
	"approach_rate": ["Approach Rate", 0.04, 0.5, 5.0, 300.0, "log"],
	"spawn_distance": ["Approach Distance", 0.04, 0.5, 5.0, 300.0, "log"],
	"parallax": ["Camera Parallax", 0.5, 0.1, 0.0, 30.0, "lin"],
	"ui_parallax": ["HUD Parallax", 0.25, 0.01, 0.0, 10.0, "lin"],
	"grid_parallax": ["Grid Parallax", 0.25, 0.01, 0.0, 10.0, "lin"],
	"fov": ["FOV", 0.04, 1.0, 30.0, 120.0, "log"],
	"fade_length": ["Fade In Length", 0.1, 0.01, 0.0, 1.0, "lin"],
	"cursor_scale": ["Cursor Scale", 0.08, 0.05, 0.2, 3.0, "log"],
	"cam_unlock": ["Spin (camera follows cursor)", 1.0, 1.0, 0.0, 1.0, "bool"],
}
# compared one at a time from your history (approach and distance together)
const HISTORY_KEYS := ["sensitivity", "absolute_scale", "parallax", "ui_parallax", "grid_parallax", "fov", "fade_length", "cursor_scale", "cam_unlock"]
const READ_MODS := ["mod_ghost", "mod_nearsighted", "mod_flashlight", "mod_strobe"]
const MOVE_MODS := ["mod_chaos", "mod_earthquake", "mod_360", "mod_hardrock"]
const LOOK_NOTES := 1500  # notes with the current camera/cursor settings to judge them
const SPEED_EDGES := [1.0, 2.0, 3.5, 5.0, 7.0, 10.0] # cells per second
const GAP_EDGES := [100.0, 200.0, 350.0]             # ms

# ------------------------------------------------------------------ entry

# cur: your settings now (read on the main thread, see GeneratorTab).
static func analyze(cur: Dictionary) -> Dictionary:
	var out := {"ok": false, "summary": "", "insights": [], "recs": [], "profiles": [], "plays": 0, "notes": 0}
	var plays := _prepare(PT.load_plays())
	out.plays = plays.size()
	var total := 0
	for p in plays:
		total += p.rows.size()
	out.notes = total
	if plays.size() < MIN_PLAYS or total < MIN_NOTES:
		out.summary = "Not enough plays yet: %d / %d plays and %d / %d notes tracked. Play a few more maps (any result counts) and come back." % [plays.size(), MIN_PLAYS, total, MIN_NOTES]
		return out
	out.ok = true
	cur = cur.duplicate()
	if cur.get("approach_rate") != null and cur.get("spawn_distance") != null:
		cur["vis"] = _vis_time(float(cur.spawn_distance), float(cur.approach_rate), float(cur.get("fade_length", 0.0)))

	var model = _fit_base(plays)
	var recs := []
	var notes_txt := []
	# 1. history: one setting at a time, then approach + distance
	var hist := {}
	if model != null:
		for key in HISTORY_KEYS:
			if key == "sensitivity" and bool(cur.get("absolute_mode", false)):
				continue
			if key == "absolute_scale" and not bool(cur.get("absolute_mode", false)):
				continue
			var r = _history_setting(plays, model, key, cur)
			if r != null:
				hist[key] = r
		var ra = _history_approach(plays, model, cur)
		if ra != null:
			hist["approach"] = ra
	for k in hist:
		if hist[k].has("changes"):
			recs.append(hist[k])
		elif hist[k].has("note"):
			notes_txt.append(hist[k].note)

	# 2. how you play with the settings you have now
	var mine := _current_plays(plays, cur)
	if not hist.has("sensitivity") and not hist.has("absolute_scale"):
		var rs = _motor(mine.motor, cur)
		if rs != null:
			if rs.has("changes"):
				recs.append(rs)
			elif rs.has("note"):
				notes_txt.append(rs.note)
	if not hist.has("approach"):
		for r in _reading(mine.reading, cur):
			if r.has("changes"):
				recs.append(r)
			elif r.has("note"):
				notes_txt.append(r.note)
	# camera, grid, FOV and cursor (each only if your history didn't already
	# decide it)
	for r in _look(plays, cur, hist):
		if r.has("changes"):
			recs.append(r)
		elif r.has("note"):
			notes_txt.append(r.note)
	if recs.size() < 2:
		var taken := {}
		for r in recs:
			for k in r.changes:
				taken[k] = true
		for e in _experiments(mine, cur, hist, plays, taken):
			if recs.size() >= 3:
				break
			recs.append(e)

	recs.sort_custom(Sorter, "by_strength")
	if recs.size() > 5:
		recs.resize(5)
	out.recs = recs
	out.profiles = _profiles(plays, model, cur)
	out.summary = _summary(plays, mine, cur)
	out.insights = _insights(mine, cur) + notes_txt
	return out

class Sorter:
	static func by_strength(a, b) -> bool:
		var ra: int = {"high": 3, "medium": 2, "try": 1}.get(a.conf, 0)
		var rb: int = {"high": 3, "medium": 2, "try": 1}.get(b.conf, 0)
		if ra != rb:
			return ra > rb
		return float(a.get("gain", 0.0)) > float(b.get("gain", 0.0))

# ------------------------------------------------------------------ plays

# Seconds a note is readable before it arrives (map speed doesn't change it:
# notes move by real time).
static func _vis_time(dist: float, ar: float, fade: float) -> float:
	if ar <= 0.0 or dist <= 0.0:
		return -1.0
	return dist / ar * (1.0 - FADE_SEEN * clamp(fade, 0.0, 1.0))

# Adds what the generator needs to each play and drops the ones it can't use.
static func _prepare(raw: Array) -> Array:
	var out := []
	for p in raw:
		if typeof(p) != TYPE_DICTIONARY or not (p.get("rows") is Array) or p.rows.size() < 20:
			continue
		if not (p.get("settings") is Dictionary):
			continue
		out.append(p)
	# stars: unknown -> your usual
	var known := []
	for p in out:
		if float(p.get("stars", -1.0)) >= 0:
			known.append(float(p.stars))
	known.sort()
	var fill: float = known[known.size() / 2] if not known.empty() else 4.0
	var n := out.size()
	for i in range(n):
		var p: Dictionary = out[i]
		var s: Dictionary = p.settings
		var spd: float = max(float(p.get("speed", 1.0)), 0.1)
		p["spd"] = spd
		p["idx"] = i
		p["practice"] = float(i) / max(n - 1, 1)
		var st: float = float(p.get("stars", -1.0))
		p["diff"] = (st if st >= 0 else fill) * spd
		var mods: Array = p.get("mods", []) if p.get("mods") is Array else []
		p["read_ok"] = not bool(s.get("half_ghost", false)) and not bool(s.get("note_visual_approach", false))
		p["move_ok"] = true
		for m in mods:
			if READ_MODS.has(m):
				p.read_ok = false
			if MOVE_MODS.has(m):
				p.move_ok = false
		var ar: float = float(s.get("approach_rate", -1.0))
		var dist: float = float(s.get("spawn_distance", -1.0))
		p["ar"] = ar
		p["vis"] = _vis_time(dist, ar, float(s.get("fade_length", 0.0)))
		if p.vis <= 0:
			p.read_ok = false
		p["v"] = int(p.get("v", 1))
		# per note, in real time
		var rows: Array = p.rows
		var times := []
		for row in rows:
			times.append(float(row[0]) / spd)
		var feats := []
		var j := 0
		for k in range(rows.size()):
			var row: Array = rows[k]
			var gap: float = float(row[3]) / spd
			var jump: float = float(row[4])
			var cps: float = jump / max(gap, 40.0) * 1000.0
			while j < times.size() and times[j] <= times[k]:
				j += 1
			var dens := 0
			var q := j
			while q < times.size() and times[q] - times[k] <= 500.0:
				dens += 1
				q += 1
			var cx := int(round(float(row[1])))
			var cy := int(round(float(row[2])))
			var edge: bool = cx != 1 or cy != -1
			feats.append({
				"gap": gap, "jump": jump, "cps": cps, "dens": dens, "edge": edge,
				"kind": int(row[5]),
				"arrive": float(row[6]) / spd if int(row[6]) >= 0 else -1.0,
				"min": float(row[7]),
				"offx": float(row[8]), "offy": float(row[9]),
				"react": float(row[10]) / spd if row.size() > 10 and int(row[10]) >= 0 else -1.0,
				"over": float(row[11]) if row.size() > 11 else -1.0,
				"cell": "%d,%d" % [int(clamp(cx, -1, 3)), int(clamp(-cy, -1, 3))],
			})
		p["f"] = feats
	return out

static func _sbin(cps: float) -> int:
	var b := 0
	for e in SPEED_EDGES:
		if cps >= e:
			b += 1
	return b

static func _gbin(gap: float) -> int:
	var b := 0
	for e in GAP_EDGES:
		if gap >= e:
			b += 1
	return b

# Notes grouped per play, speed and gap: [play index, n, hits, mean features]
static func _groups(plays: Array) -> Array:
	var out := []
	for p in plays:
		var g := {}
		for f in p.f:
			var key: int = _sbin(f.cps) * 10 + _gbin(f.gap)
			if not g.has(key):
				g[key] = {"n": 0, "h": 0, "lcps": 0.0, "jump": 0.0, "dens": 0.0, "edge": 0.0}
			var e: Dictionary = g[key]
			e.n += 1
			if f.kind == PT.KIND_HIT:
				e.h += 1
			e.lcps += log(1.0 + f.cps)
			e.jump += f.jump
			e.dens += f.dens
			e.edge += 1.0 if f.edge else 0.0
		for key in g:
			var e: Dictionary = g[key]
			var n: float = e.n
			out.append({"play": p.idx, "n": e.n, "h": e.h,
				"x": [e.lcps / n, e.jump / n, e.dens / n, e.edge / n, p.diff, p.practice]})
	return out

# ------------------------------------------------------------------ the model

# Base model: note difficulty + map + practice. Settings terms are added per
# comparison. Returns {groups, base_k}.
static func _fit_base(plays: Array):
	var groups := _groups(plays)
	if groups.size() < 8:
		return null
	return {"groups": groups, "base_k": groups[0].x.size()}

# Fits the base features plus extra columns (one row of extras per group).
# Returns {beta, cov, mu, sd} or null.
static func _fit(model: Dictionary, extra: Array):
	var groups: Array = model.groups
	var xs := []
	var ns := []
	var ys := []
	for gi in range(groups.size()):
		var g: Dictionary = groups[gi]
		var row: Array = g.x.duplicate()
		row += extra[gi]
		xs.append(row)
		ns.append(float(g.n))
		ys.append(float(g.h))
	return _logit(xs, ns, ys)

# Grouped logistic regression by IRLS, on standardised columns (an intercept is
# added in front). The covariance is widened by the overdispersion (how much
# whole plays vary more than single notes would).
static func _logit(xs: Array, ns: Array, ys: Array):
	var n := xs.size()
	if n == 0:
		return null
	var k0: int = xs[0].size()
	var mu := []
	var sd := []
	for j in range(k0):
		var s := 0.0
		var w := 0.0
		for i in range(n):
			s += xs[i][j] * ns[i]
			w += ns[i]
		var m: float = s / max(w, 1e-9)
		var v := 0.0
		for i in range(n):
			v += ns[i] * pow(xs[i][j] - m, 2)
		mu.append(m)
		sd.append(sqrt(v / max(w, 1e-9)))
	var X := []
	for i in range(n):
		var row := [1.0]
		for j in range(k0):
			row.append((xs[i][j] - mu[j]) / sd[j] if sd[j] > 1e-9 else 0.0)
		X.append(row)
	var k := k0 + 1
	var tot_h := 0.0
	var tot_n := 0.0
	for i in range(n):
		tot_h += ys[i]
		tot_n += ns[i]
	var p0: float = clamp(tot_h / max(tot_n, 1.0), 0.01, 0.995)
	var beta := [log(p0 / (1.0 - p0))]
	for j in range(k - 1):
		beta.append(0.0)
	var info = null
	for it in range(30):
		var a := _zeros(k, k)
		var bv := []
		for j in range(k):
			bv.append(0.0)
		for i in range(n):
			var eta := 0.0
			for j in range(k):
				eta += X[i][j] * beta[j]
			var pp: float = 1.0 / (1.0 + exp(-clamp(eta, -30.0, 30.0)))
			var w: float = max(ns[i] * pp * (1.0 - pp), 1e-6)
			var z: float = eta + (ys[i] - ns[i] * pp) / w
			for j in range(k):
				var wx: float = w * X[i][j]
				bv[j] += wx * z
				for l in range(j, k):
					a[j][l] += wx * X[i][l]
		for j in range(k):
			for l in range(j):
				a[j][l] = a[l][j]
			if j > 0:
				a[j][j] += 0.5 # a light ridge: keeps barely-used columns from running away
		info = _invert(a)
		if info == null:
			return null
		var nb := []
		var change := 0.0
		for j in range(k):
			var v := 0.0
			for l in range(k):
				v += info[j][l] * bv[l]
			nb.append(v)
			change = max(change, abs(v - beta[j]))
		beta = nb
		if change < 1e-5:
			break
	# overdispersion (Pearson)
	var chi := 0.0
	for i in range(n):
		var eta := 0.0
		for j in range(k):
			eta += X[i][j] * beta[j]
		var pp: float = 1.0 / (1.0 + exp(-clamp(eta, -30.0, 30.0)))
		var var_i: float = max(ns[i] * pp * (1.0 - pp), 1e-6)
		chi += pow(ys[i] - ns[i] * pp, 2) / var_i
	var phi: float = max(chi / max(n - k, 1), 1.0)
	var cov := []
	for j in range(k):
		var row := []
		for l in range(k):
			row.append(info[j][l] * phi)
		cov.append(row)
	return {"beta": beta, "cov": cov, "mu": mu, "sd": sd, "phi": phi}

static func _zeros(r: int, c: int) -> Array:
	var a := []
	for i in range(r):
		var row := []
		for j in range(c):
			row.append(0.0)
		a.append(row)
	return a

# Linear predictor of one group with its extra columns replaced.
static func _eta(fit: Dictionary, base_x: Array, extra: Array) -> float:
	var row: Array = base_x + extra
	var eta: float = fit.beta[0]
	for j in range(row.size()):
		if fit.sd[j] > 1e-9:
			eta += fit.beta[j + 1] * (row[j] - fit.mu[j]) / fit.sd[j]
	return eta

# Your usual notes, with how you play now: the groups of your newest plays,
# with practice set to "now".
static func _reference(model: Dictionary, plays: Array) -> Array:
	var newest := {}
	for i in range(max(0, plays.size() - RECENT), plays.size()):
		newest[plays[i].idx] = true
	var out := []
	for g in model.groups:
		if newest.has(g.play):
			var x: Array = g.x.duplicate()
			x[5] = 1.0
			out.append({"n": g.n, "x": x})
	return out

# Mean chance to hit your usual notes with these extra columns.
static func _hit_rate(fit: Dictionary, ref: Array, extra: Array) -> float:
	var s := 0.0
	var w := 0.0
	for g in ref:
		s += g.n / (1.0 + exp(-clamp(_eta(fit, g.x, extra), -30.0, 30.0)))
		w += g.n
	return s / max(w, 1.0)

# Standard error of the difference in linear predictor between two values of
# the extra columns (only those differ).
static func _diff_se(fit: Dictionary, base_k: int, ea: Array, eb: Array) -> float:
	var d := []
	for j in range(ea.size()):
		var c: int = base_k + j
		d.append((ea[j] - eb[j]) / fit.sd[c] if fit.sd[c] > 1e-9 else 0.0)
	var v := 0.0
	for a in range(d.size()):
		for b in range(d.size()):
			v += d[a] * d[b] * fit.cov[base_k + 1 + a][base_k + 1 + b]
	return sqrt(max(v, 0.0))

static func _diff_eta(fit: Dictionary, base_k: int, ea: Array, eb: Array) -> float:
	var s := 0.0
	for j in range(ea.size()):
		var c: int = base_k + j
		if fit.sd[c] > 1e-9:
			s += fit.beta[c + 1] * (ea[j] - eb[j]) / fit.sd[c]
	return s

# ------------------------------------------------------------------ history

static func _tx(key: String, v) -> float:
	var kind: String = TUNABLE[key][5]
	if kind == "bool":
		return 1.0 if bool(v) else 0.0
	if kind == "log":
		return log(max(float(v), 1e-4))
	return float(v)

static func _untx(key: String, x: float):
	var kind: String = TUNABLE[key][5]
	if kind == "bool":
		return x >= 0.5
	if kind == "log":
		return exp(x)
	return x

static func _bucket_of(key: String, v) -> float:
	var step: float = TUNABLE[key][1]
	return stepify(_tx(key, v), step) if TUNABLE[key][5] != "bool" else _tx(key, v)

# What you've played with: bucket -> {plays, notes, x (mean transformed value)}
# what: "vis" (time on screen), "ar" (approach rate) or a setting's name
static func _support(plays: Array, what: String, key: String) -> Dictionary:
	var g := {}
	for p in plays:
		var v = _value_of(p, what)
		if v == null:
			continue
		var b := _bucket_of(key, v)
		if not g.has(b):
			g[b] = {"plays": 0, "notes": 0, "x": 0.0}
		g[b].plays += 1
		g[b].notes += p.rows.size()
		g[b].x += _tx(key, v) * p.rows.size()
	for b in g:
		g[b].x /= max(g[b].notes, 1)
	return g

static func _value_of(p: Dictionary, what: String):
	if what == "vis":
		return p.vis if p.read_ok and p.vis > 0 else null
	if what == "ar":
		return p.ar if p.read_ok and p.ar > 0 else null
	return p.settings.get(what)

static func _conf(z: float, gain: float) -> String:
	if z >= 2.3 and gain >= 0.01:
		return "high"
	if z >= 1.64 and gain >= 0.004:
		return "medium"
	return ""

static func _history_setting(plays: Array, model: Dictionary, key: String, cur: Dictionary):
	var sup := _support(plays, key, key)
	var usable := []
	for b in sup:
		if sup[b].plays >= 2 and sup[b].notes >= 300:
			usable.append(b)
	if usable.size() < 2:
		return null
	usable.sort()
	var quad: bool = usable.size() >= 3 and TUNABLE[key][5] != "bool"
	# one extra column (two with a curve); plays with a value you barely used
	# get the nearest usable value's column
	var extra := []
	for g in model.groups:
		var v = plays[g.play].settings.get(key)
		var x: float = _tx(key, v) if v != null else sup[usable[0]].x
		var row := [x]
		if quad:
			row.append(x * x)
		extra.append(row)
	var fit = _fit(model, extra)
	if fit == null:
		return null
	var ref := _reference(model, plays)
	var lo: float = sup[usable[0]].x
	var hi: float = sup[usable[-1]].x
	var curv = cur.get(key)
	if curv == null:
		return null
	var cx: float = _tx(key, curv)
	var cands := []
	if TUNABLE[key][5] == "bool":
		cands = [0.0, 1.0]
	elif quad:
		for i in range(21):
			cands.append(lerp(lo, hi, i / 20.0))
	else:
		cands = [lo, hi]
	var best_x: float = cx
	var best_rate: float = -1.0
	for x in cands:
		var e := [x]
		if quad:
			e.append(x * x)
		var r := _hit_rate(fit, ref, e)
		if r > best_rate:
			best_rate = r
			best_x = x
	var ccx: float = clamp(cx, lo, hi) # your value, or the nearest one you've played
	var ce := [ccx]
	var be := [best_x]
	if quad:
		ce.append(ccx * ccx)
		be.append(best_x * best_x)
	var cur_rate := _hit_rate(fit, ref, ce)
	var gain: float = best_rate - cur_rate
	var de: float = _diff_eta(fit, model.base_k, be, ce)
	var se: float = _diff_se(fit, model.base_k, be, ce)
	var z: float = de / max(se, 1e-6)
	var label: String = TUNABLE[key][0]
	var to = _round(key, _untx(key, best_x))
	if abs(best_x - ccx) < 1e-6 or _same(key, to, curv):
		if abs(cx - ccx) > 1e-6:
			return null
		# is yours clearly better than the next best value, or just as good?
		var other_x: float = ccx
		var other_rate: float = -1.0
		for x in cands:
			if abs(x - ccx) < (hi - lo) * 0.2 + 1e-6:
				continue
			var e2 := [x]
			if quad:
				e2.append(x * x)
			var r2 := _hit_rate(fit, ref, e2)
			if r2 > other_rate:
				other_rate = r2
				other_x = x
		if other_rate < 0:
			return null
		var oe := [other_x]
		if quad:
			oe.append(other_x * other_x)
		var zk: float = _diff_eta(fit, model.base_k, ce, oe) / max(_diff_se(fit, model.base_k, ce, oe), 1e-6)
		if zk >= 1.64:
			return {"note": "%s: your %s is the best of the values you've played with (%.1f%% more notes than %s; %d plays compared on equal terms)." % [label, _fmt(key, curv), (cur_rate - other_rate) * 100.0, _fmt(key, _round(key, _untx(key, other_x))), plays.size()]}
		return {"note": "%s: no clear difference yet between %s and %s once each map's difficulty and you improving are allowed for." % [label, _fmt(key, curv), _fmt(key, _round(key, _untx(key, other_x)))]}
	var conf := _conf(z, gain)
	if conf == "":
		if z >= 1.0 and gain >= 0.004:
			return {"note": "%s: your plays lean toward %s (%+.1f%% notes) but it isn't clear yet; keep playing and Generate again." % [label, _fmt(key, to), gain * 100.0]}
		return null
	var same := _same_map(plays, key, best_x, ccx)
	var why := "On your usual notes, with how you play now, %s %s hits %.1f%% more notes than %s (from %d plays, comparing like with like: each note's difficulty, the map and you improving are all taken into account)." % [
		label, _fmt(key, to), gain * 100.0, _fmt(key, curv), plays.size()]
	if same != "":
		why += " " + same
	return _rec({key: to}, cur, conf, why, "history", gain)

# Maps you played with both values: raw hit rates (for the explanation).
static func _same_map(plays: Array, key: String, xa: float, xb: float) -> String:
	var step: float = TUNABLE[key][1]
	var maps := {}
	for p in plays:
		var v = p.settings.get(key)
		if v == null or String(p.get("map", "")) == "":
			continue
		var x := _tx(key, v)
		var side := -1
		if abs(x - xa) <= step * 0.75:
			side = 0
		elif abs(x - xb) <= step * 0.75:
			side = 1
		if side < 0:
			continue
		if not maps.has(p.map):
			maps[p.map] = [[0, 0], [0, 0]]
		maps[p.map][side][0] += p.rows.size()
		maps[p.map][side][1] += int(p.hits)
	var both := 0
	var ha := 0.0
	var hb := 0.0
	for m in maps:
		var e: Array = maps[m]
		if e[0][0] >= 30 and e[1][0] >= 30:
			both += 1
			ha += float(e[0][1]) / e[0][0]
			hb += float(e[1][1]) / e[1][0]
	if both < 2:
		return ""
	return "On the %d maps you played with both, you hit %.1f%% vs %.1f%%." % [both, ha / both * 100.0, hb / both * 100.0]

# Approach rate and distance from your history, as time on screen (log) and
# approach rate (log), each with a curve when you've played 3+ values.
static func _history_approach(plays: Array, model: Dictionary, cur: Dictionary):
	if cur.get("vis") == null or float(cur.vis) <= 0:
		return null
	var sv := _support(plays, "vis", "spawn_distance")
	var sa := _support(plays, "ar", "approach_rate")
	var uv := []
	var ua := []
	for b in sv:
		if sv[b].plays >= 2 and sv[b].notes >= 300:
			uv.append(b)
	for b in sa:
		if sa[b].plays >= 2 and sa[b].notes >= 300:
			ua.append(b)
	uv.sort()
	ua.sort()
	var use_v: bool = uv.size() >= 2
	var use_a: bool = ua.size() >= 2
	if not use_v and not use_a:
		return null
	var qv: bool = uv.size() >= 3
	var qa: bool = ua.size() >= 3
	var lv: float = sv[uv[0]].x if use_v else 0.0
	var hv: float = sv[uv[-1]].x if use_v else 0.0
	var la: float = sa[ua[0]].x if use_a else 0.0
	var ha: float = sa[ua[-1]].x if use_a else 0.0
	var mid_v: float = (lv + hv) / 2.0
	var mid_a: float = (la + ha) / 2.0
	var extra := []
	for g in model.groups:
		var p: Dictionary = plays[g.play]
		var xv: float = log(p.vis) if p.read_ok and p.vis > 0 else mid_v
		var xa: float = log(p.ar) if p.read_ok and p.ar > 0 else mid_a
		extra.append(_ap_cols(xv, xa, use_v, use_a, qv, qa))
	var fit = _fit(model, extra)
	if fit == null:
		return null
	var ref := _reference(model, plays)
	var cxv: float = log(float(cur.vis))
	var cxa: float = log(max(float(cur.approach_rate), 0.1))
	var ccv: float = clamp(cxv, lv, hv) if use_v else cxv
	var cca: float = clamp(cxa, la, ha) if use_a else cxa
	var vs := [ccv]
	var as_ := [cca]
	if use_v:
		vs = []
		for i in range(13):
			vs.append(lerp(lv, hv, i / 12.0) if qv else (lv if i < 6 else hv))
	if use_a:
		as_ = []
		for i in range(13):
			as_.append(lerp(la, ha, i / 12.0) if qa else (la if i < 6 else ha))
	var best := [ccv, cca]
	var best_rate: float = -1.0
	for xv in vs:
		for xa in as_:
			var r := _hit_rate(fit, ref, _ap_cols(xv, xa, use_v, use_a, qv, qa))
			if r > best_rate:
				best_rate = r
				best = [xv, xa]
	var ce := _ap_cols(ccv, cca, use_v, use_a, qv, qa)
	var be := _ap_cols(best[0], best[1], use_v, use_a, qv, qa)
	var cur_rate := _hit_rate(fit, ref, ce)
	var gain: float = best_rate - cur_rate
	var z: float = _diff_eta(fit, model.base_k, be, ce) / max(_diff_se(fit, model.base_k, be, ce), 1e-6)
	var vis_to: float = exp(best[0])
	var ar_to: float = exp(best[1])
	var fade: float = float(cur.get("fade_length", 0.0))
	var dist_to: float = vis_to * ar_to / (1.0 - FADE_SEEN * clamp(fade, 0.0, 1.0))
	var ar_new = _round("approach_rate", ar_to)
	var dist_new = _round("spawn_distance", dist_to)
	var same_ar: bool = _same("approach_rate", ar_new, cur.approach_rate)
	var same_d: bool = _same("spawn_distance", dist_new, cur.spawn_distance)
	if same_ar and same_d:
		if abs(cxv - ccv) > 1e-6 or abs(cxa - cca) > 1e-6:
			return null
		# clearly better than the furthest other setting you've played?
		var ov: float = hv if abs(hv - ccv) > abs(lv - ccv) else lv
		var oa: float = ha if abs(ha - cca) > abs(la - cca) else la
		var oe := _ap_cols(ov if use_v else ccv, oa if use_a else cca, use_v, use_a, qv, qa)
		var zk: float = _diff_eta(fit, model.base_k, ce, oe) / max(_diff_se(fit, model.base_k, ce, oe), 1e-6)
		if zk >= 1.64:
			return {"note": "Approach: your approach rate %s and distance %s (notes on screen for %.2f s) are the best of what you've played with." % [_fmt("approach_rate", cur.approach_rate), _fmt("spawn_distance", cur.spawn_distance), float(cur.vis)]}
		return {"note": "Approach: no clear difference yet between the approach settings you've played with (now %.2f s on screen)." % float(cur.vis)}
	var conf := _conf(z, gain)
	if conf == "":
		if z >= 1.0 and gain >= 0.004:
			return {"note": "Approach: your plays lean toward notes on screen for %.2f s at approach rate %s (%+.1f%% notes), but it isn't clear yet." % [vis_to, _fmt("approach_rate", ar_new), gain * 100.0]}
		return null
	var changes := {}
	if not same_ar:
		changes["approach_rate"] = ar_new
	if not same_d:
		changes["spawn_distance"] = dist_new
	var vis_changed: bool = abs(vis_to - float(cur.vis)) > 0.03 * max(float(cur.vis), 0.01)
	var what := ""
	if vis_changed:
		what = "notes on screen for %.2f s (now %.2f s)" % [vis_to, float(cur.vis)]
		if use_a and not same_ar:
			what += " coming in at approach rate %s (now %s)" % [_fmt("approach_rate", ar_new), _fmt("approach_rate", cur.approach_rate)]
	else:
		what = "approach rate %s (now %s) with notes still on screen for %.2f s" % [_fmt("approach_rate", ar_new), _fmt("approach_rate", cur.approach_rate), float(cur.vis)]
	var why := "On your usual notes, %s hit %.1f%% more notes, from %d plays with different approach settings compared like with like." % [
		what, gain * 100.0, plays.size()]
	return _rec(changes, cur, conf, why, "history", gain)

static func _ap_cols(xv: float, xa: float, use_v: bool, use_a: bool, qv: bool, qa: bool) -> Array:
	var c := []
	if use_v:
		c.append(xv)
		if qv:
			c.append(xv * xv)
	if use_a:
		c.append(xa)
		if qa:
			c.append(xa * xa)
	return c

# ------------------------------------------------------------------ now

# Your plays with the settings you have now: for aiming (sensitivity /
# absolute scale) and for reading (approach and distance), each with the
# newest RECENT. When there are too few, the newest plays with the settings you
# used most lately (and what those were).
static func _current_plays(plays: Array, cur: Dictionary) -> Dictionary:
	var abs_mode: bool = bool(cur.get("absolute_mode", false))
	var aim_key: String = "absolute_scale" if abs_mode else "sensitivity"
	var motor := _pick(plays, cur, [aim_key], abs_mode, "move_ok")
	var reading := _pick(plays, cur, ["approach_rate", "spawn_distance", "fade_length"], abs_mode, "read_ok")
	return {"motor": motor, "reading": reading}

static func _pick(plays: Array, cur: Dictionary, keys: Array, abs_mode: bool, ok_flag: String) -> Dictionary:
	var picked := []
	for i in range(plays.size() - 1, -1, -1):
		var p: Dictionary = plays[i]
		if not p.get(ok_flag, true) or bool(p.settings.get("absolute_mode", false)) != abs_mode:
			continue
		var same := true
		for k in keys:
			if cur.get(k) == null or p.settings.get(k) == null or not _close(k, p.settings[k], cur[k]):
				same = false
		if same:
			picked.push_front(p)
			if picked.size() >= RECENT:
				break
	var notes := 0
	for p in picked:
		notes += p.rows.size()
	if picked.size() >= CUR_PLAYS and notes >= CUR_NOTES:
		return {"plays": picked, "notes": notes, "values": _values(cur, keys), "current": true}
	# not enough with your settings now: the settings you used most lately
	var counts := {}
	var newest := []
	for i in range(max(0, plays.size() - RECENT), plays.size()):
		var p: Dictionary = plays[i]
		if not p.get(ok_flag, true) or bool(p.settings.get("absolute_mode", false)) != abs_mode:
			continue
		var sig := _sig(p.settings, keys)
		counts[sig] = int(counts.get(sig, 0)) + p.rows.size()
		newest.append(p)
	var top := ""
	var top_n := 0
	for s in counts:
		if counts[s] > top_n:
			top_n = counts[s]
			top = s
	var sel := []
	for p in newest:
		if _sig(p.settings, keys) == top:
			sel.append(p)
	var vals := {}
	if not sel.empty():
		vals = _values(sel[-1].settings, keys)
	return {"plays": sel, "notes": top_n, "values": vals, "current": false, "have": notes}

static func _sig(s: Dictionary, keys: Array) -> String:
	var parts := []
	for k in keys:
		var v = s.get(k)
		parts.append(str(_bucket_of(k, v)) if v != null and TUNABLE.has(k) else str(v))
	return PoolStringArray(parts).join("|")

static func _values(s: Dictionary, keys: Array) -> Dictionary:
	var d := {}
	for k in keys:
		d[k] = s.get(k)
	return d

static func _close(key: String, a, b) -> bool:
	if TUNABLE.has(key) and TUNABLE[key][5] == "log":
		return abs(log(max(float(a), 1e-4)) - log(max(float(b), 1e-4))) <= 0.02
	if typeof(a) == TYPE_BOOL or typeof(b) == TYPE_BOOL:
		return bool(a) == bool(b)
	return abs(float(a) - float(b)) <= 0.011

# Aiming (relative: sensitivity; absolute: absolute scale).
static func _motor(sel: Dictionary, cur: Dictionary):
	var plays: Array = sel.plays
	var abs_mode: bool = bool(cur.get("absolute_mode", false))
	var key: String = "absolute_scale" if abs_mode else "sensitivity"
	var label: String = TUNABLE[key][0]
	if not sel.current:
		if plays.empty():
			return null
		var was = sel.values.get(key)
		return {"note": "%s: you changed it to %s and %s. Play a few more maps with it and Generate again to see how it suits you." % [label, _fmt(key, cur.get(key)), _have_text(int(sel.get("have", 0)))]}
	var n := 0
	var over := 0
	var late := 0
	var near := 0
	var over_amt := []
	var leads := []
	var big_late := 0
	var big_n := 0
	for p in plays:
		var vis_ms: float = float(p.get("vis", -1.0)) * 1000.0
		for f in p.f:
			if f.jump < 0.8 or f.gap < 90.0:
				continue
			# a note that only showed up after the one before: being late on
			# it is reading (distance), not aiming
			if vis_ms > 0.0 and vis_ms < f.gap - 30.0:
				continue
			n += 1
			var big: bool = f.jump >= 1.8
			if big:
				big_n += 1
			match f.kind:
				PT.KIND_OVERSHOOT:
					over += 1
					if f.over > 1.0:
						over_amt.append(f.over - 1.0)
				PT.KIND_LATE:
					late += 1
					if big:
						big_late += 1
				PT.KIND_NEAR:
					near += 1
				PT.KIND_HIT:
					if f.arrive >= 0 and big:
						leads.append(f.arrive)
					if f.over > 1.0:
						over_amt.append(f.over - 1.0) # slid out and came back
	if n < 300:
		return null
	leads.sort()
	over_amt.sort()
	var lead_med: float = leads[leads.size() / 2] if not leads.empty() else -1.0
	var over_med: float = over_amt[over_amt.size() / 2] if not over_amt.empty() else 0.0
	# (missing by a hair is neither: FOV / cursor size look at those)
	var ov: float = over
	var share_over: float = ov / max(ov + late, 1.0)
	var curv: float = float(cur.get(key, 1.0))
	var miss: float = over + late + near
	if miss / n < 0.01:
		return {"note": "%s: you aim cleanly with %s (only %.1f%% of jumps missed by overshooting or arriving late)." % [label, _fmt(key, curv), miss / n * 100.0]}
	# too fast: overshoots dominate, and you slide well past notes
	if share_over >= 0.65 and over / float(n) >= 0.008:
		var f: float = clamp(0.03 + (share_over - 0.65) * 0.2 + min(over_med, 1.0) * 0.04, 0.03, 0.12)
		var conf := "medium" if over / float(n) >= 0.02 and plays.size() >= 5 else "try"
		var why := "With %s %s, %d%% of your aiming misses are overshoots (you get on the note and slide off before it comes) against %d%% late%s. A slightly lower %s should let you stop on notes." % [
			label, _fmt(key, curv), int(round(share_over * 100.0)), int(round((1.0 - share_over) * 100.0)),
			(", and when you slide off you go about %.1f hitboxes past" % (over_med + 1.0)) if over_med > 0.15 else "", label.to_lower()]
		return _rec({key: curv * (1.0 - f)}, cur, conf, why, "now", over / float(n) * 0.5)
	# too slow: late on big jumps although you get going in time
	if share_over <= 0.35 and late / float(n) >= 0.008 and big_n >= 80 and float(big_late) / big_n >= 0.015 and (lead_med < 0 or lead_med < 90.0):
		var f2: float = clamp(0.03 + (0.35 - share_over) * 0.2, 0.03, 0.12)
		var conf2 := "medium" if late / float(n) >= 0.02 and plays.size() >= 5 else "try"
		var why2 := "With %s %s, %d%% of your aiming misses are late (still on your way when the note comes), mostly on big jumps (%d%% of them), and you reach big jumps only ~%d ms early. A slightly higher %s gets you there in time." % [
			label, _fmt(key, curv), int(round((1.0 - share_over) * 100.0)), int(round(float(big_late) / big_n * 100.0)), int(max(lead_med, 0)), label.to_lower()]
		return _rec({key: curv * (1.0 + f2)}, cur, conf2, why2, "now", late / float(n) * 0.5)
	return {"note": "%s %s: your overshoots and late arrivals are balanced (%d%% / %d%%), so it suits you; your misses come from elsewhere." % [label, _fmt(key, curv), int(round(share_over * 100.0)), int(round((1.0 - share_over) * 100.0))]}

# Reading: distance (time on screen) and approach rate (spacing).
static func _have_text(n: int) -> String:
	return "haven't played with it yet" if n <= 0 else "have only %d notes with it so far" % n

static func _reading(sel: Dictionary, cur: Dictionary) -> Array:
	var out := []
	var plays: Array = sel.plays
	if cur.get("vis") == null or float(cur.vis) <= 0:
		return out
	if not sel.current:
		if not plays.empty():
			out.append({"note": "Approach: you changed it (now approach rate %s, distance %s, notes on screen %.2f s) and %s; play a few maps with it before judging it." % [
				_fmt("approach_rate", cur.approach_rate), _fmt("spawn_distance", cur.spawn_distance), float(cur.vis), _have_text(int(sel.get("have", 0)))]})
		return out
	var vis: float = float(cur.vis) * 1000.0 # ms
	var ar: float = float(cur.approach_rate)
	var dist: float = float(cur.spawn_distance)
	# reaction: notes that appeared after you'd finished the one before
	var reacts := []
	var late_n := [0, 0] # [appeared after the previous note, appeared before]
	var late_m := [0, 0]
	var gaps_late := []
	var n := 0
	var miss := 0
	var early := 0
	var skip := 0
	var early_gaps := []
	var quick_n := 0
	var quick_es := 0
	for p in plays:
		for f in p.f:
			n += 1
			if f.kind != PT.KIND_HIT:
				miss += 1
			if f.kind == PT.KIND_EARLY:
				early += 1
				early_gaps.append(f.gap)
			elif f.kind == PT.KIND_SKIP:
				skip += 1
				early_gaps.append(f.gap)
			if f.gap < 200.0:
				quick_n += 1
				if f.kind == PT.KIND_EARLY or f.kind == PT.KIND_SKIP:
					quick_es += 1
			if f.gap <= 0 or f.jump < 0.5:
				continue
			var appeared_late: bool = vis < f.gap - 30.0
			if appeared_late and f.react >= 0:
				var r: float = f.react - (f.gap - vis)
				if r > 60.0 and r < 900.0:
					reacts.append(r)
			var side := 0 if appeared_late else 1
			if f.cps >= 1.5:
				late_n[side] += 1
				if f.kind == PT.KIND_LATE or f.kind == PT.KIND_SKIP:
					late_m[side] += 1
					if appeared_late:
						gaps_late.append(f.gap)
	if n < 400:
		return out
	reacts.sort()
	var react: float = reacts[reacts.size() / 2] if reacts.size() >= 15 else -1.0
	# 1. distance: notes showing up too late for you
	var rate_late: float = float(late_m[0]) / max(late_n[0], 1)
	var rate_ok: float = float(late_m[1]) / max(late_n[1], 1)
	var short_vis: bool = react > 0 and vis < react + 260.0
	if late_n[0] >= 40 and late_m[0] >= 6 and (rate_late - rate_ok >= 0.03 or short_vis):
		gaps_late.sort()
		var want: float = gaps_late[int(gaps_late.size() * 0.75)] + 40.0 if not gaps_late.empty() else vis * 1.25
		if react > 0:
			want = max(want, react + 300.0)
		want = clamp(want, vis * 1.1, vis * 1.5)
		var nd: float = dist * want / vis
		var conf := "medium" if late_m[0] >= 15 and rate_late - rate_ok >= 0.05 else "try"
		var why := "Notes are readable for %.2f s with your settings. On notes that only showed up after you'd finished the one before, you were late %d%% of the time, against %d%% on notes you could see coming%s." % [
			vis / 1000.0, int(round(rate_late * 100.0)), int(round(rate_ok * 100.0)),
			(" (your reaction time to a new note is about %d ms)" % int(react)) if react > 0 else ""]
		var fade: float = clamp(float(cur.get("fade_length", 0.0)), 0.0, 1.0)
		var gain_r: float = (rate_late - rate_ok) * float(late_n[0]) / max(n, 1)
		if fade >= 0.25:
			# the fade-in hides notes for part of their way in: less of it
			# gives the time back without changing anything else
			var full: float = dist / ar * 1000.0
			var nf: float = (1.0 - want / full) / FADE_SEEN
			if nf >= 0.0:
				nf = min(nf, fade - 0.1)
				why += " Your fade-in (%s) keeps notes invisible for part of their way in; with less of it (%s) they're readable for about %.2f s, with the same speed and spacing." % [
					_fmt("fade_length", fade), _fmt("fade_length", nf), _vis_time(dist, ar, nf)]
				out.append(_rec({"fade_length": nf}, cur, conf, why, "now", gain_r))
			else:
				var nd0: float = want / 1000.0 * ar
				why += " Your fade-in (%s) keeps notes invisible for part of their way in: with no fade-in and a bit more distance (same approach rate, so the same speed and spacing) they're readable for about %.2f s." % [
					_fmt("fade_length", fade), want / 1000.0]
				out.append(_rec({"fade_length": 0.0, "spawn_distance": nd0}, cur, conf, why, "now", gain_r))
			return out
		why += " More distance (same approach rate, so the same speed and spacing) shows notes sooner: about %.2f s." % (want / 1000.0)
		out.append(_rec({"spawn_distance": nd}, cur, conf, why, "now", gain_r))
		return out
	# 2. approach rate: leaving notes early / skipping them in quick runs
	var es: float = early + skip
	if miss >= 20 and es / max(miss, 1) >= 0.3 and quick_n >= 60 and float(quick_es) / quick_n >= 0.02:
		var f2: float = clamp(0.1 + (es / miss - 0.3) * 0.3, 0.1, 0.25)
		var nar: float = ar * (1.0 + f2)
		var nd2: float = dist * (1.0 + f2) # same time on screen
		var conf2 := "medium" if es >= 20 and float(quick_es) / quick_n >= 0.04 else "try"
		var why2 := "%d%% of your misses are leaving a note for the next one too early or skipping it, mostly in quick runs (%d%% of notes under 200 ms apart). A higher approach rate spreads notes further apart as they come in, so the one you're on is easier to tell from the next; the distance goes up with it to keep them on screen just as long (%.2f s)." % [
			int(round(es / miss * 100.0)), int(round(float(quick_es) / quick_n * 100.0)), vis / 1000.0]
		out.append(_rec({"approach_rate": nar, "spawn_distance": nd2}, cur, conf2, why2, "now", es / max(n, 1) * 0.5))
		return out
	# 3. a lot on screen at once and you lose track: shorter time on screen
	var gaps := []
	for p in plays:
		for f in p.f:
			if f.gap > 0:
				gaps.append(f.gap)
	gaps.sort()
	var med_gap: float = gaps[gaps.size() / 2] if not gaps.empty() else 300.0
	var on_screen: float = vis / max(med_gap, 50.0)
	if on_screen >= 9.0 and miss >= 20 and float(skip) / max(miss, 1) >= 0.15:
		var want2: float = clamp(med_gap * 7.0, vis * 0.75, vis * 0.9)
		var why3 := "With notes on screen for %.2f s you usually see ~%d notes at once on your maps, and %d%% of your misses are notes you skipped. A bit less distance (%.2f s on screen) shows fewer at a time." % [
			vis / 1000.0, int(on_screen), int(round(float(skip) / miss * 100.0)), want2 / 1000.0]
		out.append(_rec({"spawn_distance": dist * want2 / vis}, cur, "try", why3, "now", float(skip) / max(n, 1) * 0.3))
		return out
	out.append({"note": "Approach: with notes on screen for %.2f s (approach rate %s, distance %s) you read notes in time%s and rarely lose track of which note is next, so these suit you." % [
		vis / 1000.0, _fmt("approach_rate", ar), _fmt("spawn_distance", dist), (" (reaction ~%d ms)" % int(react)) if react > 0 else ""]})
	return out

# Nothing to change yet: one thing to try, so your history can compare next
# time. Only for a setting you've only ever played one value of (so it can't
# keep nudging the same setting), in the direction your misses lean.
static func _experiments(mine: Dictionary, cur: Dictionary, hist: Dictionary, plays: Array, taken: Dictionary) -> Array:
	var out := []
	# not while a change you just made is still being tried out (it would mix
	# the two up)
	if not mine.motor.current or not mine.reading.current:
		return out
	var abs_mode: bool = bool(cur.get("absolute_mode", false))
	var key: String = "absolute_scale" if abs_mode else "sensitivity"
	if not hist.has(key) and not taken.has(key) and _tried(plays, key) < 2:
		var over := 0
		var late := 0
		for p in mine.motor.plays:
			for f in p.f:
				if f.kind == PT.KIND_OVERSHOOT or f.kind == PT.KIND_NEAR:
					over += 1
				elif f.kind == PT.KIND_LATE:
					late += 1
		var down: bool = over >= late
		var v: float = float(cur.get(key, 1.0))
		out.append(_rec({key: v * (0.93 if down else 1.07)}, cur, "try",
			"Nothing in how you play points one way yet, and you've only played with this %s. Play about 5 maps with it %d%% %s (your misses lean slightly toward %s); when you Generate again, your history can compare the two on equal terms." % [
				TUNABLE[key][0].to_lower(), 7, "lower" if down else "higher", "overshooting" if down else "arriving late"], "test", 0.0))
	if not hist.has("approach") and _tried(plays, "approach_rate") < 2 and not taken.has("approach_rate") and not taken.has("spawn_distance") and not taken.has("fade_length"):
		var ar: float = float(cur.approach_rate)
		var dist: float = float(cur.spawn_distance)
		out.append(_rec({"approach_rate": ar * 1.15, "spawn_distance": dist * 1.15}, cur, "try",
			"Nothing in how you read notes points one way yet, and you've only played with this approach rate. Play about 5 maps with it 15% higher (distance up as much, so notes stay on screen as long); then Generate again and your history can compare.", "test", 0.0))
	return out

# ------------------------------------------------------------------ camera, grid, FOV, cursor

static func _look(plays: Array, cur: Dictionary, hist: Dictionary) -> Array:
	var out := []
	var abs_mode: bool = bool(cur.get("absolute_mode", false))
	# camera / grid movement: touch players (the finger has to go where the
	# note is on the screen, which the camera moving shifts)
	if abs_mode and not bool(cur.get("cam_unlock", false)) and not hist.has("parallax") and not hist.has("grid_parallax"):
		var mv := _pick(plays, cur, ["parallax", "grid_parallax", "absolute_scale"], abs_mode, "move_ok")
		if mv.current:
			var r = _parallax(mv, cur)
			if r != null:
				out.append(r)
	# FOV and cursor size (Sound Space Mode uses its own during songs)
	if not bool(cur.get("sound_space_mode", false)) and not hist.has("fov") and not hist.has("cursor_scale"):
		var vw := _pick(plays, cur, ["fov", "cursor_scale"], abs_mode, "move_ok")
		if vw.current:
			var r2 = _precision(vw, cur, abs_mode)
			if r2 != null:
				out.append(r2)
	return out

static func _cell_xy(cell: String) -> Vector2:
	var p := cell.split(",")
	return Vector2(int(p[0]), int(p[1])) if p.size() == 2 else Vector2(1, 1)

static func _mean_se(a: Array) -> Array:
	var n := a.size()
	if n == 0:
		return [0.0, 1e9]
	var m := 0.0
	for v in a:
		m += v
	m /= n
	var v2 := 0.0
	for v in a:
		v2 += (v - m) * (v - m)
	return [m, sqrt(v2 / max(n - 1, 1) / n)]

# Outer squares against the middle ones, on jumps of the same speed:
# [hit rate difference (middle - outer), outer notes]
static func _outer_gap(plays: Array) -> Array:
	var b := {}
	for p in plays:
		for f in p.f:
			var c := _cell_xy(f.cell)
			if c.x < 0 or c.x > 2 or c.y < 0 or c.y > 2:
				continue
			var outer: bool = c.x != 1 and c.y != 1 # corners
			var k := _sbin(f.cps)
			if not b.has(k):
				b[k] = [0, 0, 0, 0] # outer n, outer hits, middle n, middle hits
			var e: Array = b[k]
			var hit: bool = f.kind == PT.KIND_HIT
			if outer:
				e[0] += 1
				e[1] += 1 if hit else 0
			else:
				e[2] += 1
				e[3] += 1 if hit else 0
	var num := 0.0
	var w := 0.0
	var on := 0
	for k in b:
		var e: Array = b[k]
		if e[0] < 20 or e[2] < 20:
			continue
		var d: float = float(e[3]) / e[2] - float(e[1]) / e[0]
		num += d * e[0]
		w += e[0]
		on += e[0]
	return [num / w if w > 0 else 0.0, on]

static func _parallax(sel: Dictionary, cur: Dictionary):
	var plays: Array = sel.plays
	var par: float = float(cur.get("parallax", 0.0))
	var gpar: float = float(cur.get("grid_parallax", 0.0))
	var move: float = (abs(par) + abs(gpar)) * 0.025 # grid units the view shifts at an outer square
	var notes := 0
	var inward := []
	var hbs := 0.57
	for p in plays:
		hbs = float(p.get("hbs", hbs))
		for f in p.f:
			notes += 1
			if f.kind != PT.KIND_HIT:
				continue
			var c := _cell_xy(f.cell)
			# where in the hitbox you hit (-1..1): towards the middle is +
			if c.x == 0:
				inward.append(f.offx)
			elif c.x == 2:
				inward.append(-f.offx)
			if c.y == 0:
				inward.append(-f.offy)
			elif c.y == 2:
				inward.append(f.offy)
	if notes < LOOK_NOTES or inward.size() < 200:
		return null
	var ms := _mean_se(inward)
	var bias: float = ms[0]
	var z: float = bias / max(ms[1], 1e-6)
	var og := _outer_gap(plays)
	var shift_pct: int = int(round(move / max(hbs * 2.0, 0.1) * 100.0)) # of a note's width
	if move <= 0.0:
		if bias >= 0.12 and z >= 3.0:
			return {"note": "Camera: you hit outer notes on their inner side (%d%% of the way to the hitbox edge on average), but your camera and grid don't move, so it isn't parallax; it's how you reach for them." % int(round(bias * 100.0))}
		return null
	if bias >= 0.1 and z >= 3.0:
		var changes := {}
		var to_par: float = par * 0.5
		var txt := ""
		if gpar > 0.0:
			changes["grid_parallax"] = 0.0
			txt = "Grid parallax moves the notes themselves with your cursor; without it they stay where your finger expects them"
			if par >= 4.0:
				changes["parallax"] = to_par
				txt += ", and half the camera parallax (%s) moves the view half as much" % _fmt("parallax", to_par)
		else:
			changes["parallax"] = to_par
			txt = "Half the camera parallax (%s) moves the view half as much, so outer notes show up closer to where your finger has to go" % _fmt("parallax", to_par)
		var conf := "medium" if bias >= 0.15 and z >= 4.0 and inward.size() >= 400 else "try"
		var why := "On touch, the camera%s moves with your cursor, so notes on the outer squares show up about %d%% of a note's width away from where your finger has to go. Your hits on outer notes land on their inner side (%d%% of the way to the hitbox edge on average, from %d hits)%s. %s." % [
			" and grid" if gpar > 0.0 else "", shift_pct, int(round(bias * 100.0)), inward.size(),
			(", and you hit %.1f%% fewer corner notes than middle ones on jumps of the same speed" % (og[0] * 100.0)) if og[1] >= 150 and og[0] >= 0.015 else "",
			txt]
		return _rec(changes, cur, conf, why, "now", max(og[0], 0.0) * 0.3 + bias * 0.01)
	return {"note": "Camera: with camera parallax %s%s the view moves a bit with your cursor, and your hits on outer notes are centred (%+d%% towards the middle), so it doesn't throw your finger off." % [
		_fmt("parallax", par), (" and grid parallax %s" % _fmt("grid_parallax", gpar)) if gpar > 0.0 else "", int(round(bias * 100.0))]}

static func _precision(sel: Dictionary, cur: Dictionary, abs_mode: bool):
	var plays: Array = sel.plays
	var n := 0
	var miss := 0
	var near := 0
	var off := 0
	var hits := 0
	var graze := 0
	for p in plays:
		for f in p.f:
			n += 1
			match f.kind:
				PT.KIND_HIT:
					hits += 1
					if max(abs(f.offx), abs(f.offy)) >= 0.85:
						graze += 1
				PT.KIND_NEAR:
					near += 1
					miss += 1
				PT.KIND_OFF:
					off += 1
					miss += 1
				_:
					miss += 1
	if n < LOOK_NOTES or miss < 40:
		return null
	var cs: float = float(cur.get("cursor_scale", 1.0))
	var fov: float = float(cur.get("fov", 70.0))
	var near_share: float = float(near) / miss
	var graze_share: float = float(graze) / max(hits, 1)
	if near_share >= 0.35 and float(near) / n >= 0.012:
		var conf := "medium" if near_share >= 0.45 and near >= 60 else "try"
		var base := "%d%% of your misses are by a hair: the cursor gets to the note and stays just outside its hitbox%s." % [
			int(round(near_share * 100.0)), (", and %d%% of your hits are right on its edge" % int(round(graze_share * 100.0))) if graze_share >= 0.1 else ""]
		if cs >= 1.25:
			var to_cs: float = max(1.0, cs * 0.8)
			return _rec({"cursor_scale": to_cs}, cur, conf, base + " Your cursor is big (%s): it covers the edge of the note, so you can't see how close you are. A smaller one (%s) shows it." % [_fmt("cursor_scale", cs), _fmt("cursor_scale", to_cs)], "now", float(near) / n * 0.4)
		if not abs_mode and fov >= 62.0:
			var to_fov: float = max(50.0, fov * 0.9)
			return _rec({"fov": to_fov}, cur, conf, base + " A lower FOV (%s) makes the grid bigger on screen, so being a little off is easier to see and fix (your sensitivity stays the same)." % _fmt("fov", to_fov), "now", float(near) / n * 0.3)
	if cs <= 0.7 and float(off) / miss >= 0.35 and float(off) / n >= 0.02:
		var to_cs2: float = min(1.0, cs * 1.3)
		return _rec({"cursor_scale": to_cs2}, cur, "try", "%d%% of your misses are with the cursor nowhere near the note, and your cursor is small (%s). A bigger one (%s) is easier to keep track of." % [
			int(round(float(off) / miss * 100.0)), _fmt("cursor_scale", cs), _fmt("cursor_scale", to_cs2)], "now", float(off) / n * 0.2)
	return {"note": "FOV and cursor: only %d%% of your misses are by a hair (just outside the hitbox), so FOV %s and cursor size %s let you see where you are." % [
		int(round(near_share * 100.0)), _fmt("fov", fov), _fmt("cursor_scale", cs)]}

# How many values of a setting you've really played with (2+ plays each).
static func _tried(plays: Array, key: String) -> int:
	var b := {}
	for p in plays:
		var v = p.settings.get(key)
		if v != null:
			var k := _bucket_of(key, v)
			b[k] = int(b.get(k, 0)) + 1
	var n := 0
	for k in b:
		if b[k] >= 2:
			n += 1
	return n

# ------------------------------------------------------------------ for the screen

# The settings you've played with: plays, notes, raw hit rate, and how you did
# against what the model expects from the notes and maps alone.
static func _profiles(plays: Array, model, cur: Dictionary) -> Array:
	var keys := ["sensitivity", "absolute_scale", "approach_rate", "spawn_distance", "fov", "parallax"]
	var abs_cur: bool = bool(cur.get("absolute_mode", false))
	var fit = _fit(model, _empty_extra(model)) if model != null else null
	var by := {}
	var order := []
	for p in plays:
		var s: Dictionary = p.settings
		var abs_p: bool = bool(s.get("absolute_mode", false))
		var aim: String = ("abs scale " + _fmt("absolute_scale", s.get("absolute_scale", 1.0))) if abs_p else ("sens " + _fmt("sensitivity", s.get("sensitivity", 1.0)))
		var ar = s.get("approach_rate")
		var dist = s.get("spawn_distance")
		var vis: float = p.vis
		var label := "%s · AR %s · distance %s%s" % [aim, _fmt("approach_rate", ar) if ar != null else "?", _fmt("spawn_distance", dist) if dist != null else "?", (" (%.2f s)" % vis) if vis > 0 else ""]
		if not by.has(label):
			by[label] = {"label": label, "plays": 0, "notes": 0, "hits": 0, "exp": 0.0, "last": 0, "current": false}
			order.append(label)
		var e: Dictionary = by[label]
		e.plays += 1
		e.notes += p.rows.size()
		e.hits += int(p.hits)
		e.last = p.idx
		var same := abs_p == abs_cur
		for k in ["approach_rate", "spawn_distance"]:
			if cur.get(k) == null or s.get(k) == null or not _close(k, s[k], cur[k]):
				same = false
		var ak: String = "absolute_scale" if abs_cur else "sensitivity"
		if cur.get(ak) == null or s.get(ak) == null or not _close(ak, s[ak], cur[ak]):
			same = false
		if same:
			e.current = true
	# expected hits from the notes alone
	if fit != null:
		for g in model.groups:
			var p: Dictionary = plays[g.play]
			var s: Dictionary = p.settings
			# (same label as above)
			var abs_p: bool = bool(s.get("absolute_mode", false))
			var aim: String = ("abs scale " + _fmt("absolute_scale", s.get("absolute_scale", 1.0))) if abs_p else ("sens " + _fmt("sensitivity", s.get("sensitivity", 1.0)))
			var ar = s.get("approach_rate")
			var dist = s.get("spawn_distance")
			var label := "%s · AR %s · distance %s%s" % [aim, _fmt("approach_rate", ar) if ar != null else "?", _fmt("spawn_distance", dist) if dist != null else "?", (" (%.2f s)" % p.vis) if p.vis > 0 else ""]
			by[label].exp += g.n / (1.0 + exp(-clamp(_eta(fit, g.x, []), -30.0, 30.0)))
	var out := []
	for l in order:
		var e: Dictionary = by[l]
		e["rate"] = float(e.hits) / max(e.notes, 1)
		e["vs"] = (float(e.hits) - e.exp) / max(e.notes, 1) if fit != null else 0.0
		out.append(e)
	out.sort_custom(ProfileSorter, "newest_first")
	if out.size() > 6:
		out.resize(6)
	return out

class ProfileSorter:
	static func newest_first(a, b) -> bool:
		return a.last > b.last

static func _empty_extra(model: Dictionary) -> Array:
	var e := []
	for g in model.groups:
		e.append([])
	return e

static func _summary(plays: Array, mine: Dictionary, cur: Dictionary) -> String:
	var newest := plays.slice(max(0, plays.size() - RECENT), plays.size() - 1)
	var n := 0
	var h := 0
	for p in newest:
		n += p.rows.size()
		h += int(p.hits)
	var with_now: int = mine.motor.notes if mine.motor.current else 0
	var s := "%d plays and %d notes tracked, each with the settings it was played with. Your last %d plays: %.1f%% of notes hit." % [
		plays.size(), _count(plays), newest.size(), 100.0 * h / max(n, 1)]
	if mine.motor.current and mine.reading.current:
		s += " %d of your recent plays are with the settings you have now." % mine.reading.plays.size()
	else:
		s += " You've only just changed some settings, so the advice about how you play is about the ones you used before (it says which)."
	return s

static func _count(plays: Array) -> int:
	var t := 0
	for p in plays:
		t += p.rows.size()
	return t

static func _insights(mine: Dictionary, cur: Dictionary) -> Array:
	var out := []
	var sel: Dictionary = mine.motor
	var what := "your current settings"
	if not mine.motor.current and mine.reading.current:
		sel = mine.reading
		what = "this approach rate and distance"
	var plays: Array = sel.plays
	if plays.empty():
		return out
	var n := 0
	var kinds := [0, 0, 0, 0, 0, 0, 0]
	var bins := [[0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]]
	var cells := {}
	var leads := []
	var reacts := []
	var offx := 0.0
	var offy := 0.0
	var hits := 0
	for p in plays:
		for f in p.f:
			n += 1
			kinds[clamp(f.kind, 0, 6)] += 1
			var b := _sbin(f.cps)
			bins[b][0] += 1
			if f.kind == PT.KIND_HIT:
				bins[b][1] += 1
				hits += 1
				offx += f.offx
				offy += f.offy
				if f.arrive >= 0 and f.jump >= 1.0:
					leads.append(f.arrive)
			if f.react >= 0 and f.jump >= 1.0 and f.gap >= 150.0:
				reacts.append(f.react)
			if not cells.has(f.cell):
				cells[f.cell] = [0, 0]
			cells[f.cell][0] += 1
			if f.kind == PT.KIND_HIT:
				cells[f.cell][1] += 1
	var miss: int = n - hits
	if miss > 0:
		var parts := []
		var names := {PT.KIND_LATE: "late", PT.KIND_OVERSHOOT: "overshot", PT.KIND_NEAR: "just off", PT.KIND_EARLY: "left too early", PT.KIND_SKIP: "skipped", PT.KIND_OFF: "elsewhere"}
		for k in [PT.KIND_LATE, PT.KIND_OVERSHOOT, PT.KIND_NEAR, PT.KIND_EARLY, PT.KIND_SKIP, PT.KIND_OFF]:
			if kinds[k] > 0:
				parts.append("%d%% %s" % [int(round(100.0 * kinds[k] / miss)), names[k]])
		out.append("How you miss%s: %s." % [_with(sel, what), PoolStringArray(parts).join(", ")])
	var names2 := ["very slow", "slow", "medium", "fast", "very fast", "extreme", "insane"]
	var lines := []
	var worst := -1
	var worst_rate := 2.0
	for b in range(bins.size()):
		if bins[b][0] < 60:
			continue
		var r: float = float(bins[b][1]) / bins[b][0]
		lines.append("%s %.0f%%" % [names2[b], r * 100.0])
		if r < worst_rate:
			worst_rate = r
			worst = b
	if lines.size() >= 2:
		out.append("Hit rate by jump speed: " + PoolStringArray(lines).join(", ") + ".")
	leads.sort()
	reacts.sort()
	if leads.size() >= 30:
		out.append("You usually get to a note %d ms before it arrives%s." % [int(leads[leads.size() / 2]), (" and set off toward the next one ~%d ms after hitting a note" % int(reacts[reacts.size() / 2])) if reacts.size() >= 30 else ""])
	var worst_cell := ""
	var wr := 2.0
	for c in cells:
		if cells[c][0] < 60:
			continue
		var r: float = float(cells[c][1]) / cells[c][0]
		if r < wr:
			wr = r
			worst_cell = c
	if worst_cell != "" and wr < 0.97:
		out.append("You miss most in the %s of the grid (%.0f%% hit there)." % [_cell_name(worst_cell), wr * 100.0])
	if hits > 50:
		var bias := Vector2(offx, offy) / hits
		if bias.length() >= 0.18:
			var dir := ""
			if abs(bias.y) >= 0.12:
				dir += "low" if bias.y < 0 else "high"
			if abs(bias.x) >= 0.12:
				dir += ("-" if dir != "" else "") + ("left" if bias.x < 0 else "right")
			out.append("When you hit, you're usually a bit %s of the note's centre." % dir)
	return out

static func _with(sel: Dictionary, what: String) -> String:
	return " (your %d newest plays with %s)" % [sel.plays.size(), what] if sel.current else " (your plays with the settings you used before)"

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

# ------------------------------------------------------------------ helpers

# A suggestion: changes {setting: new value}, shown as "label: from to to".
static func _rec(changes: Dictionary, cur: Dictionary, conf: String, why: String, src: String, gain: float) -> Dictionary:
	var ch := {}
	var from := {}
	var labels := []
	for k in changes:
		ch[k] = _round(k, changes[k])
		from[k] = cur.get(k)
		labels.append(TUNABLE[k][0])
	var first: String = changes.keys()[0]
	return {
		"changes": ch, "from_all": from, "label": PoolStringArray(labels).join(" + "),
		"key": first, "from": from[first], "to": ch[first], # (single-setting view)
		"conf": conf, "why": why, "src": src, "gain": gain,
	}

static func _same(key: String, a, b) -> bool:
	if a == null or b == null:
		return false
	if typeof(a) == TYPE_BOOL or typeof(b) == TYPE_BOOL:
		return bool(a) == bool(b)
	return abs(float(a) - float(b)) < TUNABLE[key][2] * 0.5 + 1e-6

static func _round(key: String, v):
	if TUNABLE[key][5] == "bool":
		return bool(v) if typeof(v) == TYPE_BOOL else float(v) >= 0.5
	var r: float = TUNABLE[key][2]
	return clamp(stepify(float(v), r), TUNABLE[key][3], TUNABLE[key][4])

static func _fmt(key: String, v) -> String:
	if v == null:
		return "?"
	if typeof(v) == TYPE_BOOL:
		return "on" if v else "off"
	if key == "fade_length":
		return "%d%%" % int(round(float(v) * 100.0))
	var r: float = TUNABLE[key][2] if TUNABLE.has(key) else 0.01
	if r >= 1.0:
		return str(int(round(float(v))))
	if r >= 0.1:
		var x := stepify(float(v), r)
		return str(int(x)) if abs(x - round(x)) < 1e-6 else "%.1f" % x
	return "%.2f" % stepify(float(v), r)

static func fmt(key: String, v) -> String:
	return _fmt(key, v)

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

extends Reference

# BPM from the notes: finds the tempo (and offset) whose beat grid the notes'
# times fit, including tempo changes. Used by BPM Setup > "Detect From Notes".
#
# A note "fits" when it lands on a 1/1, 1/2, 1/3, 1/4, 1/6, 1/8, 1/12 or 1/16
# beat (within TOL ms). Every BPM whose grid the notes fit is a candidate
# (2x and 1/2x fit too); among the best ones, the one nearest a usual tempo
# (or the previous section's) is picked. Then a straight-line fit of note time
# against grid position gives the exact BPM and offset.
#
# Sections: starting at the first note, a tempo is found from the next
# WINDOW notes and followed forward until several notes in a row miss its
# grid; there a new tempo (timing point) starts.

const GRID := 48               # 1/48 beat: every allowed snap is a multiple
const TOL := 2.5               # ms
const WINDOW := 64             # notes used to find a section's tempo
const MISSES_TO_BREAK := 4     # notes in a row off the grid end a section
const MIN_BPM := 60.0
const MAX_BPM := 320.0
const MAX_SECTIONS := 48

# weight of a snap by its position in 1/48 beats (m % 48)
static func _weights() -> PoolRealArray:
	# simpler snaps count a bit more, so the simplest reading of the rhythm wins
	var by_den := {1: 1.0, 2: 0.96, 4: 0.92, 3: 0.9, 8: 0.84, 6: 0.8, 12: 0.72, 16: 0.72}
	var w := PoolRealArray()
	w.resize(GRID)
	for m in range(GRID):
		var den: int = GRID / _gcd(m, GRID)
		w[m] = float(by_den.get(den, 0.0))
	return w

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := a % b
		a = b
		b = t
	return a

# Note times in ms (any order, stacks allowed) -> unique sorted times.
static func unique_times(times: Array) -> Array:
	var t := times.duplicate()
	t.sort()
	var out := []
	for x in t:
		if out.empty() or float(x) - float(out[-1]) > 1.5:
			out.append(float(x))
	return out

# How well one tempo fits a list of intervals: sum of weights.
static func _score(period: float, iois: Array, w: PoolRealArray) -> float:
	var g := period / GRID
	var s := 0.0
	for d in iois:
		var m := int(round(d / g))
		if m <= 0:
			continue
		var e: float = abs(d - m * g)
		if e >= TOL:
			continue
		s += w[m % GRID] * (1.0 - e / TOL)
	return s

# Best BPM for these times (unique, sorted). Tempos a factor of 2 apart fit
# the same notes, so candidates are grouped by that "family"; the family whose
# grid fits best wins, and within it the tempo nearest `ref`.
static func _find_bpm(times: Array, ref: float, w: PoolRealArray, alts = null) -> float:
	var iois := []
	for i in range(1, times.size()):
		var d: float = times[i] - times[i - 1]
		if d > 0.0 and d <= 2500.0:
			iois.append(d)
	if iois.empty():
		return 0.0
	var cands := []
	var best := 0.0
	var bpm := MIN_BPM
	while bpm <= MAX_BPM:
		var sc := _score(60000.0 / bpm, iois, w)
		cands.append([bpm, sc])
		best = max(best, sc)
		bpm *= 1.001
	if best <= 0.0:
		return 0.0
	var peaks := []
	for i in range(cands.size()):
		var sc: float = cands[i][1]
		if sc < best * 0.85:
			continue
		if i > 0 and cands[i - 1][1] > sc:
			continue
		if i < cands.size() - 1 and cands[i + 1][1] >= sc:
			continue
		peaks.append(cands[i])
	# families: log2(bpm / ref) modulo 1
	var fam_best := {}
	var fam_of := []
	for pk in peaks:
		var l: float = log(pk[0] / ref) / log(2.0)
		var key: float = l - round(l)
		var found = null
		for f in fam_best:
			var dk: float = abs(key - f)
			dk = min(dk, 1.0 - dk)
			if dk < 0.004:
				found = f
				break
		if found == null:
			fam_best[key] = pk[1]
			fam_of.append(key)
		else:
			fam_best[found] = max(fam_best[found], pk[1])
			fam_of.append(found)
	var top := -1.0
	var top_key = null
	for f in fam_best:
		if fam_best[f] > top * 1.005:
			top = fam_best[f]
			top_key = f
	var pick := 0.0
	var pick_dist := INF
	for i in range(peaks.size()):
		if fam_of[i] != top_key:
			continue
		var dist: float = abs(log(peaks[i][0] / ref) / log(2.0))
		if dist < pick_dist:
			pick_dist = dist
			pick = peaks[i][0]
	if alts is Array:
		# other readings that fit almost as well (e.g. 3:2 or 4:3 of it)
		for f in fam_best:
			if f == top_key or fam_best[f] < top * 0.93:
				continue
			var near := 0.0
			var nd := INF
			for i in range(peaks.size()):
				if fam_of[i] == f:
					var d2: float = abs(log(peaks[i][0] / ref) / log(2.0))
					if d2 < nd:
						nd = d2
						near = peaks[i][0]
			alts.append(stepify(near, 0.1))
	# finer steps around it
	var fine_best := pick
	var fine_sc := -1.0
	var b2 := pick / 1.002
	while b2 <= pick * 1.002:
		var sc2 := _score(60000.0 / b2, iois, w)
		if sc2 > fine_sc:
			fine_sc = sc2
			fine_best = b2
		b2 *= 1.00005
	return fine_best

# Tempo and offset for a window of notes: offset from the first notes (where a
# slightly wrong BPM hasn't drifted yet), then fitted over more and more notes.
static func _fit_window(win: Array, ref: float, w: PoolRealArray, alts = null):
	var bpm := _find_bpm(win, ref, w, alts)
	if bpm <= 0.0:
		return null
	var period := 60000.0 / bpm
	var offset := _find_offset(win.slice(0, min(win.size(), 16) - 1), period, w)
	var r := [period, offset]
	for n in [16, 32, win.size()]:
		r = _refine(win.slice(0, min(win.size(), n) - 1), r[0], r[1], w)
	return r

# Offset (a beat's time) for this period: the phase that puts most notes on
# the simplest snaps.
static func _find_offset(times: Array, period: float, w: PoolRealArray) -> float:
	var g := period / GRID
	var sample := times
	if times.size() > 300:
		sample = []
		var step := float(times.size()) / 300.0
		var k := 0.0
		while int(k) < times.size():
			sample.append(times[int(k)])
			k += step
	var t0: float = times[0]
	var best_o := t0
	var best_s := -1.0
	var o := 0.0
	var o_step: float = max(0.5, period / 400.0)
	while o < period:
		var s := 0.0
		for t in sample:
			var x: float = (t - t0 - o) / g
			var m := int(round(x))
			var e: float = abs(x - m) * g
			if e < TOL:
				s += w[posmod(m, GRID)] * (1.0 - e / TOL)
		if s > best_s:
			best_s = s
			best_o = t0 + o
		o += o_step
	return best_o

# Least-squares fit of time = offset + grid position * period/48 over the notes
# that fit; returns [period, offset].
static func _refine(times: Array, period: float, offset: float, w: PoolRealArray) -> Array:
	for _pass in range(3):
		var g := period / GRID
		var n := 0.0
		var sx := 0.0
		var sy := 0.0
		var sxx := 0.0
		var sxy := 0.0
		for t in times:
			var x: float = (t - offset) / g
			var m := int(round(x))
			if abs(x - m) * g >= TOL or w[posmod(m, GRID)] <= 0.0:
				continue
			n += 1.0
			sx += m
			sy += t
			sxx += float(m) * m
			sxy += float(m) * t
		var den := n * sxx - sx * sx
		if n < 3.0 or abs(den) < 0.000001:
			break
		var b := (n * sxy - sx * sy) / den
		var a := (sy - b * sx) / n
		if b <= 0.0:
			break
		period = b * GRID
		offset = a
	return [period, offset]

static func _fits(t: float, period: float, offset: float, w: PoolRealArray) -> bool:
	var g := period / GRID
	var x := (t - offset) / g
	var m := int(round(x))
	return abs(x - m) * g < TOL and w[posmod(m, GRID)] > 0.0

# Tidy numbers: integer BPMs stay integers; the offset is refit for the BPM
# that is kept and moved to the beat at or before `first`.
static func _tidy(times: Array, period: float, offset: float, first: float, w: PoolRealArray) -> Dictionary:
	var bpm := 60000.0 / period
	if abs(bpm - round(bpm)) < 0.02:
		bpm = round(bpm)
	elif abs(bpm * 10.0 - round(bpm * 10.0)) < 0.02:
		bpm = round(bpm * 10.0) / 10.0
	else:
		bpm = stepify(bpm, 0.001)
	period = 60000.0 / bpm
	var g := period / GRID
	var sum := 0.0
	var n := 0
	for t in times:
		var x: float = (t - offset) / g
		var m := int(round(x))
		if abs(x - m) * g < TOL and w[posmod(m, GRID)] > 0.0:
			sum += t - m * g
			n += 1
	if n > 0:
		offset = sum / n
	offset += floor((first - offset + TOL) / period) * period
	return {"bpm": bpm, "ms": int(round(offset)), "period": period, "offset": offset}

# times: note times in ms. Returns {"points": [{bpm, ms}], "fit": 0..1,
# "notes": count} or {"error": text}.
static func detect(note_times: Array, ref_bpm: float = 150.0) -> Dictionary:
	var times := unique_times(note_times)
	if times.size() < 8:
		return {"error": "Not enough notes (at least 8 at different times)."}
	var w := _weights()
	var points := []
	var fitted := 0
	var i := 0
	var ref := ref_bpm
	var last_end_time := -INF
	var alts := []
	while i < times.size() - 1:
		if points.size() >= MAX_SECTIONS:
			return {"error": "These notes don't follow a steady beat (too many tempo changes)."}
		var win: Array = times.slice(i, min(times.size(), i + WINDOW) - 1)
		var r = _fit_window(win, ref, w, alts if points.empty() else null)
		if r == null:
			i += 1
			continue
		var period: float = r[0]
		var offset: float = r[1]
		# follow the tempo forward
		var j := i
		var misses := 0
		var first_miss := -1
		var since_refine := 0
		while j < times.size():
			if _fits(times[j], period, offset, w):
				misses = 0
				first_miss = -1
				since_refine += 1
				if since_refine >= 64:
					since_refine = 0
					r = _refine(times.slice(i, j), period, offset, w)
					period = r[0]
					offset = r[1]
			else:
				if misses == 0:
					first_miss = j
				misses += 1
				if misses >= MISSES_TO_BREAK:
					# maybe the first guess was off: try again over more notes
					var wider: Array = times.slice(i, min(times.size(), j + 32) - 1)
					var r2 = _fit_window(wider, 60000.0 / period, w)
					if r2 != null:
						var ok := 0
						for t in wider:
							if _fits(t, r2[0], r2[1], w):
								ok += 1
						if ok >= wider.size() * 0.95:
							period = r2[0]
							offset = r2[1]
							misses = 0
							first_miss = -1
							j += 1
							continue
					break
			j += 1
		var end := j if misses < MISSES_TO_BREAK else first_miss
		end = max(end, i + 2)
		var section: Array = times.slice(i, min(end, times.size()) - 1)
		r = _refine(section, period, offset, w)
		var first: float = section[0]
		var p := _tidy(section, r[0], r[1], first, w)
		# the point must come after the previous section's notes
		while p.offset <= last_end_time and p.offset + p.period <= first + 0.5:
			p.offset += p.period
		p.ms = int(round(p.offset))
		var n_fit := 0
		for t in section:
			if _fits(t, p.period, p.offset, w):
				n_fit += 1
		if section.size() >= 4 or points.empty():
			# same tempo and phase as the last point: one section
			var same := false
			if not points.empty():
				var last: Dictionary = points[-1]
				if abs(last.bpm - p.bpm) < 0.01:
					var beats: float = (p.offset - last.offset) / last.period
					same = abs(beats - round(beats)) * last.period < TOL
			if not same:
				points.append(p)
			fitted += n_fit
			ref = p.bpm
		last_end_time = section[-1]
		i = min(end, times.size())
	var out := []
	for p in points:
		out.append({"bpm": p.bpm, "ms": p.ms})
	return {"points": out, "fit": float(fitted) / times.size(), "notes": times.size(), "also": alts}

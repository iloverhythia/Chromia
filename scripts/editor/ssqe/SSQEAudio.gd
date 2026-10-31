extends Node
# The map editor's song analysis: the waveform on the track and DETECT BPM
# (Sound Space Quantum Editor Plus decodes the song in the browser; Chromia
# can't decode audio itself, so the song is read through the audio engine).
#
# Reading the song: it is played, silently, in several slices at once at 4x
# speed (each slice through a bus that records it, AudioEffectCapture). At 4x
# the recording holds every 4th sample, so a 3 minute song is read in about
# 6 seconds (8 slices) at ~11 kHz: plenty for the waveform (a sample every
# 2 ms) and for finding the beat. A second bus behind each one keeps only the
# bass (below 150 Hz, natively filtered) for finding kicks.
#
# Finding the beat: SSQE+'s findTempo / findDownbeat (automapper.js), on drum
# envelopes worked out here in 10 ms frames (bass rises for kicks, the rise
# of the rest for snares and hats).

const PITCH := 4.0
const LOW_DECIMATE := 8 # the bass bus is read every 8th sample (it holds nothing above 150 Hz)

var page
var _stream: AudioStream = null
var _segments: Array = [] # {player, raw_bus, low_bus, raw: PoolVector2Array, low: PoolVector2Array, need, done}
var _state := "idle" # idle, capturing, analysing, ready, failed
var _rate := 11025.0 # samples per second of the recording
var _length := 0.0   # song seconds
var _started := 0
var _thread: Thread = null
var _result = null   # analysis
var _token := 0
var _job = null # the recording, kept for an analysis on demand (browsers)
var waveform = null

func ready() -> bool:
	return _state == "ready"

func progress() -> float:
	match _state:
		"capturing":
			var got := 0.0
			var need := 0.0
			for sg in _segments:
				got += min(sg.got, sg.need)
				need += sg.need
			return 0.8 * got / max(need, 1.0)
		"analysing":
			return 0.85
		"ready":
			return 1.0
	return 0.0

func analyse(_path: String, stream):
	cancel()
	if not (stream is AudioStream) or stream.get_length() <= 0:
		_state = "failed"
		return
	_stream = stream
	_length = stream.get_length()
	_token += 1
	call_deferred("_start_capture", _token)

func cancel():
	_token += 1
	for sg in _segments:
		if is_instance_valid(sg.player):
			sg.player.stop()
			sg.player.queue_free()
	_segments = []
	if _state == "capturing":
		_state = "idle"
	waveform = null
	_result = null
	_job = null
	if _state != "analysing":
		_state = "idle"

# ------------------------------------------------------------------ reading the song

func _bus(name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i == -1:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	return i

func _capture_on(bus: int) -> AudioEffectCapture:
	for k in range(AudioServer.get_bus_effect_count(bus)):
		var e = AudioServer.get_bus_effect(bus, k)
		if e is AudioEffectCapture:
			return e
	var c := AudioEffectCapture.new()
	c.buffer_length = 6.0
	AudioServer.add_bus_effect(bus, c)
	return c

func _start_capture(token: int):
	if token != _token:
		return
	var sink := _bus("EdCapSink", "Master")
	AudioServer.set_bus_volume_db(sink, -80)
	AudioServer.set_bus_mute(sink, true)
	var count := 2 if Rhythia.device("mobile") else 8
	# short songs: fewer slices
	count = int(clamp(ceil(_length / 15.0), 1, count))
	var mix := AudioServer.get_mix_rate()
	_rate = mix / PITCH
	var slice := _length / count
	_segments = []
	for i in range(count):
		# raw -> below 3 kHz -> below 150 Hz (each bus records what reaches it)
		var low_bus := _bus("EdCapLow%d" % i, "EdCapSink")
		if AudioServer.get_bus_effect_count(low_bus) == 0:
			var lp := AudioEffectLowPassFilter.new()
			lp.cutoff_hz = 150.0
			lp.db = AudioEffectFilter.FILTER_24DB
			AudioServer.add_bus_effect(low_bus, lp)
		var mid_bus := _bus("EdCapMid%d" % i, "EdCapLow%d" % i)
		if AudioServer.get_bus_effect_count(mid_bus) == 0:
			var mp := AudioEffectLowPassFilter.new()
			mp.cutoff_hz = 3000.0
			mp.db = AudioEffectFilter.FILTER_24DB
			AudioServer.add_bus_effect(mid_bus, mp)
		var raw_bus := _bus("EdCap%d" % i, "EdCapMid%d" % i)
		var p := AudioStreamPlayer.new()
		p.stream = _stream
		p.bus = "EdCap%d" % i
		p.pitch_scale = PITCH
		add_child(p)
		_segments.append({
			"player": p, "raw_cap": _capture_on(raw_bus), "mid_cap": _capture_on(mid_bus), "low_cap": _capture_on(low_bus),
			"raw": [], "mid": [], "low": [], "got": 0, "from": i * slice,
			"need": int(ceil(slice * _rate)) if i < count - 1 else int(ceil((_length - i * slice) * _rate)), "done": false,
		})
	# all slices start together, each recording from its very first sample
	AudioServer.lock()
	for sg in _segments:
		sg.player.play(sg.from)
		sg.raw_cap.clear_buffer()
		sg.mid_cap.clear_buffer()
		sg.low_cap.clear_buffer()
	AudioServer.unlock()
	_state = "capturing"
	_started = OS.get_ticks_msec()

func _process(_d):
	if _state != "capturing":
		return
	var all_done := true
	for sg in _segments:
		if sg.done:
			continue
		# (pieces kept in a list: a PoolVector2Array in a Dictionary is a copy)
		var n: int = sg.raw_cap.get_frames_available()
		if n > 0:
			sg.raw.append(sg.raw_cap.get_buffer(n))
			sg.got += n
		var m: int = sg.low_cap.get_frames_available()
		if m > 0:
			sg.low.append(sg.low_cap.get_buffer(m))
		var mm: int = sg.mid_cap.get_frames_available()
		if mm > 0:
			sg.mid.append(sg.mid_cap.get_buffer(mm))
		if sg.got >= sg.need or (not sg.player.playing and n == 0 and OS.get_ticks_msec() - _started > 500):
			sg.done = true
			sg.player.stop()
		else:
			all_done = false
	if OS.get_ticks_msec() - _started > 240000:
		_state = "failed"
		cancel()
		return
	if all_done:
		_finish_capture()

func _finish_capture():
	var raw := PoolVector2Array()
	var mid := PoolVector2Array()
	var low := PoolVector2Array()
	for sg in _segments:
		var r := _joined(sg.raw, sg.need)
		raw.append_array(r)
		mid.append_array(_joined(sg.mid, r.size()))
		low.append_array(_joined(sg.low, r.size()))
		if is_instance_valid(sg.player):
			sg.player.queue_free()
	_segments = []
	_wave_raw = raw
	waveform = _make_waveform(raw)
	if page:
		page.on_waveform(waveform)
	_state = "analysing"
	var job := {"raw": raw, "mid": mid, "low": low, "rate": _rate, "token": _token}
	if OS.can_use_threads():
		_thread = Thread.new()
		_thread.start(self, "_analyse_thread", job)
	else:
		# (no threads in a browser: worked out when DETECT BPM asks, so mapping doesn't stall)
		_job = job
		_state = "ready"

# a slice's recorded pieces as one, exactly `size` long
static func _joined(pieces: Array, size: int) -> PoolVector2Array:
	var out := PoolVector2Array()
	for piece in pieces:
		out.append_array(piece)
	if out.size() > size:
		out.resize(size)
	while out.size() < size:
		out.append(Vector2())
	return out

func _analyse_thread(job: Dictionary):
	var r = _analyse(job)
	call_deferred("_analysed", r)

func _analysed(r):
	if _thread:
		_thread.wait_to_finish()
		_thread = null
	if r == null or int(r.token) != _token:
		if _state == "analysing":
			_state = "idle"
		return
	_result = r
	_state = "ready"

var _wave_raw := PoolVector2Array() # the recording, for a new level of detail

# Settings > Graphics > Waveform Level of Detail changed: make it again
func remake_waveform():
	if _wave_raw.empty():
		return
	var d := _wave_detail()
	if waveform is Dictionary and abs(float(waveform.res) - 1.0 / d / 100.0) < 0.0000001:
		return
	waveform = _make_waveform(_wave_raw)
	if page:
		page.on_waveform(waveform)

func _wave_detail() -> float:
	if page and page.ed and page.ed.s is Dictionary:
		return clamp(float(page.ed.s.get("waveformDetail", 5.0)), 1.0, 20.0)
	return 5.0

# Waveform.Load: a left/right sample pair every 1 / detail / 100 s (2 ms at
# the default 5), normalised to the peak
func _make_waveform(raw: PoolVector2Array) -> Dictionary:
	var res := 1.0 / _wave_detail() / 100.0
	var per := _rate * res
	var length := raw.size()
	var count := int(floor(length / per))
	var left := PoolRealArray()
	var right := PoolRealArray()
	left.resize(count)
	right.resize(count)
	var peak := 0.0
	for i in range(count):
		var v: Vector2 = raw[int(min(length - 1, round((i + 1) * per)))]
		left[i] = v.x
		right[i] = v.y
		peak = max(peak, max(abs(v.x), abs(v.y)))
	if peak > 0:
		for i in range(count):
			left[i] = left[i] / peak
			right[i] = right[i] / peak
	return {"res": res, "left": left, "right": right, "count": count}

# ------------------------------------------------------------------ the drums, in 10 ms frames

static func _percentile(arr: PoolRealArray, f: float) -> float:
	var a := Array(arr)
	if a.empty():
		return 0.0
	a.sort()
	return a[int(min(a.size() - 1, floor(a.size() * f)))]

static func _smooth(arr: PoolRealArray, radius: int) -> PoolRealArray:
	var n := arr.size()
	var out := PoolRealArray()
	out.resize(n)
	var sum := 0.0
	var count := 0
	for i in range(min(n, radius)):
		sum += arr[i]
		count += 1
	for i in range(n):
		if i + radius < n:
			sum += arr[i + radius]
			count += 1
		if i - radius - 1 >= 0:
			sum -= arr[i - radius - 1]
			count -= 1
		out[i] = sum / max(count, 1)
	return out

# a 10 ms frame's energy over the 23 ms from its start
static func _ahead(e: PoolRealArray) -> PoolRealArray:
	var n := e.size()
	var out := PoolRealArray()
	out.resize(n)
	for g in range(n):
		var a: float = e[g]
		var b: float = e[g + 1] if g + 1 < n else a
		var c: float = e[g + 2] if g + 2 < n else b
		out[g] = (a + b + 0.32 * c) / 2.32
	return out

# each band on the same scale
static func _norm(a: PoolRealArray) -> PoolRealArray:
	var p := _percentile(a, 0.97)
	if p <= 0:
		p = 1.0
	for i in range(a.size()):
		a[i] = min(2.0, a[i] / p)
	return a

static func _peaky(raw: PoolRealArray) -> PoolRealArray:
	var base := _smooth(raw, 12)
	var n := raw.size()
	var out := PoolRealArray()
	out.resize(n)
	for i in range(n):
		out[i] = max(0.0, raw[i] - base[i] * 1.05)
	var p := _percentile(out, 0.98)
	if p <= 0:
		p = 1.0
	for i in range(n):
		out[i] = min(1.5, out[i] / p)
	return out

func _analyse(job: Dictionary):
	var raw: PoolVector2Array = job.raw
	var midrec: PoolVector2Array = job.mid
	var low: PoolVector2Array = job.low
	var rate: float = job.rate
	var hop := rate / 100.0
	var frames := int(floor(raw.size() / hop))
	if frames < 100:
		return null
	# per 10 ms: energy of everything, of its rise (first difference: the highs) and of the bass
	var e_all := PoolRealArray()
	var e_hp := PoolRealArray()
	e_all.resize(frames)
	e_hp.resize(frames)
	var prev := 0.0
	var f := 0
	var next := hop
	var acc := 0.0
	var acc_hp := 0.0
	var n := raw.size()
	for i in range(n):
		if job.token != _token:
			return null
		var s: Vector2 = raw[i]
		var v := (s.x + s.y) * 0.5
		acc += v * v
		var d := v - prev
		acc_hp += d * d
		prev = v
		if i + 1 >= next:
			if f < frames:
				e_all[f] = acc / hop
				e_hp[f] = acc_hp / hop
			f += 1
			acc = 0.0
			acc_hp = 0.0
			next += hop
	# below 3 kHz (every 2nd sample is enough)
	var e_lo3k := PoolRealArray()
	e_lo3k.resize(frames)
	f = 0
	next = hop
	acc = 0.0
	var cnt := 0
	var mi := 0
	while mi < midrec.size():
		var ms: Vector2 = midrec[mi]
		var mv := (ms.x + ms.y) * 0.5
		acc += mv * mv
		cnt += 1
		mi += 2
		if mi >= next:
			if f < frames:
				e_lo3k[f] = acc / max(cnt, 1)
			f += 1
			acc = 0.0
			cnt = 0
			while next <= mi:
				next += hop
	# the bass every 5 ms (from the low-passed recording, every 8th sample)
	var blk := rate / 200.0
	var nb := int(floor(low.size() / blk))
	var e5 := PoolRealArray()
	e5.resize(nb)
	var bi := 0
	var lacc := 0.0
	var lcount := 0
	var lnext := blk
	var j := 0
	while j < low.size():
		var ls: Vector2 = low[j]
		var lv := (ls.x + ls.y) * 0.5
		lacc += lv * lv
		lcount += 1
		j += LOW_DECIMATE
		if j >= lnext:
			if bi < nb:
				e5[bi] = lacc / max(lcount, 1)
				bi += 1
			lacc = 0.0
			lcount = 0
			while lnext <= j:
				lnext += blk
	# kicks: the bass's energy over 20 ms, how sharply it rises, and only above what came just before
	var floor_e := _percentile(e5, 0.9) * 1e-3 + 1e-12
	var E := PoolRealArray()
	E.resize(frames)
	for g in range(frames):
		var q := int(floor((g * 10 + 12) / 5.0))
		var e := 0.0
		for k in range(q, q + 4):
			e += e5[k] if k >= 0 and k < nb else 0.0
		E[g] = log(e / 4 + floor_e) / log(10)
	var low_rise := PoolRealArray()
	low_rise.resize(frames)
	for g in range(min(9, frames)):
		low_rise[g] = 0.0
	for g in range(9, frames):
		var before := -1e9
		for k in range(g - 9, g - 2):
			before = max(before, E[k])
		low_rise[g] = max(0.0, E[g] - E[g - 2]) * clamp((E[g] - before + 0.4) / 0.6, 0, 1)
	# snares (the rest's rise) and hats (the highs' rise), log scaled
	var mid := PoolRealArray()
	var high := PoolRealArray()
	var rms := PoolRealArray()
	var band_low := PoolRealArray()
	var band_mid := PoolRealArray()
	var band_high := PoolRealArray()
	mid.resize(frames)
	high.resize(frames)
	rms.resize(frames)
	band_low.resize(frames)
	band_mid.resize(frames)
	band_high.resize(frames)
	mid[0] = 0.0
	high[0] = 0.0
	var pm := 0.0
	var ph := 0.0
	# (like the original's 23 ms spectrum frames: each frame looks 23 ms ahead from its start)
	e_all = _ahead(e_all)
	e_lo3k = _ahead(e_lo3k)
	for g in range(frames):
		var el: float = E[g]
		var lin_low: float = pow(10, el) if el > -12 else 0.0
		# 150 Hz - 3 kHz: kicks' click and snares; above 3 kHz: hats and cymbals
		var em: float = max(e_lo3k[g] - lin_low, 0.0)
		var eh: float = max(e_all[g] - e_lo3k[g], 0.0)
		var lm := log(1 + 100 * sqrt(em))
		var lh := log(1 + 100 * sqrt(eh))
		if g > 0:
			mid[g] = max(0.0, lm - pm)
			high[g] = max(0.0, lh - ph)
		pm = lm
		ph = lh
		rms[g] = sqrt(e_all[g])
		band_low[g] = el
		band_mid[g] = log(em + 1e-7) / log(10)
		band_high[g] = log(eh + 1e-7) / log(10)
	low_rise = _norm(low_rise)
	mid = _norm(mid)
	high = _norm(high)
	var hits_raw := PoolRealArray()
	var beats_raw := PoolRealArray()
	hits_raw.resize(frames)
	beats_raw.resize(frames)
	for i in range(frames):
		hits_raw[i] = (1.2 * low_rise[i] + mid[i] + 0.6 * high[i]) / 2.8
		beats_raw[i] = (1.4 * low_rise[i] + mid[i]) / 2.4
	var hits := _peaky(hits_raw)
	var beats := _peaky(beats_raw)
	var tempo = find_tempo(beats, hits, frames)
	return {"token": job.token, "frames": frames, "hits": hits, "beats": beats, "rms": rms,
		"band_low": band_low, "band_mid": band_mid, "band_high": band_high, "tempo": tempo}

# ------------------------------------------------------------------ the beat (automapper.js findTempo)

static func _first_desc(a, b) -> bool:
	return a[0] > b[0]

static func _around(env: PoolRealArray, f: float, r := 2) -> float:
	var c := int(round(f))
	var best := 0.0
	for k in range(max(0, c - r), min(env.size() - 1, c + r) + 1):
		if env[k] > best:
			best = env[k]
	return best

static func _beat_score(env: PoolRealArray, period: float, phase: float, from := 0, to := -1) -> float:
	if to < 0:
		to = env.size()
	var sum := 0.0
	var n := 0
	var t := phase + ceil((from - phase) / period) * period
	while t < to:
		sum += _around(env, t, 1)
		n += 1
		t += period
	return sum / n if n > 0 else 0.0

static func _strong_hits(env: PoolRealArray, frames: int, f: float) -> Array:
	var out := []
	var th := _percentile(env, f)
	for i in range(1, frames - 1):
		if env[i] > th and env[i] >= env[i - 1] and env[i] >= env[i + 1]:
			var a := env[i - 1]
			var b := env[i]
			var c := env[i + 1]
			var d := a - 2 * b + c
			out.append([i + (0.5 * (a - c) / d if d != 0 else 0.0), b])
	return out

static func _gather(strong: Array, total: float, bpm: float) -> float:
	var period := 6000.0 / bpm
	var bins := int(max(8, round(period * 4)))
	var hist := PoolRealArray()
	hist.resize(bins)
	for k in range(bins):
		hist[k] = 0.0
	for sv in strong:
		var idx := int(floor(fmod(sv[0] / period, 1.0) * bins)) % bins
		hist[idx] += sv[1]
	var best := 0.0
	for k in range(bins):
		var sm := 0.0
		for j in range(-2, 3):
			sm += hist[(k + j + bins) % bins]
		if sm > best:
			best = sm
	return best / total

static func _phase_for(strong: Array, period: float) -> float:
	var bins := 100
	var hist := PoolRealArray()
	hist.resize(bins)
	for k in range(bins):
		hist[k] = 0.0
	for sv in strong:
		hist[int(floor(fmod(sv[0] / period, 1.0) * bins)) % bins] += sv[1]
	var best := 0.0
	var at := 0
	for k in range(bins):
		var v := hist[k] + 0.6 * (hist[(k + 1) % bins] + hist[(k + bins - 1) % bins])
		if v > best:
			best = v
			at = k
	return (at + 0.5) / bins * period

static func _prior(bpm: float) -> float:
	return exp(-0.5 * pow((log(bpm / 175.0) / log(2)) / 0.55, 2))

static func _full_score(beats: PoolRealArray, mean: float, bpm: float) -> Dictionary:
	var period := 6000.0 / bpm
	var top_s := -1.0
	var top_phase := 0.0
	var ph := 0.0
	while ph < period:
		var v := _beat_score(beats, period, ph)
		if v > top_s:
			top_s = v
			top_phase = ph
		ph += 0.25
	var half := _beat_score(beats, period, top_phase + period / 2)
	return {"onBeats": top_s / mean, "half": half / mean, "phase": top_phase}

static func _grid_fit(drum_hits: Array, q: float) -> Dictionary:
	var best_ph := 0.0
	var best_s := -1.0
	var ph := 0.0
	while ph < q:
		var sc := 0.0
		for dv in drum_hits:
			var d: float = fmod(fmod(dv[0] - ph, q) + q, q)
			d = min(d, q - d)
			sc += dv[1] * exp(-0.5 * pow(d / 0.8, 2))
		if sc > best_s:
			best_s = sc
			best_ph = ph
		ph += 0.05
	return {"ph": best_ph, "s": best_s}

func find_tempo(beats: PoolRealArray, hits: PoolRealArray, frames: int):
	if frames < 1500:
		return null
	var mean := 0.0
	for v in beats:
		mean += v
	mean /= frames
	if mean <= 0:
		mean = 1e-6
	# candidates from the autocorrelation of the drums
	var ac := {}
	for lag in range(20, 141):
		var sm := 0.0
		var i := 0
		while i + lag < frames:
			sm += hits[i] * hits[i + lag]
			i += 2
		ac[lag] = sm
	var peaks := []
	for lag in range(21, 140):
		if ac[lag] >= ac[lag - 1] and ac[lag] >= ac[lag + 1]:
			peaks.append([ac[lag], lag])
	peaks.sort_custom(self, "_first_desc")
	var candidates := []
	for pk in peaks.slice(0, min(5, peaks.size() - 1)) if not peaks.empty() else []:
		var lag: int = pk[1]
		var y0: float = ac[lag - 1]
		var y1: float = ac[lag]
		var y2: float = ac[lag + 1]
		var d := y0 - 2 * y1 + y2
		var exact := lag + (0.5 * (y0 - y2) / d if d != 0 else 0.0)
		for r in [1.0, 2.0, 0.5, 1.5, 2.0 / 3.0, 4.0 / 3.0, 0.75]:
			var bpm: float = 6000.0 / exact * r
			if bpm >= 85 and bpm <= 280:
				var dup := false
				for c in candidates:
					if abs(c / bpm - 1) < 0.012:
						dup = true
						break
				if not dup:
					candidates.append(bpm)
	var strong := _strong_hits(beats, frames, 0.85)
	if strong.size() < 40:
		return null
	var total := 0.0
	for sv in strong:
		total += sv[1]
	# 1) each candidate tuned in 0.01 BPM steps
	var tuned := []
	for c in candidates:
		var top_bpm := 0.0
		var top_g := -1.0
		var bpm2: float = c * 0.984
		while bpm2 <= c * 1.016:
			var g := _gather(strong, total, bpm2)
			if g > top_g:
				top_g = g
				top_bpm = bpm2
			bpm2 += 0.01
		var dup2 := false
		for t in tuned:
			if abs(t / top_bpm - 1) < 0.003:
				dup2 = true
				break
		if not dup2:
			tuned.append(top_bpm)
	# 2) which of them is the beat
	var best = null
	for t in tuned:
		var fs := _full_score(beats, mean, t)
		var score: float = (fs.onBeats + 0.5 * fs.half) * (0.55 + 0.45 * _prior(t))
		if best == null or score > best.score:
			best = {"bpm": t, "phase": fs.phase, "score": score, "onBeats": fs.onBeats}
	if best == null:
		return null
	# 3) fine: 0.002 BPM steps
	var fine_bpm: float = best.bpm
	var fine_g := _gather(strong, total, best.bpm)
	var b3: float = best.bpm - 0.03
	while b3 <= best.bpm + 0.03:
		var g3 := _gather(strong, total, b3)
		if g3 > fine_g:
			fine_g = g3
			fine_bpm = b3
		b3 += 0.002
	# 4) precise: a straight line through the strong hits that sit on beats
	var period := 6000.0 / fine_bpm
	var phase: float = _full_score(beats, mean, fine_bpm).phase
	for _pass in range(3):
		var nn := 0.0
		var sk := 0.0
		var st := 0.0
		var skk := 0.0
		var skt := 0.0
		for sv in strong:
			var t2: float = sv[0]
			var v2: float = sv[1]
			var k := round((t2 - phase) / period)
			if abs(t2 - (phase + k * period)) > 2:
				continue
			nn += v2
			sk += v2 * k
			st += v2 * t2
			skk += v2 * k * k
			skt += v2 * k * t2
		var det := nn * skk - sk * sk
		if nn < 20 or det == 0:
			break
		var p2 := (nn * skt - sk * st) / det
		if not (p2 > 0) or abs(p2 / period - 1) > 0.003:
			break
		phase = (st - p2 * sk) / nn
		period = p2
	fine_bpm = 6000.0 / period
	# a whole number when it's that close, otherwise two decimals
	var bpm_out: float = round(fine_bpm) if abs(fine_bpm - round(fine_bpm)) < 0.06 else round(fine_bpm * 100) / 100
	period = 6000.0 / bpm_out
	phase = _phase_for(strong, period)
	var top := -1.0
	var pp := phase - 2
	var best_p := phase
	while pp <= phase + 2:
		var sc := _beat_score(beats, period, pp)
		if sc > top:
			top = sc
			best_p = pp
		pp += 0.1
	phase = fmod(fmod(best_p, period) + period, period)
	# the drums on a grid of quarter beats and of third beats
	var drum_hits := _strong_hits(hits, frames, 0.8)
	var quarter_fit := _grid_fit(drum_hits, period / 4)
	var third_fit := _grid_fit(drum_hits, period / 3)
	var q := period / 4
	var near: float = quarter_fit.ph
	while near < phase - q / 2:
		near += q
	while near > phase + q / 2:
		near -= q
	if abs(near - phase) > 1.5:
		phase = fmod(fmod(near, period) + period, period)
	# which quarter of the beat is the beat
	var base := _beat_score(beats, period, phase) + 0.6 * _beat_score(beats, period, phase + period / 2)
	var bestk := 0
	var topk := base
	for k in range(1, 4):
		var v := _beat_score(beats, period, phase + k * q) + 0.6 * _beat_score(beats, period, phase + k * q + period / 2)
		if v > topk:
			topk = v
			bestk = k
	if bestk != 0 and topk >= 1.3 * base:
		phase = fmod(fmod(phase + bestk * q, period) + period, period)
	# does the beat stay put?
	var shifts := []
	var reach: float = min(5.0, period / 8 - 0.25)
	var from := 0
	while from + 1500 <= frames:
		var in_window := []
		for dv in drum_hits:
			if dv[0] >= from and dv[0] < from + 1500:
				in_window.append(dv)
		var best_shift := 0.0
		var best_s := -1.0
		if in_window.size() >= 20:
			var sh := -reach
			while sh <= reach + 1e-9:
				var sc2 := 0.0
				for dv in in_window:
					var d2: float = fmod(fmod(dv[0] - phase - sh, q) + q, q)
					d2 = min(d2, q - d2)
					sc2 += dv[1] * exp(-0.5 * pow(d2 / 0.8, 2))
				if sc2 > best_s * 1.02 or (abs(sc2 - best_s) <= best_s * 0.02 and abs(sh) < abs(best_shift)):
					best_s = max(sc2, best_s)
					best_shift = sh
				sh += 0.25
		shifts.append(round(best_shift * 2) / 2)
		from += 1500
	var steady_n := 0
	for sh2 in shifts:
		if abs(sh2) <= 2:
			steady_n += 1
	var steady := steady_n >= shifts.size() * 0.7
	return {"bpm": bpm_out, "offsetMs": phase * 10, "steady": steady, "confidence": best.onBeats}

# Which beat of four starts a bar (findDownbeat)
func _find_downbeat(a: Dictionary, beat: float, offset_ms: float) -> int:
	var step := beat / 10.0
	var frames: int = a.frames
	var count := int(floor((frames - offset_ms / 10.0) / step))
	if count < 16:
		return 0
	var D := 5
	var per := PoolRealArray()
	per.resize(count * D)
	var bl: PoolRealArray = a.band_low
	var bm: PoolRealArray = a.band_mid
	var bh: PoolRealArray = a.band_high
	var rms: PoolRealArray = a.rms
	var hits: PoolRealArray = a.hits
	for k in range(count):
		var f0 := int(floor(offset_ms / 10.0 + k * step))
		var f1 := int(min(frames, floor(offset_ms / 10.0 + (k + 1) * step)))
		var vals := [0.0, 0.0, 0.0, 0.0, 0.0]
		for f in range(f0, f1):
			vals[0] += bl[f]
			vals[1] += bm[f]
			vals[2] += bh[f]
			vals[3] += log(rms[f] + 1e-4) / log(10)
			vals[4] += hits[f]
		var c: int = max(1, f1 - f0)
		for d in range(D):
			per[k * D + d] = vals[d] / c
	for d in range(D):
		var mean := 0.0
		var sq := 0.0
		for k in range(count):
			mean += per[k * D + d]
		mean /= count
		for k in range(count):
			sq += pow(per[k * D + d] - mean, 2)
		var sd := sqrt(sq / count)
		if sd == 0:
			sd = 1.0
		for k in range(count):
			per[k * D + d] = (per[k * D + d] - mean) / sd
	var best := 0
	var top := -1.0
	for phase in range(4):
		var score := 0.0
		var prev = null
		var k := phase
		while k + 4 <= count:
			var bar := [0.0, 0.0, 0.0, 0.0, 0.0]
			for q in range(4):
				for d in range(D):
					bar[d] += per[(k + q) * D + d] / 4.0
			if prev != null:
				for d in range(D):
					score += pow(bar[d] - prev[d], 2)
			prev = bar
			k += 4
		if score > top:
			top = score
			best = phase
	return best

# DETECT BPM: {bpm, offsetMs (the first downbeat), steady} or null
func detect_bpm(from_ms: int, to_ms: int):
	if _result == null and _job != null:
		_result = _analyse(_job)
		_job = null
	if _result == null:
		return null
	var a: Dictionary = _result
	var frames: int = a.frames
	var f0 := int(max(0, floor(from_ms / 10.0)))
	var f1: int = int(min(frames, ceil(to_ms / 10.0))) if to_ms > from_ms else frames
	if f1 - f0 < 1500:
		return null
	var tempo = a.tempo
	if f0 != 0 or f1 != frames:
		tempo = find_tempo(_sub(a.beats, f0, f1), _sub(a.hits, f0, f1), f1 - f0)
	if tempo == null or not (tempo.bpm > 0):
		return null
	var beat: float = 60000.0 / tempo.bpm
	var offset: float = tempo.offsetMs + f0 * 10
	var down: float = offset + _find_downbeat(a, beat, offset) * beat
	var bar := 4 * beat
	var first: float = down - floor((down - f0 * 10) / bar) * bar
	return {"bpm": tempo.bpm, "offsetMs": int(max(0, round(first))), "steady": bool(tempo.steady)}

static func _sub(arr: PoolRealArray, a: int, b: int) -> PoolRealArray:
	var out := PoolRealArray()
	out.resize(b - a)
	for i in range(a, b):
		out[i - a] = arr[i]
	return out

# ------------------------------------------------------------------ the auto mapper

func auto_map(ed, _map):
	ed.dialogs.message("The auto mapper is being ported to Chromia and comes in a later update. Everything else in SSQE+'s editor is here.")

func learn_files(_files, ed):
	auto_map(ed, null)

func reset_learning():
	pass

func stats_text() -> String:
	return ""

func _exit_tree():
	_token += 1
	if _thread:
		_thread.wait_to_finish()
		_thread = null

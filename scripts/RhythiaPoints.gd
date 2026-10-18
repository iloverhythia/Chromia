extends Reference
# Offline RP (Rhythia Points), earned on this computer so there's something
# to grind while the servers are down. Saved to user://rp_plays.json.
#
# A play's RP: 5 x (stars x speed)^2 (the SSQE+ "Calculate SR/RP" numbers),
# scaled by accuracy. Only your best play on each map counts. Total RP is
# Rhythia's weighting: plays sorted best first, play n counts 0.97^(n - 1).
#
#   const RhythiaPoints = preload("res://scripts/RhythiaPoints.gd")
#   var store = RhythiaPoints.get_store()

signal changed

const SAVE_PATH = "user://rp_plays.json"
const META_KEY = "furria_rp_store"
const WEIGHT = 0.97
const ACC_POWER = 5.0

# song id -> {rp, stars, speed, acc, misses, name, time}
var plays: Dictionary = {}
var _sorted_cache = null

static func get_store():
	var root: Viewport = Engine.get_main_loop().root
	if root.has_meta(META_KEY):
		return root.get_meta(META_KEY)
	var s = load("res://scripts/RhythiaPoints.gd").new()
	s.load_data()
	root.set_meta(META_KEY, s)
	return s

# RP for a full-accuracy play (what SSQE+ shows for each speed).
static func max_rp(stars: float, speed: float) -> float:
	return 5.0 * pow(max(stars, 0.0) * speed, 2)

static func play_rp(stars: float, speed: float, accuracy: float) -> float:
	return max_rp(stars, speed) * pow(clamp(accuracy, 0.0, 1.0), ACC_POWER)

func load_data():
	plays = {}
	var f := File.new()
	var path: String = Globals.p(SAVE_PATH)
	if f.file_exists(path) and f.open(path, File.READ) == OK:
		var res := JSON.parse(f.get_as_text())
		f.close()
		if res.error == OK and typeof(res.result) == TYPE_DICTIONARY:
			for id in res.result.get("plays", {}):
				var p = res.result.plays[id]
				if typeof(p) == TYPE_DICTIONARY and p.has("rp"):
					plays[str(id)] = p
	_sorted_cache = null

func save():
	var f := File.new()
	if f.open(Globals.p(SAVE_PATH), File.WRITE) == OK:
		f.store_string(JSON.print({"plays": plays}, "\t"))
		f.close()

# Records a play. Returns {"rp": this play's RP, "best": true if it's a new
# best on this map, "gained": how much the total went up}.
func record(song_id: String, song_name: String, stars: float, speed: float, accuracy: float, misses: int) -> Dictionary:
	var rp := play_rp(stars, speed, accuracy)
	var old: Dictionary = plays.get(song_id, {})
	if not old.empty() and float(old.rp) >= rp:
		return {"rp": rp, "best": false, "gained": 0.0}
	var before := total()
	plays[song_id] = {
		"rp": stepify(rp, 0.01), "stars": stepify(stars, 0.01), "speed": stepify(speed, 0.0001),
		"acc": stepify(accuracy, 0.0001), "misses": misses, "name": song_name,
		"time": OS.get_unix_time(),
	}
	_sorted_cache = null
	save()
	var gained := total() - before
	emit_signal("changed")
	return {"rp": rp, "best": true, "gained": gained}

# Plays sorted best first, each with its song id added as "id".
func sorted_plays() -> Array:
	if _sorted_cache != null:
		return _sorted_cache
	var arr := []
	for id in plays:
		var p: Dictionary = plays[id].duplicate()
		p["id"] = id
		arr.append(p)
	arr.sort_custom(self, "_by_rp")
	_sorted_cache = arr
	return arr

func _by_rp(a, b) -> bool:
	return float(a.rp) > float(b.rp)

func total() -> float:
	var t := 0.0
	var w := 1.0
	for p in sorted_plays():
		t += float(p.rp) * w
		w *= WEIGHT
	return t

func top(n: int) -> Array:
	var s := sorted_plays()
	return s.slice(0, min(n, s.size()) - 1) if s.size() > 0 else []

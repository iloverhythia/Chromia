extends Reference
# Offline level system, like BeatLeader's: every play gives experience (even a
# fail), levels go up to 100, and at 100 you can Prestige, which resets your
# level and makes every next level cost 20% more. Saved in user://level.json.
#
# Experience needed for the next level (BeatLeader's formula):
#   (500 + 50 * level) * 1.2 ^ prestige
# Experience for a play (BeatLeader computes it on their server; this is ours):
#   ~2 per second actually played, x a star bonus, x an accuracy factor,
#   x1.5 for a pass.

signal changed

const SAVE_PATH = "user://level.json"
const META_KEY = "chromia_level_store"
const MAX_LEVEL = 100
const MAX_PRESTIGE = 10

var level: int = 0
var cur_exp: int = 0          # experience inside the current level
var prestige: int = 0
var total_exp: int = 0    # everything ever earned

static func get_store():
	var root: Viewport = Engine.get_main_loop().root
	if root.has_meta(META_KEY):
		return root.get_meta(META_KEY)
	var s = load("res://scripts/PlayerLevel.gd").new()
	s.load_data()
	root.set_meta(META_KEY, s)
	return s

static func required_exp(lvl: int, prest: int) -> int:
	var req := 500 + 50 * lvl
	if prest != 0:
		req = int(round(req * pow(1.2, prest)))
	return req

static func exp_for_play(seconds: float, stars: float, accuracy: float, passed: bool) -> int:
	if seconds <= 1.0:
		return 0
	var star_bonus: float = 1.0 + clamp(stars, 0.0, 15.0) * 0.1
	var acc_factor: float = 0.5 + 0.5 * clamp(accuracy, 0.0, 1.0)
	var e: float = seconds * 2.0 * star_bonus * acc_factor
	if passed:
		e *= 1.5
	return int(round(e))

func load_data():
	var f := File.new()
	var path: String = Globals.p(SAVE_PATH)
	if f.file_exists(path) and f.open(path, File.READ) == OK:
		var res := JSON.parse(f.get_as_text())
		f.close()
		if res.error == OK and typeof(res.result) == TYPE_DICTIONARY:
			var d: Dictionary = res.result
			level = int(clamp(int(d.get("level", 0)), 0, MAX_LEVEL))
			cur_exp = int(max(0, int(d.get("exp", 0))))
			prestige = int(clamp(int(d.get("prestige", 0)), 0, MAX_PRESTIGE))
			total_exp = int(max(0, int(d.get("total_exp", 0))))

func save():
	var f := File.new()
	if f.open(Globals.p(SAVE_PATH), File.WRITE) == OK:
		f.store_string(to_json({"level": level, "exp": cur_exp, "prestige": prestige, "total_exp": total_exp}))
		f.close()

func required() -> int:
	return required_exp(level, prestige)

func progress() -> float:
	if level >= MAX_LEVEL:
		return 1.0
	return clamp(float(cur_exp) / float(max(required(), 1)), 0.0, 1.0)

func can_prestige() -> bool:
	return level >= MAX_LEVEL and prestige < MAX_PRESTIGE

# Adds experience; returns {"gained", "levels_up", "level"}.
func add_exp(amount: int) -> Dictionary:
	var start_level := level
	if amount > 0:
		total_exp += amount
		if level < MAX_LEVEL:
			cur_exp += amount
			while level < MAX_LEVEL and cur_exp >= required():
				cur_exp -= required()
				level += 1
			if level >= MAX_LEVEL:
				cur_exp = 0
		save()
		emit_signal("changed")
	return {"gained": amount, "levels_up": level - start_level, "level": level}

func do_prestige() -> bool:
	if not can_prestige():
		return false
	prestige += 1
	level = 0
	cur_exp = 0
	save()
	emit_signal("changed")
	return true

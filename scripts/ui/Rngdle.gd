extends Node

# RNGdle (a secret): type "dylan jarvis" anywhere in the game (a text box or
# not) and one time in three a popup rolls six digits, one reel after the
# other, then shows the number and how rare it is. Global chat then says
# "<name> got ###### on rngdle" (the server's lobbies.js rngdle makes the
# line; one roll per player every 15 seconds there).
# LobbyManager adds this node; it only watches typed letters.

const OnlineStyle = preload("res://scripts/ui/menu/OnlineStyle.gd")
const WORD := "dylan jarvis"
const CHANCE := 3 # (1 in this many)

# rarest first: [rarity, colour, the pattern, 1 in how many]
# (the odds counted over all 1,000,000 numbers, each number in its rarest group)
const RARITY := {
	"six": ["Mythic", "#f472b6", "Six of a kind", "100,000"],
	"straight": ["Legendary", "#fb923c", "Straight", "100,000"],
	"five": ["Epic", "#c084fc", "Five of a kind", "1,852"],
	"triples": ["Epic", "#c084fc", "Two triples", "1,111"],
	"palindrome": ["Epic", "#c084fc", "Palindrome", "1,010"],
	"four": ["Rare", "#60a5fa", "Four of a kind", "84"],
	"pairs": ["Rare", "#60a5fa", "Three pairs", "99"],
	"three": ["Uncommon", "#4ade80", "Three of a kind", "7"],
	"different": ["Uncommon", "#4ade80", "All different", "7"],
	"common": ["Common", "#a1a1aa", "Nothing special", "1.5"],
}

var _typed := ""
var _rng := RandomNumberGenerator.new()
var _open = null

func _ready():
	_rng.randomize()
	pause_mode = PAUSE_MODE_PROCESS

func _input(ev):
	if not (ev is InputEventKey) or not ev.pressed or ev.echo or ev.unicode <= 0:
		return
	_typed = (_typed + char(ev.unicode).to_lower()).right(max(0, _typed.length() + 1 - 24))
	if _typed.ends_with(WORD):
		_typed = ""
		if (_open == null or not is_instance_valid(_open)) and _rng.randi() % CHANCE == 0:
			roll()

# the number's group in RARITY
static func kind_of(d: String) -> String:
	var counts := {}
	for ch in d:
		counts[ch] = int(counts.get(ch, 0)) + 1
	var c: Array = counts.values()
	c.sort()
	c.invert()
	var up := true
	var down := true
	for i in 5:
		var diff := int(d[i + 1]) - int(d[i])
		up = up and diff == 1
		down = down and diff == -1
	var rev := ""
	for i in range(5, -1, -1):
		rev += d[i]
	if c[0] == 6: return "six"
	if up or down: return "straight"
	if c[0] == 5: return "five"
	if c.size() >= 2 and c[0] == 3 and c[1] == 3: return "triples"
	if d == rev: return "palindrome"
	if c[0] == 4: return "four"
	if c.size() >= 3 and c[0] == 2 and c[1] == 2 and c[2] == 2: return "pairs"
	if c[0] == 3: return "three"
	if c.size() == 6: return "different"
	return "common"

func roll(digits: String = ""):
	if digits == "":
		for i in 6:
			digits += str(_rng.randi() % 10)
	var lm = get_node_or_null("/root/LobbyManager")
	if Rhythia.get("vr"):
		# (VR: the headset doesn't show screen layers; a notice instead)
		var r: Array = RARITY[kind_of(digits)]
		Globals.notify(Globals.NOTIFY_INFO, "You got %s: %s (%s, 1 in %s)" % [digits, r[0], r[2], r[3]], "RNGdle")
		_post(lm, digits)
		return
	var layer := CanvasLayer.new()
	layer.layer = 127
	layer.pause_mode = PAUSE_MODE_PROCESS
	get_tree().root.add_child(layer)
	var p = load("res://scripts/ui/RngdlePopup.gd").new()
	p.digits = digits
	p.info = RARITY[kind_of(digits)]
	p.owner_node = self
	layer.add_child(p)
	_open = layer

func _post(lm, digits: String):
	if lm != null and lm.has_method("_ensure_connected_then_send"):
		lm._ensure_connected_then_send({"type": "rngdle", "digits": digits, "name": String(lm.player_name), "client_id": Rhythia.cid})

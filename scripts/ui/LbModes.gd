extends OptionButton

# The leaderboards' device dropdown (every in-game leaderboard and the
# website's): all plays, or only the ones played on PC / in VR (a Meta Quest
# is VR too) / with Spin / on a phone. The server counts each device's plays on their own
# (/savia-public/api/leaderboard/sp?device=, /map/<id>?device=). The choice is
# shared by every board and kept (Rhythia.lb_device).

const MODES := [["All devices", ""], ["PC", "pc"], ["VR", "vr"], ["Spin", "spin"], ["Phone", "mobile"]]

static func name_of(dev: String) -> String:
	for m in MODES:
		if m[1] == dev:
			return m[0]
	return "All devices"

# "&device=vr" / "?device=vr" for a request ("" for all devices)
static func query(first: bool = false) -> String:
	var d: String = String(Rhythia.get("lb_device")) if Rhythia.get("lb_device") != null else ""
	if d == "quest": # (Quest was its own choice once: it's VR)
		d = "vr"
		Rhythia.lb_device = "vr"
	if d == "":
		return ""
	return ("?" if first else "&") + "device=" + d.http_escape()

# the dropdown; `target.method()` is called after a change (Rhythia.lb_device is set already)
static func make(target: Object, method: String, font: Font = null) -> OptionButton:
	var ob = load("res://scripts/ui/LbModes.gd").new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.hint_tooltip = "Only the plays on one kind of device"
	if font != null:
		ob.add_font_override("font", font)
	var cur: String = String(Rhythia.get("lb_device")) if Rhythia.get("lb_device") != null else ""
	for i in MODES.size():
		ob.add_item(MODES[i][0], i)
		if MODES[i][1] == cur:
			ob.select(i)
	ob._target = target
	ob._method = method
	ob.connect("item_selected", ob, "_picked")
	return ob

var _target: Object
var _method := ""

func _picked(i: int):
	Rhythia.lb_device = MODES[clamp(i, 0, MODES.size() - 1)][1]
	Rhythia.save_settings()
	if _target != null and is_instance_valid(_target):
		_target.call(_method)

# every dropdown on screen shows the same choice (after it changed somewhere else)
static func sync(ob):
	if ob == null or not is_instance_valid(ob):
		return
	var cur: String = String(Rhythia.get("lb_device"))
	for i in MODES.size():
		if MODES[i][1] == cur and ob.selected != i:
			ob.select(i)

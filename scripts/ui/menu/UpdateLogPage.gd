extends Control

# The Update Log: the newest updates first, more with "Show older updates".
# (All of them in one label took a long moment to lay out the first time the
# page opened.)

const STEP := 15
var _entries := []
var _shown := 0
var _more: Button

func _ready():
	_entries = Rhythia.update_log_entries()
	_more = Button.new()
	_more.text = "  Show older updates  "
	_more.size_flags_horizontal = SIZE_SHRINK_CENTER
	_more.connect("pressed", self, "_show_more")
	$Scroll/V.add_child(_more)
	$Scroll/V.move_child(_more, $Scroll/V/L.get_index() + 1)
	$Scroll/V/L.text = ""
	_show_more()

func _show_more():
	var upto: int = min(_shown + STEP, _entries.size())
	var add := PoolStringArray(_entries.slice(_shown, upto - 1)).join("\n\n")
	var L: Label = $Scroll/V/L
	L.text = add if L.text == "" else L.text + "\n\n" + add
	_shown = upto
	_more.visible = _shown < _entries.size()

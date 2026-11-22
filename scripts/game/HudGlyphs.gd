extends Node
# The HUD's numbers, made ready before the first note (HUD.gd adds this).
#
# A font draws a character from a picture of it that is made the first time
# the character is shown at that size: the engine draws the character and then
# sends the whole sheet it sits on to the graphics card again. The HUD's fonts
# are big (the combo is 128 pixels tall, a sheet of 1024 x 1024), so every
# first "1", "2", "%" or "S" was a megabyte or two sent in the middle of a
# frame. A song starts at 0 everywhere: the first hit changed the combo, the
# score, the note count, the accuracy and the grade all at once, about ten
# new characters in one frame, and the next hits brought the other digits one
# by one. On a headset or a phone that was a visible hitch on the first note
# of every map and small ones after it.
#
# So: the digits and signs the HUD can show are asked for here while the song
# counts in, a few a frame; and the fonts are kept between songs (they were
# thrown away with the HUD, so every map paid again), which leaves the second
# map on with nothing to make at all.
const CHARS := "0123456789.,:%/x-+ SABCDF"
const BUDGET_USEC := 2500 # a frame's share of it
const KEEP := "hud_glyph_fonts"

var _todo := [] # [font, how many of CHARS are done]

func _ready():
	set_process(false)
	call_deferred("_collect") # (after the HUD and the font settings have set the labels' fonts)

func _collect():
	if not is_inside_tree():
		return
	var root: Node = get_tree().current_scene if get_tree().current_scene != null else get_parent()
	var fonts := []
	var counting := [] # the ones that show numbers (a label with a digit in it, or the "-" of one not known yet)
	var stack := [root]
	while not stack.empty():
		var n: Node = stack.pop_back()
		var f = null
		if n is Label:
			f = n.get_font("font")
		elif n is RichTextLabel:
			f = n.get_font("normal_font")
		if f is DynamicFont:
			if not fonts.has(f):
				fonts.append(f)
			if not counting.has(f) and _counts(String(n.text)):
				counting.append(f)
		for c in n.get_children():
			stack.append(c)
	# (kept until the next song has collected its own: fonts of the same file
	# and size share their characters, so that song finds them all made)
	Engine.set_meta(KEEP, fonts)
	counting.sort_custom(self, "_bigger_first")
	for f in counting:
		_todo.append([f, 0])
	set_process(not _todo.empty())

static func _counts(text: String) -> bool:
	if text == "-" or text == "--":
		return true
	for i in range(text.length()):
		var c := text.ord_at(i)
		if c >= 48 and c <= 57:
			return true
	return false

func _bigger_first(a: DynamicFont, b: DynamicFont) -> bool:
	return a.size > b.size

func _process(_d):
	var t0 := OS.get_ticks_usec()
	while not _todo.empty():
		var job: Array = _todo[0]
		var f: DynamicFont = job[0]
		# (one character: measuring it makes it, when it wasn't there yet)
		f.get_string_size(CHARS[job[1]])
		job[1] += 1
		if job[1] >= CHARS.length():
			_todo.pop_front()
		if OS.get_ticks_usec() - t0 > BUDGET_USEC:
			return
	set_process(false)

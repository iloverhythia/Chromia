extends GridContainer

onready var base = $Color

var btns = {}

func upd(_c=null):
	for k in btns.keys():
		var v = (k.id == Rhythia.selected_colorset.id)
		btns[k].get_node("Select").disabled = v
		if v: btns[k].self_modulate = Color(1,1,1)
		else: btns[k].self_modulate = Color(0.5,0.5,0.5)

func col(): columns = rect_size.x / 100

func _ready():
	for cs in Rhythia.registry_colorset.items:
		add_set(cs, false)
	upd()
	Rhythia.connect("selected_colorset_changed",self,"upd")
	connect("resized",self,"col")
	col()

func _fill_colors(btn, set):
	var color_grid = btn.get_node("Colors")
	var col_template = btn.get_node("Colors/T")
	var color_count = set.real_colors.size()
	if color_count == 3: color_grid.columns = 3
	elif color_count == 0: color_grid.columns = 1
	else: color_grid.columns = ceil(sqrt(float(color_count)))
	for c in set.real_colors:
		var colrect = col_template.duplicate()
		colrect.color = c
		colrect.visible = true
		color_grid.call_deferred("add_child",colrect)

# Redraws a colorset button after its colors changed (colorset maker).
func refresh_set(set):
	if not btns.has(set):
		add_set(set)
		return
	var btn = btns[set]
	for c in btn.get_node("Colors").get_children():
		if c.name != "T": c.queue_free()
	btn.get_node("Mirror").visible = set.mirror
	_fill_colors(btn, set)

func add_set(cs, update: bool = true):
	if true:
		var set:ColorSet = cs
		var btn = $Color.duplicate()
		btn.get_node("Name").text = set.name
		btn.visible = true
		
		var sel = btn.get_node("Select")
		btn.get_node("Mirror").visible = set.mirror
		sel.hint_tooltip = set.name + "\nby " + set.creator
		_fill_colors(btn, set)
		
#		var even_v = fmod(color_grid.columns,2)
#		var even_h = fmod(ceil(color_count / color_grid.columns),2)
#		color_grid.set("custom_constants/vseparation",even_v+1)
#		color_grid.set("custom_constants/vseparation",even_h+1)
		
		sel.connect("pressed",Rhythia,"select_colorset",[cs])
		btns[cs] = btn
		call_deferred("add_child",btn)
	if update: call_deferred("upd")

extends MenuButton
# Hit effect picker (Settings > Notes). MissEffect.gd extends this for the miss effect.

var effects: Array = []
var current_sel: int = -1

func _is_miss() -> bool:
	return false

func _selected():
	return Rhythia.selected_miss_effect if _is_miss() else Rhythia.selected_hit_effect

func on_pressed(i: int):
	if i < 0 or i >= effects.size(): return
	if _is_miss(): Rhythia.select_miss_effect(effects[i])
	else: Rhythia.select_hit_effect(effects[i])

func on_effect_selected(selected_effect):
	if selected_effect == null: return
	text = selected_effect.name
	var popup = get_popup()
	for i in range(effects.size()):
		popup.set_item_checked(i, effects[i] == selected_effect)
		if effects[i] == selected_effect: current_sel = i

func _ready():
	var popup = get_popup()
	popup.clear()
	effects.clear()
	if Rhythia.registry_effect:
		var found: Array = Rhythia.registry_effect.get_items()
		for effect in found:
			if not (effect is NoteEffect): continue
			popup.add_check_item(effect.name, effects.size())
			effects.append(effect)
	var sig = "selected_miss_effect_changed" if _is_miss() else "selected_hit_effect_changed"
	if not Rhythia.is_connected(sig, self, "on_effect_selected"):
		Rhythia.connect(sig, self, "on_effect_selected")
	if not popup.is_connected("id_pressed", self, "on_pressed"):
		popup.connect("id_pressed", self, "on_pressed")
	on_effect_selected(_selected())

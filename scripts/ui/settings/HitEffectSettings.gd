extends Reference
# Adds the SS+ hit effect options to Settings > Notes, next to the existing miss
# effect options (built from those nodes so they look identical), and gives the
# miss effect dropdown its real script. Called once from menu2.gd _ready().

const HIT_EFFECT_SCRIPT = preload("res://scripts/ui/settings/HitEffect.gd")
const MISS_EFFECT_SCRIPT = preload("res://scripts/ui/settings/MissEffect.gd")

static func build(tab_container: Node):
	if tab_container == null: return
	var h = tab_container.get_node_or_null("Notes/Notes/Group/H")
	if h == null or h.has_node("HitEffect"): return
	var miss_img = h.get_node_or_null("MissRipple")
	var miss_row = h.get_node_or_null("HBoxContainer")
	var miss_chk = h.get_node_or_null("ShowMissEffect")
	if miss_row == null or miss_chk == null or not miss_row.has_node("Effect"):
		return
	var idx: int = (miss_img.get_index() if miss_img else miss_row.get_index())
	var added: Array = []

	# custom hit image (user://hit), used by ripple
	if miss_img and miss_img.has_node("MissEffect"):
		var hit_img = miss_img.duplicate()
		hit_img.name = "HitRipple"
		var btn = hit_img.get_node("MissEffect")
		btn.name = "HitEffectImage"
		btn.set("target", "hit")
		btn.hint_tooltip = "custom image for the ripple hit effect (and other image based hit effects)"
		var lbl = btn.get_node_or_null("Label")
		if lbl:
			lbl.text = "Hit Effect Image"
			lbl.hint_tooltip = btn.hint_tooltip
		added.append(hit_img)

	# hit effect dropdown
	var hit_row = miss_row.duplicate()
	hit_row.name = "HitEffect"
	hit_row.hint_tooltip = "effect shown when you hit a note"
	var hit_btn = hit_row.get_node("Effect")
	hit_btn.set_script(HIT_EFFECT_SCRIPT)
	hit_btn.hint_tooltip = hit_row.hint_tooltip
	var hit_lbl = hit_row.get_node_or_null("Label")
	if hit_lbl: hit_lbl.text = "Hit Effect"
	added.append(hit_row)

	added.append(_checkbox(miss_chk, "ShowHitEffect", "show_hit_effect", "Show Hit Effect",
		"show an effect when you hit a note"))
	added.append(_checkbox(miss_chk, "HitEffectCursor", "hit_effect_at_cursor", "Hit Effect at Cursor",
		"on: the hit effect appears where your cursor is. off: it appears on the note"))

	var sep = h.get_node_or_null("SEPARATOR4")
	if sep: added.append(sep.duplicate())

	for n in added:
		h.add_child(n)
		h.move_child(n, idx)
		idx += 1

	# the miss effect dropdown in the scene only had a stub script; swap in the real one
	var old_btn = miss_row.get_node("Effect")
	var miss_btn = old_btn.duplicate()
	miss_btn.set_script(MISS_EFFECT_SCRIPT)
	var pos = old_btn.get_index()
	miss_row.remove_child(old_btn)
	old_btn.queue_free()
	miss_btn.name = "Effect"
	miss_row.add_child(miss_btn)
	miss_row.move_child(miss_btn, pos)

static func _checkbox(template: Node, node_name: String, target: String, label: String, tip: String) -> Node:
	var c = template.duplicate()
	c.name = node_name
	c.set("target", target)
	c.text = label
	c.hint_tooltip = tip
	return c

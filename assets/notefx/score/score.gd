extends Spatial

signal cache_me

var active:bool = false
var rainbow:bool = false
var col:Color = Color(1,1,1,1)
var t:float = 1
var _pool = null # (NoteManager keeps finished popups to use again)

func _ready():
	$Label.billboard = Rhythia.billboard_score

func _process(delta):
	if active:
		t -= delta * 3
		transform.origin.y = -0.8 + clamp((2*pow((1.0 - t)-0.25,2))-0.125,-1,1) * -0.4
		$Label.modulate = Color(col.r, col.g, col.b, col.a*t)
		$Label.outline_modulate = Color(0, 0, 0, 0.6*t)
		if t <= 0:
			active = false
			if _pool is Array and _pool.size() < 32:
				visible = false
				_pool.append(self)
			else:
				queue_free()


func spawn(parent:Node,pos:Vector3,color:Color,score:int):
	col = color * Color(1,1,1,0.5)
	
	if (score > 0): $Label.text = "+" + Globals.comma_sep(score)
	else: $Label.text = Globals.comma_sep(score)
	
	transform.origin = Vector3(pos.x,-0.8,pos.z)
	if get_parent() != parent:
		if get_parent() != null:
			get_parent().remove_child(self)
		parent.add_child(self)
	t = 1
	visible = true
	active = true

extends Spatial

var rate:float = Rhythia.get("approach_rate") / 6
var s:float = -26
var e:float = 48
var tcol:Color
var color:Color = Rhythia.selected_colorset.colors[0]
var ratec:float = 0.02

func hit(col:Color):
	color = col

func _ready():
	var game = get_parent().get_node_or_null("Game") # (none in the VR menu)
	if game:
		game.connect("hit",self,"hit")

func _process(delta):
	$tunnel.translation.z += rate * delta
	$tunnel.translation.z = wrapf($tunnel.translation.z,s,e)
	tcol = color
	$tunnel.material_override.albedo_color = lerp($tunnel.material_override.albedo_color,tcol,ratec)

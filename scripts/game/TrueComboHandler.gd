extends Label

func _ready():
	if !Rhythia.display_true_combo:
		visible = false
	else:
		visible = true

func _physics_process(delta):
	# (it glides to its place and never quite arrived: every tick moved it a
	# hair, and each move had its HUD panel drawn again)
	if rect_position.y == 150:
		return
	var y: float = rect_position.y + (150 - rect_position.y) * 0.25
	if abs(150 - y) < 0.25:
		y = 150
	rect_position.y = y

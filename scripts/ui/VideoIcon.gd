extends Control
# A small video camera drawn in code (no picture file): the Save video
# button's icon on the map screen, dark like the gear icon beside it.

export var color := Color(0, 0, 0, 0.9)

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	connect("resized", self, "update")

func _draw():
	var s: float = min(rect_size.x, rect_size.y)
	var c: Vector2 = rect_size / 2.0
	var w: float = s * 0.36 # the body
	var h: float = s * 0.34
	var body := Rect2(c.x - s * 0.27, c.y - h / 2.0, w, h)
	var r: float = s * 0.06
	# the body with rounded corners: two rectangles and four corner circles
	draw_rect(Rect2(body.position.x + r, body.position.y, body.size.x - r * 2, body.size.y), color)
	draw_rect(Rect2(body.position.x, body.position.y + r, body.size.x, body.size.y - r * 2), color)
	for p in [body.position + Vector2(r, r), body.position + Vector2(body.size.x - r, r),
			body.position + Vector2(r, body.size.y - r), body.position + body.size - Vector2(r, r)]:
		draw_circle(p, r, color)
	# the lens: a triangle opening to the right
	var x0: float = body.end.x + s * 0.03
	var x1: float = c.x + s * 0.27
	draw_colored_polygon(PoolVector2Array([
		Vector2(x0, c.y - h * 0.12), Vector2(x1, c.y - h * 0.5),
		Vector2(x1, c.y + h * 0.5), Vector2(x0, c.y + h * 0.12)]), color)

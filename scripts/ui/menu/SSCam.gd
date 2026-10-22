extends Reference

# Sound Space Mode's menu "camera". Sound Space's menus are panels in a 3D
# room: the camera always drifts a little toward your cursor / finger (so the
# panels lean, like seen from the side) and whips around to another panel
# when you open something. This fakes that on the 2D menus:
#
#   sway: where the cursor is, -1..1 from the screen centre (smoothed)
#   whip: 0 = looking at this screen, +-1 = turned away to the right / left
#
# xform() gives the transform for a screen's contents (a Node2D above it):
# moved against the cursor, sheared so it leans, and squeezed / thrown aside
# while whipping.

const DRIFT := Vector2(34, 20)   # px moved at the edge of the screen (at 720p)
const LEAN := 0.11               # shear from the cursor's left / right
const TIP := 0.045               # shear from the cursor's up / down
const WHIP_DIST := 0.8           # of the screen width when turned away
const WHIP_LEAN := 0.32

static func xform(screen: Vector2, sway: Vector2, whip: float) -> Transform2D:
	var unit: float = screen.y / 720.0
	var c := screen / 2.0
	var off := Vector2(-sway.x * DRIFT.x * unit + whip * screen.x * WHIP_DIST, -sway.y * DRIFT.y * unit)
	var shy: float = -sway.x * LEAN + whip * WHIP_LEAN
	var shx: float = sway.y * TIP
	var sx: float = 1.0 - abs(sway.x) * 0.03 - abs(whip) * 0.3
	var x_axis := Vector2(sx, shy)
	var y_axis := Vector2(shx, 1.0)
	var origin: Vector2 = c + off - (x_axis * c.x + y_axis * c.y)
	return Transform2D(x_axis, y_axis, origin)

# just the sideways move, for pages that can't be sheared (the settings,
# profile... pages)
static func shift(screen: Vector2, sway: Vector2, whip: float) -> Vector2:
	var unit: float = screen.y / 720.0
	return Vector2(-sway.x * DRIFT.x * unit + whip * screen.x * WHIP_DIST, -sway.y * DRIFT.y * unit)

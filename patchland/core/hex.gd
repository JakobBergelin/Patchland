class_name Hex
## Axial hex coordinates, pointy-top. World unit = one hex radius.

const SQ3 := 1.7320508075688772
## E, NE, NW, W, SW, SE
const DIRS := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]


static func wpos(q: int, r: int) -> Vector2:
	return Vector2(SQ3 * (q + r / 2.0), 1.5 * r)


static func ax_round(q: float, r: float) -> Vector2i:
	var x := q
	var z := r
	var y := -x - z
	var rx := roundf(x)
	var ry := roundf(y)
	var rz := roundf(z)
	var dx := absf(rx - x)
	var dy := absf(ry - y)
	var dz := absf(rz - z)
	if dx > dy and dx > dz:
		rx = -ry - rz
	elif dy > dz:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(int(rx), int(rz))


static func from_world(p: Vector2) -> Vector2i:
	var rr := p.y / 1.5
	var qq := p.x / SQ3 - rr / 2.0
	return ax_round(qq, rr)

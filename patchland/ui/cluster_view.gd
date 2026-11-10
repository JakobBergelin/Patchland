class_name ClusterView
extends Control
## Draws a small group of tiles (the intro's hero picture).

var list: Array = []  # [{q, r, tile}]


static func hero_cluster(rng: RandomNumberGenerator) -> Array:
	var c := Tile.make(rng, 3, true)
	var out: Array = [{"q": 0, "r": 0, "tile": c}]
	for i in 6:
		var t := Tile.make(rng, 0, true)
		t.base[(i + 3) % 6] = c.edge(i)
		out.append({"q": Hex.DIRS[i].x, "r": Hex.DIRS[i].y, "tile": t})
	c.special = "windmill"
	out[2].tile.gold = true
	out[5].tile.special = "lighthouse"
	return out


func _draw() -> void:
	if list.is_empty() or size.x < 2:
		return
	var x0 := INF
	var x1 := -INF
	var y0 := INF
	var y1 := -INF
	for p in list:
		var wp := Hex.wpos(p.q, p.r)
		x0 = minf(x0, wp.x - Hex.SQ3 / 2 - 0.1)
		x1 = maxf(x1, wp.x + Hex.SQ3 / 2 + 0.1)
		y0 = minf(y0, wp.y - 1 - TileArt.PADT)
		y1 = maxf(y1, wp.y + 1 + TileArt.DEPTH + 0.1)
	var s := minf(minf((size.x - 8) / (x1 - x0), (size.y - 8) / (y1 - y0)), 60)
	var cx := (x0 + x1) / 2
	var cy := (y0 + y1) / 2
	var items := list.duplicate()
	items.sort_custom(func(a, b): return Hex.wpos(a.q, a.r).y < Hex.wpos(b.q, b.r).y)
	var k := s / TileArt.S0
	for it in items:
		var wp := Hex.wpos(it.q, it.r)
		var p := size / 2 + s * (wp - Vector2(cx, cy))
		draw_set_transform(p, 0, Vector2(k, k))
		TileArt.draw_tile(self, it.tile)
		if it.tile.special == "windmill":
			TileArt.sails(self, Vector2(0, -TileArt.HUB * TileArt.S0), 0.4 * TileArt.S0, 0.5)
	draw_set_transform(Vector2.ZERO)

class_name NavGrid extends RefCounted
## NavGrid: grid A* pathfinding for agents (Godot AStarGrid2D).
## Buildings and lakes are solid; rivers cost extra (wading) unless a road
## bridges them; predator/crime/restricted zones cost extra so paths route
## around danger; roads are cheap so people naturally prefer them.
## Paths are string-pulled (line-of-sight smoothed) so agents walk natural
## curves around obstacles instead of grid staircases.

const CELL := 2.0
const HALF_CELLS := 98   # ±196 m, covers the ±195 m playable area

var grid := AStarGrid2D.new()

func setup() -> void:
	grid.region = Rect2i(-HALF_CELLS, -HALF_CELLS, HALF_CELLS * 2, HALF_CELLS * 2)
	grid.cell_size = Vector2(CELL, CELL)
	grid.offset = Vector2(CELL * 0.5, CELL * 0.5)  # ids map to cell centers
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.update()

func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / CELL), floori(pos.z / CELL))

func world_of(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL + CELL * 0.5, 0.0, c.y * CELL + CELL * 0.5)

func in_bounds(c: Vector2i) -> bool:
	return grid.region.has_point(c)

# ---------------- Rebuild ----------------

func rebuild() -> void:
	if G.world == null or G.buildings == null:
		return
	grid.fill_solid_region(grid.region, false)
	grid.fill_weight_scale_region(grid.region, 1.0)
	for body in G.world.water_bodies:
		if body["type"] == "lake":
			_mark_disc(Vector3(body["x"], 0, body["z"]), float(body["radius"]) + 0.4, true, 1.0)
		else:
			_mark_river(body)
	for z in G.world.zones:
		var zc := Vector3(z["x"], 0, z["z"])
		match z["type"]:
			"predator", "crime":
				_mark_disc(zc, float(z["radius"]), false, 3.0)
			"restricted":
				_mark_disc(zc, float(z["radius"]), false, 4.0)
	for b in G.buildings.buildings.values():
		if G.buildings.WALKABLE.has(b.btype):
			continue
		_mark_rect(b.position, b.def["size"], 0.3)
	# roads last: cheap travel, and they double as bridges over rivers
	for rc in G.buildings.roads.keys():
		if in_bounds(rc):
			grid.set_point_weight_scale(rc, 0.55)

func _mark_disc(center: Vector3, radius: float, solid: bool, weight: float) -> void:
	var minc := cell_of(center - Vector3(radius, 0, radius))
	var maxc := cell_of(center + Vector3(radius, 0, radius))
	for cx in range(minc.x, maxc.x + 1):
		for cz in range(minc.y, maxc.y + 1):
			var c := Vector2i(cx, cz)
			if not in_bounds(c):
				continue
			if world_of(c).distance_to(center) > radius + CELL * 0.4:
				continue
			if solid:
				grid.set_point_solid(c, true)
			else:
				grid.set_point_weight_scale(c, maxf(grid.get_point_weight_scale(c), weight))

func _mark_rect(center: Vector3, sz: Vector2, margin: float) -> void:
	var hx := sz.x * 0.5 + margin
	var hz := sz.y * 0.5 + margin
	var minc := cell_of(center - Vector3(hx, 0, hz))
	var maxc := cell_of(center + Vector3(hx, 0, hz))
	for cx in range(minc.x, maxc.x + 1):
		for cz in range(minc.y, maxc.y + 1):
			var c := Vector2i(cx, cz)
			if in_bounds(c):
				grid.set_point_solid(c, true)

func _mark_river(body: Dictionary) -> void:
	var pts: Array = body["points"]
	var r: float = float(body["radius"])
	for i in range(pts.size() - 1):
		var a := Vector3(pts[i][0], 0, pts[i][1])
		var b := Vector3(pts[i + 1][0], 0, pts[i + 1][1])
		var seg_len := a.distance_to(b)
		var steps := maxi(int(seg_len / CELL), 1)
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / steps)
			_mark_disc(p, r, false, 2.5)

# ---------------- Queries ----------------

func is_solid_world(pos: Vector3) -> bool:
	var c := cell_of(pos)
	return in_bounds(c) and grid.is_point_solid(c)

func has_los(a: Vector3, b: Vector3) -> bool:
	var dx := b.x - a.x
	var dz := b.z - a.z
	var dist := sqrt(dx * dx + dz * dz)
	if dist < 0.01:
		return true
	var steps := int(dist) + 1
	for i in range(steps + 1):
		var f := float(i) / steps
		if is_solid_world(Vector3(a.x + dx * f, 0, a.z + dz * f)):
			return false
	return true

func _nearest_open(c: Vector2i) -> Vector2i:
	if in_bounds(c) and not grid.is_point_solid(c):
		return c
	for r in range(1, 6):
		for dx in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var n := c + Vector2i(dx, dz)
				if in_bounds(n) and not grid.is_point_solid(n):
					return n
	return Vector2i(-9999, -9999)

## Returns smoothed waypoints (excluding the start). Empty means no route.
## A clear straight line returns a single waypoint: the target itself.
func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if has_los(from, to):
		out.append(to)
		return out
	var a := _nearest_open(cell_of(from))
	var b := _nearest_open(cell_of(to))
	if a.x == -9999 or b.x == -9999:
		return out
	var pts: PackedVector2Array = grid.get_point_path(a, b, true)
	if pts.is_empty():
		return out
	var raw: Array = []
	for p2 in pts:
		raw.append(Vector3(p2.x, 0, p2.y))
	# string-pulling: keep only the corners the walk actually needs
	var cur := from
	var i := 0
	while i < raw.size():
		var j := raw.size() - 1
		while j > i and not has_los(cur, raw[j]):
			j -= 1
		out.append(raw[j])
		cur = raw[j]
		i = j + 1
	if has_los(cur, to):
		out.append(to)
	return out

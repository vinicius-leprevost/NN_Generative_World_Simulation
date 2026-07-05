class_name SpatialGrid extends RefCounted
## SpatialGrid: simple hash-grid spatial partitioning for fast
## radius queries over hundreds of agents.

var cell_size: float
var cells: Dictionary = {}   # Vector2i -> Dictionary(id -> true)
var where: Dictionary = {}   # id -> Vector2i

func _init(cs: float = 8.0) -> void:
	cell_size = cs

func _key(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.z / cell_size))

func update(id: int, pos: Vector3) -> void:
	var k := _key(pos)
	if where.has(id):
		var old: Vector2i = where[id]
		if old == k:
			return
		if cells.has(old):
			cells[old].erase(id)
	if not cells.has(k):
		cells[k] = {}
	cells[k][id] = true
	where[id] = k

func remove(id: int) -> void:
	if where.has(id):
		var old: Vector2i = where[id]
		if cells.has(old):
			cells[old].erase(id)
		where.erase(id)

func clear() -> void:
	cells.clear()
	where.clear()

func query_ids(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	var minc := _key(pos - Vector3(radius, 0, radius))
	var maxc := _key(pos + Vector3(radius, 0, radius))
	for cx in range(minc.x, maxc.x + 1):
		for cz in range(minc.y, maxc.y + 1):
			var c = cells.get(Vector2i(cx, cz))
			if c != null:
				out.append_array(c.keys())
	return out

class_name WorldManager extends Node3D
const Vis = preload("res://scripts/core/visuals.gd")

## WorldManager: terrain, sky/sun (day-night cycle), water bodies (rivers,
## lakes), wild food resources, and world zones (predator, livestock, etc).

const SIZE := 400.0
const HALF := 195.0

const ZONE_COLORS := {
	"predator": Color(0.9, 0.2, 0.2, 0.16),
	"livestock": Color(0.3, 0.85, 0.3, 0.16),
	"hunting": Color(0.95, 0.6, 0.2, 0.16),
	"restricted": Color(0.6, 0.3, 0.8, 0.16),
	"crime": Color(0.6, 0.1, 0.1, 0.16),
	"community": Color(0.3, 0.5, 0.95, 0.16),
}

var water_bodies: Array = []     # {id, type:"lake"/"river", x,z, radius, points:[[x,z],..]}
var water_points: Array = []     # Vector3 drink spots (from bodies; wells add via buildings)
var resources: Dictionary = {}   # id -> {id, x, z, amount, max}
var zones: Array = []            # {id, type, x, z, radius}
var next_id := 1

var sun: DirectionalLight3D
var env_node: WorldEnvironment
var environment: Environment
var _water_root: Node3D
var _res_root: Node3D
var _zone_root: Node3D
var _res_nodes: Dictionary = {}  # id -> MeshInstance3D
var _body_nodes: Dictionary = {} # id -> Node3D
var _zone_nodes: Dictionary = {} # id -> Node3D
var _regrow_timer := 0.0

func build() -> void:
	# Terrain
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SIZE, SIZE)
	ground.mesh = pm
	ground.material_override = Vis.mat(Color(0.27, 0.45, 0.25))
	add_child(ground)
	# Sun + environment
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)
	env_node = WorldEnvironment.new()
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	env_node.environment = environment
	add_child(env_node)
	# Containers
	_water_root = Node3D.new()
	_res_root = Node3D.new()
	_zone_root = Node3D.new()
	add_child(_water_root)
	add_child(_res_root)
	add_child(_zone_root)

func tick(dt: float) -> void:
	_update_sun()
	_regrow_timer += dt
	if _regrow_timer >= 4.0:
		_regrow(_regrow_timer)
		_regrow_timer = 0.0

func _update_sun() -> void:
	if G.clock == null:
		return
	var h: float = G.clock.hour
	var t := clampf((h - 6.0) / 12.0, 0.0, 1.0)  # 0 at dawn, 1 at dusk
	var daylight := sin(t * PI)
	if h < 6.0 or h > 18.0:
		daylight = 0.0
	sun.rotation_degrees = Vector3(-15.0 - 150.0 * t, -30.0, 0.0)
	sun.light_energy = maxf(daylight * 1.25, 0.04)
	environment.ambient_light_energy = 0.15 + daylight * 0.75

func _regrow(dt: float) -> void:
	var rate: float = 0.45 * Params.get_p("world.fertility") * Params.get_p("world.resources")
	if G.weather != null:
		rate *= G.weather.farm_mult()
	for id in resources.keys():
		var r: Dictionary = resources[id]
		if r["amount"] < r["max"]:
			r["amount"] = minf(r["amount"] + rate * dt, r["max"])
			_update_res_visual(id)

# ---------------- Water ----------------

func add_lake(pos: Vector3, radius := 10.0) -> void:
	var body := {"id": next_id, "type": "lake", "x": pos.x, "z": pos.z, "radius": radius, "points": []}
	next_id += 1
	water_bodies.append(body)
	_make_body_node(body)
	_rebuild_water_points()

func add_river(a: Vector3, b: Vector3) -> void:
	# Winding chain of segments from a to b
	var pts: Array = []
	var steps := maxi(int(a.distance_to(b) / 14.0), 2)
	var dir := (b - a)
	var side := Vector3(-dir.z, 0, dir.x).normalized()
	for i in range(steps + 1):
		var f := float(i) / float(steps)
		var p := a.lerp(b, f) + side * Rng.randf_range(-8.0, 8.0) * sin(f * PI)
		pts.append([p.x, p.z])
	var body := {"id": next_id, "type": "river", "x": a.x, "z": a.z, "radius": 2.5, "points": pts}
	next_id += 1
	water_bodies.append(body)
	_make_body_node(body)
	_rebuild_water_points()

func _make_body_node(body: Dictionary) -> void:
	var root := Node3D.new()
	_water_root.add_child(root)
	var wcol := Color(0.23, 0.5, 0.85, 0.85)
	if body["type"] == "lake":
		var disc := Vis.cylinder(body["radius"], 0.15, wcol)
		disc.position = Vector3(body["x"], 0.04, body["z"])
		root.add_child(disc)
	else:
		var pts: Array = body["points"]
		for i in range(pts.size() - 1):
			var p0 := Vector3(pts[i][0], 0.0, pts[i][1])
			var p1 := Vector3(pts[i + 1][0], 0.0, pts[i + 1][1])
			var seg := Vis.box(Vector3(p0.distance_to(p1) + 1.5, 0.12, 5.0), wcol)
			seg.position = (p0 + p1) * 0.5 + Vector3(0, 0.04, 0)
			seg.rotation.y = atan2(-(p1.z - p0.z), p1.x - p0.x)
			root.add_child(seg)
	_body_nodes[body["id"]] = root

func _rebuild_water_points() -> void:
	water_points.clear()
	for body in water_bodies:
		if body["type"] == "lake":
			var c := Vector3(body["x"], 0, body["z"])
			var r: float = body["radius"]
			for i in range(6):
				var ang := TAU * float(i) / 6.0
				water_points.append(c + Vector3(cos(ang), 0, sin(ang)) * (r + 0.8))
		else:
			for pt in body["points"]:
				water_points.append(Vector3(pt[0], 0, pt[1]))

func all_water_points() -> Array:
	# Natural water + completed wells / water storage
	var pts := water_points.duplicate()
	if G.buildings != null:
		for b in G.buildings.buildings.values():
			if b.def.get("provides", "") == "water":
				pts.append(b.position)
	return pts

func nearest_water(pos: Vector3, max_dist := 1e9) -> Dictionary:
	var best_d := max_dist
	var best := Vector3.ZERO
	var ok := false
	for p in all_water_points():
		# skip drink spots that buildings have been placed over
		if G.buildings != null and G.buildings.blocked(p):
			continue
		var d: float = pos.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
			ok = true
	return {"ok": ok, "pos": best, "dist": best_d}

func remove_water_near(pos: Vector3, radius := 15.0) -> void:
	for i in range(water_bodies.size() - 1, -1, -1):
		var body: Dictionary = water_bodies[i]
		if Vector3(body["x"], 0, body["z"]).distance_to(pos) < radius + body["radius"]:
			var n = _body_nodes.get(body["id"])
			if n != null:
				n.queue_free()
			_body_nodes.erase(body["id"])
			water_bodies.remove_at(i)
	_rebuild_water_points()

func in_water(pos: Vector3) -> bool:
	for body in water_bodies:
		if body["type"] == "lake":
			if Vector3(body["x"], 0, body["z"]).distance_to(pos) < body["radius"]:
				return true
	return false

# ---------------- Food resources ----------------

func add_resource(pos: Vector3, amount := 40.0) -> int:
	var r := {"id": next_id, "x": pos.x, "z": pos.z, "amount": amount, "max": amount}
	next_id += 1
	resources[r["id"]] = r
	var n := Vis.sphere(1.0, Color(0.2, 0.55, 0.2))
	n.position = Vector3(pos.x, 0.6, pos.z)
	_res_root.add_child(n)
	_res_nodes[r["id"]] = n
	_update_res_visual(r["id"])
	return r["id"]

func _update_res_visual(id: int) -> void:
	var r = resources.get(id)
	var n = _res_nodes.get(id)
	if r == null or n == null:
		return
	var s: float = clampf(0.3 + 0.7 * r["amount"] / maxf(r["max"], 1.0), 0.25, 1.0)
	n.scale = Vector3(s, s, s)

func nearest_resource(pos: Vector3, max_dist := 1e9) -> Dictionary:
	var best_d := max_dist
	var best: Dictionary = {}
	for r in resources.values():
		if r["amount"] < 2.0:
			continue
		var d: float = pos.distance_to(Vector3(r["x"], 0, r["z"]))
		if d < best_d:
			best_d = d
			best = r
	return best

func pick_food_target(pos: Vector3, max_dist := 70.0) -> Dictionary:
	# weighted-random rich resource nearby — spreads foragers out instead of
	# the whole settlement converging on the single nearest bush
	var candidates: Array = []
	for r in resources.values():
		if r["amount"] < 8.0:
			continue
		if pos.distance_to(Vector3(r["x"], 0, r["z"])) <= max_dist:
			candidates.append(r)
	if candidates.is_empty():
		return nearest_resource(pos, max_dist)
	candidates.sort_custom(func(a, b):
		return pos.distance_to(Vector3(a["x"], 0, a["z"])) < pos.distance_to(Vector3(b["x"], 0, b["z"])))
	return candidates[Rng.randi_range(0, mini(2, candidates.size() - 1))]

func take_food(id: int, amt: float) -> float:
	var r = resources.get(id)
	if r == null:
		return 0.0
	var taken: float = minf(amt, r["amount"])
	r["amount"] -= taken
	_update_res_visual(id)
	return taken

func resource_pos(id: int) -> Vector3:
	var r = resources.get(id)
	if r == null:
		return Vector3.ZERO
	return Vector3(r["x"], 0, r["z"])

func remove_resource(id: int) -> void:
	var n = _res_nodes.get(id)
	if n != null:
		n.queue_free()
	_res_nodes.erase(id)
	resources.erase(id)

# ---------------- Zones ----------------

func add_zone(type: String, pos: Vector3, radius := 18.0) -> void:
	var z := {"id": next_id, "type": type, "x": pos.x, "z": pos.z, "radius": radius}
	next_id += 1
	zones.append(z)
	var col: Color = ZONE_COLORS.get(type, Color(0.5, 0.5, 0.5, 0.15))
	var disc := Vis.cylinder(radius, 0.06, col)
	disc.position = Vector3(pos.x, 0.03, pos.z)
	_zone_root.add_child(disc)
	_zone_nodes[z["id"]] = disc

func remove_zone_near(pos: Vector3) -> void:
	for i in range(zones.size() - 1, -1, -1):
		var z: Dictionary = zones[i]
		if Vector3(z["x"], 0, z["z"]).distance_to(pos) < z["radius"]:
			var n = _zone_nodes.get(z["id"])
			if n != null:
				n.queue_free()
			_zone_nodes.erase(z["id"])
			zones.remove_at(i)
			return

func zones_of(type: String) -> Array:
	var out: Array = []
	for z in zones:
		if z["type"] == type:
			out.append(z)
	return out

func in_zone(pos: Vector3, type: String) -> bool:
	for z in zones:
		if z["type"] == type and Vector3(z["x"], 0, z["z"]).distance_to(pos) < z["radius"]:
			return true
	return false

# ---------------- Misc ----------------

func clamp_pos(p: Vector3) -> Vector3:
	return Vector3(clampf(p.x, -HALF, HALF), 0.0, clampf(p.z, -HALF, HALF))

func random_pos(margin := 20.0) -> Vector3:
	var h := HALF - margin
	return Vector3(Rng.randf_range(-h, h), 0, Rng.randf_range(-h, h))

func apply_weather_visuals(s: String) -> void:
	match s:
		"rain":
			environment.fog_enabled = true
			environment.fog_density = 0.004
		"storm":
			environment.fog_enabled = true
			environment.fog_density = 0.012
		"flood":
			environment.fog_enabled = true
			environment.fog_density = 0.006
		_:
			environment.fog_enabled = false

func clear_all() -> void:
	for n in _body_nodes.values():
		n.queue_free()
	for n in _res_nodes.values():
		n.queue_free()
	for n in _zone_nodes.values():
		n.queue_free()
	_body_nodes.clear()
	_res_nodes.clear()
	_zone_nodes.clear()
	water_bodies.clear()
	water_points.clear()
	resources.clear()
	zones.clear()
	next_id = 1

func to_dict() -> Dictionary:
	var res: Array = []
	for r in resources.values():
		res.append({"id": r["id"], "x": r["x"], "z": r["z"], "amount": r["amount"], "max": r["max"]})
	return {"water_bodies": water_bodies, "resources": res, "zones": zones, "next_id": next_id}

func from_dict(d: Dictionary) -> void:
	clear_all()
	next_id = int(d.get("next_id", 1))
	for body in d.get("water_bodies", []):
		body["id"] = int(body["id"])
		water_bodies.append(body)
		_make_body_node(body)
	_rebuild_water_points()
	for r in d.get("resources", []):
		var id := int(r["id"])
		var rr := {"id": id, "x": float(r["x"]), "z": float(r["z"]),
			"amount": float(r["amount"]), "max": float(r["max"])}
		resources[id] = rr
		var n := Vis.sphere(1.0, Color(0.2, 0.55, 0.2))
		n.position = Vector3(rr["x"], 0.6, rr["z"])
		_res_root.add_child(n)
		_res_nodes[id] = n
		_update_res_visual(id)
	for z in d.get("zones", []):
		add_zone(str(z["type"]), Vector3(float(z["x"]), 0, float(z["z"])), float(z["radius"]))

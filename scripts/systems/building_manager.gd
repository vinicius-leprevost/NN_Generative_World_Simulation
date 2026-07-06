class_name BuildingManager extends Node3D
const Building = preload("res://scripts/world/building.gd")
const BuildingDB = preload("res://scripts/data/building_db.gd")
const ConstructionSite = preload("res://scripts/world/construction_site.gd")
const SpatialGrid = preload("res://scripts/core/spatial_grid.gd")
const Vis = preload("res://scripts/core/visuals.gd")

## BuildingManager: buildings, construction sites, roads, power grid,
## the society construction planner, jobs, and food logistics.

const ROAD_CELL := 2.0
const WALKABLE := ["farm", "park", "animal_pen", "well", "street_light"]
const PROJECT_SEARCH_MAX_RADIUS := 185.0
const PROJECT_SEARCH_RANDOM_TRIES := 80

var buildings: Dictionary = {}   # id -> Building
var sites: Dictionary = {}       # id -> ConstructionSite
var roads: Dictionary = {}       # Vector2i -> true
var next_id := 1
var grid_b := SpatialGrid.new(8.0)
var completed_count := 0
var abandoned_count := 0

var nav := NavGrid.new()     # A* pathfinding over buildings/water/roads
var nav_dirty := true
var _nav_timer := 0.0
var _road_mmi: MultiMeshInstance3D
var _roads_dirty := false
var _planner_timer := 0.0
var _power_timer := 0.0
var _light_timer := 0.0
var _prod_timer := 0.0
var _last_crimes := 0
var _last_predator_kills := 0

func build() -> void:
	nav.setup()
	_road_mmi = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var bm := BoxMesh.new()
	bm.size = Vector3(ROAD_CELL, 0.08, ROAD_CELL)
	bm.material = Vis.mat(Color(0.32, 0.32, 0.34))
	mm.mesh = bm
	_road_mmi.multimesh = mm
	add_child(_road_mmi)

# ---------------- Buildings ----------------

func spawn_building(btype: String, pos: Vector3) -> Building:
	var b := Building.new()
	add_child(b)
	b.setup(next_id, btype, G.world.clamp_pos(pos))
	next_id += 1
	buildings[b.id] = b
	grid_b.update(b.id, b.position)
	_recompute_power()
	nav_dirty = true
	return b

func demolish(bid: int) -> void:
	var b = buildings.get(bid)
	if b == null:
		return
	for pid in b.workers.keys():
		var p = G.people.get_person(pid)
		if p != null:
			p.job_type = ""
			p.job_building = -1
	for pid in b.residents:
		var p2 = G.people.get_person(pid)
		if p2 != null:
			p2.home_id = -1
	grid_b.remove(bid)
	buildings.erase(bid)
	b.queue_free()
	_recompute_power()
	nav_dirty = true

func get_building(bid: int) -> Building:
	return buildings.get(bid)

func list_type(btype: String) -> Array:
	var out: Array = []
	for b in buildings.values():
		if b.btype == btype:
			out.append(b)
	return out

func count(btype: String) -> int:
	return list_type(btype).size()

func planned_count(btype: String) -> int:
	var total := count(btype)
	for s in sites.values():
		if s.btype == btype:
			total += 1
	return total

func nearest(btype: String, pos: Vector3) -> Building:
	var best: Building = null
	var best_d := 1e9
	for b in buildings.values():
		if b.btype != btype:
			continue
		var d: float = pos.distance_to(b.position)
		if d < best_d:
			best_d = d
			best = b
	return best

func nearest_provider(provides: String, pos: Vector3) -> Building:
	var best: Building = null
	var best_d := 1e9
	for b in buildings.values():
		if b.def.get("provides", "") != provides:
			continue
		var d: float = pos.distance_to(b.position)
		if d < best_d:
			best_d = d
			best = b
	return best

func find_free_home(pos: Vector3) -> Building:
	var best: Building = null
	var best_d := 1e9
	for b in buildings.values():
		if b.def.get("provides", "") != "shelter":
			continue
		if b.residents.size() >= int(b.def["capacity"]):
			continue
		var d: float = pos.distance_to(b.position)
		if d < best_d:
			best_d = d
			best = b
	return best

func blocked(pos: Vector3) -> bool:
	for bid in grid_b.query_ids(pos, 8.0):
		var b = buildings.get(bid)
		if b == null or WALKABLE.has(b.btype):
			continue
		var sz: Vector2 = b.def["size"]
		if absf(pos.x - b.position.x) < sz.x * 0.5 + 0.3 and absf(pos.z - b.position.z) < sz.y * 0.5 + 0.3:
			return true
	return false

func nearest_stocked_food(pos: Vector3) -> Building:
	# communal food: farms, warehouses, shelters, barns — not stores (those charge)
	var best: Building = null
	var best_d := 1e9
	for b in buildings.values():
		var prov: String = b.def.get("provides", "")
		if prov != "food_production" and prov != "storage" and prov != "shelter" and prov != "animal_shelter":
			continue
		if b.stock.get("food", 0.0) < 1.0:
			continue
		var d: float = pos.distance_to(b.position)
		if d < best_d:
			best_d = d
			best = b
	return best

func deposit_food(pos: Vector3, amount: float) -> void:
	var best: Building = null
	var best_d := 1e9
	for b in buildings.values():
		var prov: String = b.def.get("provides", "")
		if prov == "food_store" or prov == "storage" or prov == "food_production" or prov == "shelter":
			var d: float = pos.distance_to(b.position)
			if d < best_d:
				best_d = d
				best = b
	if best != null and best_d < 80.0:
		best.stock["food"] += amount
	else:
		G.world.add_resource(pos + Vector3(1, 0, 1), amount)

# ---------------- Jobs ----------------

func find_job_for(p) -> bool:
	if not sites_needing_builders().is_empty() and _assign_role_if_open(p, "builder"):
		return true
	for b in buildings.values():
		var jobs: Dictionary = b.def.get("jobs", {})
		for role in jobs.keys():
			if _try_assign_role(p, b, role, jobs[role]):
				return true
	return false

func _assign_role_if_open(p, wanted_role: String) -> bool:
	for b in buildings.values():
		var jobs: Dictionary = b.def.get("jobs", {})
		if jobs.has(wanted_role) and _try_assign_role(p, b, wanted_role, jobs[wanted_role]):
			return true
	return false

func _try_assign_role(p, b: Building, role: String, base_slots: Variant) -> bool:
	if role == "president":
		return false
	if b.worker_count(role) >= _role_slots(role, base_slots):
		return false
	if not _person_qualified_for_role(p, role):
		return false
	b.workers[p.id] = role
	p.job_type = role
	p.job_building = b.id
	return true

func _role_slots(role: String, base_slots: Variant) -> int:
	if role == "president":
		return 1
	var avail := Params.get_p("eco.job_avail")
	var slots := int(ceil(float(base_slots) * avail))
	if role == "police":
		slots = int(ceil(float(base_slots) * Params.get_p("soc.police_rate") * avail))
	return slots

func _person_qualified_for_role(p, role: String) -> bool:
	if role == "president":
		return false
	if role == "politician" and (p.education < 20.0 and p.traits["ambition"] < 0.6):
		return false
	if role == "doctor" and p.education < 25.0 and p.skills.get("medicine", 0.0) < 0.3:
		return false
	if role == "teacher" and p.education < 20.0:
		return false
	return true

func builder_slot_count() -> int:
	var total := 0
	for b in buildings.values():
		var jobs: Dictionary = b.def.get("jobs", {})
		if jobs.has("builder"):
			total += _role_slots("builder", jobs["builder"])
	return total

func builder_count() -> int:
	var total := 0
	for p in G.people.alive_list():
		if p.job_type == "builder":
			total += 1
	return total

func can_person_build(p) -> bool:
	if p.job_type == "builder":
		return true
	# Bootstrap rule: before a construction industry exists, settlers can pitch in.
	return builder_slot_count() == 0

func total_job_slots(include_president := false) -> int:
	var total := 0
	for b in buildings.values():
		var jobs: Dictionary = b.def.get("jobs", {})
		for role in jobs.keys():
			if role == "president" and not include_president:
				continue
			total += _role_slots(role, jobs[role])
	return total

func filled_job_slots(include_president := false) -> int:
	var total := 0
	for p in G.people.alive_list():
		if p.job_type == "":
			continue
		if p.job_type == "president" and not include_president:
			continue
		total += 1
	return total

# ---------------- Roads ----------------

func road_key(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / ROAD_CELL), floori(pos.z / ROAD_CELL))

func road_at(pos: Vector3) -> bool:
	return roads.has(road_key(pos))

func road_near(pos: Vector3) -> bool:
	# within one road cell (~2m) — forgiving enough for driving/walking along roads
	var k := road_key(pos)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if roads.has(Vector2i(k.x + dx, k.y + dz)):
				return true
	return false

func has_roads() -> bool:
	return not roads.is_empty()

func add_road_cell(pos: Vector3) -> void:
	roads[road_key(pos)] = true
	_roads_dirty = true
	nav_dirty = true

func add_road_line(a: Vector3, b: Vector3) -> void:
	var dist := a.distance_to(b)
	var steps := maxi(int(dist / (ROAD_CELL * 0.5)), 1)
	for i in range(steps + 1):
		add_road_cell(a.lerp(b, float(i) / float(steps)))
	Events.add("construction", "A road was built")

func _rebuild_roads() -> void:
	var mm := _road_mmi.multimesh
	mm.instance_count = roads.size()
	var i := 0
	for cell in roads.keys():
		var t := Transform3D(Basis.IDENTITY,
			Vector3(cell.x * ROAD_CELL + ROAD_CELL * 0.5, 0.05, cell.y * ROAD_CELL + ROAD_CELL * 0.5))
		mm.set_instance_transform(i, t)
		i += 1
	_roads_dirty = false

# ---------------- Construction ----------------

func create_site(btype: String, pos: Vector3, sponsor := "society") -> ConstructionSite:
	var s := ConstructionSite.new()
	add_child(s)
	s.setup(next_id, btype, G.world.clamp_pos(pos), sponsor)
	next_id += 1
	sites[s.id] = s
	Events.add("construction", "Construction started: %s" % s.def["name"])
	return s

func get_site(sid: int) -> ConstructionSite:
	return sites.get(sid)

func active_sites() -> Array:
	return sites.values()

func sites_needing_builders() -> Array:
	var out: Array = []
	for s in sites.values():
		if s.has_open_worker_slot():
			out.append(s)
	return out

func find_project_spot(center: Vector3, btype: String) -> Vector3:
	return _find_spot(center, btype)

func cancel_site(sid: int) -> void:
	var s = sites.get(sid)
	if s == null:
		return
	abandoned_count += 1
	Events.add("construction", "Construction abandoned: %s" % s.def["name"])
	sites.erase(sid)
	s.queue_free()

func finish_site(sid: int) -> void:
	var s = sites.get(sid)
	if s == null:
		return
	var b := spawn_building(s.btype, s.position)
	completed_count += 1
	for pid in s.workers:
		var p = G.people.get_person(pid)
		if p != null and p.action == "build":
			p.action = "idle"
			p.brain.reinforce("build", 0.5)
	sites.erase(sid)
	s.queue_free()
	Events.add("construction", "Construction completed: %s" % b.def["name"])
	match b.btype:
		"school": Events.add("construction", "A school opened")
		"hospital": Events.add("construction", "A hospital opened")
		"prison": Events.add("construction", "A prison opened")
		"police_station": Events.add("construction", "A police station opened")
		"construction_yard": Events.add("construction", "A construction yard opened")
		"well": Events.add("construction", "A well was built")
		"barn": Events.add("construction", "A barn was built")
		"farm": Events.add("construction", "A farm was created")

# ---------------- Power ----------------

func _recompute_power() -> void:
	var plants: Array = list_type("power_plant")
	var req := Params.get_p("con.power_req") > 0.5
	for b in buildings.values():
		if not req:
			b.powered = true
			continue
		b.powered = false
		for pl in plants:
			if b.position.distance_to(pl.position) < 80.0:
				b.powered = true
				break

# ---------------- Tick ----------------

func tick(dt: float) -> void:
	for s in sites.values():
		s.tick(dt)
	if _roads_dirty:
		_rebuild_roads()
	_nav_timer += dt
	if nav_dirty and _nav_timer >= 1.0:
		_nav_timer = 0.0
		nav_dirty = false
		nav.rebuild()
	_production(dt)
	_maintenance(dt)
	_planner_timer += dt
	if _planner_timer >= 30.0:
		_planner_timer = 0.0
		_society_planner()
	_power_timer += dt
	if _power_timer >= 10.0:
		_power_timer = 0.0
		_recompute_power()
	_light_timer += dt
	if _light_timer >= 1.0:
		_light_timer = 0.0
		_update_street_lights()
		for b in buildings.values():
			b.refresh_label()

func _production(dt: float) -> void:
	_prod_timer += dt
	if _prod_timer < 2.0:
		return
	var pdt := _prod_timer
	_prod_timer = 0.0
	var has_processing := count("food_processing") > 0
	for b in buildings.values():
		match b.def.get("provides", ""):
			"food_production":
				var farmers: int = b.present_workers()
				if farmers > 0:
					var water_ok := 1.0
					if Params.get_p("con.water_req") > 0.5:
						var w: Dictionary = G.world.nearest_water(b.position, 1e9)
						water_ok = 1.0 if (w["ok"] and w["dist"] < 60.0) else 0.25
					b.stock["food"] += farmers * 0.8 * pdt * G.weather.farm_mult() \
						* Params.get_p("world.fertility") * water_ok
			"food_processing":
				# pull raw harvest from farms and refine it (adds value)
				var hands: int = b.present_workers()
				if hands > 0:
					for src in buildings.values():
						if src.def.get("provides", "") == "food_production" and src.stock["food"] > 5.0:
							var moved: float = minf(0.6 * hands * pdt, src.stock["food"] - 5.0)
							src.stock["food"] -= moved
							b.stock["food"] += moved * 1.2
							break
			"food_store":
				if b.present_workers() > 0:
					# stores restock processed food; raw farm food only while
					# no food-processing industry exists yet
					if b.stock["food"] < 40.0:
						for src in buildings.values():
							var sp: String = src.def.get("provides", "")
							var ok_source: bool = sp == "food_processing" or sp == "storage" \
								or (sp == "food_production" and not has_processing)
							if ok_source and src.stock["food"] > 5.0:
								var moved: float = minf(0.5 * pdt, src.stock["food"] - 5.0)
								src.stock["food"] -= moved
								b.stock["food"] += moved
								break
					# bottled water: fast with wells/storage, a trickle without
					if b.stock.get("water", 0.0) < 50.0:
						var infra: int = count("well") + count("water_storage")
						b.stock["water"] = b.stock.get("water", 0.0) \
							+ (0.8 if infra > 0 else 0.15) * pdt

func _maintenance(dt: float) -> void:
	var decay := Params.get_p("con.maintenance") * dt * 0.008
	if decay <= 0.0:
		return
	for b in buildings.values():
		b.hp -= decay
		if b.hp <= 0.0:
			Events.add("construction", "%s collapsed from neglect" % b.def["name"])
			demolish(b.id)
			return

func _update_street_lights() -> void:
	var night: bool = G.clock.is_night()
	var lights: Array = list_type("street_light")
	if lights.is_empty():
		return
	var campos: Vector3 = G.cam.camera.global_position if G.cam != null else Vector3.ZERO
	# budget applies to POWERED lights only — dark poles must not eat slots
	var powered: Array = lights.filter(func(l): return l.powered)
	powered.sort_custom(func(a, b): return a.position.distance_to(campos) < b.position.distance_to(campos))
	var budget: int = G.perf["max_lights"]
	for l in lights:
		if l.light != null:
			l.light.visible = false
	for i in range(mini(budget, powered.size())):
		var l = powered[i]
		if l.light != null:
			l.light.visible = night

# ---------------- Society construction planner ----------------

func _society_planner() -> void:
	if G.politics != null and G.politics.government_controls_planning():
		return
	var people: Array = G.people.alive_list()
	if people.size() < 3:
		return
	var site_cap := 3
	if planned_count("construction_yard") == 0 and people.size() >= 8:
		site_cap = 4
	if sites.size() >= site_cap:
		return
	var centroid := Vector3.ZERO
	for p in people:
		centroid += p.position
	centroid /= people.size()
	var adults := 0
	var children := 0
	var homeless := 0
	var sick := 0
	var hunger_sum := 0.0
	for p in people:
		hunger_sum += p.hunger
		if p.is_adult():
			adults += 1
			if p.home_id < 0:
				homeless += 1
		elif p.stage() == "child" or p.stage() == "teen":
			children += 1
		if p.sick:
			sick += 1
	if adults < 2:
		return
	var avg_hunger := hunger_sum / people.size()
	var pop := people.size()
	var new_crimes: int = G.crime.stats["total"] - _last_crimes
	var new_pred_kills: int = (G.animals.humans_killed + G.animals.livestock_killed) - _last_predator_kills
	var open_sites := sites_needing_builders().size()

	var choice := ""
	var w: Dictionary = G.world.nearest_water(centroid, 1e9)
	if (not w["ok"] or w["dist"] > 55.0 or G.weather.is_drought()) and planned_count("well") + planned_count("water_storage") < pop / 8 + 1:
		choice = "well"
	elif planned_count("farm") == 0 and pop >= 8:
		choice = "farm"
	elif planned_count("construction_yard") == 0 and pop >= 8:
		choice = "construction_yard"
	elif (avg_hunger > 55.0 or planned_count("farm") < pop / 8 + 1) and planned_count("farm") < pop / 8 + 1:
		choice = "farm"
	elif open_sites > 0 and builder_count() < mini(open_sites * 2, maxi(1, int(pop / 4))) and planned_count("construction_yard") < int(pop / 80) + 1:
		choice = "construction_yard"
	elif homeless > 2:
		choice = "home" if pop < 30 else ("apartment" if Rng.chance(0.5) else "home")
	elif children > 5 and planned_count("school") == 0 and pop > 14:
		choice = "school"
	elif (sick > 3 or pop > 25) and planned_count("hospital") == 0:
		choice = "hospital"
	elif new_crimes > 4 and planned_count("police_station") == 0:
		choice = "police_station"
	elif G.crime.stats["arrests"] > 2 and planned_count("prison") == 0:
		choice = "prison"
	elif pop > 14 and planned_count("farm") > 0 and planned_count("store") + planned_count("market") == 0:
		choice = "store"
	elif pop > 12 and planned_count("food_processing") == 0 and planned_count("farm") > 0 \
			and planned_count("store") + planned_count("market") > 0:
		choice = "food_processing"
	elif new_pred_kills > 2 and planned_count("watchtower") < 2:
		choice = "watchtower"
	elif not G.animals.list_livestock().is_empty() and planned_count("animal_pen") + planned_count("barn") == 0:
		choice = "animal_pen"
	elif pop > 28 and planned_count("power_plant") == 0:
		choice = "power_plant"
	elif pop > 24 and planned_count("government") == 0:
		choice = "government"
	elif planned_count("power_plant") > 0 and planned_count("street_light") < pop / 6:
		choice = "street_light"
	elif buildings.size() >= 5 and roads.size() < buildings.size() * 6:
		_plan_road()
		_last_crimes = G.crime.stats["total"]
		_last_predator_kills = G.animals.humans_killed + G.animals.livestock_killed
		return
	_last_crimes = G.crime.stats["total"]
	_last_predator_kills = G.animals.humans_killed + G.animals.livestock_killed
	if choice == "":
		return
	var spot := _find_spot(centroid, choice)
	if spot == Vector3.INF:
		return
	create_site(choice, spot, "society")

func _plan_road() -> void:
	var blist: Array = buildings.values().filter(func(b): return not WALKABLE.has(b.btype))
	if blist.size() < 2:
		return
	var a = Rng.pick(blist)
	var b = Rng.pick(blist)
	if a == b or a.position.distance_to(b.position) < 8.0:
		return
	add_road_line(a.position + Vector3(0, 0, a.def["size"].y * 0.5 + 1.5),
		b.position + Vector3(0, 0, b.def["size"].y * 0.5 + 1.5))

func _find_spot(center: Vector3, btype: String) -> Vector3:
	var def := BuildingDB.get_def(btype)
	var sz: Vector2 = def["size"]
	var step: float = maxf(maxf(sz.x, sz.y) + 6.0, 10.0)
	var spread := minf(24.0 + buildings.size() * 1.5 + sites.size() * 2.0, 75.0)
	for i in range(PROJECT_SEARCH_RANDOM_TRIES):
		var ang := Rng.randf() * TAU
		var dist := Rng.randf_range(8.0, spread)
		var pos: Vector3 = G.world.clamp_pos(center + Vector3(cos(ang) * dist, 0, sin(ang) * dist))
		if _spot_is_clear(pos, sz):
			return pos
	var radius := step
	while radius <= PROJECT_SEARCH_MAX_RADIUS:
		var steps := maxi(16, int(ceil(TAU * radius / step)))
		var offset := fposmod(float(next_id + buildings.size()) * 0.61803398875, 1.0) * TAU
		for i in range(steps):
			var ang := offset + TAU * float(i) / float(steps)
			var pos: Vector3 = G.world.clamp_pos(center + Vector3(cos(ang) * radius, 0, sin(ang) * radius))
			if _spot_is_clear(pos, sz):
				return pos
		radius += step
	return _find_nearest_map_spot(center, sz, step)

func _find_nearest_map_spot(center: Vector3, sz: Vector2, step: float) -> Vector3:
	var limit := 190.0
	var best := Vector3.INF
	var best_d := INF
	var cells := int(floor((limit * 2.0) / step))
	for xi in range(cells + 1):
		for zi in range(cells + 1):
			var pos := Vector3(-limit + float(xi) * step, 0, -limit + float(zi) * step)
			if not _spot_is_clear(pos, sz):
				continue
			var d := center.distance_squared_to(pos)
			if d < best_d:
				best_d = d
				best = pos
	return best

func _spot_is_clear(pos: Vector3, sz: Vector2) -> bool:
	if G.world.in_water(pos) or G.world.in_zone(pos, "predator") or G.world.in_zone(pos, "restricted"):
		return false
	# Never build directly over water access or wild food.
	var margin := maxf(sz.x, sz.y) * 0.5 + 1.5
	var wnear: Dictionary = G.world.nearest_water(pos, margin + 0.01)
	if wnear["ok"]:
		return false
	var rnear: Dictionary = G.world.nearest_resource(pos, margin)
	if not rnear.is_empty():
		return false
	var query_radius := maxf(14.0, maxf(sz.x, sz.y) + 20.0)
	for bid in grid_b.query_ids(pos, query_radius):
		var other = buildings.get(bid)
		if other != null and _footprints_overlap(pos, sz, other.position, other.def["size"], 3.5):
			return false
	for s in sites.values():
		if _footprints_overlap(pos, sz, s.position, s.def["size"], 3.0):
			return false
	return true

func _footprints_overlap(a_pos: Vector3, a_size: Vector2, b_pos: Vector3, b_size: Vector2, clearance: float) -> bool:
	var x_gap: float = (a_size.x + b_size.x) * 0.5 + clearance
	var z_gap: float = (a_size.y + b_size.y) * 0.5 + clearance
	return absf(a_pos.x - b_pos.x) < x_gap and absf(a_pos.z - b_pos.z) < z_gap

# ---------------- Persistence ----------------

func clear_all() -> void:
	for b in buildings.values():
		b.queue_free()
	for s in sites.values():
		s.queue_free()
	buildings.clear()
	sites.clear()
	roads.clear()
	grid_b.clear()
	next_id = 1
	completed_count = 0
	abandoned_count = 0
	_roads_dirty = true
	nav_dirty = true

func to_dict() -> Dictionary:
	var blist: Array = []
	for b in buildings.values():
		blist.append(b.serialize())
	var slist: Array = []
	for s in sites.values():
		slist.append(s.serialize())
	var rlist: Array = []
	for cell in roads.keys():
		rlist.append("%d:%d" % [cell.x, cell.y])
	return {"buildings": blist, "sites": slist, "roads": rlist, "next_id": next_id,
		"completed": completed_count, "abandoned": abandoned_count}

func from_dict(d: Dictionary) -> void:
	clear_all()
	next_id = int(d.get("next_id", 1))
	completed_count = int(d.get("completed", 0))
	abandoned_count = int(d.get("abandoned", 0))
	for bd in d.get("buildings", []):
		var b := Building.new()
		add_child(b)
		b.setup(int(bd["id"]), str(bd["btype"]), Vector3(float(bd["x"]), 0, float(bd["z"])))
		b.deserialize(bd)
		buildings[b.id] = b
		grid_b.update(b.id, b.position)
	for sd in d.get("sites", []):
		var s := ConstructionSite.new()
		add_child(s)
		s.setup(int(sd["id"]), str(sd["btype"]), Vector3(float(sd["x"]), 0, float(sd["z"])), str(sd.get("sponsor", "society")))
		s.deserialize(sd)
		sites[s.id] = s
	for key in d.get("roads", []):
		var parts: Array = str(key).split(":")
		if parts.size() == 2:
			roads[Vector2i(int(parts[0]), int(parts[1]))] = true
	_roads_dirty = true
	_recompute_power()

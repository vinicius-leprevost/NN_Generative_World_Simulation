class_name AnimalManager extends Node3D
const Animal = preload("res://scripts/agents/animal.gd")
const SpeciesDB = preload("res://scripts/data/species_db.gd")
const SpatialGrid = preload("res://scripts/core/spatial_grid.gd")
const WorldManager = preload("res://scripts/systems/world_manager.gd")

## AnimalManager: owns all Animal agents. Ambient spawning, herds and packs,
## predation bookkeeping, domestication, hunting, production counters.

const CORPSE_TIME := 25.0
const MAX_ANIMALS := 260

var animals: Dictionary = {}   # id -> Animal
var next_id := 1
var grid := SpatialGrid.new(10.0)
var herds: Dictionary = {}     # id -> {"species": s, "members": [ids]}
var next_herd := 1
var births := 0
var deaths := 0
var deaths_by_cause: Dictionary = {}
var hunted := 0
var humans_killed := 0
var livestock_killed := 0
var eggs_produced := 0.0
var milk_produced := 0.0
var _spawn_timer := 0.0
var _herd_timer := 0.0

func spawn(species: String, pos: Vector3, opts: Dictionary = {}) -> Animal:
	var a := Animal.new()
	add_child(a)
	a.setup(next_id, species, G.world.clamp_pos(pos), opts)
	next_id += 1
	animals[a.id] = a
	grid.update(a.id, a.position)
	return a

func get_animal(aid: int) -> Animal:
	return animals.get(aid)

func nearby(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for aid in grid.query_ids(pos, radius):
		var a = animals.get(aid)
		if a != null and a.alive and a.position.distance_to(pos) <= radius:
			out.append(a)
	return out

func predators_near(pos: Vector3, radius: float) -> Array:
	var out: Array = []
	for a in nearby(pos, radius):
		if a.is_predator():
			out.append(a)
	return out

func find_prey(pred: Animal) -> Animal:
	var best: Animal = null
	var best_d := 40.0
	for a in nearby(pred.position, 40.0):
		if a.id == pred.id or a.is_predator() or a.species == pred.species:
			continue
		var d: float = pred.position.distance_to(a.position)
		# prey guarded by 3+ nearby humans is too risky
		if G.people.nearby(a.position, 8.0).size() >= 3:
			continue
		if d < best_d:
			best_d = d
			best = a
	return best

func tick(dt: float) -> void:
	var now: float = G.clock.total_time
	for a in animals.values():
		a.tick(dt)
		if a.alive:
			grid.update(a.id, a.position)
		elif a.death_time > 0.0 and now - a.death_time > CORPSE_TIME:
			remove(a.id)
	_ambient_spawn(dt)
	_herd_timer += dt
	if _herd_timer >= 12.0:
		_form_herds()
		_reproduction()
		_herd_timer = 0.0

func _ambient_spawn(dt: float) -> void:
	_spawn_timer += dt
	if _spawn_timer < 25.0:
		return
	_spawn_timer = 0.0
	if animals.size() >= MAX_ANIMALS:
		return
	if not Rng.chance(Params.get_p("ani.spawn_rate") * 0.35):
		return
	var predator_zones: Array = G.world.zones_of("predator")
	if Rng.chance(0.3) and not predator_zones.is_empty():
		var z: Dictionary = Rng.pick(predator_zones)
		var sp: String = Rng.pick(SpeciesDB.predator_list())
		spawn(sp, Vector3(z["x"] + Rng.randf_range(-10, 10), 0, z["z"] + Rng.randf_range(-10, 10)))
		Events.add("animal", "A wild %s appeared" % sp)
	else:
		var wild := ["deer", "deer", "chicken", "goat", "sheep", "dog"]
		var sp2: String = Rng.pick(wild)
		var edge: Vector3 = G.world.random_pos(15.0)
		edge = edge.normalized() * (WorldManager.HALF - 25.0) if edge.length() > 1.0 else Vector3(100, 0, 100)
		spawn(sp2, edge)
		Events.add("animal", "A wild %s wandered in" % sp2)

func _form_herds() -> void:
	# prune herds whose members have all died
	for hid in herds.keys().duplicate():
		var alive_members := 0
		for aid in herds[hid]["members"]:
			var m = animals.get(aid)
			if m != null and m.alive:
				alive_members += 1
		if alive_members == 0:
			herds.erase(hid)
	for a in animals.values():
		if not a.alive or a.herd_id >= 0 or not a.is_adult():
			continue
		var is_pack: bool = a.def["pack"]
		if not (a.def["herd"] or is_pack):
			continue
		var rate := Params.get_p("ani.pack_rate") if is_pack else Params.get_p("ani.herd_rate")
		if not Rng.chance(rate * 0.4):
			continue
		var mates: Array = []
		for o in nearby(a.position, 20.0):
			if o.id != a.id and o.species == a.species:
				mates.append(o)
		if mates.is_empty():
			continue
		var joined := false
		for m in mates:
			if m.herd_id >= 0 and herds.has(m.herd_id):
				a.herd_id = m.herd_id
				herds[m.herd_id]["members"].append(a.id)
				joined = true
				break
		if not joined:
			var h := {"species": a.species, "members": [a.id, mates[0].id]}
			herds[next_herd] = h
			a.herd_id = next_herd
			mates[0].herd_id = next_herd
			next_herd += 1
			var word := "pack" if is_pack else "herd"
			Events.add("animal", "A %s %s formed" % [a.species, word])

func herd_centroid(hid: int) -> Variant:
	var h = herds.get(hid)
	if h == null:
		return null
	var sum := Vector3.ZERO
	var n := 0
	for aid in h["members"]:
		var a = animals.get(aid)
		if a != null and a.alive:
			sum += a.position
			n += 1
	if n == 0:
		return null
	return sum / float(n)

func _reproduction() -> void:
	if animals.size() >= MAX_ANIMALS:
		return
	var species_counts := count_by_species()
	for a in animals.values():
		if not a.alive or not a.is_adult() or a.hunger > 60.0 or a.thirst > 60.0:
			continue
		if int(species_counts.get(a.species, 0)) >= 45:
			continue  # per-species population ceiling
		if not Rng.chance(Params.get_p("ani.repro_rate") * 0.04):
			continue
		var mate_found := false
		for o in nearby(a.position, 12.0):
			if o.id != a.id and o.species == a.species and o.is_adult():
				mate_found = true
				break
		if mate_found:
			species_counts[a.species] = int(species_counts.get(a.species, 0)) + 1
			var baby := spawn(a.species, a.position + Vector3(Rng.randf_range(-2, 2), 0, Rng.randf_range(-2, 2)), {"age": 0.1})
			baby.owner_id = a.owner_id
			baby.domestication = a.domestication * 0.8
			if baby.owner_id >= 0:
				var o2 = G.people.get_person(baby.owner_id)
				if o2 != null:
					o2.owned_animals.append(baby.id)
			births += 1
			Events.add("animal", "A %s was born" % a.species)
			if animals.size() >= MAX_ANIMALS:
				return

func remove(aid: int) -> void:
	var a = animals.get(aid)
	if a == null:
		return
	grid.remove(aid)
	animals.erase(aid)
	a.queue_free()

func kill(aid: int, cause := "god") -> void:
	var a = animals.get(aid)
	if a != null and a.alive:
		a.die(cause)

func on_death(a: Animal, cause: String) -> void:
	deaths += 1
	deaths_by_cause[cause] = int(deaths_by_cause.get(cause, 0)) + 1
	if a.herd_id >= 0 and herds.has(a.herd_id):
		herds[a.herd_id]["members"].erase(a.id)
	if a.owner_id >= 0:
		var o = G.people.get_person(a.owner_id)
		if o != null:
			o.owned_animals.erase(a.id)
	if cause != "hunted" and cause != "predator":
		Events.add("animal", "A %s died (%s)" % [a.species, cause])

func hunt_kill(aid: int, hunter) -> float:
	var a = animals.get(aid)
	if a == null or not a.alive:
		return 0.0
	var food: float = a.def["food"]
	a.die("hunted")
	hunted += 1
	Events.add("animal", "%s hunted a %s (+%d food)" % [hunter.pname, a.species, int(food)])
	return food

func assign_owner(aid: int, person_id: int) -> void:
	var a = animals.get(aid)
	var p = G.people.get_person(person_id)
	if a == null or p == null:
		return
	a.owner_id = person_id
	a.domestication = 1.0
	a.loyalty = 0.5
	if not p.owned_animals.has(aid):
		p.owned_animals.append(aid)
	if a.species == "dog":
		Events.add("animal", "A dog bonded with %s" % p.pname)
	else:
		Events.add("animal", "%s domesticated a %s" % [p.pname, a.species])

func on_predator_kill(pred: Animal, prey: Animal) -> void:
	if prey.owner_id >= 0 or prey.domestication > 0.5:
		livestock_killed += 1
		Events.add("animal", "A %s killed livestock (%s)" % [pred.species, prey.species])
	else:
		Events.add("animal", "A %s killed a %s" % [pred.species, prey.species])

func predator_attack_human(pred: Animal, victim) -> void:
	var dmg := Rng.randf_range(18.0, 42.0) * Params.get_p("ani.predator_danger")
	victim.health -= dmg
	victim.remember("danger", pred.position)
	Events.add("animal", "A %s attacked %s" % [pred.species, victim.pname])
	if victim.health <= 0.0:
		victim.die("predator_attack")
		humans_killed += 1
	else:
		victim.action = "flee"
		victim.arrived = false
		victim.target_kind = "point"
		victim.target_pos = G.world.clamp_pos(victim.position + (victim.position - pred.position).normalized() * 22.0)
		victim._compute_path()
	# panic ripples outward
	for p in G.people.nearby(pred.position, 14.0):
		p.remember("danger", pred.position)
		if p.action != "flee":
			p.react_to_meaning("danger", {"pos": pred.position, "speaker": -1})

func on_production(a: Animal, produces: String, amount: float) -> void:
	if produces == "eggs":
		eggs_produced += amount
		if Rng.chance(0.15):
			Events.add("animal", "Chickens produced eggs")
	elif produces == "milk":
		milk_produced += amount
		if Rng.chance(0.15):
			Events.add("animal", "A %s produced milk" % a.species)

func list_livestock() -> Array:
	var out: Array = []
	for a in animals.values():
		if a.alive and not a.is_predator() and (a.owner_id >= 0 or a.domestication > 0.5):
			out.append(a)
	return out

func count_by_species() -> Dictionary:
	var out := {}
	for a in animals.values():
		if a.alive:
			out[a.species] = int(out.get(a.species, 0)) + 1
	return out

func alive_count() -> int:
	var n := 0
	for a in animals.values():
		if a.alive:
			n += 1
	return n

func clear_all() -> void:
	for a in animals.values():
		a.queue_free()
	animals.clear()
	grid.clear()
	herds.clear()
	next_id = 1
	next_herd = 1
	births = 0
	deaths = 0
	deaths_by_cause.clear()
	hunted = 0
	humans_killed = 0
	livestock_killed = 0
	eggs_produced = 0.0
	milk_produced = 0.0

func to_dict() -> Dictionary:
	var list: Array = []
	for a in animals.values():
		if a.alive:
			list.append(a.serialize())
	var herds_ser := {}
	for hid in herds.keys():
		herds_ser[str(hid)] = herds[hid]
	return {"animals": list, "next_id": next_id, "next_herd": next_herd,
		"herds": herds_ser, "births": births, "deaths": deaths,
		"deaths_by_cause": deaths_by_cause, "hunted": hunted,
		"humans_killed": humans_killed, "livestock_killed": livestock_killed,
		"eggs": eggs_produced, "milk": milk_produced}

func from_dict(d: Dictionary) -> void:
	clear_all()
	next_id = int(d.get("next_id", 1))
	next_herd = int(d.get("next_herd", 1))
	births = int(d.get("births", 0))
	deaths = int(d.get("deaths", 0))
	deaths_by_cause = d.get("deaths_by_cause", {})
	hunted = int(d.get("hunted", 0))
	humans_killed = int(d.get("humans_killed", 0))
	livestock_killed = int(d.get("livestock_killed", 0))
	eggs_produced = float(d.get("eggs", 0.0))
	milk_produced = float(d.get("milk", 0.0))
	for hid in d.get("herds", {}).keys():
		var h: Dictionary = d["herds"][hid]
		var members: Array = []
		for m in h.get("members", []):
			members.append(int(m))
		h["members"] = members
		herds[int(hid)] = h
	for ad in d.get("animals", []):
		var a := Animal.new()
		add_child(a)
		a.setup(int(ad["id"]), str(ad["species"]), Vector3(float(ad["x"]), 0, float(ad["z"])), {})
		a.deserialize(ad)
		animals[a.id] = a
		grid.update(a.id, a.position)

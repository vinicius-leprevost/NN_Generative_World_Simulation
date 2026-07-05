class_name Animal extends Node3D
const SpeciesDB = preload("res://scripts/data/species_db.gd")
const Vis = preload("res://scripts/core/visuals.gd")

## Animal: autonomous animal agent. Herbivores graze, flee and herd;
## predators hold territory, hunt prey/livestock/humans; domestic animals
## bond with owners, produce food, and warn humans (dogs).

var id := 0
var species := "deer"
var def: Dictionary = {}
var age := 1.0
var max_age := 10.0
var alive := true
var cause_of_death := ""
var death_time := -1.0
var health := 100.0
var hunger := 30.0
var thirst := 30.0
var energy := 90.0
var aggression := 0.1
var fear := 0.0
var domestication := 0.0
var loyalty := 0.0
var owner_id := -1
var herd_id := -1
var territory := Vector3.ZERO
var behavior := "wander"
var target_pos := Vector3.ZERO
var target_id := -1
var target_kind := "point"
var arrived := false

var _decide_timer := 0.0
var _sound_timer := 5.0
var _prod_timer := 0.0
var _label_timer := 0.0
var body: MeshInstance3D
var label: Label3D

func setup(aid: int, sp: String, pos: Vector3, opts: Dictionary = {}) -> void:
	id = aid
	species = sp
	def = SpeciesDB.get_def(sp)
	position = pos
	territory = pos
	age = float(opts.get("age", Rng.randf_range(0.2, def["max_age"] * 0.6)))
	max_age = def["max_age"] * Rng.randf_range(0.85, 1.15)
	aggression = def["aggr"]
	domestication = float(opts.get("domestication", 0.0))
	owner_id = int(opts.get("owner_id", -1))
	_decide_timer = Rng.randf_range(0.0, 2.0)
	_sound_timer = Rng.randf_range(4.0, 16.0)
	_prod_timer = _prod_interval()
	_build_visual()

func _prod_interval() -> float:
	var days: float = def.get("prod_days", 0.0)
	if days <= 0.0:
		return 1e9
	return days * Params.get_p("sim.day_length") / maxf(Params.get_p("ani.livestock_prod"), 0.05)

func _build_visual() -> void:
	var sz: Vector3 = def["size"]
	body = Vis.box(sz, def["color"])
	body.position.y = sz.y * 0.5 + 0.05
	add_child(body)
	label = Vis.label(species, 24, Color(0.9, 0.95, 0.85))
	label.position = Vector3(0, sz.y + 0.9, 0)
	add_child(label)

func is_predator() -> bool:
	return bool(def["danger"])

func is_adult() -> bool:
	return age > max_age * 0.2

# ---------------- Lifecycle ----------------

func tick(dt: float) -> void:
	if not alive:
		return
	_needs(dt)
	if not alive:
		return
	_decide_timer -= dt
	if _decide_timer <= 0.0:
		_decide_timer = Rng.randf_range(1.8, 3.6)
		_decide()
	_move(dt)
	_act(dt)
	_production(dt)
	_sounds(dt)
	_label_timer -= dt
	if _label_timer <= 0.0:
		_label_timer = 0.7
		_refresh_label()

func _needs(dt: float) -> void:
	# predators have slow metabolisms — a kill sustains them for days
	var meta := 0.45 if is_predator() else 1.0
	hunger = minf(hunger + Params.get_p("ani.hunger_rate") * meta * dt, 120.0)
	var tr := Params.get_p("ani.thirst_rate") * dt
	if G.weather.is_drought():
		tr *= 1.5
	thirst = minf(thirst + tr, 120.0)
	if hunger >= 100.0:
		health -= dt * 2.0
	if thirst >= 100.0:
		health -= dt * 3.0
	if hunger < 60.0 and thirst < 60.0 and health < 100.0:
		health += dt * 0.8
	var yrs: float = dt / G.clock.day_length() * Params.get_p("pop.aging_speed")
	age += yrs
	if age >= max_age:
		die("old_age")
		return
	if health <= 0.0:
		die("dehydration" if thirst >= 100.0 else ("starvation" if hunger >= 100.0 else "injury"))

func die(cause: String) -> void:
	if not alive:
		return
	alive = false
	cause_of_death = cause
	death_time = G.clock.total_time
	behavior = "dead"
	rotation.z = deg_to_rad(85)
	body.material_override = Vis.mat(Color(0.45, 0.42, 0.4))
	G.animals.on_death(self, cause)

# ---------------- Decisions ----------------

func _decide() -> void:
	var mypos := position
	# flee predators (non-predators only)
	if not is_predator():
		var preds: Array = G.animals.predators_near(mypos, 15.0)
		var hunters: Array = []
		for p in G.people.nearby(mypos, 10.0):
			if p.action == "hunt" and p.target_id == id:
				hunters.append(p)
		if not preds.is_empty() or not hunters.is_empty():
			var threat: Vector3 = preds[0].position if not preds.is_empty() else hunters[0].position
			behavior = "flee"
			fear = 1.0
			var away := (mypos - threat)
			away.y = 0
			if away.length() < 0.5:
				away = Vector3(1, 0, 0)
			_set_point(G.world.clamp_pos(mypos + away.normalized() * 20.0))
			G.language.animal_call(self, "fear")
			return
	fear = maxf(fear - 0.3, 0.0)
	# guard dogs warn and follow
	if species == "dog" and owner_id >= 0:
		var owner = G.people.get_person(owner_id)
		if owner != null and owner.alive:
			var danger_near: Array = G.animals.predators_near(owner.position, 16.0)
			if not danger_near.is_empty():
				behavior = "guard"
				_set_point(owner.position)
				G.language.animal_call(self, "warning")
				return
			var loy := Params.get_p("ani.dog_loyalty") * loyalty
			if mypos.distance_to(owner.position) > 10.0 + (1.0 - loy) * 20.0:
				behavior = "follow"
				_set_entity("person", owner.id, owner.position)
				return
	# needs
	if thirst > 55.0:
		var w: Dictionary = G.world.nearest_water(mypos, 90.0)
		if w["ok"]:
			behavior = "drink"
			_set_point(w["pos"])
			return
		behavior = "wander"
		_set_point(G.world.clamp_pos(mypos + Vector3(Rng.randf_range(-30, 30), 0, Rng.randf_range(-30, 30))))
		return
	if hunger > 60.0:
		if is_predator():
			var prey = G.animals.find_prey(self)
			if prey != null:
				behavior = "hunt"
				_set_entity("animal", prey.id, prey.position)
				return
			# hungry, aggressive predators approach humans
			var agg_mult := Params.get_p("ani.aggression") * Params.get_p("ani.predator_danger")
			if hunger > 78.0 and aggression * agg_mult > 0.3:
				var humans: Array = G.people.nearby(mypos, 28.0)
				# predators fear groups
				if humans.size() > 0 and humans.size() < 3:
					behavior = "hunt"
					_set_entity("person", humans[0].id, humans[0].position)
					return
			behavior = "wander"
			_set_point(G.world.clamp_pos(territory + Vector3(Rng.randf_range(-25, 25), 0, Rng.randf_range(-25, 25))))
			return
		else:
			behavior = "graze"
			var res: Dictionary = G.world.nearest_resource(mypos, 30.0)
			if not res.is_empty() and Rng.chance(0.4):
				_set_point(G.world.resource_pos(res["id"]))
			else:
				_set_point(G.world.clamp_pos(mypos + Vector3(Rng.randf_range(-8, 8), 0, Rng.randf_range(-8, 8))))
			if domestication > 0.5:
				G.language.animal_call(self, "hunger")
			return
	# herd cohesion
	if def["herd"] and herd_id >= 0:
		var c = G.animals.herd_centroid(herd_id)
		if c != null and mypos.distance_to(c) > 14.0:
			behavior = "herd"
			_set_point(c)
			return
	# rest at night
	if G.clock.is_night() and Rng.chance(0.6):
		behavior = "rest"
		arrived = true
		return
	behavior = "wander"
	var anchor := territory
	if owner_id >= 0:
		var o = G.people.get_person(owner_id)
		if o != null:
			var home = G.buildings.get_building(o.home_id)
			anchor = home.position if home != null else o.position
	_set_point(G.world.clamp_pos(anchor + Vector3(Rng.randf_range(-15, 15), 0, Rng.randf_range(-15, 15))))

func _set_point(p: Vector3) -> void:
	target_pos = p
	target_kind = "point"
	target_id = -1
	arrived = false

func _set_entity(kind: String, eid: int, pos: Vector3) -> void:
	target_kind = kind
	target_id = eid
	target_pos = pos
	arrived = false

# ---------------- Movement & actions ----------------

func _move(dt: float) -> void:
	if arrived or behavior == "rest":
		return
	if target_kind == "animal":
		var t = G.animals.get_animal(target_id)
		if t != null and t.alive:
			target_pos = t.position
	elif target_kind == "person":
		var tp = G.people.get_person(target_id)
		if tp != null and tp.alive:
			target_pos = tp.position
	var to := target_pos - position
	to.y = 0
	if to.length() < 1.0:
		arrived = true
		return
	var dir := to.normalized()
	var sp: float = def["speed"] * (0.5 + 0.5 * health / 100.0) * G.weather.move_mult()
	if behavior == "flee" or behavior == "hunt":
		sp *= 1.4
	if G.world.in_river(position):
		sp *= 0.45  # animals wade/swim across rivers
	var next := position + dir * sp * dt
	if G.world.in_lake(next) or G.buildings.blocked(next):
		next = position + dir.rotated(Vector3.UP, PI * 0.4) * sp * dt
		if G.world.in_lake(next) or G.buildings.blocked(next):
			next = position + dir.rotated(Vector3.UP, -PI * 0.4) * sp * dt
			if G.world.in_lake(next) or G.buildings.blocked(next):
				next = position - dir * sp * dt  # back up rather than fake arrival
	position = G.world.clamp_pos(next)
	rotation.y = atan2(dir.x, dir.z)

func _act(dt: float) -> void:
	if not arrived:
		return
	match behavior:
		"drink":
			thirst = maxf(thirst - dt * 30.0 * G.weather.water_mult(), 0.0)
			if thirst <= 15.0:
				behavior = "wander"
		"graze":
			hunger = maxf(hunger - dt * 9.0 * Params.get_p("world.fertility"), 0.0)
			if hunger <= 20.0:
				behavior = "wander"
		"hunt":
			_resolve_attack()
		_:
			pass

func _resolve_attack() -> void:
	if target_kind == "animal":
		var prey = G.animals.get_animal(target_id)
		if prey == null or not prey.alive or position.distance_to(prey.position) > 2.5:
			behavior = "wander"
			return
		G.language.animal_call(self, "attack")
		if Rng.chance(0.4):
			prey.die("predator")
			G.animals.on_predator_kill(self, prey)
			hunger = maxf(hunger - 55.0, 0.0)
		# on a miss the prey has already been spooked into fleeing
		behavior = "wander"
	elif target_kind == "person":
		var victim = G.people.get_person(target_id)
		if victim == null or not victim.alive or position.distance_to(victim.position) > 2.5:
			behavior = "wander"
			return
		G.language.animal_call(self, "attack")
		G.animals.predator_attack_human(self, victim)
		hunger = maxf(hunger - 30.0, 0.0)
		behavior = "wander"

func _production(dt: float) -> void:
	var produces: String = def.get("produces", "")
	if produces == "" or not alive:
		return
	if owner_id < 0 and domestication < 0.5:
		return
	if hunger > 65.0 or thirst > 65.0:
		return
	_prod_timer -= dt
	if _prod_timer <= 0.0:
		_prod_timer = _prod_interval()
		var amount := 4.0 * Params.get_p("ani.livestock_prod")
		G.buildings.deposit_food(position, amount)
		G.animals.on_production(self, produces, amount)

func _sounds(dt: float) -> void:
	_sound_timer -= dt
	if _sound_timer <= 0.0:
		_sound_timer = Rng.randf_range(8.0, 25.0)
		G.language.animal_call(self, "idle")

func _refresh_label() -> void:
	if G.cam == null:
		return
	var d: float = G.cam.camera.global_position.distance_to(global_position)
	var show: bool = d < G.perf["label_dist"] * 0.7 or G.main.selected == self
	label.visible = show
	if show:
		var tag := species
		if owner_id >= 0:
			tag += " (owned)"
		elif is_predator():
			tag += " (!)"
		label.text = tag

# ---------------- Persistence ----------------

func serialize() -> Dictionary:
	return {
		"id": id, "species": species, "age": age, "max_age": max_age,
		"alive": alive, "health": health, "hunger": hunger, "thirst": thirst,
		"aggression": aggression, "domestication": domestication, "loyalty": loyalty,
		"owner_id": owner_id, "herd_id": herd_id,
		"tx": territory.x, "tz": territory.z, "x": position.x, "z": position.z,
	}

func deserialize(d: Dictionary) -> void:
	id = int(d["id"])
	age = float(d["age"])
	max_age = float(d["max_age"])
	alive = bool(d["alive"])
	health = float(d["health"])
	hunger = float(d["hunger"])
	thirst = float(d["thirst"])
	aggression = float(d["aggression"])
	domestication = float(d["domestication"])
	loyalty = float(d.get("loyalty", 0.0))
	owner_id = int(d["owner_id"])
	herd_id = int(d.get("herd_id", -1))
	territory = Vector3(float(d["tx"]), 0, float(d["tz"]))
	position = Vector3(float(d["x"]), 0, float(d["z"]))
	# movement state is not persisted — stand still until the next decision
	behavior = "wander"
	arrived = true
	target_pos = position
	if not alive:
		rotation.z = deg_to_rad(85)
		body.material_override = Vis.mat(Color(0.45, 0.42, 0.4))

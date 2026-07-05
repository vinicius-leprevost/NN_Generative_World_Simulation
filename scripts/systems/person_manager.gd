class_name PersonManager extends Node3D
const Person = preload("res://scripts/agents/person.gd")
const PersonBrain = preload("res://scripts/agents/person_brain.gd")
const SpatialGrid = preload("res://scripts/core/spatial_grid.gd")

## PersonManager: owns all Person agents. Spawning, birth with trait/brain/
## language inheritance, bonding, death bookkeeping, spatial queries.

const CORPSE_TIME := 40.0

var persons: Dictionary = {}      # id -> Person (includes recent corpses)
var next_id := 1
var grid := SpatialGrid.new(8.0)
var births := 0
var deaths := 0
var deaths_by_cause: Dictionary = {}
var decisions_made := 0
var decisions_per_sec := 0.0
var _dec_timer := 0.0

func spawn(pos: Vector3, opts: Dictionary = {}) -> Person:
	var p := Person.new()
	add_child(p)
	p.setup(next_id, G.world.clamp_pos(pos), opts)
	next_id += 1
	persons[p.id] = p
	grid.update(p.id, p.position)
	return p

func get_person(pid: int) -> Person:
	return persons.get(pid)

func alive_count() -> int:
	var n := 0
	for p in persons.values():
		if p.alive:
			n += 1
	return n

func alive_list() -> Array:
	var out: Array = []
	for p in persons.values():
		if p.alive:
			out.append(p)
	return out

func nearby(pos: Vector3, radius: float, exclude_id := -1) -> Array:
	var out: Array = []
	for pid in grid.query_ids(pos, radius):
		if pid == exclude_id:
			continue
		var p = persons.get(pid)
		if p != null and p.alive and p.position.distance_to(pos) <= radius:
			out.append(p)
	return out

func tick(dt: float) -> void:
	var now: float = G.clock.total_time
	for p in persons.values():
		p.tick(dt)
		if p.alive:
			grid.update(p.id, p.position)
		elif p.death_time > 0.0 and now - p.death_time > CORPSE_TIME:
			remove(p.id)
	_dec_timer += dt
	if _dec_timer >= 2.0:
		decisions_per_sec = decisions_made / _dec_timer
		decisions_made = 0
		_dec_timer = 0.0

func remove(pid: int) -> void:
	var p = persons.get(pid)
	if p == null:
		return
	grid.remove(pid)
	persons.erase(pid)
	p.queue_free()

func kill(pid: int, cause := "god") -> void:
	var p = persons.get(pid)
	if p != null and p.alive:
		p.die(cause)

func on_death(p: Person, cause: String) -> void:
	deaths += 1
	deaths_by_cause[cause] = int(deaths_by_cause.get(cause, 0)) + 1
	Events.add("death", "%s died at age %d (%s)" % [p.pname, int(p.age), cause])
	# detach from world structures
	var b = G.buildings.get_building(p.job_building)
	if b != null:
		b.workers.erase(p.id)
	var home = G.buildings.get_building(p.home_id)
	if home != null:
		home.residents.erase(p.id)
	for site in G.buildings.sites.values():
		site.workers.erase(p.id)
	var partner = get_person(p.partner_id)
	if partner != null:
		partner.partner_id = -1
	for gid in p.group_ids.duplicate():
		G.groups.remove_member(gid, p.id)
	for aid in p.owned_animals.duplicate():
		var an = G.animals.get_animal(aid)
		if an != null:
			an.owner_id = -1
	G.crime.on_person_died(p.id)

func try_bond(a: Person, b: Person) -> void:
	if a.partner_id >= 0 or b.partner_id >= 0:
		return
	if _is_kin(a, b):
		return
	if not Rng.chance(Params.get_p("pop.relationship_rate") * 0.5):
		return
	a.partner_id = b.id
	b.partner_id = a.id
	G.groups.family_create(a, b)
	Events.add("social", "%s and %s formed a family" % [a.pname, b.pname])
	# couple shares a home (and joins its resident list)
	if a.home_id < 0 and b.home_id >= 0:
		a.home_id = b.home_id
	elif b.home_id < 0 and a.home_id >= 0:
		b.home_id = a.home_id
	var shared = G.buildings.get_building(a.home_id)
	if shared != null:
		for pid in [a.id, b.id]:
			if not shared.residents.has(pid):
				shared.residents.append(pid)

func _is_kin(a: Person, b: Person) -> bool:
	# parent/child or shared parent (sibling)
	if a.parent_ids.has(b.id) or b.parent_ids.has(a.id):
		return true
	if a.child_ids.has(b.id) or b.child_ids.has(a.id):
		return true
	for pid in a.parent_ids:
		if b.parent_ids.has(pid):
			return true
	return false

func try_reproduce(a: Person, b: Person) -> void:
	var mother := a if a.sex == "f" else b
	var father := b if a.sex == "f" else a
	if mother.sex != "f" or father.sex != "m":
		return
	if mother.age < 18.0 or mother.age > 50.0:
		return
	if mother.hunger > 75.0 or mother.thirst > 75.0 or mother.health < 40.0:
		return
	var chance := Params.get_p("pop.reproduction_chance") * Params.get_p("pop.birth_rate") * 0.12
	if not Rng.chance(chance):
		return
	birth(mother, father)

func birth(mother: Person, father: Person) -> Person:
	var traits := {}
	for k in mother.traits.keys():
		var mt: float = mother.traits[k]
		var ft: float = father.traits.get(k, 0.5)
		traits[k] = clampf((mt + ft) * 0.5 + Rng.randfn(0.0, 0.08), 0.0, 1.0)
	# language exposure: children start with fragments of their parents' lexicon
	var baby_lex := {}
	var transfer := 0
	for src in [mother.lexicon, father.lexicon]:
		for sym in src.keys():
			if Rng.chance(0.35) and not baby_lex.has(sym):
				baby_lex[sym] = {"m": src[sym]["m"], "c": 0.25}
				transfer += 1
	G.language.stats["parent_transfers"] = int(G.language.stats.get("parent_transfers", 0)) + transfer
	var opts := {
		"age": 0.0, "sex": "f" if Rng.chance(0.5) else "m",
		"traits": traits, "brain": PersonBrain.inherit(mother.brain, father.brain),
		"lexicon": baby_lex, "parent_ids": [mother.id, father.id],
		"home_id": mother.home_id, "family_id": mother.family_id, "money": 0.0,
	}
	var home = G.buildings.get_building(mother.home_id)
	var pos: Vector3 = home.position if home != null else mother.position
	var baby := spawn(pos + Vector3(Rng.randf_range(-1, 1), 0, Rng.randf_range(-1, 1)), opts)
	if home != null and not home.residents.has(baby.id):
		home.residents.append(baby.id)
	mother.child_ids.append(baby.id)
	father.child_ids.append(baby.id)
	baby.relationships[mother.id] = 80.0
	baby.relationships[father.id] = 80.0
	mother.change_rel(baby.id, 90.0)
	father.change_rel(baby.id, 85.0)
	if mother.family_id >= 0:
		G.groups.add_member(mother.family_id, baby.id)
	births += 1
	Events.add("birth", "%s was born to %s and %s" % [baby.pname, mother.pname, father.pname])
	return baby

func random_alive() -> Person:
	var list := alive_list()
	if list.is_empty():
		return null
	return Rng.pick(list)

func clear_all() -> void:
	for p in persons.values():
		p.queue_free()
	persons.clear()
	grid.clear()
	next_id = 1
	births = 0
	deaths = 0
	deaths_by_cause.clear()

func to_dict() -> Dictionary:
	var list: Array = []
	for p in persons.values():
		if p.alive:  # corpses are transient; skip them
			list.append(p.serialize())
	return {"persons": list, "next_id": next_id, "births": births,
		"deaths": deaths, "deaths_by_cause": deaths_by_cause}

func from_dict(d: Dictionary) -> void:
	clear_all()
	next_id = int(d.get("next_id", 1))
	births = int(d.get("births", 0))
	deaths = int(d.get("deaths", 0))
	deaths_by_cause = d.get("deaths_by_cause", {})
	for pd in d.get("persons", []):
		var p := Person.new()
		add_child(p)
		p.setup(int(pd["id"]), Vector3(float(pd["x"]), 0, float(pd["z"])), {})
		p.deserialize(pd)
		persons[p.id] = p
		grid.update(p.id, p.position)

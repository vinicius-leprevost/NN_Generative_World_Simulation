class_name GroupSystem extends Node
## GroupSystem: families, communities, gangs, political groups, hunting
## groups. Groups own territory, leaders, reputation and dialects.

var groups: Dictionary = {}   # id -> Dictionary
var next_id := 1
var _form_timer := 0.0

func create(gtype: String, members: Array, gname := "") -> Dictionary:
	if gname == "":
		gname = Names.group_name()
	var dialect := -1
	if gtype == "community" or gtype == "gang" or gtype == "political":
		# new social units may fork their own way of speaking
		var parent: int = G.language.base_dialect
		for pid in members:
			var p = G.people.get_person(pid)
			if p != null:
				parent = G.language.dialect_of(p)
				break
		dialect = G.language.new_dialect(parent)
	var g := {"id": next_id, "name": gname, "type": gtype, "members": [],
		"leader": -1, "wealth": 0.0, "territory": {"x": 0.0, "z": 0.0, "radius": 25.0},
		"reputation": 0.5, "aggression": 0.3, "cooperation": 0.6,
		"political_power": 0.0, "dialect": dialect}
	groups[next_id] = g
	next_id += 1
	for pid in members:
		add_member(g["id"], pid)
	_update_territory(g)
	_pick_leader(g)
	if gtype != "family":
		Events.add("group", "%s formed: %s" % [gtype.capitalize(), gname])
	return g

func family_create(a, b) -> Dictionary:
	# sanitize stale ids (their old family group may have been erased)
	if a.family_id >= 0 and not groups.has(a.family_id):
		a.family_id = -1
	if b.family_id >= 0 and not groups.has(b.family_id):
		b.family_id = -1
	if a.family_id >= 0:
		add_member(a.family_id, b.id)
		b.family_id = a.family_id
		return groups[a.family_id]
	if b.family_id >= 0:
		add_member(b.family_id, a.id)
		a.family_id = b.family_id
		return groups[b.family_id]
	var surname: String = a.pname.split(" ")[1] if a.pname.contains(" ") else a.pname
	var g := create("family", [a.id, b.id], "%s Family" % surname)
	a.family_id = g["id"]
	b.family_id = g["id"]
	return g

func get_group(gid: int) -> Variant:
	return groups.get(gid)

func groups_of_type(gtype: String) -> Array:
	var out: Array = []
	for g in groups.values():
		if g["type"] == gtype:
			out.append(g)
	return out

func add_member(gid: int, pid: int) -> void:
	var g = groups.get(gid)
	var p = G.people.get_person(pid)
	if g == null or p == null:
		return
	if not g["members"].has(pid):
		g["members"].append(pid)
	if not p.group_ids.has(gid):
		p.group_ids.append(gid)

func remove_member(gid: int, pid: int) -> void:
	var g = groups.get(gid)
	if g != null:
		g["members"].erase(pid)
		if g["leader"] == pid:
			g["leader"] = -1
		if g["members"].is_empty():
			var dialect := int(g.get("dialect", -1))
			groups.erase(gid)
			G.language.release_dialect(dialect)  # GC orphaned dialects
	var p = G.people.get_person(pid)
	if p != null:
		p.group_ids.erase(gid)

func disband(gid: int) -> void:
	var g = groups.get(gid)
	if g == null:
		return
	for pid in g["members"].duplicate():
		remove_member(gid, pid)
	Events.add("group", "%s disbanded" % g["name"])

func _pick_leader(g: Dictionary) -> void:
	var best := -1
	var best_score := -1.0
	for pid in g["members"]:
		var p = G.people.get_person(pid)
		if p == null or not p.alive or not p.is_adult():
			continue
		var score: float = p.traits["sociability"] * 0.5 + p.traits["ambition"] * 0.5 + p.education * 0.005
		if score > best_score:
			best_score = score
			best = pid
	g["leader"] = best

func _update_territory(g: Dictionary) -> void:
	var sum := Vector3.ZERO
	var n := 0
	for pid in g["members"]:
		var p = G.people.get_person(pid)
		if p != null and p.alive:
			sum += p.position
			n += 1
	if n > 0:
		var c := sum / float(n)
		g["territory"]["x"] = c.x
		g["territory"]["z"] = c.z

func tick(dt: float) -> void:
	_form_timer += dt
	if _form_timer < 20.0:
		return
	_form_timer = 0.0
	for g in groups.values():
		_update_territory(g)
		if g["leader"] < 0 or G.people.get_person(g["leader"]) == null:
			_pick_leader(g)
	_try_form_community()
	_try_form_gang()
	_try_form_hunting_group()
	_try_form_political()
	_gang_conflict()

func _try_form_political() -> void:
	# political movements need an audience: a government or a real town
	if G.people.alive_count() < 15 and G.buildings.count("government") == 0:
		return
	if not Rng.chance(Params.get_p("soc.political_rate") * 0.2):
		return
	var seed_p = G.people.random_alive()
	if seed_p == null or not seed_p.is_adult() or seed_p.traits["ambition"] < 0.55:
		return
	if _in_group_of_type(seed_p, "political"):
		return
	var backers: Array = []
	for oid in seed_p.relationships.keys():
		if seed_p.relationships[oid] > 30.0:
			var o = G.people.get_person(oid)
			if o != null and o.alive and o.is_adult() and not _in_group_of_type(o, "political"):
				backers.append(oid)
	if backers.size() >= 3:
		backers.append(seed_p.id)
		var g := create("political", backers.slice(0, 8))
		g["political_power"] = 0.3
		g["leader"] = seed_p.id

func _try_form_community() -> void:
	if not Rng.chance(Params.get_p("soc.group_rate") * 0.35):
		return
	var seed_p = G.people.random_alive()
	if seed_p == null or not seed_p.is_adult():
		return
	if _in_group_of_type(seed_p, "community"):
		return
	var friends: Array = []
	for oid in seed_p.relationships.keys():
		if seed_p.relationships[oid] > 35.0:
			var o = G.people.get_person(oid)
			if o != null and o.alive and not _in_group_of_type(o, "community"):
				friends.append(oid)
	if friends.size() >= 3:
		friends.append(seed_p.id)
		create("community", friends)

func _try_form_gang() -> void:
	if not Rng.chance(Params.get_p("soc.gang_rate") * 0.25):
		return
	var criminals: Array = []
	for p in G.people.alive_list():
		if p.crimes_committed >= 2 and not _in_group_of_type(p, "gang"):
			criminals.append(p)
	if criminals.size() < 3:
		return
	var ids: Array = []
	for c in criminals.slice(0, 5):
		ids.append(c.id)
	var g := create("gang", ids)
	g["aggression"] = 0.8
	g["reputation"] = 0.15

func _try_form_hunting_group() -> void:
	if G.animals.humans_killed + G.animals.livestock_killed < 2:
		return
	if not groups_of_type("hunting").is_empty():
		return
	if not Rng.chance(Params.get_p("soc.group_rate") * 0.3):
		return
	var hunters: Array = []
	for p in G.people.alive_list():
		if p.is_adult() and (p.skills.get("hunting", 0.0) > 0.15 or p.traits["risk"] > 0.65):
			hunters.append(p.id)
	if hunters.size() >= 2:
		create("hunting", hunters.slice(0, 6))
		Events.add("group", "A hunting group formed in response to predator attacks")

func _gang_conflict() -> void:
	var gangs := groups_of_type("gang")
	if gangs.size() < 2:
		return
	if not Rng.chance(Params.get_p("soc.conflict") * 0.15):
		return
	var a: Dictionary = Rng.pick(gangs)
	var b: Dictionary = Rng.pick(gangs)
	if a["id"] == b["id"]:
		return
	Events.add("crime", "Gang conflict: %s vs %s" % [a["name"], b["name"]])
	G.crime.stats["assault"] += 1
	G.crime.stats["total"] += 1
	for g in [a, b]:
		if not g["members"].is_empty():
			var pid: int = Rng.pick(g["members"])
			var p = G.people.get_person(pid)
			if p != null and p.alive:
				p.health -= Rng.randf_range(10.0, 35.0)
				if p.health <= 0.0:
					p.die("murder")
					G.crime.stats["murder"] += 1

func _in_group_of_type(p, gtype: String) -> bool:
	for gid in p.group_ids:
		var g = groups.get(gid)
		if g != null and g["type"] == gtype:
			return true
	return false

func family_of(pid: int) -> Variant:
	var p = G.people.get_person(pid)
	if p == null or p.family_id < 0:
		return null
	return groups.get(p.family_id)

# God operations
func force_merge_language(gid_a: int, gid_b: int) -> void:
	var a = groups.get(gid_a)
	var b = groups.get(gid_b)
	if a == null or b == null:
		return
	b["dialect"] = a["dialect"]
	Events.add("god", "%s and %s now share a language" % [a["name"], b["name"]])

func force_isolate_language(gid: int) -> void:
	var g = groups.get(gid)
	if g == null:
		return
	g["dialect"] = G.language.new_dialect(g["dialect"])
	Events.add("god", "%s became linguistically isolated" % g["name"])

func clear_all() -> void:
	groups.clear()
	next_id = 1

func to_dict() -> Dictionary:
	var ser := {}
	for gid in groups.keys():
		ser[str(gid)] = groups[gid]
	return {"groups": ser, "next_id": next_id}

func from_dict(d: Dictionary) -> void:
	clear_all()
	next_id = int(d.get("next_id", 1))
	for k in d.get("groups", {}).keys():
		var g: Dictionary = d["groups"][k]
		g["id"] = int(g["id"])
		g["leader"] = int(g.get("leader", -1))
		g["dialect"] = int(g.get("dialect", -1))
		var members: Array = []
		for m in g.get("members", []):
			members.append(int(m))
		g["members"] = members
		groups[int(k)] = g

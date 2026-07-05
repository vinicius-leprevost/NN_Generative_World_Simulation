class_name GodTools extends Node
const BuildingDB = preload("res://scripts/data/building_db.gd")

## GodTools: placement tools (click the terrain to act) plus direct
## manipulation operations used by the inspector and God panel.

var mode := ""    # "", spawn_person, spawn_animal, building, site, road, river, lake, resource, zone, remove, kill, heal
var sub := ""     # species / building type / zone type
var _line_start = null

func active() -> bool:
	return mode != ""

func begin(m: String, s := "") -> void:
	mode = m
	sub = s
	_line_start = null
	var desc := m if s == "" else "%s (%s)" % [m, s]
	G.ui.set_hint("God tool: %s — left-click terrain to apply, right-click to cancel" % desc)

func cancel() -> void:
	mode = ""
	sub = ""
	_line_start = null
	G.ui.set_hint("")

func ground_click(pos: Vector3) -> void:
	match mode:
		"spawn_person":
			var p = G.people.spawn(pos)
			Events.add("god", "God created %s" % p.pname)
		"spawn_animal":
			G.animals.spawn(sub, pos)
			Events.add("god", "God spawned a %s" % sub)
		"building":
			var b = G.buildings.spawn_building(sub, pos)
			Events.add("god", "God placed a %s" % b.def["name"])
		"site":
			G.buildings.create_site(sub, pos, "god")
			Events.add("god", "God started construction of a %s" % BuildingDB.get_def(sub)["name"])
		"road":
			if _line_start == null:
				_line_start = pos
				G.ui.set_hint("Road: click the end point (chain continues; right-click to stop)")
			else:
				G.buildings.add_road_line(_line_start, pos)
				Events.add("god", "God built a road")
				_line_start = pos
		"river":
			if _line_start == null:
				_line_start = pos
				G.ui.set_hint("River: click the end point")
			else:
				G.world.add_river(_line_start, pos)
				Events.add("god", "God carved a river")
				_line_start = null
		"lake":
			G.world.add_lake(pos, 10.0)
			Events.add("god", "God created a lake")
		"resource":
			G.world.add_resource(pos, 50.0)
			Events.add("god", "God spawned food resources")
		"zone":
			G.world.add_zone(sub, pos, 18.0)
			Events.add("god", "God marked a %s zone" % sub)
		"remove":
			_remove_at(pos)
		_:
			pass

func _remove_at(pos: Vector3) -> void:
	# nearest person
	var people: Array = G.people.nearby(pos, 2.5)
	if not people.is_empty():
		var p = people[0]
		Events.add("god", "God removed %s" % p.pname)
		G.people.remove(p.id)
		return
	var animals: Array = G.animals.nearby(pos, 2.5)
	if not animals.is_empty():
		Events.add("god", "God removed a %s" % animals[0].species)
		G.animals.remove(animals[0].id)
		return
	for s in G.buildings.sites.values():
		if s.position.distance_to(pos) < 5.0:
			G.buildings.cancel_site(s.id)
			return
	for b in G.buildings.buildings.values():
		var sz: Vector2 = b.def["size"]
		if absf(pos.x - b.position.x) < sz.x * 0.5 + 1.0 and absf(pos.z - b.position.z) < sz.y * 0.5 + 1.0:
			Events.add("god", "God removed a %s" % b.def["name"])
			G.buildings.demolish(b.id)
			return
	for r in G.world.resources.values():
		if pos.distance_to(Vector3(r["x"], 0, r["z"])) < 2.5:
			G.world.remove_resource(r["id"])
			return
	var cell: Vector2i = G.buildings.road_key(pos)
	if G.buildings.roads.has(cell):
		G.buildings.roads.erase(cell)
		G.buildings._roads_dirty = true
		return
	G.world.remove_zone_near(pos)
	G.world.remove_water_near(pos, 4.0)

# ---------------- Direct manipulation ----------------

func god_kill(p) -> void:
	if p.alive:
		Events.add("god", "God struck down %s" % p.pname)
		p.die("god")

func god_revive(p) -> void:
	if not p.alive:
		p.revive()

func god_heal(p) -> void:
	p.heal()
	p.hunger = 10.0
	p.thirst = 10.0
	Events.add("god", "God healed %s" % p.pname)

func god_sicken(p) -> void:
	p.make_sick()
	Events.add("god", "God made %s sick" % p.pname)

func god_money(p, amount: float) -> void:
	p.money = maxf(p.money + amount, 0.0)
	Events.add("god", "God %s %s %.0f money" % ["gave" if amount > 0 else "took from", p.pname, absf(amount)])

func god_set_trait(p, trait_name: String, v: float) -> void:
	p.traits[trait_name] = clampf(v, 0.0, 1.0)
	Events.add("god", "God reshaped %s's mind (%s)" % [p.pname, trait_name])

func god_tame(a) -> void:
	var people: Array = G.people.nearby(a.position, 40.0)
	if people.is_empty():
		a.domestication = 1.0
		Events.add("god", "God tamed a %s" % a.species)
	else:
		G.animals.assign_owner(a.id, people[0].id)

func god_wild(a) -> void:
	var owner = G.people.get_person(a.owner_id)
	if owner != null:
		owner.owned_animals.erase(a.id)
	a.owner_id = -1
	a.domestication = 0.0
	Events.add("god", "God made a %s wild again" % a.species)

func god_feed_animal(a) -> void:
	a.hunger = 0.0
	a.thirst = 0.0
	a.health = 100.0

func god_set_hour(h: float) -> void:
	G.clock.set_hour(h)
	Events.add("god", "God set the time to %02d:00" % int(h))

func god_weather(s: String) -> void:
	G.weather.set_weather(s, 1.5)
	Events.add("god", "God changed the weather to %s" % s)

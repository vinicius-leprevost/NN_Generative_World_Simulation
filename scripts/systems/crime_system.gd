class_name CrimeSystem extends Node
## CrimeSystem: abstract crime events (theft, assault, robbery, murder,
## vandalism, animal theft), witnesses, police response, arrests, prisons.

var stats := {"total": 0, "theft": 0, "assault": 0, "murder": 0, "robbery": 0,
	"vandalism": 0, "animal_theft": 0, "arrests": 0}
var hotspots: Array = []   # {x, z, t}
var wanted: Array = []     # criminal person ids awaiting police response
var _tick_timer := 0.0

func law_strictness() -> float:
	return Params.get_p("soc.law_strictness") + G.politics.law_bonus()

func resolve_crime(c) -> void:
	var victim = null
	var target_building = null
	if c.target_kind == "person":
		victim = G.people.get_person(c.target_id)
	elif c.target_kind == "building":
		target_building = G.buildings.get_building(c.target_id)
	if (victim == null or not victim.alive) and target_building == null:
		return
	var ctype := "theft"
	if victim != null:
		if c.traits["aggression"] > 0.75 and c.rel(victim.id) < -20.0 \
				and Rng.chance(0.12 * Params.get_p("soc.conflict")):
			ctype = "murder"
		elif c.traits["aggression"] > 0.6 and Rng.chance(0.35):
			ctype = "assault"
		elif victim.money > 60.0:
			ctype = "robbery"
		elif not victim.owned_animals.is_empty() and Rng.chance(0.25):
			ctype = "animal_theft"
	else:
		ctype = "theft" if target_building.stock.get("food", 0.0) > 2.0 else "vandalism"

	match ctype:
		"murder":
			Events.add("crime", "%s murdered %s" % [c.pname, victim.pname])
			victim.die("murder")
		"assault":
			victim.health -= Rng.randf_range(15.0, 40.0)
			victim.change_rel(c.id, -50.0)
			victim.try_speak("help", true)
			Events.add("crime", "%s assaulted %s" % [c.pname, victim.pname])
			if victim.health <= 0.0:
				victim.die("murder")
				ctype = "murder"
		"robbery", "theft":
			if victim != null:
				var amount: float = minf(victim.money * 0.4, 60.0)
				victim.money -= amount
				c.money += amount
				victim.change_rel(c.id, -40.0)
				victim.try_speak("help", true)
				Events.add("crime", "%s robbed %s of %.0f" % [c.pname, victim.pname, amount])
			else:
				var food: float = minf(target_building.stock["food"], 8.0)
				target_building.stock["food"] -= food
				c.hunger = maxf(c.hunger - food * 1.2, 0.0)
				Events.add("crime", "%s stole food from %s" % [c.pname, target_building.def["name"]])
		"animal_theft":
			if not victim.owned_animals.is_empty():
				var aid: int = victim.owned_animals[0]
				victim.owned_animals.erase(aid)
				var a = G.animals.get_animal(aid)
				if a != null:
					a.owner_id = c.id
					c.owned_animals.append(aid)
				victim.change_rel(c.id, -45.0)
				Events.add("crime", "%s stole an animal from %s" % [c.pname, victim.pname])
		"vandalism":
			target_building.hp -= 12.0
			Events.add("crime", "%s vandalized %s" % [c.pname, target_building.def["name"]])

	stats[ctype] = int(stats.get(ctype, 0)) + 1
	stats["total"] += 1
	c.crimes_committed += 1
	c.skills["crime"] = clampf(c.skills.get("crime", 0.0) + 0.03, 0.0, 1.0)
	c.brain.reinforce("commit_crime", 0.3)
	hotspots.append({"x": c.position.x, "z": c.position.z, "t": G.clock.total_time})
	if hotspots.size() > 40:
		hotspots.pop_front()

	# witnesses
	var witnesses: Array = G.people.nearby(c.position, 12.0, c.id)
	var seen := 0
	for wtn in witnesses:
		if victim != null and wtn.id == victim.id:
			continue
		seen += 1
		wtn.change_rel(c.id, -25.0)
		wtn.remember("danger", c.position)
		if wtn.job_type == "police":
			if not wanted.has(c.id):
				wanted.append(c.id)
		elif Rng.chance(0.4):
			wtn.try_speak("crime_witnessed", true)
	# investigation chance even without a police witness
	if not wanted.has(c.id) and Rng.chance((0.15 + seen * 0.2) * law_strictness() * 0.5):
		wanted.append(c.id)

func tick(dt: float) -> void:
	_tick_timer += dt
	if _tick_timer < 2.0:
		return
	_tick_timer = 0.0
	var now: float = G.clock.total_time
	while hotspots.size() > 0 and now - hotspots[0]["t"] > G.clock.day_length() * 2.0:
		hotspots.pop_front()
	# dispatch police to wanted criminals (one pursuer per criminal)
	for i in range(wanted.size() - 1, -1, -1):
		var cid: int = wanted[i]
		var criminal = G.people.get_person(cid)
		if criminal == null or not criminal.alive or criminal.prison_until >= 0.0:
			wanted.remove_at(i)
			continue
		var pursuer = _pursuer_of(cid)
		if pursuer != null:
			pursuer.target_pos = criminal.position  # track the moving suspect
			continue
		var officer = _free_officer(criminal.position)
		if officer != null:
			officer.action = "arrest"
			officer.target_kind = "person"
			officer.target_id = cid
			officer.target_pos = criminal.position
			officer.arrived = false
			officer._compute_path()
			officer.try_speak("police_warning", true)

func _pursuer_of(cid: int) -> Variant:
	for p in G.people.alive_list():
		if p.job_type == "police" and p.action == "arrest" and p.target_kind == "person" and p.target_id == cid:
			return p
	return null

func _free_officer(pos: Vector3) -> Variant:
	var best = null
	var best_d := 120.0
	for p in G.people.alive_list():
		if p.job_type != "police" or p.action == "arrest" or p.prison_until >= 0.0:
			continue
		var d: float = p.position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = p
	return best

func try_arrest(officer, criminal) -> void:
	var success := clampf(0.55 + officer.skills.get("policing", 0.0) * 0.4
		- criminal.skills.get("crime", 0.0) * 0.25, 0.1, 0.95)
	if Rng.chance(success):
		var prison = _prison_with_space()
		wanted.erase(criminal.id)
		stats["arrests"] += 1
		officer.skills["policing"] = clampf(officer.skills.get("policing", 0.0) + 0.03, 0.0, 1.0)
		officer.brain.reinforce("patrol", 0.3)
		if prison != null:
			var sentence_days: float = (1.5 + criminal.crimes_committed * 0.8) * maxf(law_strictness(), 0.2)
			criminal.prison_until = G.clock.total_time + sentence_days * G.clock.day_length()
			criminal.position = prison.position + Vector3(Rng.randf_range(-1, 1), 0, Rng.randf_range(-1, 1))
			criminal.action = "idle"
			criminal.arrived = true
			criminal._update_color()
			Events.add("police", "%s arrested %s (%d days)" % [officer.pname, criminal.pname, int(sentence_days)])
		else:
			var fine: float = criminal.money * 0.5
			criminal.money -= fine
			G.economy.treasury += fine
			Events.add("police", "%s fined %s (no prison available)" % [officer.pname, criminal.pname])
		criminal.brain.reinforce("commit_crime", -0.8)
	else:
		Events.add("police", "%s escaped arrest" % criminal.pname)
		criminal.action = "flee"
		criminal.arrived = false
		criminal.target_kind = "point"
		criminal.target_pos = G.world.clamp_pos(criminal.position
			+ (criminal.position - officer.position).normalized() * 30.0)
		criminal._compute_path()

func _prison_with_space() -> Variant:
	# each prison adds soc.prison_capacity worth of cells; overflow spills to
	# the next prison in the list
	var cap := int(Params.get_p("soc.prison_capacity"))
	var used := in_prison_count()
	for b in G.buildings.list_type("prison"):
		if used < cap:
			return b
		used -= cap
	return null

func in_prison_count() -> int:
	var n := 0
	for p in G.people.alive_list():
		if p.prison_until >= 0.0:
			n += 1
	return n

func criminal_count() -> int:
	var n := 0
	for p in G.people.alive_list():
		if p.crimes_committed >= 2:
			n += 1
	return n

func danger_at(pos: Vector3) -> float:
	var d := 0.0
	for h in hotspots:
		var dist: float = pos.distance_to(Vector3(h["x"], 0, h["z"]))
		if dist < 20.0:
			d += (1.0 - dist / 20.0) * 0.5
	return minf(d, 1.5)

func hot_pos() -> Variant:
	if hotspots.is_empty():
		return null
	var h: Dictionary = Rng.pick(hotspots)
	return Vector3(h["x"], 0, h["z"])

func on_person_died(pid: int) -> void:
	wanted.erase(pid)

func clear_all() -> void:
	for k in stats.keys():
		stats[k] = 0
	hotspots.clear()
	wanted.clear()

func to_dict() -> Dictionary:
	return {"stats": stats, "hotspots": hotspots, "wanted": wanted}

func from_dict(d: Dictionary) -> void:
	clear_all()
	var s: Dictionary = d.get("stats", {})
	for k in s.keys():
		stats[k] = int(s[k])
	hotspots = d.get("hotspots", [])
	for w in d.get("wanted", []):
		wanted.append(int(w))

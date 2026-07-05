class_name PoliticsSystem extends Node
const BuildingDB = preload("res://scripts/data/building_db.gd")

## PoliticsSystem: president-led government. A Government Building creates one
## deterministic president role: the smartest eligible adult. The government
## analyzes dashboard-style world signals and the president funds construction
## sites for the highest-priority public need.

const ACTION_THRESHOLD := 1.0
const MAX_ACTIVE_PROJECT_SITES := 4

var leader_id := -1       # legacy alias; kept for old saves and older UI paths
var president_id := -1
var trust := 0.6
var corruption := 0.1
var laws: Array = []
var projects_funded := 0

var _act_timer := 0.0
var _trust_timer := 0.0
var _current_priority := "No government"
var _last_decision := "None"
var _last_blocker := "Government Building required"
var _top_insights: Array = []

func politicians() -> Array:
	var out: Array = []
	for p in G.people.alive_list():
		if p.job_type == "politician":
			out.append(p)
	return out

func president():
	return G.people.get_person(president_id)

func president_name() -> String:
	var p = president()
	return p.pname if p != null and p.alive else "none"

func has_president() -> bool:
	var p = president()
	return p != null and p.alive and G.buildings.count("government") > 0

func government_controls_planning() -> bool:
	return has_president()

func current_priority() -> String:
	return _current_priority

func law_bonus() -> float:
	return laws.size() * 0.08

func tick(dt: float) -> void:
	_trust_timer += dt
	if _trust_timer >= 10.0:
		_update_trust(_trust_timer)
		_trust_timer = 0.0
	if G.buildings.count("government") == 0:
		_clear_president_assignment()
		_set_no_government_report()
		return
	_ensure_president()
	if not has_president():
		_current_priority = "No eligible president"
		_last_blocker = "No eligible adult or elder available for president"
		_refresh_report()
		return
	_act_timer += dt
	if _act_timer >= G.clock.day_length():
		_act_timer = 0.0
		_president_acts()
	elif _top_insights.is_empty():
		_refresh_report()

func _update_trust(dt: float) -> void:
	var base := Params.get_p("soc.public_trust")
	var services := 0.0
	services += 0.05 * minf(G.buildings.count("hospital"), 2)
	services += 0.05 * minf(G.buildings.count("school"), 2)
	services += 0.03 * minf(G.buildings.count("police_station"), 2)
	var pop := maxi(G.people.alive_count(), 1)
	var crime_pressure := minf(float(G.crime.stats["total"]) / pop * 0.15, 0.3)
	var target := clampf(base + services - crime_pressure - corruption * 0.3, 0.0, 1.0)
	trust = lerpf(trust, target, clampf(dt * 0.02, 0.0, 1.0))
	corruption = clampf(corruption + Rng.randfn(0.0, 0.005) * Params.get_p("soc.corruption"), 0.0, 1.0)

func _eligible_president(p) -> bool:
	return p != null and p.alive and p.is_adult() and p.prison_until < 0.0

func _ensure_president() -> void:
	var best = null
	for p in G.people.alive_list():
		if not _eligible_president(p):
			continue
		if best == null:
			best = p
			continue
		var pi: float = p.traits.get("intelligence", 0.0)
		var bi: float = best.traits.get("intelligence", 0.0)
		if pi > bi or (is_equal_approx(pi, bi) and (p.education > best.education or (is_equal_approx(p.education, best.education) and p.id < best.id))):
			best = p
	if best == null:
		_clear_president_assignment()
		return
	if best.id == president_id and best.job_type == "president":
		leader_id = president_id
		_assign_president_worker(best, false)
		return
	var old = president()
	if old != null and old.job_type == "president":
		old.job_type = ""
		old.job_building = -1
		old.action = "idle"
		old._update_color()
	president_id = best.id
	leader_id = president_id
	_assign_president_worker(best, true)

func _assign_president_worker(p, announce: bool) -> void:
	for b in G.buildings.buildings.values():
		for pid in b.workers.keys().duplicate():
			if b.workers[pid] == "president":
				b.workers.erase(pid)
	var old_building = G.buildings.get_building(p.job_building)
	if old_building != null:
		old_building.workers.erase(p.id)
	var gov = G.buildings.nearest("government", p.position)
	if gov == null:
		return
	gov.workers[p.id] = "president"
	p.job_type = "president"
	p.job_building = gov.id
	p.action = "idle"
	p.arrived = true
	p._update_color()
	if announce:
		Events.add("politics", "%s became president" % p.pname)

func _clear_president_assignment() -> void:
	var old = president()
	if old != null and old.job_type == "president":
		old.job_type = ""
		old.job_building = -1
		old.action = "idle"
		old._update_color()
	for b in G.buildings.buildings.values():
		for pid in b.workers.keys().duplicate():
			if b.workers[pid] == "president":
				b.workers.erase(pid)
	president_id = -1
	leader_id = -1

func _president_acts() -> void:
	var pres = president()
	if pres == null or not pres.alive:
		_clear_president_assignment()
		return
	if pres.traits.get("greed", 0.0) > 0.7 and Rng.chance(Params.get_p("soc.corruption") * 0.4):
		var skim: float = minf(G.economy.treasury * 0.2, 100.0)
		if skim > 5.0:
			G.economy.treasury -= skim
			pres.money += skim
			corruption = clampf(corruption + 0.08, 0.0, 1.0)
			_last_decision = "No project: corruption scandal"
			_last_blocker = "%s skimmed public funds" % pres.pname
			if Rng.chance(0.5):
				Events.add("politics", "Rumors of corruption surround %s" % pres.pname)
				trust = clampf(trust - 0.08, 0.0, 1.0)
			_refresh_report()
			return
	var analysis := _analyze_world()
	var candidates: Array = analysis["candidates"]
	_apply_report_from_candidates(candidates)
	if Params.get_p("soc.gov_influence") <= 0.1:
		_last_blocker = "Government influence too low"
		return
	if candidates.is_empty() or float(candidates[0]["score"]) < ACTION_THRESHOLD:
		_last_blocker = "No need above action threshold"
		return
	if G.buildings.active_sites().size() >= MAX_ACTIVE_PROJECT_SITES:
		_last_blocker = "Too many active construction sites"
		return
	var choice: Dictionary = candidates[0]
	var btype: String = choice["btype"]
	var cost: float = BuildingDB.get_def(btype)["cost"] * Params.get_p("eco.construction_cost") * 0.5
	var spot: Vector3 = G.buildings.find_project_spot(choice["center"], btype)
	if spot == Vector3.INF:
		_last_blocker = "No clear build spot for %s" % BuildingDB.get_def(btype)["name"]
		return
	var debt_added: float = G.economy.finance_public_project(cost)
	G.buildings.create_site(btype, spot, "president")
	projects_funded += 1
	_last_decision = "%s approved %s for %s" % [pres.pname, BuildingDB.get_def(btype)["name"], choice["label"]]
	if debt_added > 0.0:
		_last_decision += " (issued %.0f public debt)" % debt_added
	_last_blocker = ""
	Events.add("politics", _last_decision)
	if G.crime.stats["total"] > maxi(G.people.alive_count(), 1) * 2 and laws.size() < 5 and Rng.chance(0.5):
		var law := "Public Order Act %d" % (laws.size() + 1)
		laws.append(law)
		Events.add("politics", "Law passed: %s" % law)

func _analyze_world() -> Dictionary:
	var people: Array = G.people.alive_list()
	var pop := people.size()
	var fallback := _centroid(people, Vector3.ZERO)
	var adults := 0
	var working_adults := 0
	var employed := 0
	var children_teens: Array = []
	var homeless_people: Array = []
	var sick_people: Array = []
	var water_gap_people: Array = []
	var hunger_sum := 0.0
	var thirst_sum := 0.0
	var health_sum := 0.0
	for p in people:
		hunger_sum += p.hunger
		thirst_sum += p.thirst
		health_sum += p.health
		if p.is_adult():
			adults += 1
			if p.stage() != "elder":
				working_adults += 1
				if p.job_type != "":
					employed += 1
			if p.home_id < 0:
				homeless_people.append(p)
		elif p.stage() == "child" or p.stage() == "teen":
			children_teens.append(p)
		if p.sick or p.health < 65.0:
			sick_people.append(p)
		var w: Dictionary = G.world.nearest_water(p.position, 1e9)
		if not w["ok"] or w["dist"] >= 70.0:
			water_gap_people.append(p)
	var n := maxf(float(pop), 1.0)
	var avg_hunger := hunger_sum / n
	var avg_thirst := thirst_sum / n
	var avg_health := health_sum / n
	var stored_food := _stored_food()
	var candidates: Array = []
	_add_water_candidate(candidates, water_gap_people, avg_thirst, pop, fallback)
	_add_health_candidate(candidates, sick_people, avg_health, pop, fallback)
	_add_housing_candidate(candidates, homeless_people, adults, pop, fallback)
	_add_school_candidate(candidates, children_teens, fallback)
	_add_construction_candidate(candidates, pop, fallback)
	_add_jobs_candidate(candidates, working_adults, employed, fallback)
	_add_food_candidate(candidates, avg_hunger, stored_food, pop, fallback)
	_add_store_candidate(candidates, stored_food, pop, fallback)
	_add_crime_candidate(candidates, pop, fallback)
	_add_prison_candidate(candidates, pop, fallback)
	_add_power_candidate(candidates, pop, fallback)
	candidates.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	return {"candidates": candidates, "pop": pop, "avg_hunger": avg_hunger,
		"avg_thirst": avg_thirst, "avg_health": avg_health}

func _add_candidate(out: Array, label: String, score: float, btype: String, center: Vector3, detail: String) -> void:
	if score <= 0.0 or btype == "":
		return
	out.append({"label": label, "score": score, "btype": btype, "center": center, "detail": detail})

func _add_water_candidate(out: Array, gap_people: Array, avg_thirst: float, pop: int, fallback: Vector3) -> void:
	var water_projects: int = G.buildings.planned_count("well") + G.buildings.planned_count("water_storage")
	if water_projects >= int(pop / 8) + 1 and gap_people.is_empty() and avg_thirst < 45.0:
		return
	var score: float = float(gap_people.size()) / maxf(float(pop), 1.0) * 4.0 + maxf(avg_thirst - 35.0, 0.0) / 20.0
	var btype: String = "water_storage" if pop > 80 or G.weather.is_drought() else "well"
	_add_candidate(out, "Water access", score, btype, _centroid(gap_people, fallback),
		"%d people lack nearby water; average thirst %.0f" % [gap_people.size(), avg_thirst])

func _add_health_candidate(out: Array, sick_people: Array, avg_health: float, pop: int, fallback: Vector3) -> void:
	var desired: int = maxi(1, int(pop / 250) + 1)
	if G.buildings.planned_count("hospital") >= desired and avg_health >= 80.0:
		return
	var score: float = float(sick_people.size()) / maxf(float(pop), 1.0) * 8.0 + maxf(85.0 - avg_health, 0.0) / 25.0
	_add_candidate(out, "Health care", score, "hospital", _centroid(sick_people, fallback),
		"%d sick/injured people; average health %.0f" % [sick_people.size(), avg_health])

func _add_housing_candidate(out: Array, homeless_people: Array, adults: int, pop: int, fallback: Vector3) -> void:
	if homeless_people.is_empty():
		return
	var score: float = float(homeless_people.size()) / maxf(float(adults), 1.0) * 5.0
	var btype: String = "home" if pop < 30 else "apartment"
	_add_candidate(out, "Housing", score, btype, _centroid(homeless_people, fallback),
		"%d homeless adults need shelter" % homeless_people.size())

func _add_school_candidate(out: Array, youth: Array, fallback: Vector3) -> void:
	var capacity: int = G.buildings.planned_count("school") * 30
	var missing: int = youth.size() - capacity
	if missing <= 0:
		return
	var score: float = float(missing) / maxf(float(youth.size()), 1.0) * 3.0
	_add_candidate(out, "Education", score, "school", _centroid(youth, fallback),
		"%d children/teens exceed school capacity" % missing)

func _add_construction_candidate(out: Array, pop: int, fallback: Vector3) -> void:
	var open_sites: int = G.buildings.sites_needing_builders().size()
	if open_sites <= 0:
		return
	var needed: int = mini(open_sites * 2, maxi(1, int(pop / 4)))
	var builders: int = G.buildings.builder_count()
	if builders >= needed:
		return
	if G.buildings.planned_count("construction_yard") >= int(pop / 80) + 1:
		return
	var score: float = 1.0 + float(needed - builders) / maxf(float(needed), 1.0) * 2.0
	_add_candidate(out, "Construction capacity", score, "construction_yard", fallback,
		"%d builder jobs for %d open site groups" % [builders, open_sites])

func _add_jobs_candidate(out: Array, working_adults: int, employed: int, fallback: Vector3) -> void:
	if working_adults <= 0:
		return
	var unemployed: int = maxi(working_adults - employed, 0)
	var vacancies: int = maxi(G.buildings.total_job_slots(false) - G.buildings.filled_job_slots(false), 0)
	if unemployed <= 0 or vacancies >= unemployed * 0.35:
		return
	if G.buildings.planned_count("workplace") >= int(working_adults / 60) + 1:
		return
	var score: float = float(unemployed) / maxf(float(working_adults), 1.0) * 3.0
	_add_candidate(out, "Employment", score, "workplace", fallback,
		"%d unemployed workers and %d open job slots" % [unemployed, vacancies])

func _add_food_candidate(out: Array, avg_hunger: float, stored_food: float, pop: int, fallback: Vector3) -> void:
	if G.buildings.planned_count("farm") >= int(pop / 8) + 1:
		return
	var shortage: bool = stored_food < pop * 3.0
	if avg_hunger < 45.0 and not shortage:
		return
	var score: float = maxf(avg_hunger - 35.0, 0.0) / 20.0 + (1.2 if shortage else 0.0)
	_add_candidate(out, "Food production", score, "farm", fallback,
		"Average hunger %.0f; stored food %.0f" % [avg_hunger, stored_food])

func _add_store_candidate(out: Array, stored_food: float, pop: int, fallback: Vector3) -> void:
	var desired: int = maxi(1, int(pop / 250) + 1)
	if G.buildings.planned_count("store") + G.buildings.planned_count("market") >= desired:
		return
	if stored_food < pop * 2.0 or G.buildings.planned_count("farm") == 0:
		return
	var btype: String = "market" if pop > 250 else "store"
	_add_candidate(out, "Food distribution", 1.1 + float(pop) / 500.0, btype, fallback,
		"Stored food exists, but stores/markets are below demand")

func _add_crime_candidate(out: Array, pop: int, fallback: Vector3) -> void:
	var desired: int = maxi(1, int(pop / 300) + 1)
	if G.buildings.planned_count("police_station") >= desired:
		return
	var crime_rate: float = float(G.crime.stats["total"]) / maxf(float(pop), 1.0)
	var pressure: float = G.crime.wanted.size() * 0.25 + G.crime.hotspots.size() * 0.08 + crime_rate
	if pressure <= 1.0:
		return
	_add_candidate(out, "Public safety", pressure, "police_station", fallback,
		"%d wanted, %d hotspots, %.2f crimes/person" % [G.crime.wanted.size(), G.crime.hotspots.size(), crime_rate])

func _add_prison_candidate(out: Array, pop: int, fallback: Vector3) -> void:
	var cap: int = G.buildings.planned_count("prison") * int(Params.get_p("soc.prison_capacity"))
	var prisoners: int = G.crime.in_prison_count()
	if prisoners <= 0 and G.crime.wanted.size() < 6:
		return
	if cap > prisoners + 2 and G.crime.wanted.size() < 6:
		return
	var score: float = 1.0 + float(prisoners + G.crime.wanted.size()) / maxf(float(maxi(pop, 1)), 1.0) * 5.0
	_add_candidate(out, "Justice capacity", score, "prison", fallback,
		"%d prisoners, %d wanted, capacity %d" % [prisoners, G.crime.wanted.size(), cap])

func _add_power_candidate(out: Array, pop: int, fallback: Vector3) -> void:
	if pop > 28 and G.buildings.planned_count("power_plant") == 0:
		_add_candidate(out, "Power grid", 1.2, "power_plant", fallback,
			"Population is large enough to need a power grid")
	elif G.buildings.planned_count("power_plant") > 0 and G.buildings.planned_count("street_light") < int(pop / 6):
		_add_candidate(out, "Lighting", 1.05, "street_light", fallback,
			"Street-light coverage is below population demand")

func _stored_food() -> float:
	var sum := 0.0
	for b in G.buildings.buildings.values():
		sum += b.stock.get("food", 0.0)
	return sum

func _centroid(items: Array, fallback: Vector3) -> Vector3:
	if items.is_empty():
		return fallback
	var sum := Vector3.ZERO
	for item in items:
		sum += item.position
	return sum / float(items.size())

func _refresh_report() -> void:
	var analysis := _analyze_world()
	_apply_report_from_candidates(analysis["candidates"])

func _apply_report_from_candidates(candidates: Array) -> void:
	_top_insights.clear()
	for i in range(mini(candidates.size(), 5)):
		var c: Dictionary = candidates[i]
		_top_insights.append("%s (%.1f): %s" % [c["label"], c["score"], c["detail"]])
	if candidates.is_empty():
		_current_priority = "Stable"
	elif float(candidates[0]["score"]) >= ACTION_THRESHOLD:
		_current_priority = "%s -> %s" % [candidates[0]["label"], BuildingDB.get_def(candidates[0]["btype"])["name"]]
	else:
		_current_priority = "%s below threshold" % candidates[0]["label"]

func _set_no_government_report() -> void:
	_current_priority = "No government"
	_last_blocker = "Government Building required"
	_top_insights = ["Build a Government Building to enable presidential planning."]

func government_report() -> Dictionary:
	if G.buildings.count("government") == 0:
		_set_no_government_report()
	if _top_insights.is_empty():
		_refresh_report()
	return {
		"President": president_name(),
		"Current priority": _current_priority,
		"Top insights": _join_lines(_top_insights),
		"Last decision": _last_decision,
		"Blocked reason": _last_blocker if _last_blocker != "" else "none",
		"Active government sites": _project_sites_text(),
		"Public debt": "%.0f" % G.economy.public_debt,
		"Trust": "%.0f%%" % (trust * 100.0),
		"Corruption": "%.0f%%" % (corruption * 100.0),
		"President projects": projects_funded,
	}

func _join_lines(lines: Array) -> String:
	if lines.is_empty():
		return "none"
	var out := ""
	for line in lines:
		if out != "":
			out += "\n"
		out += "- %s" % line
	return out

func _project_sites_text() -> String:
	var out: Array = []
	for s in G.buildings.active_sites():
		if s.sponsor == "president" or s.sponsor == "government":
			out.append("%s %.0f%%" % [s.def["name"], s.progress / maxf(s.work_required, 1.0) * 100.0])
	return _join_lines(out)

func clear_all() -> void:
	leader_id = -1
	president_id = -1
	trust = 0.6
	corruption = 0.1
	laws.clear()
	projects_funded = 0
	_act_timer = 0.0
	_trust_timer = 0.0
	_current_priority = "No government"
	_last_decision = "None"
	_last_blocker = "Government Building required"
	_top_insights.clear()

func to_dict() -> Dictionary:
	return {"leader_id": president_id, "president_id": president_id, "trust": trust,
		"corruption": corruption, "laws": laws, "projects": projects_funded,
		"act_timer": _act_timer, "last_decision": _last_decision,
		"last_blocker": _last_blocker}

func from_dict(d: Dictionary) -> void:
	president_id = int(d.get("president_id", d.get("leader_id", -1)))
	leader_id = president_id
	trust = float(d.get("trust", 0.6))
	corruption = float(d.get("corruption", 0.1))
	laws = d.get("laws", [])
	projects_funded = int(d.get("projects", 0))
	_act_timer = float(d.get("act_timer", 0.0))
	_last_decision = str(d.get("last_decision", "None"))
	_last_blocker = str(d.get("last_blocker", ""))

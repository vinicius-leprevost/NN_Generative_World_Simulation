class_name StatsSystem extends Node
## StatsSystem: aggregates live statistics from every system for the
## dashboard. Snapshots are cached and refreshed at the dashboard rate.

var _cache: Dictionary = {}
var _cache_time := -100.0

func snapshot() -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _cache_time < 1.0 / maxf(G.perf["dashboard_hz"], 0.1):
		return _cache
	_cache_time = now
	_cache = _build()
	return _cache

func _build() -> Dictionary:
	var people: Array = G.people.alive_list()
	var pop := people.size()
	var stages := {"baby": 0, "child": 0, "teen": 0, "adult": 0, "elder": 0}
	var hunger_sum := 0.0
	var thirst_sum := 0.0
	var health_sum := 0.0
	var age_sum := 0.0
	var oldest = null
	var sick := 0
	var homeless := 0
	var water_access := 0
	for p in people:
		stages[p.stage()] += 1
		hunger_sum += p.hunger
		thirst_sum += p.thirst
		health_sum += p.health
		age_sum += p.age
		if oldest == null or p.age > oldest.age:
			oldest = p
		if p.sick:
			sick += 1
		if p.home_id < 0 and p.is_adult():
			homeless += 1
		var w: Dictionary = G.world.nearest_water(p.position, 1e9)
		if w["ok"] and w["dist"] < 70.0:
			water_access += 1
	var n := maxi(pop, 1)
	var eco: Dictionary = G.economy.wealth_stats()
	var dbc: Dictionary = G.people.deaths_by_cause
	var animals_alive: int = G.animals.alive_count()
	var by_species: Dictionary = G.animals.count_by_species()
	var domestic := 0
	var predators := 0
	var pets := 0
	var animal_water := 0
	for a in G.animals.animals.values():
		if not a.alive:
			continue
		if a.is_predator():
			predators += 1
		if a.owner_id >= 0 or a.domestication > 0.5:
			domestic += 1
		if a.species == "dog" and a.owner_id >= 0:
			pets += 1
		var aw: Dictionary = G.world.nearest_water(a.position, 1e9)
		if aw["ok"] and aw["dist"] < 90.0:
			animal_water += 1
	var farm_food := 0.0
	for b in G.buildings.buildings.values():
		farm_food += b.stock.get("food", 0.0)
	var lang = G.language
	return {
		"population": {
			"Total population": pop, "Babies": stages["baby"], "Children": stages["child"],
			"Teenagers": stages["teen"], "Adults": stages["adult"], "Elders": stages["elder"],
			"Births": G.people.births, "Deaths": G.people.deaths,
			"Average age": "%.1f" % (age_sum / n),
			"Oldest person": ("%s (%.0f)" % [oldest.pname, oldest.age]) if oldest != null else "--",
			"Average health": "%.0f" % (health_sum / n),
			"Average hunger": "%.0f" % (hunger_sum / n),
			"Average thirst": "%.0f" % (thirst_sum / n),
			"Sick": sick, "Homeless adults": homeless,
		},
		"society": {
			"Families": G.groups.groups_of_type("family").size(),
			"Communities": G.groups.groups_of_type("community").size(),
			"Gangs": G.groups.groups_of_type("gang").size(),
			"Hunting groups": G.groups.groups_of_type("hunting").size(),
			"Political groups": G.groups.groups_of_type("political").size(),
			"President": G.politics.president_name(),
			"Politicians": G.politics.politicians().size(),
			"Police officers": _job_count("police"),
			"Prisoners": G.crime.in_prison_count(),
			"Criminals": G.crime.criminal_count(),
			"Honest citizens": pop - G.crime.criminal_count(),
		},
		"economy": {
			"Total money": "%.0f" % eco["total"], "Average money": "%.1f" % eco["avg"],
			"Richest": eco["richest"], "Poorest": eco["poorest"],
			"Unemployment": "%.0f%%" % eco["unemployment"],
			"In poverty": eco["poverty"], "Treasury": "%.0f" % eco["treasury"],
			"Public debt": "%.0f" % eco["public_debt"],
			"Debt issued": "%.0f" % eco["debt_issued"],
			"Tax collected": "%.0f" % eco["tax_collected"],
			"Cars": G.vehicles.cars.size(),
			"Jobs": str(eco["jobs"]),
		},
		"construction": {
			"Homes": G.buildings.count("home") + G.buildings.count("apartment") + G.buildings.count("condo"),
			"Schools": G.buildings.count("school"), "Hospitals": G.buildings.count("hospital"),
			"Police stations": G.buildings.count("police_station"), "Prisons": G.buildings.count("prison"),
			"Construction yards": G.buildings.count("construction_yard"),
			"Power plants": G.buildings.count("power_plant"),
			"Stores/Markets": G.buildings.count("store") + G.buildings.count("market"),
			"Farms": G.buildings.count("farm"), "Barns": G.buildings.count("barn"),
			"Animal pens": G.buildings.count("animal_pen"),
			"Wells": G.buildings.count("well") + G.buildings.count("water_storage"),
			"Street lights": G.buildings.count("street_light"),
			"Watch towers": G.buildings.count("watchtower"),
			"Road cells": G.buildings.roads.size(),
			"Total buildings": G.buildings.buildings.size(),
			"Active sites": G.buildings.sites.size(),
			"Completed": G.buildings.completed_count,
			"Abandoned": G.buildings.abandoned_count,
		},
		"crime": {
			"Total crimes": G.crime.stats["total"], "Thefts": G.crime.stats["theft"] + G.crime.stats["robbery"],
			"Assaults": G.crime.stats["assault"], "Murders": G.crime.stats["murder"],
			"Animal thefts": G.crime.stats["animal_theft"], "Vandalism": G.crime.stats["vandalism"],
			"Arrests": G.crime.stats["arrests"], "Wanted now": G.crime.wanted.size(),
			"Crime hotspots": G.crime.hotspots.size(),
			"Crime rate": "%.2f per person" % (float(G.crime.stats["total"]) / n),
		},
		"politics": {
			"President": G.politics.president_name(), "Politicians": G.politics.politicians().size(),
			"Current priority": G.politics.current_priority(),
			"Public trust": "%.0f%%" % (G.politics.trust * 100.0),
			"Corruption": "%.0f%%" % (G.politics.corruption * 100.0),
			"Laws passed": G.politics.laws.size(),
			"Projects funded": G.politics.projects_funded,
			"President projects": G.politics.projects_funded,
		},
		"water": {
			"Water sources": G.world.all_water_points().size(),
			"People with access": "%d / %d" % [water_access, pop],
			"Animals with access": "%d / %d" % [animal_water, animals_alive],
			"Average thirst": "%.0f" % (thirst_sum / n),
			"Dehydration deaths": int(dbc.get("dehydration", 0)),
			"Drought": "YES" if G.weather.is_drought() else "no",
		},
		"animals": {
			"Total animals": animals_alive, "By species": str(by_species),
			"Domestic": domestic, "Wild": animals_alive - domestic,
			"Predators": predators, "Pets (dogs)": pets,
			"Animal births": G.animals.births, "Animal deaths": G.animals.deaths,
			"Hunted": G.animals.hunted,
			"Humans killed by animals": G.animals.humans_killed,
			"Livestock killed": G.animals.livestock_killed,
			"Eggs produced": "%.0f" % G.animals.eggs_produced,
			"Milk produced": "%.0f" % G.animals.milk_produced,
		},
		"language": {
			"Total sound events": lang.stats["sounds"],
			"Success rate": "%.0f%%" % lang.success_rate(),
			"Miscommunications": lang.stats["miscomm"],
			"Symbols learned": lang.stats["learned"],
			"Symbols created": lang.stats["symbols_created"],
			"Dialects": lang.dialects.size(),
			"Avg words known": "%.1f" % lang.avg_lexicon_size(),
			"Parent-child transfers": lang.stats["parent_transfers"],
			"Animal warnings heeded": lang.stats["animal_warnings"],
			"Trending meanings": str(lang.most_used_meanings()),
		},
		"food": {
			"Wild food available": "%.0f" % _wild_food(),
			"Stored food": "%.0f" % farm_food,
			"Food from hunting": G.animals.hunted,
			"Eggs": "%.0f" % G.animals.eggs_produced,
			"Milk": "%.0f" % G.animals.milk_produced,
			"Starvation deaths": int(dbc.get("starvation", 0)),
			"Average hunger": "%.0f" % (hunger_sum / n),
		},
		"simulation": {
			"Time": G.clock.time_string(), "Weather": G.weather.state,
			"FPS": Engine.get_frames_per_second(),
			"Humans": pop, "Animals": animals_alive,
			"Buildings": G.buildings.buildings.size(),
			"Vehicles": G.vehicles.cars.size(),
			"AI decisions/sec": "%.0f" % G.people.decisions_per_sec,
			"Preset": G.perf["name"],
			"Speed": "x%.1f%s" % [Params.get_p("sim.speed"), " (paused)" if G.clock.paused else ""],
		},
	}

func _job_count(job: String) -> int:
	var num := 0
	for p in G.people.alive_list():
		if p.job_type == job:
			num += 1
	return num

func _leader_name() -> String:
	var l = G.people.get_person(G.politics.leader_id)
	if l == null:
		return "none"
	return l.pname

func _wild_food() -> float:
	var sum := 0.0
	for r in G.world.resources.values():
		sum += r["amount"]
	return sum

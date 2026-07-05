extends Node
## Params: central registry of every god-tunable simulation parameter.
## The God control panel sliders are generated automatically from these
## definitions, and the whole set persists in save files.

signal param_changed(key: String, value: float)

var defs: Array = []            # [{key,label,tab,min,max,def,step}]
var values: Dictionary = {}
var _by_key: Dictionary = {}

func _ready() -> void:
	_define_all()
	reset_defaults()

func _d(key: String, label: String, tab: String, minv: float, maxv: float, def: float, step: float = 0.01) -> void:
	var e := {"key": key, "label": label, "tab": tab, "min": minv, "max": maxv, "def": def, "step": step}
	defs.append(e)
	_by_key[key] = e

func get_p(key: String) -> float:
	return float(values.get(key, _by_key.get(key, {}).get("def", 0.0)))

func set_p(key: String, v: float) -> void:
	var e: Dictionary = _by_key.get(key, {})
	if not e.is_empty():
		v = clampf(v, e["min"], e["max"])
	values[key] = v
	param_changed.emit(key, v)

func reset_defaults() -> void:
	for e in defs:
		values[e["key"]] = e["def"]

func tabs() -> Array:
	var out: Array = []
	for e in defs:
		if not out.has(e["tab"]):
			out.append(e["tab"])
	return out

func defs_for_tab(tab: String) -> Array:
	var out: Array = []
	for e in defs:
		if e["tab"] == tab:
			out.append(e)
	return out

func to_dict() -> Dictionary:
	return values.duplicate()

func from_dict(d: Dictionary) -> void:
	reset_defaults()
	for k in d.keys():
		values[k] = float(d[k])
	for k in values.keys():
		param_changed.emit(k, values[k])

func _define_all() -> void:
	# ---------------- World ----------------
	_d("sim.speed", "Simulation Speed", "World", 0.1, 20.0, 1.0, 0.1)
	_d("sim.day_length", "Day Length (real sec)", "World", 20.0, 600.0, 120.0, 5.0)
	_d("world.rain_freq", "Rain Frequency", "World", 0.0, 2.0, 0.6)
	_d("world.storm_freq", "Storm Frequency", "World", 0.0, 2.0, 0.25)
	_d("world.disaster_freq", "Disaster Frequency", "World", 0.0, 2.0, 0.1)
	_d("world.resources", "Resource Availability", "World", 0.1, 3.0, 1.0)
	_d("world.fertility", "Land Fertility", "World", 0.1, 3.0, 1.0)
	_d("world.temperature", "Temperature", "World", -10.0, 45.0, 20.0, 0.5)
	_d("world.pollution", "Pollution Level", "World", 0.0, 2.0, 0.1)
	_d("world.crime_pressure", "Crime Pressure", "World", 0.0, 3.0, 1.0)
	_d("world.econ_difficulty", "Economic Difficulty", "World", 0.2, 3.0, 1.0)
	# ---------------- Population ----------------
	_d("pop.start_population", "Starting Population", "Population", 2.0, 100.0, 14.0, 1.0)
	_d("pop.birth_rate", "Birth Rate", "Population", 0.0, 3.0, 1.0)
	_d("pop.aging_speed", "Aging Speed (yrs/day)", "Population", 0.1, 10.0, 1.5, 0.1)
	_d("pop.lifespan_mod", "Lifespan Modifier", "Population", 0.3, 2.0, 1.0)
	_d("pop.disease_chance", "Disease Chance", "Population", 0.0, 3.0, 1.0)
	_d("pop.hunger_rate", "Hunger Rate", "Population", 0.05, 3.0, 0.15)
	_d("pop.thirst_rate", "Thirst Rate", "Population", 0.05, 3.0, 0.26)
	_d("pop.education_speed", "Education Speed", "Population", 0.1, 3.0, 1.0)
	_d("pop.skill_gain", "Skill Gain Speed", "Population", 0.1, 3.0, 1.0)
	_d("pop.relationship_rate", "Relationship Formation", "Population", 0.1, 3.0, 1.0)
	_d("pop.reproduction_chance", "Reproduction Chance", "Population", 0.0, 3.0, 1.0)
	_d("pop.child_growth", "Child Growth Speed", "Population", 0.2, 3.0, 1.6)
	_d("pop.death_mod", "Death Chance Modifier", "Population", 0.1, 3.0, 1.0)
	# ---------------- Neural ----------------
	_d("nn.explore", "Exploration Randomness", "Neural", 0.0, 1.0, 0.25)
	_d("nn.survival_w", "Survival Priority", "Neural", 0.1, 3.0, 1.0)
	_d("nn.hunger_w", "Hunger Priority", "Neural", 0.1, 3.0, 1.0)
	_d("nn.thirst_w", "Thirst Priority", "Neural", 0.1, 3.0, 1.0)
	_d("nn.social_w", "Social Priority", "Neural", 0.1, 3.0, 1.0)
	_d("nn.work_w", "Work Priority", "Neural", 0.1, 3.0, 1.0)
	_d("nn.family_w", "Family Priority", "Neural", 0.1, 3.0, 1.0)
	_d("nn.crime_mult", "Crime Tendency Mult", "Neural", 0.0, 3.0, 1.0)
	_d("nn.coop_mult", "Cooperation Mult", "Neural", 0.0, 3.0, 1.0)
	_d("nn.aggression_mult", "Aggression Mult", "Neural", 0.0, 3.0, 1.0)
	_d("nn.empathy_mult", "Empathy Mult", "Neural", 0.0, 3.0, 1.0)
	_d("nn.risk_mult", "Risk-Taking Mult", "Neural", 0.0, 3.0, 1.0)
	_d("nn.learning_rate", "Learning Rate", "Neural", 0.0, 0.5, 0.06)
	_d("nn.memory_strength", "Memory Strength", "Neural", 0.1, 2.0, 1.0)
	_d("nn.decision_interval", "Decision Interval (s)", "Neural", 0.3, 6.0, 1.5, 0.1)
	_d("nn.move_strength", "Movement Neural Strength", "Neural", 0.2, 2.0, 1.0)
	_d("nn.lang_learn", "Language Learning Speed", "Neural", 0.0, 3.0, 1.0)
	_d("nn.comm_radius", "Communication Radius", "Neural", 3.0, 40.0, 12.0, 0.5)
	_d("nn.dialect_diverge", "Dialect Divergence Rate", "Neural", 0.0, 3.0, 1.0)
	# ---------------- Economy ----------------
	_d("eco.start_money", "Starting Money", "Economy", 0.0, 1000.0, 20.0, 1.0)
	_d("eco.wage_mult", "Wage Multiplier", "Economy", 0.1, 5.0, 1.0)
	_d("eco.job_avail", "Job Availability", "Economy", 0.1, 3.0, 1.0)
	_d("eco.resource_price", "Resource Price", "Economy", 0.5, 50.0, 3.0, 0.5)
	_d("eco.construction_cost", "Construction Cost Mult", "Economy", 0.1, 5.0, 1.0)
	_d("eco.car_price", "Car Price", "Economy", 20.0, 2000.0, 220.0, 5.0)
	_d("eco.house_price", "Housing Price", "Economy", 20.0, 3000.0, 300.0, 5.0)
	_d("eco.food_price", "Food Price", "Economy", 0.5, 50.0, 4.0, 0.5)
	_d("eco.animal_price", "Animal Price", "Economy", 1.0, 300.0, 30.0, 1.0)
	_d("eco.tax_rate", "Tax Rate", "Economy", 0.0, 0.6, 0.1)
	_d("eco.poverty_pressure", "Poverty Pressure", "Economy", 0.0, 3.0, 1.0)
	_d("eco.inequality", "Wealth Inequality Mult", "Economy", 0.2, 3.0, 1.0)
	_d("eco.market_rand", "Market Randomness", "Economy", 0.0, 1.0, 0.2)
	# ---------------- Society ----------------
	_d("soc.group_rate", "Group Formation Rate", "Society", 0.0, 3.0, 1.0)
	_d("soc.political_rate", "Political Formation Rate", "Society", 0.0, 3.0, 1.0)
	_d("soc.gang_rate", "Gang Formation Rate", "Society", 0.0, 3.0, 1.0)
	_d("soc.police_rate", "Police Recruitment Rate", "Society", 0.0, 3.0, 1.0)
	_d("soc.prison_capacity", "Prison Capacity", "Society", 1.0, 60.0, 10.0, 1.0)
	_d("soc.law_strictness", "Law Strictness", "Society", 0.0, 3.0, 1.0)
	_d("soc.gov_influence", "Government Influence", "Society", 0.0, 3.0, 1.0)
	_d("soc.public_trust", "Public Trust (base)", "Society", 0.0, 1.0, 0.6)
	_d("soc.cooperation", "Community Cooperation", "Society", 0.0, 3.0, 1.0)
	_d("soc.conflict", "Social Conflict", "Society", 0.0, 3.0, 1.0)
	_d("soc.corruption", "Corruption Mult", "Society", 0.0, 3.0, 1.0)
	# ---------------- Construction ----------------
	_d("con.speed", "Construction Speed", "Construction", 0.1, 5.0, 1.0)
	_d("con.workers_req", "Required Workers Mult", "Construction", 0.3, 3.0, 1.0)
	_d("con.materials_req", "Material Requirement Mult", "Construction", 0.3, 3.0, 1.0)
	_d("con.efficiency", "Worker Efficiency", "Construction", 0.1, 3.0, 1.0)
	_d("con.durability", "Building Durability", "Construction", 0.2, 3.0, 1.0)
	_d("con.maintenance", "Maintenance Decay Rate", "Construction", 0.0, 3.0, 0.3)
	_d("con.road_speed", "Road Construction Speed", "Construction", 0.2, 5.0, 1.0)
	_d("con.power_req", "Power Grid Requirement", "Construction", 0.0, 1.0, 1.0, 1.0)
	_d("con.water_req", "Water Infrastructure Req", "Construction", 0.0, 1.0, 1.0, 1.0)
	# ---------------- Animals ----------------
	_d("ani.spawn_rate", "Animal Spawn Rate", "Animals", 0.0, 3.0, 1.0)
	_d("ani.repro_rate", "Animal Reproduction Rate", "Animals", 0.0, 3.0, 1.0)
	_d("ani.hunger_rate", "Animal Hunger Rate", "Animals", 0.05, 3.0, 0.28)
	_d("ani.thirst_rate", "Animal Thirst Rate", "Animals", 0.05, 3.0, 0.32)
	_d("ani.aggression", "Animal Aggression", "Animals", 0.0, 3.0, 1.0)
	_d("ani.predator_danger", "Predator Danger Level", "Animals", 0.0, 3.0, 1.0)
	_d("ani.livestock_prod", "Livestock Productivity", "Animals", 0.0, 3.0, 1.0)
	_d("ani.domestication_speed", "Domestication Speed", "Animals", 0.0, 3.0, 1.0)
	_d("ani.dog_loyalty", "Dog Loyalty", "Animals", 0.0, 3.0, 1.0)
	_d("ani.herd_rate", "Herd Formation Rate", "Animals", 0.0, 3.0, 1.0)
	_d("ani.pack_rate", "Pack Formation Rate", "Animals", 0.0, 3.0, 1.0)
	# ---------------- Audio / Language ----------------
	_d("aud.master", "Master Volume", "Audio & Language", 0.0, 1.0, 0.7)
	_d("aud.human_vol", "Human Sound Volume", "Audio & Language", 0.0, 1.0, 0.8)
	_d("aud.animal_vol", "Animal Sound Volume", "Audio & Language", 0.0, 1.0, 0.8)
	_d("aud.radius_mult", "Sound Radius Mult", "Audio & Language", 0.2, 3.0, 1.0)
	_d("aud.comm_freq", "Communication Frequency", "Audio & Language", 0.0, 3.0, 1.0)
	_d("aud.lang_speed", "Language Learning Speed", "Audio & Language", 0.0, 3.0, 1.0)
	_d("aud.dialect_speed", "Dialect Divergence Speed", "Audio & Language", 0.0, 3.0, 1.0)
	_d("aud.miscomm", "Miscommunication Rate", "Audio & Language", 0.0, 1.0, 0.15)
	_d("aud.shared_lang_speed", "Shared Language Formation", "Audio & Language", 0.0, 3.0, 1.0)
	_d("aud.mute", "Mute (0/1)", "Audio & Language", 0.0, 1.0, 0.0, 1.0)

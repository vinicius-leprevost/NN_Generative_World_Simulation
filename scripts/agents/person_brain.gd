class_name PersonBrain extends RefCounted
## PersonBrain: lightweight neural-style decision system.
## Weighted inputs (needs, environment, traits, memory, social pressure) are
## combined into utility scores per action; exploration noise makes behavior
## individual; reinforcement adjusts weights from lived outcomes; children
## inherit mutated weights from parents.

const ACTIONS := ["wander", "seek_food", "seek_water", "rest", "go_home",
	"socialize", "work", "seek_job", "build", "study", "reproduce", "hunt",
	"commit_crime", "patrol", "flee", "buy_food", "buy_car", "care_animal",
	"help", "communicate"]

var w: Dictionary = {}

func _init() -> void:
	for a in ACTIONS:
		w[a] = Rng.randf_range(0.85, 1.15)

static func inherit(a, b):
	var child = load("res://scripts/agents/person_brain.gd").new()
	for k in ACTIONS:
		var pa: float = a.w.get(k, 1.0)
		var pb: float = b.w.get(k, 1.0)
		child.w[k] = clampf((pa + pb) * 0.5 + Rng.randfn(0.0, 0.06), 0.3, 2.5)
	return child

func reinforce(action: String, reward: float) -> void:
	if not w.has(action):
		return
	var lr := Params.get_p("nn.learning_rate")
	w[action] = clampf(w[action] + lr * reward, 0.3, 2.5)

func to_dict() -> Dictionary:
	return w.duplicate()

func from_dict(d: Dictionary) -> void:
	for k in d.keys():
		w[k] = float(d[k])

## Score every action for person `p` given perception context `ctx`,
## then commit the best one via p.start_action().
func decide(p) -> void:
	var ctx: Dictionary = p.perceive()
	var u: Dictionary = {}
	var hunger_n: float = clampf(p.hunger / 100.0, 0.0, 1.2)
	var thirst_n: float = clampf(p.thirst / 100.0, 0.0, 1.2)
	var energy_n: float = clampf(p.energy / 100.0, 0.0, 1.0)
	var surv := Params.get_p("nn.survival_w")
	var night: bool = G.clock.is_night()
	var stage: String = p.stage()
	var adult: bool = stage == "adult" or stage == "elder"

	# --- survival ---
	u["seek_food"] = w["seek_food"] * pow(hunger_n, 1.4) * 4.2 * Params.get_p("nn.hunger_w") * surv
	u["seek_water"] = w["seek_water"] * pow(thirst_n, 1.4) * 4.6 * Params.get_p("nn.thirst_w") * surv
	u["rest"] = w["rest"] * (1.0 - energy_n) * 2.0 + (0.7 if night else 0.0)
	if ctx["danger"] > 0.15:
		u["flee"] = w["flee"] * ctx["danger"] * 4.0 * (1.6 - p.traits["risk"] * Params.get_p("nn.risk_mult") * 0.5)
	if night and p.home_id >= 0 and ctx["danger"] < 0.2:
		u["go_home"] = w["go_home"] * 1.2
	elif p.home_id < 0 and adult:
		# homeless: seek shelter (claims a free home on arrival)
		u["go_home"] = w["go_home"] * (1.0 if night else 0.55)

	# --- economy / work ---
	var can_work := stage == "teen" or stage == "adult" or stage == "elder"
	var elder_mult := 0.5 if stage == "elder" else 1.0
	if can_work:
		if p.job_type != "":
			var workdrive: float = 1.0 + (0.6 if p.money < 30.0 else 0.0) + p.traits["ambition"] * 0.4
			workdrive *= clampf(1.25 - hunger_n * 0.8, 0.2, 1.25) * elder_mult  # hungry workers down tools
			if p.job_type == "builder" and not ctx["sites"].is_empty():
				workdrive *= 0.25
			u["work"] = w["work"] * workdrive * Params.get_p("nn.work_w") * (0.25 if night else 1.0)
		else:
			u["seek_job"] = w["seek_job"] * (0.8 + Params.get_p("eco.poverty_pressure") * 0.4) * Params.get_p("nn.work_w")
		if not ctx["sites"].is_empty() and G.buildings.can_person_build(p):
			var builddrive: float = 0.9 + p.skills.get("construction", 0.0) * 0.5 + Params.get_p("nn.coop_mult") * p.traits["empathy"] * 0.3
			if p.job_type == "builder":
				builddrive *= 2.4
			u["build"] = w["build"] * builddrive * (0.2 if night else 1.0)
		if hunger_n > 0.45 and not ctx["prey"].is_empty():
			u["hunt"] = w["hunt"] * hunger_n * (0.8 + p.skills.get("hunting", 0.0) + p.traits["risk"] * 0.4)
		if p.money >= Params.get_p("eco.car_price") and p.car_id < 0 and G.buildings.has_roads():
			u["buy_car"] = w["buy_car"] * 0.9 * (1.0 + p.traits["ambition"])
	# shopping: restock the pocket at a market — urgent when hungry with an
	# empty pocket, routine errand when supplies merely run low
	if ctx["store"] != null and ctx["store"].stock.get("food", 0.0) >= 4.0 \
			and p.money >= G.economy.food_unit_price() * 4.0:
		var pocket_gap: float = 1.0 - clampf(p.pocket_food / maxf(p.pocket_food_max(), 1.0), 0.0, 1.0)
		var shop_drive: float = pocket_gap * 0.85
		if p.pocket_food <= 0.0:
			shop_drive += hunger_n * 2.2
		u["buy_food"] = w["buy_food"] * shop_drive

	# --- social / family ---
	var social_w := Params.get_p("nn.social_w")
	if not ctx["people"].is_empty():
		u["socialize"] = w["socialize"] * p.traits["sociability"] * social_w * (1.4 if stage == "child" or stage == "teen" else 0.9)
		u["communicate"] = w["communicate"] * p.traits["sociability"] * Params.get_p("aud.comm_freq") * 0.7
		if ctx["needy"] != null:
			u["help"] = w["help"] * p.traits["empathy"] * Params.get_p("nn.empathy_mult") * Params.get_p("nn.coop_mult") * 1.3
	if adult and p.partner_id >= 0 and stage != "elder":
		u["reproduce"] = w["reproduce"] * Params.get_p("pop.reproduction_chance") * Params.get_p("nn.family_w") * 1.05 * (0.25 if hunger_n > 0.6 or thirst_n > 0.6 else 1.0)
	if stage == "child" or stage == "teen":
		if ctx["school"] != null:
			u["study"] = w["study"] * 1.3 * Params.get_p("pop.education_speed")
		u["go_home"] = maxf(u.get("go_home", 0.0), 0.6)

	# --- crime ---
	if adult and p.prison_until < 0.0:
		var poverty: float = clampf(1.0 - p.money / 60.0, 0.0, 1.0) * Params.get_p("eco.poverty_pressure")
		var crime_drive: float = (p.traits["aggression"] * Params.get_p("nn.aggression_mult") * 0.5
			+ p.traits["greed"] * 0.4 - p.traits["empathy"] * Params.get_p("nn.empathy_mult") * 0.5
			+ poverty * 0.5 + hunger_n * 0.35 + p.gang_influence() * 0.5
			- p.education * 0.01 - Params.get_p("soc.law_strictness") * 0.25)
		crime_drive *= Params.get_p("nn.crime_mult") * Params.get_p("world.crime_pressure")
		if night:
			crime_drive *= 1.35
		if ctx["police_near"]:
			crime_drive *= 0.35
		if crime_drive > 0.1 and (ctx["victim"] != null or ctx["loot_building"] != null):
			u["commit_crime"] = w["commit_crime"] * crime_drive * 1.6

	# --- roles ---
	if p.job_type == "police":
		u["patrol"] = w["patrol"] * 1.4
		u["commit_crime"] = 0.0
	if p.job_type == "doctor" and ctx["needy"] != null:
		u["help"] = maxf(u.get("help", 0.0), 1.6)
	if adult and (not p.owned_animals.is_empty() or ctx["tameable"] != null):
		u["care_animal"] = w["care_animal"] * (0.5 + p.skills.get("animal_handling", 0.0) + p.traits["empathy"] * 0.3) * Params.get_p("ani.domestication_speed") * 0.5

	# --- baseline curiosity ---
	u["wander"] = w["wander"] * (0.35 + p.traits["curiosity"] * 0.5)

	# --- exploration noise: this is what makes each mind individual ---
	var explore := Params.get_p("nn.explore")
	for k in u.keys():
		u[k] = maxf(u[k] + Rng.randfn(0.0, explore * 0.35), 0.0)

	var best := "wander"
	var best_u := -1.0
	for k in u.keys():
		if u[k] > best_u:
			best_u = u[k]
			best = k
	p.start_action(best, ctx)

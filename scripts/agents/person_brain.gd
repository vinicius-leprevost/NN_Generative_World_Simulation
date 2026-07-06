class_name PersonBrain extends RefCounted
## PersonBrain: two-layer decision system.
##
## Layer 1 (interpretable base): weighted utility scores per action from
## needs, environment, traits and social pressure — keeps behavior sane.
## Layer 2 (neural net): a real feed-forward network (20 sensors -> 10 tanh
## hidden -> per-action tanh output) MODULATES each action's utility. The
## net gives minds cross-input pattern recognition the hand-tuned base
## cannot express ("hungry AND night AND predator near -> don't forage").
##
## Learning: reward-modulated plasticity. The habit weight of the rewarded
## action shifts (as before), and the net's output weights for that action
## are nudged along the hidden activations that were active when the
## decision was made (an eligibility trace). Learning rate scales with the
## person's intelligence trait.
##
## Evolution: children inherit both layers by per-gene crossover of their
## parents plus Gaussian mutation (God-tunable), with generation tracking.

const ACTIONS := ["wander", "seek_food", "seek_water", "rest", "go_home",
	"socialize", "work", "seek_job", "build", "study", "reproduce", "hunt",
	"commit_crime", "patrol", "flee", "buy_food", "buy_car", "care_animal",
	"help", "communicate"]

const INPUTS := 20
const HIDDEN := 10

var w: Dictionary = {}              # habit layer: action -> weight
var w_in := PackedFloat32Array()    # HIDDEN x INPUTS
var b_h := PackedFloat32Array()     # HIDDEN
var w_out: Dictionary = {}          # action -> PackedFloat32Array(HIDDEN)
var b_out: Dictionary = {}          # action -> float
var generation := 0

var _last_h := PackedFloat32Array() # hidden activations at the last decision
var _last_action := ""
var _lr_mult := 1.0                 # intelligence-scaled learning rate

func _init() -> void:
	for a in ACTIONS:
		w[a] = Rng.randf_range(0.85, 1.15)
	_init_net()

func _init_net() -> void:
	w_in.resize(HIDDEN * INPUTS)
	for i in range(w_in.size()):
		w_in[i] = Rng.randfn(0.0, 0.35)
	b_h.resize(HIDDEN)
	for j in range(HIDDEN):
		b_h[j] = 0.0
	for a in ACTIONS:
		var row := PackedFloat32Array()
		row.resize(HIDDEN)
		for j in range(HIDDEN):
			row[j] = Rng.randfn(0.0, 0.3)
		w_out[a] = row
		b_out[a] = 0.0

static func inherit(a, b):
	var child = load("res://scripts/agents/person_brain.gd").new()
	var sigma: float = Params.get_p("nn.mutation")
	for k in ACTIONS:
		var pa: float = a.w.get(k, 1.0)
		var pb: float = b.w.get(k, 1.0)
		child.w[k] = clampf((pa if Rng.chance(0.5) else pb) + Rng.randfn(0.0, sigma), 0.3, 2.5)
	# per-gene crossover + mutation of the net (neuroevolution)
	for i in range(child.w_in.size()):
		var g: float = a.w_in[i] if Rng.chance(0.5) else b.w_in[i]
		child.w_in[i] = clampf(g + Rng.randfn(0.0, sigma), -2.5, 2.5)
	for j in range(HIDDEN):
		var gb: float = a.b_h[j] if Rng.chance(0.5) else b.b_h[j]
		child.b_h[j] = clampf(gb + Rng.randfn(0.0, sigma * 0.5), -1.5, 1.5)
	for k in ACTIONS:
		var ra: PackedFloat32Array = a.w_out.get(k, child.w_out[k])
		var rb: PackedFloat32Array = b.w_out.get(k, child.w_out[k])
		var row: PackedFloat32Array = child.w_out[k]
		for j in range(HIDDEN):
			var g2: float = ra[j] if Rng.chance(0.5) else rb[j]
			row[j] = clampf(g2 + Rng.randfn(0.0, sigma), -2.5, 2.5)
		child.b_out[k] = clampf((float(a.b_out.get(k, 0.0)) if Rng.chance(0.5)
			else float(b.b_out.get(k, 0.0))) + Rng.randfn(0.0, sigma * 0.5), -1.0, 1.0)
	child.generation = maxi(int(a.generation), int(b.generation)) + 1
	return child

func reinforce(action: String, reward: float) -> void:
	if not w.has(action):
		return
	var lr := Params.get_p("nn.learning_rate") * _lr_mult
	# habit layer
	w[action] = clampf(w[action] + lr * reward, 0.3, 2.5)
	# neural layer: credit the hidden features active at the decision
	if _last_action == action and _last_h.size() == HIDDEN:
		var row: PackedFloat32Array = w_out.get(action, PackedFloat32Array())
		if row.size() == HIDDEN:
			for j in range(HIDDEN):
				row[j] = clampf(row[j] + lr * reward * _last_h[j] * 0.5, -2.5, 2.5)
			b_out[action] = clampf(float(b_out.get(action, 0.0)) + lr * reward * 0.1, -1.0, 1.0)

# ---------------- Sensors & forward pass ----------------

func _sense(p, ctx: Dictionary) -> PackedFloat32Array:
	var x := PackedFloat32Array()
	x.resize(INPUTS)
	x[0] = clampf(p.hunger / 100.0, 0.0, 1.2)
	x[1] = clampf(p.thirst / 100.0, 0.0, 1.2)
	x[2] = clampf(p.energy / 100.0, 0.0, 1.0)
	x[3] = clampf(p.health / 100.0, 0.0, 1.0)
	x[4] = clampf(p.money / 100.0, 0.0, 1.5)
	x[5] = clampf(p.age / 90.0, 0.0, 1.2)
	x[6] = 1.0 if G.clock.is_night() else 0.0
	x[7] = clampf(ctx["danger"] / 1.5, 0.0, 1.0)
	x[8] = clampf(ctx["predators"].size() / 3.0, 0.0, 1.0)
	x[9] = clampf(ctx["people"].size() / 6.0, 0.0, 1.0)
	x[10] = 1.0 if p.home_id >= 0 else 0.0
	x[11] = 1.0 if p.job_type != "" else 0.0
	x[12] = 1.0 if p.partner_id >= 0 else 0.0
	x[13] = clampf(p.pocket_food / maxf(p.pocket_food_max(), 1.0), 0.0, 1.0)
	x[14] = clampf(p.pocket_water / maxf(p.pocket_water_max(), 1.0), 0.0, 1.0)
	x[15] = 1.0 if ctx["water"]["ok"] else 0.0
	x[16] = 1.0 if ctx["store"] != null else 0.0
	x[17] = 1.0 if G.weather.move_mult() < 0.95 else 0.0
	x[18] = 1.0 if p.sick else 0.0
	x[19] = clampf(p.crimes_committed / 5.0, 0.0, 1.0)
	return x

func _forward_hidden(x: PackedFloat32Array) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	h.resize(HIDDEN)
	for j in range(HIDDEN):
		var s: float = b_h[j]
		var base := j * INPUTS
		for i in range(INPUTS):
			s += w_in[base + i] * x[i]
		h[j] = tanh(s)
	return h

func _net_out(action: String, h: PackedFloat32Array) -> float:
	var row: PackedFloat32Array = w_out.get(action, PackedFloat32Array())
	if row.size() != HIDDEN:
		return 0.0
	var s: float = float(b_out.get(action, 0.0))
	for j in range(HIDDEN):
		s += row[j] * h[j]
	return tanh(s)

## Multiplicative modulation keeps gating intact: an action the base scores
## at zero (e.g. patrol for non-police) stays zero whatever the net says.
func _modulate(action: String, base: float, h: PackedFloat32Array, strength: float) -> float:
	if base <= 0.0 or strength <= 0.0:
		return base
	return base * clampf(1.0 + _net_out(action, h) * strength, 0.3, 1.9)

# ---------------- Decision ----------------

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
	_lr_mult = 0.5 + p.traits.get("intelligence", 0.5)

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

	# --- neural modulation: the net reshapes the utility landscape ---
	var strength := Params.get_p("nn.net_strength")
	var h := PackedFloat32Array()
	if strength > 0.0:
		h = _forward_hidden(_sense(p, ctx))
		for k in u.keys():
			u[k] = _modulate(k, u[k], h, strength)

	# --- exploration noise, individualized by curiosity ---
	var explore: float = Params.get_p("nn.explore") * (0.6 + p.traits["curiosity"] * 0.8)
	for k in u.keys():
		u[k] = maxf(u[k] + Rng.randfn(0.0, explore * 0.35), 0.0)

	var best := "wander"
	var best_u := -1.0
	for k in u.keys():
		if u[k] > best_u:
			best_u = u[k]
			best = k
	_last_h = h
	_last_action = best
	p.start_action(best, ctx)

# ---------------- Persistence ----------------

func to_dict() -> Dictionary:
	var out_ser := {}
	var bias_ser := {}
	for a in ACTIONS:
		out_ser[a] = _round_arr(w_out[a])
		bias_ser[a] = snappedf(float(b_out.get(a, 0.0)), 0.001)
	return {"w": w.duplicate(), "gen": generation, "w_in": _round_arr(w_in),
		"b_h": _round_arr(b_h), "w_out": out_ser, "b_out": bias_ser}

func _round_arr(arr: PackedFloat32Array) -> Array:
	var out: Array = []
	for v in arr:
		out.append(snappedf(v, 0.001))
	return out

func from_dict(d: Dictionary) -> void:
	# legacy saves stored the habit weights flat; new saves nest them
	var habits: Dictionary = d.get("w", d)
	for k in habits.keys():
		if w.has(k) and (habits[k] is float or habits[k] is int):
			w[k] = float(habits[k])
	generation = int(d.get("gen", 0))
	var win: Array = d.get("w_in", [])
	if win.size() == HIDDEN * INPUTS:
		for i in range(win.size()):
			w_in[i] = float(win[i])
	var bh: Array = d.get("b_h", [])
	if bh.size() == HIDDEN:
		for j in range(HIDDEN):
			b_h[j] = float(bh[j])
	var wout: Dictionary = d.get("w_out", {})
	for a in wout.keys():
		if w_out.has(a):
			var row_src: Array = wout[a]
			if row_src.size() == HIDDEN:
				var row: PackedFloat32Array = w_out[a]
				for j in range(HIDDEN):
					row[j] = float(row_src[j])
	var bout: Dictionary = d.get("b_out", {})
	for a in bout.keys():
		if b_out.has(a):
			b_out[a] = float(bout[a])

class_name Person extends Node3D
const PersonBrain = preload("res://scripts/agents/person_brain.gd")
const Vis = preload("res://scripts/core/visuals.gd")

## Person: an autonomous human agent. Owns needs, traits, skills, memory,
## relationships, language lexicon, a neural-style brain, and a full
## lifecycle from birth to death. Movement and actions are agent-driven.

const JOB_COLORS := {
	"": Color(0.85, 0.72, 0.55), "builder": Color(0.9, 0.55, 0.2),
	"farmer": Color(0.4, 0.7, 0.3), "hunter": Color(0.55, 0.4, 0.25),
	"teacher": Color(0.65, 0.45, 0.8), "doctor": Color(0.95, 0.95, 0.95),
	"police": Color(0.25, 0.4, 0.85), "guard": Color(0.4, 0.5, 0.6),
	"shop_worker": Color(0.3, 0.7, 0.65), "power_worker": Color(0.7, 0.35, 0.3),
	"president": Color(1.0, 0.9, 0.15), "politician": Color(0.9, 0.8, 0.3), "gov_worker": Color(0.75, 0.7, 0.55),
	"worker": Color(0.55, 0.6, 0.7), "animal_handler": Color(0.6, 0.65, 0.35),
}

var id := 0
var pname := ""
var sex := "m"
var age := 25.0
var lifespan := 82.0
var alive := true
var cause_of_death := ""
var death_time := -1.0
var health := 100.0
var hunger := 20.0
var thirst := 20.0
var energy := 90.0
var money := 0.0
var sick := false
var emotion := "calm"
var traits := {}            # aggression, empathy, sociability, risk, intelligence, ambition, greed, curiosity (0..1)
var skills := {}            # construction, farming, hunting, medicine, teaching, policing, crime, driving, language, trade, animal_handling (0..1)
var education := 0.0        # 0..100
var job_type := ""
var job_building := -1
var home_id := -1
var family_id := -1
var partner_id := -1
var parent_ids: Array = []
var child_ids: Array = []
var group_ids: Array = []
var relationships: Dictionary = {}   # other id -> -100..100
var memory := {"food": [], "water": [], "danger": []}
var lexicon: Dictionary = {}         # symbol -> {"m": meaning_id, "c": confidence}
var car_id := -1
var owned_animals: Array = []
var prison_until := -1.0
var crimes_committed := 0
var action := "idle"
var target_pos := Vector3.ZERO
var target_id := -1
var target_kind := ""       # "point","person","animal","building","site","resource"
var arrived := false
var brain: PersonBrain

var _decide_timer := 0.0
var _commit_time := 0.0
var _speak_timer := 0.0
var _label_timer := 0.0
var _action_time := 0.0
var _last_stage := ""
var body: MeshInstance3D
var label: Label3D
var icon: Label3D

# ---------------- Setup ----------------

func setup(pid: int, pos: Vector3, opts: Dictionary = {}) -> void:
	id = pid
	position = pos
	sex = opts.get("sex", "f" if Rng.chance(0.5) else "m")
	pname = opts.get("pname", Names.person_name(sex))
	age = float(opts.get("age", Rng.randf_range(18.0, 40.0)))
	lifespan = float(opts.get("lifespan", sample_lifespan()))
	hunger = Rng.randf_range(10.0, 45.0)   # staggered need clocks
	thirst = Rng.randf_range(10.0, 45.0)
	energy = Rng.randf_range(70.0, 100.0)
	money = float(opts.get("money", Params.get_p("eco.start_money")))
	traits = opts.get("traits", _random_traits())
	skills = opts.get("skills", {})
	for s in ["construction", "farming", "hunting", "medicine", "teaching", "policing",
			"crime", "driving", "language", "trade", "animal_handling"]:
		if not skills.has(s):
			skills[s] = Rng.randf_range(0.0, 0.15)
	brain = opts.get("brain", PersonBrain.new())
	lexicon = opts.get("lexicon", {})
	parent_ids = opts.get("parent_ids", [])
	home_id = int(opts.get("home_id", -1))
	family_id = int(opts.get("family_id", -1))
	_decide_timer = Rng.randf_range(0.0, 1.5)
	_build_visual()

static func sample_lifespan() -> float:
	# Most die 70-90, some 90-100, few 100-110, 110 is rare.
	var r := Rng.randf()
	if r < 0.72:
		return Rng.randf_range(70.0, 90.0)
	elif r < 0.94:
		return Rng.randf_range(90.0, 100.0)
	elif r < 0.995:
		return Rng.randf_range(100.0, 108.0)
	return Rng.randf_range(108.0, 110.0)

func _random_traits() -> Dictionary:
	var t := {}
	for k in ["aggression", "empathy", "sociability", "risk", "intelligence",
			"ambition", "greed", "curiosity"]:
		t[k] = clampf(Rng.randfn(0.5, 0.18), 0.0, 1.0)
	return t

func _build_visual() -> void:
	body = Vis.capsule(0.32, 1.5, JOB_COLORS[""])
	body.position.y = 0.85
	add_child(body)
	label = Vis.label(pname, 30)
	label.position = Vector3(0, 2.3, 0)
	add_child(label)
	icon = Vis.label("", 44, Color(1, 0.9, 0.3))
	icon.position = Vector3(0, 2.9, 0)
	add_child(icon)
	_apply_stage_visual()

func stage() -> String:
	if age < 3.0:
		return "baby"
	elif age < 13.0:
		return "child"
	elif age < 18.0:
		return "teen"
	elif age < 65.0:
		return "adult"
	return "elder"

func is_adult() -> bool:
	var s := stage()
	return s == "adult" or s == "elder"

func _apply_stage_visual() -> void:
	var s := stage()
	_last_stage = s
	var sc := 1.0
	match s:
		"baby": sc = 0.35
		"child": sc = 0.55
		"teen": sc = 0.8
		"elder": sc = 0.95
	body.scale = Vector3(sc, sc, sc)
	body.position.y = 0.85 * sc
	_update_color()

func _update_color() -> void:
	var c: Color = JOB_COLORS.get(job_type, JOB_COLORS[""])
	if not alive:
		c = Color(0.4, 0.4, 0.4)
	elif prison_until >= 0.0:
		c = Color(0.9, 0.6, 0.1)
	elif crimes_committed >= 3:
		c = Color(0.6, 0.15, 0.15)
	body.material_override = Vis.mat(c)

# ---------------- Lifecycle ----------------

func tick(dt: float) -> void:
	if not alive:
		return
	_needs(dt)
	_aging(dt)
	if not alive:
		return
	if prison_until >= 0.0:
		if G.clock.total_time >= prison_until:
			_release_from_prison()
		else:
			hunger = minf(hunger, 70.0)  # prisons feed inmates minimally
			thirst = minf(thirst, 70.0)
		return
	_speak_timer = maxf(_speak_timer - dt, 0.0)
	if action == "build":
		_validate_build_assignment()
	_decide_timer -= dt
	if _decide_timer <= 0.0:
		# committed actions (pursuit, fleeing, satisfying a need) run to completion —
		# constant re-deciding would leave agents commuting forever between targets
		var committed := action == "arrest" or (action == "flee" and not arrived) \
			or (action == "build" and not arrived) or action == "seek_food" or action == "seek_water"
		if committed:
			_commit_time += 1.0
			if _commit_time > 30.0:
				committed = false  # stuck too long; rethink
		if committed:
			_decide_timer = 1.0
		else:
			_decide_timer = Params.get_p("nn.decision_interval") * G.perf["ai_mult"] * Rng.randf_range(0.8, 1.2)
			G.people.decisions_made += 1
			brain.decide(self)
	_move(dt)
	_do_action(dt)
	_label_timer -= dt
	if _label_timer <= 0.0:
		_label_timer = 0.5
		_refresh_label()

func _needs(dt: float) -> void:
	var heat := 1.0 + maxf(Params.get_p("world.temperature") - 28.0, 0.0) * 0.03
	hunger = minf(hunger + Params.get_p("pop.hunger_rate") * dt, 120.0)
	var tr := Params.get_p("pop.thirst_rate") * heat
	if G.weather.is_drought():
		tr *= 1.4
	thirst = minf(thirst + tr * dt, 120.0)
	if action == "rest" or action == "idle" or action == "socialize":
		energy = minf(energy + dt * 6.0, 100.0)
	else:
		var drain := 0.3
		if action == "work" or action == "build" or action == "hunt":
			drain = 1.2
		energy = maxf(energy - drain * dt, 0.0)
	var dm := Params.get_p("pop.death_mod")
	if hunger >= 100.0:
		health -= dt * 1.2 * dm
	if thirst >= 100.0:
		health -= dt * 1.8 * dm
	if sick:
		health -= dt * 0.28 * dm * (0.35 if _near_hospital() else 1.0)
		if Rng.chance(dt * (0.015 if _near_hospital() else 0.004)):
			sick = false
			Events.add("survival", "%s recovered from sickness" % pname)
	elif Rng.chance(Params.get_p("pop.disease_chance") * dt * 0.0004 * (1.0 + Params.get_p("world.pollution"))):
		make_sick()
	if hunger < 70.0 and thirst < 70.0 and not sick and health < 100.0:
		health += dt * 1.2
	if health <= 0.0:
		var cause := "injury"
		if thirst >= 100.0:
			cause = "dehydration"
		elif hunger >= 100.0:
			cause = "starvation"
		elif sick:
			cause = "disease"
		die(cause)

func _near_hospital() -> bool:
	var h = G.buildings.nearest("hospital", position)
	return h != null and h.position.distance_to(position) < 25.0 and not h.workers.is_empty()

func _aging(dt: float) -> void:
	var yrs: float = dt / G.clock.day_length() * Params.get_p("pop.aging_speed")
	if age < 18.0:
		yrs *= Params.get_p("pop.child_growth")
	age += yrs
	if stage() != _last_stage:
		_apply_stage_visual()
		if _last_stage == "adult":
			Events.add("social", "%s became an elder" % pname)
	if age >= lifespan * Params.get_p("pop.lifespan_mod"):
		die("old_age")

func die(cause: String) -> void:
	if not alive:
		return
	alive = false
	cause_of_death = cause
	death_time = G.clock.total_time
	action = "dead"
	emotion = "dead"
	rotation.x = deg_to_rad(88)
	position.y = 0.2
	_update_color()
	icon.text = "+"
	G.people.on_death(self, cause)

func revive() -> void:
	alive = true
	cause_of_death = ""
	death_time = -1.0
	health = 60.0
	hunger = 40.0
	thirst = 40.0
	rotation.x = 0.0
	position.y = 0.0
	action = "idle"
	if age >= lifespan:
		lifespan = age + Rng.randf_range(2.0, 10.0)
	_update_color()
	Events.add("god", "%s was revived" % pname)

func heal(amount := 100.0) -> void:
	health = minf(health + amount, 100.0)
	sick = false

func make_sick() -> void:
	if sick or not alive:
		return
	sick = true
	emotion = "sick"
	Events.add("survival", "%s fell sick" % pname)

func _release_from_prison() -> void:
	prison_until = -1.0
	action = "idle"
	emotion = "calm"
	_update_color()
	Events.add("police", "%s was released from prison" % pname)

# ---------------- Perception ----------------

func perceive() -> Dictionary:
	var ctx := {"danger": 0.0, "threat_pos": Vector3.ZERO, "people": [], "needy": null,
		"prey": [], "predators": [], "sites": [], "school": null, "store": null,
		"victim": null, "loot_building": null, "police_near": false, "tameable": null,
		"food_res": {}, "water": {}}
	var others: Array = G.people.nearby(position, 14.0, id)
	ctx["people"] = others
	for o in others:
		# familiarity grows from simple co-presence
		if rel(o.id) < 60.0:
			change_rel(o.id, (0.08 + traits["sociability"] * 0.12) * Params.get_p("pop.relationship_rate"))
		# pair bonds can spark from sustained proximity, not only deliberate socializing
		if is_adult() and o.is_adult() and partner_id < 0 and o.partner_id < 0 \
				and o.sex != sex and rel(o.id) > 35.0 and Rng.chance(0.06):
			G.people.try_bond(self, o)
		if o.job_type == "police" and o.prison_until < 0.0:
			ctx["police_near"] = true
		if (o.hunger > 78.0 or o.health < 40.0) and rel(o.id) >= -10:
			ctx["needy"] = o
		var same_family: bool = family_id >= 0 and o.family_id == family_id
		if o.money > money + 30.0 and not same_family and rel(o.id) < 40:
			ctx["victim"] = o
	var near_animals: Array = G.animals.nearby(position, 18.0)
	for an in near_animals:
		if not an.alive:
			continue
		if an.is_predator():
			ctx["predators"].append(an)
			var prox: float = 1.0 - clampf(position.distance_to(an.position) / 18.0, 0.0, 1.0)
			ctx["danger"] += prox * Params.get_p("ani.predator_danger") * 0.8
			ctx["threat_pos"] = an.position
		else:
			if an.owner_id < 0:
				ctx["prey"].append(an)
				var def: Dictionary = an.def
				if def.get("tame", false) and an.domestication < 0.75:
					ctx["tameable"] = an
	# remembered danger zones
	for dpos in memory["danger"]:
		var d := position.distance_to(Vector3(dpos[0], 0, dpos[1]))
		if d < 20.0:
			ctx["danger"] += (1.0 - d / 20.0) * 0.3
	ctx["danger"] += G.crime.danger_at(position) * 0.3
	ctx["food_res"] = G.world.nearest_resource(position, 45.0)
	ctx["water"] = G.world.nearest_water(position, 60.0)
	ctx["sites"] = G.buildings.sites_needing_builders()
	ctx["school"] = G.buildings.nearest("school", position)
	ctx["store"] = G.buildings.nearest_provider("food_store", position)
	ctx["loot_building"] = ctx["store"]
	# learn locations from sight
	if not ctx["food_res"].is_empty() and position.distance_to(G.world.resource_pos(ctx["food_res"]["id"])) < 25.0:
		remember("food", G.world.resource_pos(ctx["food_res"]["id"]))
	if ctx["water"]["ok"] and ctx["water"]["dist"] < 35.0:
		remember("water", ctx["water"]["pos"])
	if ctx["danger"] > 0.5 and not ctx["predators"].is_empty():
		remember("danger", ctx["threat_pos"])
		try_speak("predator", true)
	return ctx

func rel(other_id: int) -> float:
	return float(relationships.get(other_id, 0.0))

func change_rel(other_id: int, amt: float) -> void:
	relationships[other_id] = clampf(rel(other_id) + amt, -100.0, 100.0)

func gang_influence() -> float:
	for gid in group_ids:
		var g = G.groups.get_group(gid)
		if g != null and g["type"] == "gang":
			return 1.0
	return 0.0

func remember(kind: String, pos: Vector3) -> void:
	var list: Array = memory[kind]
	for e in list:
		if Vector3(e[0], 0, e[1]).distance_to(pos) < 6.0:
			return
	list.append([pos.x, pos.z])
	var cap := int(6 + 8 * Params.get_p("nn.memory_strength"))
	while list.size() > cap:
		list.pop_front()

func forget_near(kind: String, pos: Vector3) -> void:
	var list: Array = memory[kind]
	for i in range(list.size() - 1, -1, -1):
		if Vector3(list[i][0], 0, list[i][1]).distance_to(pos) < 8.0:
			list.remove_at(i)

func recall_nearest(kind: String) -> Variant:
	var best = null
	var best_d := 1e9
	for e in memory[kind]:
		var p := Vector3(e[0], 0, e[1])
		var d := position.distance_to(p)
		if d < best_d:
			best_d = d
			best = p
	return best

# ---------------- Actions ----------------

func start_action(a: String, ctx: Dictionary) -> void:
	action = a
	arrived = false
	target_id = -1
	target_kind = "point"
	_action_time = 0.0
	_commit_time = 0.0
	match a:
		"wander":
			_set_wander_target()
		"seek_food":
			_target_food(ctx)
		"seek_water":
			_target_water(ctx)
		"rest", "go_home":
			var home = G.buildings.get_building(home_id)
			if home != null:
				_set_point(home.position)
			elif a == "go_home":
				_claim_home()
			else:
				arrived = true
		"socialize", "communicate":
			var friend = _pick_social_target(ctx)
			if friend != null:
				_set_entity("person", friend.id, friend.position)
			else:
				action = "wander"
				_set_wander_target()
		"work":
			var wb = G.buildings.get_building(job_building)
			if wb != null:
				_set_point(wb.position + Vector3(Rng.randf_range(-2, 2), 0, Rng.randf_range(-2, 2)))
			else:
				job_type = ""
				job_building = -1
				action = "seek_job"
		"seek_job":
			if not G.buildings.find_job_for(self):
				if not ctx["sites"].is_empty():
					action = "build"
					_target_site(ctx)
				else:
					action = "wander"
					_set_wander_target()
			else:
				action = "work"
				var wb2 = G.buildings.get_building(job_building)
				if wb2 != null:
					_set_point(wb2.position)
				Events.add("economy", "%s got a job as %s" % [pname, job_type])
				_update_color()
		"build":
			_target_site(ctx)
		"study":
			if ctx["school"] != null:
				_set_entity("building", ctx["school"].id, ctx["school"].position)
			else:
				action = "wander"
				_set_wander_target()
		"reproduce":
			var partner = G.people.get_person(partner_id)
			if partner != null and partner.alive:
				_set_entity("person", partner.id, partner.position)
			else:
				action = "socialize"
				var f2 = _pick_social_target(ctx)
				if f2 != null:
					_set_entity("person", f2.id, f2.position)
				else:
					_set_wander_target()
		"hunt":
			var prey = _nearest_of(ctx["prey"])
			if prey != null:
				_set_entity("animal", prey.id, prey.position)
			else:
				action = "wander"
				_set_wander_target()
		"commit_crime":
			if ctx["victim"] != null:
				_set_entity("person", ctx["victim"].id, ctx["victim"].position)
			elif ctx["loot_building"] != null:
				_set_entity("building", ctx["loot_building"].id, ctx["loot_building"].position)
			else:
				action = "wander"
				_set_wander_target()
		"patrol":
			var hot = G.crime.hot_pos()
			if hot != null and Rng.chance(0.6):
				_set_point(hot + Vector3(Rng.randf_range(-6, 6), 0, Rng.randf_range(-6, 6)))
			else:
				_set_wander_target()
		"flee":
			var away: Vector3 = position - ctx["threat_pos"]
			away.y = 0
			if away.length() < 0.5:
				away = Vector3(Rng.randf_range(-1, 1), 0, Rng.randf_range(-1, 1))
			_set_point(G.world.clamp_pos(position + away.normalized() * 22.0))
			emotion = "afraid"
			try_speak("danger", true)
		"buy_food":
			if ctx["store"] != null:
				_set_entity("building", ctx["store"].id, ctx["store"].position)
			else:
				action = "seek_food"
				_target_food(ctx)
		"buy_car":
			if ctx["store"] != null:
				_set_entity("building", ctx["store"].id, ctx["store"].position)
			else:
				arrived = true
		"care_animal":
			var target_animal = null
			if not owned_animals.is_empty():
				target_animal = G.animals.get_animal(owned_animals[0])
			if target_animal == null:
				target_animal = ctx["tameable"]
			if target_animal != null and target_animal.alive:
				_set_entity("animal", target_animal.id, target_animal.position)
			else:
				action = "wander"
				_set_wander_target()
		"help":
			if ctx["needy"] != null:
				_set_entity("person", ctx["needy"].id, ctx["needy"].position)
			else:
				action = "wander"
				_set_wander_target()
		_:
			arrived = true

func _set_point(p: Vector3) -> void:
	target_pos = G.world.clamp_pos(p)
	target_kind = "point"
	arrived = false

func _set_entity(kind: String, eid: int, pos: Vector3) -> void:
	target_kind = kind
	target_id = eid
	target_pos = pos
	arrived = false

func _set_wander_target() -> void:
	var dir := Vector3(Rng.randf_range(-1, 1), 0, Rng.randf_range(-1, 1)).normalized()
	var dist: float = Rng.randf_range(8.0, 30.0) * (0.5 + traits["curiosity"])
	_set_point(position + dir * dist)

func _target_food(ctx: Dictionary) -> void:
	# 1) home stock  2) visible resource  3) memory  4) buy  5) explore
	var home = G.buildings.get_building(home_id)
	if home != null and home.stock.get("food", 0.0) >= 1.0:
		_set_entity("building", home.id, home.position)
		return
	var target_res: Dictionary = G.world.pick_food_target(position, 70.0)
	if not target_res.is_empty():
		_set_entity("resource", target_res["id"], G.world.resource_pos(target_res["id"]))
		return
	var mem = recall_nearest("food")
	if mem != null:
		_set_point(mem)
		return
	var stocked = G.buildings.nearest_stocked_food(position)
	if stocked != null:
		_set_entity("building", stocked.id, stocked.position)
		return
	if ctx["store"] != null and money >= Params.get_p("eco.food_price"):
		action = "buy_food"
		_set_entity("building", ctx["store"].id, ctx["store"].position)
		return
	try_speak("hungry")
	_set_wander_target()

func _target_water(ctx: Dictionary) -> void:
	if ctx["water"]["ok"]:
		_set_point(ctx["water"]["pos"])
		return
	var mem = recall_nearest("water")
	if mem != null:
		_set_point(mem)
		return
	try_speak("thirsty")
	_set_wander_target()

func _target_site(ctx: Dictionary) -> void:
	if not G.buildings.can_person_build(self):
		_redirect_from_build_site()
		return
	var site = _nearest_of(ctx["sites"])
	if site != null and site.reserve_worker(id):
		_set_entity("site", site.id, site.position)
	else:
		_redirect_from_build_site()

func _validate_build_assignment() -> void:
	var site = G.buildings.get_site(target_id)
	if site == null or not G.buildings.can_person_build(self):
		if site != null:
			site.release_worker(id)
		_redirect_from_build_site()
		return
	if not site.reserve_worker(id):
		_redirect_from_build_site()

func _redirect_from_build_site() -> void:
	if target_id >= 0:
		var old_site = G.buildings.get_site(target_id)
		if old_site != null:
			old_site.release_worker(id)
	target_id = -1
	target_kind = "point"
	arrived = true
	if job_type == "builder":
		var wb = G.buildings.get_building(job_building)
		if wb != null:
			action = "work"
			_set_point(wb.position + Vector3(Rng.randf_range(-2, 2), 0, Rng.randf_range(-2, 2)))
			return
	action = "idle"

func _nearest_of(arr: Array) -> Variant:
	var best = null
	var best_d := 1e9
	for e in arr:
		var d: float = position.distance_to(e.position)
		if d < best_d:
			best_d = d
			best = e
	return best

func _pick_social_target(ctx: Dictionary) -> Variant:
	var best = null
	var best_score := -1e9
	for o in ctx["people"]:
		if not o.alive:
			continue
		var score: float = rel(o.id) + Rng.randf_range(0.0, 30.0)
		if o.family_id == family_id and family_id >= 0:
			score += 20.0
		if score > best_score:
			best_score = score
			best = o
	return best

func _claim_home() -> void:
	var b = G.buildings.find_free_home(position)
	if b != null:
		home_id = b.id
		b.residents.append(id)
		_set_point(b.position)
		Events.add("social", "%s moved into a %s" % [pname, b.def["name"]])
	else:
		arrived = true

# ---------------- Movement ----------------

func base_speed() -> float:
	var s := 3.0
	match stage():
		"baby": s = 0.6
		"child": s = 2.2
		"teen": s = 2.8
		"elder": s = 1.9
	s *= 0.6 + 0.4 * (health / 100.0)
	s *= 0.75 + 0.25 * (energy / 100.0)
	s *= G.weather.move_mult()
	s *= 0.7 + 0.3 * Params.get_p("nn.move_strength")
	if G.buildings.road_at(position):
		s *= 1.3
		if car_id >= 0:
			s *= 2.4
	return s

func _move(dt: float) -> void:
	if arrived:
		return
	# chase moving targets
	if target_kind == "person":
		var t = G.people.get_person(target_id)
		if t != null and t.alive:
			target_pos = t.position
	elif target_kind == "animal":
		var ta = G.animals.get_animal(target_id)
		if ta != null and ta.alive:
			target_pos = ta.position
	var to := target_pos - position
	to.y = 0.0
	if to.length() < 0.9:
		arrived = true
		return
	var dir := to.normalized()
	# steer around known danger when not fleeing/hunting
	if action != "flee" and action != "hunt":
		var ahead := position + dir * 6.0
		if G.world.in_zone(ahead, "predator") and not G.world.in_zone(position, "predator"):
			dir = dir.rotated(Vector3.UP, PI * 0.5)
	var step: float = base_speed() * dt
	var next := position + dir * step
	if _obstructed(next):
		# try both diagonals, then a full sidestep, then back up — never fake arrival
		var alt := position + dir.rotated(Vector3.UP, PI * 0.45) * step
		if not _obstructed(alt):
			next = alt
		else:
			alt = position + dir.rotated(Vector3.UP, -PI * 0.45) * step
			if not _obstructed(alt):
				next = alt
			else:
				var side := 1.0 if (id % 2 == 0) else -1.0
				alt = position + dir.rotated(Vector3.UP, PI * 0.5 * side) * step * 1.5
				next = alt if not _obstructed(alt) else position - dir * step
	position = G.world.clamp_pos(next)
	rotation.y = atan2(dir.x, dir.z)

func _obstructed(p: Vector3) -> bool:
	return G.buildings.blocked(p) or G.world.in_water(p)

# ---------------- Action execution ----------------

func _do_action(dt: float) -> void:
	if not arrived:
		return
	_action_time += dt
	match action:
		"seek_food":
			_act_eat(dt)
		"seek_water":
			var wchk: Dictionary = G.world.nearest_water(position, 10.0)
			if not wchk["ok"]:
				forget_near("water", target_pos)  # remembered source is gone
				action = "idle"
				return
			thirst = maxf(thirst - dt * 35.0 * G.weather.water_mult(), 0.0)
			if thirst <= 12.0:
				remember("water", position)
				try_speak("water_found")
				brain.reinforce("seek_water", 0.5)
				action = "idle"
		"rest":
			if _action_time > 4.0 and energy > 92.0:
				action = "idle"
		"work":
			_act_work(dt)
		"build":
			_act_build(dt)
		"study":
			_act_study(dt)
		"socialize":
			_act_socialize(dt)
		"communicate":
			try_speak(_context_meaning())
			action = "idle"
		"reproduce":
			_act_reproduce()
		"hunt":
			_act_hunt()
		"commit_crime":
			G.crime.resolve_crime(self)
			action = "flee"
			_set_point(G.world.clamp_pos(position + Vector3(Rng.randf_range(-15, 15), 0, Rng.randf_range(-15, 15))))
		"arrest":
			_act_arrest()
		"patrol":
			if _action_time > 3.0:
				action = "idle"
		"flee":
			emotion = "calm"
			action = "idle"
			brain.reinforce("flee", 0.3)
		"buy_food":
			if G.economy.buy_food(self):
				brain.reinforce("buy_food", 0.4)
			action = "idle"
		"buy_car":
			if G.vehicles.buy_car(self):
				brain.reinforce("buy_car", 0.5)
			action = "idle"
		"care_animal":
			_act_care_animal(dt)
		"help":
			_act_help()
		"go_home":
			action = "rest"
		_:
			if _action_time > 2.0:
				action = "idle"

func _act_eat(dt: float) -> void:
	if target_kind == "point":
		# arrived at a remembered food spot — is there still a resource here?
		var res: Dictionary = G.world.nearest_resource(position, 6.0)
		if res.is_empty():
			forget_near("food", position)
			action = "idle"
			return
		target_kind = "resource"
		target_id = res["id"]
	if target_kind == "resource":
		var got: float = G.world.take_food(target_id, dt * 18.0)
		hunger = maxf(hunger - got * 1.3, 0.0)
		if got <= 0.0:
			action = "idle"
		if hunger <= 12.0:
			remember("food", position)
			try_speak("food_found")
			brain.reinforce("seek_food", 0.5)
			action = "idle"
	elif target_kind == "building":
		var b = G.buildings.get_building(target_id)
		if b != null and b.stock.get("food", 0.0) > 0.0:
			var got2: float = minf(dt * 16.0, b.stock["food"])
			b.stock["food"] -= got2
			hunger = maxf(hunger - got2 * 1.3, 0.0)
			if hunger <= 12.0:
				brain.reinforce("seek_food", 0.5)
				action = "idle"
		else:
			action = "idle"
	else:
		action = "idle"

func _act_work(dt: float) -> void:
	var b = G.buildings.get_building(job_building)
	if b == null:
		job_type = ""
		job_building = -1
		action = "idle"
		return
	G.economy.pay_wage(self, dt)
	var skill_key := _job_skill()
	skills[skill_key] = clampf(skills.get(skill_key, 0.0) + Params.get_p("pop.skill_gain") * dt * 0.002, 0.0, 1.0)
	if energy < 15.0 or _action_time > G.clock.day_length() * 0.3:
		brain.reinforce("work", 0.2)
		action = "idle"

func _job_skill() -> String:
	match job_type:
		"farmer": return "farming"
		"doctor": return "medicine"
		"teacher": return "teaching"
		"police", "guard": return "policing"
		"builder": return "construction"
		"animal_handler": return "animal_handling"
		"shop_worker": return "trade"
		_: return "trade"

func _act_build(dt: float) -> void:
	var site = G.buildings.get_site(target_id)
	if site == null:
		action = "idle"
		return
	if not G.buildings.can_person_build(self) or not site.reserve_worker(id):
		_redirect_from_build_site()
		return
	skills["construction"] = clampf(skills.get("construction", 0.0) + Params.get_p("pop.skill_gain") * dt * 0.003, 0.0, 1.0)
	if energy < 12.0:
		site.release_worker(id)
		action = "rest"

func _act_study(dt: float) -> void:
	var school = G.buildings.get_building(target_id)
	var quality := 0.5
	if school != null and not school.workers.is_empty():
		quality = 1.2
	education = minf(education + Params.get_p("pop.education_speed") * quality * dt * 0.25, 100.0)
	skills["language"] = clampf(skills.get("language", 0.0) + dt * 0.002 * quality, 0.0, 1.0)
	if school != null and Rng.chance(dt * 0.05):
		G.language.school_teach(self, school)
	if _action_time > G.clock.day_length() * 0.25:
		action = "idle"

func _act_socialize(dt: float) -> void:
	var o = G.people.get_person(target_id)
	if o == null or not o.alive:
		action = "idle"
		return
	if position.distance_to(o.position) > 4.0:
		arrived = false
		return
	var amt := Params.get_p("pop.relationship_rate") * dt * 4.0
	change_rel(o.id, amt)
	o.change_rel(id, amt * 0.8)
	emotion = "happy"
	if _speak_timer <= 0.0 and Rng.chance(dt * Params.get_p("aud.comm_freq")):
		try_speak(_context_meaning())
	if is_adult() and o.is_adult() and partner_id < 0 and o.partner_id < 0 and o.sex != sex and rel(o.id) > 30.0:
		G.people.try_bond(self, o)
	if _action_time > 8.0:
		brain.reinforce("socialize", 0.2)
		action = "idle"

func _act_reproduce() -> void:
	var partner = G.people.get_person(partner_id)
	if partner == null or not partner.alive or position.distance_to(partner.position) > 4.0:
		action = "idle"
		return
	G.people.try_reproduce(self, partner)
	action = "idle"

func _act_hunt() -> void:
	var prey = G.animals.get_animal(target_id)
	if prey == null or not prey.alive:
		action = "idle"
		return
	if position.distance_to(prey.position) > 2.2:
		arrived = false
		return
	var hs: float = skills.get("hunting", 0.0)
	var danger: float = 0.5 if prey.is_predator() else 0.0
	var p_success := clampf(0.35 + hs * 0.55 + traits["risk"] * 0.1 - danger, 0.05, 0.95)
	if Rng.chance(p_success):
		var food: float = G.animals.hunt_kill(prey.id, self)
		hunger = maxf(hunger - minf(food, 45.0) * 1.2, 0.0)
		var surplus: float = maxf(food - 40.0, 0.0)
		if surplus > 0.0:
			G.buildings.deposit_food(position, surplus)
		skills["hunting"] = clampf(hs + 0.04, 0.0, 1.0)
		brain.reinforce("hunt", 0.6)
		try_speak("food_found")
	else:
		if prey.is_predator():
			health -= Rng.randf_range(10.0, 30.0)
			remember("danger", prey.position)
			brain.reinforce("hunt", -0.6)
			action = "flee"
			_set_point(G.world.clamp_pos(position + (position - prey.position).normalized() * 20.0))
			return
		brain.reinforce("hunt", -0.1)
	action = "idle"

func _act_arrest() -> void:
	var criminal = G.people.get_person(target_id)
	if criminal == null or not criminal.alive or criminal.prison_until >= 0.0:
		action = "idle"
		return
	if position.distance_to(criminal.position) > 2.2:
		arrived = false
		return
	G.crime.try_arrest(self, criminal)
	action = "idle"

func _act_care_animal(dt: float) -> void:
	var an = G.animals.get_animal(target_id)
	if an == null or not an.alive:
		action = "idle"
		return
	if position.distance_to(an.position) > 3.0:
		arrived = false
		return
	if an.owner_id == id:
		an.hunger = maxf(an.hunger - dt * 20.0, 0.0)
		an.loyalty = clampf(an.loyalty + dt * 0.02, 0.0, 1.0)
		if _action_time > 5.0:
			action = "idle"
	elif an.owner_id < 0 and an.def.get("tame", false):
		var rate: float = Params.get_p("ani.domestication_speed") * (0.02 + skills.get("animal_handling", 0.0) * 0.05)
		an.domestication = clampf(an.domestication + rate * dt, 0.0, 1.0)
		if an.domestication >= 0.75:
			G.animals.assign_owner(an.id, id)
			skills["animal_handling"] = clampf(skills.get("animal_handling", 0.0) + 0.05, 0.0, 1.0)
			brain.reinforce("care_animal", 0.5)
			action = "idle"
		if _action_time > 12.0:
			action = "idle"
	else:
		action = "idle"

func _act_help() -> void:
	var o = G.people.get_person(target_id)
	if o == null or not o.alive:
		action = "idle"
		return
	if position.distance_to(o.position) > 3.0:
		arrived = false
		return
	if o.hunger > 70.0 and hunger < 60.0:
		o.hunger = maxf(o.hunger - 30.0, 0.0)
		hunger += 10.0
	if o.health < 50.0 and skills.get("medicine", 0.0) > 0.1:
		o.heal(25.0 + skills["medicine"] * 40.0)
	if money > 40.0 and o.money < 5.0:
		money -= 10.0
		o.money += 10.0
	change_rel(o.id, 5.0)
	o.change_rel(id, 12.0)
	brain.reinforce("help", 0.4)
	Events.add("social", "%s helped %s" % [pname, o.pname])
	try_speak("trusted")
	action = "idle"

# ---------------- Language ----------------

func _context_meaning() -> String:
	if hunger > 70.0:
		return "hungry"
	if thirst > 70.0:
		return "thirsty"
	if health < 40.0:
		return "hurt"
	if job_type == "builder" or action == "build":
		return "need_workers"
	if not G.buildings.active_sites().is_empty():
		return "build_this"
	if job_type != "":
		return "work_here"
	return "follow_me"

func try_speak(meaning_name: String, urgent := false) -> void:
	if not alive or prison_until >= 0.0:
		return
	if _speak_timer > 0.0 and not urgent:
		return
	_speak_timer = maxf(3.0 / maxf(Params.get_p("aud.comm_freq"), 0.05), 0.5)
	G.language.speak(self, meaning_name, urgent)

func on_hear(evt: Dictionary) -> void:
	if not alive:
		return
	G.language.process_hearing(self, evt)

func react_to_meaning(meaning_name: String, evt: Dictionary) -> void:
	match meaning_name:
		"danger", "predator", "run":
			if stage() != "baby":
				remember("danger", evt["pos"])
				action = "flee"
				arrived = false
				var away: Vector3 = position - evt["pos"]
				away.y = 0
				if away.length() < 0.5:
					away = Vector3(1, 0, 0)
				_set_point(G.world.clamp_pos(position + away.normalized() * 18.0))
				emotion = "afraid"
		"food_found":
			if hunger > 55.0:
				action = "seek_food"
				_set_point(evt["pos"])
		"water_found":
			if thirst > 55.0:
				action = "seek_water"
				_set_point(evt["pos"])
		"help":
			if traits["empathy"] * Params.get_p("nn.empathy_mult") > 0.5:
				action = "help"
				var speaker = G.people.get_person(evt["speaker"])
				if speaker != null:
					_set_entity("person", speaker.id, evt["pos"])
		"need_workers", "build_this":
			if is_adult() and G.buildings.can_person_build(self) and Rng.chance(0.4):
				action = "build"
				_target_site({"sites": G.buildings.sites_needing_builders()})
			elif is_adult() and job_type == "" and not G.buildings.sites_needing_builders().is_empty():
				action = "seek_job"
		"police_warning":
			if crimes_committed > 0:
				action = "flee"
				_set_point(G.world.clamp_pos(position + (position - evt["pos"]).normalized() * 25.0))
		"come_home", "family_call":
			var member = G.people.get_person(evt["speaker"])
			if member != null and member.family_id == family_id and family_id >= 0:
				action = "go_home"
				var home = G.buildings.get_building(home_id)
				if home != null:
					_set_point(home.position)

func hear_animal(animal, kind: String) -> void:
	if not alive:
		return
	if kind == "warning" or kind == "fear" or kind == "attack":
		# Animal warning sounds are learnable danger signals
		var understand: float = 0.3 + skills.get("animal_handling", 0.0) + skills.get("language", 0.0) * 0.5
		if Rng.chance(understand):
			remember("danger", animal.position)
			if action != "flee" and position.distance_to(animal.position) < 14.0:
				G.language.stats["animal_warnings"] += 1
				react_to_meaning("danger", {"pos": animal.position, "speaker": -1})

# ---------------- Visual ----------------

func _refresh_label() -> void:
	var cam = G.cam
	if cam == null:
		return
	var d: float = cam.camera.global_position.distance_to(global_position)
	var show: bool = d < G.perf["label_dist"] or G.main.selected == self
	label.visible = show
	icon.visible = show
	if not show:
		return
	label.text = pname
	var ic := ""
	if not alive:
		ic = "+"
	elif prison_until >= 0.0:
		ic = "[P]"
	elif emotion == "afraid" or action == "flee":
		ic = "!"
	elif sick:
		ic = "+"
	elif hunger > 80.0:
		ic = "H"
	elif thirst > 80.0:
		ic = "W"
	elif action == "build":
		ic = "B"
	elif action == "work":
		ic = "$"
	elif action == "rest":
		ic = "Z"
	icon.text = ic

# ---------------- Persistence ----------------

func serialize() -> Dictionary:
	return {
		"id": id, "pname": pname, "sex": sex, "age": age, "lifespan": lifespan,
		"alive": alive, "cause_of_death": cause_of_death, "health": health,
		"hunger": hunger, "thirst": thirst, "energy": energy, "money": money,
		"sick": sick, "traits": traits, "skills": skills, "education": education,
		"job_type": job_type, "job_building": job_building, "home_id": home_id,
		"family_id": family_id, "partner_id": partner_id, "parent_ids": parent_ids,
		"child_ids": child_ids, "group_ids": group_ids, "relationships": _rel_ser(),
		"memory": memory, "lexicon": lexicon, "car_id": car_id,
		"owned_animals": owned_animals, "prison_until": prison_until,
		"crimes": crimes_committed, "x": position.x, "z": position.z,
		"brain": brain.to_dict(),
	}

static func _int_array(arr: Array) -> Array:
	# JSON round-trips ints as floats; normalize id lists back to ints
	var out: Array = []
	for v in arr:
		out.append(int(v))
	return out

func _rel_ser() -> Dictionary:
	var out := {}
	for k in relationships.keys():
		out[str(k)] = relationships[k]
	return out

func deserialize(d: Dictionary) -> void:
	id = int(d["id"])
	pname = str(d["pname"])
	sex = str(d["sex"])
	age = float(d["age"])
	lifespan = float(d["lifespan"])
	alive = bool(d["alive"])
	cause_of_death = str(d.get("cause_of_death", ""))
	health = float(d["health"])
	hunger = float(d["hunger"])
	thirst = float(d["thirst"])
	energy = float(d["energy"])
	money = float(d["money"])
	sick = bool(d["sick"])
	traits = d["traits"]
	skills = d["skills"]
	education = float(d["education"])
	job_type = str(d["job_type"])
	job_building = int(d["job_building"])
	home_id = int(d["home_id"])
	family_id = int(d["family_id"])
	partner_id = int(d["partner_id"])
	parent_ids = _int_array(d.get("parent_ids", []))
	child_ids = _int_array(d.get("child_ids", []))
	group_ids = _int_array(d.get("group_ids", []))
	relationships = {}
	for k in d.get("relationships", {}).keys():
		relationships[int(k)] = float(d["relationships"][k])
	memory = d.get("memory", {"food": [], "water": [], "danger": []})
	lexicon = d.get("lexicon", {})
	car_id = int(d.get("car_id", -1))
	owned_animals = _int_array(d.get("owned_animals", []))
	prison_until = float(d.get("prison_until", -1.0))
	crimes_committed = int(d.get("crimes", 0))
	position = Vector3(float(d["x"]), 0, float(d["z"]))
	brain = PersonBrain.new()
	brain.from_dict(d.get("brain", {}))
	if not alive:
		rotation.x = deg_to_rad(88)
		position.y = 0.2
	_apply_stage_visual()
	_update_color()
	_refresh_label()

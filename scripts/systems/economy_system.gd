class_name EconomySystem extends Node
## EconomySystem: wages, prices with market randomness, taxes, treasury,
## food purchases, and society-wide wealth statistics.

const WAGES := {
	"builder": 10.0, "farmer": 12.0, "hunter": 10.0, "teacher": 14.0,
	"doctor": 18.0, "police": 14.0, "guard": 12.0, "shop_worker": 10.0,
	"power_worker": 14.0, "politician": 20.0, "gov_worker": 12.0,
	"president": 28.0, "worker": 11.0, "driver": 11.0, "animal_handler": 11.0,
}

var treasury := 0.0
var tax_collected := 0.0
var public_debt := 0.0
var debt_issued := 0.0
var _jitter: Dictionary = {}   # price key -> daily multiplier

func price(kind: String) -> float:
	var base := 4.0
	match kind:
		"food": base = Params.get_p("eco.food_price")
		"car": base = Params.get_p("eco.car_price")
		"house": base = Params.get_p("eco.house_price")
		"animal": base = Params.get_p("eco.animal_price")
		"resource": base = Params.get_p("eco.resource_price")
	var j: float = _jitter.get(kind, 1.0)
	return base * j * Params.get_p("world.econ_difficulty")

func day_tick() -> void:
	var r := Params.get_p("eco.market_rand")
	for k in ["food", "car", "house", "animal", "resource"]:
		_jitter[k] = clampf(1.0 + Rng.randfn(0.0, r * 0.3), 0.5, 2.0)
	_service_debt()

func pay_wage(p, dt: float) -> void:
	var wage_day: float = WAGES.get(p.job_type, 8.0) * Params.get_p("eco.wage_mult")
	# inequality skews earnings toward ambition/greed
	wage_day *= 1.0 + (p.traits["ambition"] - 0.5) * (Params.get_p("eco.inequality") - 1.0) * 0.6
	var gross: float = wage_day * dt / G.clock.day_length() * 3.0  # ~3 workday blocks per day
	var tax: float = gross * Params.get_p("eco.tax_rate")
	p.money += gross - tax
	treasury += tax
	tax_collected += tax

func buy_food(p) -> bool:
	var b = G.buildings.get_building(p.target_id)
	if b == null or b.def.get("provides", "") != "food_store":
		b = G.buildings.nearest_provider("food_store", p.position)
	if b == null or b.stock.get("food", 0.0) < 1.0:
		return false
	var cost := price("food")
	if p.money < cost:
		return false
	p.money -= cost
	absorb(cost * 0.4)
	b.stock["food"] -= 1.0
	p.hunger = maxf(p.hunger - 38.0, 0.0)
	return true

func absorb(amount: float) -> void:
	# a share of every purchase flows back to public funds
	treasury += amount * 0.3

func spend(amount: float) -> bool:
	if treasury < amount:
		return false
	treasury -= amount
	return true

func finance_public_project(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	if treasury >= amount:
		treasury -= amount
		return 0.0
	var issued: float = amount - treasury
	treasury = 0.0
	public_debt += issued
	debt_issued += issued
	return issued

func _service_debt() -> void:
	if public_debt <= 0.0 or treasury <= 0.0:
		return
	var payment: float = minf(public_debt, treasury * 0.25)
	treasury -= payment
	public_debt -= payment

func wealth_stats() -> Dictionary:
	var total := 0.0
	var richest = null
	var poorest = null
	var employed := 0
	var adults := 0
	var poverty := 0
	var jobs := {}
	for p in G.people.alive_list():
		total += p.money
		if richest == null or p.money > richest.money:
			richest = p
		if poorest == null or p.money < poorest.money:
			poorest = p
		if p.is_adult() and p.stage() != "elder":
			adults += 1
			if p.job_type != "":
				employed += 1
				jobs[p.job_type] = int(jobs.get(p.job_type, 0)) + 1
		if p.money < 5.0:
			poverty += 1
	var n: int = maxi(G.people.alive_count(), 1)
	return {
		"total": total + treasury, "avg": total / n,
		"richest": ("%s (%.0f)" % [richest.pname, richest.money]) if richest != null else "--",
		"poorest": ("%s (%.0f)" % [poorest.pname, poorest.money]) if poorest != null else "--",
		"unemployment": (1.0 - float(employed) / maxf(adults, 1.0)) * 100.0,
		"poverty": poverty, "jobs": jobs, "treasury": treasury,
		"tax_collected": tax_collected, "public_debt": public_debt,
		"debt_issued": debt_issued,
	}

func to_dict() -> Dictionary:
	return {"treasury": treasury, "tax_collected": tax_collected,
		"public_debt": public_debt, "debt_issued": debt_issued, "jitter": _jitter}

func from_dict(d: Dictionary) -> void:
	treasury = float(d.get("treasury", 0.0))
	tax_collected = float(d.get("tax_collected", 0.0))
	public_debt = float(d.get("public_debt", 0.0))
	debt_issued = float(d.get("debt_issued", 0.0))
	_jitter = d.get("jitter", {})

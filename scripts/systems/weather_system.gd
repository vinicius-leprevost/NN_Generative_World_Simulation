class_name WeatherSystem extends Node
## WeatherSystem: weather states with god control, automatic transitions,
## disasters (drought/flood), and effect multipliers consumed by other systems.

const STATES := ["clear", "rain", "storm", "drought", "flood"]

var state := "clear"
var timer := 120.0   # sim seconds remaining in current state

func tick(dt: float) -> void:
	timer -= dt
	if timer <= 0.0:
		_auto_pick()

func _auto_pick() -> void:
	if state != "clear":
		set_weather("clear", Rng.randf_range(0.8, 2.5))
		return
	var r := Rng.randf()
	var dis := Params.get_p("world.disaster_freq") * 0.06
	var storm := Params.get_p("world.storm_freq") * 0.15
	var rain := Params.get_p("world.rain_freq") * 0.3
	if r < dis:
		set_weather("drought" if Rng.chance(0.6) else "flood", Rng.randf_range(1.5, 3.0))
	elif r < dis + storm:
		set_weather("storm", Rng.randf_range(0.2, 0.6))
	elif r < dis + storm + rain:
		set_weather("rain", Rng.randf_range(0.3, 1.0))
	else:
		set_weather("clear", Rng.randf_range(0.8, 2.5))

func set_weather(s: String, duration_days := 1.0) -> void:
	if not STATES.has(s):
		return
	var changed := s != state
	state = s
	timer = duration_days * Params.get_p("sim.day_length")
	if changed:
		Events.add("weather", "Weather changed to %s" % s)
		if G.world != null:
			G.world.apply_weather_visuals(s)

func start_disaster(kind: String) -> void:
	set_weather(kind, 3.0)
	Events.add("god", "Disaster started: %s" % kind)

func stop_disaster() -> void:
	if state == "drought" or state == "flood" or state == "storm":
		Events.add("god", "Disaster stopped: %s" % state)
		set_weather("clear", 1.5)

func move_mult() -> float:
	match state:
		"rain": return 0.9
		"storm": return 0.7
		"flood": return 0.6
		_: return 1.0

func build_mult() -> float:
	match state:
		"rain": return 0.8
		"storm": return 0.45
		"flood": return 0.4
		_: return 1.0

func farm_mult() -> float:
	match state:
		"rain": return 1.25
		"drought": return 0.3
		"flood": return 0.5
		_: return 1.0

func water_mult() -> float:
	match state:
		"drought": return 0.35
		"rain": return 1.3
		"flood": return 1.8
		_: return 1.0

func is_drought() -> bool:
	return state == "drought"

func to_dict() -> Dictionary:
	return {"state": state, "timer": timer}

func from_dict(d: Dictionary) -> void:
	state = str(d.get("state", "clear"))
	timer = float(d.get("timer", 120.0))
	if G.world != null:
		G.world.apply_weather_visuals(state)

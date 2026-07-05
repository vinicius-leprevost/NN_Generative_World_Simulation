class_name TimeSystem extends Node
## TimeSystem: simulation clock. Converts real delta into sim time based on
## speed/pause state, tracks hour/day/year, supports single-stepping.

signal day_passed(day: int)
signal year_passed(year: int)

const DAYS_PER_YEAR := 60

var total_time := 0.0    # accumulated sim seconds
var day := 1
var year := 1
var hour := 8.0          # 0..24
var paused := false
var _step := false

func speed() -> float:
	return Params.get_p("sim.speed")

func day_length() -> float:
	return maxf(Params.get_p("sim.day_length"), 10.0)

func request_step() -> void:
	_step = true

func advance(delta: float) -> float:
	var dt := 0.0
	if paused:
		if _step:
			dt = 0.1
			_step = false
	else:
		dt = minf(delta * speed(), 2.0)  # clamp to avoid hitch spirals
	if dt <= 0.0:
		return 0.0
	total_time += dt
	hour += dt / day_length() * 24.0
	while hour >= 24.0:
		hour -= 24.0
		day += 1
		day_passed.emit(day)
		if day % DAYS_PER_YEAR == 0:
			year += 1
			year_passed.emit(year)
	return dt

func is_night() -> bool:
	return hour < 6.0 or hour >= 20.0

func set_hour(h: float) -> void:
	hour = clampf(h, 0.0, 23.99)

func time_string() -> String:
	return "Year %d · Day %d · %02d:%02d" % [year, day, int(hour), int(fmod(hour, 1.0) * 60.0)]

func to_dict() -> Dictionary:
	return {"total_time": total_time, "day": day, "year": year, "hour": hour, "paused": paused}

func from_dict(d: Dictionary) -> void:
	total_time = float(d.get("total_time", 0.0))
	day = int(d.get("day", 1))
	year = int(d.get("year", 1))
	hour = float(d.get("hour", 8.0))
	paused = bool(d.get("paused", false))

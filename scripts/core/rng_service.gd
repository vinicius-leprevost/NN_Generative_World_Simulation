extends Node
## Rng: single seeded random source for the whole simulation.
## Seed + state persist in saves so a loaded world continues deterministically.

var rng := RandomNumberGenerator.new()
var world_seed: int = 0

func _ready() -> void:
	randomize_seed()

func randomize_seed() -> void:
	world_seed = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	rng.seed = world_seed

func set_world_seed(s: int) -> void:
	world_seed = s
	rng.seed = s

func randf() -> float:
	return rng.randf()

func randf_range(a: float, b: float) -> float:
	return rng.randf_range(a, b)

func randi_range(a: int, b: int) -> int:
	return rng.randi_range(a, b)

func randfn(mean: float, dev: float) -> float:
	return rng.randfn(mean, dev)

func chance(p: float) -> bool:
	return rng.randf() < p

func pick(arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[rng.randi_range(0, arr.size() - 1)]

func to_dict() -> Dictionary:
	# state is a 64-bit int; store as string so JSON round-trips it exactly
	return {"seed": world_seed, "state": str(rng.state)}

func from_dict(d: Dictionary) -> void:
	world_seed = int(d.get("seed", 0))
	rng.seed = world_seed
	var s: String = str(d.get("state", "0"))
	rng.state = s.to_int()

class_name SpeciesDB
## SpeciesDB: static definitions for every animal species.
## danger: predator species. produces: resource the animal yields when
## domesticated and fed. food: food units when hunted/slaughtered.

const DEFS := {
	"chicken": {"danger": false, "size": Vector3(0.35, 0.35, 0.45), "color": Color(0.95, 0.93, 0.85),
		"speed": 1.6, "max_age": 8.0, "food": 6.0, "produces": "eggs", "prod_days": 1.0,
		"herd": false, "pack": false, "tame": true, "pitch": 3.2, "aggr": 0.05},
	"cow": {"danger": false, "size": Vector3(1.3, 1.2, 2.2), "color": Color(0.85, 0.8, 0.72),
		"speed": 1.5, "max_age": 20.0, "food": 60.0, "produces": "milk", "prod_days": 1.0,
		"herd": true, "pack": false, "tame": true, "pitch": 0.6, "aggr": 0.1},
	"sheep": {"danger": false, "size": Vector3(0.8, 0.8, 1.3), "color": Color(0.92, 0.9, 0.88),
		"speed": 1.8, "max_age": 12.0, "food": 25.0, "produces": "", "prod_days": 0.0,
		"herd": true, "pack": false, "tame": true, "pitch": 1.6, "aggr": 0.05},
	"goat": {"danger": false, "size": Vector3(0.7, 0.85, 1.2), "color": Color(0.72, 0.68, 0.6),
		"speed": 2.4, "max_age": 14.0, "food": 22.0, "produces": "milk", "prod_days": 1.5,
		"herd": true, "pack": false, "tame": true, "pitch": 1.8, "aggr": 0.15},
	"horse": {"danger": false, "size": Vector3(1.0, 1.7, 2.4), "color": Color(0.55, 0.4, 0.28),
		"speed": 6.0, "max_age": 28.0, "food": 40.0, "produces": "", "prod_days": 0.0,
		"herd": true, "pack": false, "tame": true, "pitch": 1.0, "aggr": 0.1},
	"dog": {"danger": false, "size": Vector3(0.5, 0.6, 1.0), "color": Color(0.75, 0.6, 0.4),
		"speed": 5.0, "max_age": 14.0, "food": 8.0, "produces": "", "prod_days": 0.0,
		"herd": false, "pack": true, "tame": true, "pitch": 2.2, "aggr": 0.25, "guard": true},
	"deer": {"danger": false, "size": Vector3(0.8, 1.2, 1.6), "color": Color(0.72, 0.55, 0.38),
		"speed": 5.5, "max_age": 15.0, "food": 30.0, "produces": "", "prod_days": 0.0,
		"herd": true, "pack": false, "tame": false, "pitch": 1.9, "aggr": 0.0},
	"wolf": {"danger": true, "size": Vector3(0.6, 0.8, 1.4), "color": Color(0.4, 0.4, 0.44),
		"speed": 5.2, "max_age": 13.0, "food": 15.0, "produces": "", "prod_days": 0.0,
		"herd": false, "pack": true, "tame": false, "pitch": 1.3, "aggr": 0.6},
	"bear": {"danger": true, "size": Vector3(1.2, 1.4, 2.2), "color": Color(0.35, 0.25, 0.18),
		"speed": 4.2, "max_age": 25.0, "food": 45.0, "produces": "", "prod_days": 0.0,
		"herd": false, "pack": false, "tame": false, "pitch": 0.5, "aggr": 0.7},
	"tiger": {"danger": true, "size": Vector3(0.8, 1.0, 2.0), "color": Color(0.85, 0.5, 0.15),
		"speed": 5.6, "max_age": 18.0, "food": 40.0, "produces": "", "prod_days": 0.0,
		"herd": false, "pack": false, "tame": false, "pitch": 0.8, "aggr": 0.8},
}

static func get_def(species: String) -> Dictionary:
	return DEFS.get(species, DEFS["deer"])

static func species_list() -> Array:
	return DEFS.keys()

static func helpful_list() -> Array:
	var out: Array = []
	for s in DEFS.keys():
		if not DEFS[s]["danger"]:
			out.append(s)
	return out

static func predator_list() -> Array:
	var out: Array = []
	for s in DEFS.keys():
		if DEFS[s]["danger"]:
			out.append(s)
	return out
